#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>

#ifndef SUBPOP_CLOUD_KEY_SERVICE
#define SUBPOP_CLOUD_KEY_SERVICE @"com.chokamin.SubPop.doubao"
#endif

static NSDictionary *SubPopCloudKeyQuery(void) {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService:SUBPOP_CLOUD_KEY_SERVICE,
             (__bridge id)kSecAttrAccount:@"api-key"};
}
static NSString *SubPopCloudKey(void) {
    NSMutableDictionary *query=SubPopCloudKeyQuery().mutableCopy;
    query[(__bridge id)kSecReturnData]=@YES;
    // Worker never opens a hidden permission dialog. Re-save in settings to grant access.
    LAContext *context=[LAContext new];context.interactionNotAllowed=YES;
    query[(__bridge id)kSecUseAuthenticationContext]=context;
    CFTypeRef value=NULL;
    OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&value);
    NSData *data=CFBridgingRelease(value);
    return status==errSecSuccess ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}
static BOOL SubPopCloudKeyValid(NSString *key) {
    if (!key.length || key.length>4096) return NO;
    for (NSUInteger i=0;i<key.length;i++) if ([key characterAtIndex:i]<33 || [key characterAtIndex:i]>126) return NO;
    return YES;
}
static OSStatus SubPopSaveCloudKey(NSString *key) {
    NSDictionary *query=SubPopCloudKeyQuery();
    if (!key) {OSStatus result=SecItemDelete((__bridge CFDictionaryRef)query);return result==errSecItemNotFound ? errSecSuccess : result;}
    NSData *data=[key dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (result==errSecItemNotFound) {
        NSMutableDictionary *item=query.mutableCopy;item[(__bridge id)kSecValueData]=data;
        item[(__bridge id)kSecAttrLabel]=@"SubPop · 豆包语音 API Key";
        result=SecItemAdd((__bridge CFDictionaryRef)item,NULL);
    }
    return result;
}
static void SubPopWriteCloudStatus(void) {
    NSString *directory=[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/cloud"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    // Only a capability flag, never the key or any part of it, is shared with the worker.
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"configured":@(SubPopCloudKeyValid(SubPopCloudKey()))} options:0 error:nil];
    [data writeToFile:[directory stringByAppendingPathComponent:@"doubao.json"] atomically:YES];
}
