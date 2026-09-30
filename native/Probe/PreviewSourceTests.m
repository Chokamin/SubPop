// Read-only source-clock regressions and optional real AVFoundation frame probe.
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "PreviewSource.h"

static void check(BOOL value,NSString *message) {
    if (!value) {fprintf(stderr,"Preview source check failed: %s\n",message.UTF8String);exit(1);}
}
static NSDictionary *resolve(NSString *story,double seconds) {
    NSString *xml=[NSString stringWithFormat:@"<fcpxml><resources><asset id='r2' hasVideo='1' start='100s' duration='100s'><media-rep kind='original-media' src='file:///tmp/video.mp4'><bookmark>test-bookmark</bookmark></media-rep></asset><asset id='audio' hasAudio='1' start='0s'/><effect id='fx'/></resources><project><sequence tcStart='3600s'><spine>%@</spine></sequence></project></fcpxml>",story];
    return SubPopPreviewSource([xml dataUsingEncoding:NSUTF8StringEncoding],seconds);
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSString *nested=@"<clip offset='3600s' start='105s' duration='3s'><video ref='r2' offset='100s' start='100s' duration='100s'/><asset-clip ref='audio' lane='-1' offset='105s' duration='3s'/><video ref='fx' lane='7' offset='105s' duration='3s'/><title offset='105s' duration='3s'/></clip>";
        NSDictionary *source=resolve(nested,1);
        check(source && [source[@"seconds"] doubleValue]==6,@"trimmed ordinary clip uses its source clock");
        check([source[@"bookmark"] isEqual:@"test-bookmark"],@"asset bookmark survives container lookup");
        check(!resolve(nested,3),@"container end is exclusive");
        check(!resolve([nested stringByReplacingOccurrencesOfString:@"<clip " withString:@"<clip enabled='0' "],1),@"disabled container is not previewed");
        check(!resolve([nested stringByReplacingOccurrencesOfString:@"<clip " withString:@"<clip srcEnable='audio' "],1),@"audio-only container is not previewed");
        check(!resolve([nested stringByReplacingOccurrencesOfString:@"<video ref='r2'" withString:@"<video enabled='0' ref='r2'"],1),@"disabled picture is not replaced with adjustment effect");
        NSString *two=@"<clip offset='3600s' start='205s' duration='3s'><gap offset='200s' start='50s' duration='20s'><clip offset='50s' start='110s' duration='20s'><video ref='r2' offset='100s' start='100s' duration='100s'/></clip></gap></clip>";
        check([resolve(two,1)[@"seconds"] doubleValue]==16,@"nested clip and gap compose independent clocks");
        check(!resolve([nested stringByReplacingOccurrencesOfString:@"<video ref='r2'" withString:@"<video lane='1' ref='r2'"],1),@"connected picture is not claimed to be a composited frame");
        check(!resolve([nested stringByReplacingOccurrencesOfString:@"</clip>" withString:@"<timeMap/></clip>"],1),@"unsupported container retime does not return a wrong timestamp");
        check(!resolve([nested stringByReplacingOccurrencesOfString:@"</clip>" withString:@"<conform-rate scaleEnabled='1'/></clip>"],1),@"scaled conform clock is not approximated");
        check([resolve([nested stringByReplacingOccurrencesOfString:@"</clip>" withString:@"<conform-rate scaleEnabled='0'/></clip>"],1)[@"seconds"] doubleValue]==6,@"ordinary frame sampling without speed scaling remains supported");
        check(!resolve(@"<clip offset='3600s' start='NaNs' duration='3s'><video ref='r2' duration='3s'/></clip>",1),@"invalid source clock rejected");
        check(!resolve(nested,-1) && !resolve(nested,NAN) && !SubPopPreviewSource(nil,1),@"invalid project time and empty data rejected");
        check(!resolve(@"<ref-clip ref='compound' offset='3600s' duration='3s'/>",1),@"unresolved compound reference is not silently ignored");
        puts("Preview source: primary clip/video, nested gap clocks, trim/boundary, bookmarks, disabled/audio-only and unsupported structures passed.");
        if (argc==4) {
            NSData *data=[NSData dataWithContentsOfFile:@(argv[1])];
            NSScanner *scanner=[NSScanner scannerWithString:@(argv[2])];double seconds=0;
            check([scanner scanDouble:&seconds] && scanner.isAtEnd,@"valid probe time");
            source=SubPopPreviewSource(data,seconds);check(source!=nil,@"real project resolves primary picture");
            AVAssetImageGenerator *generator=[AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:source[@"url"] options:nil]];
            generator.appliesPreferredTrackTransform=YES;generator.maximumSize=CGSizeMake(960,540);
            generator.requestedTimeToleranceBefore=kCMTimeZero;generator.requestedTimeToleranceAfter=kCMTimeZero;
            NSError *error=nil;CMTime actual=kCMTimeInvalid;
            CGImageRef frame=[generator copyCGImageAtTime:CMTimeMakeWithSeconds([source[@"seconds"] doubleValue],60000) actualTime:&actual error:&error];
            check(frame!=NULL,[NSString stringWithFormat:@"real source frame decodes: %@",error.localizedDescription]);
            NSBitmapImageRep *image=[[NSBitmapImageRep alloc] initWithCGImage:frame];CGImageRelease(frame);
            check([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[3]) atomically:YES],@"decoded frame saved");
            printf("Real frame: project %.6fs -> media %.6fs; decoded %.6fs; %ld x %ld\n",seconds,[source[@"seconds"] doubleValue],CMTimeGetSeconds(actual),(long)image.pixelsWide,(long)image.pixelsHigh);
        } else check(argc==1,@"optional args: XML, project seconds, PNG output");
    }
    return 0;
}
