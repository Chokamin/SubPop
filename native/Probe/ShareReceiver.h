#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
// A receive-only implementation of Apple's custom-share MediaAssetProtocol.
// No request starts recognition, opens a project, or uploads media.
@interface SubPopShareReceiver : NSObject
- (instancetype)initWithBridgeURL:(NSURL *)bridgeURL;
// Register before applicationDidFinishLaunching so the first create event is handled.
- (void)registerAppleEventHandlers;
// Returns YES if any file URL belongs to an export created by this receiver.
// Calls completion on the main queue after immutable inbox publication or failure.
- (BOOL)handleOpenURLs:(NSArray<NSURL *> *)URLs completion:(void (^)(NSDictionary * _Nullable manifest, NSError * _Nullable error))completion;
// Pending/receiving shares become terminal; late completion cannot revive them.
- (BOOL)cancelShareID:(NSString *)shareID error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
