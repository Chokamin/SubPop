#import "ExtensionRegistration.h"

// Fake PlugInKit only; the real registry and FCP are never touched.
static void check(BOOL passed,NSString *message) {if (!passed) {NSLog(@"Extension registration regression: %@",message);exit(1);}}
static NSString * const Path=@"/Applications/SubPop.app/Contents/PlugIns/SubPopProbe.appex";
static NSString *row(NSString *prefix,NSString *path) {
    return [NSString stringWithFormat:@"%@    com.chokamin.SubPopProbe.Extension(1.5.15)\tFDAE84F0-9B27-4F32-8AB6-AF91F5677D98\t2026-11-09 03:30:33 +0000\t%@\n (1 plug-in)\n",prefix,path];
}
int main(void) {
    @autoreleasepool {
        check(SubPopPluginKitListsExtension(row(@" ",Path),Path),@"default election row is registered");
        check(SubPopPluginKitListsExtension(row(@"+",Path),Path),@"elected row is registered");
        check(!SubPopPluginKitListsExtension(@"  (no matches)\n",Path),@"empty registry is missing");
        check(!SubPopPluginKitListsExtension(row(@" ",@"/Users/me/Downloads/SubPop.app/Contents/PlugIns/SubPopProbe.appex"),Path),@"another copy does not count");
        NSString *other=[row(@" ",Path) stringByReplacingOccurrencesOfString:@"com.chokamin.SubPopProbe.Extension(" withString:@"com.chokamin.SubPopProbe.ExtensionOther("];
        check(!SubPopPluginKitListsExtension(other,Path),@"identifier must match exactly");

        __block NSMutableArray<NSArray *> *calls=[NSMutableArray array];
        __block NSUInteger pauses=0;
        void (^pause)(void)=^{pauses++;};

        // Registered: one query and no registration change.
        SubPopExtensionRegistration state=SubPopEnsureExtensionRegistered(Path,^NSString *(NSArray *arguments) {[calls addObject:arguments];return row(@" ",Path);},pause);
        check(state==SubPopExtensionRegistered && calls.count==1,@"registered extension is left alone");
        check(![calls.firstObject containsObject:@"-a"] && ![calls.firstObject containsObject:@"-e"],@"query never adds or changes elections");

        // Dropped after a macOS update: add our own appex, then confirm.
        [calls removeAllObjects];__block BOOL added=NO;
        state=SubPopEnsureExtensionRegistered(Path,^NSString *(NSArray *arguments) {
            [calls addObject:arguments];
            if ([arguments.firstObject isEqual:@"-a"]) {added=YES;return @"";}
            return added ? row(@" ",Path) : @"  (no matches)\n";
        },pause);
        check(state==SubPopExtensionRepaired,@"missing extension is re-registered");
        check([calls[1] isEqual:@[@"-a",Path]],@"only the installed appex path is added");
        check(calls.count==3 && pauses==0,@"immediate confirmation needs no wait");

        // PlugInKit publishes late: retry with pauses, then succeed.
        [calls removeAllObjects];pauses=0;__block NSUInteger queries=0;
        state=SubPopEnsureExtensionRegistered(Path,^NSString *(NSArray *arguments) {
            if ([arguments.firstObject isEqual:@"-a"]) return @"";
            return ++queries>=3 ? row(@" ",Path) : @"  (no matches)\n";
        },pause);
        check(state==SubPopExtensionRepaired && pauses==1,@"late publication is accepted after a pause");

        // Never appears: bounded retries, then failure.
        pauses=0;queries=0;
        state=SubPopEnsureExtensionRegistered(Path,^NSString *(NSArray *arguments) {if (![arguments.firstObject isEqual:@"-a"]) queries++;return @"  (no matches)\n";},pause);
        check(state==SubPopExtensionRepairFailed && queries==4 && pauses==2,@"repair stops after three confirmations");

        // pluginkit unavailable: no add attempt and no alert.
        [calls removeAllObjects];
        state=SubPopEnsureExtensionRegistered(Path,^NSString *(NSArray *arguments) {[calls addObject:arguments];return (NSString *)nil;},pause);
        check(state==SubPopExtensionUnchecked && calls.count==1,@"unavailable pluginkit changes nothing");

        NSString *detail=nil;
        check(!SubPopExtensionRegistrationAlert(SubPopExtensionRegistered,YES,&detail),@"healthy launch stays silent");
        check(!SubPopExtensionRegistrationAlert(SubPopExtensionUnchecked,YES,&detail),@"unchecked launch stays silent");
        check(!SubPopExtensionRegistrationAlert(SubPopExtensionRepaired,NO,&detail),@"repair before FCP opens needs no restart prompt");
        NSString *title=SubPopExtensionRegistrationAlert(SubPopExtensionRepaired,YES,&detail);
        check([title containsString:@"重新打开 Final Cut Pro"] && [detail containsString:@"窗口 → 扩展 → SubPop"],@"running FCP asks for a restart");
        title=SubPopExtensionRegistrationAlert(SubPopExtensionRepairFailed,NO,&detail);
        check([title containsString:@"未能登记"] && [detail containsString:@"重新安装"],@"failure explains the next step");
        NSLog(@"Extension registration checks passed");
    }
    return 0;
}
