// Offscreen AppKit layout/motion checks. No FCP connection or timeline writes.
#import "ProbeViewController.m"
@interface SubPopPreviewController : SubPopProbeViewController
@property NSDictionary *previewCatalog;
@property NSUInteger importInvocationCount;
@end
@implementation SubPopPreviewController
- (NSDictionary *)readJSON:(NSURL *)url { return url ? [super readJSON:url] : self.previewCatalog; }
- (BOOL)workerAvailable { return YES; }
- (BOOL)selectedModelAvailable { return YES; }
- (BOOL)isolatedProjectActive { return YES; }
- (BOOL)canDragResult { return self.titlePayloads.count>0; }
- (void)restoreSession {}
- (void)importTitlesToFCP:(id)sender { self.importInvocationCount++; }
@end
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSDictionary *release=@{@"tag_name":@"v0.1.0.30",@"assets":@[@{@"name":@"SubPop.pkg"}]};
        if (![SubPopReleaseUpdate(release,@"0.1.0.28",@"owner/repo")[@"newer"] boolValue]) return 10;
        if ([SubPopReleaseUpdate(release,@"0.1.0.31",@"owner/repo")[@"newer"] boolValue]) return 11;
        if (SubPopReleaseUpdate(@{@"tag_name":@"v0.1.0-beta"},@"0.1.0.28",@"owner/repo")) return 12;
        NSString *sourceXML=@"<fcpxml><resources><asset id='r2' hasVideo='1' start='100s'><media-rep kind='original-media' src='file:///tmp/video.mp4'/></asset></resources><project><sequence tcStart='3600s'><spine><asset-clip ref='r2' offset='3600s' start='105s' duration='3s'/><gap offset='3603s' duration='2s'/><asset-clip ref='r2' offset='3605s' start='120s' duration='3s'/></spine></sequence></project></fcpxml>";
        NSData *sourceData=[sourceXML dataUsingEncoding:NSUTF8StringEncoding];
        if ([SubPopPreviewSource(sourceData,1)[@"seconds"] doubleValue]!=6 || [SubPopPreviewSource(sourceData,6)[@"seconds"] doubleValue]!=21 || SubPopPreviewSource(sourceData,4) || SubPopPreviewSource(nil,1)) return 23;
        NSString *retimed=[sourceXML stringByReplacingOccurrencesOfString:@"duration='3s'/>" withString:@"duration='3s'><timeMap/></asset-clip>"];
        if (SubPopPreviewSource([retimed dataUsingEncoding:NSUTF8StringEncoding],1)) return 24;
        if (argc!=3 && argc!=4) return 1;[NSApplication sharedApplication];
        SubPopPreviewController *c=[SubPopPreviewController new];
        c.previewCatalog=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
        [c loadView];NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,660,740) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.contentView=c.view;
        NSDictionary *m=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[@(argv[2]) stringByAppendingPathComponent:@"captions.json"]] options:0 error:nil];
        for (NSNumber *width in @[@580,@800,@1100]) {
            [window setContentSize:NSMakeSize(width.doubleValue,680)];[c.view layoutSubtreeIfNeeded];
            NSRect model=[c.modelPicker convertRect:c.modelPicker.bounds toView:c.view],audio=[c.audioPicker convertRect:c.audioPicker.bounds toView:c.view];
            if (model.size.width<100 || audio.size.width<100 || NSMaxX(model)>NSMinX(audio) || NSMaxX(audio)>width.doubleValue) return 2;
            c.resultManifest=m;c.captionRows=[m[@"captions"] mutableCopy];c.titlePayloads=@{@"1.14":[NSData data]};c.displayState=@"ready";[c updateInterface];[c.captionTable reloadData];[c.view layoutSubtreeIfNeeded];
            if (!c.captionScroll.hidden || c.resultView.hidden || c.captionTable.numberOfRows!=(NSInteger)[m[@"captions"] count]) return 3;
            if (width.intValue==580) {
                NSBitmapImageRep *image=[c.view bitmapImageRepForCachingDisplayInRect:c.view.bounds];[c.view cacheDisplayInRect:c.view.bounds toBitmapImageRep:image];
                [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/subpop-ready-preview.png" atomically:YES];
            }
            NSRect result=[c.resultView convertRect:c.resultView.bounds toView:c.view];
            if (NSMinY(result)<0 || NSMaxY(result)>c.view.bounds.size.height) return 7;
            [c toggleReview:nil];if (c.captionScroll.hidden || c.editorControls.hidden) return 8;
            [c toggleReview:nil];if (!c.captionScroll.hidden || !c.editorControls.hidden) return 9;
            [c.templatePicker selectItemAtIndex:1];[c updateInterface];
            if (![c usesFileImport] || ![c.resultView.accessibilityRole isEqual:NSAccessibilityButtonRole] || ![c.resultView.accessibilityLabel isEqual:@"导入字幕到 Final Cut Pro"] || !c.resultView.enabled) return 13;
            c.importInvocationCount=0;
            if (![c.resultView accessibilityPerformPress] || c.importInvocationCount!=1) return 17;
            [c.resultView performClick:nil];if (c.importInvocationCount!=2) return 18;
            NSEvent *click=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            [c.resultView mouseDown:click];if (c.importInvocationCount!=3) return 19;
            c.importInProgress=YES;[c updateInterface];if (c.resultView.enabled || [c.resultView accessibilityPerformPress]) return 14;
            c.importInProgress=NO;c.importMessage=@"已发送导入请求";[c updateInterface];
            if (![c.statusDetail.stringValue isEqual:c.importMessage]) return 15;
            if (width.intValue==580) {
                NSBitmapImageRep *image=[c.view bitmapImageRepForCachingDisplayInRect:c.view.bounds];[c.view cacheDisplayInRect:c.view.bounds toBitmapImageRep:image];
                [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/subpop-tap5a-import-preview.png" atomically:YES];
            }
            [c.templatePicker selectItemAtIndex:0];[c updateInterface];
            if ([c usesFileImport] || ![c.resultView.accessibilityLabel isEqual:@"拖回字幕到 Final Cut Pro"]) return 16;
            if ([c.resultView accessibilityPerformPress] || c.importInvocationCount!=3) return 20;
            c.requestID=@"preview";c.displayState=@"recognize";c.jobProgress=@.42;[c updateInterface];
            if (c.jobBar.hidden || fabs(c.jobBar.doubleValue-.42)>.001 || c.cancelButton.hidden || c.generateButton.enabled) return 4;
            if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && ![c.signal.bars[0] animationForKey:@"working"]) return 5;
            c.requestID=nil;c.displayState=@"ready";[c updateInterface];
            if ([c.signal.bars[0] animationForKey:@"working"]) return 6;
        }
        [c.templatePicker selectItemAtIndex:1];c.resultRequestID=@"style-test";[window orderFront:nil];
        if (argc==4) c.freshDropURL=[NSURL fileURLWithPath:@(argv[3])];
        [c showTap5aStyle:nil];
        if (c.tap5aStyleControls.count!=33 || !window.attachedSheet) return 21;
        [c fillTap5aStyleControls:@{@"outlineEnabled":@1,@"glowEnabled":@1,@"shadowEnabled":@1,@"roundness":@30,@"top":@25,@"textFont":@"Helvetica",@"textFace":@"Bold",@"textSize":@83,@"kerning":@4,@"lineSpacing":@16}];
        if ([c.tap5aStyleControls[@"roundness"] doubleValue]!=30 || [c.tap5aStyleControls[@"top"] doubleValue]!=25) return 22;
        if (![[c currentTap5aStyleValues][@"textFace"] isEqual:@"Bold"] || [[c currentTap5aStyleValues][@"textSize"] doubleValue]!=83 || [c.tap5aPreview.style[@"kerning"] doubleValue]!=4) return 28;
        NSButton *safe=[NSButton new];safe.state=NSControlStateValueOn;[c togglePreviewSafe:safe];
        if (!c.tap5aPreview.showsSafeArea || ![c.tap5aPreview.style[@"glowEnabled"] boolValue]) return 30;
        [c fullscreenPreview:nil];
        if (!c.tap5aPreview.fullscreenWindow.isVisible) return 32;
        SubPopStylePreview *full=(SubPopStylePreview *)c.tap5aPreview.fullscreenWindow.contentView;
        if (!full.showsSafeArea || ![full.style isEqual:c.tap5aPreview.style]) return 33;
        [full cancelOperation:nil];if (c.tap5aPreview.fullscreenWindow || !window.attachedSheet) return 34;
        safe.state=NSControlStateValueOff;[c togglePreviewSafe:safe];if (c.tap5aPreview.showsSafeArea) return 31;
        if (argc==4) {
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
            while (!c.tap5aPreview.frameImage && c.tap5aImageGenerator && [deadline timeIntervalSinceNow]>0) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            if (!c.tap5aPreview.frameImage) return 25;
            puts("Real source video preview frame decoded successfully.");
        }
        NSWindow *sheet=window.attachedSheet;[sheet.contentView layoutSubtreeIfNeeded];
        NSBitmapImageRep *sheetImage=[sheet.contentView bitmapImageRepForCachingDisplayInRect:sheet.contentView.bounds];[sheet.contentView cacheDisplayInRect:sheet.contentView.bounds toBitmapImageRep:sheetImage];
        [[sheetImage representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/subpop-style37.png" atomically:YES];
        [window endSheet:sheet returnCode:NSAlertThirdButtonReturn];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        if ([c.tap5aStyle[@"roundness"] doubleValue]!=30 || [[NSUserDefaults.standardUserDefaults dictionaryForKey:@"tap5aStylePreset"][@"top"] doubleValue]!=25 || c.tap5aPreview) return 26;
        if ([c.tap5aStyle[@"lineSpacing"] doubleValue]!=16 || ![c.sizePicker.titleOfSelectedItem isEqual:@"83"]) return 29;
        [c showTap5aStyle:nil];[c fillTap5aStyleControls:@{@"roundness":@80}];[window endSheet:window.attachedSheet returnCode:NSAlertSecondButtonReturn];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        if ([c.tap5aStyle[@"roundness"] doubleValue]!=30) return 27;
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"tap5aStylePreset"];
        puts("Studio layout: 580/800/1100 widths, 616-row editor, progress, cancellation and waveform start/stop passed.");return 0;
    }
}
