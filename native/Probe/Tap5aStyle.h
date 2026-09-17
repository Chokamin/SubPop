#import <Cocoa/Cocoa.h>
#import <math.h>

// Values are expressed in the same units shown by the Tap5a inspector.
static NSArray *SubPopTap5aFields(void) {
    return @[
        @[@"background",@"启用底框",@1,@0,@1,@"Enable",@"9999/10658/100/1825821409/2/100"],
        @[@"backgroundColor",@"底框颜色",@[@0,@0,@0],@0,@1,@"Color",@"9999/1825821564/10804/10924/2/353/113/111"],
        @[@"opacity",@"底框不透明度 %",@85,@0,@100,@"Opacity",@"9999/1825821564/10804/10924/2/353/113/141"],
        @[@"roundness",@"圆角",@10,@0,@100,@"Roundness",@"9999/10658/100/1825820731/2/100"],
        @[@"border",@"启用边框",@0,@0,@1,@"Enable",@"9999/10658/100/1825821410/2/100"],
        @[@"borderColor",@"边框颜色",@[@0.927873,@0.097376,@0.4057],@0,@1,@"Color",@"9999/1825821564/10804/1825823284/1825820644/2/353/108/107"],
        @[@"width",@"边框宽度",@20,@3,@100,@"Width",@"9999/10658/100/1825821354/2/100"],
        @[@"borderOpacity",@"边框不透明度 %",@100,@0,@100,@"Opacity",@"9999/1825821564/10804/1825823284/1825820644/1/200/202"],
        @[@"sides",@"边框位置",@2,@0,@6,@"Sides",@"9999/10658/100/1825821242/2/100"],
        @[@"top",@"上留白",@10,@0,@100,@"Top",@"9999/10658/100/10661/2/100"],
        @[@"bottom",@"下留白",@20,@0,@100,@"Bottom",@"9999/10658/100/10709/2/100"],
        @[@"left",@"左留白",@10,@0,@100,@"Left",@"9999/10658/100/10660/2/100"],
        @[@"right",@"右留白",@10,@0,@100,@"Right",@"9999/10658/100/10708/2/100"]
    ];
}
static NSArray *SubPopTextFields(void) {
    return @[@[@"textSize",@"字号",@72,@1,@1000],@[@"kerning",@"字距（点）",@0,@-20,@100],@[@"lineSpacing",@"额外行间距",@0,@0,@200],@[@"textColor",@"文字颜色",@[@1,@1,@1],@0,@1],@[@"positionX",@"X 偏移（px）",@0,@-10000,@10000],@[@"positionY",@"Y 偏移（px）",@0,@-10000,@10000]];
}
static NSArray *SubPopEffectFields(void) {
    return @[
        @[@"outlineEnabled",@"启用文字外框",@0,@0,@1],@[@"outlineColor",@"外框颜色",@[@0,@0,@0],@0,@1],@[@"outlineWidth",@"外框宽度",@2,@0,@20],@[@"outlineOpacity",@"外框不透明度 %",@100,@0,@100],
        @[@"glowEnabled",@"启用光晕",@0,@0,@1],@[@"glowOpacity",@"光晕不透明度 %",@70,@0,@100],@[@"glowRadius",@"光晕半径",@6,@0,@100],@[@"glowBlur",@"光晕模糊",@8,@0,@100],
        @[@"shadowEnabled",@"启用投影",@0,@0,@1],@[@"shadowColor",@"投影颜色",@[@0,@0,@0],@0,@1],@[@"shadowOpacity",@"投影不透明度 %",@75,@0,@100],@[@"shadowBlur",@"投影模糊",@4,@0,@100],@[@"shadowDistance",@"投影距离",@5,@0,@100],@[@"shadowAngle",@"投影角度 °",@315,@0,@360]
    ];
}
static NSArray *SubPopFontMembers(NSString *family) {
    return [NSFontManager.sharedFontManager availableMembersOfFontFamily:family] ?: @[];
}
static NSDictionary *SubPopNormalizeTap5aStyle(id input) {
    NSDictionary *source=[input isKindOfClass:NSDictionary.class] ? input : @{};
    NSMutableDictionary *result=[NSMutableDictionary new];
    for (NSArray *field in [[SubPopTap5aFields() arrayByAddingObjectsFromArray:SubPopTextFields()] arrayByAddingObjectsFromArray:SubPopEffectFields()]) {
        NSString *key=field[0];id value=source[key];
        if ([field[2] isKindOfClass:NSArray.class]) {
            BOOL valid=[value isKindOfClass:NSArray.class] && [value count]==3;
            if (valid) for (id component in value) if (![component isKindOfClass:NSNumber.class] || !isfinite([component doubleValue]) || [component doubleValue]<0 || [component doubleValue]>1) valid=NO;
            result[key]=valid ? value : field[2];
        } else {
            double n=[value isKindOfClass:NSNumber.class] ? [value doubleValue] : [field[2] doubleValue];
            if (!isfinite(n)) n=[field[2] doubleValue];
            n=MAX([field[3] doubleValue],MIN([field[4] doubleValue],n));
            if ([key hasSuffix:@"Enabled"] || [key isEqual:@"sides"] || [key isEqual:@"background"] || [key isEqual:@"border"]) n=round(n);
            result[key]=@(n);
        }
    }
    NSString *family=[source[@"textFont"] isKindOfClass:NSString.class] ? source[@"textFont"] : @"Helvetica";
    NSArray *members=SubPopFontMembers(family);
    if (!members.count) {family=@"Helvetica";members=SubPopFontMembers(family);}
    NSString *face=[source[@"textFace"] isKindOfClass:NSString.class] ? source[@"textFace"] : @"Regular";
    BOOL found=NO;for (NSArray *member in members) if ([member[1] isEqual:face]) found=YES;
    if (!found) face=members.count ? members[0][1] : @"Regular";
    result[@"textFont"]=family;result[@"textFace"]=face;
    return result;
}
static void SubPopApplyTap5aStyle(NSXMLDocument *doc, NSDictionary *input) {
    NSDictionary *style=SubPopNormalizeTap5aStyle(input);
    for (NSXMLElement *title in [doc nodesForXPath:@"/fcpxml/clip/spine/title" error:nil]) {
        NSDictionary *glow=@{@"":@([style[@"glowEnabled"] boolValue]),@"/43":@([style[@"glowEnabled"] boolValue] ? [style[@"glowOpacity"] doubleValue]/100 : 0),@"/45":style[@"glowRadius"],@"/77":[NSString stringWithFormat:@"%@ %@",style[@"glowBlur"],style[@"glowBlur"]]};
        for (NSString *suffix in glow) {
            NSString *key=[@"9999/1825821564/10045/10047/5/10049/38" stringByAppendingString:suffix];
            for (NSXMLElement *old in [title elementsForName:@"param"]) if ([[old attributeForName:@"key"].stringValue isEqual:key]) [old detach];
            NSXMLElement *param=[NSXMLElement elementWithName:@"param"];[param addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:@"Glow"]];[param addAttribute:[NSXMLNode attributeWithName:@"key" stringValue:key]];[param addAttribute:[NSXMLNode attributeWithName:@"value" stringValue:[glow[suffix] description]]];[title insertChild:param atIndex:0];
        }

        for (NSArray *field in SubPopTap5aFields()) {
            NSString *key=field[0], *path=field[6];id value=style[key];NSString *encoded;
            if ([value isKindOfClass:NSArray.class]) encoded=[NSString stringWithFormat:@"%.9g %.9g %.9g",[value[0] doubleValue],[value[1] doubleValue],[value[2] doubleValue]];
            else {
                double n=[value doubleValue];
                if ([key isEqual:@"width"]) n=(n-3)/97;
                else if (![key isEqual:@"background"] && ![key isEqual:@"border"] && ![key isEqual:@"sides"]) n/=100;
                encoded=[NSString stringWithFormat:@"%.9g",n];
            }
            for (NSXMLElement *old in [title elementsForName:@"param"]) if ([[old attributeForName:@"key"].stringValue isEqual:path]) [old detach];
            NSXMLElement *param=[NSXMLElement elementWithName:@"param"];
            [param addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:field[5]]];
            [param addAttribute:[NSXMLNode attributeWithName:@"key" stringValue:path]];
            [param addAttribute:[NSXMLNode attributeWithName:@"value" stringValue:encoded]];
            [title insertChild:param atIndex:0];
        }
    }
}

static void SubPopApplyTextStyle(NSXMLElement *node,NSDictionary *input) {
    NSDictionary *s=SubPopNormalizeTap5aStyle(input);NSArray *rgb=s[@"textColor"];
    NSDictionary *attrs=@{@"font":s[@"textFont"],@"fontFace":s[@"textFace"],@"fontSize":[s[@"textSize"] stringValue],@"kerning":[s[@"kerning"] stringValue],@"lineSpacing":[s[@"lineSpacing"] stringValue],@"fontColor":[NSString stringWithFormat:@"%.9g %.9g %.9g 1",[rgb[0] doubleValue],[rgb[1] doubleValue],[rgb[2] doubleValue]]};
    for (NSXMLElement *old in [node elementsForName:@"param"]) if ([[old attributeForName:@"key"].stringValue isEqual:@"MotionTextStyle:SimpleValues"]) [old detach];
    NSXMLElement *simple=[NSXMLElement elementWithName:@"param"];
    [simple addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:@"MotionSimpleValues"]];[simple addAttribute:[NSXMLNode attributeWithName:@"key" stringValue:@"MotionTextStyle:SimpleValues"]];
    NSXMLElement *tracking=[NSXMLElement elementWithName:@"param"];
    [tracking addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:@"motionTextTracking"]];[tracking addAttribute:[NSXMLNode attributeWithName:@"key" stringValue:@"tracking"]];[tracking addAttribute:[NSXMLNode attributeWithName:@"value" stringValue:[s[@"kerning"] stringValue]]];[simple addChild:tracking];[node addChild:simple];
    for (NSString *key in @[@"strokeColor",@"strokeWidth",@"shadowColor",@"shadowOffset",@"shadowBlurRadius"]) [node removeAttributeForName:key];
    NSMutableDictionary *effects=[NSMutableDictionary new];
    for (NSString *prefix in @[@"outline",@"shadow"]) if ([s[[prefix stringByAppendingString:@"Enabled"]] boolValue]) {
        NSArray *c=s[[prefix stringByAppendingString:@"Color"]];NSString *color=[NSString stringWithFormat:@"%.9g %.9g %.9g %.9g",[c[0] doubleValue],[c[1] doubleValue],[c[2] doubleValue],[s[[prefix stringByAppendingString:@"Opacity"]] doubleValue]/100];
        if ([prefix isEqual:@"outline"]) {effects[@"strokeColor"]=color;effects[@"strokeWidth"]=[@(-[s[@"outlineWidth"] doubleValue]) stringValue];}
        else {effects[@"shadowColor"]=color;effects[@"shadowOffset"]=[NSString stringWithFormat:@"%@ %@",s[@"shadowDistance"],s[@"shadowAngle"]];effects[@"shadowBlurRadius"]=[@([s[@"shadowBlur"] doubleValue]*2) stringValue];}
    }
    for (NSString *key in effects) [node addAttribute:[NSXMLNode attributeWithName:key stringValue:effects[key]]];
    [node removeAttributeForName:@"bold"];[node removeAttributeForName:@"italic"];
    for (NSString *key in attrs) {[node removeAttributeForName:key];[node addAttribute:[NSXMLNode attributeWithName:key stringValue:attrs[key]]];}
}

// FCPXML transform coordinates use percentage of the sequence height on both axes.
// Start from SubPop's canonical 0,-40 baseline every time, never accumulate offsets.
static void SubPopApplyTitlePosition(NSXMLDocument *doc,NSDictionary *input) {
    NSDictionary *s=SubPopNormalizeTap5aStyle(input);
    NSXMLElement *format=[doc nodesForXPath:@"/fcpxml/resources/format" error:nil].firstObject;
    double height=[format attributeForName:@"height"].stringValue.doubleValue;if (!isfinite(height) || height<=0) return;
    NSString *position=[NSString stringWithFormat:@"%.12g %.12g",[s[@"positionX"] doubleValue]*100/height,-40+[s[@"positionY"] doubleValue]*100/height];
    for (NSXMLElement *title in [doc nodesForXPath:@"/fcpxml/clip/spine/title" error:nil]) {
        NSXMLElement *transform=[title elementsForName:@"adjust-transform"].firstObject;
        if (!transform) {transform=[NSXMLElement elementWithName:@"adjust-transform"];[title addChild:transform];}
        [transform removeAttributeForName:@"position"];[transform addAttribute:[NSXMLNode attributeWithName:@"position" stringValue:position]];
    }
}
