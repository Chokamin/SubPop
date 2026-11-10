#import <Foundation/Foundation.h>

// macOS updates can drop the Workflow Extension from PlugInKit while the app
// stays installed; FCP then shows no SubPop toolbar button. The container
// re-registers only its own installed appex and never changes user elections.
static NSString * const SubPopInstalledAppPath=@"/Applications/SubPop.app";
static NSString * const SubPopExtensionIdentifier=@"com.chokamin.SubPopProbe.Extension";

typedef NS_ENUM(NSInteger, SubPopExtensionRegistration) {
    SubPopExtensionUnchecked,
    SubPopExtensionRegistered,
    SubPopExtensionRepaired,
    SubPopExtensionRepairFailed,
};

// Returns stdout for a successful pluginkit run, nil when it cannot run.
typedef NSString *(^SubPopPluginKitRunner)(NSArray<NSString *> *arguments);

// `pluginkit -m -v` rows: election prefix, identifier(version), UUID, date, path.
static inline BOOL SubPopPluginKitListsExtension(NSString *output,NSString *extensionPath) {
    NSString *expected=extensionPath.stringByStandardizingPath;
    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSString *> *fields=[line componentsSeparatedByString:@"\t"];
        if (fields.count<2) continue;
        NSString *name=[fields.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" +-!=?"]];
        NSString *path=[fields.lastObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([name hasPrefix:[SubPopExtensionIdentifier stringByAppendingString:@"("]] && [path.stringByStandardizingPath isEqual:expected]) return YES;
    }
    return NO;
}

static inline SubPopExtensionRegistration SubPopEnsureExtensionRegistered(NSString *extensionPath,SubPopPluginKitRunner run,void (^pause)(void)) {
    NSArray *query=@[@"-m",@"-A",@"-D",@"-v",@"-i",SubPopExtensionIdentifier];
    NSString *output=run(query);
    if (!output) return SubPopExtensionUnchecked;
    if (SubPopPluginKitListsExtension(output,extensionPath)) return SubPopExtensionRegistered;
    run(@[@"-a",extensionPath]);
    // PlugInKit can publish the new record a moment after `-a` returns.
    for (NSUInteger attempt=0;attempt<3;attempt++) {
        if (attempt) pause();
        if (SubPopPluginKitListsExtension(run(query),extensionPath)) return SubPopExtensionRepaired;
    }
    return SubPopExtensionRepairFailed;
}

// Title and detail for the one alert, or nil when nothing needs the user.
static inline NSString *SubPopExtensionRegistrationAlert(SubPopExtensionRegistration state,BOOL finalCutRunning,NSString **detail) {
    if (state==SubPopExtensionRepaired && finalCutRunning) {
        if (detail) *detail=@"系统更新后，Final Cut Pro 可能找不到 SubPop 扩展，现已重新登记。请退出并重新打开 Final Cut Pro，再从工具栏的扩展按钮或「窗口 → 扩展 → SubPop」打开。";
        return @"请重新打开 Final Cut Pro";
    }
    if (state==SubPopExtensionRepairFailed) {
        if (detail) *detail=@"Final Cut Pro 可能无法显示 SubPop。请重新安装最新版 SubPop，打开一次 SubPop 后再重新打开 Final Cut Pro。";
        return @"未能登记 SubPop 扩展";
    }
    return nil;
}

// SubPop has no window of its own. A manual open (Finder, Launchpad or a
// second double-click) otherwise looks like nothing happened.
static inline NSString *SubPopLaunchGuideAlert(BOOL finalCutRunning,NSString **detail) {
    if (detail) *detail=finalCutRunning
        ? @"SubPop 没有独立窗口，已在后台运行。请在 Final Cut Pro 中点击工具栏的扩展按钮，或选择「窗口 → 扩展 → SubPop」打开面板。"
        : @"SubPop 没有独立窗口，已在后台运行。请打开 Final Cut Pro，点击工具栏的扩展按钮，或选择「窗口 → 扩展 → SubPop」打开面板。";
    return @"SubPop 在 Final Cut Pro 中使用";
}

static inline NSString *SubPopRunPluginKit(NSArray<NSString *> *arguments) {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/pluginkit"];task.arguments=arguments;
    NSPipe *output=[NSPipe pipe];task.standardOutput=output;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    NSError *error=nil;
    if (![task launchAndReturnError:&error]) {NSLog(@"SubPop pluginkit: %@",error);return nil;}
    dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSData *data=nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{data=[output.fileHandleForReading readDataToEndOfFile];dispatch_semaphore_signal(done);});
    if (dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(10*NSEC_PER_SEC)))) {[task terminate];return nil;}
    [task waitUntilExit];
    return task.terminationStatus==0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}
