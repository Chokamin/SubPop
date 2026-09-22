#import <Sparkle/Sparkle.h>
#import <sys/file.h>
#import <fcntl.h>
#import "Updates.h"

// Runs only in the containing application, never inside Final Cut Pro.
@interface SubPopOnlineUpdate : NSObject <SPUUpdaterDelegate>
@property SPUUpdater *updater;
@property SPUStandardUserDriver *driver;
@property NSArray<NSURL *> *sources;
@property NSUInteger sourceIndex;
@property NSString *mirror;
@property NSInteger mode;
@property int lease;
@property (copy) void (^prepareInstallation)(void);
- (void)startWithURL:(NSURL *)url;
- (void)releaseLease;
@end
@implementation SubPopOnlineUpdate
- (instancetype)init { if((self=[super init]))self.lease=-1;return self; }
- (void)dealloc { [self releaseLease]; }
- (void)releaseLease { if(self.lease>=0){flock(self.lease,LOCK_UN);close(self.lease);self.lease=-1;} }
- (void)showError:(NSString *)message {
    NSAlert *alert=[NSAlert new];alert.messageText=@"暂时无法更新";alert.informativeText=message;[NSApp activateIgnoringOtherApps:YES];[alert runModal];
}
- (void)startWithURL:(NSURL *)url {
    if(self.updater.sessionInProgress){[self.updater checkForUpdates];return;}
    NSMutableDictionary *options=[NSMutableDictionary new];
    for(NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)if(item.value)options[item.name]=item.value;
    self.mirror=SubPopUpdateMirror(options[@"mirror"]) ?: SubPopDefaultUpdateMirror;
    self.mode=[@[@"0",@"1",@"2"] containsObject:options[@"mode"]] ? [options[@"mode"] integerValue] : 0;
    self.sources=SubPopUpdateSources([NSURL URLWithString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"SUFeedURL"]],self.mirror,self.mode);self.sourceIndex=0;
    NSString *bridge=[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/verification/bridge"];
    [NSFileManager.defaultManager createDirectoryAtPath:bridge withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSData *serviceData=[NSData dataWithContentsOfFile:[bridge stringByAppendingPathComponent:@"service.json"]];
    NSDictionary *service=serviceData ? [NSJSONSerialization JSONObjectWithData:serviceData options:0 error:nil] : nil;
    if([service isKindOfClass:NSDictionary.class] && [service[@"heartbeat"] isKindOfClass:NSNumber.class] && fabs(NSDate.date.timeIntervalSince1970-[service[@"heartbeat"] doubleValue])<10 && ![service[@"updateProtocol"] isEqual:@1]) {
        [self showError:@"请先退出并重新打开 SubPop，让本机服务加载更新支持后再试。"];return;
    }
    // Same advisory lock is held by the worker throughout each recognition/model task.
    [self releaseLease];
    self.lease=open([[bridge stringByAppendingPathComponent:@"update.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
    if(self.lease<0 || flock(self.lease,LOCK_EX|LOCK_NB)!=0){[self releaseLease];[self showError:@"请等待当前识别、脚本整理或模型下载结束，再更新 SubPop。"];return;}
    if(!self.updater){
        self.driver=[[SPUStandardUserDriver alloc] initWithHostBundle:NSBundle.mainBundle delegate:nil];
        self.updater=[[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:self.driver delegate:self];
        NSError *error=nil;if(![self.updater startUpdater:&error]){self.updater=nil;[self releaseLease];[self showError:error.localizedDescription];return;}
        self.updater.automaticallyChecksForUpdates=NO;self.updater.automaticallyDownloadsUpdates=NO;self.updater.sendsSystemProfile=NO;
    }
    [NSApp activateIgnoringOtherApps:YES];[self.updater checkForUpdates];
}
- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)updater { return NO; }
- (NSArray<NSString *> *)allowedSystemProfileKeysForUpdater:(SPUUpdater *)updater { return @[]; }
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater { return self.sources[self.sourceIndex].absoluteString; }
- (BOOL)updater:(SPUUpdater *)updater shouldDownloadReleaseNotesForUpdate:(SUAppcastItem *)item { return NO; }
- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(SUAppcastItem *)item updateCheck:(SPUUpdateCheck)check error:(NSError **)error {
    NSString *version=item.displayVersionString;
    NSString *expected=[NSString stringWithFormat:@"https://github.com/Chokamin/SubPop/releases/download/v%@/SubPop-%@-arm64.pkg",version,version];
    if(!SubPopUpdateMatches(version,@"[0-9]+\\.[0-9]+\\.[0-9]+") || ![item.fileURL.absoluteString isEqual:expected]){
        if(error)*error=SubPopUpdateError(@"更新地址与 SubPop 正式发行包不符，已停止安装。");return NO;
    }
    return YES;
}
- (void)updater:(SPUUpdater *)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request {
    // The selected feed and payload use the same source. Sparkle validates Ed25519
    // before invoking its installer; a mirror cannot replace the signed payload.
    NSArray *sources=SubPopUpdateSources(item.fileURL,self.mirror,self.mode);
    request.URL=sources[MIN(self.sourceIndex,sources.count-1)];
}
- (BOOL)updater:(SPUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvokingBlock:(void (^)(void))installHandler {
    if(self.prepareInstallation)self.prepareInstallation();
    // Give the extension one polling interval to persist its draft and close its own window.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),installHandler);return YES;
}
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error {
    BOOL transport=[error.domain isEqual:SUSparkleErrorDomain] && (error.code==SUAppcastError || error.code==SUDownloadError);
    if(transport && self.sourceIndex+1<self.sources.count){
        self.sourceIndex++;
        dispatch_async(dispatch_get_main_queue(),^{[self.updater checkForUpdates];});return;
    }
    [self releaseLease];
}
@end
