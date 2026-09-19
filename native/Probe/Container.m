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
    for (NSURL *url in urls) if ([url.scheme isEqual:@"subpop-probe"]) {if ([url.host isEqual:@"start"]) [self startEngine];else if ([url.host isEqual:@"cloud-settings"]) [self showCloudSettings];else if ([url.host isEqual:@"legacy-cloud-settings"]) [self showLegacyCloudSettings];else if ([url.host isEqual:@"preview"]) [self showPreview:url];}
}
- (void)showLegacyCloudSettings {
    if (self.showingCloudSettings) return;
    self.showingCloudSettings=YES;
    NSDictionary *old=SubPopLegacyCredentials();BOOL saved=SubPopLegacyValid(old);
    NSAlert *alert=[NSAlert new];alert.messageText=@"旧版极速版 · 连接验证";
    alert.informativeText=@"填写已开通极速版的同一个应用中的 APP ID 和 Access Token。Access Token 不是 Secret Key，也不是新版 API Key。\n\n凭证只保存在此 Mac 的钥匙串。保存不会上传音频；验证时直接发送测试音频，不需要配置 TOS。当前主界面的常规云端识别仍使用标准版配置。";
    NSView *form=[[NSView alloc] initWithFrame:NSMakeRect(0,0,480,90)];
    NSTextField *appID=[[NSTextField alloc] initWithFrame:NSMakeRect(125,52,350,28)];
    NSSecureTextField *token=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(125,10,350,28)];
    appID.stringValue=old[@"appID"] ?: @"";appID.placeholderString=@"旧版控制台中的数字 APP ID";
    token.placeholderString=saved ? @"已保存 · 同一应用留空保留" : @"旧版控制台中的 Access Token";
    NSArray *fields=@[appID,token],*labels=@[@"APP ID",@"Access Token"];
    for (NSUInteger i=0;i<fields.count;i++) {
        NSTextField *field=fields[i],*label=[NSTextField labelWithString:labels[i]];
        label.frame=NSMakeRect(0,field.frame.origin.y+3,120,22);[form addSubview:label];
        [field setAccessibilityLabel:labels[i]];[form addSubview:field];
    }
    alert.accessoryView=form;
    [alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];[alert addButtonWithTitle:@"旧版控制台"];
    if (saved) [alert addButtonWithTitle:@"移除旧版凭证"];
    [NSApp activateIgnoringOtherApps:YES];NSModalResponse response=[alert runModal];self.showingCloudSettings=NO;
    if (response==NSAlertThirdButtonReturn) {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://console.volcengine.com/speech/service/10012"]];return;}
    BOOL remove=saved && response==NSAlertThirdButtonReturn+1;
    if (response!=NSAlertFirstButtonReturn && !remove) return;
    NSString *identifier=[appID.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *secret=[token.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Changing the application must never silently reuse another application's token.
    if (!secret.length && [identifier isEqual:old[@"appID"]]) secret=old[@"accessToken"] ?: @"";
    NSDictionary *value=@{@"appID":identifier,@"accessToken":secret};
    token.stringValue=@"";
    if (!remove && !SubPopLegacyValid(value)) {
        NSAlert *error=[NSAlert new];error.messageText=@"凭证未保存";error.informativeText=@"请填写数字 APP ID 和对应应用的 Access Token；更换 APP ID 时需要重新填写 Token。";[error runModal];return;
    }
    OSStatus status=SubPopSaveLegacy(remove ? nil : value);SubPopWriteCloudStatus();
    NSAlert *result=[NSAlert new];result.messageText=status==errSecSuccess ? (remove ? @"旧版凭证已移除" : @"旧版凭证已保存") : @"凭证未保存";
    result.informativeText=status==errSecSuccess ? (remove ? @"新版 API Key 和本机模型不受影响。" : @"接下来可验证旧版极速版连接。尚未验证服务权限，也未上传音频。") : @"请解锁登录钥匙串并允许 SubPop 访问，然后重新保存。";
    [result runModal];
}
- (void)openTOSConsole:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://console.volcengine.com/tos"]];
}
- (void)showCloudSettings {
    if (self.showingCloudSettings) return;
    self.showingCloudSettings=YES;
    NSAlert *alert=[NSAlert new];alert.messageText=@"豆包录音文件识别 2.0";
    BOOL saved=SubPopCloudKeyValid(SubPopCloudKey());NSDictionary *old=SubPopTOSConfig();
    alert.informativeText=@"需要开通「录音文件识别 2.0」，并准备一个私有 TOS 桶。语音 API Key 与 TOS AK/SK 是两组不同凭证，均保存在此 Mac 的钥匙串。\n\n识别时自动上传音频，通过 1 小时有效链接交给语音服务，结束后尝试删除。失败的清理将在下次云端任务重试；建议为 subpop-temp/ 设置 1 天生命周期。语音与存储均可能计费。保存只记录配置，不联网验证或创建资源。";
    NSView *form=[[NSView alloc] initWithFrame:NSMakeRect(0,0,520,244)];
    NSArray *labels=@[@"语音 API Key",@"TOS 区域",@"私有桶名称",@"TOS Access Key",@"TOS Secret Key"];
    NSMutableArray<NSTextField *> *fields=[NSMutableArray new];
    NSPopUpButton *region=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,166,365,28) pullsDown:NO];
    [region addItemsWithTitles:@[@"华北 2 · 北京",@"华东 2 · 上海",@"华南 1 · 广州"]];
    NSArray *regions=@[@"cn-beijing",@"cn-shanghai",@"cn-guangzhou"];
    NSUInteger index=[regions indexOfObject:old[@"region"] ?: @""];if (index!=NSNotFound) [region selectItemAtIndex:index];
    for (NSUInteger i=0;i<labels.count;i++) {
        CGFloat y=204-i*38;NSTextField *label=[NSTextField labelWithString:labels[i]];label.frame=NSMakeRect(0,y+4,145,22);[form addSubview:label];
        if (i==1) {[form addSubview:region];[region setAccessibilityLabel:labels[i]];continue;}
        NSTextField *field=i==2 ? [[NSTextField alloc] initWithFrame:NSMakeRect(150,y,365,28)] : [[NSSecureTextField alloc] initWithFrame:NSMakeRect(150,y,365,28)];
        field.placeholderString=i==0 ? (saved ? @"已保存 · 留空保留" : @"语音服务 API Key") : (i==2 ? @"例如 subpop-audio，不能填网址" : (old.count ? @"已保存 · 留空保留" : @"仅限此桶的子用户凭证"));
        if (i==2) field.stringValue=old[@"bucket"] ?: @"";
        [field setAccessibilityLabel:labels[i]];[form addSubview:field];[fields addObject:field];
    }
    NSButton *console=[NSButton buttonWithTitle:@"打开 TOS 控制台…" target:self action:@selector(openTOSConsole:)];console.frame=NSMakeRect(0,4,175,28);console.bezelStyle=NSBezelStyleRounded;[form addSubview:console];
    NSString *uploads=[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/cloud/uploads"];
    NSUInteger pending=0;for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:uploads error:nil]) if ([name.pathExtension isEqual:@"json"]) pending++;
    if (pending) {NSTextField *notice=[NSTextField labelWithString:[NSString stringWithFormat:@"%lu 个临时文件待清理，请检查 TOS",(unsigned long)pending]];notice.frame=NSMakeRect(185,7,330,22);notice.textColor=NSColor.systemOrangeColor;[form addSubview:notice];}
    alert.accessoryView=form;
    [alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];[alert addButtonWithTitle:@"语音服务控制台"];
    if (saved || old.count) [alert addButtonWithTitle:@"移除凭证"];
    NSInteger legacyResponse=NSAlertFirstButtonReturn+alert.buttons.count;
    [alert addButtonWithTitle:@"旧版极速版连接验证…"];
    [NSApp activateIgnoringOtherApps:YES];NSModalResponse response=[alert runModal];self.showingCloudSettings=NO;
    if (response==legacyResponse) {[self showLegacyCloudSettings];return;}
    if (response==NSAlertThirdButtonReturn) {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://console.volcengine.com/speech/new/setting/apikeys"]];return;}
    BOOL remove=(saved || old.count) && response==NSAlertThirdButtonReturn+1;
    if (response!=NSAlertFirstButtonReturn && !remove) return;
    NSString *(^trim)(NSString *)=^NSString *(NSString *text){return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];};
    NSString *key=trim(fields[0].stringValue);NSString *bucket=trim(fields[1].stringValue);
    NSString *ak=trim(fields[2].stringValue),*sk=trim(fields[3].stringValue);
    NSDictionary *tos=@{@"region":regions[region.indexOfSelectedItem],@"bucket":bucket,@"tosAccessKey":ak.length ? ak : old[@"tosAccessKey"] ?: @"",@"tosSecretKey":sk.length ? sk : old[@"tosSecretKey"] ?: @""};
    BOOL hasTOS=bucket.length || ak.length || sk.length || old.count;
    if (!remove && ((key.length && !SubPopCloudKeyValid(key)) || (hasTOS && !SubPopTOSValid(tos)) || (!key.length && !saved && !hasTOS))) {
        NSAlert *error=[NSAlert new];error.messageText=@"配置未保存";error.informativeText=@"API Key 不能包含空格。TOS 配置需要完整的区域、桶名称和 AK/SK。也可以先只保存 API Key，之后再补齐 TOS。";[error runModal];return;
    }
    OSStatus status=errSecSuccess;
    if (remove || key.length) status=SubPopSaveCloudKey(remove ? nil : key);
    if (status==errSecSuccess && (remove || hasTOS)) status=SubPopSaveTOS(remove ? nil : tos);
    for (NSTextField *field in fields) field.stringValue=@"";
    SubPopWriteCloudStatus();
    NSAlert *result=[NSAlert new];result.messageText=status==errSecSuccess ? (remove ? @"凭证已移除" : @"配置已保存") : @"配置未完全保存";
    result.informativeText=status==errSecSuccess ? (remove ? @"仍可使用本机模型。若有待清理音频，请在 TOS 控制台清理 subpop-temp/ 目录。" : (SubPopCloudCredentials() ? @"配置已齐全，尚未验证服务权限与额度。返回 SubPop 选择「豆包录音文件识别 2.0」后，确认上传即可开始。" : @"配置尚未齐全，补齐 API Key 和 TOS 后即可选择云端识别。本机模型仍可使用。")) : @"请解锁登录钥匙串并允许访问，然后重新打开设置检查并补存。";
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
