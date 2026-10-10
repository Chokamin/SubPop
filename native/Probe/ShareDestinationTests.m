#import <Foundation/Foundation.h>
#import "ShareDestination.h"
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <grp.h>

static NSUInteger checks=0;
static void Check(BOOL okay,NSString *message){checks++;if(!okay){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSURL *Child(NSURL *root,NSString *name){return [root URLByAppendingPathComponent:name];}
static void Directory(NSURL *URL){Check([NSFileManager.defaultManager createDirectoryAtURL:URL withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil],@"create isolated directory");}
static void Write(NSURL *URL,NSData *data){Check([data writeToURL:URL options:NSDataWritingAtomic error:nil],@"write fixture");chmod(URL.fileSystemRepresentation,0644);}
static void Status(NSDictionary *result,NSString *expected){Check([result[@"status"] isEqual:expected],[NSString stringWithFormat:@"status %@: %@",expected,result]);}
static NSURL *Request(NSString *query){return [NSURL URLWithString:[@"subpop-probe://share-destination?" stringByAppendingString:query]];}

int main(void){@autoreleasepool{
    NSURL *root=Child([NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES].URLByResolvingSymlinksInPath,[@"SubPopDestinationTests-" stringByAppendingString:NSUUID.UUID.UUIDString]);Directory(root);
    // Synthetic plist exercises safe file publication only. It is deliberately
    // not a product preset or a claim of FCP loading/acceptance.
    NSData *preset=[NSPropertyListSerialization dataWithPropertyList:@{@"test":@"fixed synthetic preset"} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSData *other=[NSPropertyListSerialization dataWithPropertyList:@{@"test":@"user-owned different contents"} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSURL *user=Child(root,@"user/Library/Application Support/ProApps/Share Destinations"),*system=Child(root,@"system/Library/Application Support/ProApps/Share Destinations");
    Status(SubPopInstallShareDestination(nil,user,system,NO),@"failed");Check(![NSFileManager.defaultManager fileExistsAtPath:user.path],@"missing preset does not create destination");
    Status(SubPopInstallShareDestination([@"not a plist" dataUsingEncoding:NSUTF8StringEncoding],user,system,NO),@"failed");
    Status(SubPopInstallShareDestination(preset,user,system,NO),@"installed");
    NSURL *installed=Child(user,@"发送到 SubPop.fcpxdest");Check([[NSData dataWithContentsOfURL:installed] isEqual:preset],@"installed bytes exact");
    struct stat st;Check(lstat(installed.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode) && st.st_nlink==1 && (st.st_mode&0777)==0644,@"preset is complete regular owner-writable file");
    struct group *admin=getgrnam("admin");Check(admin!=NULL,@"macOS admin group exists");gid_t adminID=admin->gr_gid;
    Check(SubPopShareDestinationDirectoryModeAllowed(@"/Applications",0,adminID,S_IFDIR|0775,NO,YES),@"standard system Applications ancestor permitted for bundle read");
    Check(!SubPopShareDestinationDirectoryModeAllowed(@"/Applications",0,adminID,S_IFDIR|0775,NO,NO),@"Applications exception cannot enable destination writes");
    Check(!SubPopShareDestinationDirectoryModeAllowed(@"/Applications",0,adminID,S_IFDIR|0775,YES,YES),@"Applications exception never permits weak final directory");
    Check(!SubPopShareDestinationDirectoryModeAllowed(@"/Applications",getuid(),adminID,S_IFDIR|0775,NO,YES),@"Applications exception requires root owner");
    Check(!SubPopShareDestinationDirectoryModeAllowed(@"/Applications",0,adminID+1,S_IFDIR|0775,NO,YES),@"Applications exception requires exact admin group");
    Check(!SubPopShareDestinationDirectoryModeAllowed(@"/Applications",0,adminID,S_IFDIR|0777,NO,YES),@"Applications exception rejects world-writable directory");
    Check(!SubPopShareDestinationDirectoryModeAllowed(@"/Applications/SubPop.app",0,adminID,S_IFDIR|0775,NO,YES),@"Applications exception does not extend into bundle");
    Check(lstat("/Applications",&st)==0 && SubPopShareDestinationDirectoryModeAllowed(@"/Applications",st.st_uid,st.st_gid,st.st_mode,NO,YES),@"actual standard Applications metadata accepted read-only");
    Status(SubPopInstallShareDestination(preset,user,system,NO),@"already-installed");
    Check([NSFileManager.defaultManager contentsOfDirectoryAtPath:user.path error:nil].count==1,@"repeat creates no extra files");
    Write(installed,other);Status(SubPopInstallShareDestination(preset,user,system,NO),@"conflict");Check([[NSData dataWithContentsOfURL:installed] isEqual:other],@"user same-name preset preserved");
    [NSFileManager.defaultManager removeItemAtURL:installed error:nil];
    Status(SubPopInstallShareDestination(preset,nil,system,YES),@"installed");
    Status(SubPopInstallShareDestination(preset,user,system,NO),@"already-installed");Check(![NSFileManager.defaultManager fileExistsAtPath:installed.path],@"system preset prevents user duplicate");
    Write(installed,other);Status(SubPopInstallShareDestination(preset,user,system,NO),@"conflict");Check([[NSData dataWithContentsOfURL:installed] isEqual:other],@"user collision is reported even when system matches");
    [NSFileManager.defaultManager removeItemAtURL:installed error:nil];
    NSURL *systemFile=Child(system,@"发送到 SubPop.fcpxdest"),*renamed=Child(system,@"SubPop user renamed.fcpxdest");
    Check([NSFileManager.defaultManager moveItemAtURL:systemFile toURL:renamed error:nil],@"rename fixture");Status(SubPopInstallShareDestination(preset,user,system,NO),@"already-installed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:installed.path],@"identical renamed preset prevents duplicate");
    Write(systemFile,other);Status(SubPopInstallShareDestination(preset,nil,system,YES),@"conflict");Check([[NSData dataWithContentsOfURL:systemFile] isEqual:other],@"system collision preserved");
    [NSFileManager.defaultManager removeItemAtURL:systemFile error:nil];[NSFileManager.defaultManager removeItemAtURL:renamed error:nil];
    NSURL *outside=Child(root,@"unrelated.fcpxdest");Write(outside,other);
    Check([NSFileManager.defaultManager createSymbolicLinkAtURL:installed withDestinationURL:outside error:nil],@"create file link fixture");
    Status(SubPopInstallShareDestination(preset,user,system,NO),@"conflict");Check([[NSData dataWithContentsOfURL:outside] isEqual:other],@"symlink target untouched");
    [NSFileManager.defaultManager removeItemAtURL:installed error:nil];
    Check(link(outside.fileSystemRepresentation,installed.fileSystemRepresentation)==0,@"create hardlink fixture");Status(SubPopInstallShareDestination(preset,user,system,NO),@"conflict");
    [NSFileManager.defaultManager removeItemAtURL:installed error:nil];
    chmod(user.fileSystemRepresentation,0777);Status(SubPopInstallShareDestination(preset,user,system,NO),@"failed");Check(lstat(user.fileSystemRepresentation,&st)==0 && (st.st_mode&0777)==0777,@"unsafe permissions never changed");chmod(user.fileSystemRepresentation,0700);
    NSURL *linked=Child(root,@"linked-user");Check([NSFileManager.defaultManager createSymbolicLinkAtURL:linked withDestinationURL:user error:nil],@"create directory link");Status(SubPopInstallShareDestination(preset,linked,system,NO),@"failed");
    NSURL *ancestor=Child(root,@"linked-parent");Check([NSFileManager.defaultManager createSymbolicLinkAtURL:ancestor withDestinationURL:Child(root,@"user") error:nil],@"create ancestor link");
    Status(SubPopInstallShareDestination(preset,Child(ancestor,@"Library/Application Support/ProApps/Share Destinations"),system,NO),@"failed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:installed.path],@"rejected paths cannot write through links");
    NSURL *sourceDirectory=[[NSURL fileURLWithPath:[NSString stringWithUTF8String:__FILE__]] URLByDeletingLastPathComponent];
    NSData *genuine=[NSData dataWithContentsOfURL:Child(sourceDirectory,@"Resources/Share Destinations/发送到 SubPop.fcpxdest")];
    Check(genuine.length==3873,@"real exported preset available for pinned legacy migration checks");
    NSURL *migration=Child(root,@"migration"),*migrationUser=Child(migration,@"user"),*migrationSystem=Child(migration,@"system");
    Directory(migrationUser);Directory(migrationSystem);
    NSURL *oldSystem=Child(migrationSystem,@"SubPop.fcpxdest"),*newSystem=Child(migrationSystem,@"发送到 SubPop.fcpxdest");
    NSURL *oldUser=Child(migrationUser,@"SubPop.fcpxdest"),*newUser=Child(migrationUser,@"发送到 SubPop.fcpxdest");
    Write(oldSystem,genuine);struct stat before,after;Check(lstat(oldSystem.fileSystemRepresentation,&before)==0,@"inspect legacy fixture inode");
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"failed");
    Check([[NSData dataWithContentsOfURL:oldSystem] isEqual:genuine] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"ordinary repair preserves system legacy and creates no user duplicate");
    Status(SubPopInstallShareDestination(genuine,nil,migrationSystem,YES),@"installed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:oldSystem.path] && [[NSData dataWithContentsOfURL:newSystem] isEqual:genuine],@"system upgrade renames only pinned legacy file");
    Check(lstat(newSystem.fileSystemRepresentation,&after)==0 && before.st_ino==after.st_ino && before.st_uid==after.st_uid && before.st_mode==after.st_mode,@"atomic migration preserves inode ownership and permissions");
    Status(SubPopInstallShareDestination(genuine,nil,migrationSystem,YES),@"already-installed");
    Write(oldSystem,genuine);Status(SubPopInstallShareDestination(genuine,nil,migrationSystem,YES),@"installed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:oldSystem.path] && [[NSData dataWithContentsOfURL:newSystem] isEqual:genuine],@"known old and new pair removes only legacy duplicate");
    Write(oldUser,genuine);Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"installed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:oldUser.path] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"existing system preset removes only known user legacy without new duplicate");
    [NSFileManager.defaultManager removeItemAtURL:newSystem error:nil];Write(oldUser,genuine);
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"installed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:oldUser.path] && [[NSData dataWithContentsOfURL:newUser] isEqual:genuine],@"user-only legacy safely migrates in its own directory");
    Write(oldUser,genuine);Write(newUser,other);
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"conflict");
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:genuine] && [[NSData dataWithContentsOfURL:newUser] isEqual:other],@"occupied new filename never overwritten and legacy preserved");
    [NSFileManager.defaultManager removeItemAtURL:newUser error:nil];Write(oldUser,other);
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"conflict");
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:other] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"customized legacy filename is not renamed or removed");
    // Even identical caller-supplied bytes are not enough: migration pins the
    // actual shipped legacy hash, never any arbitrary valid plist.
    Write(oldUser,preset);Status(SubPopInstallShareDestination(preset,migrationUser,migrationSystem,NO),@"conflict");
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:preset],@"unknown legacy hash preserved even when equal to requested preset");
    [NSFileManager.defaultManager removeItemAtURL:oldUser error:nil];
    NSURL *custom=Child(migrationUser,@"My chosen destination.fcpxdest");Write(custom,genuine);Write(oldUser,genuine);
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"installed");
    Check([[NSData dataWithContentsOfURL:custom] isEqual:genuine] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path] && ![NSFileManager.defaultManager fileExistsAtPath:oldUser.path],@"custom filename retained while only pinned legacy duplicate is removed");
    [NSFileManager.defaultManager removeItemAtURL:custom error:nil];Write(outside,genuine);
    Check([NSFileManager.defaultManager createSymbolicLinkAtURL:oldUser withDestinationURL:outside error:nil],@"legacy symlink fixture");
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"conflict");
    Check([[NSData dataWithContentsOfURL:outside] isEqual:genuine] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"legacy symlink is not followed for migration");
    [NSFileManager.defaultManager removeItemAtURL:oldUser error:nil];Check(link(outside.fileSystemRepresentation,oldUser.fileSystemRepresentation)==0,@"legacy hardlink fixture");
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"conflict");
    Check([NSFileManager.defaultManager fileExistsAtPath:oldUser.path] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"legacy hardlink is not migrated");
    [NSFileManager.defaultManager removeItemAtURL:oldUser error:nil];Write(oldSystem,genuine);Write(oldUser,genuine);
    Status(SubPopInstallShareDestination(genuine,nil,migrationSystem,YES),@"installed");
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:genuine],@"root system install does not scan or mutate user legacy");
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"installed");
    Check(![NSFileManager.defaultManager fileExistsAtPath:oldUser.path] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"next explicit repair cleans current-user legacy after system upgrade");
#if defined(SUBPOP_SHARE_DESTINATION_TESTING)
    [NSFileManager.defaultManager removeItemAtURL:newSystem error:nil];Write(oldUser,genuine);
    SubPopSetShareDestinationMigrationCheckpoint(^(NSString *stage,NSURL *directory,NSString *heldName){
        if([stage isEqual:@"verified"])Write(Child(directory,@"SubPop.fcpxdest"),other);
    });
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"failed");
    SubPopSetShareDestinationMigrationCheckpoint(nil);
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:other] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"concurrent FCP replacement is restored unchanged instead of migrated");
    Check([NSFileManager.defaultManager contentsOfDirectoryAtPath:migrationUser.path error:nil].count==1,@"successful rollback leaves no hidden duplicate");
    Write(oldUser,genuine);Write(newUser,genuine);
    SubPopSetShareDestinationMigrationCheckpoint(^(NSString *stage,NSURL *directory,NSString *heldName){
        if([stage isEqual:@"verified"])Write(Child(directory,@"SubPop.fcpxdest"),other);
    });
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"failed");
    SubPopSetShareDestinationMigrationCheckpoint(nil);
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:other] && [[NSData dataWithContentsOfURL:newUser] isEqual:genuine],@"deduplication never deletes a concurrent customized replacement");
    [NSFileManager.defaultManager removeItemAtURL:newUser error:nil];Write(oldUser,genuine);
    SubPopSetShareDestinationMigrationCheckpoint(^(NSString *stage,NSURL *directory,NSString *heldName){
        if([stage isEqual:@"isolated"])Write(Child(directory,@"发送到 SubPop.fcpxdest"),other);
    });
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"failed");
    SubPopSetShareDestinationMigrationCheckpoint(nil);
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:genuine] && [[NSData dataWithContentsOfURL:newUser] isEqual:other],@"concurrent new-name occupant is preserved and old file restored");
    [NSFileManager.defaultManager removeItemAtURL:newUser error:nil];Write(oldUser,genuine);
    __block NSURL *retained=nil;
    SubPopSetShareDestinationMigrationCheckpoint(^(NSString *stage,NSURL *directory,NSString *heldName){
        if([stage isEqual:@"verified"])Write(Child(directory,@"SubPop.fcpxdest"),other);
        if([stage isEqual:@"isolated"]){retained=Child(directory,heldName);Write(Child(directory,@"SubPop.fcpxdest"),genuine);}
    });
    NSDictionary *blockedRestore=SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO);
    SubPopSetShareDestinationMigrationCheckpoint(nil);Status(blockedRestore,@"failed");
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:genuine] && [[NSData dataWithContentsOfURL:retained] isEqual:other],@"blocked rollback retains both concurrent files without overwriting either");
    Check([blockedRestore[@"message"] containsString:retained.path] && ![blockedRestore[@"message"] containsString:@"已恢复原文件"],@"blocked rollback reports retained path instead of claiming in-place restoration");
    [NSFileManager.defaultManager removeItemAtURL:retained error:nil];Write(oldUser,genuine);Write(newUser,genuine);
    SubPopSetShareDestinationMigrationCheckpoint(^(NSString *stage,NSURL *directory,NSString *heldName){
        if([stage isEqual:@"isolated"])[NSFileManager.defaultManager removeItemAtURL:Child(directory,@"发送到 SubPop.fcpxdest") error:nil];
    });
    Status(SubPopInstallShareDestination(genuine,migrationUser,migrationSystem,NO),@"failed");
    SubPopSetShareDestinationMigrationCheckpoint(nil);
    Check([[NSData dataWithContentsOfURL:oldUser] isEqual:genuine] && ![NSFileManager.defaultManager fileExistsAtPath:newUser.path],@"vanished duplicate cannot cause removal of sole remaining preset");
#else
#error ShareDestinationTests require SUBPOP_SHARE_DESTINATION_TESTING for deterministic race coverage
#endif
    NSString *ID=NSUUID.UUID.UUIDString,*query=[NSString stringWithFormat:@"host=com.apple.FinalCutApp&request=%@",ID.lowercaseString];
    NSDictionary *parsed=SubPopShareDestinationRequest(Request(query));Check([parsed[@"requestID"] isEqual:ID] && [parsed[@"host"] isEqual:@"com.apple.FinalCutApp"],@"allowlisted host and normalized UUID");
    Check(SubPopShareDestinationRequest(Request([query stringByReplacingOccurrencesOfString:@"FinalCutApp" withString:@"FinalCut"]))!=nil,@"both real host identifiers accepted");
    for(NSString *invalid in @[[query stringByAppendingString:@"&path=/tmp/foo"],[query stringByAppendingString:@"&host=com.apple.FinalCutApp"],[query stringByReplacingOccurrencesOfString:@"FinalCutApp" withString:@"Unknown"],@"host=com.apple.FinalCutApp&request=../../other",@"host=com.apple.FinalCutApp",[query stringByAppendingString:@"#fragment"]])Check(SubPopShareDestinationRequest(Request(invalid))==nil,@"invalid request rejected");
    for(NSString *base in @[@"subpop-probe://share-destination/other?",@"subpop-probe://name@share-destination?",@"subpop-probe://share-destination:33?",@"https://share-destination?"])Check(SubPopShareDestinationRequest([NSURL URLWithString:[base stringByAppendingString:query]])==nil,@"non-command URL rejected");
    // Receipt/error handling is tested with a bundle that lacks a preset, so
    // this path cannot touch the real user's share-destination directories.
    NSURL *fakeApp=Child(root,@"MissingPreset.app"),*resources=Child(fakeApp,@"Contents/Resources");Directory(resources);
    NSDictionary *info=@{@"CFBundleIdentifier":@"com.chokamin.SubPop.DestinationTest",@"CFBundlePackageType":@"APPL"};Write(Child(fakeApp,@"Contents/Info.plist"),[NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:nil]);
    NSBundle *bundle=[NSBundle bundleWithURL:fakeApp];Check(bundle!=nil,@"test bundle opened");NSURL *bridge=Child(root,@"bridge");Directory(bridge);
    Check(SubPopHandleShareDestinationURL(Request(query),bundle,bridge),@"recognized command handled");
    NSURL *receipt=Child(Child(bridge,@"share-destination"),[ID stringByAppendingString:@".json"]);NSData *bytes=[NSData dataWithContentsOfURL:receipt];NSDictionary *result=bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
    Status(result,@"failed");Check([result[@"requestID"] isEqual:ID] && [result[@"host"] isEqual:@"com.apple.FinalCutApp"] && [result[@"protocol"] isEqual:@1],@"receipt bound to request and host");
    Check(lstat(receipt.fileSystemRepresentation,&st)==0 && (st.st_mode&0777)==0600,@"receipt is private");
    Check(SubPopHandleShareDestinationURL(Request(query),bundle,bridge),@"repeat recognized");Check([[NSData dataWithContentsOfURL:receipt] isEqual:bytes],@"repeat reuses immutable result");
    chmod(bridge.fileSystemRepresentation,0755);NSString *another=[NSString stringWithFormat:@"host=com.apple.FinalCutApp&request=%@",NSUUID.UUID.UUIDString];SubPopHandleShareDestinationURL(Request(another),bundle,bridge);Check([NSFileManager.defaultManager contentsOfDirectoryAtPath:Child(bridge,@"share-destination").path error:nil].count==1,@"public bridge rejected without writing receipt");
    Check(SubPopInstallSystemShareDestination(bundle,@"/Volumes/Other")==2,@"system helper rejects alternate volume before writing");
    if(getuid()!=0)Check(SubPopInstallSystemShareDestination(bundle,@"/")==2,@"system helper requires root");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];printf("%lu checks passed (isolated destination files; no FCP settings or UI)\n",(unsigned long)checks);
}return 0;}
