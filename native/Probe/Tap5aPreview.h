#import <AVFoundation/AVFoundation.h>

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
    window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];window.becomesKeyOnlyIfNeeded=NO;window.releasedWhenClosed=NO;window.level=NSModalPanelWindowLevel;window.backgroundColor=NSColor.blackColor;window.hidesOnDeactivate=YES;
    SubPopStylePreview *preview=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,0,screen.frame.size.width,screen.frame.size.height)];
    preview.frameImage=self.frameImage;preview.style=self.style;preview.caption=self.caption;preview.projectWidth=self.projectWidth;preview.placeholder=self.placeholder;preview.showsSafeArea=self.showsSafeArea;preview.fullscreenOwner=self;preview.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    window.contentView=preview;self.fullscreenWindow=window;
    NSButton *close=[NSButton buttonWithTitle:@"退出全屏" target:self action:@selector(closeFullscreen:)];close.keyEquivalent=@"\033";close.keyEquivalentModifierMask=0;close.bezelStyle=NSBezelStyleRounded;close.bordered=YES;close.frame=NSMakeRect(preview.bounds.size.width-150,preview.bounds.size.height-48,134,30);close.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;[preview addSubview:close];
    [window makeKeyAndOrderFront:nil];[window makeFirstResponder:preview];
}
- (void)closeFullscreen:(id)sender {if (self.fullscreenOwner) {[self.fullscreenOwner closeFullscreen:sender];return;}[self.fullscreenWindow orderOut:nil];[self.fullscreenWindow close];self.fullscreenWindow=nil;[self.window makeKeyAndOrderFront:nil];}
- (void)cancelOperation:(id)sender {[self closeFullscreen:sender];}
- (void)keyDown:(NSEvent *)event {if (event.keyCode==53 && self.fullscreenOwner) [self closeFullscreen:nil];else [super keyDown:event];}
- (void)drawRect:(NSRect)dirty {
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
    CGFloat scale=canvas.size.width/MAX(1920,self.projectWidth),fontSize=MAX(1,[s[@"textSize"] doubleValue]*scale);
    NSString *postscript=s[@"textFont"];for (NSArray *member in SubPopFontMembers(s[@"textFont"])) if ([member[1] isEqual:s[@"textFace"]]) postscript=member[0];
    NSFont *font=[NSFont fontWithName:postscript size:fontSize] ?: [NSFont systemFontOfSize:fontSize];
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentCenter;paragraph.lineSpacing=[s[@"lineSpacing"] doubleValue]*scale;
    NSArray *color=s[@"textColor"];
    NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:[NSColor colorWithSRGBRed:[color[0] doubleValue] green:[color[1] doubleValue] blue:[color[2] doubleValue] alpha:1],NSParagraphStyleAttributeName:paragraph,NSKernAttributeName:@([s[@"kerning"] doubleValue]*scale)};
    NSString *text=self.caption.length ? self.caption : @"让字幕跟上你的表达";
    NSRect measured=[text boundingRectWithSize:NSMakeSize(canvas.size.width*.86,100) options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs];
    CGFloat left=[s[@"left"] doubleValue]*scale,right=[s[@"right"] doubleValue]*scale,top=[s[@"top"] doubleValue]*scale,bottom=[s[@"bottom"] doubleValue]*scale;
    NSRect textRect=NSMakeRect(NSMidX(canvas)-ceil(measured.size.width)/2,NSMinY(canvas)+canvas.size.height*.12,ceil(measured.size.width),ceil(measured.size.height));
    CGFloat positionScale=canvas.size.width/(self.projectWidth>0 ? self.projectWidth : 1920);
    textRect.origin.x+=[s[@"positionX"] doubleValue]*positionScale;textRect.origin.y+=[s[@"positionY"] doubleValue]*positionScale;
    NSRect box=NSMakeRect(textRect.origin.x-left,textRect.origin.y-bottom,textRect.size.width+left+right,textRect.size.height+top+bottom);
    CGFloat radius=MIN(box.size.height/2,[s[@"roundness"] doubleValue]*scale);
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
    if ([s[@"shadowEnabled"] boolValue]) {NSArray *c=s[@"shadowColor"];NSShadow *shadow=[NSShadow new];shadow.shadowColor=[NSColor colorWithSRGBRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:[s[@"shadowOpacity"] doubleValue]/100];CGFloat angle=[s[@"shadowAngle"] doubleValue]*M_PI/180,distance=[s[@"shadowDistance"] doubleValue]*scale;shadow.shadowOffset=NSMakeSize(cos(angle)*distance,sin(angle)*distance);shadow.shadowBlurRadius=[s[@"shadowBlur"] doubleValue]*scale;draw[NSShadowAttributeName]=shadow;[text drawInRect:textRect withAttributes:draw];[draw removeObjectForKey:NSShadowAttributeName];}
    if ([s[@"glowEnabled"] boolValue]) {NSShadow *glow=[NSShadow new];glow.shadowColor=[NSColor colorWithSRGBRed:1 green:.878431 blue:.262745 alpha:[s[@"glowOpacity"] doubleValue]/100];glow.shadowBlurRadius=([s[@"glowBlur"] doubleValue]+[s[@"glowRadius"] doubleValue])*scale;glow.shadowOffset=NSZeroSize;draw[NSShadowAttributeName]=glow;[text drawInRect:textRect withAttributes:draw];[draw removeObjectForKey:NSShadowAttributeName];}
    if ([s[@"outlineEnabled"] boolValue]) {NSArray *c=s[@"outlineColor"];draw[NSStrokeColorAttributeName]=[NSColor colorWithSRGBRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:[s[@"outlineOpacity"] doubleValue]/100];draw[NSStrokeWidthAttributeName]=@(-[s[@"outlineWidth"] doubleValue]/[s[@"textSize"] doubleValue]*100);}
    [text drawInRect:textRect withAttributes:draw];
    if (self.showsSafeArea) {
        [NSGraphicsContext saveGraphicsState];
        for (NSNumber *fraction in @[@0.05,@0.10]) {CGFloat inset=fraction.doubleValue;NSBezierPath *line=[NSBezierPath bezierPathWithRect:NSInsetRect(canvas,canvas.size.width*inset,canvas.size.height*inset)];line.lineWidth=1;CGFloat dash[]={5,4};[line setLineDash:dash count:2 phase:0];[[NSColor colorWithWhite:1 alpha:.8] setStroke];[line stroke];}
        [@"90% 动作安全区 · 80% 标题安全区" drawAtPoint:NSMakePoint(NSMinX(canvas)+12,NSMaxY(canvas)-26) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:NSColor.whiteColor,NSBackgroundColorAttributeName:[NSColor colorWithWhite:0 alpha:.6]}];[NSGraphicsContext restoreGraphicsState];
    }
}
@end
