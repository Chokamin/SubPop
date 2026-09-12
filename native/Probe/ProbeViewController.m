#import <Cocoa/Cocoa.h>
#import <ProExtension/ProExtension.h>
#import <ProExtensionHost/ProExtensionHost.h>
#import "AudioProbe.h"

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
    [@"拖出三条测试 Title → 原项目起点上方" drawAtPoint:NSMakePoint(12,10) withAttributes:@{NSForegroundColorAttributeName:NSColor.labelColor,NSFontAttributeName:[NSFont systemFontOfSize:14]}];
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
    NSTextField *label = [NSTextField wrappingLabelWithString:@"SubPop 接入探针 · 隔离项目验证\n将浏览器中的测试项目拖到此面板，检查交换数据。"];
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
    SubPopTitleDragView *drag = [[SubPopTitleDragView alloc] initWithFrame:NSMakeRect(16,267,588,42)];
    drag.controller=self; drag.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
    [drag setAccessibilityElement:YES]; [drag setAccessibilityRole:NSAccessibilityGroupRole];
    [drag setAccessibilityLabel:@"拖出三条测试 Title 到原项目起点上方"];
    [view addSubview:drag];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16,16,588,240)];
    scroll.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable; scroll.hasVerticalScroller = YES;
    self.output = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.output.editable = NO;
    self.output.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    scroll.documentView = self.output; [view addSubview:scroll]; self.view = view;
}
- (void)beginTitleDrag:(NSEvent *)event fromView:(NSView *)view {
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
    [@"SubPop · 3 Titles · 8.68s" drawAtPoint:NSMakePoint(8,10) withAttributes:@{NSForegroundColorAttributeName:NSColor.labelColor}]; [image unlockFocus];
    NSPoint point=[view convertPoint:event.locationInWindow fromView:nil];
    [drag setDraggingFrame:NSMakeRect(point.x,point.y,270,36) contents:image];
    [view beginDraggingSessionWithItems:@[drag] event:event source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context { return NSDragOperationCopy; }
- (void)pasteboard:(NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSPasteboardType)type {
    NSString *version=[type hasSuffix:@"v1-12"] ? @"1.12" : ([type hasSuffix:@"v1-13"] ? @"1.13" : @"1.14");
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:[@"TitleProbe-" stringByAppendingString:version] withExtension:@"fcpxml"];
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (data) [item setData:data forType:type];
    [self record:@{@"reason":@"title-drag-data",@"type":type,@"version":version,@"bytes":@(data.length)}];
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation {
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
- (void)activeSequenceChanged { self.observed=YES; [self snapshot:@"activeSequenceChanged"]; }
- (void)sequenceTimeRangeChanged { self.observed=YES; [self snapshot:@"sequenceTimeRangeChanged"]; }
- (void)playheadTimeChanged { self.observed=YES; [self snapshot:@"playheadTimeChanged"]; }
- (BOOL)receivePasteboard:(NSPasteboard *)pasteboard {
    NSMutableArray *saved = [NSMutableArray new];
    for (NSPasteboardType type in pasteboard.types) {
        if (![type hasPrefix:@"com.apple.finalcutpro.xml"]) continue;
        NSData *data = [pasteboard dataForType:type];
        if (!data) continue;
        NSString *name = [NSString stringWithFormat:@"drop-%@.fcpxml",NSUUID.UUID.UUIDString];
        NSURL *url = [[self evidenceDirectory] URLByAppendingPathComponent:name];
        NSError *error = nil;
        BOOL ok = [data writeToURL:url options:NSDataWritingAtomic error:&error];
        [saved addObject:@{@"type":type,@"bytes":@(data.length),@"saved":@(ok),@"file":name,@"error":error.localizedDescription ?: @""}];
    }
    [self record:@{@"reason":@"drop",@"types":pasteboard.types ?: @[],@"xml":saved}];
    return saved.count>0;
}
@end
