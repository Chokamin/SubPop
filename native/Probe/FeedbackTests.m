// Real serializers and offscreen AppKit actions, using only synthetic images,
// metadata, a unique pasteboard and a stub browser. No FCP or network access.
#import "FeedbackPanel.h"
#import <ImageIO/ImageIO.h>

static BOOL check(BOOL value,NSString *message) {
    if (!value) fprintf(stderr,"Feedback check failed: %s\n",message.UTF8String);
    return value;
}
static NSDictionary *fixtureEnvironment(void) {
    return @{@"version":@"1.4.12",@"build":@"141",@"macOS":@"15.7.0",@"architecture":@"Apple Silicon",
             @"projectName":@"PRIVATE-PROJECT",@"path":@"/Users/private-fixture/audio.wav",@"apiKey":@"FIXTURE-SECRET",
             @"error":@"FULL-PRIVATE-ERROR",@"log":@"PRIVATE-LOG",@"text":@"PRIVATE-CAPTION"};
}
static NSDictionary *queryValues(NSURL *url) {
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if (values[item.name]) return nil;
        values[item.name]=item.value ?: @"";
    }
    return values;
}
static BOOL checkData(void) {
    NSDictionary *environment=fixtureEnvironment();
    NSString *description=@"字幕 + # & title=注入？\nhttps://example.invalid/?body=改写 😊";
    NSString *body=SubPopFeedbackBody(description,environment);
    if (!check([body containsString:description] && [body containsString:@"Build 141"] && [body containsString:@"15.7.0"] && ![body containsString:@"复现步骤"] && ![body containsString:@"期望结果"] && ![body containsString:@"Final Cut Pro"],@"copy contains one problem and the public environment")) return NO;
    NSURL *url=SubPopFeedbackIssueURL(description,environment);
    NSDictionary *query=queryValues(url);
    if (!check([url.scheme isEqual:@"https"] && [url.host isEqual:@"github.com"] && [url.path isEqual:@"/Chokamin/SubPop/issues/new"] && !url.fragment && !url.user && !url.password && !url.port,@"fixed issue destination")) return NO;
    if (!check(query.count==4 && [query[@"template"] isEqual:@"bug_report.yml"] && [query[@"problem"] isEqual:description] && [query[@"environment"] containsString:@"1.4.12（Build 141）"] && [query[@"environment"] containsString:@"15.7.0"] && !query[@"body"] && !query[@"labels"] && !query[@"screenshots"],@"only current official form IDs are encoded; no screenshot URL or bytes")) return NO;
    if (!check([url.absoluteString containsString:@"%2B"] && [url.absoluteString containsString:@"%23"] && [url.absoluteString containsString:@"%26"] && ![url.absoluteString containsString:@"😊"] && [query[@"title"] isEqual:@"[问题] 字幕 + # & title=注入？"],@"reserved characters and UTF-8 safely round trip")) return NO;
    for (NSString *secret in @[@"PRIVATE-PROJECT",@"/Users/private-fixture",@"FIXTURE-SECRET",@"FULL-PRIVATE-ERROR",@"PRIVATE-LOG",@"PRIVATE-CAPTION"]) {
        if (!check(![body containsString:secret] && ![url.absoluteString containsString:secret],@"unlisted environment values never serialize")) return NO;
    }
    NSDictionary *missing=queryValues(SubPopFeedbackIssueURL(@"问题",@{}));
    if (!check(missing.count==4 && [missing[@"environment"] containsString:@"未知（Build 未知）"],@"missing environment remains usable without more required inputs")) return NO;
    NSDictionary *unsafe=@{@"version":@"/Users/private-fixture",@"build":@"FIXTURE-SECRET",@"macOS":@"FULL-PRIVATE-ERROR",@"architecture":@"PRIVATE-PROJECT"};
    NSString *safeBody=SubPopFeedbackBody(@"问题",unsafe);
    for (NSString *key in unsafe) if (!check(![safeBody containsString:unsafe[key]],@"selected metadata is still format validated")) return NO;
    if (!check(!SubPopFeedbackBody(@" \n\t",environment) && !SubPopFeedbackIssueURL(@"",environment) && SubPopFeedbackValidationMessage(@""),@"empty problem cannot copy or open")) return NO;
    NSString *tooLong=[@"x" stringByPaddingToLength:1201 withString:@"x" startingAtIndex:0];
    if (!check(!SubPopFeedbackBody(tooLong,environment),@"problem length limit")) return NO;
    unichar control=1;NSString *invalid=[@"问题" stringByAppendingString:[NSString stringWithCharacters:&control length:1]];
    if (!check(!SubPopFeedbackBody(invalid,environment) && !SubPopFeedbackIssueURL(invalid,environment),@"control characters rejected")) return NO;
    NSString *unicodeLong=[@"字" stringByPaddingToLength:1200 withString:@"字" startingAtIndex:0];
    if (!check(SubPopFeedbackBody(unicodeLong,environment)!=nil && SubPopFeedbackIssueURL(unicodeLong,environment)==nil,@"long encoded URL keeps copy available")) return NO;
    NSDictionary *shortQuery=queryValues(SubPopFeedbackShortIssueURL(unicodeLong,environment));
    if (!check(shortQuery.count==3 && [shortQuery[@"template"] isEqual:@"bug_report.yml"] && !shortQuery[@"problem"] && shortQuery[@"environment"],@"long feedback has only template, title and public environment in its short URL")) return NO;
    NSString *emojiTitle=[[@"x" stringByPaddingToLength:69 withString:@"x" startingAtIndex:0] stringByAppendingString:@"😊尾"];
    NSString *title=queryValues(SubPopFeedbackIssueURL(emojiTitle,environment))[@"title"];
    if (!check([title hasSuffix:@"😊"] && ![title hasSuffix:@"尾"],@"title truncation respects composed Unicode characters")) return NO;
    NSString *combined=[@"a" stringByAppendingString:[@"\u0301" stringByPaddingToLength:1000 withString:@"\u0301" startingAtIndex:0]];
    if (!check(SubPopFeedbackShortIssueURL(combined,environment)!=nil && [queryValues(SubPopFeedbackShortIssueURL(combined,environment))[@"title"] isEqual:@"[问题] SubPop 使用问题"],@"oversized composed Unicode title keeps the short fallback usable")) return NO;
    unichar surrogate=0xD800;NSString *invalidUnicode=[NSString stringWithCharacters:&surrogate length:1];
    if (!check(!SubPopFeedbackBody(invalidUnicode,environment) && !SubPopFeedbackIssueURL(invalidUnicode,environment),@"malformed Unicode cannot produce a broken URL")) return NO;
    NSDictionary *actual=SubPopFeedbackEnvironment(NSBundle.mainBundle);
    return check(actual.count==4 && actual[@"version"] && actual[@"build"] && actual[@"macOS"] && actual[@"architecture"],@"automatic environment contains only four public values");
}

static NSData *fixtureImage(NSString *type,size_t width,size_t height,BOOL metadata) {
    NSMutableData *pixels=[NSMutableData dataWithLength:width*height*4];unsigned char *rgba=pixels.mutableBytes;
    const unsigned char colors[4][4]={{255,0,0,255},{0,255,0,255},{0,0,255,255},{255,255,255,255}};
    for (size_t y=0;y<height;y++) for (size_t x=0;x<width;x++) memcpy(rgba+(y*width+x)*4,colors[(x+y*width)%4],4);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGImageRef image=CGImageCreate(width,height,8,32,width*4,space,kCGImageAlphaLast|kCGBitmapByteOrder32Big,provider,NULL,NO,kCGRenderingIntentDefault);
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,(__bridge CFStringRef)type,1,NULL);
    NSDictionary *properties=metadata ? @{
        (__bridge NSString *)kCGImagePropertyExifDictionary:@{(__bridge NSString *)kCGImagePropertyExifUserComment:@"PRIVATE-EXIF"},
        (__bridge NSString *)kCGImagePropertyTIFFDictionary:@{(__bridge NSString *)kCGImagePropertyTIFFImageDescription:@"/Users/private-fixture/PRIVATE-SCREENSHOT.jpg"},
        (__bridge NSString *)kCGImagePropertyGPSDictionary:@{(__bridge NSString *)kCGImagePropertyGPSLatitude:@25.0,(__bridge NSString *)kCGImagePropertyGPSLatitudeRef:@"N"},
        (__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@1.0} : @{};
    if (destination && image) CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)properties);
    BOOL success=destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);if (image) CGImageRelease(image);
    CGDataProviderRelease(provider);CGColorSpaceRelease(space);
    return success ? data : nil;
}
static NSDictionary *imageProperties(NSData *data) {
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    NSDictionary *properties=source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)) : nil;
    if (source) CFRelease(source);return properties;
}
static NSData *imagePixels(NSData *data) {
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    CGImageRef image=source ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
    if (source) CFRelease(source);if (!image) return nil;
    size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image);
    NSMutableData *pixels=[NSMutableData dataWithLength:width*height*4];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels.mutableBytes,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if (context) {CGContextDrawImage(context,CGRectMake(0,0,width,height),image);CGContextRelease(context);}
    CGColorSpaceRelease(space);CGImageRelease(image);return context ? pixels : nil;
}
static NSURL *temporaryDirectory(void) {
    NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"subpop-feedback-test-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    return [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil] ? directory : nil;
}
static NSURL *writeFixture(NSURL *directory,NSString *name,NSData *data) {
    NSURL *url=[directory URLByAppendingPathComponent:name];return data && [data writeToURL:url atomically:YES] ? url : nil;
}
static uint32_t pngCRC(const unsigned char *bytes,NSUInteger length) {
    uint32_t crc=0xffffffff;for (NSUInteger i=0;i<length;i++) {crc^=bytes[i];for (NSUInteger j=0;j<8;j++) crc=(crc>>1)^((crc&1) ? 0xedb88320 : 0);}
    return crc^0xffffffff;
}
static NSData *oversizedPixelHeader(NSData *png) {
    NSMutableData *data=png.mutableCopy;unsigned char *bytes=data.mutableBytes;
    if (data.length<33 || memcmp(bytes+12,"IHDR",4)) return nil;
    // Valid dimensions and IHDR CRC expose the pixel guard before ImageIO
    // allocates/decompresses this intentionally inconsistent tiny payload.
    const uint32_t sizes[2]={4001,4000};
    for (NSUInteger index=0;index<2;index++) for (NSUInteger byte=0;byte<4;byte++) bytes[16+index*4+byte]=(sizes[index]>>(24-byte*8))&255;
    uint32_t crc=pngCRC(bytes+12,17);for (NSUInteger byte=0;byte<4;byte++) bytes[29+byte]=(crc>>(24-byte*8))&255;
    return data;
}

@interface SubPopFeedbackFakeOpenPanel : NSOpenPanel
@property (copy) void (^testCompletion)(NSModalResponse);
@property NSURL *selectedURL;
@property NSUInteger beginCount;
@property NSUInteger cancelCount;
@end
@implementation SubPopFeedbackFakeOpenPanel
- (NSURL *)URL {return self.selectedURL;}
- (NSArray<NSURL *> *)URLs {return self.selectedURL ? @[self.selectedURL] : @[];}
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completionHandler {self.beginCount++;self.testCompletion=completionHandler;}
- (void)cancel:(id)sender {self.cancelCount++;}
- (void)finish:(NSModalResponse)response {if (self.testCompletion) self.testCompletion(response);}
@end
@interface SubPopFeedbackTestPanel : SubPopFeedbackPanel
@property NSURL *openedURL;
@property NSUInteger openCount;
@property NSPasteboard *testPasteboard;
@property BOOL allowOpen;
@property NSData *pngAtOpen;
@property NSString *textAtOpen;
@property SubPopFeedbackFakeOpenPanel *fakePicker;
@end
@implementation SubPopFeedbackTestPanel
- (BOOL)openFeedbackURL:(NSURL *)url {
    self.openedURL=url;self.openCount++;
    self.pngAtOpen=[self.testPasteboard dataForType:NSPasteboardTypePNG];self.textAtOpen=[self.testPasteboard stringForType:NSPasteboardTypeString];
    return self.allowOpen;
}
- (NSPasteboard *)feedbackPasteboard {return self.testPasteboard;}
- (NSOpenPanel *)newScreenshotOpenPanel {return self.fakePicker;}
@end
@interface SubPopFeedbackKeyTestEditor : SubPopFeedbackEditor
@property NSMutableArray *editingActions;
@end
@implementation SubPopFeedbackKeyTestEditor
- (void)paste:(id)sender {[self.editingActions addObject:@"paste"];}
- (void)copy:(id)sender {[self.editingActions addObject:@"copy"];}
- (void)cut:(id)sender {[self.editingActions addObject:@"cut"];}
- (void)selectAll:(id)sender {[self.editingActions addObject:@"selectAll"];}
@end
static NSEvent *keyEvent(NSWindow *window,NSString *character,NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil characters:character charactersIgnoringModifiers:character isARepeat:NO keyCode:0];
}
static BOOL waitForPanelClose(SubPopFeedbackPanel *panel) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while (panel.alert && deadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return panel.alert==nil;
}
static BOOL checkScreenshots(void) {
    [NSApplication sharedApplication];
    NSURL *directory=temporaryDirectory();if (!check(directory!=nil,@"synthetic image directory")) return NO;
    SubPopFeedbackTestPanel *panel=[SubPopFeedbackTestPanel new];panel.testPasteboard=[NSPasteboard pasteboardWithUniqueName];
    [panel prepareForBundle:NSBundle.mainBundle];panel.environment=fixtureEnvironment();panel.descriptionEditor.string=@"合成截图反馈";
    NSData *png=fixtureImage(@"public.png",2,2,NO);
    NSData *jpeg=fixtureImage(@"public.jpeg",2,2,YES);
    NSData *webp=[[NSData alloc] initWithBase64EncodedString:@"UklGRiwAAABXRUJQVlA4TB8AAAAvAUAAAB8gEEjeHzqN+RcQFPwf3fxHZA/gBgwR/Q8BAA==" options:0];
    NSDictionary *jpegProperties=imageProperties(jpeg);
    if (!check(png && jpeg && [[jpegProperties description] containsString:@"PRIVATE-EXIF"] && [[jpegProperties description] containsString:@"PRIVATE-SCREENSHOT"] && jpegProperties[(__bridge NSString *)kCGImagePropertyGPSDictionary],@"JPEG fixture really contains private EXIF, GPS and filename metadata")) return NO;
    for (NSString *format in @[@"png",@"jpg",@"webp"]) {
        NSData *source=[format isEqual:@"png"] ? png : [format isEqual:@"jpg"] ? jpeg : webp;
        NSURL *url=writeFixture(directory,[@"PRIVATE-SCREENSHOT." stringByAppendingString:format],source);
        if (!check([panel loadScreenshotURL:url] && panel.screenshotData.length && panel.screenshotImage,@"PNG/JPEG/WebP decode to an in-memory preview")) return NO;
        CGImageSourceRef decoded=CGImageSourceCreateWithData((__bridge CFDataRef)panel.screenshotData,NULL);
        BOOL actualPNG=decoded && [(__bridge NSString *)CGImageSourceGetType(decoded) isEqual:@"public.png"];
        if (decoded) CFRelease(decoded);
        if (!check(actualPNG && [imagePixels(panel.screenshotData) isEqual:imagePixels(source)],@"sanitized screenshot is real PNG with the source pixels")) return NO;
        NSDictionary *properties=imageProperties(panel.screenshotData);
        // ImageIO generates fresh color-space/dimension EXIF keys for PNG;
        // source comments, camera metadata, filenames and GPS must be absent.
        NSDictionary *exif=properties[(__bridge NSString *)kCGImagePropertyExifDictionary];
        NSSet *generatedExif=[NSSet setWithArray:@[(__bridge NSString *)kCGImagePropertyExifColorSpace,(__bridge NSString *)kCGImagePropertyExifPixelXDimension,(__bridge NSString *)kCGImagePropertyExifPixelYDimension]];
        if (!check([[NSSet setWithArray:exif.allKeys ?: @[]] isSubsetOfSet:generatedExif] && !properties[(__bridge NSString *)kCGImagePropertyGPSDictionary] && ![[properties description] containsString:@"PRIVATE-SCREENSHOT"] && ![[properties description] containsString:@"/Users/"],@"PNG strips source EXIF, GPS and filename metadata")) {
            fprintf(stderr,"Synthetic %s PNG properties: %s\n",format.UTF8String,properties.description.UTF8String);return NO;
        }
        for (NSString *secret in @[@"PRIVATE-EXIF",@"PRIVATE-SCREENSHOT",@"/Users/private-fixture"]) {
            if (!check([panel.screenshotData rangeOfData:[secret dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0,panel.screenshotData.length)].location==NSNotFound,@"re-encoded PNG bytes strip source metadata")) return NO;
        }
        if (!check([[NSData dataWithContentsOfURL:url] isEqual:source] && ![[panel feedbackBody] containsString:url.path] && ![SubPopFeedbackIssueURL(panel.descriptionEditor.string,panel.environment).absoluteString containsString:@"PRIVATE-SCREENSHOT"],@"source image is untouched and its path never enters feedback")) return NO;
        [panel copyScreenshot:nil];
        if (!check([[panel.testPasteboard dataForType:NSPasteboardTypePNG] isEqual:panel.screenshotData] && ![panel.testPasteboard stringForType:NSPasteboardTypeString] && ![panel.testPasteboard.types containsObject:NSPasteboardTypeFileURL] && panel.openCount==0,@"copy writes only screenshot PNG to the isolated pasteboard")) {
            fprintf(stderr,"Isolated pasteboard types: %s, PNG length: %lu, expected: %lu, status: %s\n",panel.testPasteboard.types.description.UTF8String,(unsigned long)[panel.testPasteboard dataForType:NSPasteboardTypePNG].length,(unsigned long)panel.screenshotData.length,panel.status.stringValue.UTF8String);return NO;
        }
    }
    NSData *scaled=fixtureImage(@"public.png",4097,2,NO);
    if (!check([panel loadScreenshotURL:writeFixture(directory,@"large-valid.png",scaled)],@"large but valid image loads")) return NO;
    NSDictionary *scaledProperties=imageProperties(panel.screenshotData);
    if (!check([scaledProperties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue]<=4096 && [scaledProperties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue]<=4096,@"large screenshot is decoded to a bounded PNG preview")) return NO;
    NSMutableData *atLimit=png.mutableCopy;atLimit.length=10*1024*1024;
    if (!check([panel loadScreenshotURL:writeFixture(directory,@"at-limit.png",atLimit)],@"valid image at the 10 MiB file limit is accepted")) return NO;
    NSMutableData *overLimit=atLimit.mutableCopy;overLimit.length=10*1024*1024+1;
    NSData *saved=panel.screenshotData;
    NSArray<NSURL *> *invalid=@[
        writeFixture(directory,@"invalid.png",[@"not an image" dataUsingEncoding:NSUTF8StringEncoding]),
        writeFixture(directory,@"disguised.png",fixtureImage(@"com.compuserve.gif",2,2,NO)),
        writeFixture(directory,@"too-many-pixels.png",oversizedPixelHeader(png)),
        writeFixture(directory,@"too-wide.png",fixtureImage(@"public.png",8193,1,NO)),
        writeFixture(directory,@"too-large.png",overLimit),
        [directory URLByAppendingPathComponent:@"missing.png"],directory,
        [NSURL URLWithString:@"https://example.invalid/screenshot.png"]];
    for (NSURL *url in invalid) {
        if (!check(![panel loadScreenshotURL:url] && [panel.screenshotData isEqual:saved] && panel.openCount==0,@"invalid, non-file, oversized or unsupported image leaves the previous screenshot intact")) return NO;
    }
    NSError *pixelError=nil;
    if (!check(!SubPopFeedbackScreenshotFromURL([directory URLByAppendingPathComponent:@"too-many-pixels.png"],&pixelError) && [pixelError.domain isEqual:@"SubPop.Feedback.Image"] && pixelError.code==7,@"pixel limit rejects header dimensions before decoding")) return NO;
    NSError *sizeError=nil;
    if (!check(!SubPopFeedbackScreenshotFromURL([directory URLByAppendingPathComponent:@"too-large.png"],&sizeError) && sizeError.code==3,@"otherwise valid image above 10 MiB is refused by the file-size guard")) return NO;
    NSError *dimensionError=nil;
    if (!check(!SubPopFeedbackScreenshotFromURL([directory URLByAppendingPathComponent:@"too-wide.png"],&dimensionError) && dimensionError.code==7,@"otherwise valid PNG above 8192 pixels on one edge is refused by the dimensions guard")) return NO;
    [panel removeScreenshot:nil];
    if (!check(!panel.screenshotData && !panel.screenshotImage && !panel.screenshotPreview.image && [panel.descriptionEditor.string isEqual:@"合成截图反馈"],@"remove clears screenshot and preserves the problem")) return NO;
    [panel close];[panel.testPasteboard releaseGlobally];[NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    return YES;
}
static BOOL checkPanel(void) {
    [NSApplication sharedApplication];
    NSURL *directory=temporaryDirectory();NSURL *imageURL=writeFixture(directory,@"PRIVATE-SCREENSHOT.png",fixtureImage(@"public.png",2,2,NO));
    SubPopFeedbackTestPanel *panel=[SubPopFeedbackTestPanel new];panel.allowOpen=YES;panel.testPasteboard=[NSPasteboard pasteboardWithUniqueName];
    [panel prepareForBundle:NSBundle.mainBundle];panel.environment=fixtureEnvironment();
    if (!check(!panel.issueButton.enabled && !panel.clipboardButton.enabled && panel.alert.accessoryView && !panel.alert.window.sheetParent && ![panel respondsToSelector:NSSelectorFromString(@"stepsEditor")] && ![panel respondsToSelector:NSSelectorFromString(@"expectedEditor")] && ![panel respondsToSelector:NSSelectorFromString(@"fcpVersionField")],@"offscreen form starts disabled and has only the requested problem field")) return NO;
    panel.descriptionEditor.string=@"测试反馈";
    [panel textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:panel.descriptionEditor]];
    if (!check(panel.issueButton.enabled && panel.clipboardButton.enabled,@"one problem enables both actions")) return NO;
    [panel copyFeedback:nil];
    if (!check([[panel.testPasteboard stringForType:NSPasteboardTypeString] isEqual:[panel feedbackBody]] && panel.openCount==0 && panel.alert,@"copy uses only the isolated pasteboard and keeps the form open")) return NO;
    [panel openIssue:nil];
    if (!check(panel.openCount==1 && queryValues(panel.openedURL).count==4 && [queryValues(panel.openedURL)[@"problem"] isEqual:@"测试反馈"] && panel.alert,@"explicit action opens the prefilled form without creating an issue")) return NO;
    panel.allowOpen=NO;[panel openIssue:nil];
    if (!check([panel.status.stringValue containsString:@"复制"],@"browser failure offers copy")) return NO;
    panel.allowOpen=YES;
    if (!check([panel loadScreenshotURL:imageURL],@"attach synthetic screenshot")) return NO;
    NSData *savedImage=panel.screenshotData;NSUInteger attempts=panel.openCount;[panel openIssue:nil];
    if (!check(panel.openCount==attempts+1 && [panel.pngAtOpen isEqual:savedImage] && !panel.textAtOpen && queryValues(panel.openedURL).count==4 && [panel.status.stringValue containsString:@"截图"],@"short problem copies PNG before navigation and preserves description prefill")) return NO;
    NSPasteboard *savedPasteboard=panel.testPasteboard;panel.testPasteboard=nil;attempts=panel.openCount;[panel openIssue:nil];
    if (!check(panel.openCount==attempts && [panel.status.stringValue containsString:@"未打开网页"],@"screenshot copy failure blocks navigation")) return NO;
    panel.testPasteboard=savedPasteboard;
    panel.descriptionEditor.string=[@"字" stringByPaddingToLength:1200 withString:@"字" startingAtIndex:0];[panel updateValidation];
    if (!check(panel.issueButton.enabled && panel.clipboardButton.enabled && [panel.issueButton.title containsString:@"复制说明"],@"long URL offers copy description and continue")) return NO;
    [panel openIssue:nil];
    if (!check(panel.openCount==attempts+1 && queryValues(panel.openedURL).count==3 && [[panel.testPasteboard stringForType:NSPasteboardTypeString] isEqual:[panel feedbackBody]] && [panel.textAtOpen isEqual:[panel feedbackBody]] && !panel.pngAtOpen && [panel.screenshotData isEqual:savedImage] && [panel.status.stringValue containsString:@"截图"],@"long problem copies body before short URL and keeps screenshot available separately")) return NO;
    [panel copyScreenshot:nil];
    if (!check([[panel.testPasteboard dataForType:NSPasteboardTypePNG] isEqual:savedImage] && ![panel.testPasteboard stringForType:NSPasteboardTypeString] && panel.descriptionEditor.string.length==1200,@"copy screenshot preserves the long problem for subsequent copy")) return NO;
    [panel copyFeedback:nil];
    if (!check([[panel.testPasteboard stringForType:NSPasteboardTypeString] isEqual:[panel feedbackBody]] && ![panel.testPasteboard dataForType:NSPasteboardTypePNG] && [panel.screenshotData isEqual:savedImage],@"copy description never replaces the attached screenshot")) return NO;
    attempts=panel.openCount;panel.testPasteboard=nil;[panel openIssue:nil];
    if (!check(panel.openCount==attempts && [panel.status.stringValue containsString:@"未打开网页"],@"long problem copy failure blocks navigation")) return NO;
    panel.testPasteboard=savedPasteboard;panel.descriptionEditor.string=@"";[panel updateValidation];[panel copyFeedback:nil];[panel openIssue:nil];
    if (!check(!panel.clipboardButton.enabled && !panel.issueButton.enabled && panel.openCount==attempts,@"screenshot alone does not bypass required problem validation")) return NO;
    [panel close];
    if (!check(!panel.screenshotData && !panel.screenshotImage && !panel.screenshotPreview.image,@"offscreen controller close clears the in-memory screenshot")) return NO;
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,450,100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;
    SubPopFeedbackKeyTestEditor *editor=[[SubPopFeedbackKeyTestEditor alloc] initWithFrame:NSMakeRect(0,0,450,100)];editor.editingActions=[NSMutableArray array];window.contentView=editor;[window makeFirstResponder:editor];
    for (NSString *character in @[@"v",@"c",@"x",@"a"]) if (!check([window performKeyEquivalent:keyEvent(window,character,NSEventModifierFlagCommand)],@"Command editing shortcut routes through window to feedback editor")) return NO;
    if (!check([editor.editingActions isEqual:@[@"paste",@"copy",@"cut",@"selectAll"]],@"all editing shortcuts dispatch exactly once")) return NO;
    [editor performKeyEquivalent:keyEvent(window,@"v",NSEventModifierFlagCommand|NSEventModifierFlagControl)];
    if (!check(editor.editingActions.count==4,@"unrelated modifier combination does not paste")) return NO;
    SubPopFeedbackTestPanel *sheetPanel=[SubPopFeedbackTestPanel new];sheetPanel.testPasteboard=savedPasteboard;__block NSUInteger closed=0;
    sheetPanel.onClose=^{closed++;};[sheetPanel showForWindow:window bundle:NSBundle.mainBundle];NSAlert *firstAlert=sheetPanel.alert;
    if (!check(firstAlert && firstAlert.window.sheetParent==window && window.attachedSheet==firstAlert.window,@"real sheet attaches to independent test parent")) return NO;
    [sheetPanel showForWindow:window bundle:NSBundle.mainBundle];
    if (!check(sheetPanel.alert==firstAlert && window.attachedSheet==firstAlert.window,@"repeat click does not create another sheet")) return NO;
    sheetPanel.descriptionEditor.string=@"截图生命周期";[sheetPanel loadScreenshotURL:imageURL];
    [firstAlert.buttons.firstObject performClick:nil];
    if (!check(waitForPanelClose(sheetPanel) && closed==1 && !window.attachedSheet && !sheetPanel.descriptionEditor && !sheetPanel.screenshotData && !sheetPanel.screenshotImage,@"close button ends sheet, clears text and screenshot once")) return NO;
    sheetPanel.onClose=^{closed++;};[sheetPanel showForWindow:window bundle:NSBundle.mainBundle];
    if (!check(sheetPanel.alert && sheetPanel.alert!=firstAlert && window.attachedSheet==sheetPanel.alert.window,@"feedback reopens after close")) return NO;
    SubPopFeedbackFakeOpenPanel *picker=[SubPopFeedbackFakeOpenPanel new];picker.selectedURL=imageURL;sheetPanel.fakePicker=picker;
    [sheetPanel chooseScreenshot:nil];[sheetPanel chooseScreenshot:nil];
    if (!check(sheetPanel.openPanel==picker && picker.beginCount==1 && !picker.allowsMultipleSelection && !picker.canChooseDirectories,@"one image picker is pending; repeat selection does not add sheets")) return NO;
    [sheetPanel close];
    if (!check(waitForPanelClose(sheetPanel) && closed==2 && !window.attachedSheet && !sheetPanel.openPanel && picker.cancelCount==1,@"controller close cancels pending picker and releases the sheet lifecycle")) return NO;
    sheetPanel.onClose=^{closed++;};[sheetPanel showForWindow:window bundle:NSBundle.mainBundle];
    [picker finish:NSModalResponseOK];
    if (!check(!sheetPanel.screenshotData && !sheetPanel.openPanel,@"old picker completion cannot attach an image to a reopened feedback form")) return NO;
    SubPopFeedbackFakeOpenPanel *secondPicker=[SubPopFeedbackFakeOpenPanel new];secondPicker.selectedURL=imageURL;sheetPanel.fakePicker=secondPicker;
    [sheetPanel chooseScreenshot:nil];[secondPicker finish:NSModalResponseOK];
    if (!check(sheetPanel.screenshotData && !sheetPanel.openPanel,@"current picker completion attaches the selected synthetic image")) return NO;
    [sheetPanel close];
    if (!check(waitForPanelClose(sheetPanel) && closed==3 && !sheetPanel.screenshotData && !sheetPanel.screenshotImage,@"reopened sheet clears its screenshot on close")) return NO;
    [window close];[savedPasteboard releaseGlobally];[NSFileManager.defaultManager removeItemAtURL:directory error:nil];return YES;
}

@interface SubPopFeedbackDemoDelegate : NSObject <NSWindowDelegate,NSApplicationDelegate>
@property SubPopFeedbackTestPanel *panel;
@end
@implementation SubPopFeedbackDemoDelegate
- (void)windowWillClose:(NSNotification *)notification {[self.panel close];[NSApp terminate:nil];}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {return YES;}
@end
static void fillDemo(SubPopFeedbackTestPanel *panel) {
    panel.environment=fixtureEnvironment();panel.descriptionEditor.string=@"拖入项目后点击「生成字幕」，提示片段设置无法处理。\n希望能继续识别，并保留原来的字幕时间。";
    panel.environmentLabel.stringValue=@"SubPop 1.4.12 · Build 141 · macOS 15.7.0 · Apple Silicon";
    NSURL *directory=temporaryDirectory();NSURL *url=writeFixture(directory,@"synthetic.png",fixtureImage(@"public.png",320,180,NO));
    [panel loadScreenshotURL:url];[NSFileManager.defaultManager removeItemAtURL:directory error:nil];[panel updateValidation];
}
static void showDemo(void) {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    SubPopFeedbackDemoDelegate *delegate=[SubPopFeedbackDemoDelegate new];NSApp.delegate=delegate;
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,580,450) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;window.title=@"SubPop · 独立反馈面板验证";window.delegate=delegate;window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSTextField *hint=[NSTextField wrappingLabelWithString:@"独立界面验证：不连接 FCP、不打开外部网页、不提交反馈。\n关闭此测试窗口即可结束验证。"];
    hint.frame=NSMakeRect(24,330,530,70);hint.font=[NSFont systemFontOfSize:14];[window.contentView addSubview:hint];
    SubPopFeedbackTestPanel *panel=[SubPopFeedbackTestPanel new];delegate.panel=panel;panel.allowOpen=YES;panel.testPasteboard=[NSPasteboard pasteboardWithUniqueName];
    [window center];[window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[panel showForWindow:window bundle:NSBundle.mainBundle];fillDemo(panel);
    panel.alert.informativeText=@"独立测试：不会打开网页或提交反馈。\n测试按钮只记录网址；复制仅写独立测试剪贴板。";
    [NSApp run];[panel.testPasteboard releaseGlobally];(void)delegate;
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc==2 && strcmp(argv[1],"--demo")==0) {showDemo();}
        else if (argc==2 && strcmp(argv[1],"--schema")==0) {
            NSDictionary *schema=@{@"fullKeys":[queryValues(SubPopFeedbackIssueURL(@"问题",fixtureEnvironment())).allKeys sortedArrayUsingSelector:@selector(compare:)],
                                   @"shortKeys":[queryValues(SubPopFeedbackShortIssueURL(@"问题",fixtureEnvironment())).allKeys sortedArrayUsingSelector:@selector(compare:)]};
            NSData *json=[NSJSONSerialization dataWithJSONObject:schema options:0 error:nil];puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        } else if (argc==2 && strcmp(argv[1],"--screenshots")==0) {
            if (!checkScreenshots()) return 3;
            puts("Feedback synthetic screenshots, real PNG pixels, metadata stripping and input limits: passed");
        } else if (argc==2 && strcmp(argv[1],"--panel")==0) {
            if (!checkPanel()) return 2;
            puts("Feedback offscreen actions, clipboard order, picker lifecycle and editing shortcuts: passed");
        } else {
            if (!checkData()) return 1;
            puts("Feedback simplified form URL, Unicode encoding, metadata privacy and validation: passed");
        }
    }
    return 0;
}
