// Isolated fake Keychain item; never reads or replaces the user's API key.
#import <Cocoa/Cocoa.h>
#import "RuntimePaths.h"
#define SUBPOP_CLOUD_KEY_SERVICE @"com.chokamin.SubPop.doubao.isolated-test"
#import "CloudSettings.h"
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        (void)SubPopWriteCloudStatus;
        if (argc==2 && strcmp(argv[1],"--read-legacy")==0) {
            NSDictionary *value=SubPopLegacyCredentials();if (!SubPopLegacyValid(value)) return 1;
            [NSFileHandle.fileHandleWithStandardOutput writeData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil]];return 0;
        }
        if (argc==2 && strcmp(argv[1],"--read")==0) {
            NSDictionary *value=SubPopCloudCredentials();if (!value) return 1;
            [NSFileHandle.fileHandleWithStandardOutput writeData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil]];return 0;
        }
        if (SubPopCloudKey()!=nil || SubPopTOSConfig().count || SubPopLegacyCredentials().count) return 2; // Do not overwrite a preexisting test item.
        NSDictionary *legacy=@{@"appID":@"123456789",@"accessToken":@"fake-legacy-token"};
        if (SubPopSaveLegacy(@{@"appID":@"invalid",@"accessToken":@"fake"})!=errSecParam || SubPopLegacyCredentials().count) return 7;
        if (SubPopSaveLegacy(legacy)!=errSecSuccess) return 8;
        NSTask *legacyChild=[NSTask new];legacyChild.executableURL=[NSURL fileURLWithPath:@(argv[0])];legacyChild.arguments=@[@"--read-legacy"];
        NSPipe *legacyPipe=NSPipe.pipe;legacyChild.standardOutput=legacyPipe;legacyChild.standardError=NSFileHandle.fileHandleWithNullDevice;
        BOOL legacyLaunched=[legacyChild launchAndReturnError:nil];NSData *legacyData=legacyLaunched ? [legacyPipe.fileHandleForReading readDataToEndOfFile] : nil;
        if (legacyLaunched) [legacyChild waitUntilExit];
        NSDictionary *readLegacy=legacyData ? [NSJSONSerialization JSONObjectWithData:legacyData options:0 error:nil] : nil;
        NSDictionary *legacyState=SubPopCloudStatus();
        NSString *legacyMetadata=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:legacyState options:0 error:nil] encoding:NSUTF8StringEncoding];
        BOOL legacyOK=legacyLaunched && legacyChild.terminationStatus==0 && [readLegacy isEqual:legacy] && [legacyState[@"legacyConfigured"] boolValue] && ![legacyState[@"configured"] boolValue] && ![legacyMetadata containsString:@"123456789"] && ![legacyMetadata containsString:@"fake-legacy-token"];
        legacyOK=(SubPopSaveLegacy(nil)==errSecSuccess && !SubPopLegacyCredentials().count && ![SubPopCloudStatus()[@"legacyConfigured"] boolValue]) && legacyOK;
        if (!legacyOK) return 9;
        NSString *fake=[@"fake-subpop-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
        if (SubPopSaveCloudKey(fake)!=errSecSuccess) return 3;
        NSDictionary *tos=@{@"region":@"cn-beijing",@"bucket":@"subpop-test",@"tosAccessKey":@"fake-ak",@"tosSecretKey":@"fake-sk"};
        if (![SubPopCloudCredentials()[@"apiKey"] isEqual:fake] || ![SubPopCloudStatus()[@"configured"] boolValue] || !SubPopTOSValid(tos)) {SubPopSaveCloudKey(nil);return 5;}
        if (SubPopSaveTOS(tos)!=errSecSuccess) {SubPopSaveCloudKey(nil);return 6;}
        NSTask *child=[NSTask new];child.executableURL=[NSURL fileURLWithPath:@(argv[0])];child.arguments=@[@"--read"];
        NSPipe *pipe=NSPipe.pipe;child.standardOutput=pipe;child.standardError=NSFileHandle.fileHandleWithNullDevice;
        NSError *error=nil;BOOL launched=[child launchAndReturnError:&error];
        NSData *data=launched ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
        if (launched) [child waitUntilExit];
        NSDictionary *value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        BOOL same=[value[@"apiKey"] isEqual:fake] && value.count==1; // Old TOS secrets must not travel to the worker.
        NSDictionary *state=SubPopCloudStatus();
        same=same && [state[@"version"] integerValue]==3 && [state[@"configured"] boolValue] && CFGetTypeID((__bridge CFTypeRef)state[@"configured"])==CFBooleanGetTypeID();
        NSString *metadata=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] encoding:NSUTF8StringEncoding];
        same=same && ![metadata containsString:fake] && ![metadata containsString:@"fake-ak"] && ![metadata containsString:@"fake-sk"];
        BOOL removed=SubPopSaveCloudKey(nil)==errSecSuccess && SubPopCloudKey()==nil;
        removed=(SubPopSaveTOS(nil)==errSecSuccess && SubPopTOSConfig().count==0 && SubPopCloudCredentials()==nil) && removed;
        if (!launched || child.terminationStatus!=0 || !same || !removed) return 4;
        puts("Keychain save, same-executable pipe read, removal: passed (fake item only)");
    }
    return 0;
}
