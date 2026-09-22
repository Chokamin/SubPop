#import "Updates.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SubPopUpdatePanel : NSObject
@property NSAlert *alert;
@property NSPopUpButton *sourcePicker;
@property NSTextField *mirrorField;
@property NSTextField *status;
@property NSProgressIndicator *progress;
@property NSButton *checkButton;
@property NSButton *downloadButton;
@property SubPopUpdateClient *client;
@property NSDictionary *releaseInfo;
@property NSString *repository;
@property NSString *current;
@property NSURL *savedPackage;
@property (copy) void (^onClose)(void);
- (void)showForWindow:(NSWindow *)window bundle:(NSBundle *)bundle;
- (void)close;
@end
@implementation SubPopUpdatePanel
- (void)showForWindow:(NSWindow *)window bundle:(NSBundle *)bundle {
    self.repository=[bundle objectForInfoDictionaryKey:@"SubPopUpdateRepository"] ?: @"";
    self.current=[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0";
    self.alert=[NSAlert new];self.alert.messageText=@"检查更新";
    self.alert.informativeText=@"正在获取最新正式版本。";[self.alert addButtonWithTitle:@"关闭"];
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,430,176)];
    NSTextField *sourceLabel=[NSTextField labelWithString:@"更新来源"];sourceLabel.frame=NSMakeRect(0,147,76,22);[content addSubview:sourceLabel];
    self.sourcePicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(78,145,350,26) pullsDown:NO];
    [self.sourcePicker addItemsWithTitles:@[@"自动切换（GitHub 优先）",@"仅 GitHub",@"镜像优先（GitHub 备用）"]];
    NSInteger mode=[NSUserDefaults.standardUserDefaults integerForKey:@"updateSourceMode"];
    [self.sourcePicker selectItemAtIndex:mode>=0 && mode<=2 ? mode : 0];self.sourcePicker.target=self;self.sourcePicker.action=@selector(check:);[self.sourcePicker setAccessibilityLabel:@"更新来源"];[content addSubview:self.sourcePicker];
    NSTextField *mirrorLabel=[NSTextField labelWithString:@"镜像地址"];mirrorLabel.frame=NSMakeRect(0,112,76,22);[content addSubview:mirrorLabel];
    self.mirrorField=[[NSTextField alloc] initWithFrame:NSMakeRect(80,110,348,25)];
    self.mirrorField.stringValue=SubPopUpdateMirror([NSUserDefaults.standardUserDefaults stringForKey:@"updateMirrorURL"]) ?: SubPopDefaultUpdateMirror;
    self.mirrorField.placeholderString=SubPopDefaultUpdateMirror;self.mirrorField.font=[NSFont systemFontOfSize:12];[self.mirrorField setAccessibilityLabel:@"镜像地址"];[content addSubview:self.mirrorField];
    self.status=[NSTextField wrappingLabelWithString:@""];self.status.frame=NSMakeRect(0,70,430,32);self.status.font=[NSFont systemFontOfSize:12];self.status.textColor=NSColor.secondaryLabelColor;[content addSubview:self.status];
    self.progress=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0,51,430,6)];self.progress.style=NSProgressIndicatorStyleBar;self.progress.minValue=0;self.progress.maxValue=1;[content addSubview:self.progress];
    self.checkButton=[NSButton buttonWithTitle:@"重新检查" target:self action:@selector(check:)];self.checkButton.frame=NSMakeRect(0,4,104,32);[content addSubview:self.checkButton];
    self.downloadButton=[NSButton buttonWithTitle:@"下载安装包…" target:self action:@selector(download:)];self.downloadButton.frame=NSMakeRect(105,4,160,32);self.downloadButton.enabled=NO;[content addSubview:self.downloadButton];
    NSButton *page=[NSButton buttonWithTitle:@"GitHub 发布页" target:self action:@selector(openRelease:)];page.frame=NSMakeRect(275,4,155,32);[content addSubview:page];
    self.alert.accessoryView=content;
    __weak typeof(self) weakSelf=self;
    [self.alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response){
        typeof(self) strongSelf=weakSelf;[strongSelf.client cancel];strongSelf.client=nil;strongSelf.alert=nil;
        if(strongSelf.onClose)strongSelf.onClose();strongSelf.onClose=nil;
    }];
    [self check:nil];
}
- (void)close { [self.client cancel];if(self.alert.window.sheetParent)[self.alert.window.sheetParent endSheet:self.alert.window]; }
- (NSString *)mirror {
    NSString *value=SubPopUpdateMirror(self.mirrorField.stringValue);
    if(self.sourcePicker.indexOfSelectedItem!=1 && !value){self.status.stringValue=@"请输入 HTTPS 镜像地址，例如 https://gh-proxy.org/";return nil;}
    return value ?: SubPopDefaultUpdateMirror;
}
- (void)setBusy:(BOOL)busy downloading:(BOOL)downloading {
    self.checkButton.enabled=!downloading;self.sourcePicker.enabled=!downloading;
    self.mirrorField.enabled=!downloading && self.sourcePicker.indexOfSelectedItem!=1;
    self.downloadButton.enabled=!busy && [self.releaseInfo[@"installer"] boolValue] && ![self.releaseInfo[@"older"] boolValue];
    self.progress.hidden=!busy;
    if(!busy)[self.progress stopAnimation:nil];
}
- (void)attachProgress:(SubPopUpdateClient *)client {
    __weak typeof(self) weakSelf=self;__weak SubPopUpdateClient *weakClient=client;
    client.progress=^(NSString *text,double fraction){
        typeof(self) panel=weakSelf;if(!panel.alert || panel.client!=weakClient)return;
        panel.status.stringValue=text;panel.progress.indeterminate=fraction<0;
        if(fraction<0)[panel.progress startAnimation:nil];else{[panel.progress stopAnimation:nil];panel.progress.doubleValue=fraction;}
    };
}
- (void)check:(id)sender {
    NSString *mirror=[self mirror];if(!mirror)return;
    [NSUserDefaults.standardUserDefaults setObject:mirror forKey:@"updateMirrorURL"];
    [NSUserDefaults.standardUserDefaults setInteger:self.sourcePicker.indexOfSelectedItem forKey:@"updateSourceMode"];
    [self.client cancel];self.releaseInfo=nil;self.savedPackage=nil;self.downloadButton.title=@"下载安装包…";
    self.alert.messageText=@"正在检查更新…";self.alert.informativeText=@"连接公开更新源，不会上传项目或音频。";[self setBusy:YES downloading:NO];
    SubPopUpdateClient *client=[SubPopUpdateClient new];self.client=client;[self attachProgress:client];
    __weak typeof(self) weakSelf=self;__weak SubPopUpdateClient *weakClient=client;
    client.completion=^(NSDictionary *release,NSURL *package,NSError *error){
        typeof(self) panel=weakSelf;if(!panel.alert || panel.client!=weakClient)return;
        panel.releaseInfo=release;[panel setBusy:NO downloading:NO];panel.client=nil;
        if(error){panel.alert.messageText=@"暂时无法检查更新";panel.alert.informativeText=@"可以更换更新来源后重试，这不会影响字幕识别。";panel.status.stringValue=error.localizedDescription;return;}
        panel.status.stringValue=[@"版本信息来自 " stringByAppendingString:release[@"source"]];
        if([release[@"newer"] boolValue]) {
            panel.alert.messageText=[@"发现新版本 " stringByAppendingString:release[@"version"]];
            panel.alert.informativeText=[release[@"installer"] boolValue] ? [NSString stringWithFormat:@"当前版本 %@。下载并验证安装包后，由你打开安装。",panel.current] : @"安装包尚未就绪，请稍后重试或查看发布页。";
        } else {
            panel.alert.messageText=@"当前已是最新版本";panel.alert.informativeText=[NSString stringWithFormat:@"已安装 SubPop %@ · 最新正式版 %@",panel.current,release[@"version"]];
            panel.downloadButton.title=@"下载当前发行包…";
        }
    };
    [client checkRepository:self.repository current:self.current mirror:mirror mode:self.sourcePicker.indexOfSelectedItem];
}
- (void)openRelease:(id)sender {
    if(!SubPopUpdateMatches(self.repository,@"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"))return;
    NSURL *url=[NSURL URLWithString:self.releaseInfo[@"url"] ?: [NSString stringWithFormat:@"https://github.com/%@/releases",self.repository]];
    [NSWorkspace.sharedWorkspace openURL:url];
}
- (void)download:(id)sender {
    if(self.savedPackage){[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.savedPackage]];return;}
    NSString *mirror=[self mirror];if(!mirror || ![self.releaseInfo[@"installer"] boolValue] || self.client)return;
    NSDictionary *asset=self.releaseInfo[@"asset"];NSInteger mode=self.sourcePicker.indexOfSelectedItem;
    [NSUserDefaults.standardUserDefaults setObject:mirror forKey:@"updateMirrorURL"];
    NSSavePanel *save=[NSSavePanel savePanel];save.nameFieldStringValue=asset[@"name"];save.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"pkg"]];save.canCreateDirectories=YES;save.prompt=@"下载并保存";
    save.directoryURL=[NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    __weak typeof(self) weakSelf=self;
    [save beginSheetModalForWindow:self.alert.window completionHandler:^(NSModalResponse response){
        typeof(self) panel=weakSelf;if(response!=NSModalResponseOK || !panel.alert)return;
        NSURL *destination=save.URL;BOOL scoped=[destination startAccessingSecurityScopedResource];
        panel.alert.messageText=@"正在下载安装包…";panel.alert.informativeText=@"验证通过后保存；关闭此窗口可取消下载。";[panel setBusy:YES downloading:YES];
        SubPopUpdateClient *client=[SubPopUpdateClient new];panel.client=client;[panel attachProgress:client];__weak SubPopUpdateClient *weakClient=client;
        client.completion=^(NSDictionary *release,NSURL *package,NSError *error){
            typeof(self) active=weakSelf;NSError *saveError=error;
            if(package && active.alert && active.client==weakClient) {
                NSData *data=[NSData dataWithContentsOfURL:package options:NSDataReadingMappedIfSafe error:&saveError];
                if(data && [data writeToURL:destination options:NSDataWritingAtomic error:&saveError])active.savedPackage=destination;
            }
            if(package)[NSFileManager.defaultManager removeItemAtURL:package.URLByDeletingLastPathComponent error:nil];
            if(scoped)[destination stopAccessingSecurityScopedResource];
            if(!active.alert || active.client!=weakClient)return;
            active.client=nil;[active setBusy:NO downloading:NO];
            if(saveError){active.alert.messageText=@"安装包未保存";active.alert.informativeText=@"可以切换更新来源重试，或打开 GitHub 发布页。";active.status.stringValue=saveError.localizedDescription;return;}
            active.alert.messageText=@"安装包已保存";active.alert.informativeText=@"文件校验与 SubPop 开发者签名验证通过。打开安装包即可更新。";
            active.status.stringValue=destination.path;active.downloadButton.title=@"在 Finder 中显示";active.downloadButton.enabled=YES;
        };
        [client download:asset mirror:mirror mode:mode];
    }];
}
@end
