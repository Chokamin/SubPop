#import "UpdatePanel.h"
#import <objc/runtime.h>

// Use the real panel and NSAlert, replacing only network results and preferences.
// This executable never contacts GitHub, launches an installer, or operates FCP.
static NSUInteger Checks;
static NSUserDefaults *FixtureDefaults;
@interface NSUserDefaults (UpdatePanelFixture)
+ (NSUserDefaults *)panelFixtureDefaults;
@end
@implementation NSUserDefaults (UpdatePanelFixture)
+ (NSUserDefaults *)panelFixtureDefaults { return FixtureDefaults; }
@end
@interface SubPopUpdateClient (UpdatePanelFixture)
- (void)panelFixtureCheck:(NSString *)repository current:(NSString *)current mirror:(NSString *)mirror mode:(NSInteger)mode;
@end
@implementation SubPopUpdateClient (UpdatePanelFixture)
- (void)panelFixtureCheck:(NSString *)repository current:(NSString *)current mirror:(NSString *)mirror mode:(NSInteger)mode {
    Checks++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.completion)self.completion(@{@"installer":@YES,@"newer":@YES,@"version":@"9.0.0",@"source":@"本地测试"},nil,nil);
    });
}
@end
@interface UpdatePanelFixture : SubPopUpdatePanel @end
@implementation UpdatePanelFixture
- (void)download:(id)sender { abort(); }
- (void)openRelease:(id)sender { abort(); }
@end

static void Check(BOOL condition,NSString *message) {
    if(!condition){fprintf(stderr,"Update panel: %s\n",message.UTF8String);exit(1);}
}
static void Settle(void) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:.2];
    while(deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static void CheckInitialFocus(UpdatePanelFixture *panel,NSWindow *host) {
    Check(host.attachedSheet==panel.alert.window,@"sheet attaches to host");
    Check(!panel.mirrorField.editable && !panel.mirrorField.selectable,@"opening keeps the mirror read-only");
    Check(panel.mirrorField.currentEditor==nil,@"opening does not select or edit the URL");
    // A remote host may choose an accessory responder after beginSheet returns.
    [panel.alert.window makeFirstResponder:panel.mirrorField];
    Check(panel.mirrorField.currentEditor==nil,@"deferred focus cannot start URL editing");
    [panel.mirrorField selectText:nil];
    Check(panel.mirrorField.currentEditor==nil,@"deferred selection cannot start read-only URL editing");
    Settle();
    Check(!panel.mirrorField.editable && panel.mirrorField.currentEditor==nil,@"completed check keeps the URL read-only");
    Check(panel.mirrorEditButton.enabled && [panel.mirrorEditButton.title isEqual:@"修改"],@"manual edit action is available");
}
int main(void) {
    @autoreleasepool {
        NSString *suite=[@"com.chokamin.SubPopVerification.UpdatePanelTests." stringByAppendingString:NSUUID.UUID.UUIDString];
        FixtureDefaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        method_exchangeImplementations(class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults)),class_getClassMethod(NSUserDefaults.class,@selector(panelFixtureDefaults)));
        method_exchangeImplementations(class_getInstanceMethod(SubPopUpdateClient.class,@selector(checkRepository:current:mirror:mode:)),class_getInstanceMethod(SubPopUpdateClient.class,@selector(panelFixtureCheck:current:mirror:mode:)));
        [NSApplication sharedApplication];
        NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        host.releasedWhenClosed=NO;[host orderFront:nil];
        UpdatePanelFixture *panel=[UpdatePanelFixture new];
        __block NSUInteger closes=0;panel.onClose=^{closes++;};
        [panel showForWindow:host bundle:NSBundle.mainBundle];CheckInitialFocus(panel,host);

        Check(panel.mirrorEditButton.target==panel && panel.mirrorEditButton.action==@selector(editMirror:),@"edit button invokes the explicit editing action");
        [panel.mirrorEditButton performClick:nil];Settle();
        NSText *editor=panel.mirrorField.currentEditor;
        Check(editor!=nil && panel.alert.window.firstResponder==editor,@"explicit edit action starts native URL editing");
        Check([editor isKindOfClass:NSTextView.class],@"URL uses the native text editor");
        [(NSTextView *)editor insertText:@"https://example.test/" replacementRange:NSMakeRange(0,editor.string.length)];
        editor.selectedRange=NSMakeRange(8,7);
        [panel check:nil];Settle();
        Check(panel.alert.window.firstResponder==editor,@"async result does not steal active editing focus");
        Check([editor.string isEqual:@"https://example.test/"] && NSEqualRanges(editor.selectedRange,NSMakeRange(8,7)),@"async result preserves typed text and selection");
        [panel editMirror:panel.mirrorEditButton];
        Check(!panel.editingMirror && panel.mirrorField.currentEditor==nil,@"finish ends URL editing");
        Check([panel.mirrorField.stringValue isEqual:@"https://example.test/"],@"finishing preserves the URL");
        Check([[FixtureDefaults stringForKey:@"updateMirrorURL"] isEqual:@"https://example.test/"],@"finishing saves the validated URL");
        [panel.checkButton performClick:nil];Settle();
        Check(Checks==3 && panel.mirrorField.currentEditor==nil,@"recheck never starts editing");

        [panel editMirror:panel.mirrorEditButton];editor=panel.mirrorField.currentEditor;
        [(NSTextView *)editor insertText:@"http://invalid.test/" replacementRange:NSMakeRange(0,editor.string.length)];
        [panel editMirror:panel.mirrorEditButton];
        Check(panel.editingMirror && [panel.mirrorField.stringValue isEqual:@"http://invalid.test/"],@"invalid finish preserves the user's unfinished address");
        Check([panel.status.stringValue containsString:@"HTTPS"],@"invalid address displays validation feedback");
        [panel.sourcePicker selectItemAtIndex:1];[panel check:panel.sourcePicker];Settle();
        Check(!panel.mirrorEditButton.enabled && !panel.mirrorField.editable,@"GitHub-only disables mirror editing");
        [panel.sourcePicker selectItemAtIndex:0];[panel check:panel.sourcePicker];
        Check(panel.mirrorEditButton.enabled && !panel.mirrorField.editable,@"returning to auto restores the edit action even for an invalid address");
        [panel editMirror:panel.mirrorEditButton];editor=panel.mirrorField.currentEditor;
        [(NSTextView *)editor insertText:@"https://restored.test/" replacementRange:NSMakeRange(0,editor.string.length)];
        [panel editMirror:panel.mirrorEditButton];
        Check(!panel.editingMirror && [panel.mirrorField.stringValue isEqual:@"https://restored.test/"],@"user can correct the invalid address after switching sources");
        Check([FixtureDefaults integerForKey:@"updateSourceMode"]==0,@"finishing also saves the current update source");
        [panel setBusy:YES downloading:YES];
        Check(!panel.mirrorEditButton.enabled && !panel.mirrorField.editable,@"download blocks mirror editing");
        [panel setBusy:NO downloading:NO];
        Check(panel.mirrorEditButton.enabled && !panel.mirrorField.editable,@"download completion restores the action without editing");
        [panel close];Settle();
        Check(closes==1 && panel.alert==nil && host.attachedSheet==nil,@"close completes and detaches");

        panel.onClose=^{closes++;};
        [panel showForWindow:host bundle:NSBundle.mainBundle];CheckInitialFocus(panel,host);
        [panel editMirror:panel.mirrorEditButton];
        [panel close];Settle();
        Check(closes==2 && host.attachedSheet==nil,@"close during editing completes normally");
        [panel showForWindow:host bundle:NSBundle.mainBundle];CheckInitialFocus(panel,host);
        [panel close];Settle();[host close];
        [FixtureDefaults removePersistentDomainForName:suite];
        puts("Update panel: read-only opening, deferred focus, explicit editing, async result, validation, source changes, download, close and reopen passed.");
    }
    return 0;
}
