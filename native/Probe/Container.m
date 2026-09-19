#import <Cocoa/Cocoa.h>
#import "RuntimePaths.h"
#import "CloudSettings.h"
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
@property BOOL showingCloudSettings;
@end
@implementation SubPopAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification { SubPopWriteCloudStatus(); [self startEngine]; }
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) if ([url.scheme isEqual:@"subpop-probe"]) {if ([url.host isEqual:@"start"]) [self startEngine];else if ([url.host isEqual:@"cloud-settings"]) [self showCloudSettings];else if ([url.host isEqual:@"preview"]) [self showPreview:url];}
}
- (void)showCloudSettings {
    if (self.showingCloudSettings) return;
    self.showingCloudSettings=YES;
    NSAlert *alert=[NSAlert new];alert.messageText=@"豆包云端识别";
    BOOL saved=SubPopCloudKeyValid(SubPopCloudKey());
    alert.informativeText=@"请在火山引擎开通“录音文件极速版”，填写豆包语音新版控制台的 API Key（不是方舟聊天模型密钥）。\n\n密钥仅保存在此 Mac 的钥匙串。保存不会调用接口，也不验证额度。云端识别会上传所选音频并由火山引擎计费；本机模型不受影响。";
    NSSecureTextField *field=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,460,28)];
    field.placeholderString=saved ? @"已配置 · 输入新密钥可替换" : @"粘贴豆包语音 API Key";
    [field setAccessibilityLabel:@"豆包语音 API Key"];alert.accessoryView=field;
    [alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];[alert addButtonWithTitle:@"开通与获取密钥"];
    if (saved) [alert addButtonWithTitle:@"移除密钥"];
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response=[alert runModal];self.showingCloudSettings=NO;
    if (response==NSAlertThirdButtonReturn) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://console.volcengine.com/speech/new/setting/apikeys"]];return;
    }
    BOOL remove=saved && response==NSAlertThirdButtonReturn+1;
    if (response!=NSAlertFirstButtonReturn && !remove) return;
    NSString *key=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!remove && !key.length && saved) return;
    if (!remove && !SubPopCloudKeyValid(key)) {
        NSAlert *error=[NSAlert new];error.messageText=@"密钥未保存";error.informativeText=@"请输入完整的 API Key，不能包含空格或换行。";[error runModal];return;
    }
    OSStatus status=SubPopSaveCloudKey(remove ? nil : key);field.stringValue=@"";
    SubPopWriteCloudStatus();
    NSAlert *result=[NSAlert new];result.messageText=status==errSecSuccess ? (remove ? @"密钥已移除" : @"密钥已保存") : @"无法保存密钥";
    result.informativeText=status==errSecSuccess ? (remove ? @"之后仍可使用本机模型。" : @"返回 SubPop，在模型列表中选择“豆包云端识别”。首次识别前请确认已开通服务并有可用额度。") : @"请解锁登录钥匙串，并允许 SubPop 访问后重试。";
    [result runModal];
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
    NSMutableDictionary *workerEnv=(self.worker.environment ?: NSProcessInfo.processInfo.environment).mutableCopy;
    workerEnv[@"SUBPOP_CONTAINER_EXECUTABLE"]=NSBundle.mainBundle.executablePath;self.worker.environment=workerEnv;
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
        if (argc==2 && strcmp(argv[1],"--doubao-key")==0) {
            if (isatty(STDOUT_FILENO)) return 2;
            NSString *key=SubPopCloudKey();if (!SubPopCloudKeyValid(key)) return 3;
            NSData *data=[key dataUsingEncoding:NSUTF8StringEncoding];
            [NSFileHandle.fileHandleWithStandardOutput writeData:data];return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        SubPopAppDelegate *delegate=[SubPopAppDelegate new]; app.delegate=delegate; [app run];
    }
    return 0;
}
