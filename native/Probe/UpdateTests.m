#import "Updates.h"

static NSMutableArray<NSString *> *Visited;
static NSDictionary *Fixture;
static NSInteger Scenario;
@interface SubPopUpdateProtocol : NSURLProtocol @end
@implementation SubPopUpdateProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // Live fallback verification intercepts only the first source; the mirror uses real HTTPS.
    return Scenario!=9 || [@[@"api.github.com",@"github.com"] containsObject:request.URL.host];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    @synchronized(Visited){[Visited addObject:self.request.URL.host];}
    if(Scenario==9 || (Scenario==1 && [self.request.URL.host isEqual:@"api.github.com"])) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];return;
    }
    if(Scenario==5)return; // Remain pending until the caller cancels.
    NSInteger status=Scenario==3 ? 503 : 200;
    NSData *data=Scenario==2 ? [@"<html>mirror unavailable</html>" dataUsingEncoding:NSUTF8StringEncoding] : [NSJSONSerialization dataWithJSONObject:Fixture options:0 error:nil];
    if(Scenario==4)data=[NSMutableData dataWithLength:1024*1024+1];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
static BOOL WaitFor(BOOL (^done)(void), double seconds) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(!done() && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    return done();
}
static NSDictionary *Release(void) {
    return @{@"tag_name":@"v1.2.0",@"draft":@NO,@"prerelease":@NO,@"assets":@[@{@"name":@"SubPop-1.2.0-arm64.pkg",@"state":@"uploaded",@"size":@1024,@"digest":@"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",@"browser_download_url":@"https://github.com/Chokamin/SubPop/releases/download/v1.2.0/SubPop-1.2.0-arm64.pkg"}]};
}
static BOOL CheckScenario(NSInteger scenario, NSInteger mode, NSUInteger requests, BOOL success) {
    Scenario=scenario;Visited=[NSMutableArray new];Fixture=Release();
    SubPopUpdateClient *client=[SubPopUpdateClient new];client.configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;client.configuration.protocolClasses=@[SubPopUpdateProtocol.class];
    __block BOOL done=NO,valid=NO;
    client.completion=^(NSDictionary *release,NSURL *package,NSError *error){valid=success ? release!=nil && !error : !release && error!=nil;done=YES;};
    [client checkRepository:@"Chokamin/SubPop" current:@"1.1.0" mirror:SubPopDefaultUpdateMirror mode:mode];
    if(scenario==5)[client cancel];
    if(!WaitFor(^BOOL{return done;},4)){[client cancel];return NO;}
    return valid && (scenario==5 || Visited.count==requests);
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSDictionary *release=SubPopReleaseUpdate(Release(),@"1.1.0",@"Chokamin/SubPop");
        if(![release[@"installer"] boolValue] || ![release[@"newer"] boolValue])return 1;
        for(id value in @[[NSNull null],@[],@{@"tag_name":@[]},@{@"tag_name":@"v1.2.0",@"assets":@{}},@{@"tag_name":@"v1.2.0",@"draft":@[]},@{@"tag_name":@"v1.2.0\n"},@{@"tag_name":@"v1.2.0-beta"}])if(SubPopReleaseUpdate(value,@"1.1.0",@"Chokamin/SubPop"))return 2;
        for(NSString *mirror in @[@"http://proxy.test",@"https://user:password@proxy.test",@"https://proxy.test/?token=secret",@"https://proxy.test/#part",@"https://proxy.test/../",@"https://proxy.test:8080"] )if(SubPopUpdateMirror(mirror))return 3;
        if(![SubPopUpdateMirror(@" https://proxy.test/ghproxy ") isEqual:@"https://proxy.test/ghproxy/"])return 4;
        NSMutableDictionary *tampered=[Release() mutableCopy];NSMutableDictionary *asset=[tampered[@"assets"][0] mutableCopy];asset[@"browser_download_url"]=@"https://evil.test/SubPop.pkg";tampered[@"assets"]=@[asset];
        if([SubPopReleaseUpdate(tampered,@"1.1.0",@"Chokamin/SubPop")[@"installer"] boolValue])return 5;
        NSString *trusted=@"   Status: signed by a developer certificate issued by Apple for distribution\n";
        if(!SubPopUpdateTrustedInstallerOutput([trusted stringByAppendingString:@"    1. Developer ID Installer: JIAMIN ZHANG (925BTJVFFZ)\n"]) || SubPopUpdateTrustedInstallerOutput([trusted stringByAppendingString:@"Package: Developer ID Installer: JIAMIN ZHANG (925BTJVFFZ)\n    1. Developer ID Installer: Other (OTHERTEAM1)\n"]) || SubPopUpdateTrustedInstallerOutput([trusted stringByAppendingString:@"    2. Developer ID Installer: JIAMIN ZHANG (925BTJVFFZ)\n"]) || SubPopUpdateTrustedInstallerOutput(@"   Status: signed by a certificate that is not trusted\n    1. Developer ID Installer: JIAMIN ZHANG (925BTJVFFZ)\n"))return 6;
        NSData *packageInfo=[@"<pkg-info identifier='com.chokamin.SubPop.installer' version='1.2.0'/>" dataUsingEncoding:NSUTF8StringEncoding];
        if(!SubPopUpdatePackageInfoMatches(packageInfo,@"1.2.0") || SubPopUpdatePackageInfoMatches(packageInfo,@"1.3.0") || SubPopUpdatePackageInfoMatches([@"<pkg-info identifier='other.product' version='1.2.0'/>" dataUsingEncoding:NSUTF8StringEncoding],@"1.2.0"))return 7;
        for(NSArray *args in @[@[@0,@0,@1,@YES],@[@1,@0,@2,@YES],@[@1,@1,@1,@NO],@[@0,@2,@1,@YES],@[@2,@0,@2,@NO],@[@3,@0,@2,@NO],@[@4,@0,@2,@NO],@[@5,@0,@0,@NO]])if(!CheckScenario([args[0] integerValue],[args[1] integerValue],[args[2] unsignedIntegerValue],[args[3] boolValue])){NSLog(@"Scenario failed %@",args);return 10;}
        NSString *temporary=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".pkg"]];NSData *fake=[@"not a signed package" dataUsingEncoding:NSUTF8StringEncoding];[fake writeToFile:temporary atomically:YES];
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(fake.bytes,(CC_LONG)fake.length,digest);NSMutableString *sha=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[sha appendFormat:@"%02x",digest[i]];
        NSError *error=nil;BOOL accepted=SubPopVerifyUpdatePackage([NSURL fileURLWithPath:temporary],@{@"size":@(fake.length),@"sha256":sha},&error);[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];if(accepted || !error)return 11;
        puts("Updates: fallback, source selection, malformed responses, size limit, cancellation, URL and publisher validation passed.");
        if(argc==3 && !strcmp(argv[1],"--verify")) {
            NSData *data=[NSData dataWithContentsOfFile:@(argv[2]) options:NSDataReadingMappedIfSafe error:nil];if(!data)return 20;
            CC_SHA256(data.bytes,(CC_LONG)data.length,digest);sha=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[sha appendFormat:@"%02x",digest[i]];
            if(!SubPopVerifyUpdatePackage([NSURL fileURLWithPath:@(argv[2])],@{@"size":@(data.length),@"sha256":sha,@"version":@"1.1.0"},&error)){NSLog(@"Signature verification failed: %@",error.localizedDescription);return 21;}puts("Real published package: publisher signature and signed product/version passed.");
        }
        if(argc==2 && !strcmp(argv[1],"--live-fallback")) {
            Scenario=9;Visited=[NSMutableArray new];
            SubPopUpdateClient *checker=[SubPopUpdateClient new];checker.configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;checker.configuration.protocolClasses=@[SubPopUpdateProtocol.class];
            __block BOOL done=NO;__block NSDictionary *live=nil;
            checker.completion=^(NSDictionary *r,NSURL *package,NSError *e){live=r;if(e)NSLog(@"Live check: %@",e.localizedDescription);done=YES;};
            [checker checkRepository:@"Chokamin/SubPop" current:@"1.0.0" mirror:SubPopDefaultUpdateMirror mode:0];
            if(!WaitFor(^BOOL{return done;},30) || ![live[@"installer"] boolValue] || ![live[@"source"] hasPrefix:@"镜像"]){[checker cancel];return 30;}
            SubPopUpdateClient *downloader=[SubPopUpdateClient new];downloader.configuration=checker.configuration;done=NO;__block BOOL verified=NO;__block NSInteger last=-1;
            downloader.progress=^(NSString *text,double fraction){NSInteger bucket=(NSInteger)(fraction*10);if(bucket!=last){NSLog(@"%@",text);last=bucket;}};
            downloader.completion=^(NSDictionary *r,NSURL *package,NSError *e){verified=package!=nil && !e;if(e)NSLog(@"Live download: %@",e.localizedDescription);if(package)[NSFileManager.defaultManager removeItemAtURL:package.URLByDeletingLastPathComponent error:nil];done=YES;};
            [downloader download:live[@"asset"] mirror:SubPopDefaultUpdateMirror mode:0];
            if(!WaitFor(^BOOL{return done;},600) || !verified){[downloader cancel];return 31;}
            puts("Live HTTPS mirror: API + complete package download + SHA-256 + publisher signature passed after simulated original-source failure.");
        }
    }
    return 0;
}
