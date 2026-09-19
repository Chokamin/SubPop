// Raster regression checks for Tap5a preview geometry. FCP measurements below
// were exported as 1920x1080 PNGs, not measured from a scaled viewer screenshot.
static NSRect SubPopRedPixelBounds(NSBitmapImageRep *image) {
    NSInteger minX=image.pixelsWide,minY=image.pixelsHigh,maxX=-1,maxY=-1;
    for(NSInteger y=0;y<image.pixelsHigh;y++) for(NSInteger x=0;x<image.pixelsWide;x++) {
        NSColor *pixel=[image colorAtX:x y:y];
        if(pixel.redComponent>.47 && pixel.greenComponent<.31 && pixel.blueComponent<.31) {
            minX=MIN(minX,x);minY=MIN(minY,y);maxX=MAX(maxX,x);maxY=MAX(maxY,y);
        }
    }
    return maxX<0 ? NSZeroRect : NSMakeRect(minX,minY,maxX-minX+1,maxY-minY+1);
}
static BOOL SubPopCheckPreviewGeometry(void) {
    SubPopStylePreview *preview=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,0,640,360)];
    preview.frameImage=[NSImage imageWithSize:preview.bounds.size flipped:NO drawingHandler:^BOOL(NSRect rect){[NSColor.blackColor setFill];NSRectFill(rect);return YES;}];
    preview.projectWidth=1920;preview.caption=@"字幕 gjpq";
    NSMutableDictionary *style=[@{@"backgroundColor":@[@1,@0,@0],@"opacity":@100,@"roundness":@0,@"positionY":@432,@"top":@0,@"bottom":@0,@"left":@0,@"right":@0} mutableCopy];
    preview.style=style;NSRect zero=SubPopRedPixelBounds([NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation]);
    // Change only bottom: text and other edges must stay put, while the lower
    // edge moves down by 20 * 1080 / 600 / 3 = 12 display pixels.
    style[@"bottom"]=@20;preview.style=style;
    NSRect bottom=SubPopRedPixelBounds([NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation]);
    if(fabs(zero.origin.x-bottom.origin.x)>.1 || fabs(zero.origin.y-bottom.origin.y)>.1 || fabs(zero.size.width-bottom.size.width)>.1 || fabs(bottom.size.height-zero.size.height-12)>.1) return NO;
    style[@"top"]=@10;style[@"left"]=@30;preview.style=style;
    NSRect mixed=SubPopRedPixelBounds([NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation]);
    if(fabs(mixed.origin.x-bottom.origin.x+32)>.1 || fabs(mixed.origin.y-bottom.origin.y+6)>.1 || fabs(NSMaxX(mixed)-NSMaxX(bottom))>.1 || fabs(NSMaxY(mixed)-NSMaxY(bottom))>.1) return NO;
    // The guide must be red even over a bright video frame.
    preview.frameImage=[NSImage imageWithSize:preview.bounds.size flipped:NO drawingHandler:^BOOL(NSRect rect){[NSColor.whiteColor setFill];NSRectFill(rect);return YES;}];
    preview.showsSafeArea=YES;NSBitmapImageRep *guide=[NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation];BOOL redGuide=NO;
    for(NSInteger y=80;y<100;y++) for(NSInteger x=31;x<=32;x++) {NSColor *c=[guide colorAtX:x y:y];if(c.redComponent>c.greenComponent+.15 && c.redComponent>c.blueComponent+.15)redGuide=YES;}
    if(!redGuide)return NO;
    // Explicit and width-constrained multiline text must remain centered and
    // extend the background downward instead of clipping to one line.
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:24]};NSRect one,two,wrapped;
    SubPopPreviewTextLines(@"Preview",attributes,NSMakePoint(200,100),0,1,300,&one);
    NSArray *lines=SubPopPreviewTextLines(@"Preview\ngjpq",attributes,NSMakePoint(200,100),8,1,300,&two);
    NSArray *wrap=SubPopPreviewTextLines(@"A longer subtitle that needs wrapping",attributes,NSMakePoint(200,100),0,1,100,&wrapped);
    if(lines.count!=2 || wrap.count<2 || NSMinY(two)>=NSMinY(one) || fabs(NSMaxY(two)-NSMaxY(one))>.01 || wrapped.size.width>101)return NO;
    // Optional local font fixture: exact FCP rectangle bounds for the user's
    // Smiley Sans Oblique 57 pt / tracking 4.1 caption at margins 0, 10 and 20.
    if([NSFont fontWithName:@"SmileySans-Oblique" size:57]) {
        [preview setFrameSize:NSMakeSize(1920,1080)];preview.frameImage=[NSImage imageWithSize:preview.bounds.size flipped:NO drawingHandler:^BOOL(NSRect rect){[NSColor.whiteColor setFill];NSRectFill(rect);return YES;}];preview.showsSafeArea=NO;preview.caption=@"胶片相机拍出来的感觉吗";
        [style addEntriesFromDictionary:@{@"textFont":@"Smiley Sans",@"textFace":@"Oblique",@"textSize":@57,@"kerning":@4.1}];
        for(NSNumber *margin in @[@0,@10,@20]) {
            for(NSString *key in @[@"top",@"bottom",@"left",@"right"])style[key]=margin;
            preview.style=style;NSRect actual=SubPopRedPixelBounds([NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation]);
            CGFloat n=margin.doubleValue;NSRect expected=NSMakeRect(687-3.2*n,483-1.8*n,546+6.4*n,72+3.6*n);
            if(!NSEqualRects(actual,expected)){NSLog(@"FCP preview fixture mismatch %@ / %@",NSStringFromRect(actual),NSStringFromRect(expected));return NO;}
        }
    }
    puts("Preview geometry: asymmetric margins, red guides, multiline and available FCP font fixture passed.");return YES;
}
