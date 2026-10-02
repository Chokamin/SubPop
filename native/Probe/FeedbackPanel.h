#import <Cocoa/Cocoa.h>
#import "Feedback.h"

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
@interface SubPopFeedbackVersionField : NSTextField
@end
@implementation SubPopFeedbackVersionField
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSTextView *editor=(NSTextView *)self.currentEditor;
    if ([editor isKindOfClass:NSTextView.class] && self.window.firstResponder==editor && SubPopFeedbackHandleEditingKey(editor,event)) return YES;
    return [super performKeyEquivalent:event];
}
@end

@interface SubPopFeedbackPanel : NSObject <NSTextViewDelegate,NSTextFieldDelegate>
@property NSAlert *alert;
@property NSTextView *descriptionEditor;
@property NSTextView *stepsEditor;
@property NSTextView *expectedEditor;
@property NSTextField *fcpVersionField;
@property NSTextField *environmentLabel;
@property NSTextField *status;
@property NSButton *issueButton;
@property NSButton *clipboardButton;
@property NSDictionary *environment;
@property (copy) void (^onClose)(void);
- (void)showForWindow:(NSWindow *)window bundle:(NSBundle *)bundle;
- (void)close;
@end

@implementation SubPopFeedbackPanel
- (NSTextView *)editorInView:(NSView *)view rect:(NSRect)rect label:(NSString *)label {
    NSTextField *heading=[NSTextField labelWithString:label];heading.frame=NSMakeRect(0,NSMaxY(rect)+5,450,20);heading.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];[view addSubview:heading];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:rect];scroll.hasVerticalScroller=YES;scroll.borderType=NSBezelBorder;
    NSTextView *editor=[[SubPopFeedbackEditor alloc] initWithFrame:NSMakeRect(0,0,rect.size.width-18,rect.size.height)];
    editor.richText=NO;editor.importsGraphics=NO;editor.font=[NSFont systemFontOfSize:13];editor.textContainerInset=NSMakeSize(8,8);
    editor.verticallyResizable=YES;editor.horizontallyResizable=NO;editor.autoresizingMask=NSViewWidthSizable;editor.textContainer.widthTracksTextView=YES;editor.delegate=self;
    editor.automaticTextReplacementEnabled=NO;editor.automaticSpellingCorrectionEnabled=NO;
    if (@available(macOS 15.2,*)) editor.writingToolsBehavior=NSWritingToolsBehaviorNone;
    [editor setAccessibilityLabel:label];scroll.documentView=editor;[view addSubview:scroll];return editor;
}
- (void)prepareForBundle:(NSBundle *)bundle {
    self.environment=SubPopFeedbackEnvironment(bundle);
    self.alert=[NSAlert new];self.alert.messageText=@"问题反馈";
    self.alert.informativeText=@"GitHub 反馈是公开的，请勿填写 API Key 或私密内容。\n打开网页后由你确认提交；不会自动附加日志、项目或媒体。";
    [self.alert addButtonWithTitle:@"关闭"];
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,450,402)];
    self.descriptionEditor=[self editorInView:content rect:NSMakeRect(0,286,450,90) label:@"遇到的问题（必填，最多 1200 字）"];
    self.stepsEditor=[self editorInView:content rect:NSMakeRect(0,201,450,55) label:@"复现步骤（选填，最多 800 字）"];
    self.expectedEditor=[self editorInView:content rect:NSMakeRect(0,116,450,55) label:@"期望结果（选填，最多 400 字）"];
    NSTextField *fcpLabel=[NSTextField labelWithString:@"FCP 版本（选填）"];fcpLabel.frame=NSMakeRect(0,84,130,23);fcpLabel.font=[NSFont systemFontOfSize:12];[content addSubview:fcpLabel];
    self.fcpVersionField=[[SubPopFeedbackVersionField alloc] initWithFrame:NSMakeRect(134,82,316,25)];self.fcpVersionField.placeholderString=@"例如 12.3";self.fcpVersionField.delegate=self;
    self.fcpVersionField.automaticTextCompletionEnabled=NO;if (@available(macOS 15.2,*)) self.fcpVersionField.allowsWritingTools=NO;
    [self.fcpVersionField setAccessibilityLabel:@"FCP 版本（选填）"];[content addSubview:self.fcpVersionField];
    self.environmentLabel=[NSTextField labelWithString:[NSString stringWithFormat:@"SubPop %@ · Build %@ · macOS %@ · %@",self.environment[@"version"],self.environment[@"build"],self.environment[@"macOS"],self.environment[@"architecture"]]];
    self.environmentLabel.frame=NSMakeRect(0,57,450,19);self.environmentLabel.font=[NSFont systemFontOfSize:11];self.environmentLabel.textColor=NSColor.secondaryLabelColor;[content addSubview:self.environmentLabel];
    self.status=[NSTextField wrappingLabelWithString:@"请填写问题，或复制反馈内容通过其他渠道发送。"];self.status.frame=NSMakeRect(0,28,450,25);self.status.font=[NSFont systemFontOfSize:11];self.status.textColor=NSColor.secondaryLabelColor;[content addSubview:self.status];
    self.issueButton=[NSButton buttonWithTitle:@"在 GitHub 提交…" target:self action:@selector(openIssue:)];self.issueButton.frame=NSMakeRect(0,0,221,28);self.issueButton.bezelStyle=NSBezelStyleRounded;[content addSubview:self.issueButton];
    self.clipboardButton=[NSButton buttonWithTitle:@"复制反馈内容" target:self action:@selector(copyFeedback:)];self.clipboardButton.frame=NSMakeRect(229,0,221,28);self.clipboardButton.bezelStyle=NSBezelStyleRounded;[content addSubview:self.clipboardButton];
    self.alert.accessoryView=content;self.alert.window.initialFirstResponder=self.descriptionEditor;[self updateValidation];
}
- (void)showForWindow:(NSWindow *)window bundle:(NSBundle *)bundle {
    if (self.alert || !window || window.attachedSheet) return;
    [self prepareForBundle:bundle];
    __weak typeof(self) weakSelf=self;
    [self.alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response){
        typeof(self) panel=weakSelf;panel.alert=nil;panel.descriptionEditor=nil;panel.stepsEditor=nil;panel.expectedEditor=nil;panel.fcpVersionField=nil;
        if (panel.onClose) panel.onClose();panel.onClose=nil;
    }];
}
- (void)close { if (self.alert.window.sheetParent) [self.alert.window.sheetParent endSheet:self.alert.window]; }
- (NSString *)feedbackBody {
    return SubPopFeedbackBody(self.descriptionEditor.string,self.stepsEditor.string,self.expectedEditor.string,self.fcpVersionField.stringValue,self.environment);
}
- (void)updateValidation {
    NSString *message=SubPopFeedbackValidationMessage(self.descriptionEditor.string,self.stepsEditor.string,self.expectedEditor.string,self.fcpVersionField.stringValue);
    self.clipboardButton.enabled=!message;
    BOOL urlReady=!message && SubPopFeedbackIssueURL(self.descriptionEditor.string,self.stepsEditor.string,self.expectedEditor.string,self.fcpVersionField.stringValue,self.environment)!=nil;
    self.issueButton.enabled=!message;
    self.issueButton.title=!message && !urlReady ? @"复制并打开 GitHub…" : @"在 GitHub 提交…";
    self.status.stringValue=message ?: (urlReady ? @"复现步骤和预期可在 GitHub 补充；提交前仍可修改。" : @"内容较长：点击后复制正文，再在 GitHub 表单粘贴。");
}
- (void)textDidChange:(NSNotification *)notification { [self updateValidation]; }
- (void)controlTextDidChange:(NSNotification *)notification { [self updateValidation]; }
- (BOOL)openFeedbackURL:(NSURL *)url { return [NSWorkspace.sharedWorkspace openURL:url]; }
- (NSPasteboard *)feedbackPasteboard { return NSPasteboard.generalPasteboard; }
- (BOOL)copyCurrentFeedback {
    NSString *body=[self feedbackBody];if (!body) return NO;
    NSPasteboard *pasteboard=[self feedbackPasteboard];[pasteboard clearContents];
    return [pasteboard setString:body forType:NSPasteboardTypeString];
}
- (void)openIssue:(id)sender {
    [self updateValidation];if (!self.issueButton.enabled) return;
    NSURL *url=SubPopFeedbackIssueURL(self.descriptionEditor.string,self.stepsEditor.string,self.expectedEditor.string,self.fcpVersionField.stringValue,self.environment);
    BOOL copied=NO;
    if (!url) {
        if (![self copyCurrentFeedback]) {self.status.stringValue=@"复制失败，未打开网页；请重试。";return;}
        copied=YES;url=SubPopFeedbackShortIssueURL(self.descriptionEditor.string,self.fcpVersionField.stringValue,self.environment);
    }
    if (!url || ![self openFeedbackURL:url]) { self.status.stringValue=@"无法打开浏览器，可以复制反馈内容后发送。";return; }
    self.status.stringValue=copied ? @"已复制并打开 GitHub，请粘贴正文并在网页确认提交。" : @"已打开 GitHub；请在网页中确认提交，插件不会自动提交。";
}
- (void)copyFeedback:(id)sender {
    [self updateValidation];if (!self.clipboardButton.enabled) return;
    self.status.stringValue=[self copyCurrentFeedback] ? @"已复制反馈内容，可通过其他渠道发送。" : @"复制失败，请重试。";
}
@end
