// Unsandboxed test harness only; live access evidence must come from the extension.
#import "AudioProbe.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc==3 && strcmp(argv[1],"--inspect-file")==0) {
            NSDictionary *result=SubPopAudioFileInfo([NSURL fileURLWithPath:@(argv[2])]);
            NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
            puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
            return 0;
        }
        if (argc!=4 && argc!=5) return 2;
        NSData *xml=[NSData dataWithContentsOfFile:@(argv[1])];
        NSDictionary *mix=nil;NSError *error=nil;
        if (argc==5) {
            id value=[NSJSONSerialization JSONObjectWithData:[@(argv[4]) dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:&error];
            if (error || (value!=NSNull.null && ![value isKindOfClass:NSDictionary.class])) {
                puts("{\"status\":\"failed\",\"stage\":\"invalid-channel-selection\"}");return 0;
            }
            if (value!=NSNull.null) mix=value;
        }
        NSDictionary *result=SubPopProbeAudioChannels(xml,@(argv[2]),[NSURL fileURLWithPath:@(argv[3]) isDirectory:YES],mix);
        NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return 0;
    }
}
