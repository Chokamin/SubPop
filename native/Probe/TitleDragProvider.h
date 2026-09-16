#import <Cocoa/Cocoa.h>

// The pasteboard owns this snapshot; FCP may request data after controller state changes.
@interface SubPopTitleDragProvider : NSObject <NSPasteboardItemDataProvider>
@property (copy) BOOL (^isCurrentProject)(void);
@property (readonly) NSDictionary<NSString *, NSData *> *payloads;
- (instancetype)initWithPayloads:(NSDictionary<NSString *, NSData *> *)payloads;
@end
@implementation SubPopTitleDragProvider
- (instancetype)initWithPayloads:(NSDictionary<NSString *, NSData *> *)payloads {
    if ((self=[super init])) {
        NSMutableDictionary *snapshot=[NSMutableDictionary new];
        for (NSString *version in payloads) snapshot[version]=[payloads[version] copy];
        _payloads=snapshot.copy;
    }
    return self;
}
- (void)pasteboard:(NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSPasteboardType)type {
    if (self.isCurrentProject && !self.isCurrentProject()) return;
    NSString *version=nil;
    if ([type isEqual:@"com.apple.finalcutpro.xml"] || [type isEqual:@"com.apple.finalcutpro.xml.v1-14"]) version=@"1.14";
    else if ([type isEqual:@"com.apple.finalcutpro.xml.v1-13"]) version=@"1.13";
    else if ([type isEqual:@"com.apple.finalcutpro.xml.v1-12"]) version=@"1.12";
    NSData *data=version ? self.payloads[version] : nil;
    if (data) [item setData:data forType:type];
    // No host calls, XML parsing, file I/O, or UI updates in FCP's data-request callback.
}
@end
