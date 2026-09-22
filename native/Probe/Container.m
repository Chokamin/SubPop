#import <Cocoa/Cocoa.h>
#import "RuntimePaths.h"
#import "CloudSettings.h"
#import "OnlineUpdate.h"
// Background model runner and independent fullscreen preview host.
@interface SubPopFullscreenWindow : NSWindow
@end
@implementation SubPopFullscreenWindow
- (BOOL)canBecomeKeyWindow {return YES;}
@end
@interface SubPopAppDelegate : NSObject <NSApplicationDelegate>
@property NSTask *worker;
@property SubPopOnlineUpdate *onlineUpdate;
@property NSURL *workspace;
@property BOOL choosingFolder;
@property NSWindow *previewWindow;
@property BOOL showingCloudSettings;
@end
@implementation SubPopAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSFileManager.defaultManager removeItemAtPath:[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/verification/bridge/update-installing.json"] error:nil];
    SubPopWriteCloudStatus();[self startEngine];
}
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) if ([url.scheme isEqual:@"subpop-probe"]) {if ([url.host isEqual:@"start"]) [self startEngine];else if ([url.host isEqual:@"update"]) [self showOnlineUpdate:url];else if ([url.host isEqual:@"cloud-settings"]) [self showCloudSettings];else if ([url.host isEqual:@"preview"]) [self showPreview:url];}
}
- (void)showOnlineUpdate:(NSURL *)url {
    if(!self.onlineUpdate){
        self.onlineUpdate=[SubPopOnlineUpdate new];
        __weak typeof(self) weakSelf=self;
        self.onlineUpdate.prepareInstallation=^{
            NSString *path=[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/verification/bridge/update-installing.json"];
            NSDictionary *state=@{@"timestamp":@(NSDate.date.timeIntervalSince1970),@"pid":@(NSProcessInfo.processInfo.processIdentifier)};
            [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:path atomically:YES];
            [weakSelf.previewWindow close];
        };
    }
    [self.onlineUpdate startWithURL:url];
}
- (void)showCloudSettings {
    if (self.showingCloudSettings) return;
    self.showingCloudSettings=YES;
    BOOL saved=SubPopCloudKeyValid(SubPopCloudKey());
    NSAlert *alert=[NSAlert new];alert.messageText=@"豆包录音文件识别 2.0";
    alert.informativeText=@"开通「录音文件识别 2.0」后，填入语音服务 API Key 即可。密钥保存在此 Mac 的钥匙串。\n\n识别时音频直接发送给火山引擎，费用由你的账户结算。保存不会上传音频，也不会验证服务权限或额度。";
    NSView *form=[[NSView alloc] initWithFrame:NSMakeRect(0,0,440,50)];
    NSTextField *label=[NSTextField labelWithString:@"API Key"];label.frame=NSMakeRect(0,19,85,22);[form addSubview:label];
    NSSecureTextField *field=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(90,16,350,28)];
    field.placeholderString=saved ? @"•••••••• 已保存；留空保留" : @"粘贴语音服务 API Key";
    field.toolTip=saved ? @"API Key 已保存；留空保留，输入新 Key 可替换。" : @"填写火山引擎语音服务 API Key。";
    [field setAccessibilityHelp:field.toolTip];
    [field setAccessibilityLabel:@"语音 API Key"];[form addSubview:field];
    // Keep a migration notice only for older builds with outstanding uploads.
    NSString *uploads=[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/cloud/uploads"];
    NSUInteger pending=0;for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:uploads error:nil]) if ([name.pathExtension isEqual:@"json"]) pending++;
    if (pending) alert.informativeText=[alert.informativeText stringByAppendingString:@"\n\n旧版仍有临时音频待清理，请到原 TOS 桶删除 subpop-temp/ 中的文件。新识别不会使用该桶。"];
    alert.accessoryView=form;
    [alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];[alert addButtonWithTitle:@"获取 API Key"];
    if (saved) [alert addButtonWithTitle:@"移除 API Key"];
    [NSApp activateIgnoringOtherApps:YES];NSModalResponse response=[alert runModal];self.showingCloudSettings=NO;
    if (response==NSAlertThirdButtonReturn) {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://console.volcengine.com/speech/new/setting/apikeys"]];return;}
    BOOL remove=saved && response==NSAlertThirdButtonReturn+1;
    if (response!=NSAlertFirstButtonReturn && !remove) return;
    NSString *key=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];field.stringValue=@"";
    if (!remove && ((key.length && !SubPopCloudKeyValid(key)) || (!key.length && !saved))) {
        NSAlert *error=[NSAlert new];error.messageText=@"API Key 未保存";error.informativeText=@"请填写有效的语音服务 API Key，不能包含空格。";[error runModal];return;
    }
    OSStatus status=errSecSuccess;
    if (remove || key.length) status=SubPopSaveCloudKey(remove ? nil : key);
    SubPopWriteCloudStatus();
    NSAlert *result=[NSAlert new];result.messageText=status==errSecSuccess ? (remove ? @"API Key 已移除" : @"API Key 已保存") : @"API Key 未保存";
    result.informativeText=status==errSecSuccess ? (remove ? @"仍可使用本机模型。" : @"返回 SubPop 选择「豆包录音文件识别 2.0」，确认上传后即可开始识别。") : @"请解锁登录钥匙串并允许 SubPop 访问，然后重新保存。";
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
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if(self.onlineUpdate) {
        NSData *data=[NSData dataWithContentsOfFile:[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/verification/bridge/service.json"]];
        NSDictionary *service=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if([service isKindOfClass:NSDictionary.class] && [service[@"status"] isEqual:@"busy"] && fabs(NSDate.date.timeIntervalSince1970-[service[@"heartbeat"] doubleValue])<10) {
            [self.onlineUpdate showError:@"当前任务仍在进行，请等待完成后再安装并重启 SubPop。"];return NSTerminateCancel;
        }
    }
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.worker.running) {[self.worker terminate];[self.worker waitUntilExit];}
    [self.workspace stopAccessingSecurityScopedResource];
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc==2 && strcmp(argv[1],"--doubao-legacy-credentials")==0) {
            if (isatty(STDOUT_FILENO)) return 2;
            NSDictionary *value=SubPopLegacyCredentials();if (!SubPopLegacyValid(value)) return 3;
            [NSFileHandle.fileHandleWithStandardOutput writeData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil]];return 0;
        }
        if (argc==2 && strcmp(argv[1],"--doubao-credentials")==0) {
            if (isatty(STDOUT_FILENO)) return 2;
            NSDictionary *value=SubPopCloudCredentials();if (!value) return 3;
            NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
            [NSFileHandle.fileHandleWithStandardOutput writeData:data];return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        SubPopAppDelegate *delegate=[SubPopAppDelegate new]; app.delegate=delegate; [app run];
    }
    return 0;
}
