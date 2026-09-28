// AppKit workflow regression: real drop parsing and request files, controlled
// worker responses. Downloads and ASR are not performed by this harness.
#import "ProbeViewController.m"
@interface SubPopModelPreparationTests : SubPopProbeViewController
@property NSURL *testDirectory;
@property NSDictionary *testCatalog;
@property BOOL disconnected;
@end
@implementation SubPopModelPreparationTests
- (NSDictionary *)readJSON:(NSURL *)url { return url ? [super readJSON:url] : self.testCatalog; }
- (NSURL *)evidenceDirectory { return self.testDirectory; }
- (BOOL)workerAvailable { return !self.disconnected; }
- (void)restoreSession {}
@end
static void check(BOOL ok,NSString *message) { if (!ok) {NSLog(@"Model preparation regression: %@",message);exit(1);} }
static void save(NSURL *url,NSDictionary *value) {
    check([[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToURL:url atomically:YES],@"write test state");
}
static void service(SubPopModelPreparationTests *c,BOOL installed) {
    save([c.bridgeURL URLByAppendingPathComponent:@"service.json"],@{@"models":@[@{@"id":@"qwen3-asr-0.6b",@"installed":@(installed)}]});
}
static void drop(SubPopModelPreparationTests *c) {
    NSPasteboard *board=[NSPasteboard pasteboardWithUniqueName];
    [board setString:@"<fcpxml><project uid='model-test' name='首次使用测试'><sequence><bookmark>private</bookmark></sequence></project></fcpxml>" forType:@"com.apple.finalcutpro.xml.v1-14"];
    check([c receivePasteboard:board],@"missing model must accept a valid project");[board releaseGlobally];
}
static void response(SubPopModelPreparationTests *c,NSString *status,NSString *stage,double progress) {
    save([[c.bridgeURL URLByAppendingPathComponent:c.modelRequestID] URLByAppendingPathComponent:@"response.json"],
        @{@"requestID":c.modelRequestID,@"modelID":@"qwen3-asr-0.6b",@"operation":@"install",@"status":status,@"stage":stage,@"progress":@(progress),@"completedBytes":@(progress*1000000000),@"totalBytes":@1000000000,@"error":@"测试网络中断"});
}
static void dismiss(SubPopModelPreparationTests *c,NSModalResponse answer) {
    check(c.modelDownloadAlert!=nil,@"confirmation is visible");
    [c.view.window endSheet:c.modelDownloadAlert.window returnCode:answer];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.15]];
}
static void reset(SubPopModelPreparationTests *c) {
    [c clearPendingRecognition];c.requestID=nil;c.modelRequestID=nil;c.disconnected=NO;
    c.selectedModelID=@"qwen3-asr-0.6b";c.observed=YES;c.observedProjectUID=@"model-test";c.observedProjectDuration=CMTimeMake(8,1);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"modelRequestID"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];
    service(c,NO);drop(c);
}
static void begin(SubPopModelPreparationTests *c) {
    [c startWorkerJob:nil];dismiss(c,NSAlertFirstButtonReturn);
    check(c.pendingRecognition && c.modelRequestID && !c.requestID,@"confirmation queues download only");
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc!=2) return 2;[NSApplication sharedApplication];
        for (NSString *key in @[@"modelRequestID",@"pendingSession",@"referenceScripts",@"vocabularyTerms",@"selectedModelID"]) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        NSURL *temporary=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtURL:temporary withIntermediateDirectories:YES attributes:nil error:nil];
        SubPopModelPreparationTests *c=[SubPopModelPreparationTests new];c.testDirectory=temporary;c.bridgeURL=temporary;
        c.testCatalog=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];service(c,NO);
        [c loadView];NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,660,740) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.contentView=c.view;
        check([c.statusTitle.stringValue isEqual:@"准备生成字幕"],@"idle state is not a missing-model error");
        reset(c);check(c.generateButton.enabled && [c.dropTitle.stringValue isEqual:@"首次使用测试"] && [c.statusTitle.stringValue isEqual:@"项目已就绪"],@"project remains ready without model");
        check(!c.modelRequestID && !c.requestID,@"drop does not download or recognize");
        [c startWorkerJob:nil];check([c.modelDownloadAlert.informativeText containsString:@"3.72 GB"],@"first Qwen download includes aligner size");
        NSAlert *first=c.modelDownloadAlert;[c startWorkerJob:nil];check(c.modelDownloadAlert==first,@"repeated clicks do not stack prompts");
        dismiss(c,NSAlertSecondButtonReturn);check(!c.modelRequestID && c.generateButton.enabled && c.freshDropURL,@"cancel confirmation keeps project and creates no download");
        begin(c);
        NSDictionary *request=[c readJSON:[[temporary URLByAppendingPathComponent:c.modelRequestID] URLByAppendingPathComponent:@"request.json"]];
        check([request[@"kind"] isEqual:@"model"] && [request[@"operation"] isEqual:@"install"] && !request[@"projectUID"],@"model download request contains no project data");
        response(c,@"running",@"downloading",.5);[c pollWorker:nil];
        check(c.pendingRecognition && !c.requestID && !c.jobBar.hidden && fabs(c.jobBar.doubleValue-.5)<.001 && !c.cancelButton.hidden,@"main view displays actual progress and cancellation");
        check(!c.generateButton.enabled && !c.modelPicker.enabled && !c.audioPicker.enabled && !c.referenceButton.enabled && !c.vocabularyButton.enabled,@"settings frozen during download continuation");
        response(c,@"failed",@"failed",.5);[c pollWorker:nil];
        check(!c.pendingRecognition && !c.requestID && c.freshDropURL && c.generateButton.enabled && [c.statusDetail.stringValue containsString:@"测试网络中断"],@"network failure preserves project and offers retry");
        NSString *failed=c.modelRequestID;begin(c);check(![c.modelRequestID isEqual:failed],@"retry gets a new resumable task");
        NSString *cancelled=c.modelRequestID;[c cancelJob:nil];
        check(!c.pendingRecognition && [NSFileManager.defaultManager fileExistsAtPath:[[[temporary URLByAppendingPathComponent:cancelled] URLByAppendingPathComponent:@"cancel.json"] path]],@"cancel clears continuation before signalling worker");
        response(c,@"ready",@"ready",1);service(c,YES);[c pollWorker:nil];check(!c.requestID,@"late completion after cancellation never recognizes");
        reset(c);begin(c);response(c,@"running",@"checking",1);[c pollWorker:nil];
        check(!c.requestID && c.pendingRecognition,@"100 percent is not verified completion");
        response(c,@"ready",@"ready",1);[c pollWorker:nil];check(!c.requestID && c.pendingRecognition,@"wait for model availability heartbeat");
        service(c,YES);[c pollWorker:nil];check(c.requestID && !c.pendingRecognition,@"verified download automatically starts recognition");
        NSString *recognition=c.requestID;
        request=[c readJSON:[[temporary URLByAppendingPathComponent:recognition] URLByAppendingPathComponent:@"request.json"]];
        check([request[@"modelID"] isEqual:@"qwen3-asr-0.6b"] && [request[@"projectUID"] isEqual:@"model-test"] && ![request[@"cloudConsent"] boolValue],@"continuation uses same project and local model");
        NSString *xml=[NSString stringWithContentsOfURL:[[temporary URLByAppendingPathComponent:recognition] URLByAppendingPathComponent:@"input.fcpxml"] encoding:NSUTF8StringEncoding error:nil];
        check(![xml containsString:@"bookmark"],@"existing credential stripping remains in effect");
        [c pollModelPreparation];check([c.requestID isEqual:recognition],@"completion only submits once");
        reset(c);begin(c);drop(c);response(c,@"ready",@"ready",1);service(c,YES);[c pollWorker:nil];
        check(!c.pendingRecognition && !c.requestID && [c.statusTitle.stringValue isEqual:@"项目已就绪"],@"new drop disarms the old continuation");
        reset(c);begin(c);c.observedProjectUID=@"another-project";[c pollWorker:nil];check(!c.pendingRecognition && !c.requestID,@"changed active project does not auto-recognize");
        reset(c);begin(c);response(c,@"ready",@"ready",1);service(c,YES);
        [@"changed input" writeToURL:c.freshDropURL atomically:YES encoding:NSUTF8StringEncoding error:nil];[c pollWorker:nil];
        check(!c.pendingRecognition && !c.requestID && !c.freshDropURL && [c.displayState isEqual:@"expired"],@"changed input bytes reject continuation");
        reset(c);begin(c);c.disconnected=YES;[c pollWorker:nil];check(!c.pendingRecognition && !c.requestID && [c.displayState isEqual:@"model-download-failed"],@"worker disconnect never auto-runs later");
        reset(c);NSString *existing=[c submitModelOperation:@"install" model:c.selectedModelID];begin(c);
        check([c.modelRequestID isEqual:existing],@"existing selected download can be joined without duplication");[c cancelJob:nil];
        reset(c);begin(c);[c viewWillDisappear];check(!c.pendingRecognition && !c.requestID,@"closing extension disarms auto-recognition");
        [window orderOut:nil];
        for (NSString *key in @[@"modelRequestID",@"pendingSession"]) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
        puts("Model preparation: accepted drop, confirmation, progress, cancellation, retry, verified auto-start, stale input/project rejection, disconnect and closure passed.");
    }return 0;
}
