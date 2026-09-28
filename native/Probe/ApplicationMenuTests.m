#import "ApplicationMenu.h"

// Intercept only the final paste dispatch. The real secure field editor and
// AppKit responder chain are retained, without reading the user's clipboard.
@interface SubPopShortcutApplication : NSApplication
@property id pasteTarget;
@property NSUInteger pasteCount;
@end
@implementation SubPopShortcutApplication
- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender {
    if (action==@selector(paste:)) {self.pasteCount++;self.pasteTarget=[self targetForAction:action to:target from:sender];return self.pasteTarget!=nil;}
    return [super sendAction:action to:target from:sender];
}
@end
static void check(BOOL passed,NSString *message) {if (!passed) {NSLog(@"Application menu regression: %@",message);exit(1);}}
static NSEvent *key(NSWindow *window,NSString *text,NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:0];
}
int main(void) {
    @autoreleasepool {
        SubPopShortcutApplication *app=SubPopShortcutApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSSecureTextField *field=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(20,35,350,28)];
        field.stringValue=@"subpop-shortcut-test";
        [window.contentView addSubview:field];[window makeKeyAndOrderFront:nil];[window makeFirstResponder:field];
        NSModalSession modal=[app beginModalSessionForWindow:window];[app runModalSession:modal];
        check(window.firstResponder==field.currentEditor,@"real secure field editor has focus in modal window");
        NSEvent *paste=key(window,@"v",NSEventModifierFlagCommand);
        check(![app.mainMenu performKeyEquivalent:paste] && app.pasteCount==0,@"missing accessory menu reproduces an unhandled paste shortcut");
        SubPopInstallApplicationMenu(app);
        NSMenu *edit=[app.mainMenu itemWithTitle:@"编辑"].submenu;
        // Clipboard availability is controlled only in this fixture. Production
        // retains standard AppKit validation, including secure copy restrictions.
        edit.autoenablesItems=NO;[edit itemWithTitle:@"粘贴"].enabled=YES;
        check([app.mainMenu performKeyEquivalent:paste] && app.pasteCount==1 && app.pasteTarget==field.currentEditor,@"Command-V targets the real secure field editor during a modal session");
        check([app.mainMenu performKeyEquivalent:key(window,@"a",NSEventModifierFlagCommand)],@"Command-A is handled");
        check(field.currentEditor.selectedRange.length==field.stringValue.length,@"Command-A selects the full input");
        check(![app.mainMenu performKeyEquivalent:key(window,@"v",NSEventModifierFlagCommand|NSEventModifierFlagControl)] && app.pasteCount==1,@"unrelated modifier combinations do not paste");
        check([field isKindOfClass:NSSecureTextField.class] && [field.cell isKindOfClass:NSSecureTextFieldCell.class],@"credentials remain a native secure field");
        [app endModalSession:modal];[window orderOut:nil];app.mainMenu=nil;
        puts("Application menu: missing-menu reproduction, secure-field paste dispatch, select-all and modifier isolation passed. No system clipboard or Keychain access.");
    }
    return 0;
}
