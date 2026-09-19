// Uses the author's archive supplied by the caller; third-party files are not checked in.
#import "Tap5aInstaller.h"
#define CHECK(condition) do { if(!(condition)){NSLog(@"Check failed at line %d",__LINE__);return 1;} } while(0)
static int SandboxDownloadProbe(void) {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];[NSApp finishLaunching];
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseFiles=NO;panel.canChooseDirectories=YES;
    NSString *testPath=[NSBundle.mainBundle objectForInfoDictionaryKey:@"SubPopTestDirectory"];if(!testPath)return 3;
    panel.directoryURL=[NSURL fileURLWithPath:testPath];
    panel.message=@"SubPop 隔离安装验证：仅选择 tap5a-install-sandbox 测试目录，不改已有字幕模板。";panel.prompt=@"验证安装";
    if([panel runModal]!=NSModalResponseOK)return 2;
    if(![panel.URL.lastPathComponent isEqual:@"tap5a-install-sandbox"])return 3;
    __block BOOL finished=NO;__block BOOL success=NO;__block NSData *savedBookmark=nil;
    SubPopTap5aInstaller *installer=[SubPopTap5aInstaller new];
    [installer startAtMovies:panel.URL completion:^(NSURL *url,NSError *error){
        NSError *bookmarkError=nil;
        NSData *bookmark=[url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkError];
        savedBookmark=bookmark;success=url && !error && bookmark && !bookmarkError;
        NSString *message=success ? @"Sandbox download, verified extraction, installation and bookmark passed." : [NSString stringWithFormat:@"FAILED: %@ / %@",error,bookmarkError];
        [message writeToURL:[panel.URL URLByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        finished=YES;
    }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:90];
    while(!finished && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    if(!finished)[installer cancel];
    if(success) {
        // finish() has now released the parent folder. Reacquire only the saved template.
        BOOL stale=NO;NSError *e=nil;NSURL *resolved=[NSURL URLByResolvingBookmarkData:savedBookmark options:NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil bookmarkDataIsStale:&stale error:&e];
        BOOL scoped=[resolved startAccessingSecurityScopedResource];success=resolved && !e && SubPopValidTap5a(resolved);
        if(scoped)[resolved stopAccessingSecurityScopedResource];
        BOOL parentScoped=[panel.URL startAccessingSecurityScopedResource];
        [(success ? @"Sandbox download, verified install and template bookmark reopen passed.\n" : @"FAILED template bookmark reopen\n") writeToURL:[panel.URL URLByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if(parentScoped)[panel.URL stopAccessingSecurityScopedResource];
    }
    return success ? 0 : 4;
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc==1)return SandboxDownloadProbe();
        CHECK(argc==2);
        NSData *archive=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];CHECK(archive);
        NSFileManager *fm=NSFileManager.defaultManager;
        NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        CHECK([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:nil error:nil]);
        @try {
            NSError *error=nil;
            CHECK(!SubPopInstallTap5aArchive([NSData data],root,&error) && error);
            CHECK(![fm fileExistsAtPath:SubPopTap5aInstallDirectory(root).path]);
            NSMutableData *bad=archive.mutableCopy;((unsigned char *)bad.mutableBytes)[50]^=1;
            error=nil;CHECK(!SubPopInstallTap5aArchive(bad,root,&error) && error);
            CHECK(![fm fileExistsAtPath:SubPopTap5aInstallDirectory(root).path]);
            NSURL *title=SubPopInstallTap5aArchive(archive,root,&error);CHECK(title && SubPopValidTap5a(title));
            for(NSString *name in @[@"Media",@"small.png",@"large.png",@"Tap5a Autosize Text Background Readme.txt"])
                CHECK([fm fileExistsAtPath:[title.URLByDeletingLastPathComponent URLByAppendingPathComponent:name].path]);
            NSXMLDocument *doc=[[NSXMLDocument alloc] initWithXMLString:@"<fcpxml><resources><effect id='r2' name='' uid=''/></resources><clip><spine/></clip></fcpxml>" options:0 error:nil];
            SubPopSetTitleTemplate(doc,title);CHECK([[doc XMLString] containsString:title.absoluteString]);
            // User changes survive repeat installation.
            NSData *original=[NSData dataWithContentsOfURL:title];
            NSMutableData *custom=original.mutableCopy;[custom appendData:[@"\n<!-- user customisation -->\n" dataUsingEncoding:NSUTF8StringEncoding]];
            CHECK([custom writeToURL:title atomically:YES]);
            CHECK([SubPopInstallTap5aArchive(archive,root,&error) isEqual:title]);
            CHECK([[NSData dataWithContentsOfURL:title] isEqual:custom]);
            // Already-installed templates work without a network request.
            __block BOOL completed=NO;SubPopTap5aInstaller *installer=[SubPopTap5aInstaller new];
            [installer startAtMovies:root completion:^(NSURL *url,NSError *e){completed=[url isEqual:title] && !e;}];
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
            while(!completed && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
            CHECK(completed && !installer.session);
            CHECK([@"keep invalid user file" writeToURL:title atomically:YES encoding:NSUTF8StringEncoding error:nil]);
            error=nil;CHECK(!SubPopInstallTap5aArchive(archive,root,&error) && error);
            CHECK([[NSString stringWithContentsOfURL:title encoding:NSUTF8StringEncoding error:nil] isEqual:@"keep invalid user file"]);
            for(NSString *name in [fm contentsOfDirectoryAtPath:SubPopTap5aInstallDirectory(root).path error:nil])CHECK(![name hasPrefix:@".subpop-install-"]);
            NSURL *legacy=[root URLByAppendingPathComponent:@"legacy"];
            CHECK([fm createDirectoryAtURL:[legacy URLByAppendingPathComponent:@"Motion Templates"] withIntermediateDirectories:YES attributes:nil error:nil]);
            error=nil;CHECK(!SubPopInstallTap5aArchive(archive,legacy,&error) && error);
            CHECK(![fm fileExistsAtPath:[legacy URLByAppendingPathComponent:@"Motion Templates.localized"].path]);
            NSLog(@"Tap5a installer: checksum, first install, XML reference, repeat/offline reuse, conflict preservation and cleanup passed.");
        } @finally {[fm removeItemAtURL:root error:nil];}
    }
    return 0;
}
