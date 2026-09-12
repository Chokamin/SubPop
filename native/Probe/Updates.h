#import <Cocoa/Cocoa.h>
static NSDictionary *SubPopReleaseUpdate(NSDictionary *release, NSString *current, NSString *repository) {
    NSString *tag=release[@"tag_name"];
    if (![tag isKindOfClass:NSString.class] || [release[@"draft"] boolValue] || [release[@"prerelease"] boolValue]) return nil;
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^v?([0-9]+\\.[0-9]+\\.[0-9]+(?:\\.[0-9]+)?)$" options:0 error:nil];
    NSTextCheckingResult *match=[pattern firstMatchInString:tag options:0 range:NSMakeRange(0,tag.length)];if (!match) return nil;
    NSString *version=[tag substringWithRange:[match rangeAtIndex:1]];
    BOOL installer=NO;
    for (NSDictionary *asset in release[@"assets"]) {
        NSString *name=asset[@"name"];
        if ([name isKindOfClass:NSString.class] && ([name hasSuffix:@".pkg"] || [name hasSuffix:@".dmg"])) installer=YES;
    }
    return @{@"version":version,@"newer":@([version compare:current options:NSNumericSearch]==NSOrderedDescending),@"installer":@(installer),@"url":[NSString stringWithFormat:@"https://github.com/%@/releases/tag/%@",repository,tag]};
}
