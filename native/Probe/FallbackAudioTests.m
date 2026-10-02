// Exercise the real background importer without a panel, FCP, or ASR.
#import "ProbeViewController.m"
#import <pthread.h>

@interface SubPopFallbackAudioController : SubPopProbeViewController
@property NSURL *testDirectory;
@property NSUInteger continuationCount;
@property BOOL continuedOnMain;
@property NSDictionary *lastRecord;
@property BOOL pauseHash;
@property dispatch_semaphore_t hashEntered;
@property dispatch_semaphore_t hashContinue;
@end
@implementation SubPopFallbackAudioController
- (NSURL *)evidenceDirectory { return self.testDirectory; }
- (BOOL)isolatedProjectActive { return YES; }
- (void)updateInterface {}
- (void)record:(NSDictionary *)value { self.lastRecord=value; }
- (void)startWorkerJob:(id)sender {
    self.continuationCount++;
    self.continuedOnMain=NSThread.isMainThread;
}
- (NSString *)sha256File:(NSURL *)url {
    if (self.pauseHash) {
        dispatch_semaphore_signal(self.hashEntered);
        if (dispatch_semaphore_wait(self.hashContinue,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))) return nil;
    }
    return [super sha256File:url];
}
@end

static void check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"Fallback audio regression: %@",message);exit(1); }
}
static NSData *bytes(NSUInteger length) {
    NSMutableData *data=[NSMutableData dataWithLength:length];
    uint8_t *value=data.mutableBytes;
    for (NSUInteger index=0;index<length;index++) value[index]=(uint8_t)((index*29+index/251)%256);
    return data;
}
static NSString *expectedSHA(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *result=[NSMutableString new];
    for (NSUInteger index=0;index<sizeof(digest);index++) [result appendFormat:@"%02x",digest[index]];
    return result;
}
static void writeFixture(NSURL *url, NSData *data) {
    check([data writeToURL:url options:NSDataWritingAtomic error:nil],@"write isolated fixture");
}
static SubPopFallbackAudioController *controller(NSURL *directory) {
    check([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil],@"create isolated evidence directory");
    SubPopFallbackAudioController *value=[SubPopFallbackAudioController new];
    value.testDirectory=directory;value.freshDropURL=[directory URLByAppendingPathComponent:@"project.fcpxml"];
    value.freshDropDate=NSDate.date;value.dropUID=@"fallback-project-a";value.dropDuration=CMTimeMake(13,1);
    value.displayState=@"error";value.visibleError=@"直接读取失败";
    return value;
}
static void settle(BOOL (^done)(void)) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while (!done() && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    check(done(),@"background importer completes within its deadline");
}
static NSArray<NSURL *> *fallbackFiles(NSURL *directory) {
    NSMutableArray *files=[NSMutableArray new];
    for (NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil])
        if ([url.lastPathComponent hasPrefix:@"fallback-"]) [files addObject:url];
    return files;
}
static void hashTests(NSURL *directory) {
    SubPopFallbackAudioController *value=controller([directory URLByAppendingPathComponent:@"hash-evidence"]);
    // The original 1 MB stack allocation crashed on this actual GCD worker.
    // Multiple full blocks plus a tail prove the streaming hash stays exact.
    NSMutableArray *urls=[NSMutableArray new],*expected=[NSMutableArray new];
    for (NSNumber *length in @[@(1024*1024+17),@(3*1024*1024+65539),@0]) {
        NSData *data=bytes(length.unsignedIntegerValue);
        NSURL *url=[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"hash-%@.wav",length]];
        writeFixture(url,data);[urls addObject:url];[expected addObject:expectedSHA(data)];
    }
    NSURL *missing=[directory URLByAppendingPathComponent:@"missing.wav"];
    dispatch_group_t group=dispatch_group_create();
    __block NSArray *actual=nil;__block NSUInteger stackSize=0;
    dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            stackSize=pthread_get_stacksize_np(pthread_self());
            NSMutableArray *hashes=[NSMutableArray new];
            for (NSURL *url in urls) [hashes addObject:[value sha256File:url] ?: NSNull.null];
            [hashes addObject:[value sha256File:missing] ?: NSNull.null];actual=hashes;
        }
    });
    check(!dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)),@"GCD hash returns without crashing or hanging");
    check(actual.count==4,@"all GCD hash cases completed");
    for (NSUInteger index=0;index<expected.count;index++) check([actual[index] isEqual:expected[index]],@"background SHA equals independent one-shot CommonCrypto SHA");
    check(actual.lastObject==NSNull.null,@"missing file does not produce an empty-file SHA");
    printf("Fallback hash: multi-block/tail/empty/missing files passed on GCD stack %lu bytes.\n",(unsigned long)stackSize);
}
static void importTests(NSURL *directory) {
    NSData *data=bytes(3*1024*1024+65539);NSString *sha=expectedSHA(data);
    NSURL *source=[directory URLByAppendingPathComponent:@"full-project.wav"];writeFixture(source,data);
    SubPopFallbackAudioController *normal=controller([directory URLByAppendingPathComponent:@"normal"]);
    check([normal importFallbackAudioURL:source] && normal.fallbackImporting,@"valid file starts asynchronous import");
    check(![normal canReceiveExportedAudio],@"another import is blocked while copying or hashing");
    settle(^BOOL { return !normal.fallbackImporting; });
    check(normal.continuationCount==1 && normal.continuedOnMain,@"successful import continues recognition once on the main thread");
    check(normal.fallbackAudioURL && ![normal.fallbackAudioURL isEqual:source],@"recognition uses its private copied audio");
    check([normal.fallbackAudioSHA isEqual:sha] && [[NSData dataWithContentsOfURL:normal.fallbackAudioURL] isEqual:data],@"copied bytes and SHA match the original complete file");
    check([normal.lastRecord[@"reason"] isEqual:@"fallback-audio"] && [normal.lastRecord[@"bytes"] unsignedIntegerValue]==data.length,@"successful import records actual file size");

    for (NSString *name in @[@"missing.wav",@"empty.wav"]) {
        NSURL *bad=[directory URLByAppendingPathComponent:name];
        if ([name isEqual:@"empty.wav"]) writeFixture(bad,NSData.data);
        SubPopFallbackAudioController *retry=controller([directory URLByAppendingPathComponent:name.stringByDeletingPathExtension]);
        check([retry importFallbackAudioURL:bad],@"file failure enters asynchronous validation");
        settle(^BOOL { return !retry.fallbackImporting; });
        check(!retry.fallbackAudioURL && !retry.fallbackAudioSHA && !retry.continuationCount,@"missing or empty file cannot submit recognition");
        check([retry.displayState isEqual:@"error"] && [retry.visibleError hasPrefix:@"导入备用音频失败："] && [retry canReceiveExportedAudio],@"file failure presents a recoverable interface error");
        check(!fallbackFiles(retry.testDirectory).count,@"failed import does not retain partial audio");
        check([retry importFallbackAudioURL:source],@"valid audio can be retried after file failure");
        settle(^BOOL { return !retry.fallbackImporting; });
        check(retry.continuationCount==1 && [retry.fallbackAudioSHA isEqual:sha],@"retry completes with the exact file SHA");
    }

    SubPopFallbackAudioController *stale=controller([directory URLByAppendingPathComponent:@"switched"]);
    stale.pauseHash=YES;stale.hashEntered=dispatch_semaphore_create(0);stale.hashContinue=dispatch_semaphore_create(0);
    check([stale importFallbackAudioURL:source],@"project switch fixture starts real copying");
    check(!dispatch_semaphore_wait(stale.hashEntered,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)),@"copy reaches the actual background hash");
    check(fallbackFiles(stale.testDirectory).count==1,@"stale import already has a private temporary copy");
    // Receive/activeSequenceChanged already reset these fields for a new project;
    // reproduce that state without invoking the user preference cleanup there.
    stale.dropGeneration++;stale.dropUID=@"fallback-project-b";
    stale.freshDropURL=[stale.testDirectory URLByAppendingPathComponent:@"new-project.fcpxml"];
    stale.fallbackImporting=NO;stale.displayState=@"input";stale.visibleError=nil;
    dispatch_semaphore_signal(stale.hashContinue);
    settle(^BOOL { return !fallbackFiles(stale.testDirectory).count; });
    check(!stale.fallbackAudioURL && !stale.fallbackAudioSHA && !stale.continuationCount,@"old project's imported audio never binds to the new project");
    check([stale.displayState isEqual:@"input"] && !stale.visibleError && [stale canReceiveExportedAudio],@"stale completion preserves the new project's state and availability");
    printf("Fallback import: actual copy/hash/main-thread continuation, missing/empty retry, and project switch passed.\n");
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc!=2 || (strcmp(argv[1],"hash") && strcmp(argv[1],"import"))) return 2;
        NSURL *temporary=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"SubPopFallbackTests-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
        check([NSFileManager.defaultManager createDirectoryAtURL:temporary withIntermediateDirectories:YES attributes:nil error:nil],@"create temporary test files");
        if (!strcmp(argv[1],"hash")) hashTests(temporary);else importTests(temporary);
        check([NSFileManager.defaultManager removeItemAtURL:temporary error:nil],@"remove isolated test files");
        return 0;
    }
}
