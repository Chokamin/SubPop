// Native UI -> real local text worker -> captions/XML -> undo. No FCP writes.
#import "ProbeViewController.m"
@interface SubPopReferenceTestController : SubPopProbeViewController
@property NSURL *testDirectory;
@property NSDictionary *testSettings;
@property NSDictionary *testCatalog;
@property BOOL inactiveProject;
@end
@implementation SubPopReferenceTestController
- (NSDictionary *)readJSON:(NSURL *)url { return url ? [super readJSON:url] : self.testCatalog; }
- (NSURL *)evidenceDirectory { return self.testDirectory; }
- (NSDictionary *)referenceSettings { return self.testSettings ?: @{}; }
- (BOOL)workerAvailable { return YES; }
- (BOOL)selectedModelAvailable { return YES; }
- (BOOL)isolatedProjectActive { return !self.inactiveProject; }
- (void)restoreSession {}
@end
static BOOL runReference(NSURL *directory,NSString *root) {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@".venv/bin/python"]];
    task.currentDirectoryURL=[NSURL fileURLWithPath:root];task.arguments=@[@"-B",@"-m",@"probes.reference_job",@"--request",directory.path];
    NSError *error=nil;if (![task launchAndReturnError:&error]) {NSLog(@"%@",error);return NO;}[task waitUntilExit];return task.terminationStatus==0;
}
static NSArray<NSString *> *ReferenceBusyStates(void) {
    return @[@"shareReceiving",@"fallbackImporting",@"sharePromptOpen",@"importInProgress",@"exportInProgress",@"pendingRecognition"];
}
static void SetReferenceBusyState(SubPopReferenceTestController *controller,NSString *key,BOOL busy) {
    id value=[key isEqual:@"pendingRecognition"] ? (id)(busy ? @{} : nil) : @(busy);
    [controller setValue:value forKey:key];
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc!=3) return 1;[NSApplication sharedApplication];
        NSString *root=@(argv[1]),*job=@(argv[2]);
        NSURL *temporary=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtURL:temporary withIntermediateDirectories:YES attributes:nil error:nil];
        SubPopReferenceTestController *c=[SubPopReferenceTestController new];c.testDirectory=temporary;c.bridgeURL=temporary;
        c.testCatalog=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"config/models.json"]] options:0 error:nil];
        [c loadView];NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,660,740) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.contentView=c.view;
        if ([c validatedReferenceText:[@"a" stringByPaddingToLength:20001 withString:@"a" startingAtIndex:0]] || ![[c validatedReferenceText:@" 一行\n下一行\t "] isEqual:@"一行\n下一行"]) return 2;
        c.dropUID=@"reference-test";c.resultRequestID=NSUUID.UUID.UUIDString.lowercaseString;c.requestSHA=@"fixture";c.requestModelID=@"qwen3-asr-0.6b";
        c.resultManifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[job stringByAppendingPathComponent:@"captions.json"]] options:0 error:nil];
        c.captionRows=[NSMutableArray new];for (NSDictionary *row in c.resultManifest[@"captions"]) [c.captionRows addObject:row.mutableCopy];
        NSString *source=@"今年iPhone十八pro在影响上的提升非常明显",*expected=@"今年iPhone 18 Pro在影像上的提升非常明显";
        c.captionRows[0][@"text"]=source;c.resultDate=NSDate.date;
        NSMutableDictionary *payloads=[NSMutableDictionary new];for (NSString *version in @[@"1.12",@"1.13",@"1.14"]) {
            NSData *data=[NSData dataWithContentsOfFile:[job stringByAppendingPathComponent:[NSString stringWithFormat:@"TitleProbe-%@.fcpxml",version]]];
            NSXMLDocument *xml=data ? [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil] : nil;
            NSUInteger count=[[xml nodesForXPath:@"/fcpxml/clip/spine/title" error:nil] count];
            if (!xml || !c.captionRows.count || count!=c.captionRows.count) {NSLog(@"Reference fixture mismatch: %@ has %lu titles, captions.json has %lu captions",version,(unsigned long)count,(unsigned long)c.captionRows.count);return 23;}
            payloads[version]=data;
        }
        c.titlePayloads=payloads;c.testSettings=@{@"enabled":@YES,@"text":@"今年 iPhone 18 Pro 在影像上的提升非常明显。"};
        if (![c rebuildTitles]) {NSLog(@"Reference fixture could not build matching initial subtitle XML");return 24;}
        NSArray *baseline=[[NSArray alloc] initWithArray:c.captionRows copyItems:YES];NSDictionary *originals=[c.titlePayloads copy];
        [c startReferenceRefinement];if (!c.referenceRequestID || c.generateButton.enabled || c.templatePicker.enabled || c.referenceButton.enabled) return 3;
        NSURL *request=[temporary URLByAppendingPathComponent:c.referenceRequestID];
        NSDictionary *submitted=[c readJSON:[request URLByAppendingPathComponent:@"request.json"]];
        if (![submitted[@"kind"] isEqual:@"reference"] || ![submitted[@"captions"] isEqual:baseline] || submitted[@"cloudConsent"]) return 4;
        if (!runReference(request,root)) return 5;[c pollReferenceRefinement];
        if (c.referenceRequestID || ![c.captionRows[0][@"text"] isEqual:expected] || c.referenceUndoButton.hidden || ![c referenceRows:c.captionRows matchTimingOf:baseline]) return 6;
        for (NSString *version in c.titlePayloads) {
            NSXMLDocument *doc=[[NSXMLDocument alloc] initWithData:c.titlePayloads[version] options:0 error:nil];
            if (![[doc nodesForXPath:@"//title[1]/text" error:nil].firstObject.stringValue isEqual:expected]) return 7;
        }
        // A receiving/importing/exporting transaction owns both the input and
        // the visible result. Direct action calls must obey the disabled UI.
        NSArray *refinedRows=[[NSArray alloc] initWithArray:c.captionRows copyItems:YES];NSDictionary *refinedPayloads=[c.titlePayloads copy];
        NSArray *undoRows=c.referenceUndoRows;NSDictionary *undoPayloads=c.referenceUndoPayloads;
        NSUInteger existingFiles=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:temporary.path error:nil] count];
        for (NSString *state in ReferenceBusyStates()) {
            SetReferenceBusyState(c,state,YES);[c updateReferenceInterface];
            if (c.referenceButton.enabled || c.referenceUndoButton.enabled || c.templatePicker.enabled || c.fontPicker.enabled || c.sizePicker.enabled || c.tap5aStyleButton.enabled) {NSLog(@"Reference controls enabled during %@",state);return 18;}
            [c showReferenceScript:nil];[c startReferenceRefinement];[c undoReferenceRefinement:nil];
            if (c.referenceAlert || c.referenceRequestID || ![c.captionRows isEqual:refinedRows] || ![c.titlePayloads isEqual:refinedPayloads] || c.referenceUndoRows!=undoRows || c.referenceUndoPayloads!=undoPayloads || [[NSFileManager.defaultManager contentsOfDirectoryAtPath:temporary.path error:nil] count]!=existingFiles) {NSLog(@"Reference action changed state during %@",state);return 19;}
            SetReferenceBusyState(c,state,NO);
        }
        [c updateReferenceInterface];
        [c undoReferenceRefinement:nil];if (![c.captionRows isEqual:baseline] || ![c.titlePayloads isEqual:originals] || !c.referenceUndoButton.hidden) return 8;
        // A changed source must reject the returning result, preserving the edit.
        [c startReferenceRefinement];request=[temporary URLByAppendingPathComponent:c.referenceRequestID];if (!runReference(request,root)) return 9;
        c.captionRows[0][@"text"]=@"用户后来手动改写的内容";[c pollReferenceRefinement];
        if (![c.captionRows[0][@"text"] isEqual:@"用户后来手动改写的内容"]) return 10;
        [c startReferenceRefinement];request=[temporary URLByAppendingPathComponent:c.referenceRequestID];[c cancelJob:nil];
        if (c.referenceRequestID || ![NSFileManager.defaultManager fileExistsAtPath:[[request URLByAppendingPathComponent:@"cancel.json"] path]]) return 11;
        if ([c referenceRows:@[@{@"text":@"x",@"start_frame":@9,@"end_frame":@10}] matchTimingOf:@[@{@"text":@"y",@"start_frame":@1,@"end_frame":@10}]]) return 12;
        [c showReferenceScript:nil];if (!window.attachedSheet || ![c.referenceEditor.string isEqual:c.testSettings[@"text"]]) {NSLog(@"Reference sheet check failed: sheet=%d editorMatches=%d alert=%d busy=%d",window.attachedSheet!=nil,[c.referenceEditor.string isEqual:c.testSettings[@"text"]],c.referenceAlert!=nil,[c referenceMutationBusy]);return 13;}
        NSDictionary *storedScripts=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"referenceScripts"] ?: @{};
        c.referenceEditor.string=@"共享接收开始后，这份脚本不得保存或整理。";c.shareReceiving=YES;
        [window endSheet:c.referenceAlert.window returnCode:NSAlertFirstButtonReturn];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        NSDictionary *afterScripts=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"referenceScripts"] ?: @{};
        if (c.referenceAlert || c.referenceRequestID || ![afterScripts isEqual:storedScripts]) return 20;
        c.shareReceiving=NO;[c showReferenceScript:nil];if (!window.attachedSheet) return 21;
        [window endSheet:c.referenceAlert.window returnCode:NSAlertThirdButtonReturn];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        c.inactiveProject=YES;[c updateInterface];[c showReferenceScript:nil];
        if (c.referenceAlert || c.referenceButton.enabled) return 17;c.inactiveProject=NO;
        // Restore only an intact completed result for the active project and
        // duration. Historical snapshots cannot silently start another ASR job.
        NSString *recoveredID=NSUUID.UUID.UUIDString.lowercaseString;NSURL *recovered=[temporary URLByAppendingPathComponent:recoveredID];
        [NSFileManager.defaultManager createDirectoryAtURL:recovered withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *input=[@"<fcpxml><project uid='reference-test'/></fcpxml>" dataUsingEncoding:NSUTF8StringEncoding];NSString *sha=[c sha256:input];
        [input writeToURL:[recovered URLByAppendingPathComponent:@"input.fcpxml"] atomically:YES];
        NSDictionary *oldRequest=@{@"requestID":recoveredID,@"projectUID":@"reference-test",@"xmlSHA256":sha,@"modelID":@"qwen3-asr-0.6b",@"vocabulary":@[]};
        [[NSJSONSerialization dataWithJSONObject:oldRequest options:0 error:nil] writeToURL:[recovered URLByAppendingPathComponent:@"request.json"] atomically:YES];
        NSMutableDictionary *texts=[NSMutableDictionary new],*hashes=[NSMutableDictionary new],*manifest=c.resultManifest.mutableCopy;
        manifest[@"duration"]=@"10";manifest[@"frameDuration"]=@"1/30";manifest[@"captions"]=baseline;manifest[@"vocabulary"]=@[];manifest[@"referenceSHA256"]=@"";
        for (NSString *version in originals) {texts[version]=[[NSString alloc] initWithData:originals[version] encoding:NSUTF8StringEncoding];hashes[[NSString stringWithFormat:@"TitleProbe-%@.fcpxml",version]]=[c sha256:originals[version]];}
        NSDictionary *oldResponse=@{@"requestID":recoveredID,@"projectUID":@"reference-test",@"snapshotSHA256":sha,@"modelID":@"qwen3-asr-0.6b",@"status":@"ready",@"manifest":manifest,@"payloads":texts,@"outputs":hashes};
        [[NSJSONSerialization dataWithJSONObject:oldResponse options:0 error:nil] writeToURL:[recovered URLByAppendingPathComponent:@"response.json"] atomically:YES];
        NSArray *duration=[manifest[@"duration"] componentsSeparatedByString:@"/"];CMTime expectedDuration=CMTimeMake([duration[0] longLongValue],duration.count==2 ? [duration[1] intValue] : 1);
        c.titlePayloads=nil;c.freshDropURL=nil;c.observedProjectUID=@"different-project";c.observedProjectDuration=expectedDuration;[c restoreLastResult:nil];if (c.titlePayloads) return 14;
        c.observedProjectUID=@"reference-test";c.observedProjectDuration=CMTimeMake(1,1);[c restoreLastResult:nil];if (c.titlePayloads) return 15;
        c.observedProjectDuration=expectedDuration;
        NSArray *beforeRecoveryRows=[[NSArray alloc] initWithArray:c.captionRows copyItems:YES];NSString *beforeRecoveryResult=c.resultRequestID,*beforeRecoveryMessage=c.referenceMessage;
        existingFiles=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:temporary.path error:nil] count];
        for (NSString *state in ReferenceBusyStates()) {
            SetReferenceBusyState(c,state,YES);[c updateReferenceInterface];[c restoreLastResult:nil];
            if (!c.restoreResultButton.hidden || c.referenceButton.enabled || c.titlePayloads || c.freshDropURL || c.requestID || c.historicalResult || ![c.captionRows isEqual:beforeRecoveryRows] || ![c.resultRequestID isEqual:beforeRecoveryResult] || ![c.referenceMessage isEqual:beforeRecoveryMessage] || [[NSFileManager.defaultManager contentsOfDirectoryAtPath:temporary.path error:nil] count]!=existingFiles) {NSLog(@"Historical recovery changed state during %@",state);return 22;}
            SetReferenceBusyState(c,state,NO);
        }
        [c restoreLastResult:nil];if (!c.titlePayloads || !c.historicalResult || !c.snapshotConsumed || c.generateButton.enabled || ![c.captionRows isEqual:baseline]) {NSLog(@"Recovery failed payloads=%lu history=%d consumed=%d generate=%d rows=%d status=%@ detail=%@ output=%@",(unsigned long)c.titlePayloads.count,c.historicalResult,c.snapshotConsumed,c.generateButton.enabled,[c.captionRows isEqual:baseline],c.displayState,c.referenceMessage,c.output.string);return 16;}
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];
        [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
        puts("Reference script: native request -> real local worker -> three XML outputs, exact timing, undo, stale-edit rejection, cancellation, guarded sheet/actions and verified historical recovery passed.");
    }
    return 0;
}
