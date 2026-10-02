#import "ChineseConversion.h"
#include <opencc.h>

@interface SubPopChineseEngine : NSObject
@property opencc_t converter;
@end

@implementation SubPopChineseEngine
- (void)dealloc {
    if (_converter && _converter != (opencc_t)-1) opencc_close(_converter);
}
@end

static NSString *const SubPopChineseErrorDomain = @"com.chokamin.SubPop.ChineseConversion";

static NSString *SubPopChineseFailure(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SubPopChineseErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: message}];
    return nil;
}

static NSURL *SubPopChineseResourceDirectory(void) {
    NSBundle *bundle = [NSBundle bundleForClass:SubPopChineseEngine.class];
    NSURL *resources = [bundle.resourceURL URLByAppendingPathComponent:@"OpenCC" isDirectory:YES];
    BOOL directory = NO;
    if (resources && [NSFileManager.defaultManager fileExistsAtPath:resources.path isDirectory:&directory] && directory) return resources;
    // Command-line verification binaries share executable-adjacent resources.
    // App/extension builds must use their own signed bundle resources, never a
    // Homebrew install, working directory, or absolute developer path.
    NSString *extension = bundle.bundleURL.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"app"] || [extension isEqualToString:@"appex"]) return nil;
    NSString *executable = NSProcessInfo.processInfo.arguments.firstObject;
    if (!executable.isAbsolutePath) executable = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:executable];
    return [[NSURL fileURLWithPath:executable].URLByDeletingLastPathComponent URLByAppendingPathComponent:@"OpenCC" isDirectory:YES];
}

NSString *SubPopChineseConvert(NSString *text, SubPopChineseTextMode mode, NSError **error) {
    if (error) *error = nil;
    if (![text isKindOfClass:NSString.class]) return SubPopChineseFailure(error, 1, @"字幕文字无效。");
    if (mode != SubPopChineseTextKeep && mode != SubPopChineseTextSimplified && mode != SubPopChineseTextTraditional)
        return SubPopChineseFailure(error, 2, @"简繁转换选项无效。");
    if (mode == SubPopChineseTextKeep || text.length == 0) return text;
    // OpenCC's diagnostic string is global. Serializing converter creation and
    // use avoids races and also lets the two dictionary engines be reused.
    @synchronized (SubPopChineseEngine.class) {
        static NSMutableDictionary<NSString *, SubPopChineseEngine *> *engines;
        if (!engines) engines = [NSMutableDictionary dictionary];
        NSURL *directory = SubPopChineseResourceDirectory();
        NSString *config = mode == SubPopChineseTextSimplified ? @"t2s.json" : @"s2t.json";
        NSURL *configURL = [directory URLByAppendingPathComponent:config];
        if (!configURL || ![NSFileManager.defaultManager fileExistsAtPath:configURL.path])
            return SubPopChineseFailure(error, 3, @"简繁转换词典缺失，请重新安装 SubPop。");
        NSArray<NSString *> *dictionaries = mode == SubPopChineseTextSimplified
            ? @[@"CJK_Compatibility_Ideographs.ocd2", @"TSPhrases.ocd2", @"TSCharactersExt.ocd2", @"TSCharacters.ocd2"]
            : @[@"CJK_Compatibility_Ideographs.ocd2", @"STPhrases.ocd2", @"STPhrases_GeneratedFromRegionalPhrases.ocd2", @"STCharacters.ocd2"];
        for (NSString *name in dictionaries) {
            NSURL *dictionary = [directory URLByAppendingPathComponent:name];
            // All dependencies must live beside the bundle's configuration.
            // In particular, missing bundle data cannot trigger OpenCC's
            // compiled install-prefix/system-path dictionary fallback.
            if (![NSFileManager.defaultManager fileExistsAtPath:dictionary.path])
                return SubPopChineseFailure(error, 3, @"简繁转换词典缺失，请重新安装 SubPop。");
        }
        SubPopChineseEngine *engine = engines[configURL.path];
        if (!engine) {
            engine = [SubPopChineseEngine new];
            engine.converter = opencc_open(configURL.fileSystemRepresentation);
            if (engine.converter == (opencc_t)-1)
                return SubPopChineseFailure(error, 4, @"简繁转换词典无法读取，请重新安装 SubPop。");
            engines[configURL.path] = engine;
        }
        // Preserve embedded NULs too: the C API returns a terminated UTF-8
        // buffer, so convert its text pieces separately and rejoin losslessly.
        NSString *nul = [NSString stringWithCharacters:(const unichar[]){0} length:1];
        NSArray<NSString *> *pieces = [text componentsSeparatedByString:nul];
        NSMutableArray<NSString *> *converted = [NSMutableArray arrayWithCapacity:pieces.count];
        for (NSString *piece in pieces) {
            NSData *input = [piece dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
            if (!input) return SubPopChineseFailure(error, 5, @"字幕文字无法转换为 UTF-8。");
            if (!input.length) { [converted addObject:piece]; continue; }
            char *output = opencc_convert_utf8(engine.converter, input.bytes, input.length);
            if (!output) return SubPopChineseFailure(error, 6, @"简繁转换失败，原始字幕已保留。");
            NSString *value = [[NSString alloc] initWithUTF8String:output];
            opencc_convert_utf8_free(output);
            if (!value) return SubPopChineseFailure(error, 7, @"简繁转换结果无效，原始字幕已保留。");
            [converted addObject:value];
        }
        return [converted componentsJoinedByString:nul];
    }
}
