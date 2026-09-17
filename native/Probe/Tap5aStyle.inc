- (NSDictionary *)currentTap5aStyleValues {
    NSMutableDictionary *values=[NSMutableDictionary new];
    for (NSString *key in self.tap5aStyleControls) {
        id control=self.tap5aStyleControls[key];
        if ([control isKindOfClass:NSColorWell.class]) {NSColor *color=[[control color] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];values[key]=@[@(color.redComponent),@(color.greenComponent),@(color.blueComponent)];}
        else if ([control isKindOfClass:NSPopUpButton.class]) values[key]=@([control indexOfSelectedItem]);
        else if ([control isKindOfClass:NSButton.class]) values[key]=@([control state]==NSControlStateValueOn);
        else values[key]=@([control doubleValue]);
    }
    return SubPopNormalizeTap5aStyle(values);
}
- (void)tap5aPreviewChanged:(id)sender {
    self.tap5aPreview.style=[self currentTap5aStyleValues];self.tap5aPreview.needsDisplay=YES;
}
- (void)controlTextDidChange:(NSNotification *)notification {
    if ([self.tap5aStyleControls.allValues containsObject:notification.object]) [self tap5aPreviewChanged:nil];
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
    for (NSArray *field in SubPopTap5aFields()) {
        NSString *key=field[0];id control=self.tap5aStyleControls[key], value=values[key];
        if ([control isKindOfClass:NSColorWell.class]) [control setColor:[NSColor colorWithSRGBRed:[value[0] doubleValue] green:[value[1] doubleValue] blue:[value[2] doubleValue] alpha:1]];
        else if ([control isKindOfClass:NSPopUpButton.class]) [control selectItemAtIndex:[value integerValue]];
        else if ([control isKindOfClass:NSButton.class]) [control setState:[value boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
        else [control setDoubleValue:[value doubleValue]];
    }
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
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,940,342)];
    NSPopUpButton *preset=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(390,310,230,26) pullsDown:NO];
    [preset addItemsWithTitles:@[@"恢复模板默认",@"我的预设"]];[preset selectItemAtIndex:-1];preset.title=@"载入样式预设";
    [preset itemAtIndex:1].enabled=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"tap5aStylePreset"]!=nil;preset.target=self;preset.action=@selector(tap5aPresetChanged:);[preset setAccessibilityLabel:@"载入样式预设"];[content addSubview:preset];
    self.tap5aStyleControls=[NSMutableDictionary new];
    NSArray *fields=SubPopTap5aFields();
    for (NSUInteger i=0;i<fields.count;i++) {
        NSArray *field=fields[i];NSString *key=field[0];BOOL right=i>=9;NSUInteger row=right ? i-9 : i;
        CGFloat x=right ? 680 : 390,y=278-row*30;
        NSTextField *label=[self label:field[1] size:12 weight:NSFontWeightRegular];label.frame=NSMakeRect(x,y,145,24);[content addSubview:label];
        NSControl *control;
        if ([field[2] isKindOfClass:NSArray.class]) control=[[NSColorWell alloc] initWithFrame:NSMakeRect(x+150,y,92,24)];
        else if ([key isEqual:@"background"] || [key isEqual:@"border"]) { NSButton *button=[NSButton checkboxWithTitle:@"" target:nil action:nil];button.frame=NSMakeRect(x+150,y,30,24);control=button; }
        else if ([key isEqual:@"sides"]) { NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(x+150,y,100,24) pullsDown:NO];[popup addItemsWithTitles:@[@"四边",@"上边",@"下边",@"右边",@"左边",@"上下",@"左右"]];control=popup; }
        else { NSTextField *number=[[NSTextField alloc] initWithFrame:NSMakeRect(x+150,y,92,24)];NSNumberFormatter *format=[NSNumberFormatter new];format.numberStyle=NSNumberFormatterDecimalStyle;format.minimum=field[3];format.maximum=field[4];format.maximumFractionDigits=1;number.formatter=format;number.delegate=self;control=number; }
        control.target=self;control.action=@selector(tap5aPreviewChanged:);[control setAccessibilityLabel:field[1]];[content addSubview:control];self.tap5aStyleControls[key]=control;
    }
    NSTextField *note=[NSTextField wrappingLabelWithString:@"留白与圆角使用 Tap5a 参数单位。\n颜色的透明程度由“不透明度”控制。\n保存预设会覆盖“我的预设”，并用于下一次识别。"];
    note.frame=NSMakeRect(680,36,252,102);note.font=[NSFont systemFontOfSize:11];note.textColor=NSColor.secondaryLabelColor;[content addSubview:note];
    self.tap5aPreview=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,122,360,202.5)];self.tap5aPreview.wantsLayer=YES;self.tap5aPreview.layer.cornerRadius=10;self.tap5aPreview.layer.masksToBounds=YES;[self.tap5aPreview setAccessibilityLabel:@"源视频帧上的字幕样式示意预览"];[content addSubview:self.tap5aPreview];
    self.tap5aPreviewLabel=[self label:@"读取视频帧" size:11 weight:NSFontWeightMedium];self.tap5aPreviewLabel.frame=NSMakeRect(0,92,360,22);[content addSubview:self.tap5aPreviewLabel];
    NSButton *previous=[NSButton buttonWithTitle:@"上一句" target:self action:@selector(stepTap5aPreview:)];previous.tag=-1;previous.frame=NSMakeRect(0,57,75,28);[content addSubview:previous];
    NSButton *next=[NSButton buttonWithTitle:@"下一句" target:self action:@selector(stepTap5aPreview:)];next.tag=1;next.frame=NSMakeRect(82,57,75,28);[content addSubview:next];
    NSButton *choose=[NSButton buttonWithTitle:@"选择视频截图…" target:self action:@selector(chooseTap5aPreviewImage:)];choose.frame=NSMakeRect(192,57,168,28);[content addSubview:choose];
    NSTextField *previewNote=[NSTextField wrappingLabelWithString:@"源视频帧 + 样式示意，不含 FCP 特效与调色。\n底框最终效果以 FCP 为准。"];
    previewNote.frame=NSMakeRect(0,5,360,44);previewNote.font=[NSFont systemFontOfSize:11];previewNote.textColor=NSColor.secondaryLabelColor;[content addSubview:previewNote];
    self.tap5aPreviewIndex=MAX(0,self.captionTable.selectedRow);
    [self fillTap5aStyleControls:self.tap5aStyle];[self loadTap5aPreviewFrame];alert.accessoryView=content;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response==NSAlertFirstButtonReturn || response==NSAlertThirdButtonReturn) {
            NSDictionary *style=[self currentTap5aStyleValues];
            if (response==NSAlertThirdButtonReturn) [NSUserDefaults.standardUserDefaults setObject:style forKey:@"tap5aStylePreset"];
            if (generation==self.dropGeneration && [request isEqual:self.resultRequestID]) {self.tap5aStyle=style;[self rebuildTitles];}
        }
        for (id control in self.tap5aStyleControls.allValues) if ([control isKindOfClass:NSColorWell.class]) [control deactivate];
        self.tap5aStyleControls=nil;++self.tap5aPreviewGeneration;[self.tap5aImageGenerator cancelAllCGImageGeneration];self.tap5aImageGenerator=nil;self.tap5aPreview=nil;self.tap5aPreviewLabel=nil;
    }];
}
