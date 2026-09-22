#pragma once
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const SubPopDefaultUpdateMirror=@"https://gh-proxy.org/";
static NSError *SubPopUpdateError(NSString *message) {
    return [NSError errorWithDomain:@"SubPop.Updates" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL SubPopUpdateMatches(NSString *value, NSString *pattern) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match=[regex firstMatchInString:value options:0 range:NSMakeRange(0,value.length)];
    return match && NSEqualRanges(match.range,NSMakeRange(0,value.length));
}
static NSString *SubPopUpdateMirror(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithString:[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    if (![parts.scheme.lowercaseString isEqual:@"https"] || !SubPopUpdateMatches(parts.host,@"[A-Za-z0-9.-]+") || parts.user || parts.password || parts.query || parts.fragment || (parts.port && parts.port.integerValue!=443)) return nil;
    if (parts.path.length && (!SubPopUpdateMatches(parts.path,@"/[A-Za-z0-9_/-]*") || [parts.path containsString:@"//"])) return nil;
    parts.scheme=@"https";parts.host=parts.host.lowercaseString;
    if (![parts.path hasSuffix:@"/"]) parts.path=[parts.path stringByAppendingString:@"/"];
    return parts.URL.absoluteString;
}
static NSArray<NSURL *> *SubPopUpdateSources(NSURL *origin, NSString *mirror, NSInteger mode) {
    NSString *base=SubPopUpdateMirror(mirror);
    if (mode==1 || !base) return @[origin];
    NSURL *proxy=[NSURL URLWithString:[base stringByAppendingString:origin.absoluteString]];
    return mode==2 ? @[proxy,origin] : @[origin,proxy];
}
static NSDictionary *SubPopReleaseUpdate(NSDictionary *release, NSString *current, NSString *repository) {
    if (![release isKindOfClass:NSDictionary.class] || !SubPopUpdateMatches(repository,@"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")) return nil;
    for (NSString *key in @[@"draft",@"prerelease"]) {
        id flag=release[key];if (flag && (![flag isKindOfClass:NSNumber.class] || [flag boolValue])) return nil;
    }
    NSString *tag=release[@"tag_name"];
    if (!SubPopUpdateMatches(tag,@"v?[0-9]+\\.[0-9]+\\.[0-9]+(?:\\.[0-9]+)?")) return nil;
    NSString *version=[tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
    NSString *name=[NSString stringWithFormat:@"SubPop-%@-arm64.pkg",version];
    NSString *url=[NSString stringWithFormat:@"https://github.com/%@/releases/download/%@/%@",repository,tag,name];
    NSDictionary *installer=nil;
    id assets=release[@"assets"];
    if (assets && ![assets isKindOfClass:NSArray.class]) return nil;
    for (id asset in assets) {
        if (![asset isKindOfClass:NSDictionary.class] || ![asset[@"name"] isEqual:name] || ![asset[@"state"] isEqual:@"uploaded"] || ![asset[@"size"] isKindOfClass:NSNumber.class]) continue;
        long long size=[asset[@"size"] longLongValue];NSString *digest=asset[@"digest"];
        if (size<=0 || size>2LL*1024*1024*1024 || !SubPopUpdateMatches(digest,@"sha256:[a-fA-F0-9]{64}")) continue;
        // Never trust a release response (including a proxy response) to choose a host or repository.
        if (![asset[@"browser_download_url"] isEqual:url]) continue;
        installer=@{@"name":name,@"version":version,@"url":url,@"size":@(size),@"sha256":[[digest substringFromIndex:7] lowercaseString]};break;
    }
    return @{@"version":version,@"newer":@([version compare:current options:NSNumericSearch]==NSOrderedDescending),@"older":@([version compare:current options:NSNumericSearch]==NSOrderedAscending),@"installer":@(installer!=nil),@"asset":installer ?: @{},@"url":[NSString stringWithFormat:@"https://github.com/%@/releases/tag/%@",repository,tag]};
}
static BOOL SubPopUpdateTrustedInstallerOutput(NSString *output) {
    NSRegularExpression *status=[NSRegularExpression regularExpressionWithPattern:@"^ +Status: signed by a developer certificate issued by Apple for distribution\\r?$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    if(![status firstMatchInString:output options:0 range:NSMakeRange(0,output.length)])return NO;
    // Only the leaf certificate identifies the publisher. A filename or another chain entry cannot satisfy this.
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^ +1\\. Developer ID Installer: [^\\r\\n]+ \\(925BTJVFFZ\\)\\r?$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    return [pattern firstMatchInString:output options:0 range:NSMakeRange(0,output.length)]!=nil;
}
static BOOL SubPopUpdatePackageInfoMatches(NSData *data, NSString *version) {
    if(!data.length || data.length>1024*1024 || !version.length)return NO;
    NSXMLDocument *document=[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
    NSXMLElement *root=document.rootElement;
    return [root.name isEqual:@"pkg-info"] && [[root attributeForName:@"identifier"].stringValue isEqual:@"com.chokamin.SubPop.installer"] && [[root attributeForName:@"version"].stringValue isEqual:version];
}
static BOOL SubPopVerifyUpdatePackage(NSURL *url, NSDictionary *asset, NSError **error) {
    NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;
    if (data.length!=[asset[@"size"] unsignedLongLongValue] || data.length>2ULL*1024*1024*1024) {if(error)*error=SubPopUpdateError(@"安装包大小不符，请重新下载。");return NO;}
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *sha=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[sha appendFormat:@"%02x",digest[i]];
    if (![sha isEqual:asset[@"sha256"]]) {if(error)*error=SubPopUpdateError(@"安装包校验未通过，请重新下载。");return NO;}
    // A checksum supplied by a mirror cannot authenticate that mirror. Verify Apple's
    // package signature AND our pinned publisher before offering the file to the user.
    NSTask *verify=[NSTask new];verify.executableURL=[NSURL fileURLWithPath:@"/usr/sbin/pkgutil"];
    verify.arguments=@[@"--check-signature",url.path];verify.environment=@{@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin",@"LC_ALL":@"C",@"LANG":@"C"};
    NSPipe *pipe=[NSPipe pipe];verify.standardOutput=pipe;verify.standardError=NSFileHandle.fileHandleWithNullDevice;
    if (![verify launchAndReturnError:error]) return NO;
    NSData *result=[pipe.fileHandleForReading readDataToEndOfFile];[verify waitUntilExit];
    NSString *output=[[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding] ?: @"";
    if (verify.terminationStatus || !SubPopUpdateTrustedInstallerOutput(output)) {if(error)*error=SubPopUpdateError(@"无法验证 SubPop 开发者签名，未保存安装包。请使用 GitHub 发布页中的安装包。");return NO;}
    // Check signed package metadata as well: a proxy must not relabel an older release
    // or another product from the same publisher as the requested SubPop version.
    NSURL *scratch=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"SubPop-package-info-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:scratch withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;
    BOOL matches=NO;
    @try {
        NSTask *extract=[NSTask new];extract.executableURL=[NSURL fileURLWithPath:@"/usr/bin/xar"];
        extract.arguments=@[@"-xf",url.path,@"-C",scratch.path,@"SubPop-component.pkg/PackageInfo"];
        extract.standardOutput=NSFileHandle.fileHandleWithNullDevice;extract.standardError=NSFileHandle.fileHandleWithNullDevice;
        if([extract launchAndReturnError:error]) {
            [extract waitUntilExit];
            matches=!extract.terminationStatus && SubPopUpdatePackageInfoMatches([NSData dataWithContentsOfURL:[scratch URLByAppendingPathComponent:@"SubPop-component.pkg/PackageInfo"]],asset[@"version"]);
        }
    } @finally { [fm removeItemAtURL:scratch error:nil]; }
    if(!matches && error)*error=SubPopUpdateError(@"安装包的产品或版本与更新信息不符，未保存安装包。");
    return matches;
}

// One cancellable operation, sequential sources, bounded data, no cookies or credentials.
// Callers own the returned temporary package directory and must remove it when finished.
@interface SubPopUpdateClient : NSObject <NSURLSessionDataDelegate>
@property NSURLSessionConfiguration *configuration;
@property NSURLSession *session;
@property NSURLSessionDataTask *task;
@property NSArray<NSURL *> *sources;
@property NSUInteger sourceIndex;
@property NSMutableData *metadata;
@property NSFileHandle *file;
@property NSURL *directory;
@property NSURL *package;
@property NSDictionary *asset;
@property NSString *repository;
@property NSString *current;
@property NSError *responseError;
@property long long received;
@property NSTimeInterval lastProgress;
@property (atomic) BOOL cancelled;
@property (copy) void (^progress)(NSString *,double);
@property (copy) void (^completion)(NSDictionary *,NSURL *,NSError *);
- (void)checkRepository:(NSString *)repository current:(NSString *)current mirror:(NSString *)mirror mode:(NSInteger)mode;
- (void)download:(NSDictionary *)asset mirror:(NSString *)mirror mode:(NSInteger)mode;
- (void)cancel;
@end
@implementation SubPopUpdateClient
- (NSString *)sourceName { return [self.sources[self.sourceIndex].host isEqual:@"api.github.com"] || [self.sources[self.sourceIndex].host isEqual:@"github.com"] ? @"GitHub" : [@"镜像 · " stringByAppendingString:self.sources[self.sourceIndex].host]; }
- (void)report:(NSString *)text fraction:(double)fraction {
    dispatch_async(dispatch_get_main_queue(), ^{if (!self.cancelled && self.progress) self.progress(text,fraction);});
}
- (void)prepareSession {
    NSURLSessionConfiguration *config=[self.configuration copy] ?: NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=self.asset ? 20 : 8;config.timeoutIntervalForResource=self.asset ? 1800 : 12;
    config.HTTPShouldSetCookies=NO;config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;config.URLCache=nil;
    NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;
    self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
    [self nextSource];
}
- (void)checkRepository:(NSString *)repository current:(NSString *)current mirror:(NSString *)mirror mode:(NSInteger)mode {
    self.repository=repository;self.current=current;
    if (!SubPopUpdateMatches(repository,@"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")) {[self finish:nil package:nil error:SubPopUpdateError(@"尚未配置更新仓库。")];return;}
    self.sources=SubPopUpdateSources([NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest",repository]],mirror,mode);[self prepareSession];
}
- (void)download:(NSDictionary *)asset mirror:(NSString *)mirror mode:(NSInteger)mode {
    self.asset=asset;self.sources=SubPopUpdateSources([NSURL URLWithString:asset[@"url"]],mirror,mode);[self prepareSession];
}
- (void)discardPackage {
    [self.file closeFile];self.file=nil;
    if(self.directory)[NSFileManager.defaultManager removeItemAtURL:self.directory error:nil];self.directory=nil;self.package=nil;
}
- (void)nextSource {
    if (self.cancelled) {[self finish:nil package:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];return;}
    [self discardPackage];self.metadata=[NSMutableData new];self.received=0;self.responseError=nil;self.lastProgress=0;
    if (self.asset) {
        self.directory=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"SubPop-update-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
        NSError *error=nil;
        if(![NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){[self finish:nil package:nil error:error];return;}
        self.package=[self.directory URLByAppendingPathComponent:self.asset[@"name"]];
        if(![NSFileManager.defaultManager createFileAtPath:self.package.path contents:nil attributes:@{NSFilePosixPermissions:@0600}]){[self finish:nil package:nil error:SubPopUpdateError(@"无法创建临时下载文件。")];return;}
        self.file=[NSFileHandle fileHandleForWritingToURL:self.package error:&error];if(!self.file){[self finish:nil package:nil error:error];return;}
    }
    [self report:[NSString stringWithFormat:@"%@%@%@",self.sourceIndex ? @"已切换备用通道，" : @"",self.asset ? @"正在下载 · " : @"正在连接 · ",self.sourceName] fraction:self.asset ? 0 : -1];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:self.sources[self.sourceIndex] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:self.asset ? 20 : 8];
    [request setValue:@"SubPop-Update-Check" forHTTPHeaderField:@"User-Agent"];
    [request setValue:self.asset ? @"application/octet-stream" : @"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    self.task=[self.session dataTaskWithRequest:request];[self.task resume];
}
- (void)finish:(NSDictionary *)release package:(NSURL *)package error:(NSError *)error {
    [self.file closeFile];self.file=nil;if(!package)[self discardPackage];
    [self.session finishTasksAndInvalidate];self.session=nil;self.task=nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *result=package;
        if(self.cancelled && result){[NSFileManager.defaultManager removeItemAtURL:result.URLByDeletingLastPathComponent error:nil];result=nil;}
        NSError *finalError=self.cancelled ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil] : error;
        if(self.completion)self.completion(release,result,finalError);self.completion=nil;self.progress=nil;
    });
}
- (void)cancel { self.cancelled=YES;[self.task cancel]; }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    NSString *host=request.URL.host.lowercaseString;
    BOOL allowed=[@[@"github.com",@"api.github.com",@"release-assets.githubusercontent.com",@"objects.githubusercontent.com"] containsObject:host];
    NSString *sourceHost=self.sources[self.sourceIndex].host.lowercaseString;
    allowed=allowed || [host isEqual:sourceHost] || (([sourceHost isEqual:@"gh-proxy.org"] || [sourceHost isEqual:@"gh-proxy.com"]) && [@[@"gh-proxy.org",@"gh-proxy.com"] containsObject:host]);
    completionHandler(allowed && [request.URL.scheme isEqual:@"https"] && !request.URL.user && !request.URL.password ? request : nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,NSURLCredential *))completionHandler {
    completionHandler([challenge.protectionSpace.authenticationMethod isEqual:NSURLAuthenticationMethodServerTrust] ? NSURLSessionAuthChallengePerformDefaultHandling : NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    long long limit=self.asset ? [self.asset[@"size"] longLongValue] : 1024*1024;
    if(status!=200 || response.expectedContentLength>limit) {
        self.responseError=SubPopUpdateError(status==404 ? @"尚未找到公开的正式安装包。" : @"更新来源暂时不可用。");completionHandler(NSURLSessionResponseCancel);return;
    }
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if(self.cancelled || self.responseError)return;
    long long limit=self.asset ? [self.asset[@"size"] longLongValue] : 1024*1024;
    self.received+=data.length;
    if(self.received>limit){self.responseError=SubPopUpdateError(@"下载内容大小异常。");[task cancel];return;}
    if(self.asset) {
        NSError *error=nil;if(![self.file writeData:data error:&error]){self.responseError=error;[task cancel];return;}
        NSTimeInterval now=NSDate.timeIntervalSinceReferenceDate;
        if(now-self.lastProgress>.15){self.lastProgress=now;double fraction=(double)self.received/limit;[self report:[NSString stringWithFormat:@"正在下载 · %@ · %.0f%%",self.sourceName,fraction*100] fraction:fraction];}
    } else [self.metadata appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [self.file closeFile];self.file=nil;
    if(self.cancelled){[self finish:nil package:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];return;}
    NSError *failure=self.responseError ?: error;NSDictionary *release=nil;
    if(!failure && self.asset) {
        [self report:@"正在校验安装包与开发者签名…" fraction:-1];
        if(SubPopVerifyUpdatePackage(self.package,self.asset,&failure)){[self finish:nil package:self.package error:nil];return;}
    } else if(!failure) {
        id json=[NSJSONSerialization JSONObjectWithData:self.metadata options:0 error:nil];release=SubPopReleaseUpdate(json,self.current,self.repository);
        if(release){NSMutableDictionary *result=[release mutableCopy];result[@"source"]=self.sourceName;[self finish:result package:nil error:nil];return;}
        failure=SubPopUpdateError(@"更新来源返回了无法识别的版本信息。");
    }
    if(self.sourceIndex+1<self.sources.count){self.sourceIndex++;[self nextSource];return;}
    [self finish:nil package:nil error:failure ?: SubPopUpdateError(@"暂时无法检查更新，请稍后重试。")];
}
@end
