#import <Foundation/Foundation.h>

// The feedback destination is fixed. User text cannot choose a repository,
// attachment, label, or an additional URL query parameter.
static NSString *const SubPopFeedbackNewIssue= @"https://github.com/Chokamin/SubPop/issues/new";
static NSUInteger const SubPopFeedbackDescriptionLimit=1200;
static NSUInteger const SubPopFeedbackStepsLimit=800;
static NSUInteger const SubPopFeedbackExpectedLimit=400;
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
static NSString *SubPopFeedbackValidationMessage(NSString *description,NSString *steps,NSString *expected,NSString *fcpVersion) {
    if (!SubPopFeedbackTrim(description).length) return @"请先填写遇到的问题。";
    if (!SubPopFeedbackTextValid(description,SubPopFeedbackDescriptionLimit)) return @"问题说明最多 1200 字，不能包含控制字符。";
    if (!SubPopFeedbackTextValid(steps,SubPopFeedbackStepsLimit)) return @"复现步骤最多 800 字，不能包含控制字符。";
    if (!SubPopFeedbackTextValid(expected,SubPopFeedbackExpectedLimit)) return @"期望结果最多 400 字，不能包含控制字符。";
    NSString *fcp=SubPopFeedbackTrim(fcpVersion);
    if (fcp.length && [SubPopFeedbackSafeVersion(fcp) isEqual:@"未知"]) return @"FCP 版本请填写数字版本，例如 12.3；也可以留空。";
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
static NSString *SubPopFeedbackBody(NSString *description,NSString *steps,NSString *expected,NSString *fcpVersion,NSDictionary *environment) {
    if (SubPopFeedbackValidationMessage(description,steps,expected,fcpVersion)) return nil;
    NSDictionary *safe=SubPopFeedbackSafeEnvironment(environment);
    return [NSString stringWithFormat:@"## 遇到的问题\n%@\n\n## 复现步骤\n%@\n\n## 期望结果\n%@\n\n## 使用环境\n- SubPop：%@（Build %@）\n- macOS：%@\n- 处理器：%@\n- Final Cut Pro：%@\n\n由 SubPop 反馈入口整理；未自动附加日志、项目、音频或凭证。",
            SubPopFeedbackTrim(description),SubPopFeedbackTrim(steps).length ? SubPopFeedbackTrim(steps) : @"未填写",
            SubPopFeedbackTrim(expected).length ? SubPopFeedbackTrim(expected) : @"未填写",
            safe[@"version"],safe[@"build"],safe[@"macOS"],safe[@"architecture"],
            SubPopFeedbackTrim(fcpVersion).length ? SubPopFeedbackSafeVersion(fcpVersion) : @"未填写"];
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
static NSArray *SubPopFeedbackFormFields(NSString *description,NSString *fcpVersion,NSDictionary *environment) {
    NSDictionary *safe=SubPopFeedbackSafeEnvironment(environment);
    return @[@[@"template",@"bug_report.yml"],@[@"title",SubPopFeedbackTitle(description)],
             @[@"subpop_version",[NSString stringWithFormat:@"%@（Build %@）",safe[@"version"],safe[@"build"]]],
             @[@"macos_version",[NSString stringWithFormat:@"%@ · %@",safe[@"macOS"],safe[@"architecture"]]],
             @[@"fcp_version",SubPopFeedbackTrim(fcpVersion).length ? SubPopFeedbackSafeVersion(fcpVersion) : @"不清楚"]];
}
static NSURL *SubPopFeedbackEncodedFormURL(NSArray *fields) {
    NSMutableArray *query=[NSMutableArray array];
    for (NSArray *field in fields) [query addObject:[NSString stringWithFormat:@"%@=%@",field[0],SubPopFeedbackEncode(field[1])]];
    NSString *url=[NSString stringWithFormat:@"%@?%@",SubPopFeedbackNewIssue,[query componentsJoinedByString:@"&"]];
    return url.length<=SubPopFeedbackURLLimit ? [NSURL URLWithString:url] : nil;
}
static NSURL *SubPopFeedbackIssueURL(NSString *description,NSString *steps,NSString *expected,NSString *fcpVersion,NSDictionary *environment) {
    if (SubPopFeedbackValidationMessage(description,steps,expected,fcpVersion)) return nil;
    NSMutableArray *fields=[SubPopFeedbackFormFields(description,fcpVersion,environment) mutableCopy];
    [fields addObjectsFromArray:@[@[@"problem",SubPopFeedbackTrim(description)],@[@"steps",SubPopFeedbackTrim(steps)],
                                 @[@"expected_actual",SubPopFeedbackTrim(expected).length ? [NSString stringWithFormat:@"预期：%@\n实际：见上方问题说明",SubPopFeedbackTrim(expected)] : @""]]];
    return SubPopFeedbackEncodedFormURL(fields);
}
static NSURL *SubPopFeedbackShortIssueURL(NSString *description,NSString *fcpVersion,NSDictionary *environment) {
    if (SubPopFeedbackValidationMessage(description,@"",@"",fcpVersion)) return nil;
    return SubPopFeedbackEncodedFormURL(SubPopFeedbackFormFields(description,fcpVersion,environment));
}
