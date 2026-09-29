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
    NSScrollView *page=[NSScrollView new];self.pageScroll=page;page.translatesAutoresizingMaskIntoConstraints=NO;page.hasVerticalScroller=NO;page.drawsBackground=NO;[self.view addSubview:page];
    SubPopDocumentView *document=[SubPopDocumentView new];document.translatesAutoresizingMaskIntoConstraints=NO;page.documentView=document;[document.widthAnchor constraintEqualToAnchor:page.contentView.widthAnchor].active=YES;
    NSStackView *stack=[self column:@[] spacing:16];self.pageStack=stack;stack.translatesAutoresizingMaskIntoConstraints=NO;[document addSubview:stack];
    NSLayoutConstraint *fluid=[stack.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-40];fluid.priority=750;fluid.active=YES;
    self.pageTopInset=[stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:24];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],[stack.widthAnchor constraintLessThanOrEqualToConstant:800],self.pageTopInset,[document.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor constant:16]]];
    self.signal=[[SubPopSignalView alloc] initWithFrame:NSMakeRect(0,0,38,38)];[self.signal.widthAnchor constraintEqualToConstant:38].active=YES;[self.signal.heightAnchor constraintEqualToConstant:38].active=YES;
    NSTextField *brand=[self label:@"SubPop" size:22 weight:NSFontWeightSemibold];
    NSTextField *subtitle=[self label:@"让字幕跟上你的表达" size:11 weight:NSFontWeightRegular];subtitle.textColor=NSColor.secondaryLabelColor;
    NSStackView *identity=[self column:@[brand,subtitle] spacing:2];NSView *spacer=[NSView new];
    self.vocabularyButton=[self toolbarButton:@"词库" symbol:@"text.book.closed" action:@selector(showVocabulary:)];[self.vocabularyButton setAccessibilityLabel:@"词库"];
    self.referenceButton=[self toolbarButton:@"参考脚本" symbol:@"doc.text" action:@selector(showReferenceScript:)];[self.referenceButton setAccessibilityLabel:@"参考脚本"];
    self.modelsButton=[self toolbarButton:@"模型" symbol:@"square.stack.3d.up" action:@selector(showModels:)];[self.modelsButton setAccessibilityLabel:@"模型管理"];
    NSButton *updates=[self toolbarButton:@"" symbol:@"arrow.triangle.2.circlepath" action:@selector(checkForUpdates:)];updates.toolTip=@"检查更新";[updates setAccessibilityLabel:@"检查更新"];
    NSStackView *header=[NSStackView stackViewWithViews:@[self.signal,identity,spacer,self.vocabularyButton,self.referenceButton,self.modelsButton,updates]];header.spacing=10;header.alignment=NSLayoutAttributeCenterY;[stack addArrangedSubview:header];
    self.resultView=[[SubPopTitleDragView alloc] initWithFrame:NSMakeRect(0,0,600,120)];self.resultView.controller=self;self.resultView.target=self;self.resultView.action=@selector(importTitlesToFCP:);[self.resultView setAccessibilityElement:YES];[self.resultView setAccessibilityRole:NSAccessibilityGroupRole];[stack addArrangedSubview:self.resultView];[self.resultView.heightAnchor constraintEqualToConstant:120].active=YES;self.resultView.hidden=YES;
    self.srtExportButton=[self toolbarButton:@"下载 SRT 文件…" symbol:@"text.page" action:@selector(downloadSRT:)];
    self.fcpxmlExportButton=[self toolbarButton:@"下载 FCPXML 文件…" symbol:@"film.stack" action:@selector(downloadFCPXML:)];
    self.exportActions=[NSStackView stackViewWithViews:@[self.srtExportButton,self.fcpxmlExportButton]];
    self.exportActions.spacing=10;self.exportActions.distribution=NSStackViewDistributionFillEqually;
    [stack addArrangedSubview:self.exportActions];self.exportActions.hidden=YES;
    self.exportStatus=[self label:@"" size:11 weight:NSFontWeightRegular];
    self.exportStatus.textColor=NSColor.secondaryLabelColor;
    [stack addArrangedSubview:self.exportStatus];self.exportStatus.hidden=YES;
    self.templatePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.templatePicker addItemsWithTitles:@[@"普通字幕 · 无底框",@"FCP 原生 · 自适应底框",@"Tap5a · 自适应底框"]];[self.templatePicker selectItemAtIndex:SubPopTitleTemplateBasic];self.templatePicker.target=self;self.templatePicker.action=@selector(templateChanged:);[self.templatePicker setAccessibilityLabel:@"字幕样式"];
    NSTextField *templateHint=[self label:@"无需重新识别" size:11 weight:NSFontWeightRegular];templateHint.textColor=NSColor.secondaryLabelColor;
    self.tap5aStyleButton=[self toolbarButton:@"整批样式" symbol:@"slider.horizontal.3" action:@selector(showTap5aStyle:)];
    self.templateControls=[NSStackView stackViewWithViews:@[[self label:@"字幕样式" size:11 weight:NSFontWeightMedium],self.templatePicker,self.tap5aStyleButton,[NSView new],templateHint]];self.templateControls.spacing=10;self.templateControls.alignment=NSLayoutAttributeCenterY;[stack addArrangedSubview:self.templateControls];self.templateControls.hidden=YES;
    SubPopDropView *drop=[[SubPopDropView alloc] initWithFrame:NSMakeRect(0,0,600,96)];drop.controller=self;drop.wantsLayer=YES;
    [drop registerForDraggedTypes:@[@"com.apple.finalcutpro.xml.v1-14",@"com.apple.finalcutpro.xml.v1-13",@"com.apple.finalcutpro.xml.v1-12",@"com.apple.finalcutpro.xml",NSPasteboardTypeFileURL]];[drop setAccessibilityElement:YES];[drop setAccessibilityRole:NSAccessibilityGroupRole];[drop setAccessibilityLabel:@"导入项目或整条时间线音频拖放区"];
    NSImageView *importIcon=[NSImageView new];importIcon.translatesAutoresizingMaskIntoConstraints=NO;importIcon.image=[NSImage imageWithSystemSymbolName:@"rectangle.stack.badge.plus" accessibilityDescription:nil];importIcon.contentTintColor=SubPopAccent();[drop addSubview:importIcon];
    self.dropTitle=[self label:@"把项目拖到这里" size:16 weight:NSFontWeightSemibold];self.dropTitle.maximumNumberOfLines=1;self.dropTitle.lineBreakMode=NSLineBreakByTruncatingTail;
    self.dropDetail=[self label:@"从 Final Cut Pro 浏览器拖入整个项目" size:12 weight:NSFontWeightRegular];self.dropDetail.textColor=NSColor.secondaryLabelColor;
    NSStackView *dropCopy=[self column:@[self.dropTitle,self.dropDetail] spacing:8];dropCopy.translatesAutoresizingMaskIntoConstraints=NO;[drop addSubview:dropCopy];
    for(NSView *label in dropCopy.arrangedSubviews) [label.widthAnchor constraintEqualToAnchor:dropCopy.widthAnchor].active=YES;
    [NSLayoutConstraint activateConstraints:@[[importIcon.leadingAnchor constraintEqualToAnchor:drop.leadingAnchor constant:18],[importIcon.centerYAnchor constraintEqualToAnchor:drop.centerYAnchor],[importIcon.widthAnchor constraintEqualToConstant:34],[importIcon.heightAnchor constraintEqualToConstant:34],[dropCopy.leadingAnchor constraintEqualToAnchor:drop.leadingAnchor constant:68],[dropCopy.trailingAnchor constraintEqualToAnchor:drop.trailingAnchor constant:-18],[dropCopy.centerYAnchor constraintEqualToAnchor:drop.centerYAnchor]]];
    [stack addArrangedSubview:drop];self.dropHeight=[drop.heightAnchor constraintEqualToConstant:96];self.dropHeight.active=YES;
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
    self.referenceUndoButton=[self toolbarButton:@"撤销脚本整理" symbol:@"arrow.uturn.backward" action:@selector(undoReferenceRefinement:)];self.referenceUndoButton.hidden=YES;
    self.restoreResultButton=[self toolbarButton:@"恢复上次字幕" symbol:@"clock.arrow.circlepath" action:@selector(restoreLastResult:)];self.restoreResultButton.hidden=YES;
    self.referenceActions=[NSStackView stackViewWithViews:@[[NSView new],self.referenceUndoButton,self.restoreResultButton]];self.referenceActions.spacing=10;
    self.referenceInfo=[self label:@"粘贴或导入脚本，辅助纠错与断句" size:11 weight:NSFontWeightRegular];self.referenceInfo.textColor=NSColor.secondaryLabelColor;
    self.settingsCard=[self surface:@[selectors,self.modelDetail,rules,self.referenceActions,self.referenceInfo]];[stack addArrangedSubview:self.settingsCard];
    self.statusTitle=[self label:@"准备生成字幕" size:14 weight:NSFontWeightSemibold];self.statusDetail=[self label:@"" size:12 weight:NSFontWeightRegular];self.statusDetail.textColor=NSColor.secondaryLabelColor;
    NSStackView *statusLine=[NSStackView stackViewWithViews:@[self.statusTitle,[NSView new]]];statusLine.alignment=NSLayoutAttributeCenterY;
    self.activity=[[SubPopActivityView alloc] initWithFrame:NSMakeRect(0,0,520,56)];[self.activity.heightAnchor constraintEqualToConstant:56].active=YES;
    self.jobBar=[[NSProgressIndicator alloc] initWithFrame:NSZeroRect];self.jobBar.indeterminate=NO;self.jobBar.minValue=0;self.jobBar.maxValue=1;self.jobBar.style=NSProgressIndicatorStyleBar;[self.jobBar.heightAnchor constraintEqualToConstant:5].active=YES;self.jobBar.hidden=YES;
    self.fallbackAudioButton=[self toolbarButton:@"导入整条时间线音频…" symbol:@"waveform" action:@selector(chooseFallbackAudio:)];
    self.fallbackAudioButton.toolTip=@"仅在直接读取项目音频失败时使用。请从 Final Cut Pro 导出当前完整项目的音频；备用音频会按原项目时间轴识别。";
    self.fallbackAudioButton.hidden=YES;
    self.statusCard=[self surface:@[statusLine,self.statusDetail,self.fallbackAudioButton,self.activity,self.jobBar]];[stack addArrangedSubview:self.statusCard];
    self.captionCount=[self label:@"字幕预览" size:13 weight:NSFontWeightSemibold];self.reviewToggle=[self toolbarButton:@"展开预览与样式 ▾" symbol:@"text.alignleft" action:@selector(toggleReview:)];
    self.reviewHeader=[NSStackView stackViewWithViews:@[self.captionCount,[NSView new],self.reviewToggle]];[stack addArrangedSubview:self.reviewHeader];self.reviewHeader.hidden=YES;
    self.captionTable=[NSTableView new];self.captionTable.rowHeight=36;self.captionTable.intercellSpacing=NSMakeSize(10,4);self.captionTable.usesAlternatingRowBackgroundColors=NO;self.captionTable.backgroundColor=[NSColor colorWithCalibratedWhite:.09 alpha:1];self.captionTable.dataSource=self;self.captionTable.delegate=self;
    NSTableColumn *time=[[NSTableColumn alloc] initWithIdentifier:@"time"];time.title=@"时间";time.width=82;time.minWidth=82;time.maxWidth=82;time.editable=NO;[self.captionTable addTableColumn:time];
    NSTableColumn *text=[[NSTableColumn alloc] initWithIdentifier:@"text"];text.title=@"字幕";text.width=460;text.editable=YES;[self.captionTable addTableColumn:text];self.captionTable.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    self.captionScroll=[NSScrollView new];self.captionScroll.documentView=self.captionTable;self.captionScroll.hasVerticalScroller=YES;self.captionScroll.verticalScroller.alphaValue=0;self.captionScroll.borderType=NSNoBorder;self.captionScroll.wantsLayer=YES;self.captionScroll.layer.cornerRadius=12;self.captionScroll.layer.masksToBounds=YES;[self.captionScroll.heightAnchor constraintEqualToConstant:220].active=YES;[stack addArrangedSubview:self.captionScroll];self.captionScroll.hidden=YES;
    self.fontPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.fontPicker addItemsWithTitles:@[@"Helvetica",@"PingFang SC",@"Arial"]];self.fontPicker.target=self;self.fontPicker.action=@selector(styleChanged:);[self.fontPicker setAccessibilityLabel:@"字幕字体"];
    self.sizePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.sizePicker addItemsWithTitles:@[@"28",@"36",@"48",@"64",@"72",@"80",@"96",@"120"]];self.sizePicker.target=self;self.sizePicker.action=@selector(styleChanged:);[self.sizePicker setAccessibilityLabel:@"字幕字号"];
    self.editorControls=[NSStackView stackViewWithViews:@[[self label:@"字体" size:11 weight:NSFontWeightMedium],self.fontPicker,[self label:@"字号" size:11 weight:NSFontWeightMedium],self.sizePicker,[NSView new]]];self.editorControls.spacing=10;[stack addArrangedSubview:self.editorControls];self.editorControls.hidden=YES;

    self.cancelButton=[self toolbarButton:@"取消" symbol:@"xmark" action:@selector(cancelJob:)];
    self.clearResultButton=[self toolbarButton:@"清空本次字幕" symbol:@"arrow.counterclockwise" action:@selector(clearResult:)];
    self.clearResultButton.toolTip=@"清空本次字幕并保留项目名称和设置。重新识别前请从 FCP 浏览器重新拖入项目，以确认最新时间线和已有字幕。FCP 中的字幕不会删除。";
    self.generateButton=[NSButton buttonWithTitle:@"生成字幕" target:self action:@selector(primaryAction:)];self.generateButton.bezelStyle=NSBezelStyleRounded;self.generateButton.controlSize=NSControlSizeLarge;self.generateButton.keyEquivalent=@"\r";self.generateButton.bezelColor=SubPopAccent();[self.generateButton.widthAnchor constraintEqualToConstant:148].active=YES;[self.generateButton.heightAnchor constraintEqualToConstant:36].active=YES;
    NSStackView *actions=[NSStackView stackViewWithViews:@[[NSView new],self.clearResultButton,self.cancelButton,self.generateButton]];actions.alignment=NSLayoutAttributeCenterY;actions.spacing=12;
    self.scopeLabel=[self label:@"音频留在本机  ·  字幕回到你的时间线" size:10 weight:NSFontWeightRegular];self.scopeLabel.textColor=NSColor.tertiaryLabelColor;
    // The host can open a new extension version at half its main-window size.
    // Keep the primary action outside the scrolling document at every height.
    NSStackView *footer=[self column:@[actions,self.scopeLabel] spacing:8];footer.translatesAutoresizingMaskIntoConstraints=NO;footer.edgeInsets=NSEdgeInsetsMake(12,0,16,0);[self.view addSubview:footer];
    for(NSView *row in footer.arrangedSubviews) [row.widthAnchor constraintEqualToAnchor:footer.widthAnchor].active=YES;
    NSLayoutConstraint *footerWidth=[footer.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-40];footerWidth.priority=750;footerWidth.active=YES;
    [NSLayoutConstraint activateConstraints:@[[footer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[footer.widthAnchor constraintLessThanOrEqualToConstant:800],[footer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[page.topAnchor constraintEqualToAnchor:self.view.topAnchor],[page.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[page.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[page.bottomAnchor constraintEqualToAnchor:footer.topAnchor]]];
    for (NSView *row in stack.arrangedSubviews) [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    self.output=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,520,300)];self.output.editable=NO;self.output.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];self.displayState=@"idle";[self updateInterface];
}
- (void)updateViewportLayout {
    BOOL compact=self.view.bounds.size.height<600;
    if(compact!=self.compactLayout) {
        self.compactLayout=compact;
        self.pageStack.spacing=compact ? 10 : 16;
        self.pageTopInset.constant=compact ? 16 : 24;
        self.dropHeight.constant=compact ? 72 : 96;
        self.settingsCard.spacing=compact ? 8 : 12;
        self.settingsCard.edgeInsets=compact ? NSEdgeInsetsMake(12,16,12,16) : NSEdgeInsetsMake(16,16,16,16);
    }
    BOOL busy=self.requestID || self.referenceRequestID || self.pendingRecognition;
    NSString *state=self.lastVisualState ?: self.displayState;
    BOOL connected=[self workerAvailable];
    // During processing, the current phase takes priority over locked settings.
    self.settingsCard.hidden=compact && (busy || !connected || [state isEqual:@"preparing"]);
    self.statusCard.hidden=compact && connected && !busy && !self.titlePayloads && ([state isEqual:@"idle"] || [state isEqual:@"input"]);
}
- (void)viewDidLayout {
    [super viewDidLayout];
    if((self.view.bounds.size.height<600)!=self.compactLayout) [self updateViewportLayout];
}
