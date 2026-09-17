#import <Cocoa/Cocoa.h>
#import "RuntimePaths.h"
// Background model runner and independent fullscreen preview host.
@interface SubPopFullscreenWindow : NSWindow
@end
@implementation SubPopFullscreenWindow
- (BOOL)canBecomeKeyWindow {return YES;}
@end
@interface SubPopAppDelegate : NSObject <NSApplicationDelegate>
@property NSTask *worker;
@property NSURL *workspace;
@property BOOL choosingFolder;
@property NSWindow *previewWindow;
@end
@implementation SubPopAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification { [self startEngine]; }
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) if ([url.scheme isEqual:@"subpop-probe"]) {if ([url.host isEqual:@"start"]) [self startEngine];else if ([url.host isEqual:@"preview"]) [self showPreview:url];}
}
- (void)showPreview:(NSURL *)url {
    NSString *path=nil;for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) if ([item.name isEqual:@"file"]) path=item.value;
    struct passwd *entry=getpwuid(getuid());if (!entry || !path) return;
    NSString *root=[[NSString stringWithUTF8String:entry->pw_dir] stringByAppendingPathComponent:@"Library/Containers/com.chokamin.SubPopProbe.Extension/Data/Library/Caches/SubPopPreview"];
    if (![path.stringByDeletingLastPathComponent.stringByStandardizingPath isEqual:root] || ![path.pathExtension isEqual:@"png"] || ![[NSUUID alloc] initWithUUIDString:path.lastPathComponent.stringByDeletingPathExtension]) return;
    NSImage *image=[[NSImage alloc] initWithContentsOfFile:path];if (!image) return;
    // Decode before removing the transient frame. Nothing is uploaded or retained.
    NSImage *decoded=[[NSImage alloc] initWithData:image.TIFFRepresentation];[NSFileManager.defaultManager removeItemAtPath:path error:nil];if (!decoded) return;
    [self.previewWindow close];
    NSScreen *screen=NSScreen.mainScreen;
    NSWindow *window=[[SubPopFullscreenWindow alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];window.releasedWhenClosed=NO;window.backgroundColor=NSColor.blackColor;window.level=NSPopUpMenuWindowLevel+1;
    window.collectionBehavior=NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,screen.frame.size.width,screen.frame.size.height)];
    NSImageView *view=[[NSImageView alloc] initWithFrame:content.bounds];view.image=decoded;view.imageScaling=NSImageScaleProportionallyUpOrDown;view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[content addSubview:view];
    NSButton *close=[NSButton buttonWithTitle:@"退出全屏" target:self action:@selector(closePreview:)];close.bezelStyle=NSBezelStyleRounded;close.bordered=YES;close.frame=NSMakeRect(content.bounds.size.width-150,content.bounds.size.height-48,134,30);close.keyEquivalent=@"\033";close.keyEquivalentModifierMask=0;close.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;[content addSubview:close];
    window.contentView=content;self.previewWindow=window;
    [NSApp activateIgnoringOtherApps:YES];[window makeKeyAndOrderFront:nil];[window orderFrontRegardless];
}
- (void)closePreview:(id)sender {
    [self.previewWindow orderOut:nil];[self.previewWindow close];self.previewWindow=nil;
    [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.FinalCut"].firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag { [self startEngine]; return NO; }
- (void)startEngine {
    if (self.worker.running || self.choosingFolder) return;
    NSString *root=SubPopWorkspace(NSBundle.mainBundle);
    if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"SubPopPackagedRuntime"] boolValue]) {
        NSError *error=nil;
        NSString *bridge=[root stringByAppendingPathComponent:@".subloom/verification/bridge"];
        if (![NSFileManager.defaultManager createDirectoryAtPath:bridge withIntermediateDirectories:YES attributes:nil error:&error]) { NSLog(@"SubPop data directory: %@",error);return; }
        [self launchAtURL:[NSURL fileURLWithPath:root]];return;
    }
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
    if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"SubPopPackagedRuntime"] boolValue]) {
        NSURL *runtime=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Runtime"];
        self.worker.executableURL=[runtime URLByAppendingPathComponent:@".venv/bin/python3.12"];
        NSMutableDictionary *env=NSProcessInfo.processInfo.environment.mutableCopy;
        env[@"SUBPOP_DATA_ROOT"]=url.path;env[@"PYTHONPATH"]=runtime.path;env[@"PYTHONNOUSERSITE"]=@"1";
        env[@"NUMBA_CACHE_DIR"]=[url.path stringByAppendingPathComponent:@"cache/numba"];
        self.worker.environment=env;
    }
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
