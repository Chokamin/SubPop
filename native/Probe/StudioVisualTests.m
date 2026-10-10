// Frozen AppKit presentation matrix. No FCP, worker, model or preference writes.
// Usage: SubPopStudioVisualTests config/models.json <30-caption fixture directory>
// Outputs only /tmp/subpop-ui156/{state}-{width}x{height}.png and index.json.
#import "ProbeViewController.m"

@interface SubPopVisualController : SubPopProbeViewController
@property NSDictionary *previewCatalog;
@end

@implementation SubPopVisualController
- (NSDictionary *)readJSON:(NSURL *)url {
    return !url || [url.lastPathComponent isEqual:@"models.json"] ? self.previewCatalog : nil;
}
- (BOOL)workerAvailable { return YES; }
- (BOOL)selectedModelAvailable { return YES; }
- (BOOL)modelOperationBusy { return NO; }
- (NSDictionary *)modelTaskState { return @{}; }
- (NSArray *)effectiveVocabulary { return @[]; }
- (NSDictionary *)referenceSettings { return @{}; }
- (NSString *)effectiveReferenceScript { return @""; }
- (void)restoreSession {}
- (void)saveDraft {}
- (void)record:(NSDictionary *)value {}
// Attaching a view to the offscreen window must never initialize the host.
- (void)viewDidAppear {}
- (void)viewWillDisappear {}
- (BOOL)restoreBridge {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected bridge initialization"];return NO;
}
- (NSURL *)evidenceDirectory {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected product evidence write"];return nil;
}
- (void)snapshot:(NSString *)reason {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected host snapshot"];
}
- (void)connectWorker:(id)sender {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected worker connection"];
}
- (void)startWorkerJob:(id)sender {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected recognition request"];
}
- (void)submitWorkerJob {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected recognition submission"];
}
- (void)importTitlesToFCP:(id)sender {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected title import"];
}
- (void)installShareDestination:(id)sender {
    [NSException raise:@"VisualProbeIsolation" format:@"Unexpected share preset installation"];
}
@end

static void Require(BOOL condition,NSString *message) {
    if (!condition) [NSException raise:@"VisualProbeFailure" format:@"%@",message];
}

static NSDictionary *ReadFixture(NSURL *url) {
    NSError *error=nil;NSData *data=[NSData dataWithContentsOfURL:url options:0 error:&error];
    Require(data!=nil,[NSString stringWithFormat:@"Cannot read fixture %@: %@",url.lastPathComponent,error.localizedDescription]);
    id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    Require([object isKindOfClass:NSDictionary.class],[NSString stringWithFormat:@"Fixture %@ is not an object",url.lastPathComponent]);
    return object;
}

static void SelectModel(SubPopVisualController *controller,NSString *identifier) {
    BOOL selected=NO;
    for (NSMenuItem *item in controller.modelPicker.itemArray) {
        if ([item.representedObject isEqual:identifier]) {
            controller.selectedModelID=identifier;[controller.modelPicker selectItem:item];selected=YES;break;
        }
    }
    Require(selected,[NSString stringWithFormat:@"Model %@ is missing from the supplied catalog",identifier]);
    // Do not call modelChanged:, which intentionally persists real user choices.
}

static void Project(SubPopVisualController *controller,NSDictionary *fixture) {
    CMTime frame=SubPopShareTime(fixture[@"frameDuration"]);
    NSInteger totalFrames=[fixture[@"totalFrames"] integerValue];
    Require(CMTIME_IS_NUMERIC(frame) && totalFrames>0 && totalFrames<=INT32_MAX,@"Invalid fixture project timing");
    controller.dropUID=fixture[@"projectUID"] ?: @"SUBPOP-VISUAL-PROJECT";
    controller.dropName=@"海边旅行 · 成片与解说校对";
    controller.dropDuration=CMTimeMultiply(frame,(int32_t)totalFrames);
    controller.observed=YES;controller.observedProjectUID=controller.dropUID;
    controller.observedProjectDuration=controller.dropDuration;
    // Deliberately nonexistent: these URLs are labels for state only, never opened.
    controller.freshDropURL=[NSURL fileURLWithPath:@"/tmp/subpop-ui156/fixture-project.fcpxml"];
    controller.freshDropDate=NSDate.date;controller.displayState=@"input";
}

static NSArray *PendingShares(void) {
    return @[
        @{@"shareID":@"49A34FD0-12C6-4AF6-857C-029937470ED6",@"projectUID":@"SUBPOP-VISUAL-SHARE-A",@"projectName":@"海边旅行 · 成片与解说校对",@"duration":@"90",@"frameDuration":@"1/30"},
        @{@"shareID":@"66C57BB4-B562-4AD1-B24D-1452E9C522A7",@"projectUID":@"SUBPOP-VISUAL-SHARE-B",@"projectName":@"婚礼纪实 · 长项目名称与共享音频核对",@"duration":@"600",@"frameDuration":@"1/30"}
    ];
}

static void Configure(SubPopVisualController *controller,NSString *state,NSDictionary *fixture,NSData *titles) {
    SelectModel(controller,controller.previewCatalog[@"defaultModelID"]);
    controller.displayState=@"idle";
    if (![@[@"empty",@"pending",@"setup-error"] containsObject:state]) Project(controller,fixture);
    if ([state isEqual:@"pending"] || [state isEqual:@"receiving"]) controller.pendingShares=PendingShares();
    if ([state isEqual:@"receiving"]) {
        controller.shareReceiving=YES;controller.fallbackImporting=YES;
    } else if ([state isEqual:@"received"]) {
        controller.fallbackAudioURL=[NSURL fileURLWithPath:@"/tmp/subpop-ui156/fixture-received-audio.wav"];
        controller.fallbackAudioSHA=[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
        [controller.audioPicker selectItemAtIndex:1];
    } else if ([state isEqual:@"complete"] || [state isEqual:@"warnings"]) {
        controller.resultManifest=fixture;
        controller.captionRows=SubPopMutableCaptionRows(fixture[@"captions"]);
        controller.captionSourceRows=SubPopMutableCaptionRows(fixture[@"captions"]);
        controller.titlePayloads=@{@"1.14":titles};controller.resultDate=NSDate.date;
        controller.resultRequestID=@"VISUAL-RESULT";controller.snapshotConsumed=YES;
        controller.displayState=@"ready";
        if ([state isEqual:@"warnings"]) {
            NSMutableDictionary *manifest=fixture.mutableCopy;
            manifest[@"reviewWarnings"]=@[@{@"reason":@"word-timing"},@{@"reason":@"segment-timing"}];
            manifest[@"existingTitleCollision"]=@{@"overlappingRows":@3};
            manifest[@"skippedAudio"]=@[@{@"startSample":@96000,@"endSample":@192000,@"reason":@"复杂变速"}];
            manifest[@"bypassedAudioEffects"]=@2;
            manifest[@"bypassedAudioTransitions"]=@[@{@"offset":@"19/5",@"duration":@"2/5"}];
            manifest[@"existingTitleReview"]=@"unavailable";
            manifest[@"recognitionReview"]=@{@"warningCount":@2,@"warnings":@[
                @{@"start":@5,@"end":@10,@"reason":@"signal-without-text"},
                @{@"start":@12,@"end":@20,@"reason":@"repetitive-output"}]};
            controller.resultManifest=manifest;
        }
    } else if ([state isEqual:@"error"]) {
        controller.displayState=@"error";
        controller.visibleError=@"暂时无法读取 Final Cut Pro 当前项目。已收到的成片音频仍保留，请打开对应的完整项目后重试。";
    } else if ([state isEqual:@"cloud"]) {
        SelectModel(controller,@"doubao-cloud");
    } else if ([state isEqual:@"setup-error"]) {
        controller.shareSetupStatus.stringValue=@"发现同名的不同预设，已保留原设置。请在 FCP「设置 → 目的位置」检查 SubPop 项目。";
        controller.shareSetupStatus.hidden=NO;
    } else if ([state isEqual:@"long-name"]) {
        controller.dropName=@"婚礼纪实完整成片 · 2026年十月海边仪式与晚宴精剪 · 原声对白和解说最终校对版 · 长项目名称显示检查（保留所有完整名称与原有时间线）";
    }
    [controller updateInterface];[controller.captionTable reloadData];
}

static void FreezeLayers(NSView *view) {
    // Capture stable final geometry/text, not the first transparent animation frame.
    [view.layer removeAllAnimations];
    for (NSView *child in view.subviews) FreezeLayers(child);
}

static NSDictionary *ControlGeometry(NSView *control,NSView *root) {
    NSRect frame=[control convertRect:control.bounds toView:root];
    return @{@"hidden":@(control.hidden),@"frame":NSStringFromRect(frame),@"insideWindow":@(NSContainsRect(root.bounds,frame))};
}

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc!=3) {
            fprintf(stderr,"Usage: SubPopStudioVisualTests <models.json> <30-caption fixture directory>\n");return 1;
        }
        @try {
            NSDictionary *catalog=ReadFixture([NSURL fileURLWithPath:@(argv[1])]);
            NSURL *fixtureDirectory=[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
            NSDictionary *fixture=ReadFixture([fixtureDirectory URLByAppendingPathComponent:@"captions.json"]);
            Require([catalog[@"models"] isKindOfClass:NSArray.class] && [catalog[@"defaultModelID"] isKindOfClass:NSString.class],@"Invalid model catalog");
            Require([fixture[@"captions"] isKindOfClass:NSArray.class] && [fixture[@"captions"] count]==30,@"Supply the existing 30-caption Studio layout fixture");
            NSData *titles=[NSData dataWithContentsOfURL:[fixtureDirectory URLByAppendingPathComponent:@"TitleProbe-1.14.fcpxml"]];
            Require(titles.length>0,@"Missing TitleProbe-1.14.fcpxml fixture");
            NSURL *output=[NSURL fileURLWithPath:@"/tmp/subpop-ui156" isDirectory:YES];
            NSError *error=nil;
            Require([NSFileManager.defaultManager createDirectoryAtURL:output withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error],@"Cannot create screenshot output directory");
            [NSApplication sharedApplication];
            NSArray *states=@[@"empty",@"project",@"pending",@"receiving",@"received",@"complete",@"warnings",@"error",@"cloud",@"setup-error",@"long-name"];
            NSArray *sizes=@[[NSValue valueWithSize:NSMakeSize(580,422)],[NSValue valueWithSize:NSMakeSize(660,740)],[NSValue valueWithSize:NSMakeSize(1100,740)]];
            NSMutableArray *captures=[NSMutableArray new];
            for (NSString *state in states) for (NSValue *sizeValue in sizes) {
                @autoreleasepool {
                    NSSize size=sizeValue.sizeValue;
                    SubPopVisualController *controller=[SubPopVisualController new];controller.previewCatalog=catalog;
                    [controller loadView];
                    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,size.width,size.height) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
                    window.releasedWhenClosed=NO;window.contentView=controller.view;
                    // The real FCP host owns the viewport size. This standalone
                    // window must likewise keep its assigned viewport rather
                    // than shrink-wrap the product's 800-point content column.
                    window.contentMinSize=size;window.contentMaxSize=size;
                    [window setContentSize:size];
                    [NSLayoutConstraint activateConstraints:@[[controller.view.widthAnchor constraintEqualToConstant:size.width],[controller.view.heightAnchor constraintEqualToConstant:size.height]]];
                    Configure(controller,state,fixture,titles);
                    [controller.view layoutSubtreeIfNeeded];
                    // Capture the same top-of-page starting position for all states.
                    [controller.pageScroll.documentView scrollPoint:NSZeroPoint];
                    [controller.view layoutSubtreeIfNeeded];FreezeLayers(controller.view);
                    NSSize actualSize=controller.view.bounds.size;
                    Require(fabs(actualSize.width-size.width)<.5 && fabs(actualSize.height-size.height)<.5,[NSString stringWithFormat:@"Wrong capture size for %@: requested %@, actual %@",state,NSStringFromSize(size),NSStringFromSize(actualSize)]);
                    Require(controller.host==nil && controller.timeline==nil && controller.bridgeTimer==nil && controller.bridgeURL==nil && controller.requestID==nil && controller.referenceRequestID==nil,@"Visual probe attempted to connect or run work");
                    NSBitmapImageRep *bitmap=[controller.view bitmapImageRepForCachingDisplayInRect:controller.view.bounds];
                    Require(bitmap!=nil,@"Cannot allocate screenshot bitmap");
                    [controller.view cacheDisplayInRect:controller.view.bounds toBitmapImageRep:bitmap];
                    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                    NSString *name=[NSString stringWithFormat:@"%@-%.0fx%.0f.png",state,size.width,size.height];
                    Require(png.length>0 && [png writeToURL:[output URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error],@"Cannot write screenshot PNG");
                    [captures addObject:@{@"state":state,@"file":name,@"width":@(actualSize.width),@"height":@(actualSize.height),@"requestedWidth":@(size.width),@"requestedHeight":@(size.height),@"pixelWidth":@(bitmap.pixelsWide),@"pixelHeight":@(bitmap.pixelsHigh),@"captionCount":@(controller.captionRows.count),
                        @"generate":ControlGeometry(controller.generateButton,controller.view),@"scope":ControlGeometry(controller.scopeLabel,controller.view),
                        @"status":ControlGeometry(controller.statusCard,controller.view),@"settings":ControlGeometry(controller.settingsCard,controller.view),
                        @"result":ControlGeometry(controller.resultView,controller.view),@"shareReceive":ControlGeometry(controller.shareReceiveButton,controller.view),
                        @"shareSection":ControlGeometry(controller.shareSection,controller.view),@"shareSetup":ControlGeometry(controller.shareSetupStatus,controller.view),
                        @"review":ControlGeometry(controller.reviewHeader,controller.view),@"recognitionReview":ControlGeometry(controller.recognitionReviewButton,controller.view),
                        @"audioScope":controller.audioPicker.selectedItem.title ?: @"",@"audioScopeEnabled":@(controller.audioPicker.enabled),
                        @"statusText":controller.statusDetail.stringValue ?: @"",@"projectName":controller.dropTitle.stringValue ?: @""}];
                    [controller.activity.wave setWorking:NO];[controller.signal setWorking:NO];
                    window.contentView=nil;[window close];
                }
            }
            NSData *index=[NSJSONSerialization dataWithJSONObject:@{@"scope":@"Offscreen AppKit fixture presentation at top-of-page only; no FCP, ASR or automatic scrolling validation",@"captures":captures} options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
            Require(index!=nil && [index writeToURL:[output URLByAppendingPathComponent:@"index.json"] options:NSDataWritingAtomic error:&error],@"Cannot write capture index");
            printf("Studio visual matrix: %lu offscreen PNGs in /tmp/subpop-ui156; no FCP, ASR or preference writes.\n",(unsigned long)captures.count);
            return 0;
        } @catch (NSException *exception) {
            fprintf(stderr,"Studio visual probe failure: %s\n",exception.reason.UTF8String);return 2;
        }
    }
}
