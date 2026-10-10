#pragma once
#import <Cocoa/Cocoa.h>
#import "TitleTemplates.h"

// FCP recognizes its generated clip names using the installed Motion template's
// display name, not the effect resource's XML name. Read only its localization
// data; do not load an executable from the host application or a private API.
static inline BOOL SubPopTitleNamingHostIdentifier(NSString *identifier) {
    return [identifier isEqual:@"com.apple.FinalCutApp"] || [identifier isEqual:@"com.apple.FinalCut"];
}

static inline NSArray<NSString *> *SubPopTitleNamingLanguages(id value) {
    if (![value isKindOfClass:NSArray.class] || ![value count] || [value count]>64) return nil;
    NSMutableArray *result=[NSMutableArray new];
    for (id language in value) {
        if (![language isKindOfClass:NSString.class] || ![language length] || [language length]>128) return nil;
        [result addObject:language];
    }
    return result.copy;
}

static inline NSArray<NSString *> *SubPopTitleNamingPreferredLanguages(id hostLanguages, NSArray *systemLanguages) {
    return SubPopTitleNamingLanguages(hostLanguages) ?: SubPopTitleNamingLanguages(systemLanguages) ?: @[];
}

static inline NSDictionary *SubPopTitleNamingStrings(NSURL *url) {
    NSNumber *regular=nil,*size=nil;
    if (![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] || !regular.boolValue ||
        ![url getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue>65536) return nil;
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (!data.length || data.length>65536) return nil;
    id values=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
    if (![values isKindOfClass:NSDictionary.class]) {
        // Older templates use BOM-prefixed UTF-16 .strings syntax instead of a
        // complete XML/binary property list, including FCP's Subtitle template.
        NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) text=[[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
        @try { values=[text propertyListFromStringsFileFormat]; }
        @catch (NSException *exception) { return nil; }
    }
    return [values isKindOfClass:NSDictionary.class] ? values : nil;
}

static inline NSString *SubPopTitleNamingLocalizedTemplate(NSURL *templateURL, NSArray<NSString *> *languages) {
    NSNumber *regular=nil;
    if (![templateURL getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] || !regular.boolValue) return nil;
    NSURL *directory=[templateURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@".localized" isDirectory:YES];
    NSArray<NSURL *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil];
    NSMutableDictionary<NSString *,NSURL *> *available=[NSMutableDictionary new];
    for (NSURL *file in files) if ([file.pathExtension isEqual:@"strings"]) {
        NSString *language=file.lastPathComponent.stringByDeletingPathExtension;
        if (language.length && language.length<=128) available[language]=file;
    }
    if (!available.count) return nil;
    // Order the fallback deterministically. Include English even when absent:
    // an unmatched language must return nil instead of accidentally selecting
    // whichever unrelated translation happens to sort first.
    NSMutableArray *choices=[[available.allKeys sortedArrayUsingSelector:@selector(compare:)] mutableCopy];
    [choices removeObject:@"en"];[choices insertObject:@"en" atIndex:0];
    NSString *language=[NSBundle preferredLocalizationsFromArray:choices forPreferences:languages].firstObject;
    NSURL *strings=language ? available[language] : nil;
    NSString *key=templateURL.lastPathComponent.stringByDeletingPathExtension;
    id name=strings ? SubPopTitleNamingStrings(strings)[key] : nil;
    if (![name isKindOfClass:NSString.class] || ![[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] || [name length]>256 ||
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
    return name;
}

// Dependency-injected entry point for deterministic localization probes. The
// caller supplies the host's language preferences, including a per-app override.
static inline NSString *SubPopTitleTemplateDisplayNameAtHostURL(SubPopTitleTemplate template, NSURL *appURL, NSArray<NSString *> *preferredLanguages) {
    if ((template!=SubPopTitleTemplateBasic && template!=SubPopTitleTemplateNative) || !appURL.isFileURL) return nil;
    NSBundle *bundle=[NSBundle bundleWithURL:appURL];
    if (!SubPopTitleNamingHostIdentifier(bundle.bundleIdentifier)) return nil;
    NSArray *preferences=SubPopTitleNamingLanguages(preferredLanguages);
    if (!preferences.count || !bundle.localizations.count) return nil;
    NSArray *hostLanguages=[NSBundle preferredLocalizationsFromArray:bundle.localizations forPreferences:preferences];
    if (!hostLanguages.count) return nil;
    NSString *relative=template==SubPopTitleTemplateBasic
        ? @"Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"
        : @"Titles.localized/Subtitles.localized/Subtitle.localized/Subtitle.moti";
    NSURL *resources=[appURL URLByAppendingPathComponent:@"Contents/PlugIns/MediaProviders/MotionEffect.fxp/Contents/Resources" isDirectory:YES];
    NSArray *roots=template==SubPopTitleTemplateBasic ? @[@"PETemplates.localized",@"METemplates.localized"] : @[@"METemplates.localized",@"PETemplates.localized"];
    for (NSString *root in roots) {
        NSURL *url=[[resources URLByAppendingPathComponent:root isDirectory:YES] URLByAppendingPathComponent:relative];
        NSString *name=SubPopTitleNamingLocalizedTemplate(url,hostLanguages);
        if (name.length) return name;
    }
    return nil;
}

// FCP uses the first logical line, preserving its spaces and punctuation. Do
// not strip a template-looking suffix: it may be part of the actual subtitle.
static inline NSString *SubPopAutomaticTitleClipName(NSString *text, NSString *displayName) {
    if (![text isKindOfClass:NSString.class] || ![displayName isKindOfClass:NSString.class] || !displayName.length) return nil;
    NSUInteger end=0;
    [text getLineStart:NULL end:NULL contentsEnd:&end forRange:NSMakeRange(0,0)];
    return end ? [NSString stringWithFormat:@"%@ - %@",[text substringToIndex:end],displayName] : displayName;
}

// Pass nil when a trustworthy automatic name is unavailable. Omitting the
// attribute lets FCP own naming; an empty attribute instead means a custom name.
static inline void SubPopSetTitleClipName(NSXMLElement *title, NSString *name) {
    [title removeAttributeForName:@"name"];
    if (name) [title addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:name]];
}
