- (void)syncStyleFontPickers:(NSDictionary *)style {
    NSString *font=style[@"textFont"],*size=[style[@"textSize"] stringValue];
    if (![self.fontPicker itemWithTitle:font]) [self.fontPicker addItemWithTitle:font];[self.fontPicker selectItemWithTitle:font];
    if (![self.sizePicker itemWithTitle:size]) [self.sizePicker addItemWithTitle:size];[self.sizePicker selectItemWithTitle:size];
}
- (void)updateNativePresetActions {
    if (!self.editingNativeStyle) return;
    NSString *identifier=self.nativePresetPicker.selectedItem.representedObject;
    NSDictionary *selected=nil;for (NSDictionary *p in self.nativePresetStore.presets) if ([p[@"id"] isEqual:identifier]) selected=p;
    BOOL saved=selected && [selected[@"style"] isEqual:[self currentTap5aStyleValues]] && [selected[@"name"] isEqual:self.nativePresetName.stringValue];
    self.nativePresetDefaultButton.enabled=saved;self.nativePresetDeleteButton.enabled=selected!=nil;
    BOOL isDefault=selected && [selected[@"id"] isEqual:self.nativePresetStore.defaultID];
    self.nativePresetDefaultButton.title=isDefault ? @"取消默认" : @"设为默认";
    self.nativePresetNotice.stringValue=selected ? (saved ? (isDefault ? @"此预设用于以后新项目的原生底框字幕。" : @"已载入预设；可设为以后新项目的默认样式。") : @"参数已调整；保存后可更新预设或设为默认。") : @"输入名称保存预设。同名预设会更新；预设仅保存样式，不保存字幕文字或时间。";
}
- (void)reloadNativePresetPicker:(NSString *)identifier {
    [self.nativePresetPicker removeAllItems];
    [self.nativePresetPicker addItemsWithTitles:@[@"当前调整",@"恢复模板默认"]];
    for (NSDictionary *p in self.nativePresetStore.presets) {
        NSString *name=[p[@"id"] isEqual:self.nativePresetStore.defaultID] ? [p[@"name"] stringByAppendingString:@" · 默认"] : p[@"name"];
        [self.nativePresetPicker addItemWithTitle:name];self.nativePresetPicker.lastItem.representedObject=p[@"id"];
    }
    [self.nativePresetPicker selectItemAtIndex:0];
    for (NSMenuItem *item in self.nativePresetPicker.itemArray) if (identifier && [item.representedObject isEqual:identifier]) [self.nativePresetPicker selectItem:item];
    [self updateNativePresetActions];
}
- (void)fillNativeStyleControls:(NSDictionary *)input {
    NSDictionary *style=SubPopNormalizeNativeStyle(input);
    for (NSString *key in self.tap5aStyleControls) {
        id control=self.tap5aStyleControls[key],value=style[key];
        if ([control isKindOfClass:NSColorWell.class]) [control setColor:[NSColor colorWithSRGBRed:[value[0] doubleValue] green:[value[1] doubleValue] blue:[value[2] doubleValue] alpha:1]];
        else if ([control isKindOfClass:NSPopUpButton.class]) {
            if ([key isEqual:@"textFont"] || [key isEqual:@"textFace"]) continue;
            for (NSMenuItem *item in [control itemArray]) if ([item.representedObject isEqual:value]) [control selectItem:item];
        } else if ([control isKindOfClass:NSButton.class]) [control setState:[value boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
        else [control setDoubleValue:[value doubleValue]];
    }
    SubPopSelectFontFamily(self.tap5aStyleControls[@"textFont"],style[@"textFont"]);
    [self textFamilyChanged:self.tap5aStyleControls[@"textFont"]];
    [self.tap5aStyleControls[@"textFace"] selectItemWithTitle:style[@"textFace"]];
    [self updateNativePresetActions];
}
- (void)nativePresetChanged:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem==0) return;
    self.nativePresetName.stringValue=@"";
    NSDictionary *style=nil;
    for (NSDictionary *p in self.nativePresetStore.presets) if ([p[@"id"] isEqual:sender.selectedItem.representedObject]) {style=p[@"style"];self.nativePresetName.stringValue=p[@"name"];}
    [self fillNativeStyleControls:style];
}
- (void)saveNativePreset:(id)sender {
    [self.view.window.attachedSheet makeFirstResponder:nil];
    NSString *name=[self.nativePresetName.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *identifier=[self.nativePresetStore saveStyle:[self currentTap5aStyleValues] name:name];
    if (!identifier) {self.nativePresetNotice.stringValue=@"请输入 1–60 个字符的名称；最多保存 100 个预设。";return;}
    self.nativePresetName.stringValue=name;[self reloadNativePresetPicker:identifier];
    self.nativePresetNotice.stringValue=@"预设已保存。点击“应用到全部字幕”即可用于当前结果。";
}
- (void)defaultNativePreset:(id)sender {
    if (!self.nativePresetDefaultButton.enabled) return;
    NSString *identifier=self.nativePresetPicker.selectedItem.representedObject;
    [self.nativePresetStore setDefaultID:[identifier isEqual:self.nativePresetStore.defaultID] ? @"" : identifier];
    [self reloadNativePresetPicker:identifier];
}
- (void)deleteNativePreset:(id)sender {
    NSString *identifier=self.nativePresetPicker.selectedItem.representedObject;
    if (!identifier.length) return;
    [self.nativePresetStore removeID:identifier];self.nativePresetName.stringValue=@"";
    [self reloadNativePresetPicker:nil];self.nativePresetNotice.stringValue=@"预设已删除；当前参数仍可继续使用。";
}
- (void)readNativeProjectStyle:(NSPopUpButton *)sender {
    NSXMLElement *title=sender.selectedItem.representedObject;
    if (![title isKindOfClass:NSXMLElement.class]) return;
    NSDictionary *style=SubPopNativeStyleFromTitle(title);
    if (!style) {self.nativePresetNotice.stringValue=@"这条字幕含参数关键帧或无法读取的位置，无法保存为静态样式；请选择其他字幕。";return;}
    [self.nativePresetPicker selectItemAtIndex:0];self.nativePresetName.stringValue=@"";[self fillNativeStyleControls:style];
    self.nativePresetNotice.stringValue=@"已读取静态字体、文字位置及底框参数。输入名称后可保存预设。";
}
- (void)showNativeStyle:(id)sender {
    if (self.importInProgress || self.tap5aStyleControls || !self.captionRows.count) return;
    [self.view.window makeFirstResponder:nil];
    NSString *request=self.resultRequestID;NSUInteger generation=self.dropGeneration;
    self.nativePresetStore=self.nativePresetStore ?: [[SubPopNativePresetStore alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    self.nativeStyle=self.nativeStyle ?: self.nativePresetStore.defaultStyle;
    self.editingNativeStyle=YES;self.tap5aStyleControls=[NSMutableDictionary new];
    NSAlert *alert=[NSAlert new];alert.messageText=@"原生底框样式与预设";
    alert.informativeText=@"应用到当前全部字幕，无需重新识别。FCP 中刚调整的样式需重新拖入项目后读取；已导入的字幕不会自动更新。";
    [alert addButtonWithTitle:@"应用到全部字幕"];[alert addButtonWithTitle:@"取消"];
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,600,475)];
    NSTextField *label=[self label:@"样式预设" size:12 weight:NSFontWeightMedium];label.frame=NSMakeRect(0,441,74,24);[content addSubview:label];
    self.nativePresetPicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(76,439,524,26) pullsDown:NO];
    self.nativePresetPicker.target=self;self.nativePresetPicker.action=@selector(nativePresetChanged:);[self.nativePresetPicker setAccessibilityLabel:@"原生底框样式预设"];[content addSubview:self.nativePresetPicker];
    label=[self label:@"名称" size:12 weight:NSFontWeightRegular];label.frame=NSMakeRect(0,405,74,24);[content addSubview:label];
    self.nativePresetName=[[NSTextField alloc] initWithFrame:NSMakeRect(76,403,226,26)];self.nativePresetName.placeholderString=@"例如：白字黑底";self.nativePresetName.delegate=self;[self.nativePresetName setAccessibilityLabel:@"预设名称"];[content addSubview:self.nativePresetName];
    NSArray *buttonNames=@[@"保存预设",@"设为默认",@"删除预设"];
    SEL actions[]={@selector(saveNativePreset:),@selector(defaultNativePreset:),@selector(deleteNativePreset:)};
    for (NSUInteger i=0;i<3;i++) {
        NSButton *button=[NSButton buttonWithTitle:buttonNames[i] target:self action:actions[i]];button.frame=NSMakeRect(310+i*100,402,92,28);[content addSubview:button];
        if (i==0) button.toolTip=@"同名预设会更新，其他预设保留";
        if (i==1) self.nativePresetDefaultButton=button;
        if (i==2) self.nativePresetDeleteButton=button;
    }
    NSTabView *tabs=[[NSTabView alloc] initWithFrame:NSMakeRect(0,91,600,303)];
    NSMutableArray *tabItems=[NSMutableArray new];for (NSString *name in @[@"文字",@"底框与位置",@"动画"]) {NSTabViewItem *item=[[NSTabViewItem alloc] initWithIdentifier:name];item.label=name;[tabs addTabViewItem:item];[tabItems addObject:item];}[content addSubview:tabs];
    NSView *textTab=[tabItems[0] view],*boxTab=[tabItems[1] view],*animationTab=[tabItems[2] view];
    for (NSUInteger i=0;i<2;i++) {
        NSString *key=i ? @"textFace" : @"textFont";
        label=[self label:i ? @"字形 / 粗细" : @"字体" size:12 weight:NSFontWeightRegular];label.frame=NSMakeRect(12,233-i*35,135,24);[textTab addSubview:label];
        NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(157,233-i*35,400,26) pullsDown:NO];
        if (!i) {
            NSArray *families=[NSFontManager.sharedFontManager.availableFontFamilies sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            for (NSString *family in families) {NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:SubPopFontDisplayName(family) action:nil keyEquivalent:@""];item.representedObject=family;[popup.menu addItem:item];}
        }
        popup.target=self;popup.action=i ? @selector(tap5aPreviewChanged:) : @selector(textFamilyChanged:);[popup setAccessibilityLabel:label.stringValue];[textTab addSubview:popup];self.tap5aStyleControls[key]=popup;
    }
    NSArray *textFields=[SubPopTextFields() subarrayWithRange:NSMakeRange(0,4)];
    NSArray *fields=[[textFields arrayByAddingObjectsFromArray:SubPopNativeBoxFields()] arrayByAddingObjectsFromArray:SubPopNativeTextPositionFields()];
    for (NSUInteger i=0;i<fields.count;i++) {
        NSArray *f=fields[i];NSString *key=f[0];BOOL position=i>=15,text=i<4 || position,animation=i>=12 && i<15;
        NSUInteger index=position ? i-15 : (text ? i : (animation ? i-12 : i-4));NSUInteger row=animation || text ? index : index%5;
        CGFloat x=(position || (!text && !animation && index>=5)) ? 304 : 12;
        CGFloat y=(text ? 159 : 233)-row*35;NSView *container=text ? textTab : (animation ? animationTab : boxTab);
        SubPopResetLabel *reset=[[SubPopResetLabel alloc] initWithFrame:NSMakeRect(x,y,142,24)];reset.title=f[1];reset.bordered=NO;reset.alignment=NSTextAlignmentLeft;reset.font=[NSFont systemFontOfSize:12];reset.target=reset;reset.action=@selector(resetClick:);[container addSubview:reset];
        NSControl *control;
        if ([f[2] isKindOfClass:NSArray.class]) control=[[NSColorWell alloc] initWithFrame:NSMakeRect(x+145,y,110,24)];
        else if ([key isEqual:@"verticalSafe"]) {NSButton *button=[NSButton checkboxWithTitle:@"" target:nil action:nil];button.frame=NSMakeRect(x+145,y,28,24);control=button;}
        else if ([key isEqual:@"animationStyle"] || [key isEqual:@"animateBy"]) {
            NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(x+145,y,200,26) pullsDown:NO];
            NSArray *names=[key isEqual:@"animationStyle"] ? @[@"无",@"淡入淡出",@"缩放",@"高亮",@"填充"] : @[@"字符",@"字词",@"行",@"全部"];
            NSArray *tags=[key isEqual:@"animationStyle"] ? @[@0,@1,@3,@4,@5] : @[@0,@1,@2,@3];
            for (NSUInteger n=0;n<names.count;n++) {[popup addItemWithTitle:names[n]];popup.lastItem.representedObject=tags[n];}control=popup;
        } else {
            SubPopNumberField *number=[[SubPopNumberField alloc] initWithFrame:NSMakeRect(x+145,y,110,24)];number.minimumValue=[f[3] doubleValue];number.maximumValue=[f[4] doubleValue];number.delegate=self;number.toolTip=[NSString stringWithFormat:@"范围 %@–%@；数值与 FCP 检查器一致",f[3],f[4]];reset.numberField=number;reset.defaultValue=[f[2] doubleValue];control=number;
        }
        control.target=self;control.action=@selector(tap5aPreviewChanged:);[control setAccessibilityLabel:f[1]];[container addSubview:control];self.tap5aStyleControls[key]=control;
    }
    label=[NSTextField wrappingLabelWithString:@"对应 FCP「文本」页的位置，\n与模板的位置偏移分别保存。"];
    label.frame=NSMakeRect(304,20,255,54);label.font=[NSFont systemFontOfSize:11];label.textColor=NSColor.secondaryLabelColor;[textTab addSubview:label];
    label=[NSTextField wrappingLabelWithString:@"宽高为自适应底框的调整量，0 使用模板默认。\n数值与 FCP 检查器一致；最终画面和动画请在 FCP 中查看。"];
    label.frame=NSMakeRect(12,6,550,40);label.font=[NSFont systemFontOfSize:11];label.textColor=NSColor.secondaryLabelColor;[boxTab addSubview:label];
    label=[self label:@"读取项目字幕" size:12 weight:NSFontWeightRegular];label.frame=NSMakeRect(0,56,110,24);[content addSubview:label];
    NSPopUpButton *source=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(120,54,480,26) pullsDown:NO];[source addItemWithTitle:@"选择已调整好的原生底框字幕…"];
    NSData *xml=self.freshDropURL ? [NSData dataWithContentsOfURL:self.freshDropURL] : nil;
    NSXMLDocument *doc=xml ? [[NSXMLDocument alloc] initWithData:xml options:NSXMLNodeLoadExternalEntitiesNever error:nil] : nil;
    NSUInteger n=0;for (NSXMLElement *title in SubPopNativeProjectTitles(doc)) {
        NSString *name=[title attributeForName:@"name"].stringValue ?: @"字幕";if (name.length>32) name=[[name substringToIndex:32] stringByAppendingString:@"…"];
        [source addItemWithTitle:[NSString stringWithFormat:@"%lu · %@",(unsigned long)++n,name]];source.lastItem.representedObject=title;
    }
    source.enabled=n>0;source.target=self;source.action=@selector(readNativeProjectStyle:);[source setAccessibilityLabel:@"读取项目中已有字幕的静态样式"];[content addSubview:source];
    self.nativePresetNotice=[NSTextField wrappingLabelWithString:@""];self.nativePresetNotice.frame=NSMakeRect(0,0,600,42);self.nativePresetNotice.font=[NSFont systemFontOfSize:11];self.nativePresetNotice.textColor=NSColor.secondaryLabelColor;[content addSubview:self.nativePresetNotice];
    [self reloadNativePresetPicker:nil];[self fillNativeStyleControls:self.nativeStyle];alert.accessoryView=content;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response==NSAlertFirstButtonReturn && generation==self.dropGeneration && [request isEqual:self.resultRequestID] && self.templatePicker.indexOfSelectedItem==SubPopTitleTemplateNative) {
            self.nativeStyle=[self currentTap5aStyleValues];[self syncStyleFontPickers:self.nativeStyle];[self rebuildTitles];
        }
        for (id control in self.tap5aStyleControls.allValues) if ([control isKindOfClass:NSColorWell.class]) [control deactivate];
        self.tap5aStyleControls=nil;self.editingNativeStyle=NO;self.nativePresetPicker=nil;self.nativePresetName=nil;self.nativePresetNotice=nil;self.nativePresetDefaultButton=nil;self.nativePresetDeleteButton=nil;
    }];
}
