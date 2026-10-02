#import <Foundation/Foundation.h>

// The feedback destination is fixed. User text cannot choose a repository,
// attachment, label, or an additional URL query parameter.
static NSString *const SubPopFeedbackNewIssue= @"https://github.com/Chokamin/SubPop/issues/new";
static NSUInteger const SubPopFeedbackDescriptionLimit=1200;
static NSUInteger const SubPopFeedbackURLLimit=7600;

static BOOL SubPopFeedbackMatches(NSString *text,NSString *pattern) {
    return [text isKindOfClass:NSString.class] &&
        [[NSPredicate predicateWithFormat:@"SELF MATCHES %@",pattern] evaluateWithObject:text];
}
static NSString *SubPopFeedbackTrim(id value) {
    return [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
}
static BOOL SubPopFeedbackTextValid(NSString *text,NSUInteger limit) {
    if (![text isKindOfClass:NSString.class] || text.length>limit || ![text dataUsingEncoding:NSUTF8StringEncoding]) return NO;
    NSMutableCharacterSet *invalid=NSCharacterSet.controlCharacterSet.mutableCopy;
    [invalid removeCharactersInString:@"\n\r\t"];
    return [text rangeOfCharacterFromSet:invalid].location==NSNotFound;
}
static NSString *SubPopFeedbackSafeVersion(id value) {
    NSString *text=SubPopFeedbackTrim(value);
    return text.length<=32 && SubPopFeedbackMatches(text,@"[0-9]+(?:\\.[0-9]+){0,3}(?: \\([0-9]+\\))?") ? text : @"未知";
}
static NSDictionary *SubPopFeedbackEnvironment(NSBundle *bundle) {
    NSOperatingSystemVersion system=NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *macOS=[NSString stringWithFormat:@"%ld.%ld.%ld",(long)system.majorVersion,(long)system.minorVersion,(long)system.patchVersion];
#if defined(__arm64__)
    NSString *architecture=@"Apple Silicon";
#elif defined(__x86_64__)
    NSString *architecture=@"Intel";
#else
    NSString *architecture=@"未知";
#endif
    NSString *build=SubPopFeedbackTrim([bundle objectForInfoDictionaryKey:@"CFBundleVersion"]);
    return @{@"version":SubPopFeedbackSafeVersion([bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]),
             @"build":build.length<=10 && SubPopFeedbackMatches(build,@"[0-9]+") ? build : @"未知",
             @"macOS":macOS,@"architecture":architecture};
}
static NSString *SubPopFeedbackValidationMessage(NSString *description) {
    if (!SubPopFeedbackTrim(description).length) return @"请先填写遇到的问题。";
    if (!SubPopFeedbackTextValid(description,SubPopFeedbackDescriptionLimit)) return @"问题说明最多 1200 字，不能包含控制字符。";
    return nil;
}
static NSDictionary *SubPopFeedbackSafeEnvironment(NSDictionary *environment) {
    // Whitelist individual environment values again at serialization. Never
    // include an arbitrary dictionary, an error message, logs, or project state.
    NSString *build=SubPopFeedbackTrim(environment[@"build"]);
    if (build.length>10 || !SubPopFeedbackMatches(build,@"[0-9]+")) build=@"未知";
    NSString *architecture=[@[@"Apple Silicon",@"Intel"] containsObject:environment[@"architecture"]] ? environment[@"architecture"] : @"未知";
    return @{@"version":SubPopFeedbackSafeVersion(environment[@"version"]),@"build":build,
             @"macOS":SubPopFeedbackSafeVersion(environment[@"macOS"]),@"architecture":architecture};
}
static NSString *SubPopFeedbackEnvironmentText(NSDictionary *environment) {
    NSDictionary *safe=SubPopFeedbackSafeEnvironment(environment);
    return [NSString stringWithFormat:@"SubPop：%@（Build %@）\nmacOS：%@\n处理器：%@",
            safe[@"version"],safe[@"build"],safe[@"macOS"],safe[@"architecture"]];
}
static NSString *SubPopFeedbackBody(NSString *description,NSDictionary *environment) {
    if (SubPopFeedbackValidationMessage(description)) return nil;
    return [NSString stringWithFormat:@"## 问题说明\n%@\n\n## 使用环境\n%@",
            SubPopFeedbackTrim(description),SubPopFeedbackEnvironmentText(environment)];
}
static NSString *SubPopFeedbackEncode(NSString *text) {
    // NSURLComponents leaves '+' unescaped, but web forms interpret '+' as a
    // space. Encode every character outside RFC 3986's unreserved set.
    NSCharacterSet *unreserved=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [text stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
}
static NSString *SubPopFeedbackTitle(NSString *description) {
    NSString *title=SubPopFeedbackTrim(description);
    title=[[title componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] firstObject];
    if (title.length>70) title=[title substringToIndex:[title rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,70)].length];
    if (title.length>100) title=@"SubPop 使用问题";
    return [@"[问题] " stringByAppendingString:title];
}
static NSArray *SubPopFeedbackFormFields(NSString *description,NSDictionary *environment) {
    return @[@[@"template",@"bug_report.yml"],@[@"title",SubPopFeedbackTitle(description)],
             @[@"environment",SubPopFeedbackEnvironmentText(environment)]];
}
static NSURL *SubPopFeedbackEncodedFormURL(NSArray *fields) {
    NSMutableArray *query=[NSMutableArray array];
    for (NSArray *field in fields) [query addObject:[NSString stringWithFormat:@"%@=%@",field[0],SubPopFeedbackEncode(field[1])]];
    NSString *url=[NSString stringWithFormat:@"%@?%@",SubPopFeedbackNewIssue,[query componentsJoinedByString:@"&"]];
    return url.length<=SubPopFeedbackURLLimit ? [NSURL URLWithString:url] : nil;
}
static NSURL *SubPopFeedbackIssueURL(NSString *description,NSDictionary *environment) {
    if (SubPopFeedbackValidationMessage(description)) return nil;
    NSMutableArray *fields=[SubPopFeedbackFormFields(description,environment) mutableCopy];
    [fields addObject:@[@"problem",SubPopFeedbackTrim(description)]];
    return SubPopFeedbackEncodedFormURL(fields);
}
static NSURL *SubPopFeedbackShortIssueURL(NSString *description,NSDictionary *environment) {
    if (SubPopFeedbackValidationMessage(description)) return nil;
    return SubPopFeedbackEncodedFormURL(SubPopFeedbackFormFields(description,environment));
}
