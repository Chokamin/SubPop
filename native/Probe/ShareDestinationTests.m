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
    NSURL *installed=Child(user,@"SubPop.fcpxdest");Check([[NSData dataWithContentsOfURL:installed] isEqual:preset],@"installed bytes exact");
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
    NSURL *systemFile=Child(system,@"SubPop.fcpxdest"),*renamed=Child(system,@"SubPop user renamed.fcpxdest");
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
