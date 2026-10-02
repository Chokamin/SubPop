// Exercises the real feedback serializer and offscreen AppKit panel. No FCP,
// network, general clipboard, user defaults, logs, media, or credentials.
#import "FeedbackPanel.h"

static BOOL check(BOOL value,NSString *message) {
    if (!value) fprintf(stderr,"Feedback check failed: %s\n",message.UTF8String);
    return value;
}
static NSDictionary *fixtureEnvironment(void) {
    return @{@"version":@"1.4.11",@"build":@"140",@"macOS":@"15.7.0",@"architecture":@"Apple Silicon",
             @"projectName":@"PRIVATE-PROJECT",@"path":@"/Users/private-fixture/audio.wav",@"apiKey":@"FIXTURE-SECRET",
             @"error":@"FULL-PRIVATE-ERROR",@"log":@"PRIVATE-LOG",@"text":@"PRIVATE-CAPTION"};
}
static NSDictionary *queryValues(NSURL *url) {
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if (values[item.name]) return nil;
        values[item.name]=item.value ?: @"";
    }
    return values;
}
static BOOL checkData(void) {
    NSDictionary *environment=fixtureEnvironment();
    NSString *description=@"字幕 + # & title=注入？\nhttps://example.invalid/?body=改写 😊";
    NSString *steps=@"拖入项目\n按“生成字幕”";
    NSString *expected=@"时间与声音一致";
    NSString *body=SubPopFeedbackBody(description,steps,expected,@"12.3",environment);
    if (!check([body containsString:description] && [body containsString:steps] && [body containsString:expected] && [body containsString:@"Build 140"] && [body containsString:@"15.7.0"] && [body containsString:@"12.3"],@"copy preserves user input and selected environment")) return NO;
    for (NSString *secret in @[@"PRIVATE-PROJECT",@"/Users/private-fixture",@"FIXTURE-SECRET",@"FULL-PRIVATE-ERROR",@"PRIVATE-LOG",@"PRIVATE-CAPTION"]) {
        if (!check(![body containsString:secret],@"unlisted environment values never serialize")) return NO;
    }
    NSURL *url=SubPopFeedbackIssueURL(description,steps,expected,@"12.3",environment);
    NSDictionary *query=queryValues(url);
    if (!check([url.scheme isEqual:@"https"] && [url.host isEqual:@"github.com"] && [url.path isEqual:@"/Chokamin/SubPop/issues/new"] && !url.fragment && !url.user && !url.password && !url.port,@"fixed issue destination")) return NO;
    if (!check(query.count==8 && [query[@"template"] isEqual:@"bug_report.yml"] && [query[@"problem"] isEqual:description] && [query[@"steps"] isEqual:steps] && [query[@"expected_actual"] containsString:expected] && [query[@"subpop_version"] isEqual:@"1.4.11（Build 140）"] && [query[@"fcp_version"] isEqual:@"12.3"] && !query[@"body"] && !query[@"labels"],@"only official form IDs are encoded")) return NO;
    if (!check([url.absoluteString containsString:@"%2B"] && [url.absoluteString containsString:@"%23"] && [url.absoluteString containsString:@"%26"] && ![url.absoluteString containsString:@"😊"] && [query[@"title"] isEqual:@"[问题] 字幕 + # & title=注入？"],@"reserved characters and UTF-8 safely round trip")) return NO;
    for (NSString *secret in @[@"PRIVATE-PROJECT",@"/Users/private-fixture",@"FIXTURE-SECRET",@"FULL-PRIVATE-ERROR",@"PRIVATE-LOG",@"PRIVATE-CAPTION"]) {
        if (!check(![url.absoluteString containsString:secret],@"URL never includes unlisted metadata")) return NO;
    }
    NSDictionary *missing=queryValues(SubPopFeedbackIssueURL(@"问题",@"",@"",@"",@{}));
    if (!check([missing[@"steps"] isEqual:@""] && [missing[@"expected_actual"] isEqual:@""] && [missing[@"fcp_version"] isEqual:@"不清楚"] && [missing[@"subpop_version"] isEqual:@"未知（Build 未知）"],@"missing user details remain blank for GitHub completion")) return NO;
    NSDictionary *unsafe=@{@"version":@"/Users/private-fixture",@"build":@"FIXTURE-SECRET",@"macOS":@"FULL-PRIVATE-ERROR",@"architecture":@"PRIVATE-PROJECT"};
    NSString *safeBody=SubPopFeedbackBody(@"问题",@"",@"",@"",unsafe);
    for (NSString *key in unsafe) if (!check(![safeBody containsString:unsafe[key]],@"even selected metadata is format validated")) return NO;
    if (!check(!SubPopFeedbackBody(@" \n\t",@"",@"",@"",environment) && !SubPopFeedbackIssueURL(@"",@"",@"",@"",environment),@"empty problem cannot copy or open")) return NO;
    NSString *tooLong=[@"x" stringByPaddingToLength:1201 withString:@"x" startingAtIndex:0];
    if (!check(!SubPopFeedbackBody(tooLong,@"",@"",@"",environment),@"problem length limit")) return NO;
    if (!check(!SubPopFeedbackBody(@"问题",[tooLong substringToIndex:801],@"",@"",environment),@"steps length limit")) return NO;
    if (!check(!SubPopFeedbackBody(@"问题",@"",[tooLong substringToIndex:401],@"",environment),@"expectation length limit")) return NO;
    unichar control=1;NSString *invalid=[@"问题" stringByAppendingString:[NSString stringWithCharacters:&control length:1]];
    if (!check(!SubPopFeedbackBody(invalid,@"",@"",@"",environment) && !SubPopFeedbackBody(@"问题",invalid,@"",@"",environment) && !SubPopFeedbackBody(@"问题",@"",invalid,@"",environment),@"control characters rejected")) return NO;
    if (!check(!SubPopFeedbackBody(@"问题",@"",@"",@"12.3 & bad=1",environment) && !SubPopFeedbackBody(@"问题",@"",@"",@"/Users/private-fixture",environment),@"optional FCP field is a version only")) return NO;
    NSString *unicodeLong=[@"字" stringByPaddingToLength:1200 withString:@"字" startingAtIndex:0];
    if (!check(SubPopFeedbackBody(unicodeLong,@"",@"",@"",environment)!=nil && SubPopFeedbackIssueURL(unicodeLong,@"",@"",@"",environment)==nil,@"long encoded URL keeps copy available")) return NO;
    NSDictionary *shortQuery=queryValues(SubPopFeedbackShortIssueURL(unicodeLong,@"12.3",environment));
    if (!check(shortQuery.count==5 && [shortQuery[@"template"] isEqual:@"bug_report.yml"] && !shortQuery[@"problem"] && [shortQuery[@"fcp_version"] isEqual:@"12.3"],@"long feedback uses a short metadata-only form URL")) return NO;
    NSString *emojiTitle=[[@"x" stringByPaddingToLength:69 withString:@"x" startingAtIndex:0] stringByAppendingString:@"😊尾"];
    NSString *title=queryValues(SubPopFeedbackIssueURL(emojiTitle,@"",@"",@"",environment))[@"title"];
    if (!check([title hasSuffix:@"😊"] && ![title hasSuffix:@"尾"],@"title truncation respects composed Unicode characters")) return NO;
    NSString *combined=[@"a" stringByAppendingString:[@"\u0301" stringByPaddingToLength:1000 withString:@"\u0301" startingAtIndex:0]];
    if (!check(SubPopFeedbackShortIssueURL(combined,@"",environment)!=nil && [queryValues(SubPopFeedbackShortIssueURL(combined,@"",environment))[@"title"] isEqual:@"[问题] SubPop 使用问题"],@"oversized composed Unicode title keeps short fallback usable")) return NO;
    unichar surrogate=0xD800;NSString *invalidUnicode=[NSString stringWithCharacters:&surrogate length:1];
    if (!check(!SubPopFeedbackBody(invalidUnicode,@"",@"",@"",environment) && !SubPopFeedbackIssueURL(invalidUnicode,@"",@"",@"",environment),@"malformed Unicode cannot produce a broken URL")) return NO;
    NSDictionary *actual=SubPopFeedbackEnvironment(NSBundle.mainBundle);
    if (!check(actual.count==4 && actual[@"version"] && actual[@"build"] && actual[@"macOS"] && actual[@"architecture"],@"automatic environment contains only four public values")) return NO;
    return YES;
}
@interface SubPopFeedbackTestPanel : SubPopFeedbackPanel
@property NSURL *openedURL;
@property NSUInteger openCount;
@property NSPasteboard *testPasteboard;
@property BOOL allowOpen;
@end
@implementation SubPopFeedbackTestPanel
- (BOOL)openFeedbackURL:(NSURL *)url { self.openedURL=url;self.openCount++;return self.allowOpen; }
- (NSPasteboard *)feedbackPasteboard { return self.testPasteboard; }
@end
@interface SubPopFeedbackKeyTestEditor : SubPopFeedbackEditor
@property NSMutableArray *editingActions;
@end
@implementation SubPopFeedbackKeyTestEditor
- (void)paste:(id)sender { [self.editingActions addObject:@"paste"]; }
- (void)copy:(id)sender { [self.editingActions addObject:@"copy"]; }
- (void)cut:(id)sender { [self.editingActions addObject:@"cut"]; }
- (void)selectAll:(id)sender { [self.editingActions addObject:@"selectAll"]; }
@end
static NSEvent *keyEvent(NSWindow *window,NSString *character,NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil characters:character charactersIgnoringModifiers:character isARepeat:NO keyCode:0];
}
static BOOL waitForPanelClose(SubPopFeedbackPanel *panel) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while (panel.alert && deadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return panel.alert==nil;
}
static BOOL checkPanel(void) {
    [NSApplication sharedApplication];
    SubPopFeedbackTestPanel *panel=[SubPopFeedbackTestPanel new];panel.allowOpen=YES;panel.testPasteboard=[NSPasteboard pasteboardWithUniqueName];
    [panel prepareForBundle:NSBundle.mainBundle];panel.environment=fixtureEnvironment();
    if (!check(!panel.issueButton.enabled && !panel.clipboardButton.enabled && panel.alert.accessoryView && !panel.alert.window.sheetParent,@"empty offscreen form is disabled without presenting a sheet")) return NO;
    panel.descriptionEditor.string=@"测试反馈";panel.stepsEditor.string=@"测试步骤";panel.expectedEditor.string=@"测试期望";
    [panel textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:panel.descriptionEditor]];
    if (!check(panel.issueButton.enabled && panel.clipboardButton.enabled,@"editing validates both actions")) return NO;
    [panel copyFeedback:nil];
    if (!check([[panel.testPasteboard stringForType:NSPasteboardTypeString] isEqual:[panel feedbackBody]] && panel.openCount==0 && panel.alert && !panel.alert.window.sheetParent,@"copy uses only the requested pasteboard and keeps the form open")) return NO;
    [panel openIssue:nil];
    if (!check(panel.openCount==1 && [queryValues(panel.openedURL)[@"problem"] isEqual:@"测试反馈"] && panel.alert && [panel.status.stringValue containsString:@"不会自动提交"],@"explicit submit action opens a prefilled browser URL without creating an issue")) return NO;
    panel.allowOpen=NO;[panel openIssue:nil];
    if (!check([panel.status.stringValue containsString:@"复制反馈内容"],@"browser failure offers copy")) return NO;
    panel.descriptionEditor.string=[@"字" stringByPaddingToLength:1200 withString:@"字" startingAtIndex:0];[panel updateValidation];
    if (!check(panel.issueButton.enabled && panel.clipboardButton.enabled && [panel.issueButton.title isEqual:@"复制并打开 GitHub…"],@"oversized URL clearly offers copy and open")) return NO;
    panel.allowOpen=YES;NSUInteger attempts=panel.openCount;[panel openIssue:nil];
    if (!check(panel.openCount==attempts+1 && queryValues(panel.openedURL).count==5 && [[panel.testPasteboard stringForType:NSPasteboardTypeString] isEqual:[panel feedbackBody]] && [panel.status.stringValue containsString:@"请粘贴正文"],@"explicit long-report action copies and opens metadata-only form")) return NO;
    attempts=panel.openCount;
    NSPasteboard *savedPasteboard=panel.testPasteboard;panel.testPasteboard=nil;[panel openIssue:nil];
    if (!check(panel.openCount==attempts && [panel.status.stringValue containsString:@"未打开网页"],@"copy failure does not open browser")) return NO;
    panel.testPasteboard=savedPasteboard;
    panel.descriptionEditor.string=@"";[panel updateValidation];[panel copyFeedback:nil];[panel openIssue:nil];
    if (!check(!panel.clipboardButton.enabled && !panel.issueButton.enabled && panel.openCount==attempts,@"invalid actions do not navigate")) return NO;
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,450,100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;
    SubPopFeedbackKeyTestEditor *editor=[[SubPopFeedbackKeyTestEditor alloc] initWithFrame:NSMakeRect(0,0,450,100)];editor.editingActions=[NSMutableArray array];window.contentView=editor;[window makeFirstResponder:editor];
    for (NSString *character in @[@"v",@"c",@"x",@"a"]) if (!check([window performKeyEquivalent:keyEvent(window,character,NSEventModifierFlagCommand)],@"Command editing shortcut routes through the window to feedback editor")) return NO;
    if (!check([editor.editingActions isEqual:@[@"paste",@"copy",@"cut",@"selectAll"]],@"all editing shortcuts dispatch exactly once")) return NO;
    [editor performKeyEquivalent:keyEvent(window,@"v",NSEventModifierFlagCommand|NSEventModifierFlagControl)];
    if (!check(editor.editingActions.count==4,@"unrelated modifier combination does not paste")) return NO;
    SubPopFeedbackVersionField *versionField=[[SubPopFeedbackVersionField alloc] initWithFrame:NSMakeRect(0,0,180,25)];versionField.stringValue=@"12.3";
    [window.contentView addSubview:versionField];[window makeFirstResponder:versionField];
    NSTextView *fieldEditor=(NSTextView *)versionField.currentEditor;
    if (!check([fieldEditor isKindOfClass:NSTextView.class] && window.firstResponder==fieldEditor,@"version field uses the actual AppKit field editor")) return NO;
    fieldEditor.selectedRange=NSMakeRange(0,0);
    if (!check([window performKeyEquivalent:keyEvent(window,@"a",NSEventModifierFlagCommand)] && NSEqualRanges(fieldEditor.selectedRange,NSMakeRange(0,4)),@"Command-A routes through the window to the real version field editor")) return NO;
    SubPopFeedbackTestPanel *sheetPanel=[SubPopFeedbackTestPanel new];sheetPanel.testPasteboard=panel.testPasteboard;__block NSUInteger closed=0;
    sheetPanel.onClose=^{closed++;};[sheetPanel showForWindow:window bundle:NSBundle.mainBundle];
    NSAlert *firstAlert=sheetPanel.alert;
    if (!check(firstAlert && firstAlert.window.sheetParent==window && window.attachedSheet==firstAlert.window,@"real sheet is attached to independent test parent")) return NO;
    [sheetPanel showForWindow:window bundle:NSBundle.mainBundle];
    if (!check(sheetPanel.alert==firstAlert && window.attachedSheet==firstAlert.window,@"repeat click does not create another sheet")) return NO;
    [firstAlert.buttons.firstObject performClick:nil];
    if (!check(waitForPanelClose(sheetPanel) && closed==1 && !window.attachedSheet && !sheetPanel.descriptionEditor,@"close button ends sheet and clears editor once")) return NO;
    sheetPanel.onClose=^{closed++;};[sheetPanel showForWindow:window bundle:NSBundle.mainBundle];
    if (!check(sheetPanel.alert && sheetPanel.alert!=firstAlert && window.attachedSheet==sheetPanel.alert.window,@"feedback reopens after close")) return NO;
    [sheetPanel close];
    if (!check(waitForPanelClose(sheetPanel) && closed==2 && !window.attachedSheet,@"controller teardown close ends sheet and releases its lifecycle")) return NO;
    [window close];[panel.testPasteboard releaseGlobally];return YES;
}
@interface SubPopFeedbackDemoDelegate : NSObject <NSWindowDelegate,NSApplicationDelegate>
@property SubPopFeedbackTestPanel *panel;
@end
@implementation SubPopFeedbackDemoDelegate
- (void)windowWillClose:(NSNotification *)notification { [self.panel close];[NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application { return YES; }
@end
static void showDemo(void) {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    SubPopFeedbackDemoDelegate *delegate=[SubPopFeedbackDemoDelegate new];NSApp.delegate=delegate;
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,580,450) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;window.title=@"SubPop · 独立反馈面板验证";window.delegate=delegate;window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSTextField *hint=[NSTextField wrappingLabelWithString:@"独立界面验证：不连接 FCP、不打开外部网页、不提交反馈。\n关闭此测试窗口即可结束验证。"];
    hint.frame=NSMakeRect(24,330,530,70);hint.font=[NSFont systemFontOfSize:14];[window.contentView addSubview:hint];
    SubPopFeedbackTestPanel *panel=[SubPopFeedbackTestPanel new];delegate.panel=panel;panel.allowOpen=YES;panel.testPasteboard=[NSPasteboard pasteboardWithUniqueName];
    [window center];[window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[panel showForWindow:window bundle:NSBundle.mainBundle];
    panel.environment=@{@"version":@"1.4.11",@"build":@"140",@"macOS":@"15.7.0",@"architecture":@"Apple Silicon"};
    panel.environmentLabel.stringValue=@"SubPop 1.4.11 · Build 140 · macOS 15.7.0 · Apple Silicon";
    panel.alert.informativeText=@"独立测试：不会打开网页或提交反馈。\n测试按钮只记录预填网址；复制仅写独立测试剪贴板。";
    [NSApp run];[panel.testPasteboard releaseGlobally];(void)delegate;
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc==2 && strcmp(argv[1],"--demo")==0) {showDemo();}
        else if (argc==2 && strcmp(argv[1],"--panel")==0) {
            if (!checkPanel()) return 2;
            puts("Feedback offscreen form, copy/browser recovery and editing shortcuts: passed");
        } else {
            if (!checkData()) return 1;
            puts("Feedback form URL, Unicode encoding, metadata privacy and validation: passed");
        }
    }
    return 0;
}
