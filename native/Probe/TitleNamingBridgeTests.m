// Pure snapshot tests: no FCP calls, preference writes, or production App Group.
#import "TitleNamingBridge.h"

static NSUInteger checks=0;
static void Check(BOOL condition,NSString *message) {
    checks++;
    if (!condition) {fprintf(stderr,"Title naming bridge failed: %s\n",message.UTF8String);exit(1);}
}
static NSDate *Date(NSTimeInterval seconds) {return [NSDate dateWithTimeIntervalSince1970:seconds];}
static NSString *Read(id snapshot,SubPopTitleTemplate template,NSString *hostID,NSNumber *pid,NSTimeInterval launch,NSTimeInterval now) {
    return SubPopTitleTemplateDisplayNameFromSnapshot(snapshot,template,hostID,pid,Date(launch),Date(now));
}
static NSDictionary *Replacing(NSDictionary *source,NSString *key,id value) {
    NSMutableDictionary *copy=[source mutableCopy];
    if (value) copy[key]=value;
    else [copy removeObjectForKey:key];
    return copy.copy;
}
int main(void) {
    @autoreleasepool {
        NSString *host=@"com.apple.FinalCutApp";
        __block NSArray *observedLanguages=nil;
        __block NSUInteger resolutions=0;
        SubPopTitleNamingResolver resolver=^NSString *(SubPopTitleTemplate template,NSArray<NSString *> *languages) {
            observedLanguages=languages;resolutions++;
            return template==SubPopTitleTemplateBasic
                ? ([languages.firstObject hasPrefix:@"en"] ? @"Basic Title" : @"基本字幕") : @"Subtitle";
        };
        NSDictionary *snapshot=SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),@[@"en-US"],@[@"zh-Hans"],resolver);
        Check([observedLanguages isEqual:@[@"en-US"]] && resolutions==2,@"host override wins over container/system language for both templates");
        Check([Read(snapshot,SubPopTitleTemplateBasic,host,@123,1000,2001) isEqual:@"Basic Title"],@"basic host display name survives snapshot");
        Check([Read(snapshot,SubPopTitleTemplateNative,host,@123,1000,2001) isEqual:@"Subtitle"],@"native display name survives snapshot");
        Check(snapshot.count==7 && !snapshot[@"languages"] && !snapshot[@"path"],@"snapshot contains only schema, time, identity and template names");

        NSDictionary *system=SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),nil,@[@"zh-Hans"],resolver);
        Check([observedLanguages isEqual:@[@"zh-Hans"]] && [system[@"basic"] isEqual:@"基本字幕"],@"absent per-app override uses supplied system language");
        SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),@"invalid",@[@"en-US"],resolver);
        Check([observedLanguages isEqual:@[@"en-US"]],@"invalid preference type does not become an implicit language");
        SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),@[@1],@[@"en-US"],resolver);
        Check([observedLanguages isEqual:@[@"en-US"]],@"invalid preference array item uses supplied fallback");
        Check(!SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),nil,@[],resolver),@"no trusted language yields no snapshot");

        Check(!Read(snapshot,SubPopTitleTemplateTap5a,host,@123,1000,2001),@"Tap5a never consumes built-in title naming");
        Check(!Read(snapshot,(SubPopTitleTemplate)99,host,@123,1000,2001),@"unknown template rejected");
        Check(!Read(snapshot,SubPopTitleTemplateBasic,@"com.apple.FinalCut",@123,1000,2001),@"different FCP product cannot consume this host record");
        Check(!Read(snapshot,SubPopTitleTemplateBasic,@"unrelated.app",@123,1000,2001),@"unrelated app cannot consume a record");
        Check(!Read(snapshot,SubPopTitleTemplateBasic,host,@124,1000,2001),@"different process rejected");
        Check(!Read(snapshot,SubPopTitleTemplateBasic,host,@123,1001,2001),@"reused PID with a new launch rejected");
        Check([Read(snapshot,SubPopTitleTemplateBasic,host,@123,1000,2120) isEqual:@"Basic Title"],@"snapshot valid through TTL boundary");
        Check(!Read(snapshot,SubPopTitleTemplateBasic,host,@123,1000,2120.001),@"expired snapshot rejected");
        Check(!Read(snapshot,SubPopTitleTemplateBasic,host,@123,1000,1999.999),@"future snapshot rejected without a clock grace period");
        Check(!Read(Replacing(snapshot,@"timestamp",@999),SubPopTitleTemplateBasic,host,@123,1000,2001),@"snapshot predating process launch rejected");

        NSDictionary *buyout=SubPopCreateTitleNamingSnapshot(@"com.apple.FinalCut",@456,Date(1200),Date(2000),@[@"zh-Hans"],@[@"en"],resolver);
        NSDictionary *twoHosts=@{host:snapshot,@"com.apple.FinalCut":buyout};
        Check([Read(twoHosts[host],SubPopTitleTemplateBasic,host,@123,1000,2001) isEqual:@"Basic Title"] &&
              [Read(twoHosts[@"com.apple.FinalCut"],SubPopTitleTemplateBasic,@"com.apple.FinalCut",@456,1200,2001) isEqual:@"基本字幕"],
              @"different FCP products retain separate language and process identities");

        for (id malformed in @[@"snapshot",@[],@123,NSNull.null])
            Check(!Read(malformed,SubPopTitleTemplateBasic,host,@123,1000,2001),@"non-dictionary record rejected");
        for (NSString *required in @[@"schema",@"timestamp",@"hostID",@"pid",@"launchDate"])
            Check(!Read(Replacing(snapshot,required,nil),SubPopTitleTemplateBasic,host,@123,1000,2001),@"missing identity or freshness field rejected");
        for (id schema in @[@2,@YES,@"1",NSNull.null,@(NAN),@(INFINITY)])
            Check(!Read(Replacing(snapshot,@"schema",schema),SubPopTitleTemplateBasic,host,@123,1000,2001),@"wrong schema or schema type rejected");
        for (id pid in @[@0,@(-1),@123.5,@YES,@"123",@((long long)INT_MAX+1),@(NAN),@(INFINITY),NSNull.null]) {
            Check(!Read(Replacing(snapshot,@"pid",pid),SubPopTitleTemplateBasic,host,@123,1000,2001),@"invalid serialized PID rejected");
            Check(!SubPopCreateTitleNamingSnapshot(host,pid,Date(1000),Date(2000),@[@"en"],@[],resolver),@"invalid live PID cannot create a record");
        }
        for (NSString *key in @[@"timestamp",@"launchDate"])
            for (id malformed in @[@YES,@"2000",@(NAN),@(INFINITY),NSNull.null])
                Check(!Read(Replacing(snapshot,key,malformed),SubPopTitleTemplateBasic,host,@123,1000,2001),@"invalid serialized dates rejected");
        Check(!Read(Replacing(snapshot,@"hostID",@123),SubPopTitleTemplateBasic,host,@123,1000,2001),@"host ID type rejected");
        Check(!Read(Replacing(snapshot,@"unexpected",@"data"),SubPopTitleTemplateBasic,host,@123,1000,2001),@"unknown fields rejected");

        NSString *oversized=[@"a" stringByPaddingToLength:257 withString:@"a" startingAtIndex:0];
        for (id name in @[@"",@" \t ",@"Basic\nTitle",@"Basic\rTitle",@"Basic\u2028Title",oversized,@1,NSNull.null]) {
            Check(!Read(Replacing(snapshot,@"basic",name),SubPopTitleTemplateBasic,host,@123,1000,2001),@"malformed requested name rejected");
            Check(!Read(Replacing(snapshot,@"native",name),SubPopTitleTemplateBasic,host,@123,1000,2001),@"malformed other name invalidates record");
        }
        NSDictionary *partial=SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),@[@"en"],@[],
            ^NSString *(SubPopTitleTemplate template,NSArray *languages) {return template==SubPopTitleTemplateNative ? @"Subtitle" : nil;});
        Check(!Read(partial,SubPopTitleTemplateBasic,host,@123,1000,2001) &&
              [Read(partial,SubPopTitleTemplateNative,host,@123,1000,2001) isEqual:@"Subtitle"],@"a missing resource does not invent a name or block the other template");
        Check(!SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),@[@"en"],@[],
            ^NSString *(SubPopTitleTemplate template,NSArray *languages) {return @"\n";}),@"failed resolution produces no record, not stale names");
        Check(!SubPopCreateTitleNamingSnapshot(@"unrelated.app",@123,Date(1000),Date(2000),@[@"en"],@[],resolver),@"publisher host allowlist enforced before resolution");
        Check(!SubPopCreateTitleNamingSnapshot(host,@123,Date(2001),Date(2000),@[@"en"],@[],resolver),@"future process launch cannot create a record");
        Check(!SubPopCreateTitleNamingSnapshot(host,@123,(id)@"date",Date(2000),@[@"en"],@[],resolver),@"invalid process launch date type rejected");
        Check(!SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(0),@[@"en"],@[],resolver),@"invalid current date rejected");
        Check(!SubPopCreateTitleNamingSnapshot(host,@123,Date(1000),Date(2000),@[@"en"],@[],nil),@"missing resolver does not create a record");
        NSDictionary *languageState=SubPopTitleNamingLanguageState(nil,host,@123,Date(1000),@[@"en-US"]);
        Check(languageState && ![languageState[@"invalidated"] boolValue],@"first observation establishes this process's language");
        languageState=SubPopTitleNamingLanguageState(languageState,host,@123,Date(1000),@[@"en-US"]);
        Check(![languageState[@"invalidated"] boolValue],@"unchanged preferences retain valid process state");
        languageState=SubPopTitleNamingLanguageState(languageState,host,@123,Date(1000),@[@"zh-Hans"]);
        Check([languageState[@"invalidated"] boolValue],@"a language change cannot rename titles for an already-running host");
        languageState=SubPopTitleNamingLanguageState(languageState,host,@123,Date(1000),@[@"en-US"]);
        Check([languageState[@"invalidated"] boolValue],@"reverting preferences does not clear invalidation before host restart");
        languageState=SubPopTitleNamingLanguageState(languageState,host,@123,Date(1100),@[@"zh-Hans"]);
        Check(![languageState[@"invalidated"] boolValue] && [languageState[@"languages"] isEqual:@[@"zh-Hans"]],@"a new launch can establish the updated language even when PID is reused");
        Check(!SubPopTitleNamingLanguageState(@{},host,@123,Date(1000),@[@"en"]),@"malformed private state fails closed");
        Check(!SubPopTitleNamingLanguageState(nil,host,@123,Date(1000),@[]),@"unknown language does not establish process state");
        Check(!SubPopTitleNamingLanguageState(nil,@"unrelated.app",@123,Date(1000),@[@"en"]),@"language state is restricted to supported hosts");
        // These two public calls return before looking up a process or App Group.
        Check(!SubPopReadTitleTemplateDisplayName(SubPopTitleTemplateTap5a,host),@"public Tap5a path has no host or preference side effects");
        Check(!SubPopReadTitleTemplateDisplayName(SubPopTitleTemplateBasic,@"unrelated.app"),@"public unknown-host path has no host or preference side effects");
        printf("Title naming bridge: %lu pure identity/localization/freshness checks passed; no FCP calls or preference writes.\n",(unsigned long)checks);
    }
    return 0;
}
