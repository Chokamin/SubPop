#import <Cocoa/Cocoa.h>
#import "ShareReceiver.h"
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <limits.h>

@interface SubPopShareReceiver (Testing)
- (void)createAsset:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply;
- (void)getAssetProperty:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply;
@end
static NSUInteger checks=0;
static void Check(BOOL yes,NSString *message){checks++;if(!yes){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSAppleEventDescriptor *Event(OSType ID){return [NSAppleEventDescriptor appleEventWithEventClass:'core' eventID:ID targetDescriptor:NSAppleEventDescriptor.nullDescriptor returnID:-1 transactionID:0];}
static void CreateFails(SubPopShareReceiver *receiver,NSString *message) {
    NSAppleEventDescriptor *event=Event('crel'),*reply=Event('ansr');
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'aset'] forKeyword:'kocl'];
    [receiver createAsset:event reply:reply];Check([reply paramDescriptorForKeyword:'errn']!=nil,message);
}
static NSDictionary *Create(SubPopShareReceiver *receiver,NSString *name){
    NSAppleEventDescriptor *event=Event('crel'),*reply=Event('ansr'),*properties=NSAppleEventDescriptor.recordDescriptor;
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'aset'] forKeyword:'kocl'];
    [properties setDescriptor:[NSAppleEventDescriptor descriptorWithString:name] forKeyword:'pnam'];
    NSAppleEventDescriptor *options=NSAppleEventDescriptor.recordDescriptor,*pairs=NSAppleEventDescriptor.listDescriptor,*versions=NSAppleEventDescriptor.listDescriptor;
    [pairs insertDescriptor:[NSAppleEventDescriptor descriptorWithString:@"availableDescriptionVersions"] atIndex:0];
    for(NSString *version in @[@"1.9",@"1.10",@"1.14",@"1.15"])[versions insertDescriptor:[NSAppleEventDescriptor descriptorWithString:version] atIndex:0];
    [pairs insertDescriptor:versions atIndex:0];[options setDescriptor:pairs forKeyword:'usrf'];[properties setDescriptor:options forKeyword:'dopt'];
    [event setParamDescriptor:properties forKeyword:'prdt'];[receiver createAsset:event reply:reply];
    Check(![reply paramDescriptorForKeyword:'errn'],@"create event succeeds");
    NSAppleEventDescriptor *asset=[reply paramDescriptorForKeyword:'----'];NSString *ID=[asset descriptorForKeyword:'seld'].stringValue;
    Check([[NSUUID alloc] initWithUUIDString:ID]!=nil,@"create returns unique ID object specifier");
    NSAppleEventDescriptor *object=NSAppleEventDescriptor.recordDescriptor;
    [object setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'prop'] forKeyword:'want'];[object setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:'prop'] forKeyword:'form'];[object setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'locn'] forKeyword:'seld'];[object setDescriptor:asset forKeyword:'from'];
    event=Event('getd');reply=Event('ansr');[event setParamDescriptor:[object coerceToDescriptorType:'obj '] forKeyword:'----'];[receiver getAssetProperty:event reply:reply];
    Check(![reply paramDescriptorForKeyword:'errn'],@"get location succeeds");NSAppleEventDescriptor *location=[reply paramDescriptorForKeyword:'----'];
    Check([location descriptorForKeyword:'ashm'].booleanValue && [location descriptorForKeyword:'ashd'].booleanValue,@"requests paired media and description");
    NSURL *folder=[location descriptorForKeyword:'asfd'].fileURLValue;NSString *base=[location descriptorForKeyword:'asbn'].stringValue;
    Check(folder.isFileURL && base.length,@"returns file URL and matching base");
    return @{@"id":ID,@"folder":folder,@"name":base,@"specifier":asset};
}
static NSAppleEventDescriptor *Property(SubPopShareReceiver *receiver,NSDictionary *share,OSType property) {
    NSAppleEventDescriptor *object=NSAppleEventDescriptor.recordDescriptor;
    [object setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'prop'] forKeyword:'want'];
    [object setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:'prop'] forKeyword:'form'];
    [object setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:property] forKeyword:'seld'];
    [object setDescriptor:share[@"specifier"] forKeyword:'from'];
    NSAppleEventDescriptor *event=Event('getd'),*reply=Event('ansr');
    [event setParamDescriptor:[object coerceToDescriptorType:'obj '] forKeyword:'----'];[receiver getAssetProperty:event reply:reply];
    Check(![reply paramDescriptorForKeyword:'errn'],@"documented asset property answered");return [reply paramDescriptorForKeyword:'----'];
}
static NSArray *Files(NSDictionary *share,NSString *XML){
    NSURL *folder=share[@"folder"];NSString *name=share[@"name"];
    NSURL *xml=[folder URLByAppendingPathComponent:[name stringByAppendingString:@".fcpxml"]],*audio=[folder URLByAppendingPathComponent:[name stringByAppendingString:@".wav"]];
    [XML writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // Receiver is format-agnostic; actual decode/duration is checked downstream.
    [@"RIFF synthetic receive-only bytes" writeToURL:audio atomically:YES encoding:NSUTF8StringEncoding error:nil];return @[xml,audio];
}
static NSDictionary *Receive(SubPopShareReceiver *receiver,NSArray *files,BOOL success){
    __block BOOL finished=NO;__block NSDictionary *result=nil;__block NSError *failure=nil;
    Check([receiver handleOpenURLs:files completion:^(NSDictionary *manifest,NSError *error){result=manifest;failure=error;finished=YES;}],@"completion URLs recognized");
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while(!finished && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(finished,@"completion delivered");Check(success ? result!=nil && !failure : !result && failure!=nil,@"expected validation result");return result;
}
int main(void){@autoreleasepool{
    NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"SubPopShareTests-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    root=root.URLByResolvingSymlinksInPath;
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSURL *bridge=[root URLByAppendingPathComponent:@"private-bridge" isDirectory:YES],*exportRoot=[root URLByAppendingPathComponent:@"handoff" isDirectory:YES];
    SubPopShareReceiver *receiver=[[SubPopShareReceiver alloc] initWithBridgeURL:bridge exportRootURL:exportRoot];
    NSString *XML=@"<?xml version='1.0'?><!DOCTYPE fcpxml><fcpxml version='1.14'><resources><format id='r1' frameDuration='1/25s' width='1920' height='1080'/></resources><library><event name='test'><project uid='TEST-UID' name='完整项目'><sequence format='r1' duration='250/25s'><spine><gap duration='10s'/></spine></sequence></project></event></library></fcpxml>";
    NSDictionary *first=Create(receiver,@"同名项目"),*second=Create(receiver,@"同名项目");Check(![first[@"id"] isEqual:second[@"id"]],@"same-name shares remain distinct");
    Check(![[first[@"folder"] path] hasPrefix:[bridge.path stringByAppendingString:@"/"]],@"FCP raw export directory is outside private bridge data");
    struct stat exportStat;Check(lstat(exportRoot.fileSystemRepresentation,&exportStat)==0 && exportStat.st_uid==getuid() && (exportStat.st_mode&07777)==0700,@"handoff root is current-user private");
    NSURL *firstState=[[[bridge URLByAppendingPathComponent:@"share-exports"] URLByAppendingPathComponent:first[@"id"]] URLByAppendingPathComponent:@"asset.json"];
    NSDictionary *saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:firstState] options:0 error:nil];
    Check([saved[@"exportRoot"] isEqual:exportRoot.path],@"transaction persistently binds its exact handoff root");
    Check([Property(receiver,first,'ID  ').stringValue isEqual:first[@"id"]],@"asset identity matches returned object specifier");
    Check([Property(receiver,first,'pnam').stringValue isEqual:first[@"name"]],@"asset name matches export base");
    NSAppleEventDescriptor *library=Property(receiver,first,'lbry');Check(![library descriptorForKeyword:'lbha'].booleanValue && ![library descriptorForKeyword:'lbhd'].booleanValue,@"never requests library archives or library XML");
    NSAppleEventDescriptor *options=Property(receiver,first,'dopt'),*pairs=[options descriptorForKeyword:'usrf'];
    Check([[pairs descriptorAtIndex:1].stringValue isEqual:@"descriptionVersion"] && [[pairs descriptorAtIndex:2].stringValue isEqual:@"1.14"],@"selects newest supported offered FCPXML version");
    Check([Property(receiver,first,'meta') descriptorForKeyword:'usrf'].numberOfItems==0,@"no new project metadata is inserted");
    NSArray *files=Files(first,XML),*otherFiles=Files(second,[XML stringByReplacingOccurrencesOfString:@"TEST-UID" withString:@"SECOND-UID"]);
    // FCP can return /private/var URLs for files whose returned export folder
    // uses /var. Foundation standardizes existing paths differently from raw
    // URL.path; the entire receive operation must apply one canonical form.
    NSMutableArray *physicalFiles=[NSMutableArray new];
    for(NSURL *URL in files) {
        char resolved[PATH_MAX];Check(realpath(URL.fileSystemRepresentation,resolved)!=NULL,@"actual export fixture has physical path");
        NSURL *physical=[NSURL fileURLWithPath:[NSString stringWithUTF8String:resolved]];
        Check([physical.URLByStandardizingPath.path isEqual:URL.URLByStandardizingPath.path],@"physical and Foundation file URLs identify same export");
        [physicalFiles addObject:physical];
    }
    NSDictionary *manifest=Receive(receiver,physicalFiles,YES);
    Check([manifest[@"projectUID"] isEqual:@"TEST-UID"] && [manifest[@"audioSHA256"] length]==64 && [manifest[@"xmlSHA256"] length]==64,@"bound identity and checksums");
    NSURL *inbox=[[bridge URLByAppendingPathComponent:@"share-inbox"] URLByAppendingPathComponent:first[@"id"]];
    Check([NSFileManager.defaultManager fileExistsAtPath:[inbox URLByAppendingPathComponent:@"ready.json"].path],@"manifest published");
    Check(![NSFileManager.defaultManager fileExistsAtPath:[first[@"folder"] path]],@"raw export removed only after publication");
    __block NSUInteger repeats=0;Check([receiver handleOpenURLs:files completion:^(NSDictionary *m,NSError *e){repeats++;}],@"duplicate owned callback is handled");
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];Check(repeats==0,@"duplicate cannot republish");
    Check([Receive(receiver,otherFiles,YES)[@"projectUID"] isEqual:@"SECOND-UID"],@"out-of-order matching by asset works");
    NSDictionary *bundle=Create(receiver,@"描述包");NSArray *bundleFiles=Files(bundle,XML);NSURL *package=[bundle[@"folder"] URLByAppendingPathComponent:@"描述包.fcpxmld" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:package withIntermediateDirectories:NO attributes:nil error:nil];
    [NSFileManager.defaultManager moveItemAtURL:bundleFiles[0] toURL:[package URLByAppendingPathComponent:@"Info.fcpxml"] error:nil];
    Check([Receive(receiver,@[package,bundleFiles[1]],YES)[@"projectUID"] isEqual:@"TEST-UID"],@"bundled FCPXML accepted without any original media lookup");
    NSDictionary *missing=Create(receiver,@"缺 XML");NSArray *missingFiles=Files(missing,XML);Receive(receiver,@[missingFiles[1]],NO);
    NSDictionary *role=Create(receiver,@"分角色");NSArray *roleFiles=Files(role,XML);NSURL *roleURL=[role[@"folder"] URLByAppendingPathComponent:@"分角色 - Dialogue.wav"];
    [NSFileManager.defaultManager moveItemAtURL:roleFiles[1] toURL:roleURL error:nil];Receive(receiver,@[roleFiles[0],roleURL],NO);
    NSDictionary *entity=Create(receiver,@"实体");Receive(receiver,Files(entity,[XML stringByReplacingOccurrencesOfString:@"<!DOCTYPE fcpxml>" withString:@"<!DOCTYPE fcpxml [<!ENTITY test SYSTEM 'file:///etc/passwd'>]>"]),NO);
    NSDictionary *clip=Create(receiver,@"片段");Receive(receiver,Files(clip,@"<fcpxml><resources/><clip name='not a project'/></fcpxml>"),NO);
    for(NSString *clock in @[@"10.0s",@"1e1s",@"9223372036854775808s",@"250/2147483648s"]) {
        NSDictionary *badClock=Create(receiver,@"无效时钟");Receive(receiver,Files(badClock,[XML stringByReplacingOccurrencesOfString:@"250/25s" withString:clock]),NO);
    }
    NSDictionary *badFrame=Create(receiver,@"无效帧率");Receive(receiver,Files(badFrame,[XML stringByReplacingOccurrencesOfString:@"1/25s" withString:@"1/29s"]),NO);
    NSDictionary *blankName=Create(receiver,@"空项目名");Receive(receiver,Files(blankName,[XML stringByReplacingOccurrencesOfString:@"name='完整项目'" withString:@"name='' "]),NO);
    NSDictionary *cancel=Create(receiver,@"取消");NSArray *cancelFiles=Files(cancel,XML);Check([receiver cancelShareID:cancel[@"id"] error:nil],@"cancel succeeds");
    __block BOOL cancelledDelivered=NO;[receiver handleOpenURLs:cancelFiles completion:^(NSDictionary *m,NSError *e){cancelledDelivered=YES;}];[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];Check(!cancelledDelivered,@"late cancelled event stays inert");
    Check(![NSFileManager.defaultManager fileExistsAtPath:[cancel[@"folder"] path]],@"late completion safely cleans cancelled raw files");
    NSDictionary *restart=Create(receiver,@"重启");NSArray *restartFiles=Files(restart,XML);receiver=[[SubPopShareReceiver alloc] initWithBridgeURL:bridge exportRootURL:exportRoot];Check([Receive(receiver,restartFiles,YES)[@"shareID"] isEqual:restart[@"id"]],@"asset state survives process restart with staging outside bridge");
    NSDictionary *symbol=Create(receiver,@"链接");NSArray *symbolFiles=Files(symbol,XML);[NSFileManager.defaultManager removeItemAtURL:symbolFiles[1] error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtURL:symbolFiles[1] withDestinationURL:restartFiles[0] error:nil];Receive(receiver,symbolFiles,NO);
    Check(![receiver handleOpenURLs:@[[NSURL fileURLWithPath:@"/tmp/unrelated.wav"]] completion:^(NSDictionary *m,NSError *e){}],@"ordinary files are not paired automatically");
    NSURL *weak=[root URLByAppendingPathComponent:@"weak-permissions"];
    [NSFileManager.defaultManager createDirectoryAtURL:weak withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0755} error:nil];
    CreateFails([[SubPopShareReceiver alloc] initWithBridgeURL:bridge exportRootURL:weak],@"existing weak-mode handoff root rejected without chmod");
    Check(lstat(weak.fileSystemRepresentation,&exportStat)==0 && (exportStat.st_mode&07777)==0755,@"unsafe root is not silently repaired");
    NSURL *link=[root URLByAppendingPathComponent:@"linked-handoff"];
    [NSFileManager.defaultManager createSymbolicLinkAtURL:link withDestinationURL:exportRoot error:nil];
    CreateFails([[SubPopShareReceiver alloc] initWithBridgeURL:bridge exportRootURL:link],@"symlink staging root rejected");
    CreateFails([[SubPopShareReceiver alloc] initWithBridgeURL:bridge exportRootURL:[NSURL fileURLWithPath:@"/private"]],@"root-owned ancestor rejected before staging creation");
    NSDictionary *swapped=Create(receiver,@"权限改变");NSArray *swappedFiles=Files(swapped,XML);
    chmod([swapped[@"folder"] fileSystemRepresentation],0755);Receive(receiver,swappedFiles,NO);
    Check([NSFileManager.defaultManager fileExistsAtPath:[swappedFiles[1] path]],@"unsafe replaced export directory is neither imported nor recursively removed");
    chmod([swapped[@"folder"] fileSystemRepresentation],0700);
    NSURL *otherRoot=[root URLByAppendingPathComponent:@"other-root"];
    SubPopShareReceiver *differentRoot=[[SubPopShareReceiver alloc] initWithBridgeURL:bridge exportRootURL:otherRoot];
    Check(![differentRoot handleOpenURLs:swappedFiles completion:^(NSDictionary *m,NSError *e){}],@"restart with another handoff root cannot adopt a previous root's files");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];printf("Share receiver native protocol/transaction tests: %lu checks passed (simulated FCP events, no host verification).\n",(unsigned long)checks);
}return 0;}
