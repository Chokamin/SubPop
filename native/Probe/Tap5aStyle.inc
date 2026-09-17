- (void)togglePreviewSafe:(NSButton *)sender {self.tap5aPreview.showsSafeArea=sender.state==NSControlStateValueOn;self.tap5aPreview.needsDisplay=YES;}
- (void)fullscreenPreview:(id)sender {[self.tap5aPreview showFullscreen];}
- (NSDictionary *)currentTap5aStyleValues {
    NSMutableDictionary *values=[NSMutableDictionary new];
    for (NSString *key in self.tap5aStyleControls) {
        id control=self.tap5aStyleControls[key];
        if ([control isKindOfClass:NSColorWell.class]) {NSColor *color=[[control color] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];values[key]=@[@(color.redComponent),@(color.greenComponent),@(color.blueComponent)];}
        else if ([control isKindOfClass:NSPopUpButton.class]) values[key]=[key isEqual:@"textFont"] ? SubPopSelectedFontFamily(control) : ([key hasPrefix:@"text"] ? [control titleOfSelectedItem] : @([control indexOfSelectedItem]));
        else if ([control isKindOfClass:NSButton.class]) values[key]=@([control state]==NSControlStateValueOn);
        else {
            NSString *text=[[control stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSScanner *scanner=[NSScanner scannerWithString:[text stringByReplacingOccurrencesOfString:@"," withString:@"."]];double number=0;
            if (text.length && [scanner scanDouble:&number] && scanner.isAtEnd && isfinite(number)) values[key]=@(number);
            else values[key]=self.tap5aPreview.style[key] ?: SubPopNormalizeTap5aStyle(self.tap5aStyle)[key];
        }
    }
    return SubPopNormalizeTap5aStyle(values);
}
- (void)textFamilyChanged:(NSPopUpButton *)sender {
    NSPopUpButton *faces=self.tap5aStyleControls[@"textFace"];NSString *old=faces.titleOfSelectedItem;
    [faces removeAllItems];for (NSArray *member in SubPopFontMembers(SubPopSelectedFontFamily(sender))) [faces addItemWithTitle:member[1]];
    if (old && [faces itemWithTitle:old]) [faces selectItemWithTitle:old];else if ([faces itemWithTitle:@"Regular"]) [faces selectItemWithTitle:@"Regular"];
    [self tap5aPreviewChanged:nil];
}
- (void)tap5aPreviewChanged:(id)sender {
    self.tap5aPreview.style=[self currentTap5aStyleValues];self.tap5aPreview.needsDisplay=YES;
}
- (void)controlTextDidChange:(NSNotification *)notification {
    if ([self.tap5aStyleControls.allValues containsObject:notification.object]) [self tap5aPreviewChanged:nil];
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    for (NSString *key in self.tap5aStyleControls) if (self.tap5aStyleControls[key]==notification.object) {
        NSDictionary *values=[self currentTap5aStyleValues];[(NSTextField *)notification.object setDoubleValue:[values[key] doubleValue]];[self tap5aPreviewChanged:nil];break;
    }
}
- (void)loadTap5aPreviewFrame {
    [self.tap5aImageGenerator cancelAllCGImageGeneration];self.tap5aImageGenerator=nil;
    NSUInteger generation=++self.tap5aPreviewGeneration;
    if (!self.captionRows.count || !self.tap5aPreview) return;
    self.tap5aPreviewIndex=MAX(0,MIN((NSInteger)self.captionRows.count-1,self.tap5aPreviewIndex));
    NSDictionary *row=self.captionRows[self.tap5aPreviewIndex];
    self.tap5aPreview.caption=row[@"text"];self.tap5aPreview.fontName=self.fontPicker.titleOfSelectedItem;
    self.tap5aPreview.fontSize=self.sizePicker.titleOfSelectedItem.doubleValue;self.tap5aPreview.projectWidth=[self.resultManifest[@"width"] doubleValue];
    double seconds=([row[@"start_frame"] doubleValue]+[row[@"end_frame"] doubleValue])/2*SubPopPreviewSeconds(self.resultManifest[@"frameDuration"]);
    self.tap5aPreviewLabel.stringValue=[NSString stringWithFormat:@"第 %ld / %lu 句 · %02d:%05.2f",(long)self.tap5aPreviewIndex+1,(unsigned long)self.captionRows.count,(int)(seconds/60),fmod(seconds,60)];
    self.tap5aPreview.frameImage=nil;self.tap5aPreview.placeholder=@"正在读取对应的视频帧…";[self tap5aPreviewChanged:nil];
    NSDictionary *source=self.freshDropURL ? SubPopPreviewSource([NSData dataWithContentsOfURL:self.freshDropURL],seconds) : nil;
    if (!source) {self.tap5aPreview.placeholder=@"当前片段暂不支持自动取帧\n可选择一张视频截图作为背景";return;}
    NSURL *url=source[@"url"];BOOL stale=NO;
    NSData *bookmark=[[NSData alloc] initWithBase64EncodedString:source[@"bookmark"] options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (bookmark.length) {NSURL *resolved=[NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope|NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:nil];if (resolved.isFileURL && !stale) url=resolved;}
    BOOL scoped=[url startAccessingSecurityScopedResource];
    AVAssetImageGenerator *generator=[AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:url options:nil]];
    generator.appliesPreferredTrackTransform=YES;generator.maximumSize=CGSizeMake(960,540);self.tap5aImageGenerator=generator;
    [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds([source[@"seconds"] doubleValue],60000) completionHandler:^(CGImageRef image,CMTime actualTime,NSError *error) {
        NSImage *frame=image ? [[NSImage alloc] initWithCGImage:image size:NSZeroSize] : nil;
        if (scoped) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation!=self.tap5aPreviewGeneration || !self.tap5aPreview) return;
            self.tap5aPreview.frameImage=frame;self.tap5aPreview.placeholder=frame ? nil : @"无法读取视频帧\n可选择一张视频截图作为背景";self.tap5aPreview.needsDisplay=YES;self.tap5aImageGenerator=nil;
        });
    }];
}
- (void)stepTap5aPreview:(NSButton *)sender {self.tap5aPreviewIndex+=sender.tag;[self loadTap5aPreviewFrame];}
- (void)chooseTap5aPreviewImage:(id)sender {
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;panel.message=@"选择视频截图作为样式预览背景";
    if ([panel runModal]==NSModalResponseOK) {
        BOOL scoped=[panel.URL startAccessingSecurityScopedResource];NSImage *image=[[NSImage alloc] initWithContentsOfURL:panel.URL];if (scoped) [panel.URL stopAccessingSecurityScopedResource];
        if (image) {++self.tap5aPreviewGeneration;[self.tap5aImageGenerator cancelAllCGImageGeneration];self.tap5aPreview.frameImage=image;self.tap5aPreviewLabel.stringValue=@"自选截图 · 当前字幕";self.tap5aPreview.needsDisplay=YES;}
    }
}
- (void)fillTap5aStyleControls:(NSDictionary *)style {
    NSDictionary *values=SubPopNormalizeTap5aStyle(style);
    for (NSArray *field in [[SubPopTap5aFields() arrayByAddingObjectsFromArray:SubPopTextFields()] arrayByAddingObjectsFromArray:SubPopEffectFields()]) {
        NSString *key=field[0];id control=self.tap5aStyleControls[key], value=values[key];
        if ([control isKindOfClass:NSColorWell.class]) [control setColor:[NSColor colorWithSRGBRed:[value[0] doubleValue] green:[value[1] doubleValue] blue:[value[2] doubleValue] alpha:1]];
        else if ([control isKindOfClass:NSPopUpButton.class]) [control selectItemAtIndex:[value integerValue]];
        else if ([control isKindOfClass:NSButton.class]) [control setState:[value boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
        else [control setDoubleValue:[value doubleValue]];
    }
    SubPopSelectFontFamily(self.tap5aStyleControls[@"textFont"],values[@"textFont"]);
    [self textFamilyChanged:self.tap5aStyleControls[@"textFont"]];
    [self.tap5aStyleControls[@"textFace"] selectItemWithTitle:values[@"textFace"]];
    [self tap5aPreviewChanged:nil];
}
- (void)tap5aPresetChanged:(NSPopUpButton *)sender {
    [self fillTap5aStyleControls:sender.indexOfSelectedItem==1 ? [NSUserDefaults.standardUserDefaults dictionaryForKey:@"tap5aStylePreset"] : nil];
}
- (void)showTap5aStyle:(id)sender {
    if (![self usesFileImport] || self.importInProgress || self.tap5aStyleControls) return;
    [self.view.window makeFirstResponder:nil];
    NSString *request=self.resultRequestID;NSUInteger generation=self.dropGeneration;
    NSAlert *alert=[NSAlert new];alert.messageText=@"整批字幕样式";
    alert.informativeText=@"应用到当前全部字幕，无需重新识别。导入后需替换旧字幕，不会更新 FCP 时间线上已有的字幕。";
    [alert addButtonWithTitle:@"应用到全部字幕"];[alert addButtonWithTitle:@"取消"];[alert addButtonWithTitle:@"保存预设并应用"];
    NSRect available=(self.view.window.screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat previewWidth=MAX(360,MIN(640,MIN(available.size.width-660,(available.size.height-350)*16/9)));
    CGFloat contentHeight=MAX(342,122+previewWidth*9/16+18);
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,previewWidth+580,contentHeight)];
    NSPopUpButton *preset=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(previewWidth+30,contentHeight-32,230,26) pullsDown:NO];
    [preset addItemsWithTitles:@[@"恢复模板默认",@"我的预设"]];[preset selectItemAtIndex:-1];preset.title=@"载入样式预设";
    [preset itemAtIndex:1].enabled=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"tap5aStylePreset"]!=nil;preset.target=self;preset.action=@selector(tap5aPresetChanged:);[preset setAccessibilityLabel:@"载入样式预设"];[content addSubview:preset];
    self.tap5aStyleControls=[NSMutableDictionary new];
    NSTabView *tabs=[[NSTabView alloc] initWithFrame:NSMakeRect(previewWidth+20,contentHeight-342,560,305)];
    NSTabViewItem *textTab=[[NSTabViewItem alloc] initWithIdentifier:@"text"];textTab.label=@"文字";
    NSTabViewItem *boxTab=[[NSTabViewItem alloc] initWithIdentifier:@"box"];boxTab.label=@"底框与留白";
    NSTabViewItem *effectsTab=[[NSTabViewItem alloc] initWithIdentifier:@"effects"];effectsTab.label=@"文字效果";
    [tabs addTabViewItem:textTab];[tabs addTabViewItem:effectsTab];[tabs addTabViewItem:boxTab];[content addSubview:tabs];
    for (NSUInteger i=0;i<2;i++) {
        NSString *key=i==0 ? @"textFont" : @"textFace";
        NSTextField *label=[self label:i==0 ? @"字体" : @"字形 / 粗细" size:12 weight:NSFontWeightRegular];label.frame=NSMakeRect(12,230-i*36,130,24);[textTab.view addSubview:label];
        NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(155,230-i*36,355,26) pullsDown:NO];
        if (i==0) {
            NSMutableArray *items=[NSMutableArray new];
            for(NSString *family in NSFontManager.sharedFontManager.availableFontFamilies) {
                NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:SubPopFontDisplayName(family) action:nil keyEquivalent:@""];item.representedObject=family;item.toolTip=family;[items addObject:item];
            }
            [items sortUsingComparator:^NSComparisonResult(NSMenuItem *a,NSMenuItem *b){NSComparisonResult order=[a.title localizedCaseInsensitiveCompare:b.title];return order==NSOrderedSame ? [a.representedObject compare:b.representedObject] : order;}];
            for(NSMenuItem *item in items) [popup.menu addItem:item];
        }
        popup.target=self;popup.action=i==0 ? @selector(textFamilyChanged:) : @selector(tap5aPreviewChanged:);[popup setAccessibilityLabel:label.stringValue];[textTab.view addSubview:popup];self.tap5aStyleControls[key]=popup;
    }
    NSArray *fields=[[SubPopTap5aFields() arrayByAddingObjectsFromArray:SubPopTextFields()] arrayByAddingObjectsFromArray:SubPopEffectFields()];
    for (NSUInteger i=0;i<fields.count;i++) {
        NSArray *field=fields[i];NSString *key=field[0];BOOL right=i>=9;NSUInteger row=right ? i-9 : i;
        BOOL typography=i>=13;CGFloat x=typography ? 12 : (right ? 290 : 12),y=typography ? 155-(i-13)*34 : 238-row*27;
        BOOL effect=i>=19;NSUInteger effectIndex=effect ? i-19 : 0;
        if (i==17 || i==18) {x=290;y=155-(i-17)*34;}
        if (effect) {NSUInteger column=effectIndex<4 ? 0 : (effectIndex<8 ? 1 : 2);NSUInteger effectRow=effectIndex-(column==0 ? 0 : (column==1 ? 4 : 8));x=12+column*178;y=235-effectRow*36;}
        NSView *container=effect ? effectsTab.view : (typography ? textTab.view : boxTab.view);
        SubPopResetLabel *label=[[SubPopResetLabel alloc] initWithFrame:NSZeroRect];label.title=field[1];label.bordered=NO;label.alignment=NSTextAlignmentLeft;label.font=[NSFont systemFontOfSize:12];label.target=label;label.action=@selector(resetClick:);label.frame=NSMakeRect(x,y,effect ? 105 : 145,24);[container addSubview:label];
        NSControl *control;
        if ([field[2] isKindOfClass:NSArray.class]) control=[[NSColorWell alloc] initWithFrame:NSMakeRect(x+(effect ? 107 : 150),y,effect ? 55 : 92,24)];
        else if ([key hasSuffix:@"Enabled"] || [key isEqual:@"background"] || [key isEqual:@"border"]) { NSButton *button=[NSButton checkboxWithTitle:@"" target:nil action:nil];button.frame=NSMakeRect(x+(effect ? 107 : 150),y,30,24);control=button; }
        else if ([key isEqual:@"sides"]) { NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(x+(effect ? 107 : 150),y,100,24) pullsDown:NO];[popup addItemsWithTitles:@[@"四边",@"上边",@"下边",@"右边",@"左边",@"上下",@"左右"]];control=popup; }
        else { SubPopNumberField *number=[[SubPopNumberField alloc] initWithFrame:NSMakeRect(x+(effect ? 107 : 150),y,effect ? 55 : 92,24)];number.minimumValue=[field[3] doubleValue];number.maximumValue=[field[4] doubleValue];number.placeholderString=[NSString stringWithFormat:@"%@–%@",field[3],field[4]];number.toolTip=[NSString stringWithFormat:@"范围 %@–%@；左右拖动调整，Shift 精调；点击输入数字",field[3],field[4]];number.delegate=self;control=number; }
        if ([control isKindOfClass:SubPopNumberField.class]) {label.numberField=(SubPopNumberField *)control;label.defaultValue=[field[2] doubleValue];label.toolTip=[NSString stringWithFormat:@"双击恢复默认值 %@",field[2]];}
        control.target=self;control.action=@selector(tap5aPreviewChanged:);[control setAccessibilityLabel:field[1]];[container addSubview:control];self.tap5aStyleControls[key]=control;
    }
    NSTextField *effectNote=[NSTextField wrappingLabelWithString:@"外框作用于文字轮廓，与底框边框独立。光晕沿用 Tap5a 的暖黄色；预览为效果示意。"];
    effectNote.frame=NSMakeRect(12,6,510,34);effectNote.font=[NSFont systemFontOfSize:11];effectNote.textColor=NSColor.secondaryLabelColor;[effectsTab.view addSubview:effectNote];
    NSTextField *textNote=[NSTextField wrappingLabelWithString:@"数值左右拖动，Shift 精调，点击输入；双击标签恢复默认。X 右正，Y 上正。\n行间距仅影响多行字幕；字距以点计，FCP 会换算为字号百分比。"];
    textNote.frame=NSMakeRect(12,0,510,44);textNote.font=[NSFont systemFontOfSize:11];textNote.textColor=NSColor.secondaryLabelColor;[textTab.view addSubview:textNote];
    NSTextField *note=[NSTextField wrappingLabelWithString:@"留白与圆角使用 Tap5a 参数单位。\n颜色的透明程度由“不透明度”控制。\n保存预设会覆盖“我的预设”，并用于下一次识别。"];
    note.frame=NSMakeRect(290,15,240,102);note.font=[NSFont systemFontOfSize:11];note.textColor=NSColor.secondaryLabelColor;[boxTab.view addSubview:note];
    self.tap5aPreview=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,122,previewWidth,previewWidth*9/16)];self.tap5aPreview.wantsLayer=YES;self.tap5aPreview.layer.cornerRadius=10;self.tap5aPreview.layer.masksToBounds=YES;[self.tap5aPreview setAccessibilityLabel:@"源视频帧上的字幕样式示意预览"];[content addSubview:self.tap5aPreview];
    self.tap5aPreviewLabel=[self label:@"读取视频帧" size:11 weight:NSFontWeightMedium];self.tap5aPreviewLabel.frame=NSMakeRect(0,92,previewWidth,22);[content addSubview:self.tap5aPreviewLabel];
    NSButton *previous=[NSButton buttonWithTitle:@"上一句" target:self action:@selector(stepTap5aPreview:)];previous.tag=-1;previous.frame=NSMakeRect(0,57,75,28);[content addSubview:previous];
    NSButton *next=[NSButton buttonWithTitle:@"下一句" target:self action:@selector(stepTap5aPreview:)];next.tag=1;next.frame=NSMakeRect(82,57,75,28);[content addSubview:next];
    NSButton *choose=[NSButton buttonWithTitle:@"选择视频截图…" target:self action:@selector(chooseTap5aPreviewImage:)];choose.frame=NSMakeRect(previewWidth-168,57,168,28);[content addSubview:choose];
    NSTextField *previewNote=[NSTextField wrappingLabelWithString:@"源画面示意，不含调色与特效 · 最终效果以 FCP 为准。"];
    previewNote.frame=NSMakeRect(0,0,previewWidth,25);previewNote.font=[NSFont systemFontOfSize:11];previewNote.textColor=NSColor.secondaryLabelColor;[content addSubview:previewNote];
    NSButton *safe=[NSButton checkboxWithTitle:@"安全框" target:self action:@selector(togglePreviewSafe:)];safe.frame=NSMakeRect(0,28,110,24);[safe setAccessibilityLabel:@"显示或隐藏安全框"];[content addSubview:safe];
    NSButton *full=[NSButton buttonWithTitle:@"全屏预览" target:self action:@selector(fullscreenPreview:)];full.frame=NSMakeRect(previewWidth-116,26,116,26);[content addSubview:full];
    self.tap5aPreviewIndex=MAX(0,self.captionTable.selectedRow);
    NSMutableDictionary *initial=SubPopNormalizeTap5aStyle(self.tap5aStyle).mutableCopy;
    initial[@"textFont"]=self.fontPicker.titleOfSelectedItem;initial[@"textSize"]=@(self.sizePicker.titleOfSelectedItem.doubleValue);
    [self fillTap5aStyleControls:initial];[self loadTap5aPreviewFrame];alert.accessoryView=content;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response==NSAlertFirstButtonReturn || response==NSAlertThirdButtonReturn) {
            NSDictionary *style=[self currentTap5aStyleValues];
            if (response==NSAlertThirdButtonReturn) [NSUserDefaults.standardUserDefaults setObject:style forKey:@"tap5aStylePreset"];
            if (generation==self.dropGeneration && [request isEqual:self.resultRequestID]) {self.tap5aStyle=style;
                NSString *font=style[@"textFont"],*size=[style[@"textSize"] stringValue];
                if (![self.fontPicker itemWithTitle:font]) [self.fontPicker addItemWithTitle:font];[self.fontPicker selectItemWithTitle:font];
                if (![self.sizePicker itemWithTitle:size]) [self.sizePicker addItemWithTitle:size];[self.sizePicker selectItemWithTitle:size];[self rebuildTitles];}
        }
        for (id control in self.tap5aStyleControls.allValues) if ([control isKindOfClass:NSColorWell.class]) [control deactivate];
        [self.tap5aPreview closeFullscreen:nil];self.tap5aStyleControls=nil;++self.tap5aPreviewGeneration;[self.tap5aImageGenerator cancelAllCGImageGeneration];self.tap5aImageGenerator=nil;self.tap5aPreview=nil;self.tap5aPreviewLabel=nil;
    }];
}
