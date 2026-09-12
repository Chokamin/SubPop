#import <Cocoa/Cocoa.h>
#import <ProExtension/ProExtension.h>
#import <ProExtensionHost/ProExtensionHost.h>
#import "AudioProbe.h"
#import <CommonCrypto/CommonDigest.h>

static NSDictionary *Time(CMTime t) {
    return @{ @"value": @(t.value), @"timescale": @(t.timescale), @"flags": @(t.flags), @"epoch": @(t.epoch) };
}
@class SubPopProbeViewController;
@interface SubPopDropView : NSView <NSDraggingDestination>
@property (weak) SubPopProbeViewController *controller;
@end
@interface SubPopTitleDragView : NSView
@property (weak) SubPopProbeViewController *controller;
@end
@interface SubPopProbeViewController : NSViewController <FCPXTimelineObserver, NSDraggingSource, NSPasteboardItemDataProvider>
@property id<FCPXHost> host;
@property FCPXTimeline *timeline;
@property NSTextView *output;
@property BOOL observed;
@property NSDictionary<NSString *, NSData *> *titlePayloads;
@property BOOL resultLoadAttempted;
@property NSURL *freshDropURL;
@property NSDate *freshDropDate;
@property NSDate *resultDate;
@property NSUInteger dropGeneration;
@property NSUInteger requestGeneration;
@property NSURL *bridgeURL;
@property BOOL bridgeScoped;
@property NSTimer *bridgeTimer;
@property NSString *requestID;
@property NSString *requestSHA;
@property NSString *lastJobStage;
@property NSButton *generateButton;
- (BOOL)receivePasteboard:(NSPasteboard *)pasteboard;
- (void)beginTitleDrag:(NSEvent *)event fromView:(NSView *)view;
@end
@implementation SubPopDropView
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { return NSDragOperationCopy; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender { return [self.controller receivePasteboard:sender.draggingPasteboard]; }
@end
@implementation SubPopTitleDragView
- (void)drawRect:(NSRect)rect {
    [[NSColor controlBackgroundColor] setFill]; NSRectFill(self.bounds);
    [@"拖出本次新 Title → 原项目起点上方" drawAtPoint:NSMakePoint(12,10) withAttributes:@{NSForegroundColorAttributeName:NSColor.labelColor,NSFontAttributeName:[NSFont systemFontOfSize:14]}];
}
- (void)mouseDown:(NSEvent *)event { [self.controller beginTitleDrag:event fromView:self]; }
@end
@implementation SubPopProbeViewController
- (NSURL *)evidenceDirectory {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [base URLByAppendingPathComponent:@"SubPopProbe"];
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return folder;
}
- (void)record:(NSDictionary *)value {
    NSMutableDictionary *record = value.mutableCopy;
    record[@"recordedAt"] = [[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.output.string = text ?: @"无法序列化";
    NSString *name = [NSString stringWithFormat:@"%@.json", NSUUID.UUID.UUIDString];
    [data writeToURL:[[self evidenceDirectory] URLByAppendingPathComponent:name] atomically:YES];
}
- (void)loadView {
    SubPopDropView *view = [[SubPopDropView alloc] initWithFrame:NSMakeRect(0,0,620,430)];
    view.controller = self;
    [view registerForDraggedTypes:@[@"com.apple.finalcutpro.xml.v1-14", @"com.apple.finalcutpro.xml.v1-13", @"com.apple.finalcutpro.xml.v1-12", @"com.apple.finalcutpro.xml.v1-11", @"com.apple.finalcutpro.xml.v1-10", @"com.apple.finalcutpro.xml", NSPasteboardTypeFileURL]];
    NSTextField *label = [NSTextField wrappingLabelWithString:@"SubPop 整段识别 · 连续单声道片段、空隙、静音、恒定音量\n每次识别前，将当前测试项目拖到此处；不跟随临时独奏监听。"];
    label.frame = NSMakeRect(16,365,588,52); label.autoresizingMask = NSViewWidthSizable|NSViewMinYMargin;
    [view addSubview:label];
    NSButton *refresh = [NSButton buttonWithTitle:@"记录当前状态" target:self action:@selector(refresh:)];
    refresh.frame = NSMakeRect(16,325,160,30); refresh.autoresizingMask = NSViewMinYMargin;
    [view addSubview:refresh];
    NSButton *diagnose = [NSButton buttonWithTitle:@"诊断只读通信" target:self action:@selector(diagnose:)];
    diagnose.frame = NSMakeRect(190,325,160,30); diagnose.autoresizingMask = NSViewMinYMargin;
    [view addSubview:diagnose];
    NSButton *audio = [NSButton buttonWithTitle:@"验证最近项目音频" target:self action:@selector(probeAudio:)];
    audio.frame = NSMakeRect(360,325,240,30); audio.autoresizingMask = NSViewMinYMargin;
    [view addSubview:audio];
    SubPopTitleDragView *drag = [[SubPopTitleDragView alloc] initWithFrame:NSMakeRect(184,267,420,42)];
    drag.controller=self; drag.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
    [drag setAccessibilityElement:YES]; [drag setAccessibilityRole:NSAccessibilityGroupRole];
    [drag setAccessibilityLabel:@"拖出本次新 Title 到原项目起点上方"];
    [view addSubview:drag];
    NSButton *connect=[NSButton buttonWithTitle:@"连接本机识别服务" target:self action:@selector(connectWorker:)];
    connect.frame=NSMakeRect(16,218,220,32); connect.autoresizingMask=NSViewMinYMargin; [view addSubview:connect];
    self.generateButton=[NSButton buttonWithTitle:@"识别刚拖入的项目" target:self action:@selector(startWorkerJob:)];
    self.generateButton.frame=NSMakeRect(250,218,350,32); self.generateButton.autoresizingMask=NSViewMinYMargin;
    [view addSubview:self.generateButton];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16,16,588,192)];
    scroll.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable; scroll.hasVerticalScroller = YES;
    self.output = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.output.editable = NO;
    self.output.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    scroll.documentView = self.output; [view addSubview:scroll]; self.view = view;
}
- (NSDictionary *)readJSON:(NSURL *)url {
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (!data || data.length>2*1024*1024) return nil;
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
- (NSString *)sha256:(NSData *)data {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *sha=[NSMutableString new]; for (int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [sha appendFormat:@"%02x",digest[i]];
    return sha;
}
- (BOOL)isolatedProjectActive {
    FCPXSequence *sequence=self.timeline.activeSequence;
    FCPXObject *container=sequence.container;
    return container.objectType==kFCPXObjectType_Project &&
        [((FCPXProject *)container).UID isEqual:@"0D11EC79-ED11-4688-97A9-CB78621857DD"] &&
        CMTIME_IS_NUMERIC(sequence.duration) && CMTimeCompare(sequence.duration,CMTimeMake(217,25))==0;
}
- (BOOL)workerAvailable {
    NSDictionary *service=[self readJSON:[self.bridgeURL URLByAppendingPathComponent:@"service.json"]];
    NSNumber *heartbeat=service[@"heartbeat"];
    return [heartbeat isKindOfClass:NSNumber.class] && fabs(NSDate.date.timeIntervalSince1970-heartbeat.doubleValue)<10 && [service[@"protocol"] isEqual:@1];
}
- (void)connectWorker:(id)sender {
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseDirectories=YES; panel.canChooseFiles=NO;
    panel.allowsMultipleSelection=NO; panel.message=@"选择 SubPop 的 .subloom/verification/bridge 任务目录（首次连接）";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response!=NSModalResponseOK) return;
        NSString *root=[[NSBundle bundleForClass:self.class] objectForInfoDictionaryKey:@"SubPopWorkspace"];
        NSString *expected=[root stringByAppendingPathComponent:@".subloom/verification/bridge"];
        if (![panel.URL.path.stringByStandardizingPath isEqual:expected]) { [self record:@{@"reason":@"worker-connect",@"status":@"wrong-directory"}]; return; }
        if (self.bridgeScoped) [self.bridgeURL stopAccessingSecurityScopedResource];
        self.bridgeURL=panel.URL; self.bridgeScoped=[panel.URL startAccessingSecurityScopedResource];
        [self.bridgeTimer invalidate];
        self.bridgeTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(pollWorker:) userInfo:nil repeats:YES];
        [self record:@{@"reason":@"worker-connect",@"status":[self workerAvailable] ? @"connected" : @"service-unavailable-open-SubPop-app"}];
    }];
}
- (void)startWorkerJob:(id)sender {
    if (self.requestID) return;
    if (!self.bridgeURL || ![self workerAvailable] || ![self isolatedProjectActive]) {
        [self record:@{@"reason":@"worker-submit",@"status":@"connect-service-and-open-isolated-project-first"}]; return;
    }
    if (!self.freshDropURL || !self.freshDropDate || -self.freshDropDate.timeIntervalSinceNow>300) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-submit",@"status":@"fresh-project-drop-required",@"message":@"请重新拖入当前项目；旧快照不能重复识别"}]; return;
    }
    NSURL *latest=self.freshDropURL; NSDate *latestDate=self.freshDropDate;
    NSData *original=[NSData dataWithContentsOfURL:latest];
    NSXMLDocument *xml=original ? [[NSXMLDocument alloc] initWithData:original options:NSXMLNodeLoadExternalEntitiesNever error:nil] : nil;
    NSArray *projects=[xml nodesForXPath:@"/fcpxml/project | /fcpxml/library/event/project" error:nil];
    if (projects.count!=1 || ![[projects[0] attributeForName:@"uid"].stringValue isEqual:@"0D11EC79-ED11-4688-97A9-CB78621857DD"]) {
        [self record:@{@"reason":@"worker-submit",@"status":@"matching-dropped-project-required"}]; return;
    }
    // Credentials from FCP drag are never handed to the unsandboxed worker.
    for (NSXMLNode *bookmark in [xml nodesForXPath:@"//bookmark" error:nil]) [bookmark detach];
    NSData *data=[xml XMLDataWithOptions:0];
    NSString *request=NSUUID.UUID.UUIDString.lowercaseString;
    NSURL *directory=[self.bridgeURL URLByAppendingPathComponent:request isDirectory:YES]; NSError *error=nil;
    BOOL ok=[[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:&error];
    if (ok) ok=[data writeToURL:[directory URLByAppendingPathComponent:@"input.fcpxml"] options:NSDataWritingAtomic error:&error];
    NSString *sha=[self sha256:data];
    NSDictionary *manifest=@{@"requestID":request,@"projectUID":@"0D11EC79-ED11-4688-97A9-CB78621857DD",@"xmlSHA256":sha};
    if (ok) ok=[[NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"request.json"] options:NSDataWritingAtomic error:&error];
    if (!ok) { [self record:@{@"reason":@"worker-submit",@"status":@"write-failed",@"error":error.localizedDescription ?: @""}]; return; }
    self.requestGeneration=self.dropGeneration; self.freshDropURL=nil;
    self.requestID=request; self.requestSHA=sha; self.lastJobStage=nil; self.generateButton.enabled=NO;
    self.resultLoadAttempted=YES; self.titlePayloads=nil;
    [self record:@{@"reason":@"worker-submit",@"status":@"submitted",@"requestID":request,@"snapshotDate":latestDate.description ?: @"",@"source":@"new drop in current session; edits after capture still require another drop"}];
}
- (void)pollWorker:(NSTimer *)timer {
    if (!self.requestID) return;
    NSURL *directory=[self.bridgeURL URLByAppendingPathComponent:self.requestID isDirectory:YES];
    NSDictionary *response=[self readJSON:[directory URLByAppendingPathComponent:@"response.json"]];
    if (!response) {
        if (![self workerAvailable]) { self.generateButton.enabled=YES; self.requestID=nil; [self record:@{@"reason":@"worker-result",@"status":@"service-disconnected"}]; }
        return;
    }
    if (![response[@"requestID"] isEqual:self.requestID]) return;
    if ([response[@"status"] isEqual:@"ready"]) {
        NSMutableDictionary *payloads=[NSMutableDictionary new];
        BOOL valid=self.requestGeneration==self.dropGeneration && [self isolatedProjectActive] && [response[@"snapshotSHA256"] isEqual:self.requestSHA] &&
            [response[@"projectUID"] isEqual:@"0D11EC79-ED11-4688-97A9-CB78621857DD"] &&
            [response[@"payloads"] isKindOfClass:NSDictionary.class] && [response[@"outputs"] isKindOfClass:NSDictionary.class];
        if (valid) for (NSString *version in @[@"1.12",@"1.13",@"1.14"]) {
            id text=response[@"payloads"][version]; if (![text isKindOfClass:NSString.class]) { valid=NO; break; }
            NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
            NSString *name=[NSString stringWithFormat:@"TitleProbe-%@.fcpxml",version];
            if (![[self sha256:data] isEqual:response[@"outputs"][name]]) { valid=NO; break; }
            payloads[version]=data;
        }
        if (valid && payloads.count==3) { self.titlePayloads=payloads; self.resultDate=NSDate.date; }
        [self record:@{@"reason":@"worker-result",@"status":self.titlePayloads ? @"ready-to-drag" : @"result-rejected",@"requestID":self.requestID,@"jobID":response[@"jobID"] ?: @""}];
        self.requestID=nil; self.generateButton.enabled=YES;
    } else if ([response[@"status"] isEqual:@"blocked-no-audio"]) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-result",@"status":@"blocked-no-audio",@"message":@"整段音频为静音，未启动识别或生成字幕"}];
        self.requestID=nil; self.generateButton.enabled=YES;
    } else if ([response[@"status"] isEqual:@"blocked-existing-titles"]) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-result",@"status":@"blocked-existing-titles",@"stage":response[@"stage"] ?: @"conflict",@"collision":response[@"collision"] ?: @{},@"requestID":self.requestID,@"message":@"已有相同或重叠Title，未生成可拖出内容；保留现有编辑"}];
        self.requestID=nil; self.generateButton.enabled=YES;
    } else if ([response[@"status"] isEqual:@"failed"] || ![self workerAvailable]) {
        [self record:@{@"reason":@"worker-result",@"status":@"failed",@"error":response[@"error"] ?: @"service-disconnected"}];
        self.requestID=nil; self.generateButton.enabled=YES;
    } else if (![self.lastJobStage isEqual:response[@"stage"]]) {
        self.lastJobStage=response[@"stage"];
        [self record:@{@"reason":@"worker-progress",@"status":response[@"stage"] ?: @"running",@"requestID":self.requestID}];
    }
}
- (void)beginTitleDrag:(NSEvent *)event fromView:(NSView *)view {
    if (!self.titlePayloads || !self.resultDate || -self.resultDate.timeIntervalSinceNow>300) { [self record:@{@"reason":@"title-drag-refused",@"status":@"Load a valid completed result first"}]; return; }
    FCPXSequence *sequence=self.timeline.activeSequence;
    FCPXObject *container=sequence.container;
    if (container.objectType!=kFCPXObjectType_Project ||
        ![((FCPXProject *)container).UID isEqual:@"0D11EC79-ED11-4688-97A9-CB78621857DD"] ||
        CMTimeCompare(sequence.duration,CMTimeMake(217,25))!=0) {
        [self record:@{@"reason":@"title-drag-refused",@"status":@"Open the unchanged isolated 8.68s original project first"}]; return;
    }
    NSPasteboardItem *item=[NSPasteboardItem new];
    [item setDataProvider:self forTypes:@[@"com.apple.finalcutpro.xml",@"com.apple.finalcutpro.xml.v1-14",@"com.apple.finalcutpro.xml.v1-13",@"com.apple.finalcutpro.xml.v1-12"]];
    NSDraggingItem *drag=[[NSDraggingItem alloc] initWithPasteboardWriter:item];
    NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(270,36)];
    [image lockFocus]; [[NSColor controlBackgroundColor] setFill]; NSRectFill(NSMakeRect(0,0,270,36));
    [@"SubPop · 整段字幕" drawAtPoint:NSMakePoint(8,10) withAttributes:@{NSForegroundColorAttributeName:NSColor.labelColor}]; [image unlockFocus];
    NSPoint point=[view convertPoint:event.locationInWindow fromView:nil];
    [drag setDraggingFrame:NSMakeRect(point.x,point.y,270,36) contents:image];
    [view beginDraggingSessionWithItems:@[drag] event:event source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context { return NSDragOperationCopy; }
- (void)pasteboard:(NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSPasteboardType)type {
    NSString *version=[type hasSuffix:@"v1-12"] ? @"1.12" : ([type hasSuffix:@"v1-13"] ? @"1.13" : @"1.14");
    NSData *data=self.titlePayloads[version];
    if (data) [item setData:data forType:type];
    [self record:@{@"reason":@"title-drag-data",@"type":type,@"version":version,@"bytes":@(data.length)}];
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation {
    if (operation!=NSDragOperationNone) { self.titlePayloads=nil; self.resultDate=nil; }
    [self record:@{@"reason":@"title-drag-ended",@"operation":@(operation),@"status":@"Host XML readback required; operation alone is not writeback proof"}];
}
- (void)viewDidAppear {
    [super viewDidAppear];
    id candidate = ProExtensionHostSingleton();
    if (![candidate conformsToProtocol:@protocol(FCPXHost)]) { [self record:@{@"status":@"host unavailable"}]; return; }
    self.host = candidate; self.timeline = self.host.timeline;
    [self record:@{@"status":@"waiting for timeline observer", @"host":self.host.name ?: @"", @"version":self.host.versionString ?: @"", @"bundle":self.host.bundleIdentifier ?: @""}];
    [self.timeline addTimelineObserver:self];
}
- (void)viewWillDisappear {
    [self.bridgeTimer invalidate]; self.bridgeTimer=nil;
    if (self.bridgeScoped) [self.bridgeURL stopAccessingSecurityScopedResource];
    self.freshDropURL=nil; self.freshDropDate=nil; self.titlePayloads=nil; self.resultDate=nil; self.dropGeneration++;
    self.bridgeScoped=NO; self.bridgeURL=nil; self.requestID=nil; self.generateButton.enabled=YES;
    [self.timeline removeTimelineObserver:self]; self.timeline = nil; self.host = nil; self.observed = NO;
    [super viewWillDisappear];
}
- (void)refresh:(id)sender { [self snapshot:@"manual"]; }
- (void)probeAudio:(NSButton *)sender {
    NSURL *directory=[self evidenceDirectory];
    NSArray<NSURL *> *files=[[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil];
    NSURL *latest=nil; NSDate *latestDate=nil;
    for (NSURL *file in files) {
        if (![file.lastPathComponent hasPrefix:@"drop-"] || ![file.pathExtension isEqual:@"fcpxml"]) continue;
        NSDate *date=nil; [file getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        if (!latest || [date compare:latestDate]==NSOrderedDescending) { latest=file; latestDate=date; }
    }
    FCPXObject *container=self.timeline.activeSequence.container;
    NSString *uid=container.objectType==kFCPXObjectType_Project ? ((FCPXProject *)container).UID : nil;
    if (!latest || !uid.length) { [self record:@{@"reason":@"audio-probe",@"status":@"missing dropped XML or active project"}]; return; }
    NSData *xml=[NSData dataWithContentsOfURL:latest];
    sender.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSMutableDictionary *result=[SubPopProbeAudio(xml,uid,directory) mutableCopy];
        result[@"reason"]=@"audio-probe"; result[@"xmlFile"]=latest.lastPathComponent;
        dispatch_async(dispatch_get_main_queue(), ^{ sender.enabled=YES; [self record:result]; });
    });
}
// Read only the application's public libraries collection; never modifies the timeline.
- (void)diagnose:(id)sender {
    NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:self.host.bundleIdentifier];
    NSMutableArray *results = [NSMutableArray new];
    for (NSRunningApplication *app in apps) {
        NSAppleEventDescriptor *spec = [NSAppleEventDescriptor recordDescriptor];
        [spec setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'fxlb'] forKeyword:'want'];
        [spec setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:'indx'] forKeyword:'form'];
        [spec setDescriptor:[NSAppleEventDescriptor descriptorWithInt32:1] forKeyword:'seld'];
        [spec setDescriptor:[NSAppleEventDescriptor nullDescriptor] forKeyword:'from'];
        NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:'core' eventID:'getd' targetDescriptor:[NSAppleEventDescriptor descriptorWithProcessIdentifier:app.processIdentifier] returnID:-1 transactionID:0];
        [event setParamDescriptor:[spec coerceToDescriptorType:'obj '] forKeyword:'----'];
        NSError *error = nil;
        NSAppleEventDescriptor *reply = [event sendEventWithOptions:NSAppleEventSendWaitForReply timeout:5 error:&error];
        [results addObject:@{@"pid":@(app.processIdentifier), @"bundle":app.bundleIdentifier ?: @"", @"path":app.bundleURL.path ?: @"", @"errorDomain":error.domain ?: @"", @"errorCode":@(error.code), @"replyError":@([[reply paramDescriptorForKeyword:'errn'] int32Value]), @"reply":reply.description ?: @"nil"}];
    }
    [self record:@{@"reason":@"public-library-read-diagnostic", @"runningHosts":results}];
}
- (void)snapshot:(NSString *)reason {
    if (!self.observed) { [self record:@{@"status":@"observer has not delivered state", @"reason":reason}]; return; }
    FCPXSequence *sequence = self.timeline.activeSequence;
    NSMutableDictionary *result = [@{@"reason":reason, @"host":self.host.name ?: @"", @"version":self.host.versionString ?: @"", @"bundle":self.host.bundleIdentifier ?: @"", @"hasSequence":@(sequence != nil), @"selectionAPI":@"sequenceTimeRange semantics require host testing", @"clipEnumerationAPI":@"not exposed by SDK 1.0.3", @"captionWriteAPI":@"not exposed by SDK 1.0.3"} mutableCopy];
    CMTimeRange observedRange = self.timeline.sequenceTimeRange;
    result[@"sequenceRange"] = @{@"start":Time(observedRange.start),@"duration":Time(observedRange.duration)};
    result[@"playhead"] = Time(self.timeline.playheadTime);
    if (sequence) {
        result[@"sequence"] = @{ @"name":sequence.name ?: @"", @"start":Time(sequence.startTime), @"duration":Time(sequence.duration), @"frameDuration":Time(sequence.frameDuration) };
        NSMutableArray *containers = [NSMutableArray new];
        FCPXObject *object = sequence.container;
        for (NSInteger depth=0; object && depth<5; depth++,object=object.container) {
            NSMutableDictionary *item = [@{@"type":@(object.objectType)} mutableCopy];
            if (object.objectType == kFCPXObjectType_Project) { item[@"uid"]=((FCPXProject *)object).UID; item[@"name"]=((FCPXProject *)object).name; }
            if (object.objectType == kFCPXObjectType_Event) { item[@"uid"]=((FCPXEvent *)object).UID; item[@"name"]=((FCPXEvent *)object).name; }
            if (object.objectType == kFCPXObjectType_Library) { item[@"url"]=((FCPXLibrary *)object).url.absoluteString; item[@"name"]=((FCPXLibrary *)object).name; }
            [containers addObject:item];
        }
        result[@"containers"]=containers;
    }
    [self record:result];
}
- (void)activeSequenceChanged { self.freshDropURL=nil; self.titlePayloads=nil; self.dropGeneration++; self.observed=YES; [self snapshot:@"activeSequenceChanged"]; }
- (void)sequenceTimeRangeChanged { self.observed=YES; [self snapshot:@"sequenceTimeRangeChanged"]; }
- (void)playheadTimeChanged { self.observed=YES; [self snapshot:@"playheadTimeChanged"]; }
- (BOOL)receivePasteboard:(NSPasteboard *)pasteboard {
    self.freshDropURL=nil; self.freshDropDate=nil; self.titlePayloads=nil; self.resultDate=nil; self.dropGeneration++;
    NSMutableArray *saved = [NSMutableArray new];
    for (NSPasteboardType type in pasteboard.types) {
        if (![type hasPrefix:@"com.apple.finalcutpro.xml"]) continue;
        NSData *data = [pasteboard dataForType:type];
        if (!data) continue;
        NSString *name = [NSString stringWithFormat:@"drop-%@.fcpxml",NSUUID.UUID.UUIDString];
        NSURL *url = [[self evidenceDirectory] URLByAppendingPathComponent:name];
        NSError *error = nil;
        BOOL ok = [data writeToURL:url options:NSDataWritingAtomic error:&error];
        if (ok && (!self.freshDropURL || [type isEqual:@"com.apple.finalcutpro.xml.v1-14"])) { self.freshDropURL=url; self.freshDropDate=NSDate.date; }
        [saved addObject:@{@"type":type,@"bytes":@(data.length),@"saved":@(ok),@"file":name,@"error":error.localizedDescription ?: @""}];
    }
    [self record:@{@"reason":@"drop",@"types":pasteboard.types ?: @[],@"xml":saved}];
    return saved.count>0;
}
@end
