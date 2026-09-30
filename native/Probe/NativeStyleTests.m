// Isolated preferences + offscreen editor checks. No FCP or model invocation.
#import "ProbeViewController.m"
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
        NSString *suite=[@"com.chokamin.SubPop.style-test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        SubPopNativePresetStore *store=[[SubPopNativePresetStore alloc] initWithDefaults:defaults];
        check(store.presets.count==0 && !store.defaultID.length,@"first installation has no saved presets");
        NSDictionary *style=SubPopNormalizeNativeStyle(@{@"textFont":@"Helvetica",@"textFace":@"Bold",@"textSize":@72,@"opacity":@95,@"roundness":@20,@"boxHeight":@-8,@"boxWidth":@15,@"positionX":@-300,@"positionY":@200,@"animationStyle":@4,@"animateBy":@2,@"fillColor":@[@1,@0.5,@0],@"verticalSafe":@1});
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
        check([title elementsForName:@"param"].count==11,@"idempotent published parameters");
        SubPopApplyTextStyle([title nodesForXPath:@"text-style-def/text-style" error:nil].firstObject,style);
        check([SubPopNativeStyleFromTitle(title) isEqual:style],@"published values and text style round-trip");
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
        check(c.editingNativeStyle && c.tap5aStyleControls.count==17 && window.attachedSheet!=nil,@"native editor opens with all supported controls");
        [c fillNativeStyleControls:style];check([[c currentTap5aStyleValues] isEqual:style],@"editor preserves all published units including negative height and animation tags");
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
        check(!c.editingNativeStyle && !c.tap5aStyleControls && [c.nativeStyle isEqual:oldStyle] && [c.titlePayloads isEqual:before],@"cancel leaves current captions and style untouched even after deliberate preset save");
        [c showNativeStyle:nil];[c.nativePresetPicker selectItemAtIndex:2];[c nativePresetChanged:c.nativePresetPicker];
        [window endSheet:window.attachedSheet returnCode:NSAlertFirstButtonReturn];spin();
        check([c.nativeStyle isEqual:style] && ![c.titlePayloads isEqual:before],@"apply loads saved native style onto current captions");
        NSXMLDocument *applied=[[NSXMLDocument alloc] initWithData:c.titlePayloads[@"1.14"] options:0 error:nil];
        check([[applied nodesForXPath:@"//title/param[@name='Background Height']/@value" error:nil].firstObject.stringValue isEqual:@"0.46"],@"applied payload contains native published height");
        c.nativeStyle=nil;[c templateChanged:nil];check([c.nativeStyle isEqual:style],@"new result selecting native uses saved default");
        [c.templatePicker selectItemAtIndex:SubPopTitleTemplateBasic];[c templateChanged:nil];
        check(![c.templatePicker.titleOfSelectedItem containsString:@"自适应"],@"plain subtitle remains independently selectable");
        [window orderOut:nil];[defaults removePersistentDomainForName:suite];
        puts("Native style: XML units/timing, preset persistence, defaults, cancel/apply, and sheet controls passed.");
    }return 0;
}
