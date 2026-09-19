#import <Cocoa/Cocoa.h>
#import "TitleTemplates.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const SubPopTap5aFolder=@"Tap5a Autosize Text Background";
static NSError *SubPopTap5aInstallError(NSString *message) {
    return [NSError errorWithDomain:@"SubPop.Tap5aInstall" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSURL *SubPopTap5aInstallDirectory(NSURL *movies) {
    return [movies URLByAppendingPathComponent:@"Motion Templates.localized/Titles.localized/Tap5a"];
}
// A pinned author archive is checked before extraction. Never merge into an existing template.
static NSURL *SubPopInstallTap5aArchive(NSData *data, NSURL *movies, NSError **error) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (data.length!=37428) {if(error)*error=SubPopTap5aInstallError(@"模板下载不完整，请重试。");return nil;}
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *sha=[NSMutableString new];
    for(NSUInteger i=0;i<sizeof(digest);i++)[sha appendFormat:@"%02x",digest[i]];
    if (![sha isEqual:@"9b08f4c091af396657e9b976274030e3fa0a8e807c76e5a641beef8188045308"]) {if(error)*error=SubPopTap5aInstallError(@"模板校验未通过，未安装任何文件。请重试或从作者页面手动下载。");return nil;}
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *parent=SubPopTap5aInstallDirectory(movies),*destination=[parent URLByAppendingPathComponent:SubPopTap5aFolder];
    NSURL *title=[destination URLByAppendingPathComponent:[SubPopTap5aFolder stringByAppendingPathExtension:@"moti"]];
    if ([fm fileExistsAtPath:destination.path]) {
        if(SubPopValidTap5a(title))return title;
        if(error)*error=SubPopTap5aInstallError(@"安装位置已有同名文件夹，已保留原文件。请检查现有模板，或选择已安装的模板。");return nil;
    }
    // Preserve a pre-existing nonlocalized template tree instead of silently creating a second one.
    NSURL *plainMotion=[movies URLByAppendingPathComponent:@"Motion Templates"];
    if ([fm fileExistsAtPath:plainMotion.path] && ![fm fileExistsAtPath:[movies URLByAppendingPathComponent:@"Motion Templates.localized"].path]) {
        if(error)*error=SubPopTap5aInstallError(@"已有 Motion Templates 目录未使用 .localized 后缀。请按 README 的手动安装说明处理，现有目录未修改。");return nil;
    }
    NSURL *plainTitles=[movies URLByAppendingPathComponent:@"Motion Templates.localized/Titles"];
    if ([fm fileExistsAtPath:plainTitles.path] && ![fm fileExistsAtPath:[movies URLByAppendingPathComponent:@"Motion Templates.localized/Titles.localized"].path]) {
        if(error)*error=SubPopTap5aInstallError(@"已有 Titles 目录未使用 .localized 后缀。请按 README 的手动安装说明处理，现有目录未修改。");return nil;
    }
    if(![fm createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:error])return nil;
    NSURL *stage=[parent URLByAppendingPathComponent:[@".subpop-install-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if(![fm createDirectoryAtURL:stage withIntermediateDirectories:NO attributes:nil error:error])return nil;
    NSURL *result=nil;
    @try {
        NSURL *archive=[stage URLByAppendingPathComponent:@"template.zip"];
        if(![data writeToURL:archive options:NSDataWritingAtomic error:error])return nil;
        NSTask *extract=[NSTask new];extract.executableURL=[NSURL fileURLWithPath:@"/usr/bin/ditto"];
        extract.arguments=@[@"-x",@"-k",archive.path,stage.path];
        extract.standardOutput=NSFileHandle.fileHandleWithNullDevice;extract.standardError=NSFileHandle.fileHandleWithNullDevice;
        if(![extract launchAndReturnError:error])return nil;[extract waitUntilExit];
        NSURL *folder=[stage URLByAppendingPathComponent:SubPopTap5aFolder];
        NSURL *stagedTitle=[folder URLByAppendingPathComponent:[SubPopTap5aFolder stringByAppendingPathExtension:@"moti"]];
        if(extract.terminationStatus || !SubPopValidTap5a(stagedTitle)) {if(error)*error=SubPopTap5aInstallError(@"模板解压或兼容性检查失败，未替换现有模板。");return nil;}
        NSURL *readme=[stage URLByAppendingPathComponent:@"Tap5a Autosize Text Background Readme.txt"];
        if(![fm copyItemAtURL:readme toURL:[folder URLByAppendingPathComponent:readme.lastPathComponent] error:error])return nil;
        if(![fm moveItemAtURL:folder toURL:destination error:error])return nil;
        result=title;
    } @finally { [fm removeItemAtURL:stage error:nil]; }
    return result;
}

@interface SubPopTap5aInstaller : NSObject
@property NSURLSession *session;
@property NSURL *movies;
@property BOOL scoped;
@property (atomic) BOOL cancelled;
@property (copy) void (^completion)(NSURL *,NSError *);
- (void)startAtMovies:(NSURL *)movies completion:(void (^)(NSURL *,NSError *))completion;
- (void)cancel;
@end
@implementation SubPopTap5aInstaller
- (void)cancel { self.cancelled=YES;[self.session invalidateAndCancel]; }
- (void)finish:(NSURL *)url error:(NSError *)error {
    [self.session finishTasksAndInvalidate];self.session=nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.completion)self.completion(url,error);self.completion=nil;
        if(self.scoped)[self.movies stopAccessingSecurityScopedResource];self.scoped=NO;
    });
}
- (void)startAtMovies:(NSURL *)movies completion:(void (^)(NSURL *,NSError *))completion {
    self.movies=movies;self.completion=completion;self.scoped=[movies startAccessingSecurityScopedResource];
    NSURL *existing=[[SubPopTap5aInstallDirectory(movies) URLByAppendingPathComponent:SubPopTap5aFolder] URLByAppendingPathComponent:[SubPopTap5aFolder stringByAppendingPathExtension:@"moti"]];
    if(SubPopValidTap5a(existing)){[self finish:existing error:nil];return;}
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=30;
    self.session=[NSURLSession sessionWithConfiguration:config];[self downloadSource:0];
}
- (void)downloadSource:(NSUInteger)index {
    if(self.cancelled){[self finish:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];return;}
    NSArray *sources=@[@"https://raw.githubusercontent.com/tap5a/free-final-cut-pro-x-plugins/ac76d8a36a8877984aac15659a2bcc1ee8fd614f/Tap5a_Autosize_Text_Background.zip",@"https://github.com/tap5a/free-final-cut-pro-x-plugins/raw/ac76d8a36a8877984aac15659a2bcc1ee8fd614f/Tap5a_Autosize_Text_Background.zip"];
    NSURLSessionDataTask *task=[self.session dataTaskWithURL:[NSURL URLWithString:sources[index]] completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        if(self.cancelled){[self finish:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];return;}
        if(error || ![response isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)response).statusCode!=200){
            if(index+1<sources.count){[self downloadSource:index+1];return;}
            [self finish:nil error:SubPopTap5aInstallError(@"暂时无法连接 Tap5a 作者下载源。请稍后重试，或选择已手动安装的模板。")];return;
        }
        // Cancellation stops downloading. Once the verified archive is being installed,
        // always report its actual outcome, including a completed installation.
        NSError *installError=nil;NSURL *title=SubPopInstallTap5aArchive(data,self.movies,&installError);
        [self finish:title error:installError];
    }];[task resume];
}
@end
