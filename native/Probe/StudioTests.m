// Offscreen AppKit layout/motion checks. No FCP connection or timeline writes.
#import "ProbeViewController.m"
@interface SubPopPreviewController : SubPopProbeViewController
@property NSDictionary *previewCatalog;
@end
@implementation SubPopPreviewController
- (NSDictionary *)readJSON:(NSURL *)url { return url ? [super readJSON:url] : self.previewCatalog; }
- (BOOL)workerAvailable { return YES; }
- (BOOL)selectedModelAvailable { return YES; }
- (BOOL)isolatedProjectActive { return YES; }
- (BOOL)canDragResult { return self.titlePayloads.count>0; }
- (void)restoreSession {}
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
            c.requestID=@"preview";c.displayState=@"recognize";c.jobProgress=@.42;[c updateInterface];
            if (c.jobBar.hidden || fabs(c.jobBar.doubleValue-.42)>.001 || c.cancelButton.hidden || c.generateButton.enabled) return 4;
            if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && ![c.signal.bars[0] animationForKey:@"working"]) return 5;
            c.requestID=nil;c.displayState=@"ready";[c updateInterface];
            if ([c.signal.bars[0] animationForKey:@"working"]) return 6;
        }
        puts("Studio layout: 580/800/1100 widths, 616-row editor, progress, cancellation and waveform start/stop passed.");return 0;
    }
}
