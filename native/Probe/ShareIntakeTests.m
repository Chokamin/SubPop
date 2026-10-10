// Actual asynchronous extension copy/hash/adoption; no FCP connection or ASR.
#import "ProbeViewController.m"

@interface SubPopShareIntakeController : SubPopProbeViewController
@property NSURL *testDirectory;
@property NSUInteger recognitionStarts;
@property BOOL interfaceOffMain;
@property BOOL pauseHash;
@property dispatch_semaphore_t hashEntered;
@property dispatch_semaphore_t hashContinue;
@property BOOL mockHost;
@property BOOL acceptanceOnStack;
@property BOOL readInsideAcceptance;
@property NSUInteger hostReads;
@property NSUInteger unavailableReads;
@property BOOL unavailableObserved;
@property NSString *hostUID;
@property CMTime hostDuration;
@property BOOL switchDuringRead;
@end
@implementation SubPopShareIntakeController
- (NSURL *)evidenceDirectory { return self.testDirectory; }
- (void)updateInterface { if (!NSThread.isMainThread) self.interfaceOffMain=YES; }
- (BOOL)workerAvailable { return YES; }
- (BOOL)isolatedProjectActive { return YES; }
- (void)record:(NSDictionary *)value {}
- (void)startWorkerJob:(id)sender { self.recognitionStarts++; }
- (void)snapshot:(NSString *)reason {
    if (!self.mockHost) { [super snapshot:reason];return; }
    self.hostReads++;self.readInsideAcceptance|=self.acceptanceOnStack;
    if (self.unavailableReads) {
        self.unavailableReads--;self.observed=self.unavailableObserved;self.observedProjectUID=nil;self.observedProjectDuration=kCMTimeInvalid;
    } else {
        self.observed=YES;self.observedProjectUID=self.hostUID ?: @"PROJECT-A";
        self.observedProjectDuration=CMTIME_IS_NUMERIC(self.hostDuration) ? self.hostDuration : CMTimeMake(10,1);
    }
    if (self.switchDuringRead) {
        self.switchDuringRead=NO;self.dropGeneration++;self.observedProjectUID=@"PROJECT-B";
        self.displayState=@"input";self.visibleError=nil;self.fallbackImporting=NO;
    }
}
- (NSString *)sha256File:(NSURL *)url {
    if (self.pauseHash) {
        dispatch_semaphore_signal(self.hashEntered);
        if (dispatch_semaphore_wait(self.hashContinue,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))) return nil;
    }
    return [super sha256File:url];
}
@end

static NSUInteger checks=0;
static void Check(BOOL value,NSString *message) {
    checks++;
    if (!value) @throw [NSException exceptionWithName:@"ShareIntakeRegression" reason:message userInfo:nil];
}
static void Write(NSURL *url,NSData *data) {
    Check([data writeToURL:url options:NSDataWritingAtomic error:nil],@"write isolated fixture");
}
static void JSON(NSURL *url,id value) {Write(url,[NSJSONSerialization dataWithJSONObject:value options:0 error:nil]);}
static NSString *Digest(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *text=[NSMutableString new];for (NSUInteger index=0;index<sizeof(digest);index++) [text appendFormat:@"%02x",digest[index]];
    return text;
}
static NSData *Audio(void) {
    NSMutableData *data=[NSMutableData dataWithLength:1024*1024+397];uint8_t *bytes=data.mutableBytes;
    for (NSUInteger index=0;index<data.length;index++) bytes[index]=(uint8_t)((index*29+index/251)%256);
    return data;
}
static NSString *XML(NSString *uid,NSString *duration) {
    return [NSString stringWithFormat:@"<fcpxml version='1.14'><resources><format id='r1' frameDuration='1/25s' width='1920' height='1080'/></resources><library><event name='test'><project uid='%@' name='合成测试'><sequence format='r1' duration='%@'><spine><gap duration='%@'/></spine></sequence></project></event></library></fcpxml>",uid,duration,duration];
}
static NSURL *Directory(NSURL *parent,NSString *name) {
    NSURL *url=[parent URLByAppendingPathComponent:name isDirectory:YES];
    Check([NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil],@"create isolated directory");return url;
}
static SubPopShareIntakeController *Controller(NSURL *root,NSString *name) {
    NSURL *directory=Directory(root,name);
    SubPopShareIntakeController *c=[SubPopShareIntakeController new];
    c.testDirectory=Directory(directory,@"evidence");c.bridgeURL=Directory(directory,@"bridge");
    c.observed=YES;c.observedProjectUID=@"PROJECT-A";c.observedProjectDuration=CMTimeMake(10,1);
    c.freshDropURL=[c.testDirectory URLByAppendingPathComponent:@"old-project.fcpxml"];
    Write(c.freshDropURL,[@"existing project snapshot" dataUsingEncoding:NSUTF8StringEncoding]);
    c.freshDropDate=NSDate.date;c.dropUID=@"PROJECT-A";c.dropDuration=CMTimeMake(10,1);c.dropGeneration=7;
    c.fallbackAudioURL=[c.testDirectory URLByAppendingPathComponent:@"fallback-old.wav"];
    Write(c.fallbackAudioURL,[@"existing audio" dataUsingEncoding:NSUTF8StringEncoding]);c.fallbackAudioSHA=@"old-audio-sha";
    c.captionRows=[NSMutableArray arrayWithObject:[@{@"text":@"原有字幕"} mutableCopy]];
    c.titlePayloads=@{@"1.14":[@"old titles" dataUsingEncoding:NSUTF8StringEncoding]};
    c.resultManifest=@{@"marker":@"existing result"};c.resultRequestID=@"old-result";c.resultDate=NSDate.date;
    c.displayState=@"ready";
    return c;
}
static NSURL *Inbox(SubPopShareIntakeController *c,NSDictionary *share) {
    return [[c.bridgeURL URLByAppendingPathComponent:@"share-inbox"] URLByAppendingPathComponent:share[@"shareID"]];
}
static NSMutableDictionary *Share(SubPopShareIntakeController *c,NSString *xml,NSData *audio) {
    NSString *ID=NSUUID.UUID.UUIDString;
    NSURL *directory=Directory(Directory(c.bridgeURL,@"share-inbox"),ID);
    NSData *data=[xml dataUsingEncoding:NSUTF8StringEncoding];
    Write([directory URLByAppendingPathComponent:@"input.fcpxml"],data);
    Write([directory URLByAppendingPathComponent:@"audio.wav"],audio);
    NSMutableDictionary *manifest=[@{@"protocol":@1,@"shareID":ID,@"projectUID":@"PROJECT-A",@"projectName":@"合成测试",
        @"duration":@"10",@"frameDuration":@"1/25",@"audioFile":@"audio.wav",@"xmlFile":@"input.fcpxml",
        @"xmlSHA256":Digest(data),@"audioSHA256":Digest(audio)} mutableCopy];
    JSON([directory URLByAppendingPathComponent:@"ready.json"],manifest);return manifest;
}
static void Settle(BOOL (^finished)(void)) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while (!finished() && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(finished(),@"asynchronous share operation completes");
}
static NSArray *EvidenceNames(SubPopShareIntakeController *c) {
    return [[NSFileManager.defaultManager contentsOfDirectoryAtPath:c.testDirectory.path error:nil] sortedArrayUsingSelector:@selector(compare:)];
}
static void Unchanged(SubPopShareIntakeController *c,NSURL *oldXML,NSURL *oldAudio,NSArray *before) {
    Check([c.freshDropURL isEqual:oldXML] && [c.fallbackAudioURL isEqual:oldAudio],@"rejected transaction preserves existing inputs");
    Check([c.resultManifest[@"marker"] isEqual:@"existing result"] && [c.resultRequestID isEqual:@"old-result"] && c.captionRows.count==1 && c.titlePayloads.count==1,@"rejected transaction preserves completed result");
    Check([EvidenceNames(c) isEqual:before],@"rejected transaction removes only its temporary copies");
    Check(!c.recognitionStarts && !c.interfaceOffMain,@"no recognition or off-main UI update");
}
static void StartPaused(SubPopShareIntakeController *c,NSDictionary *share) {
    c.pauseHash=YES;c.hashEntered=dispatch_semaphore_create(0);c.hashContinue=dispatch_semaphore_create(0);
    Check([c acceptSharedAudio:share],@"starts asynchronous share intake");
    Check(![c canDragResult],@"old results cannot be dragged while a replacement input is being copied");
    __block BOOL entered=NO;
    Settle(^BOOL{if (!entered) entered=dispatch_semaphore_wait(c.hashEntered,DISPATCH_TIME_NOW)==0;return entered;});
    Check(entered,@"actual copy reaches background hash");
}

static void RestoreDuringIntake(NSURL *root) {
    SubPopShareIntakeController *c=Controller(root,@"restore-during-intake");
    c.titlePayloads=nil;c.resultManifest=nil;c.captionRows=nil;
    // restoreSession only tests presence of timeline before reading saved state;
    // this sentinel never sends SDK messages or connects to an actual host.
    c.timeline=(id)[NSObject new];
    [NSUserDefaults.standardUserDefaults setObject:@{@"projectUID":@"PROJECT-A",@"durationValue":@10,@"durationScale":@1,
        @"requestID":NSUUID.UUID.UUIDString,@"modelID":@"test-model"} forKey:@"pendingSession"];
    c.shareReceiving=YES;[c restoreSession];
    Check(!c.requestID,@"automatic historical restoration cannot race shared audio receipt");
    c.shareReceiving=NO;c.fallbackImporting=YES;[c restoreSession];
    Check(!c.requestID,@"automatic historical restoration cannot race fallback audio copying");
    c.fallbackImporting=NO;c.sharePromptOpen=YES;[c restoreSession];
    Check(!c.requestID,@"historical restoration cannot change the current result beneath the share selection sheet");
    c.timeline=nil;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];
}

static void DeferredHostValidation(NSURL *root,NSData *audio) {
    SubPopShareIntakeController *c=Controller(root,@"deferred-host");
    NSDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);
    c.mockHost=YES;c.timeline=(id)[NSObject new];c.hostDuration=kCMTimeInvalid;
    c.observed=NO;c.observedProjectUID=nil;c.observedProjectDuration=kCMTimeInvalid;
    c.acceptanceOnStack=YES;
    BOOL scheduled=[c acceptSharedAudio:share];
    c.acceptanceOnStack=NO;
    Check(scheduled && c.shareReceiving,@"acceptance schedules a guarded confirmation");
    Check(!c.readInsideAcceptance && c.hostReads==0,@"no synchronous SDK read while the share sheet completion is still on stack");
    __block BOOL modalFinished=NO;
    NSDate *modalStarted=NSDate.date;
    NSTimer *modalTimer=[NSTimer timerWithTimeInterval:.2 repeats:NO block:^(NSTimer *timer){modalFinished=YES;}];
    [NSRunLoop.currentRunLoop addTimer:modalTimer forMode:NSModalPanelRunLoopMode];
    while (!modalFinished) [NSRunLoop.currentRunLoop runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    Check(-modalStarted.timeIntervalSinceNow>=.1 && c.hostReads==0 && c.shareReceiving,@"host reads stay deferred throughout the actual modal runloop beyond the scheduled delay");
    Settle(^BOOL{return !c.shareReceiving;});
    Check(c.hostReads==1 && [c.displayState isEqual:@"input"] && !c.recognitionStarts,@"next default runloop confirms identity without starting ASR");
    c.timeline=nil;
}

static NSDictionary *Diagnostic(SubPopShareIntakeController *c,NSDictionary *share) {
    NSURL *url=[Inbox(c,share) URLByAppendingPathComponent:@"share-intake.json"];
    NSDictionary *diagnostic=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:nil];
    Check([diagnostic[@"shareID"] isEqual:share[@"shareID"]],@"diagnostic is bound to the selected share only");
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    Check([attrs[NSFilePosixPermissions] unsignedIntegerValue]==0600,@"diagnostic is private to this account");
    NSSet *allowed=[NSSet setWithArray:@[@"shareID",@"version",@"build",@"startedAt",@"updatedAt",@"finished",@"accepted",@"cancelled",@"contentVerified",@"snapshots"]];
    for (NSString *key in diagnostic) Check([allowed containsObject:key],@"diagnostic top-level whitelist excludes names, paths, settings and media");
    NSSet *snapshotKeys=[NSSet setWithArray:@[@"observed",@"hasTimeline",@"current",@"expectedProjectUID",@"observedProjectUID",@"expectedDuration",@"observedDuration",@"notReady",@"identityMismatch",@"durationMismatch"]];
    for (NSDictionary *snapshot in diagnostic[@"snapshots"])
        for (NSString *key in snapshot) Check([snapshotKeys containsObject:key],@"host diagnostic has only booleans, identities and times");
    return diagnostic;
}

static void HostReadiness(NSURL *root,NSData *audio) {
    for (NSString *kind in @[@"observer-late",@"invalid-late",@"unavailable",@"wrong-uid",@"wrong-duration",@"zero-duration"]) {
        SubPopShareIntakeController *c=Controller(root,kind);NSDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);
        NSURL *oldXML=c.freshDropURL,*oldAudio=c.fallbackAudioURL;NSArray *before=EvidenceNames(c);
        c.mockHost=YES;c.timeline=(id)[NSObject new];c.hostDuration=kCMTimeInvalid;
        if ([kind hasSuffix:@"late"]) c.unavailableReads=2;
        c.unavailableObserved=[kind isEqual:@"invalid-late"];
        if ([kind isEqual:@"unavailable"]) c.unavailableReads=10;
        if ([kind isEqual:@"wrong-uid"]) c.hostUID=@"OTHER-PROJECT";
        if ([kind isEqual:@"wrong-duration"]) c.hostDuration=CMTimeMake(9,1);
        if ([kind isEqual:@"zero-duration"]) c.hostDuration=kCMTimeZero;
        Check([c acceptSharedAudio:share],@"host validation is deferred for the selected transaction");
        Settle(^BOOL{return !c.shareReceiving;});
        NSDictionary *diagnostic=Diagnostic(c,share);NSArray *snapshots=diagnostic[@"snapshots"];
        BOOL succeeds=[kind hasSuffix:@"late"],mismatch=[kind hasPrefix:@"wrong-"];
        Check(c.hostReads==(mismatch ? 1U : 3U) && snapshots.count==c.hostReads,@"only unavailable host state is retried, at most three times");
        Check([diagnostic[@"finished"] boolValue] && [diagnostic[@"accepted"] boolValue]==succeeds,@"diagnostic records the final acceptance without starting recognition");
        if (succeeds) Check([c.displayState isEqual:@"input"] && c.fallbackAudioURL && !c.recognitionStarts,@"delayed valid host state safely receives once");
        else {
            Unchanged(c,oldXML,oldAudio,before);
            Check([c.visibleError containsString:mismatch ? @"不一致" : @"暂时无法读取"],@"unavailable and true mismatch have distinct messages");
            Check(![NSFileManager.defaultManager fileExistsAtPath:[Inbox(c,share) URLByAppendingPathComponent:@"consumed.json"].path],@"host failure never consumes the share");
        }
        c.timeline=nil;
    }
}

static void CancelHostValidation(NSURL *root,NSData *audio) {
    for (NSString *kind in @[@"switch-before-read",@"switch-during-read",@"close-before-read"]) {
        SubPopShareIntakeController *c=Controller(root,kind);NSDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);
        c.mockHost=YES;c.timeline=(id)[NSObject new];c.hostDuration=kCMTimeInvalid;
        Check([c acceptSharedAudio:share],@"schedule host validation before lifecycle change");
        if ([kind isEqual:@"switch-during-read"]) c.switchDuringRead=YES;
        else {
            c.dropGeneration++;c.fallbackImporting=NO;c.displayState=@"input";c.visibleError=nil;
            if ([kind isEqual:@"close-before-read"]) {c.bridgeURL=nil;c.timeline=nil;c.observed=NO;}
        }
        Settle(^BOOL{return !c.shareReceiving;});
        Check(c.hostReads==([kind isEqual:@"switch-during-read"] ? 1U : 0U),@"cancelled host validation does not retry or query a closed host");
        Check([c.displayState isEqual:@"input"] && !c.visibleError && !c.fallbackImporting,@"cancelled confirmation preserves the new UI state");
        Check(!c.recognitionStarts && ![NSFileManager.defaultManager fileExistsAtPath:[[[root URLByAppendingPathComponent:kind] URLByAppendingPathComponent:@"bridge/share-inbox"] URLByAppendingPathComponent:[share[@"shareID"] stringByAppendingPathComponent:@"consumed.json"]].path],@"cancelled confirmation never consumes or starts recognition");
        c.timeline=nil;
    }
}

static void Success(NSURL *root,NSData *audio) {
    SubPopShareIntakeController *c=Controller(root,@"success");
    NSURL *original=[root URLByAppendingPathComponent:@"original-source.wav"];Write(original,audio);
    NSDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);
    NSURL *dir=Inbox(c,share),*oldAudio=c.fallbackAudioURL;
    Check(SubPopPendingShares(c.bridgeURL).count==1,@"valid transaction is discoverable");
    Check([c acceptSharedAudio:share] && c.shareReceiving && c.fallbackImporting,@"valid share starts copying");
    Check(![c acceptSharedAudio:share],@"a second acceptance cannot race the first");
    Settle(^BOOL{return !c.shareReceiving;});
    Check(!c.fallbackImporting && c.dropGeneration==8 && !c.snapshotConsumed && [c.displayState isEqual:@"input"],@"successful receipt adopts a fresh complete input");
    Check([c.fallbackAudioSHA isEqual:Digest(audio)] && [[NSData dataWithContentsOfURL:c.fallbackAudioURL] isEqual:audio],@"private copied bytes and checksum match");
    Check([c.freshDropURL.lastPathComponent hasPrefix:@"drop-"] && [c.fallbackAudioURL.lastPathComponent hasPrefix:@"fallback-"],@"each input gets a new private evidence path");
    Check(!c.titlePayloads && !c.captionRows && !c.resultManifest && !c.resultRequestID,@"accepted transaction clears only SubPop's old result");
    Check(![NSFileManager.defaultManager fileExistsAtPath:oldAudio.path],@"old private fallback audio is cleaned after adoption");
    Check([[NSData dataWithContentsOfURL:original] isEqual:audio],@"unrelated original source is not removed or changed");
    Check([NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"consumed.json"].path],@"receipt marker is committed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"audio.wav"].path] && !SubPopPendingShares(c.bridgeURL).count,@"received inbox payload is retired");
    Check(![c acceptSharedAudio:share],@"duplicate receipt cannot replace current input");
    Check(!c.recognitionStarts && !c.interfaceOffMain,@"receipt alone never starts local or cloud ASR");
}

static void Rejections(NSURL *root,NSData *audio) {
    for (NSString *kind in @[@"active-uid",@"active-duration",@"xml-uid",@"xml-duration",@"malformed-xml",@"checksum",@"consumed"]) {
        SubPopShareIntakeController *c=Controller(root,kind);NSString *xml=XML(@"PROJECT-A",@"10s");
        if ([kind isEqual:@"xml-uid"]) xml=XML(@"OTHER-PROJECT",@"10s");
        if ([kind isEqual:@"xml-duration"]) xml=XML(@"PROJECT-A",@"9s");
        if ([kind isEqual:@"malformed-xml"]) xml=@"not XML";
        NSDictionary *share=Share(c,xml,audio);NSURL *dir=Inbox(c,share),*oldXML=c.freshDropURL,*oldAudio=c.fallbackAudioURL;NSArray *before=EvidenceNames(c);
        if ([kind isEqual:@"active-uid"]) c.observedProjectUID=@"OTHER-PROJECT";
        if ([kind isEqual:@"active-duration"]) c.observedProjectDuration=CMTimeMake(9,1);
        if ([kind isEqual:@"checksum"]) Write([dir URLByAppendingPathComponent:@"audio.wav"],[@"modified after manifest publication" dataUsingEncoding:NSUTF8StringEncoding]);
        if ([kind isEqual:@"consumed"]) JSON([dir URLByAppendingPathComponent:@"consumed.json"],@{@"status":@"received"});
        BOOL accepted=[c acceptSharedAudio:share];
        if ([kind isEqual:@"consumed"]) Check(!accepted,@"terminal receipt rejected before host validation");
        else Check(accepted,@"identity and content are checked after the acceptance callback returns");
        Settle(^BOOL{return !c.shareReceiving;});Unchanged(c,oldXML,oldAudio,before);
        Check([NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"audio.wav"].path],@"rejected transaction remains available for diagnosis or retry");
        if (![kind isEqual:@"consumed"]) Check(![NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"consumed.json"].path],@"failed transaction is not marked received");
    }
}

static void InvalidManifest(NSURL *root,NSData *audio) {
    NSArray *changes=@[@{@"protocol":@2},@{@"audioFile":@"../audio.wav"},@{@"audioFile":@"audio.txt"},@{@"xmlFile":@"../input.fcpxml"},
        @{@"xmlSHA256":@"wrong"},@{@"audioSHA256":[@"A" stringByPaddingToLength:64 withString:@"A" startingAtIndex:0]},
        @{@"duration":@"nan"},@{@"duration":@"-1"},@{@"duration":@"1/0"},@{@"duration":@"14401"},@{@"frameDuration":@"2"},@{@"shareID":@"not-a-uuid"}];
    NSUInteger index=0;
    for (NSDictionary *change in changes) {
        SubPopShareIntakeController *c=Controller(root,[NSString stringWithFormat:@"manifest-%lu",(unsigned long)index++]);
        NSMutableDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);NSURL *dir=Inbox(c,share);[share addEntriesFromDictionary:change];
        JSON([dir URLByAppendingPathComponent:@"ready.json"],share);
        Check(!SubPopShareManifest(dir) && !SubPopPendingShares(c.bridgeURL).count,@"malformed manifest is not offered as an input");
    }
    SubPopShareIntakeController *c=Controller(root,@"manifest-symlink");NSDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);NSURL *dir=Inbox(c,share);
    NSURL *path=[dir URLByAppendingPathComponent:@"audio.wav"],*source=[root URLByAppendingPathComponent:@"original-source.wav"];
    Check([NSFileManager.defaultManager removeItemAtURL:path error:nil],@"remove only generated inbox audio");
    Check([NSFileManager.defaultManager createSymbolicLinkAtURL:path withDestinationURL:source error:nil],@"create isolated symlink fixture");
    Check(!SubPopShareManifest(dir),@"symlink audio is rejected");
}

static void StaleCompletions(NSURL *root,NSData *audio) {
    for (NSNumber *generationChanges in @[@YES,@NO]) {
        SubPopShareIntakeController *c=Controller(root,generationChanges.boolValue ? @"generation-switch" : @"identity-switch");
        NSDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);StartPaused(c,share);
        c.observedProjectUID=@"PROJECT-B";
        if (generationChanges.boolValue) c.dropGeneration++;
        NSURL *newXML=[c.testDirectory URLByAppendingPathComponent:@"new-project.fcpxml"],*newAudio=[c.testDirectory URLByAppendingPathComponent:@"fallback-new.wav"];
        Write(newXML,[@"new project input" dataUsingEncoding:NSUTF8StringEncoding]);Write(newAudio,[@"new project audio" dataUsingEncoding:NSUTF8StringEncoding]);
        c.freshDropURL=newXML;c.fallbackAudioURL=newAudio;c.fallbackAudioSHA=@"new-sha";c.dropUID=@"PROJECT-B";
        c.displayState=@"input";c.visibleError=nil;c.fallbackImporting=NO;c.resultManifest=@{@"marker":@"new project result"};
        dispatch_semaphore_signal(c.hashContinue);Settle(^BOOL{return !c.shareReceiving;});
        Check([c.freshDropURL isEqual:newXML] && [c.fallbackAudioURL isEqual:newAudio] && [c.fallbackAudioSHA isEqual:@"new-sha"],@"late old share never binds to new input");
        Check([c.resultManifest[@"marker"] isEqual:@"new project result"] && [c.displayState isEqual:@"input"] && !c.visibleError && !c.fallbackImporting,@"late share preserves new project's result and state");
        Check(EvidenceNames(c).count==4,@"late share removes exactly its two temporary copies");
        Check(SubPopPendingShares(c.bridgeURL).count==1 && !c.recognitionStarts,@"stale share is retained but does not run recognition");
    }
    SubPopShareIntakeController *c=Controller(root,@"receipt-race");NSDictionary *share=Share(c,XML(@"PROJECT-A",@"10s"),audio);
    NSURL *oldXML=c.freshDropURL,*oldAudio=c.fallbackAudioURL;NSArray *before=EvidenceNames(c);StartPaused(c,share);
    Check(![c beginResultRevalidation:oldXML projectUID:@"PROJECT-A"],@"same-project revalidation cannot race an active share copy");
    JSON([Inbox(c,share) URLByAppendingPathComponent:@"consumed.json"],@{@"status":@"discarded"});
    dispatch_semaphore_signal(c.hashContinue);Settle(^BOOL{return !c.shareReceiving;});Unchanged(c,oldXML,oldAudio,before);
    NSDictionary *receipt=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[Inbox(c,share) URLByAppendingPathComponent:@"consumed.json"]] options:0 error:nil];
    Check([receipt[@"status"] isEqual:@"discarded"],@"late receipt cannot overwrite a terminal discard");
}

int main(void) {
    @autoreleasepool {
        NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"SubPopShareIntakeTests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        root=root.URLByResolvingSymlinksInPath;
        id previous=[NSUserDefaults.standardUserDefaults objectForKey:@"pendingSession"];
        int status=0;
        @try {
            Check([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil],@"create isolated test root");
            NSData *audio=Audio();DeferredHostValidation(root,audio);HostReadiness(root,audio);CancelHostValidation(root,audio);Success(root,audio);Rejections(root,audio);InvalidManifest(root,audio);StaleCompletions(root,audio);RestoreDuringIntake(root);
            printf("Share intake: %lu checks passed; actual background copy/hash, validation, terminal replay and stale-completion state preservation (no FCP).\n",(unsigned long)checks);
        } @catch (NSException *exception) {
            fprintf(stderr,"Share intake failure: %s\n",exception.reason.UTF8String);status=1;
        } @finally {
            if (previous) [NSUserDefaults.standardUserDefaults setObject:previous forKey:@"pendingSession"];
            else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];
            [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        }
        return status;
    }
}
