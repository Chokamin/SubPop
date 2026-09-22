#import "RuntimePaths.h"
@interface PathTestBundle : NSBundle
@property NSDictionary *values;
@end
@implementation PathTestBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {return self.values[key];}
@end
int main(void){@autoreleasepool{
    NSString *key=@"SubPopDataRoot";id original=[NSUserDefaults.standardUserDefaults objectForKey:key];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    PathTestBundle *bundle=[PathTestBundle new];bundle.values=@{@"SubPopPackagedRuntime":@YES};
    NSString *fresh=SubPopWorkspace(bundle);BOOL valid=[fresh hasSuffix:@"/Library/Application Support/SubPop"];
    bundle.values=@{@"SubPopWorkspace":@"/tmp/SubPop-existing-data"};valid&=[SubPopWorkspace(bundle) isEqual:@"/tmp/SubPop-existing-data"];
    bundle.values=@{@"SubPopPackagedRuntime":@YES};valid&=[SubPopWorkspace(bundle) isEqual:@"/tmp/SubPop-existing-data"];
    [NSUserDefaults.standardUserDefaults setObject:@"relative-path" forKey:key];valid&=[SubPopWorkspace(bundle) isEqual:fresh];
    if(original)[NSUserDefaults.standardUserDefaults setObject:original forKey:key];else[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    if(!valid)return 1;puts("Runtime paths: fresh install, development-to-packaged update, and invalid preference fallback passed.");
}return 0;}
