// Optional, project-scoped reference text. Processing stays in the local worker.
- (NSString *)validatedReferenceText:(NSString *)text {
    if (![text isKindOfClass:NSString.class] || text.length>20000) return nil;
    NSMutableCharacterSet *invalid=NSCharacterSet.controlCharacterSet.mutableCopy;
    [invalid removeCharactersInString:@"\n\r\t"];
    if ([text rangeOfCharacterFromSet:invalid].location!=NSNotFound) return nil;
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
- (NSDictionary *)referenceSettings {
    if (!self.dropUID.length) return @{};
    return [NSUserDefaults.standardUserDefaults dictionaryForKey:@"referenceScripts"][self.dropUID] ?: @{};
}
- (NSString *)effectiveReferenceScript {
    NSDictionary *settings=[self referenceSettings];
    return [settings[@"enabled"] boolValue] ? ([self validatedReferenceText:settings[@"text"]] ?: @"") : @"";
}
- (NSString *)referenceHash:(NSString *)text {
    return text.length ? [self sha256:[text dataUsingEncoding:NSUTF8StringEncoding]] : @"";
}
- (void)importReferenceText:(id)sender {
    if (!self.referenceAlert) return;
    NSOpenPanel *panel=[NSOpenPanel new];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    panel.allowedContentTypes=@[UTTypePlainText,[UTType typeWithFilenameExtension:@"md"] ?: UTTypePlainText];panel.message=@"选择参考脚本的文本文件";
    [panel beginSheetModalForWindow:self.referenceAlert.window completionHandler:^(NSModalResponse response) {
        if (response!=NSModalResponseOK) return;
        NSNumber *size=nil;[panel.URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        NSString *text=size.unsignedLongLongValue<=128*1024 ? [NSString stringWithContentsOfURL:panel.URL usedEncoding:nil error:nil] : nil;
        text=[self validatedReferenceText:text];
        if (text) {self.referenceEditor.string=text;self.referenceLimit.stringValue=@"最多 20000 字 · 仅保存在本机当前项目";}
        else self.referenceLimit.stringValue=@"无法读取：请选择不超过 20000 字的 TXT 或 Markdown 文本。";
    }];
}
- (void)showReferenceScript:(id)sender {
    if (self.requestID || self.referenceRequestID || !self.dropUID.length || ![self isolatedProjectActive] || self.referenceAlert) return;
    NSString *project=self.dropUID;
    NSAlert *alert=[NSAlert new];self.referenceAlert=alert;alert.messageText=@"参考脚本";
    alert.informativeText=@"以实际说出的内容为准，参考脚本校正疑似错词、统一写法和辅助断句。\n现场改说、临时补充和未读出的段落会保留差异，不会照抄整篇脚本。";
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    NSButton *enabled=[NSButton checkboxWithTitle:@"使用此脚本辅助整理" target:nil action:nil];enabled.frame=NSMakeRect(0,272,310,24);
    NSDictionary *settings=[self referenceSettings];enabled.state=(!settings[@"enabled"] || [settings[@"enabled"] boolValue]) ? NSControlStateValueOn : NSControlStateValueOff;[view addSubview:enabled];
    NSButton *import=[self toolbarButton:@"导入文本…" symbol:@"doc.text" action:@selector(importReferenceText:)];import.frame=NSMakeRect(370,268,130,30);[view addSubview:import];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,54,500,204)];scroll.hasVerticalScroller=YES;scroll.borderType=NSNoBorder;scroll.wantsLayer=YES;scroll.layer.cornerRadius=10;scroll.layer.masksToBounds=YES;
    NSTextView *editor=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,480,204)];self.referenceEditor=editor;
    editor.richText=NO;editor.importsGraphics=NO;editor.font=[NSFont systemFontOfSize:14];editor.backgroundColor=[NSColor colorWithCalibratedWhite:.09 alpha:1];editor.textColor=NSColor.labelColor;editor.textContainerInset=NSMakeSize(12,12);
    editor.verticallyResizable=YES;editor.horizontallyResizable=NO;editor.autoresizingMask=NSViewWidthSizable;editor.textContainer.widthTracksTextView=YES;
    editor.string=self.referenceDraft ?: (settings[@"text"] ?: @"");[editor setAccessibilityLabel:@"参考脚本文本"];scroll.documentView=editor;[view addSubview:scroll];
    self.referenceLimit=[self label:@"最多 20000 字 · 仅保存在本机当前项目" size:11 weight:NSFontWeightRegular];self.referenceLimit.frame=NSMakeRect(0,27,500,22);self.referenceLimit.textColor=NSColor.secondaryLabelColor;[view addSubview:self.referenceLimit];
    NSTextField *hint=[self label:self.captionRows.count ? @"整理当前字幕会保留现有时间与分句；下次识别也会参考脚本断句。" : @"保存后，下次生成字幕时会自动参考；清空或关闭后停止使用。" size:11 weight:NSFontWeightRegular];hint.frame=NSMakeRect(0,0,500,22);hint.textColor=NSColor.secondaryLabelColor;[view addSubview:hint];
    BOOL current=self.titlePayloads && self.captionRows.count;
    [alert addButtonWithTitle:current ? @"保存并整理当前字幕" : @"保存"];
    if (current) [alert addButtonWithTitle:@"仅保存"];
    [alert addButtonWithTitle:@"取消"];alert.accessoryView=view;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        self.referenceAlert=nil;self.referenceEditor=nil;self.referenceLimit=nil;
        if (result!=(NSAlertFirstButtonReturn) && !(current && result==NSAlertSecondButtonReturn)) {self.referenceDraft=nil;return;}
        if (![self.dropUID isEqual:project]) {self.referenceDraft=nil;return;}
        NSString *text=[self validatedReferenceText:editor.string];
        if (!text) {
            self.referenceDraft=editor.string;NSAlert *error=[NSAlert new];error.messageText=@"脚本未保存";error.informativeText=@"参考脚本最多 20000 字，不能包含控制字符。";[error beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r){[self showReferenceScript:nil];}];return;
        }
        self.referenceDraft=nil;NSMutableDictionary *all=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"referenceScripts"] mutableCopy] ?: [NSMutableDictionary new];
        if (text.length) all[project]=@{@"text":text,@"enabled":@(enabled.state==NSControlStateValueOn)};else [all removeObjectForKey:project];
        [NSUserDefaults.standardUserDefaults setObject:all forKey:@"referenceScripts"];self.referenceMessage=nil;[self updateInterface];
        if (current && result==NSAlertFirstButtonReturn && [self effectiveReferenceScript].length) [self startReferenceRefinement];
    }];
}
- (void)startReferenceRefinement {
    NSString *script=[self effectiveReferenceScript];
    if (!script.length || self.requestID || self.referenceRequestID || !self.captionRows.count || ![self isolatedProjectActive]) return;
    if (![self workerAvailable]) {self.referenceMessage=@"请先连接本机服务，再整理当前字幕。";[self updateInterface];return;}
    [self.view.window makeFirstResponder:nil];
    NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString;NSURL *directory=[self.bridgeURL URLByAppendingPathComponent:identifier];
    NSError *error=nil;BOOL ok=[NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:&error];
    NSArray *rows=[[NSArray alloc] initWithArray:self.captionRows copyItems:YES];
    NSDictionary *request=@{@"kind":@"reference",@"requestID":identifier,@"projectUID":self.dropUID,@"referenceScript":script,@"vocabulary":[self effectiveVocabulary],@"captions":rows};
    if (ok) ok=[[NSJSONSerialization dataWithJSONObject:request options:0 error:&error] writeToURL:[directory URLByAppendingPathComponent:@"request.json"] options:NSDataWritingAtomic error:&error];
    if (!ok) {self.referenceMessage=@"脚本整理未开始，请重试。";[self updateInterface];return;}
    self.referenceRequestID=identifier;self.referenceSourceRows=rows;self.referenceSourceResultID=self.resultRequestID;
    self.referenceGeneration=self.dropGeneration;self.referenceProcessingSHA=[self referenceHash:script];self.referenceStarted=NSDate.date;
    self.referenceMessage=nil;self.cancelButton.enabled=YES;[self updateInterface];
}
- (NSString *)referenceSummary:(NSDictionary *)report {
    NSUInteger changes=[report[@"correctionCount"] unsignedIntegerValue],breaks=[report[@"boundaryCount"] unsignedIntegerValue];
    if (!changes && !breaks) return @"脚本已参考 · 未发现可靠的可优化内容，保留识别结果";
    return [NSString stringWithFormat:@"已参考脚本 · 校正 %lu 处 · 分句参考 %lu 处",(unsigned long)changes,(unsigned long)breaks];
}
- (void)pollReferenceRefinement {
    if (!self.referenceRequestID) return;
    NSURL *directory=[self.bridgeURL URLByAppendingPathComponent:self.referenceRequestID];
    NSDictionary *response=[self readJSON:[directory URLByAppendingPathComponent:@"response.json"]];
    if (!response || [@[@"queued",@"running"] containsObject:response[@"status"]]) {
        if ([self workerAvailable] && -self.referenceStarted.timeIntervalSinceNow<120) return;
        [@"{}" writeToURL:[directory URLByAppendingPathComponent:@"cancel.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        self.referenceMessage=@"脚本整理未完成，当前字幕保持原样。";
    } else {
        NSArray *rows=response[@"captions"];
        BOOL valid=[response[@"requestID"] isEqual:self.referenceRequestID] && [response[@"status"] isEqual:@"ready"] && [response[@"projectUID"] isEqual:self.dropUID] && [response[@"referenceSHA256"] isEqual:self.referenceProcessingSHA] && self.referenceGeneration==self.dropGeneration && [self.resultRequestID isEqual:self.referenceSourceResultID] && [self.captionRows isEqual:self.referenceSourceRows] && [rows isKindOfClass:NSArray.class] && rows.count==self.captionRows.count;
        if (valid) for (NSUInteger i=0;i<rows.count;i++) {
            if (![rows[i] isKindOfClass:NSDictionary.class] || ![rows[i][@"text"] isKindOfClass:NSString.class] || ![rows[i][@"text"] length] || [rows[i][@"text"] length]>500) {valid=NO;break;}
            NSMutableDictionary *unchanged=[rows[i] mutableCopy];unchanged[@"text"]=self.captionRows[i][@"text"];
            if (![unchanged isEqual:self.captionRows[i]]) {valid=NO;break;}
        }
        if (valid) {
            self.referenceUndoRows=self.referenceSourceRows;self.referenceUndoPayloads=self.titlePayloads;self.referenceUndoWasOriginal=self.referenceUndone;
            for (NSUInteger i=0;i<rows.count;i++) self.captionRows[i][@"text"]=rows[i][@"text"];
            self.referenceMessage=[self referenceSummary:response[@"referenceReview"]];[self rebuildTitles];[self.captionTable reloadData];
        } else self.referenceMessage=[response[@"status"] isEqual:@"cancelled"] ? @"已取消脚本整理，字幕保持原样。" : @"脚本整理未应用，字幕保持原样；请重试。";
    }
    self.referenceRequestID=nil;self.referenceSourceRows=nil;self.referenceStarted=nil;[self updateInterface];
}
- (void)undoReferenceRefinement:(id)sender {
    if (self.requestID || self.referenceRequestID || !self.referenceUndoRows || !self.referenceUndoPayloads) return;
    self.captionRows=[NSMutableArray new];for (NSDictionary *row in self.referenceUndoRows) [self.captionRows addObject:row.mutableCopy];
    self.titlePayloads=self.referenceUndoPayloads;self.referenceUndoRows=nil;self.referenceUndoPayloads=nil;self.referenceUndone=self.referenceUndoWasOriginal;
    self.referenceMessage=@"已撤销本次脚本整理";[self rebuildTitles];[self.captionTable reloadData];[self updateInterface];
}
- (void)updateReferenceInterface {
    BOOL busy=self.requestID || self.referenceRequestID;
    NSString *script=[self effectiveReferenceScript];
    self.referenceButton.enabled=!busy && self.dropUID.length && [self isolatedProjectActive] && !self.importInProgress;
    NSString *referenceState=script.length ? @"已启用" : ([self referenceSettings][@"text"] ? @"已停用" : @"可选");
    self.referenceButton.toolTip=[NSString stringWithFormat:@"参考脚本 · %@：粘贴或导入脚本，辅助纠错与断句",referenceState];
    self.referenceButton.contentTintColor=script.length ? SubPopAccent() : nil;
    [self.referenceButton setAccessibilityValue:referenceState];
    self.referenceUndoButton.hidden=!self.referenceUndoRows || !self.titlePayloads;
    self.referenceUndoButton.enabled=!busy;
    self.restoreResultButton.hidden=self.titlePayloads || !self.observedProjectUID.length || busy;
    self.referenceActions.hidden=self.referenceUndoButton.hidden && self.restoreResultButton.hidden;
    self.referenceInfo.stringValue=self.referenceRequestID ? @"正在参考脚本整理字幕…" : (self.referenceMessage ?: (script.length ? @"以实际语音为准 · 脚本仅在本机参考" : @"粘贴或导入脚本，辅助纠错与断句"));
    if (self.referenceRequestID) {
        self.statusTitle.stringValue=@"正在参考脚本";self.statusDetail.stringValue=@"正在比对已识别的内容，保留现场表达和字幕时间。";
        [self.activity showStage:@"generate-titles" active:YES];
    }
    self.templatePicker.enabled=!busy;self.fontPicker.enabled=!busy;self.sizePicker.enabled=!busy;
    self.tap5aStyleButton.enabled=!busy && !self.importInProgress;
    if (self.historicalResult) {self.generateButton.enabled=NO;self.dropDetail.stringValue=@"已恢复历史字幕 · 重新识别前请拖入当前项目";}
}
- (BOOL)referenceRows:(NSArray *)rows matchTimingOf:(NSArray *)source {
    if (![rows isKindOfClass:NSArray.class] || rows.count!=source.count) return NO;
    for (NSUInteger i=0;i<rows.count;i++) {
        if (![rows[i] isKindOfClass:NSDictionary.class] || ![rows[i][@"text"] isKindOfClass:NSString.class] || ![rows[i][@"text"] length] || [rows[i][@"text"] length]>500) return NO;
        NSMutableDictionary *comparison=[rows[i] mutableCopy];comparison[@"text"]=source[i][@"text"];
        if (![comparison isEqual:source[i]]) return NO;
    }
    return YES;
}
- (void)restoreLastResult:(id)sender {
    if (self.requestID || self.referenceRequestID || self.titlePayloads || !self.observedProjectUID.length || !CMTIME_IS_NUMERIC(self.observedProjectDuration)) return;
    NSString *sha=nil,*uid=self.observedProjectUID;
    if (self.freshDropURL) {
        NSXMLDocument *xml=[[NSXMLDocument alloc] initWithData:[NSData dataWithContentsOfURL:self.freshDropURL] options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        for (NSXMLNode *bookmark in [xml nodesForXPath:@"//bookmark" error:nil]) [bookmark detach];
        if (!xml) return;sha=[self sha256:[xml XMLDataWithOptions:0]];
    }
    NSArray *directories=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.bridgeURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSDictionary *latestRequest=nil,*latestResponse=nil;NSDate *latestDate=nil;NSURL *latestInput=nil;
    for (NSURL *directory in directories) {
        if (![[NSUUID alloc] initWithUUIDString:directory.lastPathComponent]) continue;
        NSURL *responseURL=[directory URLByAppendingPathComponent:@"response.json"];NSDictionary *response=[self readJSON:responseURL];
        if (![response[@"status"] isEqual:@"ready"] || ![response[@"projectUID"] isEqual:uid] || (sha && ![response[@"snapshotSHA256"] isEqual:sha])) continue;
        NSString *duration=response[@"manifest"][@"duration"];if (![duration isKindOfClass:NSString.class]) continue;
        NSArray *fraction=[duration componentsSeparatedByString:@"/"];CMTime time=CMTimeMake([fraction[0] longLongValue],fraction.count==2 ? [fraction[1] intValue] : 1);
        if (!CMTIME_IS_NUMERIC(time) || CMTimeCompare(time,self.observedProjectDuration)!=0) continue;
        NSDictionary *request=[self readJSON:[directory URLByAppendingPathComponent:@"request.json"]];NSURL *input=[directory URLByAppendingPathComponent:@"input.fcpxml"];
        NSNumber *size=nil;[input getResourceValue:&size forKey:NSURLFileSizeKey error:nil];if (!size || size.unsignedLongLongValue>16*1024*1024) continue;
        NSString *inputSHA=[self sha256:[NSData dataWithContentsOfURL:input]];
        if (![request[@"requestID"] isEqual:directory.lastPathComponent] || ![request[@"xmlSHA256"] isEqual:inputSHA] || ![response[@"snapshotSHA256"] isEqual:inputSHA] || ![request[@"projectUID"] isEqual:uid]) continue;
        NSDate *date=nil;[responseURL getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        if (!latestDate || [date compare:latestDate]==NSOrderedDescending) {latestDate=date;latestRequest=request;latestResponse=response;latestInput=input;}
    }
    if (!latestRequest) {self.referenceMessage=@"未找到与当前项目匹配的历史字幕";[self updateInterface];return;}
    if (!self.freshDropURL) {
        NSURL *copy=[[self evidenceDirectory] URLByAppendingPathComponent:[NSString stringWithFormat:@"drop-recovered-%@.fcpxml",NSUUID.UUID.UUIDString]];
        if (![NSFileManager.defaultManager copyItemAtURL:latestInput toURL:copy error:nil]) return;
        NSDate *date=nil;[latestInput getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        self.freshDropURL=copy;self.freshDropDate=date ?: NSDate.distantPast;self.historicalResult=YES;
    }
    self.dropUID=uid;self.dropDuration=self.observedProjectDuration;self.dropName=latestResponse[@"manifest"][@"project"] ?: @"当前项目";
    self.requestID=latestRequest[@"requestID"];self.requestSHA=latestRequest[@"xmlSHA256"];self.requestModelID=latestRequest[@"modelID"];self.requestVocabulary=latestRequest[@"vocabulary"] ?: @[];
    for (NSMenuItem *item in self.modelPicker.itemArray) if ([item.representedObject isEqual:self.requestModelID]) {self.selectedModelID=self.requestModelID;[self.modelPicker selectItem:item];break;}
    self.requestReferenceSHA=[self referenceHash:[self validatedReferenceText:latestRequest[@"referenceScript"]] ?: @""];self.requestGeneration=self.dropGeneration;self.displayState=@"validate";self.visibleError=nil;
    [NSUserDefaults.standardUserDefaults setObject:@{@"historicalResult":@(self.historicalResult),@"referenceSHA256":self.requestReferenceSHA,@"vocabulary":self.requestVocabulary,@"requestID":self.requestID,@"snapshotSHA":self.requestSHA,@"modelID":self.requestModelID,@"projectUID":self.dropUID,@"projectName":self.dropName ?: @"",@"durationValue":@(self.dropDuration.value),@"durationScale":@(self.dropDuration.timescale),@"inputFile":self.freshDropURL.lastPathComponent} forKey:@"pendingSession"];
    [self pollWorker:nil];
}
