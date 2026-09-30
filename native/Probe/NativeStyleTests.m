// Isolated preferences + offscreen editor checks. No FCP or model invocation.
#import "ProbeViewController.m"
#import "PreviewGeometryTests.h"
@interface SubPopNativeStyleTestController : SubPopProbeViewController
@end
@implementation SubPopNativeStyleTestController
- (void)restoreSession {}
- (void)saveDraft {}
- (BOOL)workerAvailable {return YES;}
- (BOOL)selectedModelAvailable {return YES;}
- (BOOL)isolatedProjectActive {return YES;}
@end
static void spin(void) {[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.12]];}
static void check(BOOL ok,NSString *message) {if (!ok) {fprintf(stderr,"Native style check failed: %s\n",message.UTF8String);exit(1);}}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        check(argc==3 || argc==4,@"expected fixture and output folder, optional preview");[NSApplication sharedApplication];
        check(SubPopCheckPreviewGeometry(),@"shared Tap5a preview geometry remains intact");
        NSString *suite=[@"com.chokamin.SubPop.style-test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        SubPopNativePresetStore *store=[[SubPopNativePresetStore alloc] initWithDefaults:defaults];
        check(store.presets.count==0 && !store.defaultID.length,@"first installation has no saved presets");
        NSDictionary *style=SubPopNormalizeNativeStyle(@{@"textFont":@"Helvetica",@"textFace":@"Bold",@"textSize":@72,@"kerning":@8.64,@"opacity":@95,@"roundness":@20,@"boxHeight":@-8,@"boxWidth":@15,@"positionX":@-300,@"positionY":@200,@"textPositionX":@37,@"textPositionY":@-125.457,@"textPositionZ":@12,@"outlineEnabled":@1,@"outlineWidth":@3,@"outlineColor":@[@1,@0,@0],@"shadowEnabled":@1,@"shadowBlur":@7,@"shadowDistance":@8,@"shadowAngle":@120,@"glowEnabled":@1,@"glowColor":@[@0,@1,@0],@"glowRadius":@12,@"glowBlur":@9,@"glowOpacity":@65,@"animationStyle":@4,@"animateBy":@2,@"fillColor":@[@1,@0.5,@0],@"verticalSafe":@1});
        NSString *first=[store saveStyle:style name:@"黑底白字"];
        NSString *second=[store saveStyle:@{@"opacity":@50} name:@"浅底框"];
        [store setDefaultID:first];
        check(first.length && second.length && store.presets.count==2,@"multiple named presets");
        SubPopNativePresetStore *reopened=[[SubPopNativePresetStore alloc] initWithDefaults:[[NSUserDefaults alloc] initWithSuiteName:suite]];
        check([reopened.defaultStyle isEqual:style] && [reopened.defaultID isEqual:first],@"default survives preferences reopening");
        check([[store saveStyle:style name:@" 黑底白字 "] isEqual:first] && store.presets.count==2,@"same name updates stable identity without deleting other presets");
        check(![store saveStyle:style name:@"\n"] && ![store saveStyle:style name:@"bad\nname"],@"invalid name rejected");
        [store removeID:second];check([store.defaultID isEqual:first],@"unrelated deletion preserves default");
        [store removeID:first];check(!store.defaultID.length && store.presets.count==0,@"deleting default resets to built-in style");
        check([SubPopNormalizeNativeStyle(@{@"positionX":@-3000,@"boxHeight":@(NAN),@"animationStyle":@2})[@"positionX"] doubleValue]==-2000,@"native geometry clamps independently of Tap5a");
        NSString *xml=[NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:nil];
        NSXMLDocument *doc=[[NSXMLDocument alloc] initWithXMLString:xml options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        check(doc!=nil,@"fixture parses");
        NSXMLElement *title=[doc nodesForXPath:@"//title" error:nil].firstObject;
        NSString *offset=[title attributeForName:@"offset"].stringValue,*duration=[title attributeForName:@"duration"].stringValue;
        NSString *caption=[title nodesForXPath:@"text" error:nil].firstObject.XMLString;
        SubPopSetNativeSubtitle(doc);SubPopApplyNativeStyle(doc,style);SubPopApplyNativeStyle(doc,style);
        check([title elementsForName:@"param"].count==18,@"idempotent published parameters and text position");
        check([title nodesForXPath:@"param[@key='9999/3336674837/3336674846/5/3336674848/38/40'][@value='0 1 0']" error:nil].count==1 && [title nodesForXPath:@"param[@key='9999/3336674837/3336674846/5/3336674848/38/39'][@value='0']" error:nil].count==1,@"FCP verified glow Color 40 and Fill 39 keys");
        SubPopApplyTextStyle([title nodesForXPath:@"text-style-def/text-style" error:nil].firstObject,style);
        check([SubPopNativeStyleFromTitle(title) isEqual:style],@"published values and text style round-trip");
        NSXMLElement *position=[title nodesForXPath:@"param[@name='Position']" error:nil].firstObject;
        [position attributeForName:@"name"].stringValue=@"位置";
        [position attributeForName:@"value"].stringValue=@"0 -125.457";
        NSDictionary *readPosition=SubPopNativeStyleFromTitle(title);
        check([readPosition[@"textPositionY"] doubleValue]==-125.457 && [readPosition[@"textPositionZ"] doubleValue]==0 && [readPosition[@"positionY"] doubleValue]==200,@"localized FCP two-component position stays independent of rig offset");
        for (NSString *bad in @[@"0",@"0 -125 trailing",@"0 -125 12 99"]) {
            [position attributeForName:@"value"].stringValue=bad;check(SubPopNativeStyleFromTitle(title)==nil,@"invalid position cannot silently become a zero-position preset");
        }
        [position attributeForName:@"value"].stringValue=@"37 -125.457 12";
        NSXMLElement *positionAnimation=[NSXMLElement elementWithName:@"keyframeAnimation"];[position addChild:positionAnimation];
        check(SubPopNativeStyleFromTitle(title)==nil,@"animated text position is not flattened");[positionAnimation detach];
        [position detach];check([SubPopNativeStyleFromTitle(title)[@"textPositionY"] doubleValue]==0,@"old presets and default titles use zero text position");
        SubPopApplyNativeStyle(doc,style);
        NSXMLElement *textStyle=[title nodesForXPath:@"text-style-def/text-style" error:nil].firstObject;
        [textStyle removeAttributeForName:@"fontFace"];[textStyle addAttribute:[NSXMLNode attributeWithName:@"bold" stringValue:@"1"]];
        check([SubPopNativeStyleFromTitle(title)[@"textFace"] isEqual:@"Bold"],@"legacy bold attribute preserves font weight");
        SubPopApplyTextStyle(textStyle,style);
        NSXMLDocument *nested=[[NSXMLDocument alloc] initWithXMLString:@"<fcpxml><resources><effect id='fx'/><media id='used'><sequence><spine><title ref='fx'/><ref-clip ref='used'/></spine></sequence></media><media id='unused'><sequence><spine><title ref='fx'/></spine></sequence></media></resources><project><sequence><spine><ref-clip ref='used'/></spine></sequence></project></fcpxml>" options:0 error:nil];
        [[nested nodesForXPath:@"//effect" error:nil].firstObject addAttribute:[NSXMLNode attributeWithName:@"uid" stringValue:SubPopNativeSubtitleUID]];
        check(SubPopNativeProjectTitles(nested).count==1,@"style reader follows used subtitle wrappers, avoids cycles and ignores unused media");
        check([[title attributeForName:@"offset"].stringValue isEqual:offset] && [[title attributeForName:@"duration"].stringValue isEqual:duration] && [[title nodesForXPath:@"text" error:nil].firstObject.XMLString isEqual:caption],@"caption text and timing untouched");
        NSString *folder=@(argv[2]);[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        [[doc XMLDataWithOptions:NSXMLNodePrettyPrint] writeToFile:[folder stringByAppendingPathComponent:@"native-style.fcpxml"] atomically:YES];
        NSXMLElement *height=[title nodesForXPath:@"param[@name='Background Height']" error:nil].firstObject;
        check(fabs([height attributeForName:@"value"].stringValue.doubleValue-.46)<1e-10,@"-8 inspector height encodes as 0.46");
        NSXMLElement *animation=[NSXMLElement elementWithName:@"keyframeAnimation"];[height addChild:animation];
        check(SubPopNativeStyleFromTitle(title)==nil,@"animated geometry not flattened into a misleading static preset");[animation detach];
        SubPopSetTitleTemplate(doc,nil);check(![title elementsForName:@"param"].count && [[title attributeForName:@"start"].stringValue isEqual:@"0s"],@"native settings do not leak to plain titles");
        SubPopNativeStyleTestController *c=[SubPopNativeStyleTestController new];[c loadView];
        c.resultRequestID=@"native-style-test";c.titlePayloads=@{@"1.14":[xml dataUsingEncoding:NSUTF8StringEncoding]};
        c.captionRows=[NSMutableArray arrayWithObject:[@{@"text":@"测试字幕",@"start_frame":@0,@"end_frame":@25} mutableCopy]];
        c.resultManifest=@{@"width":@1920,@"height":@1080,@"frameDuration":@"1/25s",@"captions":c.captionRows};
        c.nativePresetStore=store;c.nativeStyle=SubPopNormalizeNativeStyle(nil);[c.templatePicker selectItemAtIndex:SubPopTitleTemplateNative];[c syncStyleFontPickers:c.nativeStyle];[c rebuildTitles];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,840,850) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.contentView=c.view;[window orderFront:nil];
        NSDictionary *before=c.titlePayloads.copy,*oldStyle=c.nativeStyle.copy;
        [c showTap5aStyle:nil];spin();
        check(c.editingNativeStyle && c.tap5aStyleControls.count==35 && window.attachedSheet!=nil,@"native editor opens with all supported controls");
        [c fillNativeStyleControls:style];check([[c currentTap5aStyleValues] isEqual:style],@"editor preserves all published units including negative height and animation tags");
        check(fabs([c.tap5aStyleControls[@"kerning"] doubleValue]-12)<1e-9,@"legacy point-based preset displays FCP tracking percentage");
        [c controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:c.tap5aStyleControls[@"kerning"]]];
        check([c.tap5aStyleControls[@"kerning"] doubleValue]==12 && [[c currentTap5aStyleValues][@"kerning"] doubleValue]==8.64,@"committing percentage does not turn it back into points");
        [c.tap5aStyleControls[@"textSize"] setDoubleValue:144];[c tap5aPreviewChanged:nil];
        check([[c currentTap5aStyleValues][@"kerning"] doubleValue]==17.28,@"font-size change retains the entered tracking percentage");
        [c fillNativeStyleControls:style];
        check(c.tap5aPreview.nativeSubtitle && [c.tap5aPreview.style isEqual:style] && [c.tap5aPreview renderLinearPreview]!=nil,@"native preview renders the selected preset without invoking FCP or recognition");
        c.nativePresetName.stringValue=@"测试默认";[c saveNativePreset:nil];[c defaultNativePreset:nil];
        check([store.defaultStyle isEqual:style] && store.presets.count==1,@"save and default actions persist editor settings");
        if (argc==4) {
            window.title=@"SubPop 样式预设验证";
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];[NSApp activateIgnoringOtherApps:YES];
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:55]];
        }
        NSView *sheet=window.attachedSheet.contentView;[sheet layoutSubtreeIfNeeded];
        NSBitmapImageRep *image=[sheet bitmapImageRepForCachingDisplayInRect:sheet.bounds];[sheet cacheDisplayInRect:sheet.bounds toBitmapImageRep:image];
        [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[folder stringByAppendingPathComponent:@"native-style-editor.png"] atomically:YES];
        [window endSheet:window.attachedSheet returnCode:NSAlertSecondButtonReturn];spin();
        check(!c.editingNativeStyle && !c.tap5aStyleControls && !c.tap5aPreview && [c.nativeStyle isEqual:oldStyle] && [c.titlePayloads isEqual:before],@"cancel leaves current captions and style untouched and cleans preview resources");
        [c showNativeStyle:nil];[c.nativePresetPicker selectItemAtIndex:2];[c nativePresetChanged:c.nativePresetPicker];
        [window endSheet:window.attachedSheet returnCode:NSAlertFirstButtonReturn];spin();
        if (![c.nativeStyle isEqual:style] || [c.titlePayloads isEqual:before]) NSLog(@"Native apply: style=%@ expected=%@ unchanged=%d",c.nativeStyle,style,[c.titlePayloads isEqual:before]);
        check([c.nativeStyle isEqual:style] && ![c.titlePayloads isEqual:before],@"apply loads saved native style onto current captions");
        NSXMLDocument *applied=[[NSXMLDocument alloc] initWithData:c.titlePayloads[@"1.14"] options:0 error:nil];
        check([[applied nodesForXPath:@"//title/param[@name='Background Height']/@value" error:nil].firstObject.stringValue isEqual:@"0.46"],@"applied payload contains native published height");
        check([[applied nodesForXPath:@"//title/param[@name='Position']/@value" error:nil].firstObject.stringValue isEqual:@"37 -125.457 12"],@"saved preset restores the text inspector position into every generated title");
        check([[applied nodesForXPath:@"//text-style-def/text-style/@kerning" error:nil].firstObject.stringValue isEqual:@"8.64"],@"12 percent at size 72 exports the original 8.64 points");
        SubPopStylePreview *preview=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,0,640,360)];preview.nativeSubtitle=YES;preview.caption=@"字幕 gjpq";
        NSMutableDictionary *red=[@{@"backgroundColor":@[@1,@0,@0],@"textColor":@[@0,@0,@0],@"opacity":@100,@"roundness":@0,@"textSize":@144,@"textPositionY":@400} mutableCopy];preview.style=red;
        NSRect base=SubPopRedPixelBounds([NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation]);
        red[@"textPositionX"]=@120;red[@"positionX"]=@120;preview.style=red;
        NSRect shifted=SubPopRedPixelBounds([NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation]);
        fprintf(stderr,"Native preview bounds: base %s; shifted %s\n",NSStringFromRect(base).UTF8String,NSStringFromRect(shifted).UTF8String);
        check(base.size.width>0 && fabs(shifted.origin.x-base.origin.x-40)<2 && fabs(shifted.size.width-base.size.width)<2,@"native preview responds to both independent horizontal positions");
        red[@"boxHeight"]=@-8;preview.style=red;
        NSRect tight=SubPopRedPixelBounds([NSBitmapImageRep imageRepWithData:[preview renderLinearPreview].TIFFRepresentation]);
        check(fabs(shifted.size.height-tight.size.height-88.0/6)<2,@"native height adjustment uses its own rig units, independent of Tap5a padding");
        c.nativeStyle=nil;[c templateChanged:nil];check([c.nativeStyle isEqual:style],@"new result selecting native uses saved default");
        [c.templatePicker selectItemAtIndex:SubPopTitleTemplateBasic];[c templateChanged:nil];
        check(![c.templatePicker.titleOfSelectedItem containsString:@"自适应"],@"plain subtitle remains independently selectable");
        [window orderOut:nil];[defaults removePersistentDomainForName:suite];
        puts("Native style: XML units/timing, preset persistence, defaults, cancel/apply, and sheet controls passed.");
    }return 0;
}
