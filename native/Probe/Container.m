#import <Cocoa/Cocoa.h>
@interface SubPopAppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@end
@implementation SubPopAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,460,180)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"SubPop 接入探针";
    NSTextField *label = [NSTextField wrappingLabelWithString:@"在 Final Cut Pro 的扩展菜单打开 SubPop Probe。\n面板读取宿主信息与拖入的 XML；拖出测试 Title 可交由 FCP 插入隔离测试项目。"];
    label.frame = NSMakeRect(24,40,412,100);
    [self.window.contentView addSubview:label];
    [self.window center]; [self.window makeKeyAndOrderFront:nil];
}
@end
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        SubPopAppDelegate *delegate = [SubPopAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
