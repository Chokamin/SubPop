#import <Cocoa/Cocoa.h>
@interface SubPopAppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSTask *worker;
@end
@implementation SubPopAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,460,180)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"SubPop 接入探针";
    NSTextField *label = [NSTextField wrappingLabelWithString:@"在 Final Cut Pro 的扩展菜单打开 SubPop Probe。\n选择工作目录后，本窗口运行本机识别服务；保持应用打开。扩展首次连接任务目录后，可提交项目快照并自动取得 Title。"];
    label.frame = NSMakeRect(24,40,412,100);
    [self.window.contentView addSubview:label];
    NSButton *start=[NSButton buttonWithTitle:@"选择 SubPop 工作目录并启动服务" target:self action:@selector(startService:)];
    start.frame=NSMakeRect(24,12,412,32); [self.window.contentView addSubview:start];
    [self.window center]; [self.window makeKeyAndOrderFront:nil];
}
- (void)startService:(id)sender {
    if (self.worker.running) return;
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseFiles=NO; panel.canChooseDirectories=YES; panel.allowsMultipleSelection=NO;
    panel.message=@"选择当前 SubPop 项目目录，启动本机识别服务";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result!=NSModalResponseOK) return;
        NSString *root=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"SubPopWorkspace"];
        if (![panel.URL.path.stringByStandardizingPath isEqual:root]) return;
        [panel.URL startAccessingSecurityScopedResource];
        self.worker=[NSTask new]; self.worker.executableURL=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@".venv/bin/python"]];
        self.worker.currentDirectoryURL=panel.URL; self.worker.arguments=@[@"-B",@"-m",@"probes.worker"];
        NSString *path=[root stringByAppendingPathComponent:@".subloom/worker.log"];
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *log=[NSFileHandle fileHandleForWritingAtPath:path]; self.worker.standardOutput=log; self.worker.standardError=log;
        NSError *error=nil; if (![self.worker launchAndReturnError:&error]) NSLog(@"SubPop worker: %@",error);
    }];
}
- (void)applicationWillTerminate:(NSNotification *)notification { if (self.worker.running) [self.worker terminate]; }
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
