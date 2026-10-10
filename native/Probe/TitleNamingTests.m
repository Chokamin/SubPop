// Local resource/XML tests only. Does not launch or communicate with FCP.
#import "TitleNaming.h"

static NSUInteger checks=0;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) {fprintf(stderr,"Title naming failed: %s\n",message.UTF8String);exit(1);}
}
static void Write(NSURL *url, NSData *data) {
    Check([NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil],@"fixture directory");
    Check([data writeToURL:url atomically:YES],@"fixture data");
}
static void WritePlist(NSURL *url, id value) {
    Write(url,[NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:nil]);
}
static NSURL *Template(NSURL *app,BOOL native) {
    return [app URLByAppendingPathComponent:native
        ? @"Contents/PlugIns/MediaProviders/MotionEffect.fxp/Contents/Resources/METemplates.localized/Titles.localized/Subtitles.localized/Subtitle.localized/Subtitle.moti"
        : @"Contents/PlugIns/MediaProviders/MotionEffect.fxp/Contents/Resources/PETemplates.localized/Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"];
}
static NSURL *Strings(NSURL *template,NSString *language) {
    return [[template.URLByDeletingLastPathComponent URLByAppendingPathComponent:@".localized"] URLByAppendingPathComponent:[language stringByAppendingString:@".strings"]];
}
static NSString *Display(NSURL *app,SubPopTitleTemplate template,NSArray *languages) {
    return SubPopTitleTemplateDisplayNameAtHostURL(template,app,languages);
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"SubPopTitleNaming-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
        NSURL *app=[root URLByAppendingPathComponent:@"FCP.app" isDirectory:YES];
        WritePlist([app URLByAppendingPathComponent:@"Contents/Info.plist"],@{@"CFBundleIdentifier":@"com.apple.FinalCutApp",@"CFBundlePackageType":@"APPL",@"CFBundleDevelopmentRegion":@"en",@"CFBundleLocalizations":@[@"en",@"zh_CN",@"zh_TW",@"fr",@"de"]});
        NSURL *basic=Template(app,NO),*native=Template(app,YES);
        Check(!SubPopValidTap5a(basic),@"built-in template remains distinct from Tap5a");
        Write(basic,[@"<ozml/>" dataUsingEncoding:NSUTF8StringEncoding]);
        Write(native,[@"<ozml/>" dataUsingEncoding:NSUTF8StringEncoding]);
        NSDictionary *names=@{@"en":@"Basic Title",@"zh_CN":@"基本字幕",@"zh_TW":@"基本標題",@"fr":@"Titre standard"};
        for (NSString *language in names) WritePlist(Strings(basic,language),@{@"Basic Title":names[language]});
        Write(Strings(native,@"en"),[@"\"Subtitle\" = \"Subtitle\";\n" dataUsingEncoding:NSUTF16StringEncoding]);
        Check([Display(app,SubPopTitleTemplateBasic,@[@"zh-Hans-CN"]) isEqual:@"基本字幕"],@"simplified host language reads simplified template resource");
        Check([Display(app,SubPopTitleTemplateBasic,@[@"zh-Hant-TW"]) isEqual:@"基本標題"],@"traditional host language reads traditional template resource");
        Check([Display(app,SubPopTitleTemplateBasic,@[@"en-US"]) isEqual:@"Basic Title"],@"English host language reads English template resource");
        NSArray *overridden=SubPopTitleNamingPreferredLanguages(@[@"fr-FR"],@[@"zh-Hans"]);
        Check([Display(app,SubPopTitleTemplateBasic,overridden) isEqual:@"Titre standard"],@"host per-app override wins over system language");
        Check([SubPopTitleNamingPreferredLanguages(@"fr",@[@"zh-Hans"]) isEqual:@[@"zh-Hans"]],@"invalid preference type falls back without interpretation");
        Check([SubPopTitleNamingPreferredLanguages(@[@1],@[@"en"]) isEqual:@[@"en"]],@"invalid preference item falls back");
        Check([Display(app,SubPopTitleTemplateBasic,@[@"de"]) isEqual:@"Basic Title"],@"template development resource supplies missing localization");
        Check([Display(app,SubPopTitleTemplateNative,@[@"zh-Hans"]) isEqual:@"Subtitle"],@"native template uses its real English-only name, not localized role name");
        Check(!Display(app,SubPopTitleTemplateTap5a,@[@"en"]),@"Tap5a never uses automatic built-in localization");
        Check(!Display(app,SubPopTitleTemplateBasic,@[]),@"unknown host language does not guess a label");
        Check(!SubPopTitleNamingHostIdentifier(@"unknown.application"),@"unrecognized host does not resolve some other installed FCP");
        NSURL *other=[root URLByAppendingPathComponent:@"Other.app"];
        WritePlist([other URLByAppendingPathComponent:@"Contents/Info.plist"],@{@"CFBundleIdentifier":@"other.app",@"CFBundleLocalizations":@[@"en"]});
        Check(!Display(other,SubPopTitleTemplateBasic,@[@"en"]),@"mismatched host bundle fails closed");

        NSURL *damaged=[root URLByAppendingPathComponent:@"Broken.moti"];
        Write(damaged,[@"<ozml/>" dataUsingEncoding:NSUTF8StringEncoding]);
        Check(!SubPopTitleNamingLocalizedTemplate(damaged,@[@"en"]),@"missing localization returns nil");
        WritePlist(Strings(damaged,@"zh_CN"),@{@"Broken":@"中文名称"});
        Check([SubPopTitleNamingLocalizedTemplate(damaged,@[@"zh-Hans"]) isEqual:@"中文名称"],@"available matching language remains usable without development localization");
        Check(!SubPopTitleNamingLocalizedTemplate(damaged,@[@"fr"]),@"missing development localization cannot select an unrelated language");
        WritePlist(Strings(damaged,@"en"),@{@"unrelated":@"Name"});
        Check(!SubPopTitleNamingLocalizedTemplate(damaged,@[@"en"]),@"wrong resource key is not a display name");
        WritePlist(Strings(damaged,@"en"),@{@"Broken":@"unsafe\nname"});
        Check(!SubPopTitleNamingLocalizedTemplate(damaged,@[@"en"]),@"invalid control characters do not enter clip names");
        Write(Strings(damaged,@"en"),[NSMutableData dataWithLength:65537]);
        Check(!SubPopTitleNamingLocalizedTemplate(damaged,@[@"en"]),@"oversized resources rejected");

        Check(!SubPopAutomaticTitleClipName(@"正文",nil),@"unknown display name cannot create a custom clip name");
        Check(!SubPopAutomaticTitleClipName(@"正文",@""),@"empty display name remains unresolved");
        Check([SubPopAutomaticTitleClipName(@"",@"Subtitle") isEqual:@"Subtitle"],@"empty text uses plain template name");
        Check([SubPopAutomaticTitleClipName(@"\n第二行",@"基本字幕") isEqual:@"基本字幕"],@"empty first line uses plain template name");
        Check([SubPopAutomaticTitleClipName(@"第一行\n第二行",@"基本字幕") isEqual:@"第一行 - 基本字幕"],@"LF uses only first logical line");
        Check([SubPopAutomaticTitleClipName(@"第一行\r\n第二行",@"Subtitle") isEqual:@"第一行 - Subtitle"],@"CRLF does not enter clip name");
        Check([SubPopAutomaticTitleClipName(@"第一行\r第二行",@"Subtitle") isEqual:@"第一行 - Subtitle"],@"CR uses first logical line");
        Check([SubPopAutomaticTitleClipName(@"第一行\u2028第二行",@"Subtitle") isEqual:@"第一行 - Subtitle"],@"Unicode line separator follows Foundation line boundaries");
        Check([SubPopAutomaticTitleClipName(@"第一行\u2029第二段",@"Subtitle") isEqual:@"第一行 - Subtitle"],@"Unicode paragraph separator follows Foundation line boundaries");
        Check([SubPopAutomaticTitleClipName(@"  首尾空格  \n下一行",@"基本字幕") isEqual:@"  首尾空格   - 基本字幕"],@"first-line whitespace is never trimmed");
        Check([SubPopAutomaticTitleClipName(@"😀 & <保留> 3.5% USB-C",@"基本字幕") isEqual:@"😀 & <保留> 3.5% USB-C - 基本字幕"],@"symbols and composed characters are preserved");
        Check([SubPopAutomaticTitleClipName(@"正文 - 基本字幕",@"基本字幕") isEqual:@"正文 - 基本字幕 - 基本字幕"],@"template-like suffix inside body is literal content");
        NSString *longLine=[@"长" stringByPaddingToLength:500 withString:@"长" startingAtIndex:0];
        Check([SubPopAutomaticTitleClipName(longLine,@"Subtitle") isEqual:[longLine stringByAppendingString:@" - Subtitle"]],@"long first line is not truncated");

        NSXMLElement *title=[[NSXMLElement alloc] initWithXMLString:@"<title name='旧文字' offset='7/25s' duration='1s'><text><text-style>新文字 &amp; 😀</text-style></text></title>" error:nil];
        NSString *text=[title nodesForXPath:@"text" error:nil].firstObject.XMLString;
        SubPopSetTitleClipName(title,@"新文字 & 😀 - 基本字幕");
        Check([[title attributeForName:@"name"].stringValue isEqual:@"新文字 & 😀 - 基本字幕"],@"setter replaces stale name");
        SubPopSetTitleClipName(title,@"新文字 & 😀 - 基本字幕");
        Check([title nodesForXPath:@"@name" error:nil].count==1,@"rebuilding cannot add duplicate name attributes");
        SubPopSetTitleClipName(title,nil);
        Check(![title attributeForName:@"name"],@"unknown name removes attribute, not empty custom name");
        SubPopSetTitleClipName(title,@"恢复名称");
        Check([[title attributeForName:@"name"].stringValue isEqual:@"恢复名称"],@"setter creates missing name attribute");
        Check([[title attributeForName:@"offset"].stringValue isEqual:@"7/25s"] && [[title attributeForName:@"duration"].stringValue isEqual:@"1s"] && [[title nodesForXPath:@"text" error:nil].firstObject.XMLString isEqual:text],@"naming never alters timing or subtitle text");
        if (argc==2) {
            NSURL *installed=[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
            Check([Display(installed,SubPopTitleTemplateBasic,@[@"zh-Hans-CN"]) isEqual:@"基本字幕"],@"installed Basic simplified resource");
            Check([Display(installed,SubPopTitleTemplateBasic,@[@"zh-Hant-TW"]) isEqual:@"基本標題"],@"installed Basic traditional resource");
            Check([Display(installed,SubPopTitleTemplateBasic,@[@"en-US"]) isEqual:@"Basic Title"],@"installed Basic English resource");
            Check([Display(installed,SubPopTitleTemplateNative,@[@"zh-Hans-CN"]) isEqual:@"Subtitle"],@"installed native template resource");
        }
        Check([NSFileManager.defaultManager removeItemAtURL:root error:nil],@"remove only this process's isolated test directory");
        printf("Title naming: %lu local resource/preference/XML checks passed; no FCP calls.\n",(unsigned long)checks);
    }
    return 0;
}
