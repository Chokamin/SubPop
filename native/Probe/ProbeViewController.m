#import <Cocoa/Cocoa.h>
#import "ProbePresentation.h"
#import <ProExtension/ProExtension.h>
#import <ProExtensionHost/ProExtensionHost.h>
#import "AudioProbe.h"
#import <CommonCrypto/CommonDigest.h>
#import "StudioChrome.h"
#import "RuntimePaths.h"
#import "Updates.h"
#import "TitleDragProvider.h"
#import "TitleTemplates.h"
#import "Tap5aInstaller.h"
#import "Tap5aStyle.h"
#import "ScrubbableNumberField.h"
#import "Tap5aPreview.h"
#import "TitleImport.h"

static NSDictionary *Time(CMTime t) {
    return @{ @"value": @(t.value), @"timescale": @(t.timescale), @"flags": @(t.flags), @"epoch": @(t.epoch) };
}
@class SubPopProbeViewController;
@interface SubPopDocumentView : NSView
@end
@implementation SubPopDocumentView
- (BOOL)isFlipped { return YES; }
@end
@interface SubPopDropView : NSView <NSDraggingDestination>
@property (weak) SubPopProbeViewController *controller;
@property BOOL dragHover;
@end
@interface SubPopTitleDragView : NSButton
@property NSImage *hostIcon;
@property NSTrackingArea *hoverArea;
@property BOOL hovered;
@property (weak) SubPopProbeViewController *controller;
@end
@interface SubPopProbeViewController : NSViewController <FCPXTimelineObserver, NSDraggingSource, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
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
@property SubPopSignalView *signal;
@property NSProgressIndicator *jobBar;
@property NSStackView *reviewHeader;
@property NSButton *reviewToggle;
@property BOOL reviewExpanded;
@property NSTextField *captionCount;
@property NSString *lastVisualState;
@property SubPopActivityView *activity;
@property SubPopTitleDragView *resultView;
@property NSString *displayState;
@property NSString *dropName;
@property NSDate *engineLaunchDate;
@property NSArray *modelCatalog;
@property NSString *selectedModelID;
@property NSString *requestModelID;
@property NSString *dropUID;
@property CMTime dropDuration;
@property NSString *observedProjectUID;
@property CMTime observedProjectDuration;
@property NSPopUpButton *modelPicker;
@property NSPopUpButton *audioPicker;
@property NSPopUpButton *templatePicker;
@property NSDictionary *tap5aStyle;
@property SubPopStylePreview *tap5aPreview;
@property NSTextField *tap5aPreviewLabel;
@property NSInteger tap5aPreviewIndex;
@property NSUInteger tap5aPreviewGeneration;
@property AVAssetImageGenerator *tap5aImageGenerator;
@property NSMutableDictionary *tap5aStyleControls;
@property NSButton *tap5aStyleButton;
@property NSStackView *templateControls;
@property NSURL *tap5aURL;
@property BOOL tap5aScoped;
@property SubPopTap5aInstaller *tap5aInstaller;
@property BOOL importInProgress;
@property NSDate *lastImportAttempt;
@property NSString *importMessage;
@property NSPopUpButton *fontPicker;
@property NSPopUpButton *sizePicker;
@property NSTextField *modelDetail;
@property NSTextField *scopeLabel;
@property NSButton *cancelButton;
@property NSTableView *captionTable;
@property NSScrollView *captionScroll;
@property NSStackView *editorControls;
@property NSMutableArray *captionRows;
@property NSDictionary *resultManifest;
@property NSString *visibleError;
@property NSNumber *jobProgress;
@property NSString *cloudPhase;
@property NSString *resultRequestID;
@property BOOL restoringSession;
@property NSPopover *diagnostics;
@property NSButton *vocabularyButton;
@property NSButton *modelsButton;
@property NSAlert *updateAlert;
@property NSURL *updateURL;
@property NSArray *requestVocabulary;
@property NSAlert *modelAlert;
@property NSMutableDictionary *modelRows;
@property NSProgressIndicator *downloadProgress;
@property NSProgressIndicator *downloadSpinner;
@property NSTextField *downloadLabel;
@property NSButton *downloadCancel;
@property NSPopUpButton *downloadSourcePicker;
@property NSString *modelRequestID;
@property NSString *vocabularyDraft;
- (void)updateInterface;
- (BOOL)canDragResult;
- (BOOL)receivePasteboard:(NSPasteboard *)pasteboard;
- (void)beginTitleDrag:(NSEvent *)event fromView:(NSView *)view;
- (BOOL)usesFileImport;
- (void)importTitlesToFCP:(id)sender;
@end
@implementation SubPopDropView
- (void)drawRect:(NSRect)rect {
    NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:14 yRadius:14];
    [(self.dragHover ? [SubPopAccent() colorWithAlphaComponent:0.10] : [NSColor colorWithCalibratedWhite:.09 alpha:1]) setFill]; [path fill];
    [(self.dragHover ? SubPopAccent() : [NSColor colorWithCalibratedWhite:1 alpha:.14]) setStroke];
    CGFloat dash[]={5,4}; [path setLineDash:dash count:2 phase:0]; [path stroke];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    BOOL supported=NO;
    for (NSString *type in sender.draggingPasteboard.types) if ([type hasPrefix:@"com.apple.finalcutpro.xml"]) supported=YES;
    self.dragHover=supported; if (supported) SubPopReveal(self); [self setNeedsDisplay:YES]; return supported ? NSDragOperationCopy : NSDragOperationNone;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender { self.dragHover=NO; [self setNeedsDisplay:YES]; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.dragHover=NO; [self setNeedsDisplay:YES];
    return [self.controller receivePasteboard:sender.draggingPasteboard];
}
@end
@implementation SubPopTitleDragView
- (BOOL)isFlipped { return NO; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.bordered=NO;self.title=@"";[self setButtonType:NSButtonTypeMomentaryPushIn];
        NSURL *url=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.FinalCut"];
        NSString *appPath=url.path ?: @"/Applications/Final Cut Pro.app";
        self.hostIcon=[[NSImage alloc] initWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Contents/Resources/AppIcon.icns"]];
        if (!self.hostIcon) self.hostIcon=[NSImage imageWithSystemSymbolName:@"film.stack" accessibilityDescription:nil];
        self.toolTip=@"按住整张卡片，拖到原项目时间线起点的视频上方。落轨后选择“片段 → 将片段项分开”即可逐句编辑。";
    } return self;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea=[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil];[self addTrackingArea:self.hoverArea];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered=YES;[self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event { self.hovered=NO;[self setNeedsDisplay:YES]; }
- (void)resetCursorRects { if (self.enabled) [self addCursorRect:self.bounds cursor:[self.controller usesFileImport] ? NSCursor.pointingHandCursor : NSCursor.openHandCursor]; }
- (void)drawRect:(NSRect)rect {
    BOOL enabled=[self.controller canDragResult] && !self.controller.importInProgress;
    BOOL importing=[self.controller usesFileImport];
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:16 yRadius:16];
    NSColor *base=enabled ? [NSColor colorWithCalibratedRed:.32 green:.26 blue:.64 alpha:1] : NSColor.controlBackgroundColor;
    NSGradient *gradient=[[NSGradient alloc] initWithStartingColor:enabled ? [NSColor colorWithCalibratedRed:.43 green:.35 blue:(self.hovered ? .86 : .78) alpha:1] : base endingColor:base];[gradient drawInBezierPath:shape angle:-20];
    [[NSColor colorWithCalibratedWhite:1 alpha:self.hovered ? .32 : .16] setStroke];[shape stroke];
    [self.hostIcon drawInRect:NSMakeRect(20,35,50,50) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:enabled ? 1 : .4];
    NSString *title=self.controller.importInProgress ? @"正在发送到 Final Cut Pro…" : (enabled ? (importing ? @"导入字幕到 Final Cut Pro" : @"拖回字幕到 Final Cut Pro") : @"请先打开原项目时间线");
    [title drawAtPoint:NSMakePoint(86,73) withAttributes:@{NSForegroundColorAttributeName:NSColor.whiteColor,NSFontAttributeName:[NSFont systemFontOfSize:17 weight:NSFontWeightSemibold]}];
    NSString *detail=[NSString stringWithFormat:importing ? @"%lu 条字幕 · 点击导入，再从 FCP 浏览器拖回时间线" : @"%lu 条字幕已准备好 · 按住卡片拖到时间线起点上方",(unsigned long)self.controller.captionRows.count];
    [detail drawAtPoint:NSMakePoint(86,48) withAttributes:@{NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:1 alpha:.85],NSFontAttributeName:[NSFont systemFontOfSize:11]}];
    [(importing ? @"每次导入使用独立编号事件 · 对齐原项目起点" : @"落轨后：片段 → 将片段项分开，即可逐句编辑") drawAtPoint:NSMakePoint(86,24) withAttributes:@{NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:1 alpha:.72],NSFontAttributeName:[NSFont systemFontOfSize:10]}];
}
- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) return;
    if ([self.controller usesFileImport]) { if (event.clickCount<2) [self.controller importTitlesToFCP:self]; }
    else if ([self.controller canDragResult]) [self.controller beginTitleDrag:event fromView:self];
}
- (BOOL)accessibilityPerformPress {
    if (!self.enabled || ![self.controller usesFileImport]) return NO;
    [self.controller importTitlesToFCP:self];return YES;
}
@end
@implementation SubPopProbeViewController
#include "Updates.inc"
#include "TitleImport.inc"
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
#include "StudioLayout.inc"
#include "Tap5aStyle.inc"
- (void)restoreSession {
    if (self.restoringSession || self.requestID || self.titlePayloads || !self.bridgeURL || !self.timeline || ![self workerAvailable]) return;
    NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"pendingSession"];
    if (!saved || !self.observed || ![self.observedProjectUID isEqual:saved[@"projectUID"]] || !CMTIME_IS_NUMERIC(self.observedProjectDuration)) return;
    CMTime duration=CMTimeMake([saved[@"durationValue"] longLongValue],[saved[@"durationScale"] intValue]);
    if (!CMTIME_IS_NUMERIC(duration) || CMTimeCompare(self.observedProjectDuration,duration)!=0) return;
    self.restoringSession=YES;self.dropUID=saved[@"projectUID"];self.dropDuration=duration;self.dropName=saved[@"projectName"];
    NSString *file=saved[@"inputFile"];
    if ([file hasPrefix:@"drop-"] && [file.lastPathComponent isEqual:file]) { self.freshDropURL=[[self evidenceDirectory] URLByAppendingPathComponent:file];NSDate *captured=nil;[self.freshDropURL getResourceValue:&captured forKey:NSURLContentModificationDateKey error:nil];self.freshDropDate=captured; }
    self.requestVocabulary=saved[@"vocabulary"] ?: @[];self.requestID=saved[@"requestID"];self.requestSHA=saved[@"snapshotSHA"];self.requestModelID=saved[@"modelID"];self.requestGeneration=self.dropGeneration;self.displayState=@"validate";
    // Keep historical results, but do not reselect a model removed from the catalog.
    for (NSMenuItem *item in self.modelPicker.itemArray) if ([item.representedObject isEqual:self.requestModelID]) { self.selectedModelID=self.requestModelID;[self.modelPicker selectItem:item];break; }
    self.restoringSession=NO;
}
- (void)saveDraft {
    if (!self.resultRequestID || !self.titlePayloads || !self.captionRows) return;
    NSDictionary *draft=@{@"requestID":self.resultRequestID,@"snapshotSHA":self.requestSHA ?: @"",@"modelID":self.requestModelID ?: @"",@"captions":self.captionRows,@"font":self.fontPicker.titleOfSelectedItem,@"fontSize":self.sizePicker.titleOfSelectedItem,@"tap5aStyle":SubPopNormalizeTap5aStyle(self.tap5aStyle),@"titleTemplate":@(self.templatePicker.indexOfSelectedItem==1)};
    NSData *data=[NSJSONSerialization dataWithJSONObject:draft options:0 error:nil];[data writeToURL:[[self evidenceDirectory] URLByAppendingPathComponent:[@"draft-" stringByAppendingString:self.resultRequestID]] atomically:YES];
}
- (NSDictionary *)selectedModel {
    for (NSDictionary *model in self.modelCatalog) if ([model[@"id"] isEqual:self.selectedModelID]) return model;
    return @{};
}
- (BOOL)selectedCloudModel { return [[self selectedModel][@"engine"] isEqual:@"doubao"]; }
- (BOOL)selectedModelAvailable {
    NSDictionary *service=[self readJSON:[self.bridgeURL URLByAppendingPathComponent:@"service.json"]];
    for (NSDictionary *model in service[@"models"]) if ([model[@"id"] isEqual:self.selectedModelID]) return [model[@"installed"] boolValue];
    return NO;
}
- (void)modelChanged:(id)sender {
    if (self.requestID) return;
    self.selectedModelID=self.modelPicker.selectedItem.representedObject;
    [NSUserDefaults.standardUserDefaults setObject:self.selectedModelID forKey:@"selectedModelID"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.titlePayloads=nil;self.captionRows=nil;self.displayState=self.freshDropURL ? @"input" : @"idle";
    [self record:@{@"reason":@"model-selected",@"modelID":self.selectedModelID}];
}
- (void)audioChanged:(id)sender { if (!self.requestID) { [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.titlePayloads=nil;self.captionRows=nil;self.displayState=self.freshDropURL ? @"input" : @"idle";[self updateInterface]; } }
- (void)cancelJob:(id)sender {
    if (!self.requestID) return;
    NSURL *url=[[self.bridgeURL URLByAppendingPathComponent:self.requestID] URLByAppendingPathComponent:@"cancel.json"];
    [@"{}" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];self.cancelButton.enabled=NO;self.statusTitle.stringValue=@"正在取消…";
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.captionRows.count; }
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *caption=self.captionRows[row];if ([column.identifier isEqual:@"text"]) return caption[@"text"];
    NSArray *parts=[self.resultManifest[@"frameDuration"] componentsSeparatedByString:@"/"];
    double frame=[parts[0] doubleValue]/(parts.count==2 ? [parts[1] doubleValue] : 1);double value=[caption[@"start_frame"] doubleValue]*frame;
    return [NSString stringWithFormat:@"%02ld:%05.2f",(long)(value/60),fmod(value,60)];
}
- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSString *text=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || text.length>500) { NSBeep();return; }
    self.captionRows[row][@"text"]=text;[self rebuildTitles];
}
- (BOOL)resolveTap5a {
    if (self.tap5aURL && SubPopValidTap5a(self.tap5aURL)) return YES;
    NSData *bookmark=[NSUserDefaults.standardUserDefaults dataForKey:@"tap5aTemplateBookmark"];
    BOOL stale=NO;
    NSURL *url=bookmark ? [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil bookmarkDataIsStale:&stale error:nil] : nil;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    if (url && SubPopValidTap5a(url)) {
        if (self.tap5aScoped) [self.tap5aURL stopAccessingSecurityScopedResource];
        self.tap5aURL=url;self.tap5aScoped=scoped;
        if (stale) { NSData *fresh=[url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:nil];if (fresh) [NSUserDefaults.standardUserDefaults setObject:fresh forKey:@"tap5aTemplateBookmark"]; }
        return YES;
    }
    if (scoped) [url stopAccessingSecurityScopedResource];return NO;
}
- (BOOL)useInstalledTap5a:(NSURL *)url {
    NSError *error=nil;
    NSData *bookmark=[url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    if (!bookmark || !SubPopValidTap5a(url)) {
        NSAlert *alert=[NSAlert new];alert.messageText=@"无法使用这个模板";
        alert.informativeText=error.localizedDescription ?: @"请选择 Titles.localized 目录中已安装的 Tap5a Autosize Text Background.moti。";
        [alert runModal];return NO;
    }
    BOOL stale=NO;
    NSURL *scopedURL=[NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    BOOL scoped=[scopedURL startAccessingSecurityScopedResource];
    if(!scopedURL || !SubPopValidTap5a(scopedURL)) {
        if(scoped)[scopedURL stopAccessingSecurityScopedResource];
        NSAlert *alert=[NSAlert new];alert.messageText=@"模板访问授权未完成";alert.informativeText=@"请使用「选择已安装的模板」重新选择模板文件。";[alert runModal];return NO;
    }
    [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:@"tap5aTemplateBookmark"];
    if (self.tap5aScoped) [self.tap5aURL stopAccessingSecurityScopedResource];
    self.tap5aURL=scopedURL;self.tap5aScoped=scoped;
    [self.templatePicker selectItemAtIndex:1];[self rebuildTitles];return YES;
}
- (void)chooseTap5aTemplate {
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    panel.message=@"请选择已安装的 Tap5a Autosize Text Background.moti，之后会记住位置。";panel.prompt=@"使用此模板";
    struct passwd *entry=getpwuid(getuid());NSString *home=entry ? [NSString stringWithUTF8String:entry->pw_dir] : NSHomeDirectory();
    panel.directoryURL=[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Movies/Motion Templates.localized/Titles.localized/Tap5a/Tap5a Autosize Text Background"]];
    if ([panel runModal]==NSModalResponseOK) [self useInstalledTap5a:panel.URL];
}
- (void)downloadTap5aTemplate {
    if(self.tap5aInstaller)return;
    struct passwd *entry=getpwuid(getuid());NSString *home=entry ? [NSString stringWithUTF8String:entry->pw_dir] : NSHomeDirectory();
    NSURL *movies=[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Movies"]];
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.allowsMultipleSelection=NO;
    panel.directoryURL=movies;panel.prompt=@"授权并安装";
    panel.message=@"请选择当前用户的「影片」文件夹。SubPop 会在其中创建 Motion Templates 标题目录并安装 Tap5a，保留已有模板。";
    if([panel runModal]!=NSModalResponseOK)return;
    if(![panel.URL.URLByResolvingSymlinksInPath.path isEqual:movies.URLByResolvingSymlinksInPath.path]) {
        NSAlert *alert=[NSAlert new];alert.messageText=@"请选择当前用户的「影片」文件夹";alert.informativeText=@"模板必须安装到 Final Cut Pro 能识别的标题目录。请再次点击下载并安装。";[alert runModal];return;
    }
    NSAlert *progress=[NSAlert new];progress.messageText=@"正在下载并安装 Tap5a";
    progress.informativeText=@"从 Tap5a 作者源下载约 37 KB，校验后自动安装。完成后即可使用自适应底框。";
    [progress addButtonWithTitle:@"取消下载"];
    NSProgressIndicator *spinner=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0,0,280,16)];spinner.indeterminate=YES;spinner.style=NSProgressIndicatorStyleBar;[spinner startAnimation:nil];progress.accessoryView=spinner;
    SubPopTap5aInstaller *installer=[SubPopTap5aInstaller new];self.tap5aInstaller=installer;
    [progress beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result){if(result==NSAlertFirstButtonReturn)[installer cancel];}];
    [installer startAtMovies:panel.URL completion:^(NSURL *url,NSError *error){
        if(progress.window.sheetParent)[progress.window.sheetParent endSheet:progress.window returnCode:NSModalResponseStop];
        [spinner stopAnimation:nil];self.tap5aInstaller=nil;
        if(url){
            if(![self useInstalledTap5a:url])return;
            NSAlert *done=[NSAlert new];done.messageText=@"Tap5a 已就绪";done.informativeText=@"已选择自适应底框样式。如 Final Cut Pro 尚未显示新模板，请重新打开 Final Cut Pro。";[done runModal];
        } else if(![error.domain isEqual:NSURLErrorDomain] || error.code!=NSURLErrorCancelled) {
            NSAlert *failed=[NSAlert new];failed.messageText=@"Tap5a 安装未完成";failed.informativeText=error.localizedDescription ?: @"请重试或选择已安装的模板。";[failed runModal];
        }
    }];
}
- (void)templateChanged:(id)sender {
    [self.view.window makeFirstResponder:nil];
    if (self.templatePicker.indexOfSelectedItem==1 && ![self resolveTap5a]) {
        [self.templatePicker selectItemAtIndex:0];[self rebuildTitles];
        NSAlert *choice=[NSAlert new];choice.messageText=@"准备 Tap5a 自适应底框";
        choice.informativeText=@"可以从作者源下载并安装，也可以选择已经安装的模板。下载需要联网，并首次授权「影片」文件夹。";
        [choice addButtonWithTitle:@"下载并安装 Tap5a"];[choice addButtonWithTitle:@"选择已安装的模板…"];[choice addButtonWithTitle:@"取消"];
        NSModalResponse result=[choice runModal];
        if(result==NSAlertFirstButtonReturn)[self downloadTap5aTemplate];
        else if(result==NSAlertSecondButtonReturn)[self chooseTap5aTemplate];
        return;
    }
    [self rebuildTitles];
}
- (void)styleChanged:(id)sender {
    NSMutableDictionary *style=SubPopNormalizeTap5aStyle(self.tap5aStyle).mutableCopy;
    style[@"textFont"]=self.fontPicker.titleOfSelectedItem;style[@"textSize"]=@(self.sizePicker.titleOfSelectedItem.doubleValue);
    if (sender==self.fontPicker) style[@"textFace"]=@"Regular";
    self.tap5aStyle=SubPopNormalizeTap5aStyle(style);[self rebuildTitles];
}
- (void)rebuildTitles {
    if (!self.titlePayloads) return;
    NSMutableDictionary *updated=[NSMutableDictionary new];
    for (NSString *version in self.titlePayloads) {
        NSXMLDocument *doc=[[NSXMLDocument alloc] initWithData:self.titlePayloads[version] options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        if (!doc) return;
        SubPopSetTitleTemplate(doc,self.templatePicker.indexOfSelectedItem==1 ? self.tap5aURL : nil);
        if ([self usesFileImport]) SubPopApplyTap5aStyle(doc,self.tap5aStyle);
        SubPopApplyTitlePosition(doc,self.tap5aStyle);
        NSArray *titles=[doc nodesForXPath:@"/fcpxml/clip/spine/title" error:nil];
        if (titles.count!=self.captionRows.count) return;
        for (NSUInteger i=0;i<titles.count;i++) {
            NSXMLElement *title=titles[i];NSString *text=self.captionRows[i][@"text"];
            [title attributeForName:@"name"].stringValue=text;
            NSXMLNode *node=[title nodesForXPath:@"text/text-style" error:nil].firstObject;node.stringValue=text;
            NSXMLElement *style=[title nodesForXPath:@"text-style-def/text-style" error:nil].firstObject;
            NSMutableDictionary *textStyle=SubPopNormalizeTap5aStyle(self.tap5aStyle).mutableCopy;
            textStyle[@"textFont"]=self.fontPicker.titleOfSelectedItem;textStyle[@"textSize"]=@(self.sizePicker.titleOfSelectedItem.doubleValue);
            SubPopApplyTextStyle(style,textStyle);
        }
        updated[version]=[doc XMLDataWithOptions:NSXMLNodePrettyPrint];
    }
    if (![self.titlePayloads isEqual:updated]) self.importMessage=nil;
    self.titlePayloads=updated;[self.captionTable reloadData];[self saveDraft];[self updateInterface];
}
- (void)primaryAction:(id)sender { if (![self workerAvailable]) [self connectWorker:sender]; else [self startWorkerJob:sender]; }
- (void)showDiagnostics:(id)sender {
    if (!self.diagnostics) {
        self.diagnostics=[NSPopover new]; self.diagnostics.behavior=NSPopoverBehaviorTransient;
        NSViewController *controller=[NSViewController new]; controller.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,540,360)];
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(10,10,520,300)]; scroll.hasVerticalScroller=YES; scroll.documentView=self.output; [controller.view addSubview:scroll];
        NSArray *names=@[@"记录状态",@"重新检查上次拖入",@"音频探针"]; SEL actions[]={@selector(refresh:),@selector(recheckLastDrop:),@selector(probeAudio:)};
        for (NSUInteger i=0;i<3;i++) { NSButton *b=[NSButton buttonWithTitle:names[i] target:self action:actions[i]]; b.frame=NSMakeRect(10+i*174,322,164,28); [controller.view addSubview:b]; }
        self.diagnostics.contentViewController=controller;
    }
    [self.diagnostics showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSRectEdgeMaxY];
}
- (BOOL)canDragResult { return self.titlePayloads && self.resultDate && [self isolatedProjectActive]; }
- (BOOL)usesFileImport { return self.templatePicker.indexOfSelectedItem==1; }
- (void)consumeUIEvent:(NSDictionary *)event {
    NSString *reason=event[@"reason"], *status=event[@"status"];
    if ([event[@"error"] isKindOfClass:NSString.class]) self.visibleError=event[@"error"];
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
    [self restoreSession];
    [self updateModelManager];
    BOOL connected=[self workerAvailable], fresh=self.freshDropURL && self.freshDropDate;
    NSString *state=self.displayState ?: @"idle";
    if (([state isEqual:@"input"] && !fresh) || ([state isEqual:@"ready"] && ![self canDragResult])) state=@"expired";
    if ([state isEqual:@"preparing"] && connected) { self.engineLaunchDate=nil; self.displayState=fresh ? @"input" : @"idle"; state=self.displayState; }
    if ([state isEqual:@"preparing"] && self.engineLaunchDate && -self.engineLaunchDate.timeIntervalSinceNow>20) { self.displayState=@"setup-needed"; state=self.displayState; }
    if ([state isEqual:@"disconnected"] && connected) state=fresh ? @"input" : @"idle";
    if ([state isEqual:@"idle"] && !connected) state=@"disconnected";
    if (fresh && !self.requestID && ![self isolatedProjectActive]) state=@"inactive";
    NSDictionary *copy=SubPopPresentation(state); self.statusTitle.stringValue=copy[@"title"]; self.statusDetail.stringValue=copy[@"detail"];
    if ([state isEqual:@"error"] && self.visibleError.length) self.statusDetail.stringValue=self.visibleError;
    if ([state isEqual:@"recognize"] && self.jobProgress) self.statusTitle.stringValue=[NSString stringWithFormat:@"正在识别语音 · %.0f%%",100*self.jobProgress.doubleValue];
    self.serviceLabel.stringValue=connected ? @"● 本机就绪" : @"本机未连接";
    self.modelDetail.stringValue=[NSString stringWithFormat:@"%@ · %@ · %@",[self selectedModel][@"description"] ?: @"",[self selectedModelAvailable] ? @"已安装" : @"模型未就绪",[[self selectedModel][@"engine"] isEqual:@"mlx-whisper"] ? @"本机 MLX" : @"本机 CPU"];
    BOOL cloud=[self selectedCloudModel];
    if (cloud) self.modelDetail.stringValue=[NSString stringWithFormat:@"豆包云端 · %@ · 按账户计费",[self selectedModelAvailable] ? @"已配置，尚需有效服务额度" : @"请先配置 API Key"];
    self.scopeLabel.stringValue=cloud ? @"云端识别会上传音频至火山引擎 · 按账户计费" : @"音频留在本机  ·  字幕回到你的时间线";
    if (cloud && self.requestID && [state isEqual:@"recognize"]) self.statusDetail.stringValue=@{@"uploading":@"正在向豆包上传音频…",@"queued":@"音频已提交，正在等待云端处理…",@"processing":@"豆包 2.0 正在识别音频，完成后在本机整理字幕。"}[self.cloudPhase ?: @""] ?: @"正在提交音频，完成后在本机整理字幕。";
    self.serviceLabel.textColor=connected ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    self.dropTitle.stringValue=fresh ? (self.dropName ?: @"项目已导入") : @"把项目拖到这里";
    self.dropDetail.stringValue=fresh ? [NSString stringWithFormat:@"%02ld:%02ld · 整个项目 · 修改时间线后请重新拖入",(long)(CMTimeGetSeconds(self.dropDuration)/60),(long)CMTimeGetSeconds(self.dropDuration)%60] : @"从 Final Cut Pro 浏览器拖入整个项目";
    BOOL busy=self.requestID!=nil;BOOL managing=[self modelOperationBusy];
    BOOL preparing=[state isEqual:@"preparing"];
    self.generateButton.title=preparing ? @"正在准备…" : (busy ? @"正在处理…" : (connected ? (self.titlePayloads ? @"重新识别" : @"生成字幕") : @"准备本机识别"));
    self.generateButton.enabled=!managing && !preparing && !busy && (!connected || (fresh && [self isolatedProjectActive] && [self selectedModelAvailable]));
    self.vocabularyButton.enabled=!busy;self.vocabularyButton.title=[NSString stringWithFormat:@"词库 · %lu",(unsigned long)[self effectiveVocabulary].count];
    self.modelPicker.enabled=!busy && !managing;self.audioPicker.enabled=!busy;self.cancelButton.hidden=!busy;
    BOOL hasRows=self.titlePayloads && self.captionRows.count;
    self.templateControls.hidden=!hasRows;
    BOOL newlyReady=hasRows && self.resultView.hidden;
    if (newlyReady || !hasRows) self.reviewExpanded=NO;
    self.captionScroll.hidden=!hasRows || !self.reviewExpanded;self.editorControls.hidden=!hasRows || !self.reviewExpanded;self.resultView.hidden=!hasRows;self.reviewHeader.hidden=!hasRows;
    self.captionCount.stringValue=[NSString stringWithFormat:@"字幕预览  ·  %lu 条",(unsigned long)self.captionRows.count];
    self.reviewToggle.title=self.reviewExpanded ? @"收起预览与样式 ▴" : @"展开预览与样式 ▾";
    if (newlyReady) {SubPopReveal(self.resultView);[self.view layoutSubtreeIfNeeded];[self.resultView scrollRectToVisible:self.resultView.bounds];}
    self.jobBar.hidden=!(busy && [state isEqual:@"recognize"] && self.jobProgress);
    if (!self.jobBar.hidden) self.jobBar.doubleValue=self.jobProgress.doubleValue;
    [self.signal setWorking:managing && !busy && !preparing];
    [self.activity showStage:state active:busy || preparing];
    if (hasRows && [self.resultManifest[@"reviewWarnings"] count]) self.statusDetail.stringValue=[NSString stringWithFormat:@"已自动整理 · %lu 段时间需校对，保留原断句 · 拖回后可逐句编辑",(unsigned long)[self.resultManifest[@"reviewWarnings"] count]];
    if (self.lastVisualState && ![self.lastVisualState isEqual:state]) SubPopReveal(self.statusTitle);
    self.lastVisualState=state;
    if (connected && ![self selectedModelAvailable] && !busy) { self.statusTitle.stringValue=@"所选模型尚未就绪";self.statusDetail.stringValue=cloud ? @"点击“模型”，为豆包配置语音 API Key，或选择本机模型。" : @"点击“模型管理”下载，或选择已安装的模型。"; }

    BOOL ready=[self canDragResult];BOOL fileImport=[self usesFileImport];
    if (hasRows && fileImport && ready) {
        self.statusTitle.stringValue=self.importInProgress ? @"正在发送导入请求" : (self.importMessage.length ? @"Tap5a 字幕导入" : @"底框字幕已准备好");
        self.statusDetail.stringValue=self.importMessage ?: @"点击上方按钮导入 FCP，在本次新建的“SubPop 字幕”编号事件中拖出片段，对齐原项目起点。落轨后可将片段项分开。";
    }
    if (hasRows && [self.resultManifest[@"cloudCleanupPending"] unsignedIntegerValue]>0) self.statusDetail.stringValue=[self.statusDetail.stringValue stringByAppendingString:@" 旧版临时音频尚待清理，请打开云端设置查看。"];

    self.tap5aStyleButton.hidden=![self usesFileImport];self.tap5aStyleButton.enabled=!self.importInProgress;
    self.resultView.enabled=ready && !self.importInProgress;
    self.resultView.toolTip=fileImport ? @"点击导入到 FCP 浏览器。若出现资源库选择，请选择原项目所在资源库；在本次新建的编号事件中将字幕片段拖到原项目起点上方。每次导入都会保留旧版并新建事件。" : @"按住卡片拖到原项目时间线起点上方，落轨后将片段项分开。";
    [self.resultView setAccessibilityRole:fileImport ? NSAccessibilityButtonRole : NSAccessibilityGroupRole];
    [self.resultView setAccessibilityLabel:ready ? (fileImport ? @"导入字幕到 Final Cut Pro" : @"拖回字幕到 Final Cut Pro") : @"请先打开原项目时间线"];
    [self.resultView.window invalidateCursorRectsForView:self.resultView];[self.resultView setNeedsDisplay:YES];
}
- (void)toggleReview:(id)sender { self.reviewExpanded=!self.reviewExpanded;[self updateInterface]; }
- (NSDictionary *)readJSON:(NSURL *)url {
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (!data || data.length>32*1024*1024) return nil;
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
- (NSString *)sha256:(NSData *)data {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *sha=[NSMutableString new]; for (int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [sha appendFormat:@"%02x",digest[i]];
    return sha;
}
- (BOOL)isolatedProjectActive {
    CMTime duration=self.observedProjectDuration;
    return self.observed && self.dropUID.length && [self.dropUID isEqual:self.observedProjectUID] && CMTIME_IS_NUMERIC(duration) && CMTimeCompare(duration,self.dropDuration)==0;
}
- (BOOL)workerAvailable {
    NSDictionary *service=[self readJSON:[self.bridgeURL URLByAppendingPathComponent:@"service.json"]];
    NSNumber *heartbeat=service[@"heartbeat"];
    return [heartbeat isKindOfClass:NSNumber.class] && fabs(NSDate.date.timeIntervalSince1970-heartbeat.doubleValue)<10 && [service[@"protocol"] isEqual:@3];
}
- (void)showModelSettings:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"使用帮助";
    alert.informativeText=@"在主面板选择 Qwen3-ASR 0.6B 或 1.7B。选择会被记住，每次任务使用所选模型。缺少模型时，点击“模型管理”下载；“词库”可填写人名、品牌和专业词。\n\n默认仅识别对白角色。请在 FCP 将背景音乐设为“音乐”角色；需要保留全部声音时选择“所有音频”。\n\n视频类型不限，单次项目不设固定时长上限。长视频会分段识别，可随时取消。支持普通剪切、单声道／立体声及连接音频。暂不支持变速、多机位、复合片段、音频效果或音量关键帧。";
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
    NSString *root=SubPopWorkspace([NSBundle bundleForClass:self.class]);
    if (!url || stale || ![url.path.stringByStandardizingPath isEqual:[root stringByAppendingPathComponent:@".subloom/verification/bridge"]]) return NO;
    [self attachBridge:url]; return YES;
}
- (void)connectWorker:(id)sender {
    if (self.bridgeURL) { [self launchEngine]; return; }
    if ([self restoreBridge]) return;
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseDirectories=YES; panel.canChooseFiles=NO;
    panel.allowsMultipleSelection=NO; panel.prompt=@"允许并继续";
    NSString *workspace=SubPopWorkspace([NSBundle bundleForClass:self.class]);
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
    if (![self selectedCloudModel]) {[self submitWorkerJob];return;}
    if (self.requestID || ![self selectedModelAvailable]) return;
    NSString *model=self.selectedModelID;NSString *uid=self.dropUID;NSUInteger generation=self.dropGeneration;
    NSAlert *alert=[NSAlert new];alert.messageText=@"使用豆包云端识别？";
    alert.informativeText=@"所选范围的音频会直接发送给火山引擎的豆包录音文件识别 2.0。视频画面、项目文件和词库不上传，识别费用由你的火山引擎账户结算。\n\n取消或断网不会重新提交识别，已提交部分仍可能计费。";
    [alert addButtonWithTitle:@"上传并识别"];[alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response==NSAlertFirstButtonReturn && [self.selectedModelID isEqual:model] && [self.dropUID isEqual:uid] && self.dropGeneration==generation) [self submitWorkerJob];
    }];
}
- (void)submitWorkerJob {
    if (self.requestID || [self modelOperationBusy]) return;
    if (!self.bridgeURL || ![self workerAvailable] || ![self isolatedProjectActive]) {
        [self record:@{@"reason":@"worker-submit",@"status":@"connect-service-and-open-isolated-project-first"}]; return;
    }
    if (!self.freshDropURL || !self.freshDropDate) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-submit",@"status":@"fresh-project-drop-required",@"message":@"请重新拖入当前项目；旧快照不能重复识别"}]; return;
    }
    if (![self selectedModelAvailable]) return;
    NSURL *latest=self.freshDropURL; NSDate *latestDate=self.freshDropDate;
    NSData *original=[NSData dataWithContentsOfURL:latest];
    NSXMLDocument *xml=original ? [[NSXMLDocument alloc] initWithData:original options:NSXMLNodeLoadExternalEntitiesNever error:nil] : nil;
    NSArray *projects=[xml nodesForXPath:@"/fcpxml/project | /fcpxml/library/event/project" error:nil];
    if (projects.count!=1 || ![[projects[0] attributeForName:@"uid"].stringValue isEqual:self.dropUID]) {
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
    self.requestVocabulary=[self effectiveVocabulary];
    NSDictionary *manifest=@{@"cloudConsent":@([self selectedCloudModel]),@"vocabulary":self.requestVocabulary,@"requestID":request,@"projectUID":self.dropUID,@"xmlSHA256":sha,@"modelID":self.selectedModelID,@"audioMode":self.audioPicker.indexOfSelectedItem==0 ? @"dialogue" : @"all"};
    if (ok) ok=[[NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"request.json"] options:NSDataWritingAtomic error:&error];
    if (!ok) { [self record:@{@"reason":@"worker-submit",@"status":@"write-failed",@"error":error.localizedDescription ?: @""}]; return; }
    self.jobProgress=nil;self.visibleError=nil;self.requestGeneration=self.dropGeneration; self.requestModelID=self.selectedModelID;self.cancelButton.enabled=YES;
    self.requestID=request; self.requestSHA=sha; self.lastJobStage=nil; self.generateButton.enabled=NO;
    self.resultLoadAttempted=YES; self.titlePayloads=nil;
    [NSUserDefaults.standardUserDefaults setObject:@{@"vocabulary":self.requestVocabulary,@"requestID":request,@"snapshotSHA":sha,@"modelID":self.selectedModelID,@"projectUID":self.dropUID,@"projectName":self.dropName ?: @"",@"durationValue":@(self.dropDuration.value),@"durationScale":@(self.dropDuration.timescale),@"inputFile":latest.lastPathComponent} forKey:@"pendingSession"];
    [self record:@{@"reason":@"worker-submit",@"status":@"submitted",@"requestID":request,@"snapshotDate":latestDate.description ?: @"",@"source":@"received project snapshot; original capture date retained; edits after capture require another drop"}];
}
- (void)pollWorker:(NSTimer *)timer {
    [self updateInterface];
    if (!self.requestID) return;
    NSURL *directory=[self.bridgeURL URLByAppendingPathComponent:self.requestID isDirectory:YES];
    NSDictionary *response=[self readJSON:[directory URLByAppendingPathComponent:@"response.json"]];
    if (!response) {
        if (![self workerAvailable]) { self.generateButton.enabled=YES; [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.requestID=nil; [self record:@{@"reason":@"worker-result",@"status":@"service-disconnected"}]; }
        return;
    }
    if (![response[@"requestID"] isEqual:self.requestID]) return;
    self.cloudPhase=[response[@"cloudPhase"] isKindOfClass:NSString.class] ? response[@"cloudPhase"] : nil;
    self.jobProgress=[response[@"progress"] isKindOfClass:NSNumber.class] ? response[@"progress"] : nil;
    if ([response[@"status"] isEqual:@"ready"]) {
        NSMutableDictionary *payloads=[NSMutableDictionary new];
        BOOL valid=[(response[@"manifest"][@"vocabulary"] ?: @[]) isEqual:(self.requestVocabulary ?: @[])] && [response[@"modelID"] isEqual:self.requestModelID] && self.requestGeneration==self.dropGeneration && [self isolatedProjectActive] && [response[@"snapshotSHA256"] isEqual:self.requestSHA] &&
            [response[@"projectUID"] isEqual:self.dropUID] &&
            [response[@"payloads"] isKindOfClass:NSDictionary.class] && [response[@"outputs"] isKindOfClass:NSDictionary.class];
        if (valid) for (NSString *version in @[@"1.12",@"1.13",@"1.14"]) {
            id text=response[@"payloads"][version]; if (![text isKindOfClass:NSString.class]) { valid=NO; break; }
            NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
            NSString *name=[NSString stringWithFormat:@"TitleProbe-%@.fcpxml",version];
            if (![[self sha256:data] isEqual:response[@"outputs"][name]]) { valid=NO; break; }
            payloads[version]=data;
        }
        if (valid && payloads.count==3) { self.titlePayloads=payloads; self.resultDate=NSDate.date;self.resultManifest=response[@"manifest"];self.tap5aStyle=SubPopNormalizeTap5aStyle([NSUserDefaults.standardUserDefaults dictionaryForKey:@"tap5aStylePreset"]);NSString *presetFont=self.tap5aStyle[@"textFont"],*presetSize=[self.tap5aStyle[@"textSize"] stringValue];
            if (![self.fontPicker itemWithTitle:presetFont]) [self.fontPicker addItemWithTitle:presetFont];[self.fontPicker selectItemWithTitle:presetFont];
            if (![self.sizePicker itemWithTitle:presetSize]) [self.sizePicker addItemWithTitle:presetSize];[self.sizePicker selectItemWithTitle:presetSize];[self.templatePicker selectItemAtIndex:0];self.resultRequestID=self.requestID;self.captionRows=[NSMutableArray new];for (NSDictionary *row in response[@"manifest"][@"captions"]) [self.captionRows addObject:row.mutableCopy];
            NSDictionary *draft=[self readJSON:[[self evidenceDirectory] URLByAppendingPathComponent:[@"draft-" stringByAppendingString:self.requestID]]];
            if ([draft[@"snapshotSHA"] isEqual:self.requestSHA] && [draft[@"modelID"] isEqual:self.requestModelID] && [draft[@"captions"] isKindOfClass:NSArray.class] && [draft[@"captions"] count]==self.captionRows.count) {
                // Restore only text and presentation onto fresh, validated timing/payloads.
                self.tap5aStyle=SubPopNormalizeTap5aStyle(draft[@"tap5aStyle"]);
                if ([draft[@"titleTemplate"] boolValue] && [self resolveTap5a]) [self.templatePicker selectItemAtIndex:1];
                for (NSUInteger i=0;i<self.captionRows.count;i++) { id text=draft[@"captions"][i][@"text"];if ([text isKindOfClass:NSString.class] && [text length]>0 && [text length]<=500) self.captionRows[i][@"text"]=text; }
                if ([draft[@"font"] isKindOfClass:NSString.class] && ![self.fontPicker itemWithTitle:draft[@"font"]]) [self.fontPicker addItemWithTitle:draft[@"font"]];
                if ([self.fontPicker itemWithTitle:draft[@"font"]]) [self.fontPicker selectItemWithTitle:draft[@"font"]];
                if ([draft[@"fontSize"] isKindOfClass:NSString.class] && ![self.sizePicker itemWithTitle:draft[@"fontSize"]]) [self.sizePicker addItemWithTitle:draft[@"fontSize"]];
                if ([self.sizePicker itemWithTitle:draft[@"fontSize"]]) [self.sizePicker selectItemWithTitle:draft[@"fontSize"]];
                [self rebuildTitles];
            }
            [self.captionTable reloadData]; }
        [self record:@{@"reason":@"worker-result",@"status":self.titlePayloads ? @"ready-to-drag" : @"result-rejected",@"requestID":self.requestID,@"jobID":response[@"jobID"] ?: @""}];
        if (!self.titlePayloads) [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.requestID=nil; [self updateInterface];
    } else if ([response[@"status"] isEqual:@"blocked-no-audio"]) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-result",@"status":@"blocked-no-audio",@"message":@"整段音频为静音，未启动识别或生成字幕"}];
        if (!self.titlePayloads) [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.requestID=nil; [self updateInterface];
    } else if ([response[@"status"] isEqual:@"blocked-existing-titles"]) {
        self.titlePayloads=nil;
        [self record:@{@"reason":@"worker-result",@"status":@"blocked-existing-titles",@"stage":response[@"stage"] ?: @"conflict",@"collision":response[@"collision"] ?: @{},@"requestID":self.requestID,@"message":@"已有相同或重叠Title，未生成可拖出内容；保留现有编辑"}];
        if (!self.titlePayloads) [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.requestID=nil; [self updateInterface];
    } else if ([response[@"status"] isEqual:@"cancelled"]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.requestID=nil;self.displayState=@"cancelled";[self updateInterface];
    } else if ([response[@"status"] isEqual:@"failed"] || ![self workerAvailable]) {
        [self record:@{@"reason":@"worker-result",@"status":@"failed",@"error":response[@"error"] ?: @"service-disconnected"}];
        if (!self.titlePayloads) [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];self.requestID=nil; [self updateInterface];
    } else if (![self.lastJobStage isEqual:response[@"stage"]]) {
        self.lastJobStage=response[@"stage"];
        [self record:@{@"reason":@"worker-progress",@"status":response[@"stage"] ?: @"running",@"requestID":self.requestID}];
    }
}
- (void)beginTitleDrag:(NSEvent *)event fromView:(NSView *)view {
    if ([self usesFileImport]) return;
    [self.view.window makeFirstResponder:nil];
    if (!self.titlePayloads || !self.resultDate) { [self record:@{@"reason":@"title-drag-refused",@"status":@"Load a valid completed result first"}]; return; }
    if (![self isolatedProjectActive]) {
        [self record:@{@"reason":@"title-drag-refused",@"status":@"Open the unchanged source project first"}]; return;
    }
    NSString *previousTemplatePath=self.tap5aURL.path;
    if (self.templatePicker.indexOfSelectedItem==1 && ![self resolveTap5a]) {
        NSAlert *alert=[NSAlert new];alert.messageText=@"Tap5a 模板已移动或无法读取";alert.informativeText=@"请重新选择 Tap5a 样式并定位已安装模板，或切换为基础字幕。";[alert runModal];return;
    }
    if (self.templatePicker.indexOfSelectedItem==1 && ![previousTemplatePath isEqual:self.tap5aURL.path]) [self rebuildTitles];
    SubPopTitleDragProvider *provider=[[SubPopTitleDragProvider alloc] initWithPayloads:self.titlePayloads];
    __weak SubPopProbeViewController *weakSelf=self;
    NSUInteger generation=self.dropGeneration;
    provider.isCurrentProject=^BOOL { return weakSelf.dropGeneration==generation && [weakSelf isolatedProjectActive]; };
    NSPasteboardItem *item=[provider preparedItem];
    if (!item) return;
    NSDraggingItem *drag=[[NSDraggingItem alloc] initWithPasteboardWriter:item];
    NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(270,36)];
    [image lockFocus]; [[NSColor controlBackgroundColor] setFill]; NSRectFill(NSMakeRect(0,0,270,36));
    [@"SubPop · 整段字幕" drawAtPoint:NSMakePoint(8,10) withAttributes:@{NSForegroundColorAttributeName:NSColor.labelColor}]; [image unlockFocus];
    NSPoint point=[view convertPoint:event.locationInWindow fromView:nil];
    [drag setDraggingFrame:NSMakeRect(point.x,point.y,270,36) contents:image];
    [view beginDraggingSessionWithItems:@[drag] event:event source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context { return NSDragOperationCopy; }
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation {
    // A drag operation is not proof that FCP inserted the titles. Keep the result
    // and recovery session available; project observers still invalidate stale input.
    [self saveDraft];
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
    [self.activity.wave setWorking:NO];
    if (self.tap5aScoped) [self.tap5aURL stopAccessingSecurityScopedResource];self.tap5aScoped=NO;self.tap5aURL=nil;
    [self.bridgeTimer invalidate]; self.bridgeTimer=nil;
    if (self.bridgeScoped) [self.bridgeURL stopAccessingSecurityScopedResource];
    self.freshDropURL=nil; self.freshDropDate=nil; self.titlePayloads=nil; self.resultDate=nil; self.dropGeneration++;
    self.bridgeScoped=NO; self.bridgeURL=nil; self.requestID=nil; [self updateInterface];
    [self.timeline removeTimelineObserver:self]; self.timeline = nil; self.host = nil; self.observed = NO; self.observedProjectUID=nil;self.observedProjectDuration=kCMTimeInvalid;
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
    FCPXObject *project=sequence.container;
    self.observedProjectUID=project.objectType==kFCPXObjectType_Project ? [((FCPXProject *)project).UID copy] : nil;
    self.observedProjectDuration=sequence ? sequence.duration : kCMTimeInvalid;
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
- (void)playheadTimeChanged {
    // Captions are anchored to the whole project, never to the playhead.
    // Active-sequence and time-range observers continue to update identity/duration immediately.
    if (!self.observed) { self.observed=YES; [self snapshot:@"initialPlayheadState"]; }
}
- (void)validateDroppedProject {
    NSError *error=nil;
    NSData *data=[NSData dataWithContentsOfURL:self.freshDropURL options:0 error:&error];
    NSXMLDocument *doc=data ? [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:&error] : nil;
    NSArray *projects=[doc nodesForXPath:@"/fcpxml/project | /fcpxml/library/event/project" error:&error];
    NSString *activeUID=self.observedProjectUID;
    NSString *inputUID=projects.count==1 ? [projects[0] attributeForName:@"uid"].stringValue : nil;
    CMTime duration=self.observedProjectDuration;
    BOOL valid=projects.count==1 && activeUID.length && [inputUID isEqual:activeUID] && CMTIME_IS_NUMERIC(duration) && CMTimeGetSeconds(duration)>0;
    [self record:@{@"reason":@"drop-validation",@"projectCount":@(projects.count),@"inputUID":inputUID ?: @"",@"activeUID":activeUID ?: @"",@"duration":Time(duration),@"accepted":@(valid),@"error":error.localizedDescription ?: @""}];
    if (!valid) { self.freshDropURL=nil;self.freshDropDate=nil; }
    else { self.dropName=[projects[0] attributeForName:@"name"].stringValue;self.dropUID=inputUID.copy;self.dropDuration=duration; }
}
- (void)recheckLastDrop:(id)sender {
    if (self.requestID || self.titlePayloads) return;
    // Explicit recovery of a real drag record, never a fabricated new input.
    NSDictionary *last=nil;NSString *lastDate=@"",*lastConsumedDate=@"";
    for (NSURL *url in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self evidenceDirectory] includingPropertiesForKeys:nil options:0 error:nil]) {
        if (![url.pathExtension isEqual:@"json"]) continue;
        NSDictionary *record=[self readJSON:url];NSString *date=record[@"recordedAt"];
        if ([record[@"reason"] isEqual:@"title-drag-ended"] && [record[@"operation"] unsignedIntegerValue]!=NSDragOperationNone && [date isKindOfClass:NSString.class] && [date compare:lastConsumedDate]==NSOrderedDescending) lastConsumedDate=date;
        if ([record[@"reason"] isEqual:@"drop"] && [date isKindOfClass:NSString.class] && [date compare:lastDate]==NSOrderedDescending) { last=record;lastDate=date; }
    }
    NSDate *date=[[NSISO8601DateFormatter new] dateFromString:lastDate];
    if (!date || date.timeIntervalSinceNow>0 || -date.timeIntervalSinceNow>3600 || [lastConsumedDate compare:lastDate]!=NSOrderedAscending) return;
    NSString *file=nil;
    for (NSDictionary *item in last[@"xml"]) if ([item[@"saved"] boolValue] && (!file || [item[@"type"] isEqual:@"com.apple.finalcutpro.xml.v1-14"])) file=item[@"file"];
    if (![file hasPrefix:@"drop-"] || ![file.lastPathComponent isEqual:file]) return;
    self.freshDropURL=[[self evidenceDirectory] URLByAppendingPathComponent:file];self.freshDropDate=date;self.dropGeneration++;
    [self validateDroppedProject];
    self.displayState=self.freshDropURL ? @"input" : @"invalid-input";
    [self record:@{@"reason":@"recheck-real-drop",@"originalRecordedAt":lastDate,@"accepted":@(self.freshDropURL!=nil)}];
    [self.diagnostics close];[self updateInterface];
}
- (BOOL)receivePasteboard:(NSPasteboard *)pasteboard {
    if (self.requestID) return NO;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];
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
    if (self.freshDropURL) [self validateDroppedProject];
    [self record:@{@"reason":@"drop",@"types":pasteboard.types ?: @[],@"xml":saved}];
    return self.freshDropURL!=nil;
}
#include "Preferences.inc"
@end
