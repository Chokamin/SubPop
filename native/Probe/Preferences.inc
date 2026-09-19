// Native sheets attached to the existing FCP panel.
- (NSArray *)effectiveVocabulary {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:@"vocabularyEnabled"] && ![defaults boolForKey:@"vocabularyEnabled"]) return @[];
    return [defaults arrayForKey:@"vocabularyTerms"] ?: @[];
}
- (NSArray *)parseVocabulary:(NSString *)text {
    NSArray *parts=[text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\n\r,，;；、"]];
    NSMutableOrderedSet *terms=[NSMutableOrderedSet new];NSUInteger total=0;
    for (NSString *part in parts) {
        NSString *word=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if (!word.length || [terms containsObject:word]) continue;
        if (word.length>64 || [word rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
        total+=word.length;[terms addObject:word];
    }
    return terms.count<=100 && total<=2000 ? terms.array : nil;
}
- (void)showVocabulary:(id)sender {
    if (self.requestID) return;
    NSAlert *alert=[NSAlert new];alert.messageText=@"词库";
    alert.informativeText=@"填写人名、品牌和专业词，每行一个，也可以用逗号分隔。\n辅助识别，并统一词条的大小写、空格和等值数字写法；修改在下一次识别生效。";
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,480,238)];
    NSButton *enabled=[NSButton checkboxWithTitle:@"识别时使用词库" target:nil action:nil];enabled.frame=NSMakeRect(0,208,480,24);
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    enabled.state=![defaults objectForKey:@"vocabularyEnabled"] || [defaults boolForKey:@"vocabularyEnabled"] ? NSControlStateValueOn : NSControlStateValueOff;[view addSubview:enabled];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,34,480,164)];scroll.hasVerticalScroller=YES;scroll.borderType=NSNoBorder;scroll.wantsLayer=YES;scroll.layer.cornerRadius=10;scroll.layer.masksToBounds=YES;
    NSTextView *editor=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,460,164)];editor.richText=NO;editor.backgroundColor=[NSColor colorWithCalibratedWhite:.09 alpha:1];editor.font=[NSFont systemFontOfSize:14];editor.textContainerInset=NSMakeSize(10,10);editor.string=self.vocabularyDraft ?: ([[defaults arrayForKey:@"vocabularyTerms"] componentsJoinedByString:@"\n"] ?: @"");scroll.documentView=editor;[view addSubview:scroll];
    NSTextField *limit=[self label:@"最多 100 个词 · 合计 2000 字 · 保存在本机" size:12 weight:NSFontWeightRegular];limit.frame=NSMakeRect(0,0,480,24);limit.textColor=NSColor.secondaryLabelColor;[view addSubview:limit];
    alert.accessoryView=view;[alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result!=NSAlertFirstButtonReturn) {self.vocabularyDraft=nil;return;}
        NSArray *terms=[self parseVocabulary:editor.string];
        if (!terms) { self.vocabularyDraft=editor.string;NSAlert *error=[NSAlert new];error.messageText=@"词库未保存";error.informativeText=@"最多100个词、合计2000字，每个词最多64字，不能包含控制字符。";[error beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {[self showVocabulary:nil];}];return; }
        self.vocabularyDraft=nil;[defaults setObject:terms forKey:@"vocabularyTerms"];[defaults setBool:enabled.state==NSControlStateValueOn forKey:@"vocabularyEnabled"];[self updateInterface];
    }];
}
- (NSDictionary *)modelTaskState {
    if (!self.modelRequestID) self.modelRequestID=[NSUserDefaults.standardUserDefaults stringForKey:@"modelRequestID"];
    if (self.modelRequestID && self.bridgeURL) return [self readJSON:[[self.bridgeURL URLByAppendingPathComponent:self.modelRequestID] URLByAppendingPathComponent:@"response.json"]] ?: @{@"status":@"queued",@"stage":@"queued"};
    return [self readJSON:[self.bridgeURL URLByAppendingPathComponent:@"service.json"]][@"modelTask"] ?: @{};
}
- (BOOL)modelOperationBusy { NSString *status=[self modelTaskState][@"status"];return [status isEqual:@"queued"] || [status isEqual:@"running"]; }
- (void)showModels:(id)sender {
    if (self.modelAlert) return;
    self.modelAlert=[NSAlert new];self.modelAlert.messageText=@"本机模型";
    self.modelAlert.informativeText=@"Qwen 首次下载含共用对齐模型；其他模型自带时间对齐。\n国内镜像为第三方 HF-Mirror · 所有来源均做 SHA-256 校验。";
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,520,140+self.modelCatalog.count*100)];self.modelRows=[NSMutableDictionary new];
    self.downloadSourcePicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,view.bounds.size.height-34,520,28) pullsDown:NO];
    [self.downloadSourcePicker addItemsWithTitles:@[@"下载源：国内镜像优先（失败后尝试官方）",@"下载源：仅 Hugging Face 官方"]];
    [self.downloadSourcePicker selectItemAtIndex:[[NSUserDefaults.standardUserDefaults stringForKey:@"downloadSource"] isEqual:@"official"] ? 1 : 0];
    self.downloadSourcePicker.target=self;self.downloadSourcePicker.action=@selector(downloadSourceChanged:);[view addSubview:self.downloadSourcePicker];
    NSUInteger index=0;
    for (NSDictionary *spec in self.modelCatalog) {
        CGFloat y=104+(self.modelCatalog.count-1-index)*100;
        NSView *card=[[NSView alloc] initWithFrame:NSMakeRect(0,y-3,520,92)];card.wantsLayer=YES;card.layer.cornerRadius=12;card.layer.backgroundColor=[NSColor colorWithCalibratedWhite:.105 alpha:1].CGColor;card.layer.borderColor=[NSColor colorWithCalibratedWhite:1 alpha:.065].CGColor;card.layer.borderWidth=1;[view addSubview:card];
        NSTextField *name=[self label:spec[@"name"] size:16 weight:NSFontWeightSemibold];name.frame=NSMakeRect(14,y+54,330,26);[view addSubview:name];
        NSTextField *detail=[self label:spec[@"description"] size:12 weight:NSFontWeightRegular];detail.frame=NSMakeRect(14,y+28,330,24);detail.textColor=NSColor.secondaryLabelColor;[view addSubview:detail];
        NSTextField *status=[self label:@"检查模型…" size:12 weight:NSFontWeightMedium];status.frame=NSMakeRect(14,y+3,330,22);[view addSubview:status];
        NSButton *action=[NSButton buttonWithTitle:@"下载" target:self action:@selector(modelAction:)];action.identifier=spec[@"id"];action.frame=NSMakeRect(358,y+41,145,30);action.bezelStyle=NSBezelStyleRounded;[view addSubview:action];
        NSButton *remove=[NSButton buttonWithTitle:@"移除模型" target:self action:@selector(removeModel:)];remove.identifier=spec[@"id"];remove.frame=NSMakeRect(358,y+6,145,28);remove.bordered=NO;[view addSubview:remove];
        self.modelRows[spec[@"id"]]=@{@"status":status,@"action":action,@"remove":remove};index++;
    }
    self.downloadProgress=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0,66,520,8)];self.downloadProgress.indeterminate=NO;self.downloadProgress.minValue=0;self.downloadProgress.maxValue=1;[view addSubview:self.downloadProgress];
    self.downloadSpinner=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0,31,16,16)];self.downloadSpinner.style=NSProgressIndicatorStyleSpinning;self.downloadSpinner.displayedWhenStopped=NO;[view addSubview:self.downloadSpinner];
    self.downloadLabel=[self label:@"模型准备好后，点击“使用”即可切换。" size:12 weight:NSFontWeightRegular];self.downloadLabel.frame=NSMakeRect(24,3,390,51);[view addSubview:self.downloadLabel];
    self.downloadCancel=[NSButton buttonWithTitle:@"暂停下载" target:self action:@selector(cancelModelDownload:)];self.downloadCancel.frame=NSMakeRect(420,22,100,30);self.downloadCancel.bezelStyle=NSBezelStyleRounded;[view addSubview:self.downloadCancel];
    self.modelAlert.accessoryView=view;[self.modelAlert addButtonWithTitle:@"完成"];[self updateModelManager];
    [self.modelAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {self.modelAlert=nil;self.modelRows=nil;self.downloadProgress=nil;self.downloadSpinner=nil;self.downloadLabel=nil;self.downloadCancel=nil;}];
}
- (void)updateModelManager {
    if (!self.modelAlert) return;
    NSDictionary *service=[self readJSON:[self.bridgeURL URLByAppendingPathComponent:@"service.json"]];NSDictionary *task=[self modelTaskState];BOOL busy=[self modelOperationBusy];
    for (NSDictionary *spec in self.modelCatalog) {
        NSDictionary *available=nil;for (NSDictionary *model in service[@"models"]) if ([model[@"id"] isEqual:spec[@"id"]]) available=model;
        NSDictionary *row=self.modelRows[spec[@"id"]];BOOL installed=[available[@"installed"] boolValue];BOOL selected=[self.selectedModelID isEqual:spec[@"id"]];
        unsigned long long bytes=0;for (NSNumber *size in [spec[@"files"] allValues]) bytes+=size.unsignedLongLongValue;
        NSTextField *status=row[@"status"];status.stringValue=[NSString stringWithFormat:@"%@ · %.2f GB",installed ? @"✓ 已安装" : @"需要下载或修复",bytes/1e9];status.textColor=installed ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
        NSButton *action=row[@"action"];action.title=installed ? (selected ? @"正在使用" : @"使用此模型") : @"下载模型";action.enabled=[self workerAvailable] && !busy && !self.requestID && !(installed && selected);
        NSButton *remove=row[@"remove"];remove.hidden=![available[@"hasFiles"] boolValue];remove.enabled=!busy && !self.requestID && [self workerAvailable];
    }
    NSString *status=task[@"status"],*stage=task[@"stage"];
    BOOL cancelling=self.modelRequestID && [[NSFileManager defaultManager] fileExistsAtPath:[[[self.bridgeURL URLByAppendingPathComponent:self.modelRequestID] URLByAppendingPathComponent:@"cancel.json"] path]];
    self.downloadSourcePicker.enabled=!busy;
    self.downloadCancel.hidden=!busy;self.downloadCancel.enabled=busy && !cancelling;self.downloadProgress.hidden=!task.count;
    double value=[task[@"progress"] doubleValue];
    if (!busy || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) self.downloadProgress.doubleValue=value;
    else [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {context.duration=0.2;self.downloadProgress.animator.doubleValue=value;} completionHandler:nil];
    self.downloadProgress.hidden=!busy;
    if (busy) {
        [self.downloadSpinner startAnimation:nil];
        if (cancelling) self.downloadLabel.stringValue=@"正在暂停下载…\n已经下载的部分会保留。";
        else if ([stage isEqual:@"downloading"]) self.downloadLabel.stringValue=[NSString stringWithFormat:@"%@ · %.0f%%\n%.2f / %.2f GB · %.1f MB/s",task[@"source"] ?: @"正在下载",value*100,[task[@"completedBytes"] doubleValue]/1e9,[task[@"totalBytes"] doubleValue]/1e9,[task[@"bytesPerSecond"] doubleValue]/1e6];
        else self.downloadLabel.stringValue=[stage isEqual:@"checking"] ? @"正在校验模型文件…\n校验完成后才会标记为可用。" : @"正在准备下载…\n可以关闭此面板，下载会在后台继续。";
    } else {
        [self.downloadSpinner stopAnimation:nil];
        if ([status isEqual:@"ready"]) self.downloadLabel.stringValue=[task[@"operation"] isEqual:@"remove"] ? @"模型已移除，共用时间对齐模型已保留。" : @"✓ 模型已准备好，可以开始识别。";
        else if ([status isEqual:@"failed"] || [status isEqual:@"cancelled"]) self.downloadLabel.stringValue=[NSString stringWithFormat:@"%@\n点击“下载模型”可重试，已下载部分会保留。",task[@"error"] ?: @"下载未完成"];
    }
}
- (void)downloadSourceChanged:(id)sender {
    [NSUserDefaults.standardUserDefaults setObject:self.downloadSourcePicker.indexOfSelectedItem==1 ? @"official" : @"auto" forKey:@"downloadSource"];
}
- (void)submitModelOperation:(NSString *)operation model:(NSString *)modelID {
    if (self.requestID || [self modelOperationBusy] || ![self workerAvailable]) return;
    NSString *request=NSUUID.UUID.UUIDString.lowercaseString;NSURL *directory=[self.bridgeURL URLByAppendingPathComponent:request];NSError *error=nil;
    BOOL ok=[[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:&error];
    NSDictionary *data=@{@"requestID":request,@"kind":@"model",@"operation":operation,@"modelID":modelID,@"downloadSource":[NSUserDefaults.standardUserDefaults stringForKey:@"downloadSource"] ?: @"auto"};
    if (ok) ok=[[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"request.json"] options:NSDataWritingAtomic error:&error];
    if (!ok) {self.downloadLabel.stringValue=error.localizedDescription ?: @"无法创建下载任务";return;}
    self.modelRequestID=request;[NSUserDefaults.standardUserDefaults setObject:request forKey:@"modelRequestID"];[self updateInterface];
}
- (void)modelAction:(NSButton *)sender {
    NSDictionary *service=[self readJSON:[self.bridgeURL URLByAppendingPathComponent:@"service.json"]];BOOL installed=NO;
    for (NSDictionary *model in service[@"models"]) if ([model[@"id"] isEqual:sender.identifier]) installed=[model[@"installed"] boolValue];
    if (!installed) {[self submitModelOperation:@"install" model:sender.identifier];return;}
    if (self.requestID || [self modelOperationBusy]) return;
    for (NSMenuItem *item in self.modelPicker.itemArray) if ([item.representedObject isEqual:sender.identifier]) [self.modelPicker selectItem:item];
    [self modelChanged:self.modelPicker];
}
- (void)removeModel:(NSButton *)sender {
    NSAlert *alert=[NSAlert new];alert.messageText=@"移除此识别模型？";alert.informativeText=@"之后可重新下载。共用时间对齐模型会保留，字幕草稿不受影响。";[alert addButtonWithTitle:@"移除"];[alert addButtonWithTitle:@"取消"];
    NSString *model=sender.identifier;
    [alert beginSheetModalForWindow:self.modelAlert.window completionHandler:^(NSModalResponse result) {if (result==NSAlertFirstButtonReturn) [self submitModelOperation:@"remove" model:model];}];
}
- (void)cancelModelDownload:(id)sender {
    if (!self.modelRequestID) return;
    [@"{}" writeToURL:[[self.bridgeURL URLByAppendingPathComponent:self.modelRequestID] URLByAppendingPathComponent:@"cancel.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];self.downloadCancel.enabled=NO;self.downloadLabel.stringValue=@"正在暂停下载…";
}
