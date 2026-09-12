#import <Cocoa/Cocoa.h>
#import "ProbePresentation.h"
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
@property BOOL dragHover;
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
@property NSTextField *statusTitle;
@property NSTextField *statusDetail;
@property NSTextField *serviceLabel;
@property NSTextField *dropTitle;
@property NSTextField *dropDetail;
@property NSTextField *steps;
@property NSProgressIndicator *spinner;
@property SubPopTitleDragView *resultView;
@property NSString *displayState;
@property NSString *dropName;
@property NSDate *engineLaunchDate;
@property NSButton *engineSettings;
@property NSPopover *diagnostics;
@property NSButton *diagnosticsButton;
- (void)updateInterface;
- (BOOL)canDragResult;
- (BOOL)receivePasteboard:(NSPasteboard *)pasteboard;
- (void)beginTitleDrag:(NSEvent *)event fromView:(NSView *)view;
@end
@implementation SubPopDropView
- (void)drawRect:(NSRect)rect {
    NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:12 yRadius:12];
    [(self.dragHover ? [NSColor.controlAccentColor colorWithAlphaComponent:0.12] : NSColor.controlBackgroundColor) setFill]; [path fill];
    [(self.dragHover ? NSColor.controlAccentColor : NSColor.separatorColor) setStroke];
    CGFloat dash[]={5,4}; [path setLineDash:dash count:2 phase:0]; [path stroke];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    BOOL supported=NO;
    for (NSString *type in sender.draggingPasteboard.types) if ([type hasPrefix:@"com.apple.finalcutpro.xml"]) supported=YES;
    self.dragHover=supported; [self setNeedsDisplay:YES]; return supported ? NSDragOperationCopy : NSDragOperationNone;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender { self.dragHover=NO; [self setNeedsDisplay:YES]; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.dragHover=NO; [self setNeedsDisplay:YES];
    return [self.controller receivePasteboard:sender.draggingPasteboard];
}
@end
@implementation SubPopTitleDragView
- (void)drawRect:(NSRect)rect {
    BOOL enabled=[self.controller canDragResult];
    [(enabled ? [NSColor.controlAccentColor colorWithAlphaComponent:0.14] : NSColor.controlBackgroundColor) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
    NSString *text=enabled ? @"↗  拖回字幕到 Final Cut Pro" : @"识别完成后，在这里拖回字幕";
    [text drawAtPoint:NSMakePoint(16,9) withAttributes:@{NSForegroundColorAttributeName:enabled ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]}];
}
- (void)mouseDown:(NSEvent *)event { if ([self.controller canDragResult]) [self.controller beginTitleDrag:event fromView:self]; }
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
    [self consumeUIEvent:value];
    NSString *name = [NSString stringWithFormat:@"%@.json", NSUUID.UUID.UUIDString];
    [data writeToURL:[[self evidenceDirectory] URLByAppendingPathComponent:name] atomically:YES];
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *label=[NSTextField wrappingLabelWithString:text];
    label.font=[NSFont systemFontOfSize:size weight:weight]; return label;
}
- (void)loadView {
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,620,460)]; self.view=view;
    NSStackView *stack=[NSStackView new]; stack.orientation=NSUserInterfaceLayoutOrientationVertical;
    stack.alignment=NSLayoutAttributeLeading; stack.spacing=10; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:20]]];
    NSView *header=[[NSView alloc] initWithFrame:NSMakeRect(0,0,572,46)];
    NSTextField *brand=[self label:@"SubPop" size:25 weight:NSFontWeightSemibold]; brand.frame=NSMakeRect(0,14,240,32); [header addSubview:brand];
    NSTextField *tagline=[self label:@"为完整视频生成中文字幕" size:12 weight:NSFontWeightRegular]; tagline.textColor=NSColor.secondaryLabelColor; tagline.frame=NSMakeRect(0,0,280,18); [header addSubview:tagline];
    NSButton *connect=[NSButton buttonWithTitle:@"模型与设置…" target:self action:@selector(showModelSettings:)]; self.engineSettings=connect;
    connect.bezelStyle=NSBezelStyleRounded; connect.frame=NSMakeRect(452,20,120,26); connect.autoresizingMask=NSViewMinXMargin; [header addSubview:connect];
    self.serviceLabel=[self label:@"Qwen3-ASR 0.6B · 本机" size:11 weight:NSFontWeightRegular]; self.serviceLabel.alignment=NSTextAlignmentRight;
    self.serviceLabel.frame=NSMakeRect(352,0,220,18); self.serviceLabel.autoresizingMask=NSViewMinXMargin; [header addSubview:self.serviceLabel];
    [stack addArrangedSubview:header]; [header.heightAnchor constraintEqualToConstant:46].active=YES;
    self.steps=[self label:@"1  导入项目       →       2  整段识别       →       3  拖回字幕" size:12 weight:NSFontWeightMedium];
    self.steps.textColor=NSColor.secondaryLabelColor; [stack addArrangedSubview:self.steps];
    SubPopDropView *drop=[[SubPopDropView alloc] initWithFrame:NSMakeRect(0,0,572,96)]; drop.controller=self;
    [drop registerForDraggedTypes:@[@"com.apple.finalcutpro.xml.v1-14",@"com.apple.finalcutpro.xml.v1-13",@"com.apple.finalcutpro.xml.v1-12",@"com.apple.finalcutpro.xml"]];
    [drop setAccessibilityElement:YES]; [drop setAccessibilityRole:NSAccessibilityGroupRole]; [drop setAccessibilityLabel:@"导入项目拖放区"];
    self.dropTitle=[self label:@"将项目拖到这里" size:17 weight:NSFontWeightSemibold]; self.dropTitle.frame=NSMakeRect(20,52,532,26); self.dropTitle.autoresizingMask=NSViewWidthSizable; [drop addSubview:self.dropTitle];
    self.dropDetail=[self label:@"从 Final Cut Pro 浏览器拖入当前项目。\n识别整个视频，无需选择片段。" size:12 weight:NSFontWeightRegular]; self.dropDetail.textColor=NSColor.secondaryLabelColor;
    self.dropDetail.frame=NSMakeRect(20,12,532,34); self.dropDetail.autoresizingMask=NSViewWidthSizable; [drop addSubview:self.dropDetail];
    [stack addArrangedSubview:drop]; [drop.heightAnchor constraintEqualToConstant:96].active=YES;
    NSView *status=[[NSView alloc] initWithFrame:NSMakeRect(0,0,572,106)];
    self.statusTitle=[self label:@"等待导入项目" size:17 weight:NSFontWeightSemibold]; self.statusTitle.frame=NSMakeRect(0,82,530,24); self.statusTitle.autoresizingMask=NSViewWidthSizable; [status addSubview:self.statusTitle];
    self.spinner=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(544,85,18,18)]; self.spinner.style=NSProgressIndicatorStyleSpinning; self.spinner.displayedWhenStopped=NO; self.spinner.autoresizingMask=NSViewMinXMargin; [status addSubview:self.spinner];
    self.statusDetail=[self label:@"" size:12 weight:NSFontWeightRegular]; self.statusDetail.textColor=NSColor.secondaryLabelColor;
    self.statusDetail.frame=NSMakeRect(0,40,572,34); self.statusDetail.autoresizingMask=NSViewWidthSizable; [status addSubview:self.statusDetail];
    self.resultView=[[SubPopTitleDragView alloc] initWithFrame:NSMakeRect(0,0,572,34)]; self.resultView.controller=self; self.resultView.autoresizingMask=NSViewWidthSizable;
    [self.resultView setAccessibilityElement:YES]; [self.resultView setAccessibilityRole:NSAccessibilityGroupRole]; [self.resultView setAccessibilityLabel:@"字幕拖出区，识别完成后可用"]; [status addSubview:self.resultView];
    [stack addArrangedSubview:status]; [status.heightAnchor constraintEqualToConstant:106].active=YES;
    self.generateButton=[NSButton buttonWithTitle:@"准备本机识别" target:self action:@selector(primaryAction:)]; self.generateButton.bezelStyle=NSBezelStyleRounded;
    self.generateButton.controlSize=NSControlSizeLarge; self.generateButton.keyEquivalent=@"\r"; self.generateButton.bezelColor=NSColor.controlAccentColor;
    [stack addArrangedSubview:self.generateButton]; [self.generateButton.heightAnchor constraintEqualToConstant:34].active=YES;
    NSTextField *scope=[self label:@"测试版 · 当前仅支持 Subloom-Original（8.68 秒）" size:11 weight:NSFontWeightRegular]; scope.textColor=NSColor.tertiaryLabelColor; [stack addArrangedSubview:scope];
    self.diagnosticsButton=[NSButton buttonWithTitle:@"诊断…" target:self action:@selector(showDiagnostics:)]; self.diagnosticsButton.bordered=NO; self.diagnosticsButton.font=[NSFont systemFontOfSize:11]; [stack addArrangedSubview:self.diagnosticsButton];
    for (NSView *row in stack.arrangedSubviews) if (row!=self.diagnosticsButton) [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    self.output=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,520,300)]; self.output.editable=NO; self.output.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.displayState=@"idle"; [self updateInterface];
}
- (void)primaryAction:(id)sender { if (![self workerAvailable]) [self connectWorker:sender]; else [self startWorkerJob:sender]; }
- (void)showDiagnostics:(id)sender {
    if (!self.diagnostics) {
        self.diagnostics=[NSPopover new]; self.diagnostics.behavior=NSPopoverBehaviorTransient;
        NSViewController *controller=[NSViewController new]; controller.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,540,360)];
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(10,10,520,300)]; scroll.hasVerticalScroller=YES; scroll.documentView=self.output; [controller.view addSubview:scroll];
        NSArray *names=@[@"记录状态",@"诊断通信",@"音频探针"]; SEL actions[]={@selector(refresh:),@selector(diagnose:),@selector(probeAudio:)};
        for (NSUInteger i=0;i<3;i++) { NSButton *b=[NSButton buttonWithTitle:names[i] target:self action:actions[i]]; b.frame=NSMakeRect(10+i*174,322,164,28); [controller.view addSubview:b]; }
        self.diagnostics.contentViewController=controller;
    }
    [self.diagnostics showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSRectEdgeMaxY];
}
- (BOOL)canDragResult { return self.titlePayloads && self.resultDate && -self.resultDate.timeIntervalSinceNow<=300 && [self isolatedProjectActive]; }
- (void)consumeUIEvent:(NSDictionary *)event {
    NSString *reason=event[@"reason"], *status=event[@"status"];
    if ([reason isEqual:@"drop"]) self.displayState=self.freshDropURL ? @"input" : @"invalid-input";
    else if ([reason isEqual:@"activeSequenceChanged"]) self.displayState=@"idle";
    else if ([reason isEqual:@"worker-connect"]) self.displayState=[status isEqual:@"connected"] ? (self.freshDropURL ? @"input" : @"idle") : ([status isEqual:@"wrong-directory"] ? @"wrong-directory" : @"disconnected");
    else if ([reason isEqual:@"worker-submit"]) self.displayState=[status isEqual:@"submitted"] ? @"validate" : ([status isEqual:@"fresh-project-drop-required"] ? @"expired" : @"error");
    else if ([reason isEqual:@"worker-progress"]) self.displayState=([status isEqual:@"starting"] || [status isEqual:@"running"]) ? @"validate" : status;
    else if ([reason isEqual:@"worker-result"]) {
        if ([status isEqual:@"ready-to-drag"]) self.displayState=@"ready";
        else if ([status isEqual:@"blocked-no-audio"]) self.displayState=@"silent";
        else if ([status isEqual:@"blocked-existing-titles"]) self.displayState=event[@"stage"] ?: @"conflict";
        else self.displayState=@"error";
    } else if ([reason isEqual:@"title-drag-ended"] && [event[@"operation"] unsignedIntegerValue]!=NSDragOperationNone) self.displayState=@"sent";
    else if ([reason isEqual:@"title-drag-refused"]) self.displayState=@"expired";
    [self updateInterface];
}
- (void)updateInterface {
    BOOL connected=[self workerAvailable], fresh=self.freshDropURL && self.freshDropDate && -self.freshDropDate.timeIntervalSinceNow<=300;
    NSString *state=self.displayState ?: @"idle";
    if (([state isEqual:@"input"] && !fresh) || ([state isEqual:@"ready"] && ![self canDragResult])) state=@"expired";
    if ([state isEqual:@"preparing"] && connected) { self.engineLaunchDate=nil; self.displayState=fresh ? @"input" : @"idle"; state=self.displayState; }
    if ([state isEqual:@"preparing"] && self.engineLaunchDate && -self.engineLaunchDate.timeIntervalSinceNow>20) { self.displayState=@"setup-needed"; state=self.displayState; }
    if ([state isEqual:@"disconnected"] && connected) state=fresh ? @"input" : @"idle";
    if ([state isEqual:@"idle"] && !connected) state=@"disconnected";
    if (fresh && !self.requestID && ![self isolatedProjectActive]) state=@"inactive";
    NSDictionary *copy=SubPopPresentation(state); self.statusTitle.stringValue=copy[@"title"]; self.statusDetail.stringValue=copy[@"detail"];
    self.serviceLabel.stringValue=connected ? @"● Qwen3-ASR 0.6B · 本机就绪" : @"Qwen3-ASR 0.6B · 本机";
    self.serviceLabel.textColor=connected ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    self.dropTitle.stringValue=fresh ? (self.dropName ?: @"项目已导入") : @"将项目拖到这里";
    self.dropDetail.stringValue=fresh ? @"完整视频 · 8.68 秒 · 中文字幕\n如已修改时间线，请重新拖入项目。" : @"从 Final Cut Pro 浏览器拖入当前项目。\n识别整个视频，无需选择片段。";
    BOOL busy=self.requestID!=nil;
    BOOL preparing=[state isEqual:@"preparing"];
    self.generateButton.title=preparing ? @"正在准备…" : (busy ? @"正在处理…" : (connected ? @"开始识别" : @"准备本机识别"));
    self.generateButton.enabled=!preparing && !busy && (!connected || (fresh && [self isolatedProjectActive]));
    if (busy || preparing) [self.spinner startAnimation:nil]; else [self.spinner stopAnimation:nil];
    BOOL ready=[self canDragResult]; [self.resultView setAccessibilityLabel:ready ? @"拖回字幕到 Final Cut Pro" : @"字幕拖出区，识别完成后可用"]; [self.resultView setNeedsDisplay:YES];
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
- (void)showModelSettings:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"识别模型";
    alert.informativeText=@"当前：Qwen3-ASR 0.6B（已安装）\n运行方式：本机 CPU\n\n目前只接入了这一款识别模型，尚不能切换到其他模型。时间对齐模型会自动配合运行。";
    [alert addButtonWithTitle:@"完成"]; [alert addButtonWithTitle:@"重新准备识别"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) { if (result==NSAlertSecondButtonReturn) [self connectWorker:nil]; }];
}
- (void)launchEngine {
    self.engineLaunchDate=NSDate.date; self.displayState=@"preparing"; [self updateInterface];
    NSWorkspaceOpenConfiguration *config=[NSWorkspaceOpenConfiguration configuration]; config.activates=NO;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"subpop-probe://start"] configuration:config completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (error) dispatch_async(dispatch_get_main_queue(), ^{ self.engineLaunchDate=nil; [self record:@{@"reason":@"worker-result",@"status":@"failed",@"error":error.localizedDescription ?: @""}]; });
    }];
}
- (void)attachBridge:(NSURL *)url {
    if (self.bridgeScoped) [self.bridgeURL stopAccessingSecurityScopedResource];
    self.bridgeURL=url; self.bridgeScoped=[url startAccessingSecurityScopedResource];
    [self.bridgeTimer invalidate]; self.bridgeTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(pollWorker:) userInfo:nil repeats:YES];
    if ([self workerAvailable]) [self record:@{@"reason":@"worker-connect",@"status":@"connected"}];
    else [self launchEngine];
}
- (BOOL)restoreBridge {
    NSData *data=[NSUserDefaults.standardUserDefaults dataForKey:@"taskDirectoryBookmark"];
    if (!data) return NO;
    BOOL stale=NO; NSURL *url=[NSURL URLByResolvingBookmarkData:data options:NSURLBookmarkResolutionWithSecurityScope|NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
    NSString *root=[[NSBundle bundleForClass:self.class] objectForInfoDictionaryKey:@"SubPopWorkspace"];
    if (!url || stale || ![url.path.stringByStandardizingPath isEqual:[root stringByAppendingPathComponent:@".subloom/verification/bridge"]]) return NO;
    [self attachBridge:url]; return YES;
}
- (void)connectWorker:(id)sender {
    if (self.bridgeURL) { [self launchEngine]; return; }
    if ([self restoreBridge]) return;
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseDirectories=YES; panel.canChooseFiles=NO;
    panel.allowsMultipleSelection=NO; panel.prompt=@"允许并继续";
    NSString *workspace=[[NSBundle bundleForClass:self.class] objectForInfoDictionaryKey:@"SubPopWorkspace"];
    NSString *expected=[workspace stringByAppendingPathComponent:@".subloom/verification/bridge"];
    panel.directoryURL=[NSURL fileURLWithPath:expected];
    panel.message=@"首次使用：允许 SubPop 处理本机字幕任务。请使用默认文件夹；之后会自动连接。";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response!=NSModalResponseOK) return;
        if (![panel.URL.path.stringByStandardizingPath isEqual:expected]) { [self record:@{@"reason":@"worker-connect",@"status":@"wrong-directory"}]; return; }
        NSData *data=[panel.URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
        if (data) [NSUserDefaults.standardUserDefaults setObject:data forKey:@"taskDirectoryBookmark"];
        [self attachBridge:panel.URL];
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
    [self updateInterface];
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
        self.requestID=nil; [self updateInterface];
    } else if ([response[@"status"] isEqual:@"blocked-no-audio"]) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-result",@"status":@"blocked-no-audio",@"message":@"整段音频为静音，未启动识别或生成字幕"}];
        self.requestID=nil; [self updateInterface];
    } else if ([response[@"status"] isEqual:@"blocked-existing-titles"]) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-result",@"status":@"blocked-existing-titles",@"stage":response[@"stage"] ?: @"conflict",@"collision":response[@"collision"] ?: @{},@"requestID":self.requestID,@"message":@"已有相同或重叠Title，未生成可拖出内容；保留现有编辑"}];
        self.requestID=nil; [self updateInterface];
    } else if ([response[@"status"] isEqual:@"failed"] || ![self workerAvailable]) {
        [self record:@{@"reason":@"worker-result",@"status":@"failed",@"error":response[@"error"] ?: @"service-disconnected"}];
        self.requestID=nil; [self updateInterface];
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
    [self restoreBridge];
}
- (void)viewWillDisappear {
    [self.bridgeTimer invalidate]; self.bridgeTimer=nil;
    if (self.bridgeScoped) [self.bridgeURL stopAccessingSecurityScopedResource];
    self.freshDropURL=nil; self.freshDropDate=nil; self.titlePayloads=nil; self.resultDate=nil; self.dropGeneration++;
    self.bridgeScoped=NO; self.bridgeURL=nil; self.requestID=nil; [self updateInterface];
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
    if (self.freshDropURL) {
        NSData *data=[NSData dataWithContentsOfURL:self.freshDropURL];
        NSXMLDocument *doc=[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        NSArray *projects=[doc nodesForXPath:@"/fcpxml/project | /fcpxml/library/event/project" error:nil];
        if (projects.count!=1 || ![[projects[0] attributeForName:@"uid"].stringValue isEqual:@"0D11EC79-ED11-4688-97A9-CB78621857DD"]) { self.freshDropURL=nil; self.freshDropDate=nil; }
        else self.dropName=[projects[0] attributeForName:@"name"].stringValue;
    }
    [self record:@{@"reason":@"drop",@"types":pasteboard.types ?: @[],@"xml":saved}];
    return self.freshDropURL!=nil;
}
@end
