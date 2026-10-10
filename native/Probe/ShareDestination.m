#import "ShareDestination.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>
#include <dirent.h>

static NSString *const SPPresetName=@"SubPop.fcpxdest";
static const NSUInteger SPMaxPresetBytes=1024*1024;

static NSDictionary *SPResult(NSString *status,NSString *message) {
    return @{@"status":status,@"message":message};
}

// Walk with descriptors, refusing links even on parent components. An existing
// directory is never chmod'ed or chown'ed. Root-owned sticky temp ancestors are
// allowed for isolated tests, but never for the destination itself.
BOOL SubPopShareDestinationDirectoryModeAllowed(NSString *path,uid_t owner,gid_t group,mode_t mode,BOOL final,BOOL resourceRead) {
    if(!S_ISDIR(mode) || (owner!=0 && owner!=geteuid()))return NO;
    BOOL stickyAncestor=!final && owner==0 && (mode&S_ISVTX);
    struct group *admin=getgrnam("admin");
    // /Applications is root:admin 0775 on standard macOS installs. This exact
    // ancestor is allowed only while reading our bundle, never for a write.
    BOOL applications=resourceRead && !final && [path isEqual:@"/Applications"] && owner==0 && admin && group==admin->gr_gid && (mode&07777)==0775;
    return !(mode&0022) || stickyAncestor || applications;
}

static int SPOpenDirectory(NSURL *URL,BOOL create,mode_t mode,BOOL privateFinal,BOOL resourceRead) {
    NSString *path=URL.path;
    if(!URL.isFileURL || !path.isAbsolutePath || [path.pathComponents containsObject:@".."] || [path.pathComponents containsObject:@"."]) {errno=EINVAL;return -1;}
    // Foundation may shorten Apple's /private/var and /private/tmp aliases.
    // Accept only those exact root-owned OS links, never a caller-created link.
    for(NSString *alias in @[@"/var",@"/tmp"])if([path hasPrefix:[alias stringByAppendingString:@"/"]]) {
        struct stat linkStat={0};char target[64]={0};ssize_t length=readlink(alias.fileSystemRepresentation,target,sizeof(target)-1);
        NSString *expected=[@"private" stringByAppendingString:alias];
        if(lstat(alias.fileSystemRepresentation,&linkStat)!=0 || !S_ISLNK(linkStat.st_mode) || linkStat.st_uid!=0 || length<=0 || ![[NSString stringWithUTF8String:target] isEqual:expected]){errno=EPERM;return -1;}
        path=[@"/private" stringByAppendingString:path];break;
    }
    NSArray *parts=path.pathComponents;int fd=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC);
    if(fd<0)return -1;
    NSString *walk=@"/";
    for(NSUInteger i=1;i<parts.count;i++) {
        NSString *part=parts[i];BOOL last=i==parts.count-1;
        walk=[walk stringByAppendingPathComponent:part];
        int next=openat(fd,part.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        if(next<0 && errno==ENOENT && create) {
            if(mkdirat(fd,part.fileSystemRepresentation,last ? mode : 0755)!=0 && errno!=EEXIST){close(fd);return -1;}
            next=openat(fd,part.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        }
        if(next<0){int saved=errno;close(fd);errno=saved;return -1;}
        struct stat st={0};BOOL valid=fstat(next,&st)==0 && SubPopShareDestinationDirectoryModeAllowed(walk,st.st_uid,st.st_gid,st.st_mode,last,resourceRead);
        if(last && privateFinal)valid=valid && st.st_uid==geteuid() && (st.st_mode&0777)==0700;
        close(fd);fd=next;
        if(!valid){close(fd);errno=EPERM;return -1;}
    }
    return fd;
}

static NSData *SPReadFile(int directory,NSString *name,BOOL privateFile) {
    int fd=openat(directory,name.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
    if(fd<0)return nil;
    struct stat st;BOOL valid=fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_nlink==1 &&
        (st.st_uid==0 || st.st_uid==geteuid()) && !(st.st_mode&0022) && st.st_size>0 && (NSUInteger)st.st_size<=SPMaxPresetBytes;
    if(privateFile)valid=valid && st.st_uid==geteuid() && (st.st_mode&0777)==0600;
    if(!valid){close(fd);errno=EPERM;return nil;}
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)st.st_size];size_t done=0;
    while(done<data.length){ssize_t n=read(fd,(char *)data.mutableBytes+done,data.length-done);if(n<0 && errno==EINTR)continue;if(n<=0){close(fd);errno=EIO;return nil;}done+=(size_t)n;}
    char extra;ssize_t tail=read(fd,&extra,1);close(fd);if(tail!=0){errno=EIO;return nil;}return data;
}

// 0: absent, 1: same bytes (including an FCP-exported alternate filename),
// 2: our fixed filename is occupied or unsafe, -1: unsafe/unreadable directory.
static int SPExisting(NSURL *directory,NSData *preset) {
    int fd=SPOpenDirectory(directory,NO,0755,NO,NO);if(fd<0)return errno==ENOENT ? 0 : -1;
    struct stat st;int found=fstatat(fd,SPPresetName.fileSystemRepresentation,&st,AT_SYMLINK_NOFOLLOW);
    if(found==0){NSData *data=SPReadFile(fd,SPPresetName,NO);close(fd);return [data isEqual:preset] ? 1 : 2;}
    if(errno!=ENOENT){close(fd);return -1;}
    int scan=dup(fd);DIR *stream=scan<0 ? NULL : fdopendir(scan);if(!stream){if(scan>=0)close(scan);close(fd);return -1;}
    BOOL same=NO;struct dirent *entry;NSUInteger count=0;
    while((entry=readdir(stream))) {
        if(++count>4096){closedir(stream);close(fd);return -1;}
        NSString *name=[NSString stringWithUTF8String:entry->d_name];
        if([name.pathExtension.lowercaseString isEqual:@"fcpxdest"] && [SPReadFile(fd,name,NO) isEqual:preset]){same=YES;break;}
    }
    closedir(stream);close(fd);return same ? 1 : 0;
}

static BOOL SPPresetValid(NSData *data) {
    if(!data.length || data.length>SPMaxPresetBytes)return NO;
    // Parse plist containers only; never instantiate NSKeyedArchiver classes.
    id plist=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
    return [plist isKindOfClass:NSDictionary.class] && [plist count]>0;
}

static BOOL SPWriteNew(int directory,NSString *name,NSData *data,mode_t mode) {
    // Publish only after a complete fsync, and never replace an existing file.
    NSString *temporary=[@".SubPop-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int fd=openat(directory,temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,mode);
    if(fd<0)return NO;size_t done=0;BOOL okay=YES;
    while(done<data.length){ssize_t n=write(fd,(const char *)data.bytes+done,data.length-done);if(n<0 && errno==EINTR)continue;if(n<=0){okay=NO;break;}done+=(size_t)n;}
    if(okay && fsync(fd)!=0)okay=NO;close(fd);
    if(okay && linkat(directory,temporary.fileSystemRepresentation,directory,name.fileSystemRepresentation,0)!=0)okay=NO;
    int saved=errno;unlinkat(directory,temporary.fileSystemRepresentation,0);if(okay)fsync(directory);errno=saved;return okay;
}

NSDictionary *SubPopInstallShareDestination(NSData *preset,NSURL *userDirectory,NSURL *systemDirectory,BOOL systemInstall) {
    if(!SPPresetValid(preset))return SPResult(@"failed",@"共享预设资源缺失或无效，请重新安装 SubPop。");
    int user=systemInstall ? 0 : SPExisting(userDirectory,preset),system=SPExisting(systemDirectory,preset);
    if(user==2 || system==2)return SPResult(@"conflict",@"已有同名共享预设，已保留原文件。请在 FCP 中检查 SubPop 目的位置。");
    if(user<0 || system<0)return SPResult(@"failed",@"无法安全读取共享目的位置目录，请检查目录权限后重试。");
    if(user==1 || system==1)return SPResult(@"already-installed",@"共享预设已安装；如 FCP 尚未显示，请重新打开 FCP。");
    NSURL *target=systemInstall ? systemDirectory : userDirectory;
    int fd=SPOpenDirectory(target,YES,0755,NO,NO);
    if(fd<0)return SPResult(@"failed",@"无法创建共享目的位置目录，请检查目录权限后重试。");
    BOOL written=SPWriteNew(fd,SPPresetName,preset,0644);int saved=errno;close(fd);
    if(!written) {
        if(saved==EEXIST){int current=SPExisting(target,preset);if(current==1)return SPResult(@"already-installed",@"共享预设已安装；如 FCP 尚未显示，请重新打开 FCP。");if(current==2)return SPResult(@"conflict",@"已有同名共享预设，已保留原文件。请在 FCP 中检查 SubPop 目的位置。");}
        return SPResult(@"failed",@"共享预设未能保存，请检查目录权限后重试。");
    }
    return SPResult(@"installed",@"共享预设已安装；如 FCP 尚未显示，请重新打开 FCP。");
}

NSDictionary *SubPopShareDestinationRequest(NSURL *URL) {
    if(![URL.scheme isEqual:@"subpop-probe"] || ![URL.host isEqual:@"share-destination"] || URL.user || URL.password || URL.port || URL.fragment || (URL.path.length && ![URL.path isEqual:@"/"]))return nil;
    NSArray *items=[NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO].queryItems;
    if(items.count!=2)return nil;NSMutableDictionary *values=[NSMutableDictionary new];
    for(NSURLQueryItem *item in items){if(![@[@"host",@"request"] containsObject:item.name] || values[item.name] || !item.value.length)return nil;values[item.name]=item.value;}
    if(![@[@"com.apple.FinalCut",@"com.apple.FinalCutApp"] containsObject:values[@"host"]])return nil;
    NSUUID *request=[[NSUUID alloc] initWithUUIDString:values[@"request"]];
    if(!request || [values[@"request"] caseInsensitiveCompare:request.UUIDString]!=NSOrderedSame)return nil;
    return @{@"host":values[@"host"],@"requestID":request.UUIDString};
}

static NSData *SPBundledPreset(NSBundle *bundle) {
    NSURL *directory=[bundle.resourceURL URLByAppendingPathComponent:@"Share Destinations" isDirectory:YES];
    int fd=SPOpenDirectory(directory,NO,0755,NO,YES);if(fd<0)return nil;NSData *data=SPReadFile(fd,SPPresetName,NO);close(fd);return data;
}

BOOL SubPopHandleShareDestinationURL(NSURL *URL,NSBundle *bundle,NSURL *bridgeURL) {
    if(![URL.scheme isEqual:@"subpop-probe"] || ![URL.host isEqual:@"share-destination"])return NO;
    NSDictionary *request=SubPopShareDestinationRequest(URL);if(!request)return YES;
    int bridge=SPOpenDirectory(bridgeURL,NO,0700,YES,NO);if(bridge<0)return YES;close(bridge);
    NSURL *results=[bridgeURL URLByAppendingPathComponent:@"share-destination" isDirectory:YES];
    int directory=SPOpenDirectory(results,YES,0700,YES,NO);if(directory<0)return YES;
    NSString *name=[request[@"requestID"] stringByAppendingString:@".json"];
    struct stat existing;if(fstatat(directory,name.fileSystemRepresentation,&existing,AT_SYMLINK_NOFOLLOW)==0 || errno!=ENOENT){close(directory);return YES;}
    struct passwd *account=getpwuid(getuid());NSDictionary *result;
    if(!account || geteuid()!=getuid() || getuid()==0)result=SPResult(@"failed",@"请从当前用户的 SubPop 面板添加共享目的位置。");
    else {
        NSString *home=[NSString stringWithUTF8String:account->pw_dir];
        NSURL *user=[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Library/Application Support/ProApps/Share Destinations"] isDirectory:YES];
        NSURL *system=[NSURL fileURLWithPath:@"/Library/Application Support/ProApps/Share Destinations" isDirectory:YES];
        result=SubPopInstallShareDestination(SPBundledPreset(bundle),user,system,NO);
    }
    NSMutableDictionary *receipt=result.mutableCopy;[receipt addEntriesFromDictionary:request];receipt[@"protocol"]=@1;receipt[@"createdAt"]=@(NSDate.date.timeIntervalSince1970);
    SPWriteNew(directory,name,[NSJSONSerialization dataWithJSONObject:receipt options:0 error:nil],0600);close(directory);return YES;
}

int SubPopInstallSystemShareDestination(NSBundle *bundle,NSString *volumePath) {
    // Installer is restricted to the boot volume. No path from FCP or a URL is
    // ever passed to this elevated code path.
    if(getuid()!=0 || geteuid()!=0 || ![volumePath isEqual:@"/"])return 2;
    NSDictionary *result=SubPopInstallShareDestination(SPBundledPreset(bundle),nil,[NSURL fileURLWithPath:@"/Library/Application Support/ProApps/Share Destinations" isDirectory:YES],YES);
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    [NSFileHandle.fileHandleWithStandardOutput writeData:json];[NSFileHandle.fileHandleWithStandardOutput writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    return [@[@"installed",@"already-installed"] containsObject:result[@"status"]] ? 0 : 1;
}
