#import <Cocoa/Cocoa.h>

// The accessory app has no nib-created menu. AppKit needs the Edit commands
// to route keyboard equivalents to the active alert's field editor.
static void SubPopInstallApplicationMenu(NSApplication *application) {
    NSMenu *main=[NSMenu new];
    NSMenuItem *appItem=[[NSMenuItem alloc] initWithTitle:@"SubPop" action:nil keyEquivalent:@""];
    NSMenu *appMenu=[[NSMenu alloc] initWithTitle:@"SubPop"];
    [appMenu addItemWithTitle:@"退出 SubPop" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu=appMenu;[main addItem:appItem];
    NSMenuItem *editItem=[[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""];
    NSMenu *edit=[[NSMenu alloc] initWithTitle:@"编辑"];
    [edit addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo=[edit addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;
    [edit addItem:NSMenuItem.separatorItem];
    [edit addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    // Nil targets use the responder chain, retaining NSSecureTextField's
    // restrictions on copying secrets and normal modal-window validation.
    editItem.submenu=edit;[main addItem:editItem];
    application.mainMenu=main;
}
