#import "ShareReceiver.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>
#include <errno.h>
#include <stdlib.h>

// Apple protocol: https://developer.apple.com/documentation/professional-video-applications/creating-scripting-definitions-for-custom-share-destinations
// Each asset owns a private export directory. Open events never pair files from
// unrelated directories, the foreground project, or a global "latest" slot.
static NSString *const SPShareErrorDomain=@"SubPopShareReceiver";
static const uint64_t SPMaxAudioBytes=4ULL*1024*1024*1024;
static const uint64_t SPMaxXMLBytes=16ULL*1024*1024;
static NSError *SPError(NSString *message) { return [NSError errorWithDomain:SPShareErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static BOOL SPFail(NSError **error,NSString *message) {if(error)*error=SPError(message);return NO;}
static BOOL SPUUID(NSString *value) {return [value isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:value]!=nil && [value isEqual:value.uppercaseString];}
static BOOL SPSafePath(NSURL *URL) {
    if(!URL.isFileURL || !URL.path.isAbsolutePath)return NO;
    NSString *path=URL.path.stringByStandardizingPath;
    // Symlink ancestors are rejected as well as the leaf (including bundles).
    return [path isEqual:URL.URLByResolvingSymlinksInPath.path.stringByStandardizingPath];
}
static BOOL SPDirectory(NSURL *URL,BOOL create,NSError **error) {
    if(!SPSafePath(URL))return SPFail(error,@"共享目录包含无效的路径或符号链接");
    if(create && ![NSFileManager.defaultManager createDirectoryAtURL:URL withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;
    struct stat st;if(lstat(URL.fileSystemRepresentation,&st)!=0 || !S_ISDIR(st.st_mode) || st.st_uid!=getuid())return SPFail(error,@"共享目录不可用");
    return YES;
}
static BOOL SPPrivateDirectory(NSURL *URL,BOOL create,NSError **error) {
    // Do not repair or follow an existing directory owned by another process or
    // with broader permissions. mkdir never follows a final symlink.
    if(!SPSafePath(URL))return SPFail(error,@"共享临时目录包含符号链接");
    if(create && mkdir(URL.fileSystemRepresentation,0700)!=0 && errno!=EEXIST)return SPFail(error,@"无法创建共享临时目录");
    struct stat st;
    if(lstat(URL.fileSystemRepresentation,&st)!=0 || !S_ISDIR(st.st_mode) || st.st_uid!=getuid() || (st.st_mode&07777)!=0700)return SPFail(error,@"共享临时目录的所有者或权限无效");
    return YES;
}
static NSDictionary *SPJSON(NSURL *URL) {
    if(!SPSafePath(URL))return nil;
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:URL.path error:nil];
    if(![attrs[NSFileType] isEqual:NSFileTypeRegular] || [attrs[NSFileSize] unsignedLongLongValue]>65536)return nil;
    NSData *data=[NSData dataWithContentsOfURL:URL];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static BOOL SPWriteJSON(NSDictionary *value,NSURL *URL,NSError **error) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:error];
    if(!data || ![data writeToURL:URL options:NSDataWritingAtomic error:error])return NO;
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:URL.path error:error];
}
static NSAppleEventDescriptor *SPUserRecord(NSDictionary<NSString *,NSString *> *values) {
    NSAppleEventDescriptor *record=NSAppleEventDescriptor.recordDescriptor,*list=NSAppleEventDescriptor.listDescriptor;
    for(NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [list insertDescriptor:[NSAppleEventDescriptor descriptorWithString:key] atIndex:0];
        [list insertDescriptor:[NSAppleEventDescriptor descriptorWithString:values[key]] atIndex:0];
    }
    [record setDescriptor:list forKeyword:'usrf'];return record;
}
static NSString *SPDescriptionVersion(NSAppleEventDescriptor *options) {
    NSAppleEventDescriptor *list=[options descriptorForKeyword:'usrf'];NSString *best=nil;
    for(NSInteger i=1;i+1<=list.numberOfItems;i+=2) {
        if(![[list descriptorAtIndex:i].stringValue isEqual:@"availableDescriptionVersions"])continue;
        NSAppleEventDescriptor *versions=[list descriptorAtIndex:i+1];
        for(NSInteger j=1;j<=versions.numberOfItems;j++) {
            NSString *value=[versions descriptorAtIndex:j].stringValue;
            if(![value hasPrefix:@"1."])continue;
            NSString *minor=[value substringFromIndex:2];
            if(!minor.length || [minor rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound || minor.integerValue>14 || minor.integerValue<8)continue;
            if(!best || [best compare:value options:NSNumericSearch]==NSOrderedAscending)best=value;
        }
    }
    return best;
}
static NSAppleEventDescriptor *SPAssetSpecifier(NSString *ID) {
    NSAppleEventDescriptor *record=NSAppleEventDescriptor.recordDescriptor;
    [record setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'aset'] forKeyword:'want'];
    [record setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:'ID  '] forKeyword:'form'];
    [record setDescriptor:[NSAppleEventDescriptor descriptorWithString:ID] forKeyword:'seld'];
    [record setDescriptor:NSAppleEventDescriptor.nullDescriptor forKeyword:'from'];
    return [record coerceToDescriptorType:'obj '];
}
static void SPReplyError(NSAppleEventDescriptor *reply,NSString *message) {
    [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithInt32:-1708] forKeyword:'errn'];
    [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:message] forKeyword:'errs'];
}
// Bounded streaming copy, checksum and inode/mtime stability check. No full audio
// allocation, symbolic links, device files, or paths outside the transaction.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static NSString *SPCopy(NSURL *source,NSURL *target,uint64_t limit,NSError **error) {
    if(!SPSafePath(source)){SPFail(error,@"共享文件包含符号链接");return nil;}
    int input=open(source.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
    struct stat before,after;
    if(input<0 || fstat(input,&before)!=0 || !S_ISREG(before.st_mode) || before.st_uid!=getuid() || before.st_size<=0 || (uint64_t)before.st_size>limit) {
        if(input>=0)close(input);SPFail(error,@"共享文件为空、过大或不是普通文件");return nil;
    }
    int output=open(target.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(output<0){close(input);SPFail(error,@"无法保存共享音频");return nil;}
    CC_SHA256_CTX ctx;CC_SHA256_Init(&ctx);uint8_t buffer[65536];uint64_t count=0;BOOL ok=YES;
    while(YES) {
        ssize_t size=read(input,buffer,sizeof(buffer));if(size==0)break;if(size<0){ok=NO;break;}
        count+=(uint64_t)size;if(count>limit){ok=NO;break;}
        CC_SHA256_Update(&ctx,buffer,(CC_LONG)size);
        ssize_t offset=0;while(offset<size){ssize_t written=write(output,buffer+offset,(size_t)(size-offset));if(written<=0){ok=NO;break;}offset+=written;}if(!ok)break;
    }
    if(fstat(input,&after)!=0 || count!=(uint64_t)before.st_size || before.st_dev!=after.st_dev || before.st_ino!=after.st_ino || before.st_size!=after.st_size || before.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec || before.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec)ok=NO;
    if(fsync(output)!=0)ok=NO;close(output);close(input);
    if(!ok){[NSFileManager.defaultManager removeItemAtURL:target error:nil];SPFail(error,@"共享文件尚未完成或在接收时发生变化，请重新共享");return nil;}
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(digest,&ctx);NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];return hex;
}
#pragma clang diagnostic pop
static BOOL SPFraction(NSString *value,long long *numerator,long long *denominator) {
    if(![value isKindOfClass:NSString.class] || ![value hasSuffix:@"s"] || value.length>64)return NO;
    NSString *text=[value substringToIndex:value.length-1];NSArray *parts=[text componentsSeparatedByString:@"/"];if(parts.count<1 || parts.count>2)return NO;
    long long values[2]={0,1};NSCharacterSet *digits=[NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    for(NSUInteger i=0;i<parts.count;i++) {
        NSString *part=parts[i];if(i==0 && [part hasPrefix:@"+"])part=[part substringFromIndex:1];
        if(!part.length || [part rangeOfCharacterFromSet:digits.invertedSet].location!=NSNotFound)return NO;
        // Reject overflow explicitly; NSScanner's clamping is not a valid clock.
        errno=0;char *end=NULL;values[i]=strtoll(part.UTF8String,&end,10);
        if(errno==ERANGE || !end || *end || values[i]<=0)return NO;
    }
    if(values[1]>INT32_MAX)return NO;*numerator=values[0];*denominator=values[1];return YES;
}
static NSDictionary *SPProject(NSURL *URL,NSError **error) {
    NSData *raw=[NSData dataWithContentsOfURL:URL options:0 error:error];
    if(!raw || raw.length>SPMaxXMLBytes)return nil;
    NSString *text=[[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
    if(!text || [text rangeOfString:@"<!ENTITY" options:NSCaseInsensitiveSearch].location!=NSNotFound) {SPFail(error,@"共享的项目 XML 包含不支持的外部实体");return nil;}
    NSXMLDocument *document=[[NSXMLDocument alloc] initWithData:raw options:NSXMLNodeLoadExternalEntitiesNever error:error];
    if(document.DTD.systemID.length || document.DTD.publicID.length){SPFail(error,@"共享的项目 XML 包含不支持的外部 DTD");return nil;}
    if(![document.rootElement.name isEqual:@"fcpxml"]){SPFail(error,@"共享描述不是 FCPXML");return nil;}
    NSArray *projects=[document nodesForXPath:@"//project" error:nil];
    if(projects.count!=1){SPFail(error,@"请只共享一个完整项目，而不是片段或多个项目");return nil;}
    NSXMLElement *project=projects.firstObject;NSArray *sequences=[project elementsForName:@"sequence"];
    if(sequences.count!=1){SPFail(error,@"共享描述缺少完整项目时间线");return nil;}
    NSXMLElement *sequence=sequences.firstObject;NSString *uid=[project attributeForName:@"uid"].stringValue;
    NSString *name=[project attributeForName:@"name"].stringValue ?: @"未命名项目",*duration=[sequence attributeForName:@"duration"].stringValue;
    NSString *formatID=[sequence attributeForName:@"format"].stringValue;NSString *frame=nil;
    for(NSXMLElement *format in [document nodesForXPath:@"/fcpxml/resources/format" error:nil])if([[format attributeForName:@"id"].stringValue isEqual:formatID]){if(frame){SPFail(error,@"共享描述有重复的项目格式");return nil;}frame=[format attributeForName:@"frameDuration"].stringValue;}
    long long durationN=0,durationD=0,frameN=0,frameD=0;
    if(!uid.length || uid.length>1024 || !name.length || name.length>1024 || ![sequence elementsForName:@"spine"].count || !SPFraction(duration,&durationN,&durationD) || (__int128)durationN>(__int128)durationD*4*60*60 || !SPFraction(frame,&frameN,&frameD)){SPFail(error,@"共享项目的标识、时长或帧率无效");return nil;}
    BOOL supported=NO;
    for(NSNumber *rate in @[@24,@25,@30,@50,@60])if((__int128)frameN*rate.longLongValue==frameD)supported=YES;
    for(NSNumber *rate in @[@24000,@30000,@60000])if((__int128)frameN*rate.longLongValue==(__int128)1001*frameD)supported=YES;
    if(!supported){SPFail(error,@"暂不支持此项目帧率");return nil;}
    return @{@"projectUID":uid,@"projectName":name,@"duration":[duration substringToIndex:duration.length-1],@"frameDuration":[frame substringToIndex:frame.length-1]};
}

@interface SubPopShareReceiver ()
@property NSURL *bridgeURL;
@property NSURL *rawExportRootURL;
@property NSMutableDictionary<NSString *,NSMutableDictionary *> *assets;
@property NSMutableDictionary<NSString *,NSAppleEventDescriptor *> *metadata;
@property dispatch_queue_t queue;
@end
@implementation SubPopShareReceiver
- (instancetype)initWithBridgeURL:(NSURL *)bridgeURL {
    // AppGroup containers are protected app data. Returning an AppGroup URL to
    // FCP causes a SystemPolicyAppDataDetailed denial on current macOS. Only raw
    // handoff files live in this private temporary root; state/inbox stay private.
    NSURL *temporary=[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES].URLByResolvingSymlinksInPath;
    return [self initWithBridgeURL:bridgeURL exportRootURL:[temporary URLByAppendingPathComponent:@"com.chokamin.SubPop.ShareExports" isDirectory:YES]];
}
- (instancetype)initWithBridgeURL:(NSURL *)bridgeURL exportRootURL:(NSURL *)exportRootURL {
    if((self=[super init])){_bridgeURL=bridgeURL.URLByStandardizingPath;_rawExportRootURL=exportRootURL.URLByStandardizingPath;_assets=[NSMutableDictionary new];_metadata=[NSMutableDictionary new];_queue=dispatch_queue_create("com.chokamin.SubPop.share-receive",DISPATCH_QUEUE_SERIAL);}return self;
}
- (NSURL *)exportsURL {return [self.bridgeURL URLByAppendingPathComponent:@"share-exports" isDirectory:YES];}
- (NSURL *)assetURL:(NSString *)ID {return [[self exportsURL] URLByAppendingPathComponent:ID isDirectory:YES];}
- (NSURL *)exportURL:(NSString *)ID {return [[self.rawExportRootURL URLByAppendingPathComponent:ID isDirectory:YES] URLByAppendingPathComponent:@"export" isDirectory:YES];}
- (BOOL)validateExportDirectory:(NSString *)ID create:(BOOL)create error:(NSError **)error {
    NSURL *transaction=[self.rawExportRootURL URLByAppendingPathComponent:ID isDirectory:YES];
    return SPPrivateDirectory(self.rawExportRootURL.URLByDeletingLastPathComponent,NO,error) && SPPrivateDirectory(self.rawExportRootURL,create,error) && SPPrivateDirectory(transaction,create,error) && SPPrivateDirectory([self exportURL:ID],create,error);
}
- (void)removeCompletedExport:(NSString *)ID {
    // Revalidate before cleanup as well: a replaced ancestor must not redirect
    // deletion outside this receiver's private staging area.
    if([self validateExportDirectory:ID create:NO error:nil])[NSFileManager.defaultManager removeItemAtURL:[self exportURL:ID] error:nil];
}
- (NSURL *)stateURL:(NSString *)ID {return [[self assetURL:ID] URLByAppendingPathComponent:@"asset.json"];}
- (NSMutableDictionary *)asset:(NSString *)ID {
    if(!SPUUID(ID))return nil;
    if(self.assets[ID])return self.assets[ID];
    NSDictionary *saved=SPJSON([self stateURL:ID]);
    if(![saved[@"shareID"] isEqual:ID] || ![saved[@"name"] isKindOfClass:NSString.class] || ![saved[@"state"] isKindOfClass:NSString.class] || ![saved[@"createdAt"] isKindOfClass:NSNumber.class] || ![saved[@"exportRoot"] isEqual:self.rawExportRootURL.path])return nil;
    NSMutableDictionary *asset=saved.mutableCopy;
    // A crash never auto-finishes a transaction. A repeated completion event
    // may retry its own unfinished staging data after this process restarts.
    if([asset[@"state"] isEqual:@"receiving"])asset[@"state"]=@"pending";
    self.assets[ID]=asset;return asset;
}
- (void)registerAppleEventHandlers {
    [NSAppleEventManager.sharedAppleEventManager setEventHandler:self andSelector:@selector(createAsset:reply:) forEventClass:'core' andEventID:'crel'];
    [NSAppleEventManager.sharedAppleEventManager setEventHandler:self andSelector:@selector(getAssetProperty:reply:) forEventClass:'core' andEventID:'getd'];
}
- (void)createAsset:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply {
    @synchronized(self) {
        if([event paramDescriptorForKeyword:'kocl'].typeCodeValue!='aset'){SPReplyError(reply,@"SubPop 只接收 FCP 音频共享");return;}
        NSError *error=nil;
        if(!SPDirectory(self.bridgeURL,YES,&error) || !SPDirectory(self.exportsURL,YES,&error)){SPReplyError(reply,error.localizedDescription);return;}
        // Bound outstanding placeholders (cancelled exports receive no callback).
        NSUInteger pending=0;for(NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.exportsURL.path error:nil]) {
            if(!SPUUID(entry))continue;NSDictionary *asset=[self asset:entry];
            if([@[@"pending",@"receiving"] containsObject:asset[@"state"] ?: @""] && NSDate.date.timeIntervalSince1970-[asset[@"createdAt"] doubleValue]<86400)pending++;
        }
        if(pending>=32){SPReplyError(reply,@"待接收的共享过多，请完成或取消已有共享后重试");return;}
        NSString *ID=NSUUID.UUID.UUIDString;NSAppleEventDescriptor *properties=[event paramDescriptorForKeyword:'prdt'];
        NSString *name=[properties descriptorForKeyword:'pnam'].stringValue;
        if(!name.length || [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>180 || [name hasPrefix:@"."] || [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\n\r\0"]].location!=NSNotFound)name=[@"SubPop-" stringByAppendingString:ID];
        NSMutableDictionary *asset=[@{@"protocol":@1,@"shareID":ID,@"name":name,@"state":@"pending",@"createdAt":@(NSDate.date.timeIntervalSince1970),@"exportRoot":self.rawExportRootURL.path} mutableCopy];
        NSString *version=SPDescriptionVersion([properties descriptorForKeyword:'dopt']);if(version)asset[@"descriptionVersion"]=version;
        if(![self validateExportDirectory:ID create:YES error:&error] || !SPDirectory([self assetURL:ID],YES,&error) || !SPWriteJSON(asset,[self stateURL:ID],&error)){SPReplyError(reply,error.localizedDescription);return;}
        self.assets[ID]=asset;NSAppleEventDescriptor *metadata=[properties descriptorForKeyword:'meta'];if(metadata)self.metadata[ID]=metadata;
        [reply setParamDescriptor:SPAssetSpecifier(ID) forKeyword:'----'];
    }
}
- (void)getAssetProperty:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply {
    @synchronized(self) {
        NSAppleEventDescriptor *object=[event paramDescriptorForKeyword:'----'];
        if([object descriptorForKeyword:'want'].typeCodeValue!='prop' || [object descriptorForKeyword:'form'].enumCodeValue!='prop'){SPReplyError(reply,@"不支持的共享属性请求");return;}
        NSAppleEventDescriptor *container=[object descriptorForKeyword:'from'];NSString *ID=[container descriptorForKeyword:'seld'].stringValue;
        NSMutableDictionary *asset=[self asset:ID];
        if([container descriptorForKeyword:'want'].typeCodeValue!='aset' || [container descriptorForKeyword:'form'].enumCodeValue!='ID  ' || !asset || ![@[@"pending",@"receiving"] containsObject:asset[@"state"]]){SPReplyError(reply,@"共享已结束或不存在，请重新共享");return;}
        OSType property=[object descriptorForKeyword:'seld'].typeCodeValue;NSAppleEventDescriptor *value=nil;
        if(property=='ID  ')value=[NSAppleEventDescriptor descriptorWithString:ID];
        else if(property=='pnam')value=[NSAppleEventDescriptor descriptorWithString:asset[@"name"]];
        else if(property=='locn') {
            NSError *error=nil;if(![self validateExportDirectory:ID create:NO error:&error]){SPReplyError(reply,error.localizedDescription);return;}
            value=NSAppleEventDescriptor.recordDescriptor;
            [value setDescriptor:[NSAppleEventDescriptor descriptorWithFileURL:[self exportURL:ID]] forKeyword:'asfd'];
            [value setDescriptor:[NSAppleEventDescriptor descriptorWithString:asset[@"name"]] forKeyword:'asbn'];
            [value setDescriptor:[NSAppleEventDescriptor descriptorWithBoolean:YES] forKeyword:'ashm'];
            [value setDescriptor:[NSAppleEventDescriptor descriptorWithBoolean:YES] forKeyword:'ashd'];
        } else if(property=='lbry') {
            value=NSAppleEventDescriptor.recordDescriptor;
            [value setDescriptor:[NSAppleEventDescriptor descriptorWithBoolean:NO] forKeyword:'lbha'];
            [value setDescriptor:[NSAppleEventDescriptor descriptorWithBoolean:NO] forKeyword:'lbhd'];
        } else if(property=='meta')value=self.metadata[ID] ?: SPUserRecord(@{});
        else if(property=='dopt')value=SPUserRecord(asset[@"descriptionVersion"] ? @{@"descriptionVersion":asset[@"descriptionVersion"]} : @{});
        if(!value){SPReplyError(reply,@"不支持的共享属性");return;}[reply setParamDescriptor:value forKeyword:'----'];
    }
}
- (NSString *)shareIDForURL:(NSURL *)URL {
    if(!URL.isFileURL || !SPSafePath(URL))return nil;
    NSArray *base=self.rawExportRootURL.path.pathComponents,*parts=URL.URLByStandardizingPath.path.pathComponents;
    if(parts.count<base.count+3 || ![[parts subarrayWithRange:NSMakeRange(0,base.count)] isEqual:base])return nil;
    NSString *ID=parts[base.count];return SPUUID(ID) && [parts[base.count+1] isEqual:@"export"] ? ID : nil;
}
- (NSDictionary *)publishShare:(NSString *)ID URLs:(NSArray<NSURL *> *)URLs error:(NSError **)error {
    NSDictionary *asset=nil;@synchronized(self){asset=[[self asset:ID] copy];}
    NSURL *folder=[self exportURL:ID];if(![self validateExportDirectory:ID create:NO error:error])return nil;
    NSMutableArray<NSURL *> *xmls=[NSMutableArray new],*audios=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
    NSSet *audioTypes=[NSSet setWithArray:@[@"wav",@"aif",@"aiff",@"m4a",@"caf"]];
    for(NSURL *receivedURL in URLs) {
        if(![[self shareIDForURL:receivedURL] isEqual:ID]){SPFail(error,@"共享结果不能混合不同项目的文件");return nil;}
        // Validate the original URL first so a real symlink is still rejected.
        // FCP returns physical /private/var paths while Foundation may provide
        // /var for the same existing file. Match the canonical form already
        // used by shareIDForURL before checking the direct parent directory.
        NSURL *URL=receivedURL.URLByStandardizingPath;
        if([seen containsObject:URL.path])continue;[seen addObject:URL.path];
        if(![URL.URLByDeletingLastPathComponent.path isEqual:folder.path]){SPFail(error,@"共享文件不在本次导出目录内");return nil;}
        NSString *extension=URL.pathExtension.lowercaseString,*stem=URL.lastPathComponent.stringByDeletingPathExtension;
        if(![stem isEqual:asset[@"name"]]){SPFail(error,@"请将音频合并为一个文件；暂不接收分角色或重命名的共享文件");return nil;}
        if([extension isEqual:@"fcpxml"])[xmls addObject:URL];
        else if([extension isEqual:@"fcpxmld"]) {
            if(!SPDirectory(URL,NO,error))return nil;[xmls addObject:[URL URLByAppendingPathComponent:@"Info.fcpxml"]];
        } else if([audioTypes containsObject:extension])[audios addObject:URL];
        else {SPFail(error,@"请使用「仅音频」共享，选择 WAV、AIFF、M4A 或 CAF");return nil;}
    }
    if(xmls.count!=1 || audios.count!=1){SPFail(error,@"需要同一次共享的一份完整项目 XML 和一份混合音频，请重新共享完整项目");return nil;}
    NSURL *inbox=[self.bridgeURL URLByAppendingPathComponent:@"share-inbox" isDirectory:YES];
    if(!SPDirectory(inbox,YES,error))return nil;
    NSURL *target=[inbox URLByAppendingPathComponent:ID isDirectory:YES];
    if([NSFileManager.defaultManager fileExistsAtPath:target.path]){SPFail(error,@"这次共享已接收，请勿重复导入");return nil;}
    NSURL *staging=[inbox URLByAppendingPathComponent:[NSString stringWithFormat:@".pending-%@-%@",ID,NSUUID.UUID.UUIDString] isDirectory:YES];
    if(!SPDirectory(staging,YES,error))return nil;
    NSString *audioName=[@"audio." stringByAppendingString:audios.firstObject.pathExtension.lowercaseString];
    NSURL *xml=[staging URLByAppendingPathComponent:@"input.fcpxml"];
    NSString *xmlHash=SPCopy(xmls.firstObject,xml,SPMaxXMLBytes,error);
    NSDictionary *project=xmlHash ? SPProject(xml,error) : nil;
    NSString *audioHash=project ? SPCopy(audios.firstObject,[staging URLByAppendingPathComponent:audioName],SPMaxAudioBytes,error) : nil;
    if(!audioHash){[NSFileManager.defaultManager removeItemAtURL:staging error:nil];return nil;}
    NSMutableDictionary *manifest=[project mutableCopy];[manifest addEntriesFromDictionary:@{@"protocol":@1,@"shareID":ID,@"createdAt":asset[@"createdAt"],@"receivedAt":@(NSDate.date.timeIntervalSince1970),@"xmlFile":@"input.fcpxml",@"audioFile":audioName,@"xmlSHA256":xmlHash,@"audioSHA256":audioHash,@"source":@"fcp-custom-share",@"status":@"ready"}];
    @synchronized(self) {
        NSMutableDictionary *current=[self asset:ID];
        if(![current[@"state"] isEqual:@"receiving"]){[NSFileManager.defaultManager removeItemAtURL:staging error:nil];SPFail(error,@"共享已取消，请重新共享");return nil;}
        if(!SPWriteJSON(manifest,[staging URLByAppendingPathComponent:@"ready.json"],error) || ![NSFileManager.defaultManager moveItemAtURL:staging toURL:target error:error]){[NSFileManager.defaultManager removeItemAtURL:staging error:nil];return nil;}
        current[@"state"]=@"ready";
        if(!SPWriteJSON(current,[self stateURL:ID],error)) {
            // Without a terminal marker restart could accidentally republish it.
            [NSFileManager.defaultManager removeItemAtURL:target error:nil];return nil;
        }
    }
    // The canonical inbox now owns both files. Remove only this receiver's raw
    // export directory, never any caller-selected source or project media.
    [self removeCompletedExport:ID];return manifest;
}
- (BOOL)handleOpenURLs:(NSArray<NSURL *> *)URLs completion:(void (^)(NSDictionary *,NSError *))completion {
    NSMutableDictionary<NSString *,NSMutableArray<NSURL *> *> *groups=[NSMutableDictionary new];
    for(NSURL *URL in URLs){NSString *ID=[self shareIDForURL:URL];if(!ID)continue;if(!groups[ID])groups[ID]=[NSMutableArray new];[groups[ID] addObject:URL];}
    if(!groups.count)return NO;
    for(NSString *ID in groups) {
        @synchronized(self) {
            NSMutableDictionary *asset=[self asset:ID];
            if(!asset)continue;
            if(![asset[@"state"] isEqual:@"pending"]) {
                // This is a completion callback, so FCP has finished writing.
                // Cancel alone never removes a directory an exporter may use.
                if([@[@"cancelled",@"expired",@"failed",@"ready"] containsObject:asset[@"state"]]) {
                    [self removeCompletedExport:ID];[self.metadata removeObjectForKey:ID];
                }
                continue; // duplicate and terminal events cannot publish again
            }
            if(NSDate.date.timeIntervalSince1970-[asset[@"createdAt"] doubleValue]>86400) {
                asset[@"state"]=@"expired";SPWriteJSON(asset,[self stateURL:ID],nil);
                [self removeCompletedExport:ID];[self.metadata removeObjectForKey:ID];
                dispatch_async(dispatch_get_main_queue(),^{completion(nil,SPError(@"这次共享已过期，请重新共享完整项目"));});continue;
            }
            asset[@"state"]=@"receiving";NSError *error=nil;
            if(!SPWriteJSON(asset,[self stateURL:ID],&error)){asset[@"state"]=@"failed";dispatch_async(dispatch_get_main_queue(),^{completion(nil,error);});continue;}
        }
        NSArray *files=[groups[ID] copy];
        dispatch_async(self.queue,^{
            NSError *error=nil;NSDictionary *manifest=[self publishShare:ID URLs:files error:&error];
            @synchronized(self) {
                NSMutableDictionary *asset=[self asset:ID];
                if(!manifest && [asset[@"state"] isEqual:@"receiving"]){asset[@"state"]=@"failed";SPWriteJSON(asset,[self stateURL:ID],nil);}
                // Open Document is FCP's completion notification. Failure here
                // is terminal and only this asset's raw output is discarded.
                [self removeCompletedExport:ID];[self.metadata removeObjectForKey:ID];
            }
            dispatch_async(dispatch_get_main_queue(),^{completion(manifest,error ?: (manifest ? nil : SPError(@"共享接收失败，请重新共享完整项目")));});
        });
    }
    return YES;
}
- (BOOL)cancelShareID:(NSString *)shareID error:(NSError **)error {
    @synchronized(self) {
        NSMutableDictionary *asset=[self asset:shareID];if(!asset)return SPFail(error,@"共享不存在");
        if([asset[@"state"] isEqual:@"ready"])return SPFail(error,@"音频已接收，请在 SubPop 中移除待接收项目");
        asset[@"state"]=@"cancelled";return SPWriteJSON(asset,[self stateURL:shareID],error);
    }
}
@end
