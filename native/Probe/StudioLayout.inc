- (NSStackView *)column:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *stack=[NSStackView stackViewWithViews:views];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=spacing;return stack;
}
- (NSStackView *)surface:(NSArray<NSView *> *)views {
    NSStackView *card=[self column:views spacing:12];card.edgeInsets=NSEdgeInsetsMake(16,16,16,16);card.wantsLayer=YES;card.layer.backgroundColor=[NSColor colorWithCalibratedWhite:.105 alpha:1].CGColor;card.layer.cornerRadius=14;card.layer.borderColor=[NSColor colorWithCalibratedWhite:1 alpha:.065].CGColor;card.layer.borderWidth=1;
    for (NSView *view in views) [view.widthAnchor constraintEqualToAnchor:card.widthAnchor constant:-32].active=YES;
    return card;
}
- (NSButton *)toolbarButton:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    NSButton *button=[NSButton buttonWithTitle:title target:self action:action];button.bezelStyle=NSBezelStyleRounded;button.controlSize=NSControlSizeRegular;button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];button.imagePosition=NSImageLeading;button.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];[button.heightAnchor constraintEqualToConstant:32].active=YES;return button;
}
- (void)loadView {
    self.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,660,740)];self.view.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];self.view.wantsLayer=YES;self.view.layer.backgroundColor=[NSColor colorWithCalibratedWhite:.065 alpha:1].CGColor;
    NSDictionary *catalog=[self readJSON:[[NSBundle bundleForClass:self.class] URLForResource:@"models" withExtension:@"json"]];self.modelCatalog=catalog[@"models"] ?: @[];
    self.selectedModelID=[NSUserDefaults.standardUserDefaults stringForKey:@"selectedModelID"] ?: catalog[@"defaultModelID"];
    if (![self.modelCatalog filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id == %@",self.selectedModelID]].count) self.selectedModelID=catalog[@"defaultModelID"];
    NSScrollView *page=[[NSScrollView alloc] initWithFrame:self.view.bounds];page.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;page.hasVerticalScroller=YES;page.drawsBackground=NO;[self.view addSubview:page];
    SubPopDocumentView *document=[SubPopDocumentView new];document.translatesAutoresizingMaskIntoConstraints=NO;page.documentView=document;[document.widthAnchor constraintEqualToAnchor:page.contentView.widthAnchor].active=YES;
    NSStackView *stack=[self column:@[] spacing:16];stack.translatesAutoresizingMaskIntoConstraints=NO;[document addSubview:stack];
    NSLayoutConstraint *fluid=[stack.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-40];fluid.priority=750;fluid.active=YES;
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],[stack.widthAnchor constraintLessThanOrEqualToConstant:800],[stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:24],[document.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor constant:24]]];
    self.signal=[[SubPopSignalView alloc] initWithFrame:NSMakeRect(0,0,38,38)];[self.signal.widthAnchor constraintEqualToConstant:38].active=YES;[self.signal.heightAnchor constraintEqualToConstant:38].active=YES;
    NSTextField *brand=[self label:@"SubPop" size:22 weight:NSFontWeightSemibold];
    NSTextField *subtitle=[self label:@"让字幕跟上你的表达" size:11 weight:NSFontWeightRegular];subtitle.textColor=NSColor.secondaryLabelColor;
    NSStackView *identity=[self column:@[brand,subtitle] spacing:2];NSView *spacer=[NSView new];
    self.vocabularyButton=[self toolbarButton:@"词库" symbol:@"text.book.closed" action:@selector(showVocabulary:)];[self.vocabularyButton setAccessibilityLabel:@"词库"];
    self.modelsButton=[self toolbarButton:@"模型" symbol:@"square.stack.3d.up" action:@selector(showModels:)];[self.modelsButton setAccessibilityLabel:@"模型管理"];
    NSButton *updates=[self toolbarButton:@"" symbol:@"arrow.triangle.2.circlepath" action:@selector(checkForUpdates:)];updates.toolTip=@"检查更新";[updates setAccessibilityLabel:@"检查更新"];
    NSButton *diagnostics=[self toolbarButton:@"" symbol:@"info.circle" action:@selector(showDiagnostics:)];diagnostics.toolTip=@"连接诊断";[diagnostics setAccessibilityLabel:@"连接诊断"];
    NSStackView *header=[NSStackView stackViewWithViews:@[self.signal,identity,spacer,self.vocabularyButton,self.modelsButton,updates,diagnostics]];header.spacing=10;header.alignment=NSLayoutAttributeCenterY;[stack addArrangedSubview:header];
    self.resultView=[[SubPopTitleDragView alloc] initWithFrame:NSMakeRect(0,0,600,120)];self.resultView.controller=self;self.resultView.target=self;self.resultView.action=@selector(importTitlesToFCP:);[self.resultView setAccessibilityElement:YES];[self.resultView setAccessibilityRole:NSAccessibilityGroupRole];[stack addArrangedSubview:self.resultView];[self.resultView.heightAnchor constraintEqualToConstant:120].active=YES;self.resultView.hidden=YES;
    self.templatePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.templatePicker addItemsWithTitles:@[@"FCP 原生 · 自适应底框",@"Tap5a · 自适应底框"]];self.templatePicker.target=self;self.templatePicker.action=@selector(templateChanged:);[self.templatePicker setAccessibilityLabel:@"字幕样式"];
    NSTextField *templateHint=[self label:@"无需重新识别" size:11 weight:NSFontWeightRegular];templateHint.textColor=NSColor.secondaryLabelColor;
    self.tap5aStyleButton=[self toolbarButton:@"整批样式" symbol:@"slider.horizontal.3" action:@selector(showTap5aStyle:)];
    self.templateControls=[NSStackView stackViewWithViews:@[[self label:@"字幕样式" size:11 weight:NSFontWeightMedium],self.templatePicker,self.tap5aStyleButton,[NSView new],templateHint]];self.templateControls.spacing=10;self.templateControls.alignment=NSLayoutAttributeCenterY;[stack addArrangedSubview:self.templateControls];self.templateControls.hidden=YES;
    SubPopDropView *drop=[[SubPopDropView alloc] initWithFrame:NSMakeRect(0,0,600,96)];drop.controller=self;drop.wantsLayer=YES;
    [drop registerForDraggedTypes:@[@"com.apple.finalcutpro.xml.v1-14",@"com.apple.finalcutpro.xml.v1-13",@"com.apple.finalcutpro.xml.v1-12",@"com.apple.finalcutpro.xml"]];[drop setAccessibilityElement:YES];[drop setAccessibilityRole:NSAccessibilityGroupRole];[drop setAccessibilityLabel:@"导入项目拖放区"];
    NSImageView *importIcon=[[NSImageView alloc] initWithFrame:NSMakeRect(18,29,34,34)];importIcon.image=[NSImage imageWithSystemSymbolName:@"rectangle.stack.badge.plus" accessibilityDescription:nil];importIcon.contentTintColor=SubPopAccent();[drop addSubview:importIcon];
    self.dropTitle=[self label:@"把项目拖到这里" size:16 weight:NSFontWeightSemibold];self.dropTitle.frame=NSMakeRect(68,50,510,24);self.dropTitle.autoresizingMask=NSViewWidthSizable;[drop addSubview:self.dropTitle];
    self.dropDetail=[self label:@"从 Final Cut Pro 浏览器拖入整个项目" size:12 weight:NSFontWeightRegular];self.dropDetail.textColor=NSColor.secondaryLabelColor;self.dropDetail.frame=NSMakeRect(68,22,510,22);self.dropDetail.autoresizingMask=NSViewWidthSizable;[drop addSubview:self.dropDetail];
    [stack addArrangedSubview:drop];[drop.heightAnchor constraintEqualToConstant:96].active=YES;
    self.modelPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];self.modelPicker.target=self;self.modelPicker.action=@selector(modelChanged:);[self.modelPicker setAccessibilityLabel:@"识别模型"];
    for (NSDictionary *model in self.modelCatalog) {[self.modelPicker addItemWithTitle:model[@"name"]];self.modelPicker.lastItem.representedObject=model[@"id"];}
    [self.modelPicker selectItemAtIndex:[self.modelCatalog indexOfObjectPassingTest:^BOOL(NSDictionary *m,NSUInteger i,BOOL *stop){return [m[@"id"] isEqual:self.selectedModelID];}]];
    self.audioPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.audioPicker addItemsWithTitles:@[@"仅对白 · 排除音乐角色",@"所有音频 · 时间线混合"]];self.audioPicker.target=self;self.audioPicker.action=@selector(audioChanged:);[self.audioPicker setAccessibilityLabel:@"音频范围"];
    NSStackView *left=[self column:@[[self label:@"识别模型" size:11 weight:NSFontWeightMedium],self.modelPicker] spacing:6];
    NSStackView *right=[self column:@[[self label:@"音频范围" size:11 weight:NSFontWeightMedium],self.audioPicker] spacing:6];
    for (NSStackView *column in @[left,right]) for (NSView *view in column.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:column.widthAnchor].active=YES;
    NSStackView *selectors=[NSStackView stackViewWithViews:@[left,right]];selectors.spacing=20;selectors.distribution=NSStackViewDistributionFillEqually;
    self.modelDetail=[self label:@"" size:11 weight:NSFontWeightRegular];self.modelDetail.textColor=NSColor.secondaryLabelColor;
    NSTextField *rules=[self label:@"自动整理   去句子标点  ·  自然断句  ·  保护专名和数值" size:11 weight:NSFontWeightRegular];rules.textColor=[NSColor colorWithCalibratedWhite:.68 alpha:1];
    [stack addArrangedSubview:[self surface:@[selectors,self.modelDetail,rules]]];
    self.statusTitle=[self label:@"准备生成字幕" size:14 weight:NSFontWeightSemibold];self.statusDetail=[self label:@"" size:12 weight:NSFontWeightRegular];self.statusDetail.textColor=NSColor.secondaryLabelColor;
    NSStackView *statusLine=[NSStackView stackViewWithViews:@[self.statusTitle,[NSView new]]];statusLine.alignment=NSLayoutAttributeCenterY;
    self.activity=[[SubPopActivityView alloc] initWithFrame:NSMakeRect(0,0,520,56)];[self.activity.heightAnchor constraintEqualToConstant:56].active=YES;
    self.jobBar=[[NSProgressIndicator alloc] initWithFrame:NSZeroRect];self.jobBar.indeterminate=NO;self.jobBar.minValue=0;self.jobBar.maxValue=1;self.jobBar.style=NSProgressIndicatorStyleBar;[self.jobBar.heightAnchor constraintEqualToConstant:5].active=YES;self.jobBar.hidden=YES;
    [stack addArrangedSubview:[self surface:@[statusLine,self.statusDetail,self.activity,self.jobBar]]];
    self.captionCount=[self label:@"字幕预览" size:13 weight:NSFontWeightSemibold];self.reviewToggle=[self toolbarButton:@"展开预览与样式 ▾" symbol:@"text.alignleft" action:@selector(toggleReview:)];
    self.reviewHeader=[NSStackView stackViewWithViews:@[self.captionCount,[NSView new],self.reviewToggle]];[stack addArrangedSubview:self.reviewHeader];self.reviewHeader.hidden=YES;
    self.captionTable=[NSTableView new];self.captionTable.rowHeight=36;self.captionTable.intercellSpacing=NSMakeSize(10,4);self.captionTable.usesAlternatingRowBackgroundColors=NO;self.captionTable.backgroundColor=[NSColor colorWithCalibratedWhite:.09 alpha:1];self.captionTable.dataSource=self;self.captionTable.delegate=self;
    NSTableColumn *time=[[NSTableColumn alloc] initWithIdentifier:@"time"];time.title=@"时间";time.width=82;time.minWidth=82;time.maxWidth=82;time.editable=NO;[self.captionTable addTableColumn:time];
    NSTableColumn *text=[[NSTableColumn alloc] initWithIdentifier:@"text"];text.title=@"字幕";text.width=460;text.editable=YES;[self.captionTable addTableColumn:text];self.captionTable.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    self.captionScroll=[NSScrollView new];self.captionScroll.documentView=self.captionTable;self.captionScroll.hasVerticalScroller=YES;self.captionScroll.borderType=NSNoBorder;self.captionScroll.wantsLayer=YES;self.captionScroll.layer.cornerRadius=12;self.captionScroll.layer.masksToBounds=YES;[self.captionScroll.heightAnchor constraintEqualToConstant:220].active=YES;[stack addArrangedSubview:self.captionScroll];self.captionScroll.hidden=YES;
    self.fontPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.fontPicker addItemsWithTitles:@[@"Helvetica",@"PingFang SC",@"Arial"]];self.fontPicker.target=self;self.fontPicker.action=@selector(styleChanged:);[self.fontPicker setAccessibilityLabel:@"字幕字体"];
    self.sizePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.sizePicker addItemsWithTitles:@[@"28",@"36",@"48",@"64",@"72",@"80",@"96",@"120"]];self.sizePicker.target=self;self.sizePicker.action=@selector(styleChanged:);[self.sizePicker setAccessibilityLabel:@"字幕字号"];
    self.editorControls=[NSStackView stackViewWithViews:@[[self label:@"字体" size:11 weight:NSFontWeightMedium],self.fontPicker,[self label:@"字号" size:11 weight:NSFontWeightMedium],self.sizePicker,[NSView new]]];self.editorControls.spacing=10;[stack addArrangedSubview:self.editorControls];self.editorControls.hidden=YES;

    self.serviceLabel=[self label:@"正在连接" size:11 weight:NSFontWeightRegular];self.cancelButton=[self toolbarButton:@"取消" symbol:@"xmark" action:@selector(cancelJob:)];
    self.generateButton=[NSButton buttonWithTitle:@"生成字幕" target:self action:@selector(primaryAction:)];self.generateButton.bezelStyle=NSBezelStyleRounded;self.generateButton.controlSize=NSControlSizeLarge;self.generateButton.keyEquivalent=@"\r";self.generateButton.bezelColor=SubPopAccent();[self.generateButton.widthAnchor constraintEqualToConstant:148].active=YES;[self.generateButton.heightAnchor constraintEqualToConstant:36].active=YES;
    NSStackView *actions=[NSStackView stackViewWithViews:@[self.serviceLabel,[NSView new],self.cancelButton,self.generateButton]];actions.alignment=NSLayoutAttributeCenterY;actions.spacing=12;[stack addArrangedSubview:actions];
    self.scopeLabel=[self label:@"音频留在本机  ·  字幕回到你的时间线" size:10 weight:NSFontWeightRegular];self.scopeLabel.textColor=NSColor.tertiaryLabelColor;[stack addArrangedSubview:self.scopeLabel];
    for (NSView *row in stack.arrangedSubviews) [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    self.output=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,520,300)];self.output.editable=NO;self.output.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];self.displayState=@"idle";[self updateInterface];
}
