#import <Cocoa/Cocoa.h>

// The pasteboard owns this snapshot; FCP may request data after controller state changes.
@interface SubPopTitleDragProvider : NSObject <NSPasteboardItemDataProvider>
@property (copy) BOOL (^isCurrentProject)(void);
@property (readonly) NSDictionary<NSString *, NSData *> *payloads;
- (NSPasteboardItem *)preparedItem;
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
- (NSPasteboardItem *)preparedItem {
    if (self.isCurrentProject && !self.isCurrentProject()) return nil;
    NSPasteboardItem *item=[NSPasteboardItem new];
    for (NSString *type in @[@"com.apple.finalcutpro.xml",@"com.apple.finalcutpro.xml.v1-14",@"com.apple.finalcutpro.xml.v1-13",@"com.apple.finalcutpro.xml.v1-12"]) {
        NSString *version=[type hasSuffix:@"v1-12"] ? @"1.12" : ([type hasSuffix:@"v1-13"] ? @"1.13" : @"1.14");
        NSData *data=self.payloads[version];
        if (!data.length || ![item setData:data forType:type]) return nil;
    }
    return item;
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
