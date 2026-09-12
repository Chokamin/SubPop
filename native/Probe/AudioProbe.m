#import "AudioProbe.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

static NSDictionary *Failure(NSString *stage, NSError *error) {
    return @{ @"status":@"failed", @"stage":stage, @"errorDomain":error.domain ?: @"", @"errorCode":@(error.code), @"error":error.localizedDescription ?: @"unsupported fixture" };
}
static NSString *Attr(NSXMLElement *node, NSString *key) { return [node attributeForName:key].stringValue ?: @""; }
static CMTime ParseTime(NSString *text) {
    if (![text hasSuffix:@"s"]) return kCMTimeInvalid;
    NSArray *parts = [[text substringToIndex:text.length-1] componentsSeparatedByString:@"/"];
    if (parts.count < 1 || parts.count > 2) return kCMTimeInvalid;
    long long numerator=0, denominator=1;
    NSScanner *n=[NSScanner scannerWithString:parts[0]];
    if (![n scanLongLong:&numerator] || !n.isAtEnd) return kCMTimeInvalid;
    if (parts.count==2) {
        NSScanner *d=[NSScanner scannerWithString:parts[1]];
        if (![d scanLongLong:&denominator] || !d.isAtEnd) return kCMTimeInvalid;
    }
    if (denominator<=0 || denominator>INT32_MAX) return kCMTimeInvalid;
    return CMTimeMake(numerator,(int32_t)denominator);
}
static BOOL EqualTime(CMTime a, CMTime b) { return CMTIME_IS_NUMERIC(a) && CMTIME_IS_NUMERIC(b) && CMTimeCompare(a,b)==0; }

NSDictionary *SubPopProbeAudio(NSData *xml, NSString *expectedUID, NSURL *outputDirectory) {
    if (!xml.length || xml.length>16*1024*1024) return Failure(@"xml-size",nil);
    NSError *error=nil;
    NSXMLDocument *doc=[[NSXMLDocument alloc] initWithData:xml options:NSXMLNodeLoadExternalEntitiesNever error:&error];
    if (!doc) return Failure(@"xml-parse",error);
    NSArray *projects=[doc nodesForXPath:@"/fcpxml/project | /fcpxml/library/event/project" error:&error];
    if (projects.count!=1) return Failure(@"single-project-required",error);
    NSXMLElement *project=projects[0];
    if (!expectedUID.length || ![Attr(project,@"uid") isEqual:expectedUID]) return Failure(@"active-project-uid-mismatch",nil);
    NSArray *sequences=[project elementsForName:@"sequence"];
    if (sequences.count!=1) return Failure(@"single-sequence-required",nil);
    NSXMLElement *sequence=sequences[0];
    NSArray *spines=[sequence elementsForName:@"spine"];
    if (spines.count!=1) return Failure(@"single-spine-required",nil);
    NSArray *clips=[spines[0] nodesForXPath:@"*" error:nil];
    if (clips.count!=1 || ![[clips[0] name] isEqual:@"asset-clip"]) return Failure(@"plain-clip-required",nil);
    NSXMLElement *clip=clips[0];
    if ([[clip nodesForXPath:@"*[not(self::caption)]" error:nil] count] || [Attr(clip,@"enabled") isEqual:@"0"] || ![Attr(clip,@"audioRole") isEqual:@"dialogue"]) return Failure(@"unverified-clip-features",nil);
    NSXMLElement *asset=nil;
    for (NSXMLElement *candidate in [doc nodesForXPath:@"/fcpxml/resources/asset" error:nil]) {
        if ([Attr(candidate,@"id") isEqual:Attr(clip,@"ref")]) { asset=candidate; break; }
    }
    if (!asset || ![Attr(asset,@"hasAudio") isEqual:@"1"]) return Failure(@"audio-asset-required",nil);
    NSArray *media=[asset nodesForXPath:@"media-rep[@kind='original-media']" error:nil];
    if (media.count!=1) return Failure(@"single-media-required",nil);
    CMTime duration=ParseTime(Attr(sequence,@"duration"));
    CMTime assetStart=ParseTime(Attr(asset,@"start").length ? Attr(asset,@"start") : @"0s");
    CMTime clipStart=ParseTime(Attr(clip,@"start").length ? Attr(clip,@"start") : (Attr(asset,@"start").length ? Attr(asset,@"start") : @"0s"));
    CMTime sourceStart=CMTimeSubtract(clipStart,assetStart);
    if (!CMTIME_IS_NUMERIC(duration) || CMTimeGetSeconds(duration)<=0 || CMTimeGetSeconds(duration)>30 || !CMTIME_IS_NUMERIC(sourceStart) || CMTimeGetSeconds(sourceStart)<0 || !EqualTime(duration,ParseTime(Attr(clip,@"duration"))) || !EqualTime(ParseTime(Attr(clip,@"offset")),ParseTime(Attr(sequence,@"tcStart")))) return Failure(@"full-project-coverage-required",nil);
    NSXMLElement *rep=media[0];
    NSURL *url=[NSURL URLWithString:Attr(rep,@"src")];
    if (!url.isFileURL || (url.host.length && ![url.host isEqual:@"localhost"])) return Failure(@"local-media-required",nil);
    NSMutableDictionary *result=[@{@"projectUID":expectedUID,@"projectName":Attr(project,@"name"),@"sourceURL":url.absoluteString,@"durationSeconds":@(CMTimeGetSeconds(duration)),@"sourceStartSeconds":@(CMTimeGetSeconds(sourceStart)),@"scope":@"full active project; plain fixture only",@"audibility":@"unknown: source PCM is not verified final timeline mix"} mutableCopy];
    NSFileHandle *direct=[NSFileHandle fileHandleForReadingFromURL:url error:&error];
    result[@"directOpen"]=@(direct!=nil); result[@"directOpenErrorCode"]=@(error.code);
    [direct closeFile];
    NSString *bookmark=[[rep elementsForName:@"bookmark"].firstObject stringValue];
    NSData *bookmarkData=[[NSData alloc] initWithBase64EncodedString:bookmark ?: @"" options:NSDataBase64DecodingIgnoreUnknownCharacters];
    BOOL stale=NO, scoped=NO;
    if (bookmarkData.length) {
        error=nil;
        NSURL *resolved=[NSURL URLByResolvingBookmarkData:bookmarkData options:NSURLBookmarkResolutionWithSecurityScope|NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
        result[@"bookmarkResolved"]=@(resolved!=nil); result[@"bookmarkErrorCode"]=@(error.code); result[@"bookmarkStale"]=@(stale);
        if (resolved.isFileURL) { url=resolved; scoped=[url startAccessingSecurityScopedResource]; }
    }
    result[@"securityScopeStarted"]=@(scoped);
    @try {
        AVURLAsset *avasset=[AVURLAsset URLAssetWithURL:url options:nil];
        dispatch_semaphore_t ready=dispatch_semaphore_create(0);
        __block NSArray<AVAssetTrack *> *tracks=nil;
        __block NSError *loadError=nil;
        [avasset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> *loaded, NSError *err) { tracks=loaded; loadError=err; dispatch_semaphore_signal(ready); }];
        if (dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) { [result addEntriesFromDictionary:Failure(@"audio-track-timeout",nil)]; return result; }
        if (tracks.count!=1) { [result addEntriesFromDictionary:Failure(@"single-audio-track-required",loadError)]; return result; }
        error=nil;
        AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:avasset error:&error];
        if (!reader) { [result addEntriesFromDictionary:Failure(@"reader-init",error)]; return result; }
        reader.timeRange=CMTimeRangeMake(sourceStart,duration);
        AVAssetReaderTrackOutput *out=[[AVAssetReaderTrackOutput alloc] initWithTrack:tracks[0] outputSettings:@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@16000,AVNumberOfChannelsKey:@1,AVLinearPCMBitDepthKey:@32,AVLinearPCMIsFloatKey:@YES,AVLinearPCMIsNonInterleaved:@NO,AVLinearPCMIsBigEndianKey:@NO}];
        if (![reader canAddOutput:out]) { [result addEntriesFromDictionary:Failure(@"reader-output",nil)]; return result; }
        [reader addOutput:out];
        if (![reader startReading]) { [result addEntriesFromDictionary:Failure(@"reader-start",reader.error)]; return result; }
        NSMutableData *pcm=[NSMutableData new];
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+20;
        while (reader.status==AVAssetReaderStatusReading) {
            if (CFAbsoluteTimeGetCurrent()>deadline || pcm.length>30*16000*4) { [reader cancelReading]; break; }
            CMSampleBufferRef sample=[out copyNextSampleBuffer];
            if (!sample) break;
            CMBlockBufferRef buffer=CMSampleBufferGetDataBuffer(sample);
            size_t length=buffer ? CMBlockBufferGetDataLength(buffer) : 0;
            NSMutableData *chunk=[NSMutableData dataWithLength:length];
            OSStatus status=buffer ? CMBlockBufferCopyDataBytes(buffer,0,length,chunk.mutableBytes) : -1;
            CFRelease(sample);
            if (status!=noErr) { [reader cancelReading]; break; }
            [pcm appendData:chunk];
        }
        if (reader.status!=AVAssetReaderStatusCompleted || !pcm.length || pcm.length%4) { [result addEntriesFromDictionary:Failure(@"decode",reader.error)]; return result; }
        int64_t expectedSamples=CMTimeConvertScale(duration,16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
        if ((int64_t)(pcm.length/4)!=expectedSamples) { [result addEntriesFromDictionary:Failure(@"incomplete-project-audio",nil)]; result[@"sampleCount"]=@(pcm.length/4); result[@"expectedSampleCount"]=@(expectedSamples); return result; }
        NSString *name=[NSString stringWithFormat:@"audio-%@.f32le",NSUUID.UUID.UUIDString];
        error=nil;
        if (![pcm writeToURL:[outputDirectory URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]) { [result addEntriesFromDictionary:Failure(@"pcm-save",error)]; return result; }
        const float *samples=pcm.bytes; double energy=0; BOOL finite=YES;
        for (NSUInteger i=0;i<pcm.length/4;i++) { if (!isfinite(samples[i])) { finite=NO; break; } energy+=(double)samples[i]*samples[i]; }
        result[@"status"]=finite ? @"decoded" : @"invalid-pcm"; result[@"pcmFile"]=name; result[@"sampleRate"]=@16000; result[@"channels"]=@1; result[@"sampleCount"]=@(pcm.length/4); result[@"pcmBytes"]=@(pcm.length); result[@"rms"]=finite ? @(sqrt(energy/(pcm.length/4))) : @0;
        return result;
    } @finally { if (scoped) [url stopAccessingSecurityScopedResource]; }
}
