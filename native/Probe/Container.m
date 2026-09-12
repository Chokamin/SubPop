#import <Cocoa/Cocoa.h>
// Background model runner. The FCP extension is the only regular user window.
@interface SubPopAppDelegate : NSObject <NSApplicationDelegate>
@property NSTask *worker;
@property NSURL *workspace;
@property BOOL choosingFolder;
@end
@implementation SubPopAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification { [self startEngine]; }
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) if ([url.scheme isEqual:@"subpop-probe"] && [url.host isEqual:@"start"]) [self startEngine];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag { [self startEngine]; return NO; }
- (void)startEngine {
    if (self.worker.running || self.choosingFolder) return;
    NSString *root=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"SubPopWorkspace"];
    NSData *bookmark=[NSUserDefaults.standardUserDefaults dataForKey:@"workspaceBookmark"];
    if (bookmark) {
        BOOL stale=NO;
        NSURL *url=[NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope|NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
        if (url && !stale && [url.path.stringByStandardizingPath isEqual:root]) { [self launchAtURL:url]; return; }
    }
    self.choosingFolder=YES;
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseFiles=NO; panel.canChooseDirectories=YES; panel.allowsMultipleSelection=NO;
    panel.directoryURL=[NSURL fileURLWithPath:root]; panel.prompt=@"允许并继续";
    panel.message=@"首次使用：允许 SubPop 读取本机识别模型。请选择默认打开的 SubPop 文件夹；之后会自动在后台准备。";
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        self.choosingFolder=NO;
        if (result!=NSModalResponseOK) return;
        if (![panel.URL.path.stringByStandardizingPath isEqual:root]) return;
        NSData *data=[panel.URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
        if (data) [NSUserDefaults.standardUserDefaults setObject:data forKey:@"workspaceBookmark"];
        [self launchAtURL:panel.URL];
    }];
}
- (void)launchAtURL:(NSURL *)url {
    if (self.worker.running) return;
    self.workspace=url; [url startAccessingSecurityScopedResource];
    self.worker=[NSTask new]; self.worker.executableURL=[url URLByAppendingPathComponent:@".venv/bin/python"];
    self.worker.currentDirectoryURL=url; self.worker.arguments=@[@"-B",@"-m",@"probes.worker"];
    NSString *path=[url.path stringByAppendingPathComponent:@".subloom/worker.log"];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *log=[NSFileHandle fileHandleForWritingAtPath:path]; self.worker.standardOutput=log; self.worker.standardError=log;
    NSError *error=nil;
    if (![self.worker launchAndReturnError:&error]) NSLog(@"SubPop engine startup failed: %@",error);
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.worker.running) [self.worker terminate];
    [self.workspace stopAccessingSecurityScopedResource];
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        SubPopAppDelegate *delegate=[SubPopAppDelegate new]; app.delegate=delegate; [app run];
    }
    return 0;
}
