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
        if (argc!=4) return 2;
        NSData *xml=[NSData dataWithContentsOfFile:@(argv[1])];
        NSDictionary *result=SubPopProbeAudio(xml,@(argv[2]),[NSURL fileURLWithPath:@(argv[3]) isDirectory:YES]);
        NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return 0;
    }
}
