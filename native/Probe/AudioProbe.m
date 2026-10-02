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

static BOOL Absent(id value) { return !value || value==NSNull.null; }
static BOOL Number(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID();
}
static BOOL PositiveInteger(id value) {
    return Number(value) && isfinite([value doubleValue]) && [value doubleValue]>=1
        && [value doubleValue]<=INT32_MAX && [value doubleValue]==[value longLongValue];
}

static NSDictionary *TrackMetadata(AVURLAsset *asset, NSArray<AVAssetTrack *> *tracks) {
    if (!tracks.count) return Failure(@"audio-track-required",nil);
    if (tracks.count>32) return Failure(@"unsupported-channel-layout",nil);
    NSMutableArray *details=[NSMutableArray new];NSUInteger total=0;
    BOOL fallback=NO,enabled=YES;
    for (AVAssetTrack *track in tracks) {
        dispatch_semaphore_t ready=dispatch_semaphore_create(0);
        [track loadValuesAsynchronouslyForKeys:@[@"formatDescriptions",@"timeRange",@"availableTrackAssociationTypes"] completionHandler:^{dispatch_semaphore_signal(ready);}];
        if (dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) return Failure(@"audio-format-timeout",nil);
        NSError *error=nil;
        if ([track statusOfValueForKey:@"formatDescriptions" error:&error]!=AVKeyValueStatusLoaded
            || [track statusOfValueForKey:@"timeRange" error:&error]!=AVKeyValueStatusLoaded
            || [track statusOfValueForKey:@"availableTrackAssociationTypes" error:&error]!=AVKeyValueStatusLoaded) return Failure(@"audio-format-required",error);
        UInt32 channels=0;double sampleRate=0;
        for (id value in track.formatDescriptions) {
            const AudioStreamBasicDescription *description=CMAudioFormatDescriptionGetStreamBasicDescription((__bridge CMAudioFormatDescriptionRef)value);
            if (!description || !description->mChannelsPerFrame || description->mChannelsPerFrame>64) return Failure(@"unsupported-channel-layout",nil);
            if (channels && channels!=description->mChannelsPerFrame) return Failure(@"audio-layout-conflict",nil);
            if (!isfinite(description->mSampleRate) || description->mSampleRate<8000 || description->mSampleRate>384000
                || description->mSampleRate!=round(description->mSampleRate)) return Failure(@"unsupported-channel-layout",nil);
            if (sampleRate && sampleRate!=description->mSampleRate) return Failure(@"audio-layout-conflict",nil);
            channels=description->mChannelsPerFrame;
            sampleRate=description->mSampleRate;
        }
        CMTimeRange range=track.timeRange;
        if (!channels) return Failure(@"audio-format-required",nil);
        if (!CMTIMERANGE_IS_VALID(range) || !CMTIME_IS_NUMERIC(range.start) || !CMTIME_IS_NUMERIC(range.duration)
            || CMTimeCompare(range.start,kCMTimeZero)<0 || CMTimeCompare(range.duration,kCMTimeZero)<0) return Failure(@"audio-format-required",nil);
        for (AVTrackAssociationType type in track.availableTrackAssociationTypes) {
            dispatch_semaphore_t associatedReady=dispatch_semaphore_create(0);
            __block NSArray<AVAssetTrack *> *associated=nil;__block NSError *associatedError=nil;
            [track loadAssociatedTracksOfType:type completionHandler:^(NSArray<AVAssetTrack *> *loaded,NSError *err) {
                associated=loaded;associatedError=err;dispatch_semaphore_signal(associatedReady);
            }];
            if (dispatch_semaphore_wait(associatedReady,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) return Failure(@"audio-format-timeout",nil);
            if (associatedError) return Failure(@"audio-format-required",associatedError);
            for (AVAssetTrack *other in associated) {
                if ([other.mediaType isEqual:AVMediaTypeAudio]) fallback=YES;
            }
        }
        enabled &= track.isEnabled;
        [details addObject:@{@"sourceIndex":@(details.count+1),@"trackID":@(track.trackID),@"channels":@(channels),@"sampleRate":@(sampleRate),
            @"firstChannel":@(total+1),@"lastChannel":@(total+channels),@"enabled":@(track.isEnabled),
            @"startValue":@(range.start.value),@"startScale":@(range.start.timescale),
            @"durationValue":@(range.duration.value),@"durationScale":@(range.duration.timescale)}];
        total+=channels;
        if (total>64) return Failure(@"unsupported-channel-layout",nil);
    }
    dispatch_semaphore_t selectionReady=dispatch_semaphore_create(0);
    __block AVMediaSelectionGroup *group=nil;__block NSError *selectionError=nil;
    [asset loadMediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible completionHandler:^(AVMediaSelectionGroup *loaded,NSError *error) {
        group=loaded;selectionError=error;dispatch_semaphore_signal(selectionReady);
    }];
    if (dispatch_semaphore_wait(selectionReady,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) return Failure(@"audio-format-timeout",nil);
    if (selectionError) return Failure(@"audio-format-required",selectionError);
    BOOL alternate=group.options.count>1;
    return @{@"status":@"ready",@"audioTracks":@(tracks.count),@"audioChannels":@(total),@"tracks":details,
        @"hasAudioAssociations":@(fallback),@"hasAlternateAudio":@(alternate),@"allTracksEnabled":@(enabled)};
}

static NSDictionary *ValidateMix(NSDictionary *mix, NSDictionary *metadata) {
    if (mix && ![mix isKindOfClass:NSDictionary.class]) return Failure(@"invalid-channel-selection",nil);
    NSSet *allowed=[NSSet setWithArray:@[@"components",@"sourceID",@"expectedChannels",@"expectedSources"]];
    for (NSString *key in mix) if (![allowed containsObject:key]) return Failure(@"invalid-channel-selection",nil);
    NSArray *tracks=metadata[@"tracks"];
    for (NSString *key in @[@"expectedChannels",@"expectedSources"]) {
        id value=mix[key];
        if (Absent(value)) continue;
        if (!PositiveInteger(value)) return Failure(@"invalid-channel-selection",nil);
        if ([key isEqual:@"expectedSources"]) {
            if ([value unsignedIntegerValue]!=tracks.count) return Failure(@"audio-layout-conflict",nil);
        } else {
            for (NSDictionary *track in tracks) if ([value unsignedIntegerValue]!=[track[@"channels"] unsignedIntegerValue]) return Failure(@"audio-layout-conflict",nil);
        }
    }
    id source=mix[@"sourceID"];NSInteger sourceIndex=-1;
    if (!Absent(source)) {
        if (![source isKindOfClass:NSString.class] || ![source length] || [source length]>10) return Failure(@"unverified-audio-source-id",nil);
        long long index=0;NSScanner *scanner=[NSScanner scannerWithString:source];
        if (![scanner scanLongLong:&index] || !scanner.isAtEnd || index<1 || index>(long long)tracks.count
            || ![source isEqual:[@(index) stringValue]]) return Failure(@"unverified-audio-source-id",nil);
        sourceIndex=(NSInteger)index-1;
    }
    id components=mix[@"components"];
    if (Absent(components)) {
        if ([metadata[@"hasAudioAssociations"] boolValue]
            || (sourceIndex<0 && tracks.count>1 && ([metadata[@"hasAlternateAudio"] boolValue] || ![metadata[@"allTracksEnabled"] boolValue])))
            return Failure(@"ambiguous-audio-tracks",nil);
        return @{@"status":@"ready",@"defaultDownmix":@YES,@"legacyGain":@1,@"sourceIndex":@(sourceIndex)};
    }
    if (![components isKindOfClass:NSArray.class]) return Failure(@"invalid-channel-selection",nil);
    // Explicit FCP selection takes precedence over a container's alternate
    // group/enabled flags. Audio fallback associations still cannot be mixed.
    if ([metadata[@"hasAudioAssociations"] boolValue]) return Failure(@"ambiguous-audio-tracks",nil);
    NSUInteger count=sourceIndex<0 ? [metadata[@"audioChannels"] unsignedIntegerValue] : [tracks[sourceIndex][@"channels"] unsignedIntegerValue];
    NSMutableSet *seen=[NSMutableSet new];
    for (id item in components) {
        if (![item isKindOfClass:NSDictionary.class] || [item count]!=2 || ![item[@"channels"] isKindOfClass:NSArray.class]
            || ![item[@"channels"] count] || !Number(item[@"gain"]) || !isfinite([item[@"gain"] doubleValue])
            || [item[@"gain"] doubleValue]<0 || [item[@"gain"] doubleValue]>1e6)
            return Failure(@"invalid-channel-selection",nil);
        for (NSNumber *channel in item[@"channels"]) {
            if (!PositiveInteger(channel) || channel.unsignedIntegerValue>count || [seen containsObject:channel]) return Failure(@"invalid-channel-selection",nil);
            [seen addObject:channel];
        }
    }
    NSMutableDictionary *result=[@{@"status":@"ready",@"defaultDownmix":@NO,@"components":components,@"sourceIndex":@(sourceIndex)} mutableCopy];
    // Explicit components always mean arithmetic group averages. AVFoundation
    // uses its own (e.g. equal-power stereo) default downmix, so that path is
    // reserved for a genuinely unspecified component selection.
    return result;
}

static NSMutableDictionary *PCMResult(NSMutableDictionary *result, NSMutableData *pcm, NSURL *outputDirectory) {
    const float *samples=pcm.bytes;double energy=0;
    if (!pcm.length || pcm.length%4) { [result addEntriesFromDictionary:Failure(@"invalid-pcm",nil)];return result; }
    for (NSUInteger i=0;i<pcm.length/4;i++) {
        if (!isfinite(samples[i])) { [result addEntriesFromDictionary:Failure(@"invalid-pcm",nil)];return result; }
        energy+=(double)samples[i]*samples[i];
    }
    NSString *name=[NSString stringWithFormat:@"audio-%@.f32le",NSUUID.UUID.UUIDString];NSError *error=nil;
    if (![pcm writeToURL:[outputDirectory URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]) {
        [result addEntriesFromDictionary:Failure(@"pcm-save",error)];return result;
    }
    [result addEntriesFromDictionary:@{@"status":@"decoded",@"pcmFile":name,@"sampleRate":@16000,@"channels":@1,
        @"sampleCount":@(pcm.length/4),@"pcmBytes":@(pcm.length),@"rms":@(sqrt(energy/(pcm.length/4)))}];
    return result;
}

static NSData *Mono16k(NSData *source, NSUInteger sourceRate, NSUInteger expected, NSError **error) {
    if (sourceRate==16000 && source.length==expected*4) return source;
    AVAudioFormat *inputFormat=[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:sourceRate channels:1 interleaved:YES];
    AVAudioFormat *outputFormat=[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:16000 channels:1 interleaved:YES];
    AVAudioPCMBuffer *input=[[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFormat frameCapacity:(AVAudioFrameCount)(source.length/4)];
    AVAudioPCMBuffer *output=[[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat frameCapacity:(AVAudioFrameCount)(expected+64)];
    AVAudioConverter *converter=[[AVAudioConverter alloc] initFromFormat:inputFormat toFormat:outputFormat];
    if (!input || !output || !converter) return nil;
    // Normal primes trailing frames without output latency; None would add
    // through-latency at the beginning of the converted sound clock.
    converter.primeMethod=AVAudioConverterPrimeMethod_Normal;
    input.frameLength=(AVAudioFrameCount)(source.length/4);
    memcpy(input.floatChannelData[0],source.bytes,source.length);
    // Feed one continuous sample clock. AVAssetReader's direct SRC can adjust
    // PCM repeatedly to rounded MOV packet times and accumulate phase drift.
    __block BOOL supplied=NO;
    AVAudioConverterInputBlock provide=^AVAudioBuffer *(AVAudioPacketCount packets, AVAudioConverterInputStatus *inputStatus) {
        (void)packets;
        if (supplied) { *inputStatus=AVAudioConverterInputStatus_EndOfStream;return nil; }
        supplied=YES;*inputStatus=AVAudioConverterInputStatus_HaveData;return input;
    };
    NSMutableData *converted=[NSMutableData new];BOOL drained=NO;
    for (NSUInteger iteration=0;iteration<8;iteration++) {
        output.frameLength=0;
        AVAudioConverterOutputStatus status=[converter convertToBuffer:output error:error withInputFromBlock:provide];
        if (status==AVAudioConverterOutputStatus_Error || status==AVAudioConverterOutputStatus_InputRanDry || (error && *error)) return nil;
        if (converted.length/4+output.frameLength>expected+16) return nil;
        [converted appendBytes:output.floatChannelData[0] length:output.frameLength*4];
        if (status==AVAudioConverterOutputStatus_EndOfStream) { drained=YES;break; }
        if (!output.frameLength) return nil;
    }
    if (!drained || converted.length/4+16<expected) return nil;
    NSMutableData *pcm=[NSMutableData dataWithLength:expected*4];
    memcpy(pcm.mutableBytes,converted.bytes,MIN(expected*4,converted.length));
    return pcm;
}

static NSDictionary *DecodeChannels(AVURLAsset *asset, NSArray<AVAssetTrack *> *tracks, NSDictionary *metadata,
    NSDictionary *mix, CMTime start, CMTime duration, CMTime containerDuration, NSURL *directory, NSMutableDictionary *result) {
    CMTime end=CMTimeAdd(start,duration);
    int64_t expected=CMTimeConvertScale(duration,16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
    if (!CMTIME_IS_NUMERIC(containerDuration) || CMTimeCompare(end,CMTimeAdd(containerDuration,CMTimeMake(1,20)))>0 || expected<=0)
        { [result addEntriesFromDictionary:Failure(@"incomplete-project-audio",nil)];return result; }
    NSMutableData *pcm=[NSMutableData dataWithLength:(NSUInteger)expected*4];
    float *output=pcm.mutableBytes;CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+20;
    NSUInteger totalDecoded=0,totalTail=0;BOOL useDefault=[mix[@"defaultDownmix"] boolValue];
    for (NSUInteger index=0;index<tracks.count;index++) {
      @autoreleasepool {
        NSInteger selectedSource=[mix[@"sourceIndex"] integerValue];
        if (selectedSource>=0 && index!=(NSUInteger)selectedSource) continue;
        AVAssetTrack *track=tracks[index];NSUInteger channels=[metadata[@"tracks"][index][@"channels"] unsignedIntegerValue];
        NSUInteger sourceRate=[metadata[@"tracks"][index][@"sampleRate"] unsignedIntegerValue];
        int64_t sourceFrames=CMTimeConvertScale(duration,(int32_t)sourceRate,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
        NSUInteger firstChannel=[metadata[@"tracks"][index][@"firstChannel"] unsignedIntegerValue];
        NSMutableData *weightData=[NSMutableData dataWithLength:channels*sizeof(double)];double *weights=weightData.mutableBytes;
        BOOL selected=useDefault;
        if (!useDefault) for (NSDictionary *component in mix[@"components"]) {
            double weight=[component[@"gain"] doubleValue]/[component[@"channels"] count];
            for (NSNumber *channel in component[@"channels"]) {
                NSUInteger number=channel.unsignedIntegerValue+(selectedSource>=0 ? firstChannel-1 : 0);
                if (number>=firstChannel && number<firstChannel+channels) { weights[number-firstChannel]=weight;selected=YES; }
            }
        }
        if (!selected) continue;
        CMTimeRange trackRange=track.timeRange;
        BOOL verifiedGap=CMTimeCompare(end,containerDuration)<=0
            && (CMTimeCompare(trackRange.start,kCMTimeZero)>0 || CMTimeCompare(CMTimeRangeGetEnd(trackRange),containerDuration)<0);
        CMTimeRange range=verifiedGap ? CMTimeRangeGetIntersection(CMTimeRangeMake(start,duration),trackRange) : CMTimeRangeMake(start,duration);
        if (!CMTIMERANGE_IS_VALID(range) || CMTimeCompare(range.duration,kCMTimeZero)<=0) continue;
        int64_t first=CMTimeConvertScale(CMTimeSubtract(range.start,start),(int32_t)sourceRate,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
        int64_t last=CMTimeConvertScale(CMTimeSubtract(CMTimeRangeGetEnd(range),start),(int32_t)sourceRate,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
        first=MAX(0,MIN(sourceFrames,first));last=MAX(first,MIN(sourceFrames,last));
        NSUInteger targetChannels=useDefault ? 1 : channels;
        NSMutableDictionary *settings=[@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@(sourceRate),AVNumberOfChannelsKey:@(targetChannels),
            AVLinearPCMBitDepthKey:@32,AVLinearPCMIsFloatKey:@YES,AVLinearPCMIsNonInterleaved:@NO,AVLinearPCMIsBigEndianKey:@NO} mutableCopy];
        if (targetChannels>2) {
            id description=track.formatDescriptions.firstObject;size_t size=0;
            const AudioChannelLayout *layout=CMAudioFormatDescriptionGetChannelLayout((__bridge CMAudioFormatDescriptionRef)description,&size);
            if (layout && size) settings[AVChannelLayoutKey]=[NSData dataWithBytes:layout length:size];
            else {
                AudioChannelLayout discrete={0};discrete.mChannelLayoutTag=kAudioChannelLayoutTag_DiscreteInOrder|(UInt32)targetChannels;
                settings[AVChannelLayoutKey]=[NSData dataWithBytes:&discrete length:sizeof(discrete)];
            }
        }
        NSError *error=nil;AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:asset error:&error];
        if (!reader) { [result addEntriesFromDictionary:Failure(@"reader-init",error)];return result; }
        reader.timeRange=range;
        AVAssetReaderTrackOutput *trackOutput=[[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
        if (![reader canAddOutput:trackOutput]) { [result addEntriesFromDictionary:Failure(@"reader-output",nil)];return result; }
        [reader addOutput:trackOutput];
        if (![reader startReading]) { [result addEntriesFromDictionary:Failure(@"reader-start",reader.error)];return result; }
        NSMutableData *coveredData=[NSMutableData dataWithLength:(NSUInteger)sourceFrames];unsigned char *covered=coveredData.mutableBytes;
        NSMutableData *trackPCM=[NSMutableData dataWithLength:(NSUInteger)sourceFrames*4];float *values=trackPCM.mutableBytes;
        BOOL invalid=NO;NSUInteger filled=0;CMTime previous=kCMTimeInvalid;
        while (reader.status==AVAssetReaderStatusReading) {
            if (CFAbsoluteTimeGetCurrent()>deadline) { [reader cancelReading];break; }
            CMSampleBufferRef sample=[trackOutput copyNextSampleBuffer];if (!sample) break;
            CMTime presentation=CMSampleBufferGetPresentationTimeStamp(sample);
            const AudioStreamBasicDescription *format=CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample));
            CMBlockBufferRef buffer=CMSampleBufferGetDataBuffer(sample);size_t length=buffer ? CMBlockBufferGetDataLength(buffer) : 0;
            CMItemCount frames=CMSampleBufferGetNumSamples(sample);
            if (!CMTIME_IS_NUMERIC(presentation) || (CMTIME_IS_NUMERIC(previous) && CMTimeCompare(presentation,previous)<0)
                || !format || format->mChannelsPerFrame!=targetChannels || format->mSampleRate!=sourceRate
                || format->mFormatID!=kAudioFormatLinearPCM || !(format->mFormatFlags&kAudioFormatFlagIsFloat)
                || (format->mFormatFlags&kAudioFormatFlagIsNonInterleaved) || format->mBitsPerChannel!=32
                || frames<0 || (uint64_t)frames>31*sourceRate || length!=(size_t)frames*targetChannels*4) {
                CFRelease(sample);invalid=YES;[reader cancelReading];break;
            }
            previous=presentation;NSMutableData *chunk=[NSMutableData dataWithLength:length];
            OSStatus status=buffer ? CMBlockBufferCopyDataBytes(buffer,0,length,chunk.mutableBytes) : -1;CFRelease(sample);
            if (status!=noErr) { invalid=YES;[reader cancelReading];break; }
            int64_t base=CMTimeConvertScale(CMTimeSubtract(presentation,start),(int32_t)sourceRate,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
            int64_t begin=MAX(0,first-base),finish=MIN((int64_t)frames,last-base);const float *source=chunk.bytes;
            for (int64_t frame=begin;frame<finish;frame++) {
                int64_t position=base+frame;double value=0;
                if (useDefault) value=source[frame];
                else for (NSUInteger channel=0;channel<channels;channel++) value+=(double)source[frame*channels+channel]*weights[channel];
                if (!isfinite(value)) { invalid=YES;break; }
                if (!covered[position]) { covered[position]=1;filled++;values[position]=(float)value; }
            }
            if (invalid) { [reader cancelReading];break; }
        }
        if (invalid || reader.status!=AVAssetReaderStatusCompleted || !filled) {
            [result addEntriesFromDictionary:Failure(@"decode",reader.error)];result[@"readerStatus"]=@(reader.status);return result;
        }
        NSUInteger missing=0;int64_t firstMissing=last;
        for (int64_t sample=first;sample<last;sample++) if (!covered[sample]) { missing++;firstMissing=MIN(firstMissing,sample); }
        // Only the established <=1ms resampler tail allowance is padding inside
        // a real track. Never fill an interior PCM hole or a failed reader.
        NSUInteger tailAllowance=(sourceRate+999)/1000;
        if (missing && (missing>tailAllowance || firstMissing<last-(int64_t)tailAllowance || firstMissing+(int64_t)missing!=last)) {
            [result addEntriesFromDictionary:Failure(@"incomplete-project-audio",nil)];result[@"decodedSamples"]=@(filled);result[@"expectedSampleCount"]=@(last-first);return result;
        }
        totalTail+=(NSUInteger)llround((double)missing*16000/sourceRate);totalDecoded+=filled;
        NSData *resampled=Mono16k(trackPCM,sourceRate,(NSUInteger)expected,&error);
        if (!resampled) { [result addEntriesFromDictionary:Failure(@"resample",error)];return result; }
        const float *resampledValues=resampled.bytes;
        int64_t outputFirst=CMTimeConvertScale(CMTimeSubtract(range.start,start),16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
        int64_t outputLast=CMTimeConvertScale(CMTimeSubtract(CMTimeRangeGetEnd(range),start),16000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
        // SRC filter ringing is not media outside the verified audible track.
        // Preserve exact leading/trailing silence proved by the container.
        for (int64_t sample=MAX(0,outputFirst);sample<MIN(expected,outputLast);sample++) output[sample]+=resampledValues[sample];
      }
    }
    result[@"decodedTrackSamples"]=@(totalDecoded);result[@"resampleTailAdjustmentSamples"]=@(totalTail);
    result[@"channelMixMode"]=useDefault ? @"actual-track-default-downmix" : @"selected-source-components";
    return PCMResult(result,pcm,directory);
}

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
    if (!tracks.count) return Failure(@"audio-track-required",trackError);
    NSDictionary *metadata=TrackMetadata(asset,tracks);
    if (![metadata[@"status"] isEqual:@"ready"]) return metadata;
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
    NSMutableDictionary *info=[metadata mutableCopy];info[@"durationValue"]=@(duration.value);info[@"durationScale"]=@(duration.timescale);return info;
}

NSDictionary *SubPopProbeAudioChannels(NSData *xml, NSString *expectedUID, NSURL *outputDirectory, NSDictionary *channelMix) {
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
        if (!tracks.count) { [result addEntriesFromDictionary:Failure(@"audio-track-required",loadError)]; return result; }
        NSDictionary *metadata=TrackMetadata(avasset,tracks);
        if (![metadata[@"status"] isEqual:@"ready"]) { [result addEntriesFromDictionary:metadata];return result; }
        [result addEntriesFromDictionary:metadata];
        NSMutableDictionary *requested=channelMix ? [channelMix mutableCopy] : [NSMutableDictionary new];
        if (!channelMix) {
            // A bare fixture still has explicit XML claims. Check them against
            // the file; missing claims remain unknown rather than becoming 1/2.
            for (NSArray *pair in @[@[@"audioChannels",@"expectedChannels"],@[@"audioSources",@"expectedSources"]]) {
                NSString *value=Attr(asset,pair[0]);
                if (!value.length) continue;
                NSScanner *scanner=[NSScanner scannerWithString:value];long long count=0;
                if (![scanner scanLongLong:&count] || !scanner.isAtEnd || count<=0 || count>INT32_MAX) { [result addEntriesFromDictionary:Failure(@"audio-layout-conflict",nil)];return result; }
                requested[pair[1]]=@(count);
            }
        }
        NSDictionary *mix=ValidateMix(requested,metadata);
        if (![mix[@"status"] isEqual:@"ready"]) { [result addEntriesFromDictionary:mix];return result; }
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
        NSUInteger sourceChannels=[metadata[@"tracks"][0][@"channels"] unsignedIntegerValue];
        BOOL legacy=tracks.count==1 && sourceChannels<=2 && mix[@"legacyGain"];
        if (!legacy) return DecodeChannels(avasset,tracks,metadata,mix,sourceStart,duration,containerDuration,outputDirectory,result);
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
        double channelGain=[mix[@"legacyGain"] doubleValue];
        if (channelGain!=1.0) {
            float *values=pcm.mutableBytes;
            for (NSUInteger sample=0;sample<pcm.length/4;sample++) values[sample]=(float)((double)values[sample]*channelGain);
        }
        result[@"channelMixMode"]=@"legacy-mono-stereo-downmix";
        NSString *name=[NSString stringWithFormat:@"audio-%@.f32le",NSUUID.UUID.UUIDString];
        error=nil;
        if (![pcm writeToURL:[outputDirectory URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]) { [result addEntriesFromDictionary:Failure(@"pcm-save",error)]; return result; }
        const float *samples=pcm.bytes; double energy=0; BOOL finite=YES;
        for (NSUInteger i=0;i<pcm.length/4;i++) { if (!isfinite(samples[i])) { finite=NO; break; } energy+=(double)samples[i]*samples[i]; }
        result[@"status"]=finite ? @"decoded" : @"invalid-pcm"; result[@"pcmFile"]=name; result[@"sampleRate"]=@16000; result[@"channels"]=@1; result[@"sampleCount"]=@(pcm.length/4); result[@"pcmBytes"]=@(pcm.length); result[@"rms"]=finite ? @(sqrt(energy/(pcm.length/4))) : @0;
        return result;
    } @finally { if (scoped) [url stopAccessingSecurityScopedResource]; }
}

NSDictionary *SubPopProbeAudio(NSData *xml, NSString *expectedUID, NSURL *outputDirectory) {
    return SubPopProbeAudioChannels(xml,expectedUID,outputDirectory,nil);
}
