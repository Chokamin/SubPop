// Isolated fake Keychain item; never reads or replaces the user's API key.
#import <Cocoa/Cocoa.h>
#import "RuntimePaths.h"
#define SUBPOP_CLOUD_KEY_SERVICE @"com.chokamin.SubPop.doubao.isolated-test"
#import "CloudSettings.h"
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        (void)SubPopWriteCloudStatus;
        if (argc==2 && strcmp(argv[1],"--read")==0) {
            NSString *key=SubPopCloudKey();if (!SubPopCloudKeyValid(key)) return 1;
            [NSFileHandle.fileHandleWithStandardOutput writeData:[key dataUsingEncoding:NSUTF8StringEncoding]];return 0;
        }
        if (SubPopCloudKey()!=nil) return 2; // Do not overwrite a preexisting test item.
        NSString *fake=[@"fake-subpop-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
        if (SubPopSaveCloudKey(fake)!=errSecSuccess) return 3;
        NSTask *child=[NSTask new];child.executableURL=[NSURL fileURLWithPath:@(argv[0])];child.arguments=@[@"--read"];
        NSPipe *pipe=NSPipe.pipe;child.standardOutput=pipe;child.standardError=NSFileHandle.fileHandleWithNullDevice;
        NSError *error=nil;BOOL launched=[child launchAndReturnError:&error];
        NSData *data=launched ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
        if (launched) [child waitUntilExit];
        BOOL same=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] isEqual:fake];
        BOOL removed=SubPopSaveCloudKey(nil)==errSecSuccess && SubPopCloudKey()==nil;
        if (!launched || child.terminationStatus!=0 || !same || !removed) return 4;
        puts("Keychain save, same-executable pipe read, removal: passed (fake item only)");
    }
    return 0;
}
