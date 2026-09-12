#import <Cocoa/Cocoa.h>
#include <pwd.h>
#include <unistd.h>
static NSString *SubPopWorkspace(NSBundle *bundle) {
    if (![[bundle objectForInfoDictionaryKey:@"SubPopPackagedRuntime"] boolValue]) return [bundle objectForInfoDictionaryKey:@"SubPopWorkspace"];
    struct passwd *entry=getpwuid(getuid());
    NSString *home=entry ? [NSString stringWithUTF8String:entry->pw_dir] : NSHomeDirectory();
    return [home stringByAppendingPathComponent:@"Library/Application Support/SubPop"];
}
