#pragma once
#import <Cocoa/Cocoa.h>
#import "RuntimePaths.h"
#import "TitleNaming.h"
#include <limits.h>
#include <math.h>

// Only the existing, non-sandboxed container publishes these small records.
// The extension reads its own App Group; it never needs the host's preferences.
static NSString *const SubPopTitleNamingSnapshotsKey = @"SubPopTitleNamingHostSnapshots.v1";
static const NSTimeInterval SubPopTitleNamingSnapshotLifetime = 120.0;
typedef NSString *(^SubPopTitleNamingResolver)(SubPopTitleTemplate template, NSArray<NSString *> *languages);

static inline BOOL SubPopTitleNamingBridgeNumber(id value) {
    return [value isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID() && isfinite([value doubleValue]);
}

static inline BOOL SubPopTitleNamingBridgePID(id value) {
    if (!SubPopTitleNamingBridgeNumber(value)) return NO;
    double number=[value doubleValue];
    return number>0 && number<=INT_MAX && floor(number)==number;
}

static inline BOOL SubPopTitleNamingBridgeName(id value) {
    return [value isKindOfClass:NSString.class] && [value length]>0 && [value length]<=256 &&
        [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]>0 &&
        [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound &&
        [value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound;
}

static inline BOOL SubPopTitleNamingBridgeDate(id value) {
    return [value isKindOfClass:NSDate.class] && isfinite([value timeIntervalSince1970]) && [value timeIntervalSince1970]>0;
}

// Pure generation path. Resolver injection keeps tests independent of running
// apps, real host preferences, the installed FCP, and the production App Group.
static inline NSDictionary *SubPopCreateTitleNamingSnapshot(NSString *hostID, NSNumber *pid,
        NSDate *launchDate, NSDate *now, id hostLanguages, NSArray *systemLanguages,
        SubPopTitleNamingResolver resolver) {
    if (![hostID isKindOfClass:NSString.class] || !SubPopTitleNamingHostIdentifier(hostID) ||
        !SubPopTitleNamingBridgePID(pid) || !SubPopTitleNamingBridgeDate(launchDate) ||
        !SubPopTitleNamingBridgeDate(now) || [launchDate compare:now]==NSOrderedDescending || !resolver) return nil;
    NSArray *languages=SubPopTitleNamingPreferredLanguages(hostLanguages,systemLanguages);
    if (!languages.count) return nil;
    NSMutableDictionary *snapshot=[@{@"schema":@1,@"timestamp":@(now.timeIntervalSince1970),
        @"hostID":hostID,@"pid":pid,@"launchDate":@(launchDate.timeIntervalSince1970)} mutableCopy];
    NSString *basic=resolver(SubPopTitleTemplateBasic,languages);
    NSString *native=resolver(SubPopTitleTemplateNative,languages);
    if (SubPopTitleNamingBridgeName(basic)) snapshot[@"basic"]=basic;
    if (SubPopTitleNamingBridgeName(native)) snapshot[@"native"]=native;
    return snapshot.count>5 ? snapshot.copy : nil;
}

// Pure consumption path. PID alone is insufficient because macOS reuses it.
// A fresh record must also belong to this host's exact process launch date.
static inline NSString *SubPopTitleTemplateDisplayNameFromSnapshot(id value, SubPopTitleTemplate template,
        NSString *hostID, NSNumber *pid, NSDate *launchDate, NSDate *now) {
    if ((template!=SubPopTitleTemplateBasic && template!=SubPopTitleTemplateNative) ||
        ![hostID isKindOfClass:NSString.class] || !SubPopTitleNamingHostIdentifier(hostID) ||
        !SubPopTitleNamingBridgePID(pid) || !SubPopTitleNamingBridgeDate(launchDate) ||
        !SubPopTitleNamingBridgeDate(now) || ![value isKindOfClass:NSDictionary.class] || [value count]>7) return nil;
    NSDictionary *snapshot=value;
    NSSet *keys=[NSSet setWithArray:@[@"schema",@"timestamp",@"hostID",@"pid",@"launchDate",@"basic",@"native"]];
    for (id key in snapshot) if (![key isKindOfClass:NSString.class] || ![keys containsObject:key]) return nil;
    if (!SubPopTitleNamingBridgeNumber(snapshot[@"schema"]) || [snapshot[@"schema"] doubleValue]!=1 ||
        ![snapshot[@"hostID"] isKindOfClass:NSString.class] || ![snapshot[@"hostID"] isEqual:hostID] ||
        !SubPopTitleNamingBridgePID(snapshot[@"pid"]) || ![snapshot[@"pid"] isEqualToNumber:pid] ||
        !SubPopTitleNamingBridgeNumber(snapshot[@"launchDate"]) ||
        [snapshot[@"launchDate"] doubleValue]!=launchDate.timeIntervalSince1970 ||
        !SubPopTitleNamingBridgeNumber(snapshot[@"timestamp"])) return nil;
    NSTimeInterval timestamp=[snapshot[@"timestamp"] doubleValue],current=now.timeIntervalSince1970;
    if (timestamp<launchDate.timeIntervalSince1970 || timestamp>current ||
        current-timestamp>SubPopTitleNamingSnapshotLifetime) return nil;
    for (NSString *key in @[@"basic",@"native"]) {
        if (snapshot[key] && !SubPopTitleNamingBridgeName(snapshot[key])) return nil;
    }
    return snapshot[template==SubPopTitleTemplateBasic ? @"basic" : @"native"];
}

// Preferences describe the next launch after a language change; the running
// host may still display its previous language. Once this process's observed
// preferences change, stop publishing until it launches again. This state is
// private to the container and never writes language preferences to the group.
static inline NSDictionary *SubPopTitleNamingLanguageState(id previous,NSString *hostID,NSNumber *pid,
        NSDate *launchDate,NSArray *languages) {
    NSArray *validLanguages=SubPopTitleNamingLanguages(languages);
    if (![hostID isKindOfClass:NSString.class] || !SubPopTitleNamingHostIdentifier(hostID) ||
        !SubPopTitleNamingBridgePID(pid) || !SubPopTitleNamingBridgeDate(launchDate) || !validLanguages.count) return nil;
    if (previous && (![previous isKindOfClass:NSDictionary.class] || [previous count]!=5 ||
        ![previous[@"hostID"] isKindOfClass:NSString.class] || !SubPopTitleNamingHostIdentifier(previous[@"hostID"]) ||
        !SubPopTitleNamingBridgePID(previous[@"pid"]) || !SubPopTitleNamingBridgeNumber(previous[@"launchDate"]) ||
        [previous[@"launchDate"] doubleValue]<=0 || !SubPopTitleNamingLanguages(previous[@"languages"]) ||
        ![previous[@"invalidated"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)previous[@"invalidated"])!=CFBooleanGetTypeID())) return nil;
    BOOL sameProcess=[previous isKindOfClass:NSDictionary.class] &&
        [previous[@"hostID"] isEqual:hostID] && [previous[@"pid"] isEqual:pid] &&
        [previous[@"launchDate"] isEqual:@(launchDate.timeIntervalSince1970)];
    BOOL invalidated=sameProcess && ([previous[@"invalidated"] boolValue] || ![previous[@"languages"] isEqual:validLanguages]);
    return @{@"hostID":hostID,@"pid":pid,@"launchDate":@(launchDate.timeIntervalSince1970),
        @"languages":sameProcess ? previous[@"languages"] : validLanguages,@"invalidated":@(invalidated)};
}

static inline NSRunningApplication *SubPopTitleNamingRunningHost(NSString *hostID) {
    if (![hostID isKindOfClass:NSString.class] || !SubPopTitleNamingHostIdentifier(hostID)) return nil;
    NSArray<NSRunningApplication *> *apps=[NSRunningApplication runningApplicationsWithBundleIdentifier:hostID];
    if (apps.count!=1) return nil;
    NSRunningApplication *app=apps.firstObject;
    if (app.terminated || !app.finishedLaunching || ![app.bundleIdentifier isEqual:hostID] ||
        !app.bundleURL.isFileURL || !SubPopTitleNamingBridgePID(@(app.processIdentifier)) ||
        !SubPopTitleNamingBridgeDate(app.launchDate) ||
        ![[NSBundle bundleWithURL:app.bundleURL].bundleIdentifier isEqual:hostID]) return nil;
    return app;
}

// Call from the container's existing main-loop timer (about every five seconds).
// Replacing the whole map also clears any entry whose host or resolution failed.
// Different FCP products can coexist; multiple instances of one ID are ambiguous.
static inline void SubPopPublishTitleNamingSnapshot(void) {
    // This function is invoked on the container's main run loop only.
    static NSMutableDictionary<NSString *,NSDictionary *> *languageStates=nil;
    if (!languageStates) languageStates=[NSMutableDictionary new];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:SubPopApplicationGroup];
    if (!defaults) return;
    NSMutableDictionary *snapshots=[NSMutableDictionary new];
    for (NSString *hostID in @[@"com.apple.FinalCutApp",@"com.apple.FinalCut"]) {
        NSRunningApplication *app=SubPopTitleNamingRunningHost(hostID);
        if (!app) continue;
        id override=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AppleLanguages"),(__bridge CFStringRef)hostID));
        id global=CFBridgingRelease(CFPreferencesCopyValue(CFSTR("AppleLanguages"),kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
        NSArray *languages=SubPopTitleNamingPreferredLanguages(override,global);
        NSDictionary *state=SubPopTitleNamingLanguageState(languageStates[hostID],hostID,@(app.processIdentifier),app.launchDate,languages);
        if (!state) continue;
        languageStates[hostID]=state;
        if ([state[@"invalidated"] boolValue]) continue;
        NSDictionary *snapshot=SubPopCreateTitleNamingSnapshot(hostID,@(app.processIdentifier),app.launchDate,NSDate.date,
            override,global,^NSString *(SubPopTitleTemplate template,NSArray<NSString *> *resolvedLanguages) {
                return SubPopTitleTemplateDisplayNameAtHostURL(template,app.bundleURL,resolvedLanguages);
            });
        if (snapshot) snapshots[hostID]=snapshot;
    }
    if (snapshots.count) [defaults setObject:snapshots.copy forKey:SubPopTitleNamingSnapshotsKey];
    else [defaults removeObjectForKey:SubPopTitleNamingSnapshotsKey];
}

static inline NSString *SubPopReadTitleTemplateDisplayName(SubPopTitleTemplate template,NSString *hostID) {
    if ((template!=SubPopTitleTemplateBasic && template!=SubPopTitleTemplateNative) ||
        ![hostID isKindOfClass:NSString.class] || !SubPopTitleNamingHostIdentifier(hostID)) return nil;
    NSRunningApplication *app=SubPopTitleNamingRunningHost(hostID);
    if (!app) return nil;
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:SubPopApplicationGroup];
    id snapshots=[defaults objectForKey:SubPopTitleNamingSnapshotsKey];
    if (![snapshots isKindOfClass:NSDictionary.class] || [snapshots count]>2) return nil;
    return SubPopTitleTemplateDisplayNameFromSnapshot(snapshots[hostID],template,hostID,@(app.processIdentifier),app.launchDate,NSDate.date);
}
