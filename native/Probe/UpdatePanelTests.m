#import "UpdatePanel.h"

// Exercise the real NSAlert presentation with a local result. No network,
// containing application, installer, or Final Cut Pro is involved.
@interface UpdatePanelFixture : SubPopUpdatePanel
@property NSUInteger checks;
@end
@implementation UpdatePanelFixture
- (void)check:(id)sender {
    self.checks++;
    self.alert.messageText=@"正在检查更新…";
    [self setBusy:YES downloading:NO];
    NSAlert *alert=self.alert;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.alert!=alert)return;
        self.releaseInfo=@{@"installer":@YES,@"newer":@YES};
        self.alert.messageText=@"发现新版本 1.5.0";
        self.alert.informativeText=@"独立测试结果，不会下载或安装。";
        [self setBusy:NO downloading:NO];
    });
}
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
    Check(panel.alert.window.firstResponder==panel.checkButton,@"opening focuses the check button");
    Check(panel.mirrorField.currentEditor==nil,@"opening does not select or edit the URL");
    Settle();
    Check(panel.alert.window.firstResponder==panel.checkButton,@"completed check preserves button focus");
    Check(panel.mirrorField.currentEditor==nil,@"completed check does not start URL editing");
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        host.releasedWhenClosed=NO;[host orderFront:nil];
        UpdatePanelFixture *panel=[UpdatePanelFixture new];
        __block NSUInteger closes=0;panel.onClose=^{closes++;};
        [panel showForWindow:host bundle:NSBundle.mainBundle];CheckInitialFocus(panel,host);

        // URL editing remains available when deliberately selected. An async
        // result must not move focus away from the user's active edit.
        [panel.mirrorField selectText:nil];
        NSText *editor=panel.mirrorField.currentEditor;
        Check(editor!=nil && panel.alert.window.firstResponder==editor,@"explicit URL editing remains available");
        [panel check:nil];Settle();
        Check(panel.alert.window.firstResponder==editor,@"check completion does not steal editing focus");
        Check([editor isKindOfClass:NSTextView.class],@"URL uses the native text editor");
        [(NSTextView *)editor insertText:@"https://example.test/" replacementRange:NSMakeRange(0,editor.string.length)];
        Check([panel.alert.window makeFirstResponder:panel.checkButton],@"button can end editing");
        Check([panel.mirrorField.stringValue isEqual:@"https://example.test/"],@"leaving the field preserves its URL");
        [panel check:nil];Settle();
        Check(panel.checks==3 && panel.alert.window.firstResponder==panel.checkButton,@"recheck retains button focus");
        [panel close];Settle();
        Check(closes==1 && panel.alert==nil && host.attachedSheet==nil,@"close completes and detaches");

        panel.onClose=^{closes++;};
        [panel showForWindow:host bundle:NSBundle.mainBundle];CheckInitialFocus(panel,host);
        [panel close];Settle();
        Check(closes==2 && host.attachedSheet==nil,@"reopened sheet closes normally");
        [host close];
        puts("Update panel: actual initial focus, async completion, deliberate URL editing, recheck, close and reopen passed.");
    }
    return 0;
}
