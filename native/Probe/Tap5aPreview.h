#import <AVFoundation/AVFoundation.h>

// FCP frame exports at 1920x1080: a 10-unit margin expands each side
// by 32 px horizontally and 18 px vertically. The rig's offsets use axis-
// relative units, so applying the horizontal conversion to Y is incorrect.
static CGFloat SubPopTap5aMargin(CGFloat value,CGFloat canvasAxis) {return value*canvasAxis/600.0;}
static NSArray *SubPopPreviewTextLines(NSString *text,NSDictionary *attributes,NSPoint baseline,CGFloat spacing,CGFloat scale,CGFloat maxWidth,NSRect *textBounds) {
    NSMutableArray *lines=[NSMutableArray new];NSRect bounds=NSZeroRect;BOOL hasBounds=NO;
    NSFont *font=attributes[NSFontAttributeName];
    CGFloat step=font.ascender-font.descender+font.leading+spacing;
    for (NSString *paragraph in [text componentsSeparatedByString:@"\n"]) {
        NSAttributedString *string=[[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
        CTTypesetterRef setter=CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)string);
        NSUInteger offset=0;
        do {
            NSUInteger count=paragraph.length ? MAX(1,CTTypesetterSuggestLineBreak(setter,offset,maxWidth)) : 0;
            count=MIN(count,paragraph.length-offset);
            CTLineRef line=CTTypesetterCreateLine(setter,CFRangeMake(offset,count));
            CGFloat ascent=0,descent=0;CGFloat width=CTLineGetTypographicBounds(line,&ascent,&descent,NULL);
            NSPoint origin=NSMakePoint(baseline.x-width/2,baseline.y);
            // Motion's Align To encloses typographic extents, including descenders,
            // rather than glyph ink or AppKit's extra line-fragment leading.
            // Its vertical raster guard is ~2 template pixels in the FCP fixture.
            NSRect placed=NSMakeRect(origin.x,origin.y-descent-2*scale,width,ascent+descent+4*scale);
            if (width>0) {bounds=hasBounds ? NSUnionRect(bounds,placed) : placed;hasBounds=YES;}
            [lines addObject:@{@"text":[paragraph substringWithRange:NSMakeRange(offset,count)],@"origin":[NSValue valueWithPoint:origin]}];
            CFRelease(line);baseline.y-=step;offset+=count;
        } while (offset<paragraph.length);
        CFRelease(setter);
    }
    *textBounds=hasBounds ? bounds : NSMakeRect(baseline.x,baseline.y,0,0);
    return lines;
}
static void SubPopDrawPreviewLines(NSArray *lines,NSDictionary *attributes) {
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow=attributes[NSShadowAttributeName];if(shadow) [shadow set];
    CGContextRef context=NSGraphicsContext.currentContext.CGContext;CGContextSetTextMatrix(context,CGAffineTransformIdentity);
    for (NSDictionary *item in lines) {
        NSAttributedString *string=[[NSAttributedString alloc] initWithString:item[@"text"] attributes:attributes];
        CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
        NSPoint origin=[item[@"origin"] pointValue];CGContextSetTextPosition(context,origin.x,origin.y);CTLineDraw(line,context);CFRelease(line);
    }
    [NSGraphicsContext restoreGraphicsState];
}

static double SubPopPreviewSeconds(NSString *value) {
    if (!value.length) return 0;
    NSString *s=[value hasSuffix:@"s"] ? [value substringToIndex:value.length-1] : value;
    NSArray *parts=[s componentsSeparatedByString:@"/"];if (parts.count>2) return NAN;
    double numerator=0,denominator=1;NSScanner *scan=[NSScanner scannerWithString:parts[0]];
    if (![scan scanDouble:&numerator] || !scan.isAtEnd) return NAN;
    if (parts.count==2) {scan=[NSScanner scannerWithString:parts[1]];if (![scan scanDouble:&denominator] || !scan.isAtEnd || denominator==0) return NAN;}
    return numerator/denominator;
}
// Resolve only ordinary primary-storyline cuts. Unsupported compositions are not
// presented as the final FCP frame: Motion/effects are rendered only by FCP.
static NSDictionary *SubPopPreviewSource(NSData *data, double seconds) {
    if (!data.length) return nil;
    NSXMLDocument *doc=[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
    NSXMLElement *sequence=[doc nodesForXPath:@"//project/sequence" error:nil].firstObject;
    if (!sequence || !isfinite(seconds)) return nil;
    double timeline=SubPopPreviewSeconds([sequence attributeForName:@"tcStart"].stringValue)+seconds;
    for (NSXMLElement *clip in [sequence nodesForXPath:@"spine/asset-clip" error:nil]) {
        double offset=SubPopPreviewSeconds([clip attributeForName:@"offset"].stringValue),duration=SubPopPreviewSeconds([clip attributeForName:@"duration"].stringValue);
        if (!(timeline>=offset && timeline<offset+duration) || [[clip attributeForName:@"enabled"].stringValue isEqual:@"0"]) continue;
        if ([clip nodesForXPath:@"timeMap|video|asset-clip|ref-clip|mc-clip|sync-clip" error:nil].count) return nil;
        for (NSXMLElement *rate in [clip elementsForName:@"conform-rate"]) if (![[rate attributeForName:@"scaleEnabled"].stringValue isEqual:@"0"]) return nil;
        NSString *ref=[clip attributeForName:@"ref"].stringValue;
        for (NSXMLElement *asset in [doc nodesForXPath:@"/fcpxml/resources/asset" error:nil]) {
            if (![[asset attributeForName:@"id"].stringValue isEqual:ref] || ![[asset attributeForName:@"hasVideo"].stringValue isEqual:@"1"]) continue;
            NSXMLElement *rep=[asset nodesForXPath:@"media-rep[@kind='original-media']" error:nil].firstObject;
            NSURL *url=[NSURL URLWithString:[rep attributeForName:@"src"].stringValue ?: @""];if (!url.isFileURL || (url.host.length && ![url.host isEqual:@"localhost"])) return nil;
            double start=SubPopPreviewSeconds([clip attributeForName:@"start"].stringValue ?: [asset attributeForName:@"start"].stringValue);
            double source=start-SubPopPreviewSeconds([asset attributeForName:@"start"].stringValue)+timeline-offset;
            if (!isfinite(source) || source<0) return nil;
            return @{@"url":url,@"seconds":@(source),@"bookmark":[[rep elementsForName:@"bookmark"].firstObject stringValue] ?: @""};
        }
    }
    return nil;
}

@interface SubPopPreviewPanel : NSPanel
@end
@implementation SubPopPreviewPanel
- (BOOL)canBecomeKeyWindow {return YES;}
- (BOOL)worksWhenModal {return YES;}
- (void)cancelOperation:(id)sender {[NSApp sendAction:@selector(closeFullscreen:) to:self.contentView from:sender];}
@end
@interface SubPopStylePreview : NSView
@property BOOL showsSafeArea;
@property NSWindow *fullscreenWindow;
@property (weak) SubPopStylePreview *fullscreenOwner;
- (void)showFullscreen;
- (void)closeFullscreen:(id)sender;
@property NSImage *frameImage;
@property NSDictionary *style;
@property NSString *caption;
@property NSString *fontName;
@property CGFloat fontSize;
@property CGFloat projectWidth;
@property NSString *placeholder;
@end
@implementation SubPopStylePreview
- (BOOL)acceptsFirstResponder {return YES;}
- (void)showFullscreen {
    if (self.fullscreenWindow) return;
    NSScreen *screen=self.window.screen ?: NSScreen.mainScreen;
    SubPopPreviewPanel *window=[[SubPopPreviewPanel alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];window.becomesKeyOnlyIfNeeded=NO;window.releasedWhenClosed=NO;// The FCP-hosted sheet is in another process; a modal level does not clear it.
    window.level=NSPopUpMenuWindowLevel+1;window.backgroundColor=NSColor.blackColor;window.hidesOnDeactivate=YES;
    SubPopStylePreview *preview=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,0,screen.frame.size.width,screen.frame.size.height)];
    preview.frameImage=self.frameImage;preview.style=self.style;preview.caption=self.caption;preview.projectWidth=self.projectWidth;preview.placeholder=self.placeholder;preview.showsSafeArea=self.showsSafeArea;preview.fullscreenOwner=self;preview.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    // In FCP, view-service windows are reparented by the host. Render locally,
    // then let the containing app own and activate the actual preview window.
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.chokamin.SubPopProbe.Extension"]) {
        NSBitmapImageRep *bitmap=[preview bitmapImageRepForCachingDisplayInRect:preview.bounds];
        [preview cacheDisplayInRect:preview.bounds toBitmapImageRep:bitmap];
        NSURL *folder=[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"SubPopPreview"];
        [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *file=[folder URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
        NSError *writeError=nil;
        if (![[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToURL:file options:NSDataWritingAtomic error:&writeError]) {NSLog(@"Preview render failed: %@",writeError);return;}
        NSURLComponents *request=[NSURLComponents componentsWithString:@"subpop-probe://preview"];
        request.queryItems=@[[NSURLQueryItem queryItemWithName:@"file" value:file.path]];
        NSWorkspaceOpenConfiguration *config=NSWorkspaceOpenConfiguration.configuration;config.activates=YES;
        NSURL *container=[NSBundle.mainBundle.bundleURL URLByDeletingLastPathComponent];container=[[container URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
        [NSWorkspace.sharedWorkspace openURLs:@[request.URL] withApplicationAtURL:container configuration:config completionHandler:^(NSRunningApplication *app,NSError *error) {if(error) {NSLog(@"Preview open failed: %@",error);[NSFileManager.defaultManager removeItemAtURL:file error:nil];}}];
        return;
    }
    window.contentView=preview;self.fullscreenWindow=window;
    NSButton *close=[NSButton buttonWithTitle:@"退出全屏" target:self action:@selector(closeFullscreen:)];close.keyEquivalent=@"\033";close.keyEquivalentModifierMask=0;close.bezelStyle=NSBezelStyleRounded;close.bordered=YES;close.frame=NSMakeRect(preview.bounds.size.width-150,preview.bounds.size.height-48,134,30);close.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;[preview addSubview:close];
    [window makeKeyAndOrderFront:nil];[window orderFrontRegardless];[window makeFirstResponder:preview];
}
- (void)closeFullscreen:(id)sender {if (self.fullscreenOwner) {[self.fullscreenOwner closeFullscreen:sender];return;}if (!self.fullscreenWindow) return;[self.fullscreenWindow orderOut:nil];[self.fullscreenWindow close];self.fullscreenWindow=nil;[self.window makeKeyAndOrderFront:nil];}
- (void)cancelOperation:(id)sender {[self closeFullscreen:sender];}
- (void)keyDown:(NSEvent *)event {if (event.keyCode==53 && self.fullscreenOwner) [self closeFullscreen:nil];else [super keyDown:event];}
// Motion SDR composites in linear RGB. Render the complete preview in that
// space, then let ColorSync convert the image for the display. Drawing an
// 85% black fill directly in an sRGB AppKit view otherwise looks too dark.
- (NSImage *)renderLinearPreview {
    CGFloat backing=self.window.backingScaleFactor ?: 1;
    backing=MIN(backing,4096/MAX(1,MAX(self.bounds.size.width,self.bounds.size.height)));
    size_t width=MAX(1,ceil(self.bounds.size.width*backing)),height=MAX(1,ceil(self.bounds.size.height*backing));
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    CGContextRef bitmap=CGBitmapContextCreate(NULL,width,height,32,0,space,(CGBitmapInfo)(kCGImageAlphaPremultipliedLast | kCGBitmapFloatComponents | kCGBitmapByteOrder32Little));
    CGColorSpaceRelease(space);
    if (!bitmap) return nil;
    CGContextScaleCTM(bitmap,backing,backing);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:bitmap flipped:NO];
    [self drawPreviewContent];
    [NSGraphicsContext restoreGraphicsState];
    CGImageRef image=CGBitmapContextCreateImage(bitmap);CGContextRelease(bitmap);
    if (!image) return nil;
    // Resolve the linear image into an explicitly tagged display bitmap before
    // NSImage caching/fullscreen PNG encoding; do not let TIFF infer a profile.
    CGColorSpaceRef outputSpace=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef output=CGBitmapContextCreate(NULL,width,height,8,0,outputSpace,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(outputSpace);
    if (!output) {CGImageRelease(image);return nil;}
    CGContextDrawImage(output,CGRectMake(0,0,width,height),image);CGImageRelease(image);
    CGImageRef display=CGBitmapContextCreateImage(output);CGContextRelease(output);
    NSImage *result=display ? [[NSImage alloc] initWithCGImage:display size:self.bounds.size] : nil;
    if (display) CGImageRelease(display);
    return result;
}
- (void)drawRect:(NSRect)dirty {
    NSImage *image=[self renderLinearPreview];
    if (image) [image drawInRect:self.bounds]; else [self drawPreviewContent];
}
- (void)drawPreviewContent {
    [[NSColor colorWithCalibratedWhite:.035 alpha:1] setFill];NSRectFill(self.bounds);
    NSRect canvas=self.bounds;
    if (self.frameImage) {
        NSSize size=self.frameImage.size;CGFloat scale=MIN(canvas.size.width/size.width,canvas.size.height/size.height);
        canvas=NSMakeRect((canvas.size.width-size.width*scale)/2,(canvas.size.height-size.height*scale)/2,size.width*scale,size.height*scale);
        [self.frameImage drawInRect:canvas];
    } else {
        NSDictionary *attrs=@{NSFontAttributeName:[NSFont systemFontOfSize:12],NSForegroundColorAttributeName:NSColor.secondaryLabelColor};
        [self.placeholder ?: @"正在读取视频画面…" drawInRect:NSInsetRect(self.bounds,16,30) withAttributes:attrs];
    }
    NSDictionary *s=SubPopNormalizeTap5aStyle(self.style);
    // Tap5a uses a 1920x1080 Motion canvas, independent of output resolution.
    // Project-pixel offsets keep their separate scale below.
    CGFloat scale=canvas.size.width/1920.0,fontSize=MAX(1,[s[@"textSize"] doubleValue]*scale);
    NSString *postscript=s[@"textFont"];for (NSArray *member in SubPopFontMembers(s[@"textFont"])) if ([member[1] isEqual:s[@"textFace"]]) postscript=member[0];
    NSFont *font=[NSFont fontWithName:postscript size:fontSize] ?: [NSFont systemFontOfSize:fontSize];
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentCenter;paragraph.lineSpacing=[s[@"lineSpacing"] doubleValue]*scale;
    NSArray *color=s[@"textColor"];
    NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:[NSColor colorWithSRGBRed:[color[0] doubleValue] green:[color[1] doubleValue] blue:[color[2] doubleValue] alpha:1],NSParagraphStyleAttributeName:paragraph,NSKernAttributeName:@([s[@"kerning"] doubleValue]*scale)};
    NSString *text=self.caption.length ? self.caption : @"让字幕跟上你的表达";
    CGFloat left=SubPopTap5aMargin([s[@"left"] doubleValue],canvas.size.width),right=SubPopTap5aMargin([s[@"right"] doubleValue],canvas.size.width),top=SubPopTap5aMargin([s[@"top"] doubleValue],canvas.size.height),bottom=SubPopTap5aMargin([s[@"bottom"] doubleValue],canvas.size.height);
    CGFloat positionScale=canvas.size.width/(self.projectWidth>0 ? self.projectWidth : 1920);
    // The exported title origin is 0,-40 percent of sequence height: its text
    // baseline is 10% above the bottom, including for non-1080p projects.
    NSPoint baseline=NSMakePoint(NSMidX(canvas)+[s[@"positionX"] doubleValue]*positionScale,NSMinY(canvas)+canvas.size.height*.10+[s[@"positionY"] doubleValue]*positionScale);
    NSRect textRect;NSArray *lines=SubPopPreviewTextLines(text,attrs,baseline,[s[@"lineSpacing"] doubleValue]*scale,scale,canvas.size.width*.86,&textRect);
    NSRect box=NSMakeRect(textRect.origin.x-left,textRect.origin.y-bottom,textRect.size.width+left+right,textRect.size.height+top+bottom);
    CGFloat radius=MIN(MIN(box.size.width,box.size.height)/2,[s[@"roundness"] doubleValue]*.5*scale);
    NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:box xRadius:radius yRadius:radius];
    NSArray *rgb=s[@"backgroundColor"];
    if ([s[@"background"] boolValue]) {[[NSColor colorWithSRGBRed:[rgb[0] doubleValue] green:[rgb[1] doubleValue] blue:[rgb[2] doubleValue] alpha:[s[@"opacity"] doubleValue]/100] setFill];[path fill];}
    if ([s[@"border"] boolValue]) {
        rgb=s[@"borderColor"];[[NSColor colorWithSRGBRed:[rgb[0] doubleValue] green:[rgb[1] doubleValue] blue:[rgb[2] doubleValue] alpha:[s[@"borderOpacity"] doubleValue]/100] setStroke];
        CGFloat width=MAX(.5,[s[@"width"] doubleValue]*scale);NSInteger sides=[s[@"sides"] integerValue];
        if (!sides) {path.lineWidth=width;[path stroke];}
        else {NSBezierPath *lines=[NSBezierPath bezierPath];lines.lineWidth=width;
            if (sides==1 || sides==5) {[lines moveToPoint:NSMakePoint(NSMinX(box),NSMaxY(box))];[lines lineToPoint:NSMakePoint(NSMaxX(box),NSMaxY(box))];}
            if (sides==2 || sides==5) {[lines moveToPoint:box.origin];[lines lineToPoint:NSMakePoint(NSMaxX(box),NSMinY(box))];}
            if (sides==3 || sides==6) {[lines moveToPoint:NSMakePoint(NSMaxX(box),NSMinY(box))];[lines lineToPoint:NSMakePoint(NSMaxX(box),NSMaxY(box))];}
            if (sides==4 || sides==6) {[lines moveToPoint:box.origin];[lines lineToPoint:NSMakePoint(NSMinX(box),NSMaxY(box))];}[lines stroke];}
    }
    NSMutableDictionary *draw=attrs.mutableCopy;
    if ([s[@"shadowEnabled"] boolValue]) {NSArray *c=s[@"shadowColor"];NSShadow *shadow=[NSShadow new];shadow.shadowColor=[NSColor colorWithSRGBRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:[s[@"shadowOpacity"] doubleValue]/100];CGFloat angle=[s[@"shadowAngle"] doubleValue]*M_PI/180,distance=[s[@"shadowDistance"] doubleValue]*scale;shadow.shadowOffset=NSMakeSize(cos(angle)*distance,sin(angle)*distance);shadow.shadowBlurRadius=[s[@"shadowBlur"] doubleValue]*scale;draw[NSShadowAttributeName]=shadow;SubPopDrawPreviewLines(lines,draw);[draw removeObjectForKey:NSShadowAttributeName];}
    if ([s[@"glowEnabled"] boolValue]) {NSShadow *glow=[NSShadow new];glow.shadowColor=[NSColor colorWithSRGBRed:1 green:.878431 blue:.262745 alpha:[s[@"glowOpacity"] doubleValue]/100];glow.shadowBlurRadius=([s[@"glowBlur"] doubleValue]+[s[@"glowRadius"] doubleValue])*scale;glow.shadowOffset=NSZeroSize;draw[NSShadowAttributeName]=glow;SubPopDrawPreviewLines(lines,draw);[draw removeObjectForKey:NSShadowAttributeName];}
    if ([s[@"outlineEnabled"] boolValue]) {NSArray *c=s[@"outlineColor"];draw[NSStrokeColorAttributeName]=[NSColor colorWithSRGBRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:[s[@"outlineOpacity"] doubleValue]/100];draw[NSStrokeWidthAttributeName]=@(-[s[@"outlineWidth"] doubleValue]/[s[@"textSize"] doubleValue]*100);}
    SubPopDrawPreviewLines(lines,draw);
    if (self.showsSafeArea) {
        [NSGraphicsContext saveGraphicsState];
        for (NSNumber *fraction in @[@0.05,@0.10]) {CGFloat inset=fraction.doubleValue;NSBezierPath *line=[NSBezierPath bezierPathWithRect:NSInsetRect(canvas,canvas.size.width*inset,canvas.size.height*inset)];line.lineWidth=1;CGFloat dash[]={5,4};[line setLineDash:dash count:2 phase:0];[[NSColor colorWithSRGBRed:1 green:.15 blue:.15 alpha:.95] setStroke];[line stroke];}
        [@"90% 动作安全区 · 80% 标题安全区" drawAtPoint:NSMakePoint(NSMinX(canvas)+12,NSMaxY(canvas)-26) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:NSColor.whiteColor,NSBackgroundColorAttributeName:[NSColor colorWithWhite:0 alpha:.6]}];[NSGraphicsContext restoreGraphicsState];
    }
}
@end
