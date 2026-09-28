#import <Cocoa/Cocoa.h>
#import <limits.h>

static NSError *SubPopCaptionExportError(NSString *message) {
    return [NSError errorWithDomain:@"SubPopCaptionExport" code:1
                           userInfo:@{NSLocalizedDescriptionKey:message}];
}

static BOOL SubPopParseFrameDuration(NSString *value, long long *numerator, long long *denominator) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSArray<NSString *> *parts=[value componentsSeparatedByString:@"/"];
    if (parts.count<1 || parts.count>2) return NO;
    long long numbers[2]={0,1};
    for (NSUInteger i=0;i<parts.count;i++) {
        NSScanner *scanner=[NSScanner scannerWithString:parts[i]];
        scanner.charactersToBeSkipped=nil;
        if (![scanner scanLongLong:&numbers[i]] || !scanner.isAtEnd) return NO;
    }
    if (numbers[0]<=0 || numbers[1]<=0) return NO;
    *numerator=numbers[0];*denominator=numbers[1];return YES;
}

static NSString *SubPopSRTTime(long long frame, long long numerator, long long denominator) {
    // Quantize to milliseconds only at export; keep frame-accurate source rows.
    __int128 scaled=(__int128)frame*numerator*1000;
    __int128 whole=scaled/denominator, remainder=scaled%denominator;
    if (remainder*2>denominator || (remainder*2==denominator && (whole&1))) whole++;
    if (whole>LLONG_MAX) return nil;
    long long ms=(long long)whole;
    long long hours=ms/3600000;ms%=3600000;
    long long minutes=ms/60000;ms%=60000;
    long long seconds=ms/1000;ms%=1000;
    return [NSString stringWithFormat:@"%02lld:%02lld:%02lld,%03lld",hours,minutes,seconds,ms];
}

static NSData *SubPopSRTExportData(NSArray<NSDictionary *> *rows, NSString *frameDuration, NSError **error) {
    long long numerator=0,denominator=0;
    if (![rows isKindOfClass:NSArray.class] || !rows.count ||
        !SubPopParseFrameDuration(frameDuration,&numerator,&denominator)) {
        if (error) *error=SubPopCaptionExportError(@"字幕时间数据不完整，无法导出 SRT。");
        return nil;
    }
    NSMutableString *srt=[NSMutableString new];
    long long previousEnd=0;
    for (NSUInteger i=0;i<rows.count;i++) {
        id row=rows[i];
        if (![row isKindOfClass:NSDictionary.class]) {
            if (error) *error=SubPopCaptionExportError(@"字幕内容不完整，无法导出 SRT。");
            return nil;
        }
        NSNumber *start=row[@"start_frame"],*end=row[@"end_frame"];
        NSString *value=row[@"text"];
        if (![start isKindOfClass:NSNumber.class] ||
            ![end isKindOfClass:NSNumber.class] || ![value isKindOfClass:NSString.class]) {
            if (error) *error=SubPopCaptionExportError(@"字幕内容不完整，无法导出 SRT。");
            return nil;
        }
        long long first=start.longLongValue,last=end.longLongValue;
        NSString *text=[[[value stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                         stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"]
                         stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (first<previousEnd || last<=first || !text.length || first<0 ||
            start.doubleValue!=(double)first || end.doubleValue!=(double)last) {
            if (error) *error=SubPopCaptionExportError(@"字幕时间或文字无效，无法导出 SRT。");
            return nil;
        }
        NSString *from=SubPopSRTTime(first,numerator,denominator);
        NSString *to=SubPopSRTTime(last,numerator,denominator);
        if (!from || !to) {
            if (error) *error=SubPopCaptionExportError(@"字幕时间超出 SRT 支持范围。");
            return nil;
        }
        [srt appendFormat:@"%lu\n%@ --> %@\n%@\n\n",(unsigned long)(i+1),from,to,text];
        previousEnd=last;
    }
    return [srt dataUsingEncoding:NSUTF8StringEncoding];
}
