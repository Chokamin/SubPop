#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>

static NSUInteger const SubPopFeedbackImageByteLimit=10*1024*1024;
static NSUInteger const SubPopFeedbackImagePixelLimit=16000000;
static NSUInteger const SubPopFeedbackImageDimensionLimit=8192;
static NSUInteger const SubPopFeedbackImageDecodeLimit=4096;

static NSArray<UTType *> *SubPopFeedbackScreenshotTypes(void) {
    NSMutableArray *types=[NSMutableArray arrayWithArray:@[UTTypePNG,UTTypeJPEG]];
    UTType *webp=[UTType typeWithFilenameExtension:@"webp"];
    if (webp) [types addObject:webp];
    return types;
}
static NSDictionary *SubPopFeedbackImageFailure(NSError **error,NSInteger code,NSString *message) {
    if (error) *error=[NSError errorWithDomain:@"SubPop.Feedback.Image" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}
static NSDictionary *SubPopFeedbackScreenshotFromURL(NSURL *url,NSError **error) {
    if (error) *error=nil;
    if (!url.isFileURL) return SubPopFeedbackImageFailure(error,1,@"请选择本机的 PNG、JPEG 或 WebP 截图。");
    NSDictionary *file=[url resourceValuesForKeys:@[NSURLFileSizeKey,NSURLIsRegularFileKey] error:nil];
    if (![file[NSURLIsRegularFileKey] boolValue]) return SubPopFeedbackImageFailure(error,2,@"无法读取截图，请重新选择图片。");
    if ([file[NSURLFileSizeKey] unsignedLongLongValue]>SubPopFeedbackImageByteLimit) return SubPopFeedbackImageFailure(error,3,@"截图文件不能超过 10 MB。");
    NSData *input=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (!input.length || input.length>SubPopFeedbackImageByteLimit) return SubPopFeedbackImageFailure(error,4,@"截图为空、无法读取或超过 10 MB。");
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)input,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCache:@NO});
    if (!source) return SubPopFeedbackImageFailure(error,5,@"无法读取图片，请选择 PNG、JPEG 或 WebP 截图。");
    UTType *type=CGImageSourceGetType(source) ? [UTType typeWithIdentifier:(__bridge NSString *)CGImageSourceGetType(source)] : nil;
    BOOL accepted=NO;for (UTType *allowed in SubPopFeedbackScreenshotTypes()) if ([type conformsToType:allowed]) {accepted=YES;break;}
    if (!accepted || !CGImageSourceGetCount(source)) {
        CFRelease(source);return SubPopFeedbackImageFailure(error,6,@"仅支持 PNG、JPEG 或 WebP 截图；不支持 GIF。");
    }
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    unsigned long long width=[properties[(__bridge id)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    unsigned long long height=[properties[(__bridge id)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    if (!width || !height || width>SubPopFeedbackImageDimensionLimit || height>SubPopFeedbackImageDimensionLimit || height>SubPopFeedbackImagePixelLimit/width) {
        CFRelease(source);return SubPopFeedbackImageFailure(error,7,@"图片尺寸过大，请使用不超过 1600 万像素、边长不超过 8192 的截图。");
    }
    // Decode only the first frame, keeping the complete image and respecting
    // orientation. Bound decoded memory even for a large compressed image.
    CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{
        (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (__bridge id)kCGImageSourceThumbnailMaxPixelSize:@(SubPopFeedbackImageDecodeLimit),
        (__bridge id)kCGImageSourceShouldCacheImmediately:@YES});
    CFRelease(source);
    if (!image) return SubPopFeedbackImageFailure(error,8,@"图片无法解码，请重新选择截图。");
    NSMutableData *png=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png,(__bridge CFStringRef)UTTypePNG.identifier,1,NULL);
    BOOL encoded=NO;
    if (destination) {
        // Add decoded pixels, never the original source's metadata dictionary.
        // This drops EXIF, GPS, filenames and comments from the selected file.
        CGImageDestinationAddImage(destination,image,NULL);encoded=CGImageDestinationFinalize(destination);CFRelease(destination);
    }
    CGImageRelease(image);
    if (!encoded || !png.length) return SubPopFeedbackImageFailure(error,9,@"截图转换失败，请重新选择图片。");
    if (png.length>SubPopFeedbackImageByteLimit) return SubPopFeedbackImageFailure(error,10,@"截图转换后超过 10 MB，请选择较小的截图。");
    CGImageSourceRef previewSource=CGImageSourceCreateWithData((__bridge CFDataRef)png,NULL);
    CGImageRef preview=previewSource ? CGImageSourceCreateThumbnailAtIndex(previewSource,0,(__bridge CFDictionaryRef)@{
        (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge id)kCGImageSourceThumbnailMaxPixelSize:@160,
        (__bridge id)kCGImageSourceShouldCacheImmediately:@YES}) : NULL;
    if (previewSource) CFRelease(previewSource);
    if (!preview) return SubPopFeedbackImageFailure(error,11,@"无法生成截图预览，请重新选择图片。");
    NSImage *thumbnail=[[NSImage alloc] initWithCGImage:preview size:NSZeroSize];CGImageRelease(preview);
    return @{@"data":[png copy],@"image":thumbnail};
}
