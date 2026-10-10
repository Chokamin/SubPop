// Actual asynchronous extension copy/hash/adoption; no FCP connection or ASR.
#import "ProbeViewController.m"

@interface SubPopShareIntakeController : SubPopProbeViewController
@property NSURL *testDirectory;
@property NSUInteger recognitionStarts;
@property BOOL interfaceOffMain;
@property BOOL pauseHash;
@property dispatch_semaphore_t hashEntered;
@property dispatch_semaphore_t hashContinue;
@end
@implementation SubPopShareIntakeController
- (NSURL *)evidenceDirectory { return self.testDirectory; }
- (void)updateInterface { if (!NSThread.isMainThread) self.interfaceOffMain=YES; }
- (BOOL)workerAvailable { return YES; }
- (BOOL)isolatedProjectActive { return YES; }
- (void)record:(NSDictionary *)value {}
- (void)startWorkerJob:(id)sender { self.recognitionStarts++; }
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
    Check([NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil],@"create isolated directory");return url;
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
    Check(!dispatch_semaphore_wait(c.hashEntered,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)),@"actual copy reaches background hash");
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
        if ([kind hasPrefix:@"active-"] || [kind isEqual:@"consumed"]) Check(!accepted,@"identity/duration/terminal receipt rejected before copy");
        else Check(accepted,@"content verification runs on background queue");
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
            NSData *audio=Audio();Success(root,audio);Rejections(root,audio);InvalidManifest(root,audio);StaleCompletions(root,audio);RestoreDuringIntake(root);
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
