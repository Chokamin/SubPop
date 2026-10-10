#pragma once
#import <Cocoa/Cocoa.h>
#import <CoreMedia/CoreMedia.h>
#include <fcntl.h>
#include <unistd.h>

// Shared exports are explicit transactions, never paired by name or recency.
static CMTime SubPopShareTime(id value) {
    if (![value isKindOfClass:NSString.class] || [value length]>64) return kCMTimeInvalid;
    NSString *text=value;
    if ([text hasSuffix:@"s"]) text=[text substringToIndex:text.length-1];
    NSArray *parts=[text componentsSeparatedByString:@"/"];
    if (parts.count<1 || parts.count>2) return kCMTimeInvalid;
    long long n=0,d=1;
    NSScanner *a=[NSScanner scannerWithString:parts[0]];a.charactersToBeSkipped=nil;
    if (![a scanLongLong:&n] || !a.isAtEnd) return kCMTimeInvalid;
    if (parts.count==2) {
        NSScanner *b=[NSScanner scannerWithString:parts[1]];b.charactersToBeSkipped=nil;
        if (![b scanLongLong:&d] || !b.isAtEnd) return kCMTimeInvalid;
    }
    if (n<=0 || d<=0 || d>INT32_MAX) return kCMTimeInvalid;
    return CMTimeMake(n,(int32_t)d);
}
static BOOL SubPopShareRegularFile(NSURL *url, unsigned long long limit) {
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    return [attrs.fileType isEqual:NSFileTypeRegular] && attrs.fileSize>0 && attrs.fileSize<=limit;
}
static NSDictionary *SubPopShareManifest(NSURL *directory) {
    if (![[NSUUID alloc] initWithUUIDString:directory.lastPathComponent]) return nil;
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:directory.path error:nil];
    if (![attrs.fileType isEqual:NSFileTypeDirectory]) return nil;
    if ([NSFileManager.defaultManager fileExistsAtPath:[[directory URLByAppendingPathComponent:@"consumed.json"] path]]) return nil;
    NSURL *ready=[directory URLByAppendingPathComponent:@"ready.json"];
    if (!SubPopShareRegularFile(ready,64*1024)) return nil;
    id value=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:ready] options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"protocol"] isEqual:@1] || ![value[@"shareID"] isEqual:directory.lastPathComponent]) return nil;
    for (NSString *key in @[@"projectUID",@"projectName",@"audioFile",@"xmlFile",@"xmlSHA256",@"audioSHA256"]) {
        if (![value[key] isKindOfClass:NSString.class] || ![value[key] length] || [value[key] length]>1024) return nil;
    }
    NSCharacterSet *hex=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    for (NSString *key in @[@"xmlSHA256",@"audioSHA256"])
        if ([value[key] length]!=64 || [value[key] rangeOfCharacterFromSet:hex].location!=NSNotFound) return nil;
    if (![value[@"xmlFile"] isEqual:@"input.fcpxml"]) return nil;
    NSString *audio=value[@"audioFile"];
    if (![audio isEqual:audio.lastPathComponent] || ![audio hasPrefix:@"audio."] || ![@[@"wav",@"aif",@"aiff",@"m4a",@"caf"] containsObject:audio.pathExtension.lowercaseString]) return nil;
    CMTime duration=SubPopShareTime(value[@"duration"]),frame=SubPopShareTime(value[@"frameDuration"]);
    if (!CMTIME_IS_NUMERIC(duration) || CMTimeGetSeconds(duration)>14400 || !CMTIME_IS_NUMERIC(frame) || CMTimeGetSeconds(frame)>=1) return nil;
    if (!SubPopShareRegularFile([directory URLByAppendingPathComponent:audio],4ULL*1024*1024*1024) || !SubPopShareRegularFile([directory URLByAppendingPathComponent:@"input.fcpxml"],16*1024*1024)) return nil;
    return value;
}
static BOOL SubPopFinishShare(NSURL *directory, NSString *status) {
    NSURL *marker=[directory URLByAppendingPathComponent:@"consumed.json"];
    int fd=open(marker.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if (fd<0) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"status":status} options:0 error:nil];
    BOOL ok=write(fd,data.bytes,data.length)==(ssize_t)data.length && fsync(fd)==0;
    close(fd);
    if (!ok) [NSFileManager.defaultManager removeItemAtURL:marker error:nil];
    return ok;
}
static NSArray<NSDictionary *> *SubPopPendingShares(NSURL *bridge) {
    if (!bridge) return @[];
    NSURL *inbox=[bridge URLByAppendingPathComponent:@"share-inbox" isDirectory:YES];
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:inbox.path error:nil];
    if (![attrs.fileType isEqual:NSFileTypeDirectory]) return @[];
    NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:inbox.path error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *pending=[NSMutableArray new];
    for (NSString *name in names) {
        if (pending.count>=64) break;
        NSURL *dir=[inbox URLByAppendingPathComponent:name isDirectory:YES];
        if ([NSFileManager.defaultManager fileExistsAtPath:[[dir URLByAppendingPathComponent:@"consumed.json"] path]]) continue;
        NSDictionary *manifest=SubPopShareManifest(dir);
        if (manifest) [pending addObject:manifest];
    }
    return [pending sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        return [a[@"shareID"] compare:b[@"shareID"]];
    }];
}
