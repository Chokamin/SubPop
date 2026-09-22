#pragma once
#import <Cocoa/Cocoa.h>
#include <pwd.h>
#include <unistd.h>
static NSString *SubPopWorkspace(NSBundle *bundle) {
    // Remember an explicitly configured development data root in each process's
    // existing preferences. Later packaged updates then retain the same models,
    // bridge bookmark and jobs; new installations still use Application Support.
    if (![[bundle objectForInfoDictionaryKey:@"SubPopPackagedRuntime"] boolValue]) {
        NSString *root=[bundle objectForInfoDictionaryKey:@"SubPopWorkspace"];
        if(root.isAbsolutePath)[NSUserDefaults.standardUserDefaults setObject:root forKey:@"SubPopDataRoot"];
        return root;
    }
    NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:@"SubPopDataRoot"];
    if(saved.isAbsolutePath && ![saved isEqual:@"/"])return saved;
    struct passwd *entry=getpwuid(getuid());
    NSString *home=entry ? [NSString stringWithUTF8String:entry->pw_dir] : NSHomeDirectory();
    return [home stringByAppendingPathComponent:@"Library/Application Support/SubPop"];
}
