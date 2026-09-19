#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>

#ifndef SUBPOP_CLOUD_KEY_SERVICE
#define SUBPOP_CLOUD_KEY_SERVICE @"com.chokamin.SubPop.doubao"
#endif

static NSDictionary *SubPopSecretQuery(NSString *account) {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService:SUBPOP_CLOUD_KEY_SERVICE,
             (__bridge id)kSecAttrAccount:account};
}
static NSString *SubPopReadSecret(NSString *account) {
    NSMutableDictionary *query=SubPopSecretQuery(account).mutableCopy;
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
static OSStatus SubPopSaveSecret(NSString *account, NSString *key) {
    NSDictionary *query=SubPopSecretQuery(account);
    if (!key) {OSStatus result=SecItemDelete((__bridge CFDictionaryRef)query);return result==errSecItemNotFound ? errSecSuccess : result;}
    NSData *data=[key dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (result==errSecItemNotFound) {
        NSMutableDictionary *item=query.mutableCopy;item[(__bridge id)kSecValueData]=data;
        item[(__bridge id)kSecAttrLabel]=@"SubPop · 云端识别凭证";
        result=SecItemAdd((__bridge CFDictionaryRef)item,NULL);
    }
    return result;
}
static NSString *SubPopCloudKey(void) {return SubPopReadSecret(@"api-key");}
static OSStatus SubPopSaveCloudKey(NSString *key) {return SubPopSaveSecret(@"api-key",key);}
static NSDictionary *SubPopLegacyCredentials(void) {
    NSData *data=[SubPopReadSecret(@"legacy-speech") dataUsingEncoding:NSUTF8StringEncoding];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static BOOL SubPopLegacyValid(NSDictionary *value) {
    id appID=value[@"appID"],token=value[@"accessToken"];
    return [appID isKindOfClass:NSString.class] && [[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"[0-9]{1,32}"] evaluateWithObject:appID] && [token isKindOfClass:NSString.class] && SubPopCloudKeyValid(token);
}
static OSStatus SubPopSaveLegacy(NSDictionary *value) {
    if (value && !SubPopLegacyValid(value)) return errSecParam;
    NSString *json=value ? [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding] : nil;
    return SubPopSaveSecret(@"legacy-speech",json);
}
static NSDictionary *SubPopTOSConfig(void) {
    NSData *data=[SubPopReadSecret(@"tos-credentials") dataUsingEncoding:NSUTF8StringEncoding];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static BOOL SubPopTOSValid(NSDictionary *value) {
    if (![@[@"cn-beijing",@"cn-shanghai",@"cn-guangzhou"] containsObject:value[@"region"] ?: @""]) return NO;
    id bucket=value[@"bucket"];
    if (![bucket isKindOfClass:NSString.class] || ![[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]"] evaluateWithObject:bucket]) return NO;
    return [value[@"tosAccessKey"] isKindOfClass:NSString.class] && [value[@"tosSecretKey"] isKindOfClass:NSString.class] && SubPopCloudKeyValid(value[@"tosAccessKey"]) && SubPopCloudKeyValid(value[@"tosSecretKey"]);
}
static OSStatus SubPopSaveTOS(NSDictionary *value) {
    NSString *json=value ? [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding] : nil;
    return SubPopSaveSecret(@"tos-credentials",json);
}
static NSDictionary *SubPopCloudCredentials(void) {
    NSString *key=SubPopCloudKey();NSDictionary *tos=SubPopTOSConfig();
    if (!SubPopCloudKeyValid(key) || !SubPopTOSValid(tos)) return nil;
    NSMutableDictionary *value=tos.mutableCopy;value[@"apiKey"]=key;return value;
}
static NSDictionary *SubPopCloudStatus(void) {
    // Only non-secret readiness flags and region/bucket identifiers reach disk.
    NSDictionary *tos=SubPopTOSConfig();BOOL api=SubPopCloudKeyValid(SubPopCloudKey()),storage=SubPopTOSValid(tos);
    return @{@"version":@2,@"configured":api && storage ? @YES : @NO,@"apiKeyConfigured":@(api),@"storageConfigured":@(storage),@"legacyConfigured":@(SubPopLegacyValid(SubPopLegacyCredentials())),@"region":tos[@"region"] ?: @"",@"bucket":tos[@"bucket"] ?: @""};
}
static void SubPopWriteCloudStatus(void) {
    NSString *directory=[SubPopWorkspace(NSBundle.mainBundle) stringByAppendingPathComponent:@".subloom/cloud"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSData *data=[NSJSONSerialization dataWithJSONObject:SubPopCloudStatus() options:0 error:nil];
    [data writeToFile:[directory stringByAppendingPathComponent:@"doubao.json"] atomically:YES];
}
