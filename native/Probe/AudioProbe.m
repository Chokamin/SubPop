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

NSDictionary *SubPopAudioFileInfo(NSURL *url) {
    if (!url.isFileURL) return Failure(@"local-audio-required",nil);
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:nil];
    dispatch_semaphore_t ready=dispatch_semaphore_create(0);
    __block NSArray<AVAssetTrack *> *tracks=nil;
    __block NSError *trackError=nil;
    [asset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> *loaded, NSError *error) {
        tracks=loaded;trackError=error;dispatch_semaphore_signal(ready);
    }];
    if (dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) return Failure(@"audio-track-timeout",nil);
    if (tracks.count!=1) return Failure(@"single-audio-track-required",trackError);
    dispatch_semaphore_t durationReady=dispatch_semaphore_create(0);
    __block CMTime duration=kCMTimeInvalid;
    __block NSError *durationError=nil;
    [asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
        duration=asset.duration;
        if ([asset statusOfValueForKey:@"duration" error:&durationError]!=AVKeyValueStatusLoaded) duration=kCMTimeInvalid;
        dispatch_semaphore_signal(durationReady);
    }];
    if (dispatch_semaphore_wait(durationReady,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) return Failure(@"duration-timeout",nil);
    if (!CMTIME_IS_NUMERIC(duration) || CMTimeGetSeconds(duration)<=0) return Failure(@"invalid-duration",durationError);
    return @{@"status":@"ready",@"durationValue":@(duration.value),@"durationScale":@(duration.timescale),@"audioTracks":@(tracks.count)};
}

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
    NSString *sourceEnable=Attr(clip,@"srcEnable");
    if (([clip attributeForName:@"srcEnable"] && ![sourceEnable isEqual:@"all"] && ![sourceEnable isEqual:@"audio"]) || [clip attributeForName:@"audioStart"] || [clip attributeForName:@"audioDuration"]) return Failure(@"unverified-source-audio",nil);
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
        // Only silence outside a verified audio track, within the real media
        // container, is padding. A truncated/missing media range still fails.
        dispatch_semaphore_t durationReady=dispatch_semaphore_create(0);
        __block CMTime containerDuration=kCMTimeInvalid;
        [avasset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
            NSError *durationError=nil;
            if ([avasset statusOfValueForKey:@"duration" error:&durationError]==AVKeyValueStatusLoaded) containerDuration=avasset.duration;
            dispatch_semaphore_signal(durationReady);
        }];
        if (dispatch_semaphore_wait(durationReady,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) { [result addEntriesFromDictionary:Failure(@"duration-timeout",nil)];return result; }
        CMTimeRange trackRange=tracks[0].timeRange;
        CMTime requestedEnd=CMTimeAdd(sourceStart,duration);
        if (!CMTIME_IS_NUMERIC(containerDuration) || !CMTIMERANGE_IS_VALID(trackRange)
            || !CMTIME_IS_NUMERIC(trackRange.start) || !CMTIME_IS_NUMERIC(trackRange.duration)
            || CMTimeCompare(trackRange.start,kCMTimeZero)<0 || CMTimeCompare(trackRange.duration,kCMTimeZero)<0
            || CMTimeCompare(requestedEnd,CMTimeAdd(containerDuration,CMTimeMake(1,20)))>0) {
            [result addEntriesFromDictionary:Failure(@"incomplete-project-audio",nil)];return result;
        }
        // AAC metadata may omit its last compressed packet (observed 22ms).
        // That is not proof of silence: decode the requested range and still
        // require all PCM. Only a track gap inside a longer container is padded.
        BOOL verifiedGap=CMTimeCompare(requestedEnd,containerDuration)<=0
            && (CMTimeCompare(trackRange.start,kCMTimeZero)>0
                || CMTimeCompare(CMTimeRangeGetEnd(trackRange),containerDuration)<0);
        CMTimeRange audioRange=verifiedGap ? CMTimeRangeGetIntersection(CMTimeRangeMake(sourceStart,duration),trackRange) : CMTimeRangeMake(sourceStart,duration);
        BOOL hasAudio=CMTIMERANGE_IS_VALID(audioRange) && CMTimeCompare(audioRange.duration,kCMTimeZero)>0;
        CMTime decodeStart=hasAudio ? audioRange.start : sourceStart;
        CMTime decodeDuration=hasAudio ? audioRange.duration : kCMTimeZero;
        result[@"sourceAudioStartSeconds"]=@(CMTimeGetSeconds(trackRange.start));
        result[@"sourceAudioDurationSeconds"]=@(CMTimeGetSeconds(trackRange.duration));
        error=nil;
        AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:avasset error:&error];
        if (!reader) { [result addEntriesFromDictionary:Failure(@"reader-init",error)]; return result; }
        reader.timeRange=CMTimeRangeMake(decodeStart,decodeDuration);
        AVAssetReaderTrackOutput *out=[[AVAssetReaderTrackOutput alloc] initWithTrack:tracks[0] outputSettings:@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@16000,AVNumberOfChannelsKey:@1,AVLinearPCMBitDepthKey:@32,AVLinearPCMIsFloatKey:@YES,AVLinearPCMIsNonInterleaved:@NO,AVLinearPCMIsBigEndianKey:@NO}];
        if (![reader canAddOutput:out]) { [result addEntriesFromDictionary:Failure(@"reader-output",nil)]; return result; }
        [reader addOutput:out];
        if (hasAudio && ![reader startReading]) { [result addEntriesFromDictionary:Failure(@"reader-start",reader.error)]; return result; }
        NSMutableData *pcm=[NSMutableData new];
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+20;
        while (hasAudio && reader.status==AVAssetReaderStatusReading) {
            if (CFAbsoluteTimeGetCurrent()>deadline || pcm.length>30*16000*4) { [reader cancelReading]; break; }
            CMSampleBufferRef sample=[out copyNextSampleBuffer];
            if (!sample) break;
            CMTime presentation=CMSampleBufferGetPresentationTimeStamp(sample);
            CMBlockBufferRef buffer=CMSampleBufferGetDataBuffer(sample);
            size_t length=buffer ? CMBlockBufferGetDataLength(buffer) : 0;
            NSMutableData *chunk=[NSMutableData dataWithLength:length];
            OSStatus status=buffer ? CMBlockBufferCopyDataBytes(buffer,0,length,chunk.mutableBytes) : -1;
            CFRelease(sample);
            if (status!=noErr) { [reader cancelReading]; break; }
            // Compressed packets may extend past reader.timeRange (AAC observed
            // 48 extra samples at a 30s boundary). Crop by output timestamps,
            // rather than treating a complete packet as project audio.
            if (!CMTIME_IS_NUMERIC(presentation) || length%4) { [reader cancelReading]; break; }
            int64_t first=CMTimeConvertScale(CMTimeSubtract(decodeStart,presentation),16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
            int64_t last=CMTimeConvertScale(CMTimeSubtract(CMTimeAdd(decodeStart,decodeDuration),presentation),16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
            first=MAX(0,first);last=MIN((int64_t)(length/4),last);
            if (last>first) [pcm appendBytes:(const char *)chunk.bytes+first*4 length:(NSUInteger)(last-first)*4];
        }
        if (hasAudio && (reader.status!=AVAssetReaderStatusCompleted || !pcm.length || pcm.length%4)) { [result addEntriesFromDictionary:Failure(@"decode",reader.error)]; result[@"readerStatus"]=@(reader.status);result[@"decodedSamples"]=@(pcm.length/4); return result; }
        int64_t expectedSamples=CMTimeConvertScale(duration,16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
        int64_t prefix=hasAudio ? CMTimeConvertScale(CMTimeSubtract(decodeStart,sourceStart),16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value : 0;
        int64_t end=hasAudio ? CMTimeConvertScale(CMTimeSubtract(CMTimeAdd(decodeStart,decodeDuration),sourceStart),16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value : 0;
        prefix=MAX(0,MIN(expectedSamples,prefix));end=MAX(prefix,MIN(expectedSamples,end));
        int64_t audibleSamples=end-prefix;
        int64_t sampleDelta=audibleSamples-(int64_t)(pcm.length/4);
        // Keep the existing 1ms converter-tail allowance inside the verified
        // audible range. Larger shortages never become invented silence.
        if (sampleDelta && llabs(sampleDelta)<=16) {
            result[@"resampleTailAdjustmentSamples"]=@(sampleDelta);
            [pcm setLength:(NSUInteger)audibleSamples*4];
        }
        if ((int64_t)(pcm.length/4)!=audibleSamples) { [result addEntriesFromDictionary:Failure(@"incomplete-project-audio",nil)]; result[@"sampleCount"]=@(pcm.length/4); result[@"expectedSampleCount"]=@(audibleSamples); return result; }
        if (audibleSamples!=expectedSamples) {
            NSMutableData *timeline=[NSMutableData dataWithLength:(NSUInteger)expectedSamples*4];
            if (pcm.length) memcpy((char *)timeline.mutableBytes+prefix*4,pcm.bytes,pcm.length);
            result[@"verifiedSilenceSamples"]=@(expectedSamples-audibleSamples);
            pcm=timeline;
        }
        NSString *name=[NSString stringWithFormat:@"audio-%@.f32le",NSUUID.UUID.UUIDString];
        error=nil;
        if (![pcm writeToURL:[outputDirectory URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]) { [result addEntriesFromDictionary:Failure(@"pcm-save",error)]; return result; }
        const float *samples=pcm.bytes; double energy=0; BOOL finite=YES;
        for (NSUInteger i=0;i<pcm.length/4;i++) { if (!isfinite(samples[i])) { finite=NO; break; } energy+=(double)samples[i]*samples[i]; }
        result[@"status"]=finite ? @"decoded" : @"invalid-pcm"; result[@"pcmFile"]=name; result[@"sampleRate"]=@16000; result[@"channels"]=@1; result[@"sampleCount"]=@(pcm.length/4); result[@"pcmBytes"]=@(pcm.length); result[@"rms"]=finite ? @(sqrt(energy/(pcm.length/4))) : @0;
        return result;
    } @finally { if (scoped) [url stopAccessingSecurityScopedResource]; }
}
