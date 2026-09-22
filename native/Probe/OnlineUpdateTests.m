// Isolated Sparkle feed/download verification. Never installs or touches FCP.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
static SPUUpdater *Updater;
static NSString *Mode;
static void (^CancelDownload)(void);
static uint64_t Downloaded;
@interface FeedDriver : NSObject <SPUUserDriver,SPUUpdaterDelegate>
@end
@implementation FeedDriver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {exit(10);}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    if( ![item.versionString isEqual:@"82"] || ![item.displayVersionString isEqual:@"1.2.0"] || ![item.fileURL.absoluteString isEqual:@"https://github.com/Chokamin/SubPop/releases/download/v1.2.0/SubPop-1.2.0-arm64.pkg"])exit(11);
    puts("Sparkle accepted the signed 1.2.0 feed and exact official package URL.");fflush(stdout);if([Mode isEqual:@"--download"] || [Mode isEqual:@"--cancel"]){reply(SPUUserUpdateChoiceInstall);return;}
    reply(SPUUserUpdateChoiceDismiss);exit(0);
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack {NSLog(@"Unexpected no-update: %@",error);exit(12);}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack {NSLog(@"Sparkle rejected feed: %@",error);exit(13);}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancel {CancelDownload=[cancel copy];}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {Downloaded+=length;if([Mode isEqual:@"--cancel"] && Downloaded>65536 && CancelDownload){void (^cancel)(void)=CancelDownload;CancelDownload=nil;cancel();}}
- (void)showDownloadDidStartExtractingUpdate {if(![Mode isEqual:@"--download"])exit(15);printf("Sparkle completed package download (%llu bytes); stopped before installation.\n",Downloaded);exit(0);}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {exit(16);}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {exit(17);}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack {exit(18);}
- (void)dismissUpdateInstallation {if([Mode isEqual:@"--cancel"] && Downloaded>65536){puts("Sparkle download cancellation completed without installation.");exit(0);}}
- (void)showUpdateInFocus {}
- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)updater {return NO;}
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater {return NSProcessInfo.processInfo.arguments[1];}
- (BOOL)updater:(SPUUpdater *)updater shouldDownloadReleaseNotesForUpdate:(SUAppcastItem *)item {return NO;}
@end
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc<2)return 1;Mode=argc>2 ? @(argv[2]) : @"--check";[NSApplication sharedApplication];
        FeedDriver *driver=[FeedDriver new];
        Updater=[[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:driver delegate:driver];
        NSError *error=nil;if(![Updater startUpdater:&error]){NSLog(@"%@",error);return 2;}
        dispatch_async(dispatch_get_main_queue(),^{[Updater checkForUpdates];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300LL*NSEC_PER_SEC),dispatch_get_main_queue(),^{exit(19);});
        [NSApp run];
    }return 20;
}
