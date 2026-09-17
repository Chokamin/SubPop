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

@interface SubPopStylePreview : NSView
@property NSImage *frameImage;
@property NSDictionary *style;
@property NSString *caption;
@property NSString *fontName;
@property CGFloat fontSize;
@property CGFloat projectWidth;
@property NSString *placeholder;
@end
@implementation SubPopStylePreview
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
    CGFloat scale=canvas.size.width/MAX(1920,self.projectWidth),fontSize=MAX(9,self.fontSize*scale);
    NSFont *font=[NSFont fontWithName:self.fontName ?: @"Helvetica" size:fontSize] ?: [NSFont systemFontOfSize:fontSize];
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentCenter;
    NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:NSColor.whiteColor,NSParagraphStyleAttributeName:paragraph};
    NSString *text=self.caption.length ? self.caption : @"让字幕跟上你的表达";
    NSRect measured=[text boundingRectWithSize:NSMakeSize(canvas.size.width*.86,100) options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs];
    CGFloat left=[s[@"left"] doubleValue]*scale,right=[s[@"right"] doubleValue]*scale,top=[s[@"top"] doubleValue]*scale,bottom=[s[@"bottom"] doubleValue]*scale;
    NSRect textRect=NSMakeRect(NSMidX(canvas)-ceil(measured.size.width)/2,NSMinY(canvas)+canvas.size.height*.12,ceil(measured.size.width),ceil(measured.size.height));
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
    [text drawInRect:textRect withAttributes:attrs];
}
@end
