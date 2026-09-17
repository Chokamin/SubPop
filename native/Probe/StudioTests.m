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
        if (argc!=3) return 1;[NSApplication sharedApplication];
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
        puts("Studio layout: 580/800/1100 widths, 616-row editor, progress, cancellation and waveform start/stop passed.");return 0;
    }
}
