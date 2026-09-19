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
        NSDictionary *v1=@{@"tag_name":@"v1.0.0",@"assets":@[@{@"name":@"SubPop-1.0.0-arm64.pkg"}]};
        if(![SubPopReleaseUpdate(v1,@"0.1.0.58",@"owner/repo")[@"newer"] boolValue])return 90;
        if([SubPopReleaseUpdate(v1,@"1.0.0",@"owner/repo")[@"newer"] boolValue])return 91;
        if(![SubPopReleaseUpdate(@{@"tag_name":@"v1.0.1",@"assets":@[]},@"1.0.0",@"owner/repo")[@"newer"] boolValue])return 92;
        NSString *sourceXML=@"<fcpxml><resources><asset id='r2' hasVideo='1' start='100s'><media-rep kind='original-media' src='file:///tmp/video.mp4'/></asset></resources><project><sequence tcStart='3600s'><spine><asset-clip ref='r2' offset='3600s' start='105s' duration='3s'/><gap offset='3603s' duration='2s'/><asset-clip ref='r2' offset='3605s' start='120s' duration='3s'/></spine></sequence></project></fcpxml>";
        NSData *sourceData=[sourceXML dataUsingEncoding:NSUTF8StringEncoding];
        if ([SubPopPreviewSource(sourceData,1)[@"seconds"] doubleValue]!=6 || [SubPopPreviewSource(sourceData,6)[@"seconds"] doubleValue]!=21 || SubPopPreviewSource(sourceData,4) || SubPopPreviewSource(nil,1)) return 23;
        NSString *retimed=[sourceXML stringByReplacingOccurrencesOfString:@"duration='3s'/>" withString:@"duration='3s'><timeMap/></asset-clip>"];
        if (SubPopPreviewSource([retimed dataUsingEncoding:NSUTF8StringEncoding],1)) return 24;
        if (argc!=3 && argc!=4) return 1;[NSApplication sharedApplication];
        SubPopStylePreview *composite=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,0,640,360)];
        composite.frameImage=[NSImage imageWithSize:NSMakeSize(640,360) flipped:NO drawingHandler:^BOOL(NSRect rect) { [NSColor.whiteColor setFill];NSRectFill(rect);return YES;}];
        composite.caption=@"X";
        for (NSNumber *opacity in @[@0,@85,@100]) {
            composite.style=@{@"opacity":opacity,@"bottom":@100,@"top":@100,@"left":@100,@"right":@100,@"roundness":@0};
            composite.projectWidth=1920;NSImage *hd=[composite renderLinearPreview];
            composite.projectWidth=3840;NSImage *uhd=[composite renderLinearPreview];
            NSBitmapImageRep *hdPixels=[NSBitmapImageRep imageRepWithData:hd.TIFFRepresentation];
            NSBitmapImageRep *uhdPixels=[NSBitmapImageRep imageRepWithData:uhd.TIFFRepresentation];
            for (NSInteger y=0;y<360;y+=3) for (NSInteger x=0;x<640;x+=3) {
                NSColor *a=[[hdPixels colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                NSColor *b=[[uhdPixels colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                if (fabs(a.redComponent-b.redComponent)>.005) {NSLog(@"Resolution mismatch %ld %ld %@ %@",x,y,a,b);return 60;}
            }
            NSBitmapImageRep *pixels=[NSBitmapImageRep imageRepWithData:uhd.TIFFRepresentation];
            // The renderer already encodes sRGB; inspect its channel values directly.
            NSColor *pixel=[pixels colorAtX:320 y:340];
            double expected=opacity.intValue==0 ? 1 : (opacity.intValue==100 ? 0 : .42358);
            if (fabs(pixel.redComponent-expected)>.025 || fabs(pixel.greenComponent-expected)>.025) { NSLog(@"Linear composite mismatch %@: %@",opacity,pixel);return 61; }
        }
        SubPopPreviewController *c=[SubPopPreviewController new];
        c.previewCatalog=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
        [c loadView];NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,660,740) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.contentView=c.view;
        if (getenv("SUBPOP_ACTIVITY_PREVIEW")) {
            c.requestID=@"preview";c.displayState=@"recognize";c.jobProgress=@.42;[c updateInterface];
            window.title=@"SubPop · 识别动效预览";[window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[NSApp run];return 0;
        }
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
            if (c.activity.hidden || c.activity.stage!=1 || ![c.activity.currentLabel.stringValue containsString:@"聆听"]) return 70;
            if (c.jobBar.hidden || fabs(c.jobBar.doubleValue-.42)>.001 || c.cancelButton.hidden || c.generateButton.enabled) return 4;
            if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && ![c.activity.wave.bars[0] animationForKey:@"working"]) return 5;
            for (NSString *stage in @[@"decode",@"recognize",@"generate-titles"]) {
                [c.activity showStage:stage active:YES];[c.view layoutSubtreeIfNeeded];
                if (fabs(NSMidY(c.activity.currentLabel.frame)-NSMidY(c.activity.bounds))>.5 || c.activity.row.subviews.count!=2 || c.activity.wave.visualStage!=c.activity.stage || NSMaxX(c.activity.wave.frame)>NSMinX(c.activity.currentLabel.frame)) return 72;
            }
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.60]];
            if (c.activity.outgoingRow || c.activity.row.layer.filters.count || [c.activity.row.layer animationForKey:@"phase-change"]) return 73;
            c.requestID=nil;c.displayState=@"ready";[c updateInterface];
            if (!c.activity.hidden || c.activity.wave.running || c.activity.outgoingRow || c.activity.row.layer.filters.count) return 71;
            if ([c.activity.wave.bars[0] animationForKey:@"working"]) return 6;
        }
        [c.templatePicker selectItemAtIndex:1];c.resultRequestID=@"style-test";[window orderFront:nil];
        if (argc==4) c.freshDropURL=[NSURL fileURLWithPath:@(argv[3])];
        [c showTap5aStyle:nil];
        if (c.tap5aStyleControls.count!=35 || !window.attachedSheet) return 21;
        if(c.tap5aPreview.bounds.size.width<360 || c.tap5aPreview.bounds.size.width>640 || fabs(c.tap5aPreview.bounds.size.height/c.tap5aPreview.bounds.size.width-9.0/16)>.001) return 44;
        SubPopNumberField *scrub=c.tap5aStyleControls[@"positionX"];
        scrub.doubleValue=0;
        NSEvent *(^mouse)(NSEventType,CGFloat,NSEventModifierFlags)=^NSEvent *(NSEventType type,CGFloat x,NSEventModifierFlags flags){return [NSEvent mouseEventWithType:type location:NSMakePoint(x,0) modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];};
        [scrub mouseDown:mouse(NSEventTypeLeftMouseDown,100,0)];[scrub mouseDragged:mouse(NSEventTypeLeftMouseDragged,80,0)];
        if(scrub.doubleValue!=-20 || [c.tap5aPreview.style[@"positionX"] doubleValue]!=-20) return 45;
        [scrub mouseUp:mouse(NSEventTypeLeftMouseUp,80,0)];
        [scrub mouseDown:mouse(NSEventTypeLeftMouseDown,100,0)];[scrub mouseDragged:mouse(NSEventTypeLeftMouseDragged,115,NSEventModifierFlagShift)];
        if(scrub.doubleValue!=-18.5) return 46;
        [scrub mouseDragged:mouse(NSEventTypeLeftMouseDragged,200000,0)];if(scrub.doubleValue!=10000) return 47;
        [scrub mouseUp:mouse(NSEventTypeLeftMouseUp,200000,0)];
        for(NSString *key in @[@"positionX",@"textSize"]) {
            SubPopNumberField *field=c.tap5aStyleControls[key];field.doubleValue=123;
            SubPopResetLabel *label=nil;for(NSView *view in field.superview.subviews) if([view isKindOfClass:SubPopResetLabel.class] && [(SubPopResetLabel *)view numberField]==field) label=(SubPopResetLabel *)view;
            if(!label) return 48;
            [label resetClick:nil];if(field.doubleValue!=123) return 49;
            [label resetClick:nil];
            double expected=[key isEqual:@"positionX"] ? 0 : 72;
            if(field.doubleValue!=expected || [c.tap5aPreview.style[key] doubleValue]!=expected) return 50;
        }
        NSPopUpButton *families=c.tap5aStyleControls[@"textFont"];
        if((NSUInteger)families.numberOfItems!=NSFontManager.sharedFontManager.availableFontFamilies.count) return 40;
        for(NSString *family in @[@"PingFang SC",@"Alibaba PuHuiTi 3.0",@"Alimama ShuHeiTi"]) if(SubPopFontMembers(family).count) {
            [c fillTap5aStyleControls:@{@"textFont":family}];
            if(![SubPopSelectedFontFamily(families) isEqual:family] || ![[c currentTap5aStyleValues][@"textFont"] isEqual:family]) return 41;
            if([family isEqual:@"PingFang SC"] && [families.titleOfSelectedItem isEqual:family]) return 42;
            NSXMLElement *node=[NSXMLElement elementWithName:@"text-style"];SubPopApplyTextStyle(node,[c currentTap5aStyleValues]);
            if(![[node attributeForName:@"font"].stringValue isEqual:family]) return 43;
        }
        [c fillTap5aStyleControls:@{@"outlineEnabled":@1,@"glowEnabled":@1,@"shadowEnabled":@1,@"positionX":@120,@"positionY":@-80,@"roundness":@30,@"top":@25,@"textFont":@"Helvetica",@"textFace":@"Bold",@"textSize":@83,@"kerning":@4,@"lineSpacing":@16}];
        if ([c.tap5aStyleControls[@"roundness"] doubleValue]!=30 || [c.tap5aStyleControls[@"top"] doubleValue]!=25) return 22;
        if (![[c currentTap5aStyleValues][@"textFace"] isEqual:@"Bold"] || [[c currentTap5aStyleValues][@"textSize"] doubleValue]!=83 || [c.tap5aPreview.style[@"kerning"] doubleValue]!=4) return 28;
        NSTextField *size=c.tap5aStyleControls[@"textSize"];
        if (size.formatter) return 35;
        for (NSString *entry in @[@"1",@"12",@"128",@"7",@"7.5",@"350",@"999.5"]) {
            size.stringValue=entry;[c controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:size]];
            if (![size.stringValue isEqual:entry] || [c.tap5aPreview.style[@"textSize"] doubleValue]!=entry.doubleValue) return 36;
        }
        for (NSString *entry in @[@"",@"-",@"oops",@"12oops"]) {
            size.stringValue=entry;[c controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:size]];
            if (![size.stringValue isEqual:entry] || [c.tap5aPreview.style[@"textSize"] doubleValue]!=999.5) return 37;
        }
        size.stringValue=@"1200";[c controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:size]];
        if (size.doubleValue!=1000) return 38;
        size.stringValue=@"83";[c tap5aPreviewChanged:nil];
        if ([c.tap5aPreview.style[@"positionX"] doubleValue]!=120 || [c.tap5aPreview.style[@"positionY"] doubleValue]!=-80) return 39;
        NSButton *safe=[NSButton new];safe.state=NSControlStateValueOn;[c togglePreviewSafe:safe];
        if (!c.tap5aPreview.showsSafeArea || ![c.tap5aPreview.style[@"glowEnabled"] boolValue]) return 30;
        [c fullscreenPreview:nil];
        if (!c.tap5aPreview.fullscreenWindow.isVisible || c.tap5aPreview.fullscreenWindow.level<=NSPopUpMenuWindowLevel || ![(NSPanel *)c.tap5aPreview.fullscreenWindow hidesOnDeactivate]) return 32;
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
