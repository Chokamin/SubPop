#import <Cocoa/Cocoa.h>
#import "Feedback.h"
#import "FeedbackImage.h"

static BOOL SubPopFeedbackHandleEditingKey(NSTextView *editor,NSEvent *event) {
    NSEventModifierFlags modifiers=event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagShift|NSEventModifierFlagControl|NSEventModifierFlagOption);
    if (modifiers!=NSEventModifierFlagCommand) return NO;
    NSString *key=event.charactersIgnoringModifiers.lowercaseString;
    if ([key isEqual:@"v"]) [editor paste:nil];
    else if ([key isEqual:@"c"]) [editor copy:nil];
    else if ([key isEqual:@"x"]) [editor cut:nil];
    else if ([key isEqual:@"a"]) [editor selectAll:nil];
    else return NO;
    return YES;
}
@interface SubPopFeedbackEditor : NSTextView
@end
@implementation SubPopFeedbackEditor
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.window.firstResponder==self && SubPopFeedbackHandleEditingKey(self,event)) return YES;
    return [super performKeyEquivalent:event];
}
@end

@interface SubPopFeedbackPanel : NSObject <NSTextViewDelegate>
@property NSAlert *alert;
@property NSTextView *descriptionEditor;
@property NSTextField *environmentLabel;
@property NSTextField *status;
@property NSButton *issueButton;
@property NSButton *clipboardButton;
@property NSDictionary *environment;
@property NSData *screenshotData;
@property NSImage *screenshotImage;
@property NSImageView *screenshotPreview;
@property NSTextField *screenshotLabel;
@property NSButton *screenshotChooseButton;
@property NSButton *screenshotCopyButton;
@property NSButton *screenshotRemoveButton;
@property NSOpenPanel *openPanel;
@property NSUInteger screenshotGeneration;
@property (copy) void (^onClose)(void);
- (void)showForWindow:(NSWindow *)window bundle:(NSBundle *)bundle;
- (void)close;
- (BOOL)loadScreenshotURL:(NSURL *)url;
- (void)chooseScreenshot:(id)sender;
- (void)copyScreenshot:(id)sender;
- (void)removeScreenshot:(id)sender;
@end

@implementation SubPopFeedbackPanel
- (NSTextView *)editorInView:(NSView *)view rect:(NSRect)rect label:(NSString *)label {
    NSTextField *heading=[NSTextField labelWithString:label];heading.frame=NSMakeRect(0,NSMaxY(rect)+5,450,20);heading.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];[view addSubview:heading];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:rect];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.borderType=NSBezelBorder;
    NSTextView *editor=[[SubPopFeedbackEditor alloc] initWithFrame:NSMakeRect(0,0,rect.size.width-18,rect.size.height)];
    editor.richText=NO;editor.importsGraphics=NO;editor.font=[NSFont systemFontOfSize:13];editor.textContainerInset=NSMakeSize(8,8);
    editor.verticallyResizable=YES;editor.horizontallyResizable=NO;editor.autoresizingMask=NSViewWidthSizable;editor.textContainer.widthTracksTextView=YES;editor.delegate=self;
    editor.automaticTextReplacementEnabled=NO;editor.automaticSpellingCorrectionEnabled=NO;
    if (@available(macOS 15.2,*)) editor.writingToolsBehavior=NSWritingToolsBehaviorNone;
    [editor setAccessibilityLabel:label];scroll.documentView=editor;[view addSubview:scroll];return editor;
}
- (void)prepareForBundle:(NSBundle *)bundle {
    self.environment=SubPopFeedbackEnvironment(bundle);self.screenshotGeneration++;
    self.alert=[NSAlert new];self.alert.messageText=@"问题反馈";
    self.alert.informativeText=@"反馈将在 GitHub 公开，请勿填写 API Key 或私密内容。\n截图请先遮盖私人信息；由你在网页确认提交。";
    [self.alert addButtonWithTitle:@"关闭"];
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,450,320)];
    self.descriptionEditor=[self editorInView:content rect:NSMakeRect(0,156,450,138) label:@"遇到了什么问题？（最多 1200 字）"];
    self.environmentLabel=[NSTextField labelWithString:[NSString stringWithFormat:@"SubPop %@ · Build %@ · macOS %@ · %@",self.environment[@"version"],self.environment[@"build"],self.environment[@"macOS"],self.environment[@"architecture"]]];
    self.environmentLabel.frame=NSMakeRect(0,129,450,19);self.environmentLabel.font=[NSFont systemFontOfSize:11];self.environmentLabel.textColor=NSColor.secondaryLabelColor;[content addSubview:self.environmentLabel];
    self.screenshotPreview=[[NSImageView alloc] initWithFrame:NSMakeRect(0,63,72,56)];self.screenshotPreview.imageScaling=NSImageScaleProportionallyUpOrDown;self.screenshotPreview.hidden=YES;[self.screenshotPreview setAccessibilityLabel:@"已选择的反馈截图"];[content addSubview:self.screenshotPreview];
    self.screenshotLabel=[NSTextField labelWithString:@"截图（选填）"];self.screenshotLabel.frame=NSMakeRect(0,92,450,20);self.screenshotLabel.font=[NSFont systemFontOfSize:11];self.screenshotLabel.textColor=NSColor.secondaryLabelColor;[content addSubview:self.screenshotLabel];
    self.screenshotChooseButton=[NSButton buttonWithTitle:@"添加截图…" target:self action:@selector(chooseScreenshot:)];self.screenshotChooseButton.frame=NSMakeRect(0,63,140,28);self.screenshotChooseButton.bezelStyle=NSBezelStyleRounded;[content addSubview:self.screenshotChooseButton];
    self.screenshotCopyButton=[NSButton buttonWithTitle:@"复制截图" target:self action:@selector(copyScreenshot:)];self.screenshotCopyButton.frame=NSMakeRect(226,63,110,28);self.screenshotCopyButton.bezelStyle=NSBezelStyleRounded;[content addSubview:self.screenshotCopyButton];
    self.screenshotRemoveButton=[NSButton buttonWithTitle:@"移除" target:self action:@selector(removeScreenshot:)];self.screenshotRemoveButton.frame=NSMakeRect(344,63,106,28);self.screenshotRemoveButton.bezelStyle=NSBezelStyleRounded;[content addSubview:self.screenshotRemoveButton];
    self.status=[NSTextField wrappingLabelWithString:@""];self.status.frame=NSMakeRect(0,29,450,30);self.status.font=[NSFont systemFontOfSize:11];self.status.textColor=NSColor.secondaryLabelColor;[content addSubview:self.status];
    self.issueButton=[NSButton buttonWithTitle:@"继续到 GitHub…" target:self action:@selector(openIssue:)];self.issueButton.frame=NSMakeRect(0,0,221,28);self.issueButton.bezelStyle=NSBezelStyleRounded;[content addSubview:self.issueButton];
    self.clipboardButton=[NSButton buttonWithTitle:@"复制反馈内容" target:self action:@selector(copyFeedback:)];self.clipboardButton.frame=NSMakeRect(229,0,221,28);self.clipboardButton.bezelStyle=NSBezelStyleRounded;[content addSubview:self.clipboardButton];
    self.alert.accessoryView=content;self.alert.window.initialFirstResponder=self.descriptionEditor;[self updateScreenshotInterface];[self updateValidation];
}
- (void)showForWindow:(NSWindow *)window bundle:(NSBundle *)bundle {
    if (self.alert || !window || window.attachedSheet) return;
    [self prepareForBundle:bundle];NSAlert *currentAlert=self.alert;
    __weak typeof(self) weakSelf=self;
    [currentAlert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response){
        typeof(self) panel=weakSelf;if (!panel || panel.alert!=currentAlert) return;
        [panel clearScreenshotState];panel.alert=nil;panel.descriptionEditor=nil;
        if (panel.onClose) panel.onClose();panel.onClose=nil;
    }];
}
- (void)clearScreenshotState {
    self.screenshotGeneration++;NSOpenPanel *picker=self.openPanel;self.openPanel=nil;if (picker) [picker cancel:nil];
    self.screenshotData=nil;self.screenshotImage=nil;self.screenshotPreview.image=nil;
    [self updateScreenshotInterface];
}
- (void)close {
    [self clearScreenshotState];
    if (self.alert.window.sheetParent) [self.alert.window.sheetParent endSheet:self.alert.window];
}
- (NSString *)feedbackBody { return SubPopFeedbackBody(self.descriptionEditor.string,self.environment); }
- (void)updateScreenshotInterface {
    BOOL selected=self.screenshotData.length && self.screenshotImage;
    self.screenshotPreview.image=self.screenshotImage;self.screenshotPreview.hidden=!selected;
    self.screenshotLabel.frame=NSMakeRect(selected ? 82 : 0,92,selected ? 368 : 450,20);
    self.screenshotLabel.stringValue=selected ? @"截图已选择 · 只保存在本机" : @"截图（选填，PNG／JPEG／WebP，最多 10 MB）";
    self.screenshotChooseButton.frame=NSMakeRect(selected ? 82 : 0,63,140,28);self.screenshotChooseButton.title=selected ? @"更换截图…" : @"添加截图…";
    self.screenshotChooseButton.enabled=!self.openPanel;self.screenshotCopyButton.hidden=!selected;self.screenshotRemoveButton.hidden=!selected;
    self.screenshotCopyButton.enabled=selected && !self.openPanel;self.screenshotRemoveButton.enabled=selected && !self.openPanel;
}
- (void)updateValidation {
    NSString *message=SubPopFeedbackValidationMessage(self.descriptionEditor.string);
    self.clipboardButton.enabled=!message && !self.openPanel;self.issueButton.enabled=!message && !self.openPanel;
    BOOL longDescription=!message && !SubPopFeedbackIssueURL(self.descriptionEditor.string,self.environment);
    self.issueButton.title=longDescription ? @"复制说明并继续…" : (self.screenshotData.length ? @"复制截图并继续…" : @"继续到 GitHub…");
    self.status.stringValue=message ?: (longDescription ? (self.screenshotData.length ? @"先粘贴问题说明，再回来复制截图；提交在 GitHub 完成。" : @"说明较长，会先复制正文；请在 GitHub 粘贴并提交。") : (self.screenshotData.length ? @"继续后请在 GitHub 的截图栏按 ⌘V 上传，再确认提交。" : @"问题和环境会预填到 GitHub，由你确认提交。"));
}
- (void)textDidChange:(NSNotification *)notification { [self updateValidation]; }
- (BOOL)openFeedbackURL:(NSURL *)url { return [NSWorkspace.sharedWorkspace openURL:url]; }
- (NSPasteboard *)feedbackPasteboard { return NSPasteboard.generalPasteboard; }
- (BOOL)copyCurrentFeedback {
    NSString *body=[self feedbackBody];if (!body) return NO;
    NSPasteboard *pasteboard=[self feedbackPasteboard];[pasteboard clearContents];return [pasteboard setString:body forType:NSPasteboardTypeString];
}
- (BOOL)copyCurrentScreenshot {
    if (!self.screenshotData.length) return NO;
    NSPasteboardItem *item=[NSPasteboardItem new];
    if (![item setData:self.screenshotData forType:NSPasteboardTypePNG]) return NO;
    NSPasteboard *pasteboard=[self feedbackPasteboard];[pasteboard clearContents];return [pasteboard writeObjects:@[item]];
}
- (void)openIssue:(id)sender {
    [self updateValidation];if (!self.issueButton.enabled) return;
    NSURL *url=SubPopFeedbackIssueURL(self.descriptionEditor.string,self.environment);BOOL copiedBody=NO;BOOL copiedImage=NO;
    if (!url) {
        if (![self copyCurrentFeedback]) {self.status.stringValue=@"复制失败，未打开网页；请重试。";return;}
        copiedBody=YES;url=SubPopFeedbackShortIssueURL(self.descriptionEditor.string,self.environment);
    } else if (self.screenshotData.length) {
        if (![self copyCurrentScreenshot]) {self.status.stringValue=@"复制失败，未打开网页；请重试。";return;}
        copiedImage=YES;
    }
    if (!url || ![self openFeedbackURL:url]) {self.status.stringValue=@"无法打开浏览器，说明和截图仍保留，可重试或分别复制。";return;}
    self.status.stringValue=copiedBody ? (self.screenshotData.length ? @"说明已复制，请先在 GitHub 粘贴问题；再返回这里复制截图。" : @"说明已复制，请在 GitHub 粘贴问题并确认提交。") : (copiedImage ? @"截图已复制，请在 GitHub 的截图栏按 ⌘V 上传，再确认提交。" : @"已打开 GitHub，请在网页中确认提交。插件不会自动提交。");
}
- (void)copyFeedback:(id)sender {
    [self updateValidation];if (!self.clipboardButton.enabled) return;
    self.status.stringValue=[self copyCurrentFeedback] ? (self.screenshotData.length ? @"已复制反馈内容；截图可通过「复制截图」单独粘贴。" : @"已复制反馈内容。") : @"复制失败，请重试。";
}
- (void)copyScreenshot:(id)sender {
    if (self.openPanel || !self.screenshotData.length) return;
    self.status.stringValue=[self copyCurrentScreenshot] ? @"截图已复制，请在 GitHub 的截图栏按 ⌘V 上传。" : @"截图复制失败，请重试。";
}
- (void)removeScreenshot:(id)sender {
    if (self.openPanel) return;self.screenshotGeneration++;self.screenshotData=nil;self.screenshotImage=nil;
    [self updateScreenshotInterface];[self updateValidation];
}
- (BOOL)loadScreenshotURL:(NSURL *)url {
    if (!self.alert) return NO;
    BOOL scoped=[url startAccessingSecurityScopedResource];NSError *error=nil;NSDictionary *image=nil;
    @try {image=SubPopFeedbackScreenshotFromURL(url,&error);}
    @finally {if (scoped) [url stopAccessingSecurityScopedResource];}
    if (!image) {self.status.stringValue=error.localizedDescription ?: @"截图无法读取，请重试。";return NO;}
    self.screenshotData=image[@"data"];self.screenshotImage=image[@"image"];
    [self updateScreenshotInterface];[self updateValidation];self.status.stringValue=@"截图已选择；继续后在 GitHub 截图栏按 ⌘V 上传。";return YES;
}
- (NSOpenPanel *)newScreenshotOpenPanel { return [NSOpenPanel openPanel]; }
- (void)chooseScreenshot:(id)sender {
    if (!self.alert || self.openPanel || self.alert.window.attachedSheet) return;
    NSOpenPanel *picker=[self newScreenshotOpenPanel];self.openPanel=picker;NSUInteger generation=++self.screenshotGeneration;NSAlert *currentAlert=self.alert;
    picker.canChooseDirectories=NO;picker.canChooseFiles=YES;picker.allowsMultipleSelection=NO;picker.allowedContentTypes=SubPopFeedbackScreenshotTypes();picker.message=@"选择一张截图，提交前请遮盖私人信息";
    [self updateScreenshotInterface];[self updateValidation];__weak typeof(self) weakSelf=self;
    [picker beginSheetModalForWindow:currentAlert.window completionHandler:^(NSModalResponse response){
        typeof(self) panel=weakSelf;
        if (!panel || panel.alert!=currentAlert || panel.openPanel!=picker || panel.screenshotGeneration!=generation) return;
        panel.openPanel=nil;[panel updateScreenshotInterface];[panel updateValidation];
        if (response==NSModalResponseOK && picker.URL) [panel loadScreenshotURL:picker.URL];
    }];
}
@end
