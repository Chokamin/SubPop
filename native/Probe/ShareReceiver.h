#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
// A receive-only implementation of Apple's custom-share MediaAssetProtocol.
// No request starts recognition, opens a project, or uploads media.
@interface SubPopShareReceiver : NSObject
- (instancetype)initWithBridgeURL:(NSURL *)bridgeURL;
// Inject a dedicated private staging root for isolated native protocol tests.
// The production initializer uses a per-user temporary directory, outside the
// AppGroup so FCP can export without access to another application's data.
- (instancetype)initWithBridgeURL:(NSURL *)bridgeURL exportRootURL:(NSURL *)exportRootURL;
// Register before applicationDidFinishLaunching so the first create event is handled.
- (void)registerAppleEventHandlers;
// Returns YES if any file URL belongs to an export created by this receiver.
// Calls completion on the main queue after immutable inbox publication or failure.
- (BOOL)handleOpenURLs:(NSArray<NSURL *> *)URLs completion:(void (^)(NSDictionary * _Nullable manifest, NSError * _Nullable error))completion;
// Pending/receiving shares become terminal; late completion cannot revive them.
- (BOOL)cancelShareID:(NSString *)shareID error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
