#import "Tap5aStyle.h"

// Text inspector position is separate from the template's published rig offsets.
static NSString *const SubPopNativeTextPositionKey=@"9999/3336674837/3336674846/1/100/101";
static NSArray *SubPopNativeTextPositionFields(void) {
    return @[@[@"textPositionX",@"文本位置 X（px）",@0,@-10000,@10000],
             @[@"textPositionY",@"文本位置 Y（px）",@0,@-10000,@10000],
             @[@"textPositionZ",@"文本位置 Z（px）",@0,@-10000,@10000]];
}

// Native Subtitle's published rig sliders are normalized 0..1 in FCPXML.
// These values stay in the units displayed in the FCP Title inspector.
static NSArray *SubPopNativeBoxFields(void) {
    return @[
        @[@"backgroundColor",@"底框颜色",@[@0,@0,@0],@0,@1,@"Background Color",@"9999/3336674837/3336685305/3336678548/2/353/113/111"],
        @[@"opacity",@"底框不透明度 %",@85,@0,@100,@"Background Opacity",@"9999/3336674837/3336685305/3336678548/1/200/202"],
        @[@"roundness",@"底框圆角",@20,@0,@1000,@"Background Corner Radius",@"9999/3336674837/3336685305/3336678548/2/353/144"],
        @[@"boxWidth",@"底框宽度调整",@0,@-100,@100,@"Background Width",@"9999/3336678691/100/3336678692/2/100"],
        @[@"boxHeight",@"底框高度调整",@0,@-100,@100,@"Background Height",@"9999/3336678691/100/3336678786/2/100"],
        @[@"positionX",@"X 位置偏移",@0,@-2000,@2000,@"X Position Offset",@"9999/3336678691/100/3337241478/2/100"],
        @[@"positionY",@"Y 位置偏移",@0,@-2000,@2000,@"Y Position Offset",@"9999/3336678691/100/3337241559/2/100"],
        @[@"verticalSafe",@"竖屏社交媒体安全区",@0,@0,@1,@"Vertical Social Media Safe",@"9999/3336678691/100/3337013104/2/100"],
        @[@"animationStyle",@"动画样式",@0,@0,@5,@"Animation Style",@"9999/3336678691/100/3336692171/2/100"],
        @[@"animateBy",@"动画单位",@1,@0,@3,@"Animate By",@"9999/3336678691/100/3336679301/2/100"],
        @[@"fillColor",@"高亮与填充颜色",@[@1,@0.85,@0],@0,@1,@"Highlight and Fill Color",@"9999/3336674837/3337240802/2/353/113/111"]
    ];
}
static NSDictionary *SubPopNormalizeNativeStyle(id input) {
    NSDictionary *source=[input isKindOfClass:NSDictionary.class] ? input : @{};
    // Reuse the font resolver, but never clamp native geometry to Tap5a ranges.
    NSMutableDictionary *result=[SubPopNormalizeTap5aStyle(source) mutableCopy];
    for (NSArray *f in [SubPopNativeBoxFields() arrayByAddingObjectsFromArray:SubPopNativeTextPositionFields()]) {
        id value=source[f[0]];
        if ([f[2] isKindOfClass:NSArray.class]) {
            BOOL valid=[value isKindOfClass:NSArray.class] && [value count]==3;
            if (valid) for (id c in value) if (![c isKindOfClass:NSNumber.class] || !isfinite([c doubleValue]) || [c doubleValue]<0 || [c doubleValue]>1) valid=NO;
            result[f[0]]=valid ? value : f[2];
        } else {
            double n=[value isKindOfClass:NSNumber.class] ? [value doubleValue] : [f[2] doubleValue];
            if (!isfinite(n)) n=[f[2] doubleValue];
            n=MAX([f[3] doubleValue],MIN([f[4] doubleValue],n));
            n=round(n*1e9)/1e9; // Stable inspector values after normalized-rig decoding.
            if ([f[0] isEqual:@"verticalSafe"] || [f[0] isEqual:@"animateBy"] || [f[0] isEqual:@"animationStyle"]) n=round(n);
            if ([f[0] isEqual:@"animationStyle"] && n==2) n=0; // Native rig has no tag 2.
            result[f[0]]=@(n);
        }
    }
    return result;
}
static double SubPopNativeEncodeNumber(NSString *key,double value) {
    if ([key isEqual:@"opacity"]) return value/100;
    if ([key isEqual:@"boxWidth"] || [key isEqual:@"boxHeight"]) return (value+100)/200;
    if ([key isEqual:@"positionX"] || [key isEqual:@"positionY"]) return (value+2000)/4000;
    return value;
}
static double SubPopNativeDecodeNumber(NSString *key,double value) {
    if ([key isEqual:@"opacity"]) return value*100;
    if ([key isEqual:@"boxWidth"] || [key isEqual:@"boxHeight"]) return value*200-100;
    if ([key isEqual:@"positionX"] || [key isEqual:@"positionY"]) return value*4000-2000;
    return value;
}
static void SubPopApplyNativeStyle(NSXMLDocument *doc,NSDictionary *input) {
    NSDictionary *s=SubPopNormalizeNativeStyle(input);
    for (NSXMLElement *title in [doc nodesForXPath:@"/fcpxml/clip/spine/title" error:nil]) {
        for (NSXMLElement *old in [title elementsForName:@"param"]) if ([[old attributeForName:@"key"].stringValue isEqual:SubPopNativeTextPositionKey]) [old detach];
        NSXMLElement *position=[NSXMLElement elementWithName:@"param"];
        [position addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:@"Position"]];
        [position addAttribute:[NSXMLNode attributeWithName:@"key" stringValue:SubPopNativeTextPositionKey]];
        NSString *vector=[NSString stringWithFormat:@"%.12g %.12g",[s[@"textPositionX"] doubleValue],[s[@"textPositionY"] doubleValue]];
        if ([s[@"textPositionZ"] doubleValue]!=0) vector=[vector stringByAppendingFormat:@" %.12g",[s[@"textPositionZ"] doubleValue]];
        [position addAttribute:[NSXMLNode attributeWithName:@"value" stringValue:vector]];
        [title insertChild:position atIndex:0];
        for (NSArray *f in SubPopNativeBoxFields()) {
            for (NSXMLElement *old in [title elementsForName:@"param"]) if ([[old attributeForName:@"key"].stringValue isEqual:f[6]]) [old detach];
            id value=s[f[0]];
            NSString *encoded=[value isKindOfClass:NSArray.class] ? [NSString stringWithFormat:@"%.9g %.9g %.9g",[value[0] doubleValue],[value[1] doubleValue],[value[2] doubleValue]] : [NSString stringWithFormat:@"%.12g",SubPopNativeEncodeNumber(f[0],[value doubleValue])];
            NSXMLElement *param=[NSXMLElement elementWithName:@"param"];
            [param addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:f[5]]];
            [param addAttribute:[NSXMLNode attributeWithName:@"key" stringValue:f[6]]];
            [param addAttribute:[NSXMLNode attributeWithName:@"value" stringValue:encoded]];
            [title insertChild:param atIndex:0];
        }
    }
}
// Read only supported static settings; never capture caption text or timing.
static NSDictionary *SubPopNativeStyleFromTitle(NSXMLElement *title) {
    NSMutableDictionary *s=[NSMutableDictionary new];
    NSXMLElement *text=[title nodesForXPath:@"text-style-def/text-style" error:nil].firstObject;
    for (NSString *key in @[@"font",@"fontFace",@"fontSize",@"kerning",@"lineSpacing"]) {
        NSString *value=[text attributeForName:key].stringValue;if (!value.length) continue;
        NSString *mapped=@{@"font":@"textFont",@"fontFace":@"textFace",@"fontSize":@"textSize"}[key] ?: key;
        if ([key isEqual:@"font"] || [key isEqual:@"fontFace"]) s[mapped]=value;
        else {NSScanner *scan=[NSScanner scannerWithString:value];double n;if ([scan scanDouble:&n] && scan.isAtEnd && isfinite(n)) s[mapped]=@(n);}
    }
    if (!s[@"textFace"]) {
        // Some FCP exports describe the face with traits instead of fontFace.
        NSFontTraitMask traits=0;
        if ([[text attributeForName:@"bold"].stringValue boolValue]) traits|=NSBoldFontMask;
        if ([[text attributeForName:@"italic"].stringValue boolValue]) traits|=NSItalicFontMask;
        NSFont *font=[NSFontManager.sharedFontManager fontWithFamily:s[@"textFont"] ?: @"Helvetica" traits:traits weight:traits & NSBoldFontMask ? 9 : 5 size:12];
        for (NSArray *member in SubPopFontMembers(font.familyName)) if ([member[0] isEqual:font.fontName]) {s[@"textFont"]=font.familyName;s[@"textFace"]=member[1];break;}
    }
    NSString *rgb=[text attributeForName:@"fontColor"].stringValue;
    if (rgb) {NSScanner *scan=[NSScanner scannerWithString:rgb];double a,b,c;if ([scan scanDouble:&a] && [scan scanDouble:&b] && [scan scanDouble:&c]) s[@"textColor"]=@[@(a),@(b),@(c)];}
    for (NSXMLElement *param in [title elementsForName:@"param"]) {
        if (![[param attributeForName:@"key"].stringValue isEqual:SubPopNativeTextPositionKey]) continue;
        if ([param elementsForName:@"keyframeAnimation"].count) return nil;
        NSScanner *scan=[NSScanner scannerWithString:[param attributeForName:@"value"].stringValue ?: @""];
        double x,y,z=0;
        if (![scan scanDouble:&x] || ![scan scanDouble:&y] || (!scan.isAtEnd && ![scan scanDouble:&z]) || !scan.isAtEnd || !isfinite(x) || !isfinite(y) || !isfinite(z)) return nil;
        s[@"textPositionX"]=@(x);s[@"textPositionY"]=@(y);s[@"textPositionZ"]=@(z);
    }
    for (NSArray *f in SubPopNativeBoxFields()) for (NSXMLElement *param in [title elementsForName:@"param"]) {
        if (![[param attributeForName:@"key"].stringValue isEqual:f[6]]) continue;
        // A keyframed parameter cannot be represented by one preset value.
        if ([param elementsForName:@"keyframeAnimation"].count) return nil;
        NSScanner *scan=[NSScanner scannerWithString:[param attributeForName:@"value"].stringValue ?: @""];
        double a,b,c;
        if ([f[2] isKindOfClass:NSArray.class]) {if ([scan scanDouble:&a] && [scan scanDouble:&b] && [scan scanDouble:&c]) s[f[0]]=@[@(a),@(b),@(c)];}
        else if ([scan scanDouble:&a] && isfinite(a)) s[f[0]]=@(SubPopNativeDecodeNumber(f[0],a));
    }
    return SubPopNormalizeNativeStyle(s);
}

// Follow referenced compound clips so a freshly dropped project can read the
// styles inside a subtitle wrapper as well as individual timeline titles.
static NSArray<NSXMLElement *> *SubPopNativeProjectTitles(NSXMLDocument *doc) {
    NSMutableSet *effects=[NSMutableSet new],*visited=[NSMutableSet new];
    NSMutableDictionary *media=[NSMutableDictionary new];
    for (NSXMLElement *e in [doc nodesForXPath:@"/fcpxml/resources/effect" error:nil]) {
        NSString *identifier=[e attributeForName:@"id"].stringValue;
        if (identifier.length && [[e attributeForName:@"uid"].stringValue isEqual:SubPopNativeSubtitleUID]) [effects addObject:identifier];
    }
    for (NSXMLElement *m in [doc nodesForXPath:@"/fcpxml/resources/media" error:nil]) {NSString *identifier=[m attributeForName:@"id"].stringValue;if (identifier.length) media[identifier]=m;}
    NSMutableArray *queue=[[doc nodesForXPath:@"//project/sequence" error:nil] mutableCopy] ?: [NSMutableArray new],*result=[NSMutableArray new];
    for (NSUInteger i=0;i<queue.count;i++) {
        NSXMLElement *node=queue[i];NSString *ref=[node attributeForName:@"ref"].stringValue;
        if ([node.name isEqual:@"title"] && [effects containsObject:ref]) [result addObject:node];
        if ([node.name isEqual:@"ref-clip"] && media[ref] && ![visited containsObject:ref]) {[visited addObject:ref];[queue addObject:media[ref]];}
        for (NSXMLNode *child in node.children) if (child.kind==NSXMLElementKind) [queue addObject:child];
    }
    return result;
}

@interface SubPopNativePresetStore : NSObject
@property NSUserDefaults *defaults;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (NSArray<NSDictionary *> *)presets;
- (NSString *)defaultID;
- (NSDictionary *)defaultStyle;
- (NSString *)saveStyle:(NSDictionary *)style name:(NSString *)name;
- (void)setDefaultID:(NSString *)identifier;
- (void)removeID:(NSString *)identifier;
@end
@implementation SubPopNativePresetStore
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {if ((self=[super init])) _defaults=defaults;return self;}
- (NSDictionary *)library {id value=[self.defaults dictionaryForKey:@"nativeSubtitleStyleLibrary"];return [value isKindOfClass:NSDictionary.class] ? value : @{};}
- (NSArray<NSDictionary *> *)presets {
    NSMutableArray *result=[NSMutableArray new];id rows=self.library[@"presets"];
    if ([rows isKindOfClass:NSArray.class]) for (id row in rows) {
        if (![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class] || ![row[@"name"] isKindOfClass:NSString.class] || ![row[@"style"] isKindOfClass:NSDictionary.class]) continue;
        if (![row[@"id"] length] || ![row[@"name"] length]) continue;
        [result addObject:@{@"id":row[@"id"],@"name":row[@"name"],@"style":SubPopNormalizeNativeStyle(row[@"style"])}];
    }
    return result;
}
- (NSString *)defaultID {id value=self.library[@"defaultID"];if ([value isKindOfClass:NSString.class]) for (NSDictionary *p in self.presets) if ([p[@"id"] isEqual:value]) return value;return @"";}
- (NSDictionary *)defaultStyle {NSString *identifier=self.defaultID;for (NSDictionary *p in self.presets) if ([p[@"id"] isEqual:identifier]) return p[@"style"];return SubPopNormalizeNativeStyle(nil);}
- (void)writePresets:(NSArray *)presets defaultID:(NSString *)identifier {[self.defaults setObject:@{@"version":@1,@"presets":presets,@"defaultID":identifier ?: @""} forKey:@"nativeSubtitleStyleLibrary"];}
- (NSString *)saveStyle:(NSDictionary *)style name:(NSString *)name {
    name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || name.length>60 || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
    NSMutableArray *presets=self.presets.mutableCopy;NSString *identifier=nil;NSUInteger index=NSNotFound;
    for (NSUInteger i=0;i<presets.count;i++) if ([presets[i][@"name"] localizedCaseInsensitiveCompare:name]==NSOrderedSame) {identifier=presets[i][@"id"];index=i;break;}
    if (index==NSNotFound && presets.count>=100) return nil;
    identifier=identifier ?: NSUUID.UUID.UUIDString;
    NSDictionary *row=@{@"id":identifier,@"name":name,@"style":SubPopNormalizeNativeStyle(style)};
    if (index==NSNotFound) [presets addObject:row];else presets[index]=row;
    [self writePresets:presets defaultID:self.defaultID];return identifier;
}
- (void)setDefaultID:(NSString *)identifier {
    NSString *valid=@"";for (NSDictionary *p in self.presets) if ([p[@"id"] isEqual:identifier]) valid=identifier;
    [self writePresets:self.presets defaultID:valid];
}
- (void)removeID:(NSString *)identifier {
    NSMutableArray *presets=self.presets.mutableCopy;NSString *defaultID=self.defaultID;
    NSIndexSet *indices=[presets indexesOfObjectsPassingTest:^BOOL(NSDictionary *p,NSUInteger i,BOOL *stop){return [p[@"id"] isEqual:identifier];}];[presets removeObjectsAtIndexes:indices];
    [self writePresets:presets defaultID:[defaultID isEqual:identifier] ? @"" : defaultID];
}
@end
