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
static NSDictionary *SubPopNormalizeTap5aStyle(id input) {
    NSDictionary *source=[input isKindOfClass:NSDictionary.class] ? input : @{};
    NSMutableDictionary *result=[NSMutableDictionary new];
    for (NSArray *field in SubPopTap5aFields()) {
        NSString *key=field[0];id value=source[key];
        if ([field[2] isKindOfClass:NSArray.class]) {
            BOOL valid=[value isKindOfClass:NSArray.class] && [value count]==3;
            if (valid) for (id component in value) if (![component isKindOfClass:NSNumber.class] || !isfinite([component doubleValue]) || [component doubleValue]<0 || [component doubleValue]>1) valid=NO;
            result[key]=valid ? value : field[2];
        } else {
            double n=[value isKindOfClass:NSNumber.class] ? [value doubleValue] : [field[2] doubleValue];
            if (!isfinite(n)) n=[field[2] doubleValue];
            n=MAX([field[3] doubleValue],MIN([field[4] doubleValue],n));
            if ([key isEqual:@"sides"] || [key isEqual:@"background"] || [key isEqual:@"border"]) n=round(n);
            result[key]=@(n);
        }
    }
    return result;
}
static void SubPopApplyTap5aStyle(NSXMLDocument *doc, NSDictionary *input) {
    NSDictionary *style=SubPopNormalizeTap5aStyle(input);
    for (NSXMLElement *title in [doc nodesForXPath:@"/fcpxml/clip/spine/title" error:nil]) {
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
