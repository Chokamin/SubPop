// AppKit regression harness. No FCP host, no windows, no timeline writes.
#import "ProbeViewController.m"
@interface SubPopDragObserverTests : SubPopProbeViewController
@property NSUInteger snapshotCount;
@end
@implementation SubPopDragObserverTests
- (void)snapshot:(NSString *)reason { self.snapshotCount++; }
- (void)record:(NSDictionary *)value {}
@end
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc!=2) return 2;
        [NSApplication sharedApplication];
        NSString *directory=@(argv[1]);
        NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"captions.json"]] options:0 error:nil];
        SubPopProbeViewController *controller=[SubPopProbeViewController new];
        // UI identity guards use one observer-delivered snapshot, without live SDK calls.
        controller.observed=YES;controller.observedProjectUID=@"project-a";controller.dropUID=@"project-a";
        controller.observedProjectDuration=CMTimeMake(111104,12800);controller.dropDuration=CMTimeMake(217,25);
        if (![controller isolatedProjectActive]) return 7;
        controller.observedProjectUID=@"project-b";if ([controller isolatedProjectActive]) return 8;
        controller.observedProjectUID=@"project-a";controller.observedProjectDuration=kCMTimeInvalid;if ([controller isolatedProjectActive]) return 9;
        controller.observedProjectDuration=CMTimeMake(9,1);if ([controller isolatedProjectActive]) return 10;
        controller.observedProjectDuration=controller.dropDuration;controller.observed=NO;if ([controller isolatedProjectActive]) return 11;
        NSString *longInput=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [@"<fcpxml><project uid='project-a' name='Long project'/></fcpxml>" writeToFile:longInput atomically:YES encoding:NSUTF8StringEncoding error:nil];
        controller.observed=YES;controller.observedProjectDuration=CMTimeMake(7200,1);
        controller.freshDropURL=[NSURL fileURLWithPath:longInput];[controller validateDroppedProject];
        if (!controller.freshDropURL || ![controller isolatedProjectActive]) return 14;
        controller.observedProjectDuration=kCMTimeZero;[controller validateDroppedProject];
        if (controller.freshDropURL) return 15;
        [[NSFileManager defaultManager] removeItemAtPath:longInput error:nil];
        NSArray *terms=[controller parseVocabulary:@" 小蚕，USB-C\n3.5%;小蚕"];
        if (![terms isEqual:@[@"小蚕",@"USB-C",@"3.5%"]]) return 12;
        if ([controller parseVocabulary:[@"x" stringByPaddingToLength:65 withString:@"x" startingAtIndex:0]]) return 13;
        controller.resultManifest=manifest;controller.captionRows=[NSMutableArray new];
        for (NSDictionary *row in manifest[@"captions"]) [controller.captionRows addObject:row.mutableCopy];
        NSMutableDictionary *payloads=[NSMutableDictionary new];
        for (NSString *v in @[@"1.12",@"1.13",@"1.14"]) payloads[v]=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"TitleProbe-%@.fcpxml",v]]];
        controller.titlePayloads=payloads;
        controller.fontPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[controller.fontPicker addItemWithTitle:@"PingFang SC"];
        controller.sizePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[controller.sizePicker addItemWithTitle:@"48"];
        controller.captionTable=[NSTableView new];
        NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"text"];
        [controller tableView:controller.captionTable setObjectValue:@"校对 & <保留> 3.5% USB-C" forTableColumn:column row:0];
        for (NSString *v in payloads) {
            NSXMLDocument *before=[[NSXMLDocument alloc] initWithData:payloads[v] options:0 error:nil];
            NSXMLDocument *after=[[NSXMLDocument alloc] initWithData:controller.titlePayloads[v] options:0 error:nil];
            NSXMLElement *basicEffect=[after nodesForXPath:@"/fcpxml/resources/effect[@id='r2']" error:nil].firstObject;
            if (![[basicEffect attributeForName:@"uid"].stringValue isEqual:SubPopBasicTitleUID]) return 81;
            if ([after nodesForXPath:@"/fcpxml/clip/spine/title/adjust-transform[@position='0 -40']" error:nil].count!=controller.captionRows.count) return 82;
            if ([after nodesForXPath:@"/fcpxml/clip/spine/title/param" error:nil].count) return 83;
            NSArray *a=[before nodesForXPath:@"/fcpxml/clip/spine/title" error:nil],*b=[after nodesForXPath:@"/fcpxml/clip/spine/title" error:nil];
            if (a.count!=b.count || !b.count) return 3;
            for (NSUInteger i=0;i<a.count;i++) {
                for (NSString *key in @[@"offset",@"duration",@"ref"]) if (![[a[i] attributeForName:key].stringValue isEqual:[b[i] attributeForName:key].stringValue]) return 4;
                NSXMLElement *style=[b[i] nodesForXPath:@"text-style-def/text-style" error:nil].firstObject;
                if (![[style attributeForName:@"font"].stringValue isEqual:@"PingFang SC"] || ![[style attributeForName:@"fontSize"].stringValue isEqual:@"48"]) return 5;
            }
            NSXMLNode *text=[b[0] nodesForXPath:@"text/text-style" error:nil].firstObject;
            if (![text.stringValue isEqual:@"校对 & <保留> 3.5% USB-C"]) return 6;
        }
        // Convert existing results without ASR; preserve edited text and every timing attribute.
        NSString *tempRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSURL *validURL=[NSURL fileURLWithPath:[tempRoot stringByAppendingPathComponent:@"Titles.localized/Tap5a/Template/Tap5a Autosize Text Background.moti"]];
        [NSFileManager.defaultManager createDirectoryAtURL:validURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [@"<ozml><publishSettings><target object='1825821409'/><target object='10924'/><target object='10924'/></publishSettings></ozml>" writeToURL:validURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (!SubPopValidTap5a(validURL)) return 31;
        [@"<ozml/>" writeToURL:validURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (SubPopValidTap5a(validURL)) return 32;
        [NSFileManager.defaultManager removeItemAtPath:tempRoot error:nil];
        NSDictionary *basic=controller.titlePayloads;
        controller.templatePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[controller.templatePicker addItemsWithTitles:@[@"Basic",@"Native",@"Tap5a"]];
        for (NSNumber *index in @[@(SubPopTitleTemplateBasic),@(SubPopTitleTemplateNative),@(SubPopTitleTemplateTap5a)]) {
            NSDictionary *draft=@{@"templateID":SubPopTitleTemplateID(index.integerValue),@"titleTemplate":@YES};
            if (SubPopTitleTemplateFromDraft(draft)!=index.integerValue) return 84;
        }
        if (SubPopTitleTemplateFromDraft(@{})!=SubPopTitleTemplateBasic || SubPopTitleTemplateFromDraft(@{@"templateID":@"unknown"})!=SubPopTitleTemplateBasic || SubPopTitleTemplateFromDraft(@{@"titleTemplate":@YES})!=SubPopTitleTemplateTap5a) return 85;
        controller.tap5aURL=[NSURL fileURLWithPath:@"/tmp/Titles.localized/Tap5a/Tap5a Autosize Text Background/Tap5a Autosize Text Background.moti"];
        if (SubPopTap5aUID([NSURL fileURLWithPath:@"/tmp/Other.moti"])) return 24;
        controller.tap5aStyle=SubPopNormalizeTap5aStyle(@{@"positionX":@120,@"positionY":@108,@"outlineEnabled":@1,@"outlineWidth":@3,@"shadowEnabled":@1,@"shadowBlur":@7,@"glowEnabled":@1,@"glowRadius":@12,@"textFace":@"Bold",@"kerning":@3.5,@"lineSpacing":@12,@"textColor":@[@1,@0.5,@0],@"roundness":@30,@"opacity":@65,@"width":@12,@"border":@1,@"top":@25,@"backgroundColor":@[@0.1,@0.2,@0.3]});
        NSXMLElement *disabled=[NSXMLElement elementWithName:@"text-style"];
        SubPopApplyTextStyle(disabled,controller.tap5aStyle);SubPopApplyTextStyle(disabled,@{});
        if ([disabled attributeForName:@"strokeWidth"] || [disabled attributeForName:@"shadowColor"]) return 47;
        NSXMLDocument *positionDoc=[[NSXMLDocument alloc] initWithXMLString:@"<fcpxml><resources><format height='2160'/></resources><clip><spine><title><adjust-transform position='0 -40'/></title></spine></clip></fcpxml>" options:0 error:nil];
        SubPopApplyTitlePosition(positionDoc,@{@"positionX":@216,@"positionY":@432});NSString *once=positionDoc.XMLString;
        SubPopApplyTitlePosition(positionDoc,@{@"positionX":@216,@"positionY":@432});
        if (![once isEqual:positionDoc.XMLString] || ![[positionDoc nodesForXPath:@"//adjust-transform/@position" error:nil].firstObject.stringValue isEqual:@"10 -20"]) return 49;
        SubPopApplyTitlePosition(positionDoc,@{});if (![[positionDoc nodesForXPath:@"//adjust-transform/@position" error:nil].firstObject.stringValue isEqual:@"0 -40"]) return 50;
        NSDictionary *invalid=SubPopNormalizeTap5aStyle(@{@"roundness":@999,@"width":@(-1),@"top":@(NAN),@"backgroundColor":@[@1]});
        if ([invalid[@"roundness"] doubleValue]!=100 || [invalid[@"width"] doubleValue]!=3 || [invalid[@"top"] doubleValue]!=10 || ![invalid[@"backgroundColor"] isEqual:@[@0,@0,@0]]) return 41;
        [controller.templatePicker selectItemAtIndex:SubPopTitleTemplateTap5a];[controller rebuildTitles];
        for (NSString *v in basic) {
            NSXMLDocument *before=[[NSXMLDocument alloc] initWithData:basic[v] options:0 error:nil];
            NSXMLDocument *after=[[NSXMLDocument alloc] initWithData:controller.titlePayloads[v] options:0 error:nil];
            NSXMLElement *effect=[after nodesForXPath:@"/fcpxml/resources/effect[@id='r2']" error:nil].firstObject;
            if (![[effect attributeForName:@"uid"].stringValue isEqual:SubPopTap5aUID(controller.tap5aURL)] || ![[effect attributeForName:@"src"].stringValue isEqual:controller.tap5aURL.absoluteString]) return 25;
            NSArray *a=[before nodesForXPath:@"//title" error:nil],*b=[after nodesForXPath:@"//title" error:nil];
            if (a.count!=b.count) return 26;
            for (NSUInteger i=0;i<a.count;i++) {
                for (NSString *key in @[@"offset",@"start",@"duration",@"ref"]) if (![[a[i] attributeForName:key].stringValue isEqual:[b[i] attributeForName:key].stringValue]) return 27;
                if (![[a[i] nodesForXPath:@"text" error:nil].firstObject.XMLString isEqual:[b[i] nodesForXPath:@"text" error:nil].firstObject.XMLString]) return 28;
                NSArray *params=[b[i] nodesForXPath:@"param[@key='9999/10658/100/1825821409/2/100'][@value='1']" error:nil];if (params.count!=1) return 29;
                if ([b[i] nodesForXPath:@"param[@name='Roundness'][@value='0.3']" error:nil].count!=1 || [b[i] nodesForXPath:@"param[@name='Top'][@value='0.25']" error:nil].count!=1 || [b[i] nodesForXPath:@"param[@name='Color'][@value='0.1 0.2 0.3']" error:nil].count!=1) return 42;
                NSXMLElement *ts=[b[i] nodesForXPath:@"text-style-def/text-style" error:nil].firstObject;
                if (![[ts attributeForName:@"kerning"].stringValue isEqual:@"3.5"] || ![[ts attributeForName:@"lineSpacing"].stringValue isEqual:@"12"] || ![[ts attributeForName:@"fontColor"].stringValue isEqual:@"1 0.5 0 1"]) return 44;
                if ([ts nodesForXPath:@"param[@key='MotionTextStyle:SimpleValues']/param[@key='tracking'][@value='3.5']" error:nil].count!=1) return 45;
                if (![[ts attributeForName:@"strokeWidth"].stringValue isEqual:@"-3"] || ![[ts attributeForName:@"shadowBlurRadius"].stringValue isEqual:@"14"] || [b[i] nodesForXPath:@"param[@key='9999/1825821564/10045/10047/5/10049/38'][@value='1']" error:nil].count!=1) return 46;
                double height=[after nodesForXPath:@"/fcpxml/resources/format/@height" error:nil].firstObject.stringValue.doubleValue;
                NSString *expectedPosition=[NSString stringWithFormat:@"%.12g %.12g",12000/height,-40+10800/height];
                if (![[b[i] nodesForXPath:@"adjust-transform/@position" error:nil].firstObject.stringValue isEqual:expectedPosition]) return 48;
                NSXMLElement *width=[b[i] nodesForXPath:@"param[@name='Width']" error:nil].firstObject;
                if (fabs([width attributeForName:@"value"].stringValue.doubleValue - 9.0/97)>1e-8) return 43;
            }
            [controller.titlePayloads[v] writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"Tap5a-%@.fcpxml",v]] atomically:YES];
            NSError *importError=nil;
            NSData *importData=SubPopTitleImportXML(controller.titlePayloads[v],@"项目 & <测试>",1,&importError);
            NSXMLDocument *importDoc=[[NSXMLDocument alloc] initWithData:importData options:NSXMLNodeLoadExternalEntitiesNever error:nil];
            NSString *importXML=[[NSString alloc] initWithData:importData encoding:NSUTF8StringEncoding];
            if (!importData || importError || [importXML containsString:@"standalone=\"yes\""]) return 33;
            NSArray *importTitles=[importDoc nodesForXPath:@"/fcpxml/event/clip/spine/title" error:nil];
            if (importTitles.count!=b.count || [importDoc nodesForXPath:@"//project|//library|/fcpxml/clip" error:nil].count) return 34;
            if (![[importDoc nodesForXPath:@"/fcpxml/event/@name" error:nil].firstObject.stringValue isEqual:@"SubPop 字幕 001"] ||
                ![[importDoc nodesForXPath:@"/fcpxml/event/clip/@name" error:nil].firstObject.stringValue isEqual:@"项目 & <测试> · Tap5a 字幕 001"]) return 35;
            NSData *second=SubPopTitleImportXML(controller.titlePayloads[v],@"项目 & <测试>",2,nil);
            NSXMLDocument *secondDoc=[[NSXMLDocument alloc] initWithData:second options:NSXMLNodeLoadExternalEntitiesNever error:nil];
            if (![[secondDoc nodesForXPath:@"/fcpxml/event/clip/@name" error:nil].firstObject.stringValue isEqual:@"项目 & <测试> · Tap5a 字幕 002"]) return 62;
            if ([secondDoc nodesForXPath:@"/fcpxml/event/clip/@uid" error:nil].count) return 63;
            if (![[secondDoc nodesForXPath:@"/fcpxml/event/@name" error:nil].firstObject.stringValue isEqual:@"SubPop 字幕 002"] ||
                [secondDoc nodesForXPath:@"/fcpxml/event/clip" error:nil].count!=1) return 64;
            for (NSUInteger i=0;i<b.count;i++) {
                NSXMLElement *original=b[i],*imported=importTitles[i];
                for (NSString *key in @[@"offset",@"start",@"duration",@"ref"]) if (![[original attributeForName:key].stringValue isEqual:[imported attributeForName:key].stringValue]) return 36;
                if (![[original nodesForXPath:@"text/text-style" error:nil].firstObject.stringValue isEqual:[imported nodesForXPath:@"text/text-style" error:nil].firstObject.stringValue] || [imported elementsForName:@"param"].count!=17) return 37;
            }
            [importData writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"Tap5a-Import-%@.fcpxml",v]] atomically:YES];
        }
        for (NSString *bad in @[@"",@"<fcpxml><project/></fcpxml>",@"<fcpxml><clip><spine/></clip></fcpxml>"]) {
            NSError *error=nil;
            if (SubPopTitleImportXML([bad dataUsingEncoding:NSUTF8StringEncoding],@"Test",1,&error) || !error) return 38;
        }
        puts("Tap5a file import: all versions preserve titles and timing; no project/library writes; invalid results rejected.");
        [controller.templatePicker selectItemAtIndex:SubPopTitleTemplateBasic];[controller rebuildTitles];
        for (NSString *v in basic) {
            NSXMLDocument *after=[[NSXMLDocument alloc] initWithData:controller.titlePayloads[v] options:0 error:nil];
            if ([after nodesForXPath:@"/fcpxml/resources/effect/@src" error:nil].count || [after nodesForXPath:@"//title/param" error:nil].count || ![[[after nodesForXPath:@"/fcpxml/resources/effect/@uid" error:nil] firstObject].stringValue isEqual:SubPopBasicTitleUID]) return 30;
        }
        NSDictionary *plain=[controller.titlePayloads copy];
        [controller.templatePicker selectItemAtIndex:SubPopTitleTemplateNative];[controller rebuildTitles];
        for (NSString *v in basic) {
            NSXMLDocument *native=[[NSXMLDocument alloc] initWithData:controller.titlePayloads[v] options:0 error:nil];
            if (![[[native nodesForXPath:@"/fcpxml/resources/effect/@uid" error:nil] firstObject].stringValue isEqual:SubPopNativeSubtitleUID] || [native nodesForXPath:@"//title/param|//title/adjust-transform" error:nil].count) return 86;
            if ([native nodesForXPath:@"//title[@start='3600s']" error:nil].count!=controller.captionRows.count) return 87;
            NSXMLDocument *before=[[NSXMLDocument alloc] initWithData:plain[v] options:0 error:nil];
            NSArray *a=[before nodesForXPath:@"//title" error:nil],*b=[native nodesForXPath:@"//title" error:nil];
            for (NSUInteger i=0;i<a.count;i++) {
                for (NSString *key in @[@"offset",@"duration"]) if (![[a[i] attributeForName:key].stringValue isEqual:[b[i] attributeForName:key].stringValue]) return 88;
                if (![[a[i] nodesForXPath:@"text" error:nil].firstObject.XMLString isEqual:[b[i] nodesForXPath:@"text" error:nil].firstObject.XMLString]) return 89;
            }
        }
        [controller.templatePicker selectItemAtIndex:SubPopTitleTemplateBasic];[controller rebuildTitles];
        if (![plain isEqual:controller.titlePayloads]) return 90;
        printf("Three templates: Basic default, Native/Tap5a conversion, plain round-trip and draft identities passed.\n");
        // Delayed pasteboard requests must survive result cleanup and later edits.
        NSMutableData *mutable=[controller.titlePayloads[@"1.14"] mutableCopy];
        NSMutableDictionary *source=[controller.titlePayloads mutableCopy];source[@"1.14"]=mutable;
        NSData *expected=mutable.copy;
        SubPopTitleDragProvider *provider=[[SubPopTitleDragProvider alloc] initWithPayloads:source];
        [mutable setLength:0];[source removeAllObjects];controller.titlePayloads=nil;
        for (NSString *type in @[@"com.apple.finalcutpro.xml",@"com.apple.finalcutpro.xml.v1-14",@"com.apple.finalcutpro.xml.v1-13",@"com.apple.finalcutpro.xml.v1-12"]) {
            NSPasteboardItem *item=[NSPasteboardItem new];
            [provider pasteboard:nil item:item provideDataForType:type];
            NSString *version=[type hasSuffix:@"v1-12"] ? @"1.12" : ([type hasSuffix:@"v1-13"] ? @"1.13" : @"1.14");
            NSData *wanted=[version isEqual:@"1.14"] ? expected : provider.payloads[version];
            if (![[item dataForType:type] isEqual:wanted]) return 16;
        }
        NSPasteboardItem *promised=[NSPasteboardItem new];
        __weak SubPopTitleDragProvider *retainedProvider;
        @autoreleasepool {
            SubPopTitleDragProvider *temporary=[[SubPopTitleDragProvider alloc] initWithPayloads:provider.payloads];
            retainedProvider=temporary;
            if (![promised setDataProvider:temporary forTypes:@[@"com.apple.finalcutpro.xml.v1-14"]]) return 21;
        }
        if (!retainedProvider || ![[promised dataForType:@"com.apple.finalcutpro.xml.v1-14"] isEqual:expected]) return 22;
        NSPasteboardItem *prepared=[provider preparedItem];
        if (prepared.types.count!=4) return 33;
        provider.isCurrentProject=^BOOL { return NO; };
        if ([provider preparedItem]) return 34;
        if (![[prepared dataForType:@"com.apple.finalcutpro.xml"] isEqual:expected]) return 35;
        SubPopDragObserverTests *retention=[SubPopDragObserverTests new];
        retention.titlePayloads=payloads;retention.resultDate=NSDate.date;retention.captionRows=[NSMutableArray arrayWithObject:@{@"text":@"保留识别结果"}];
        retention.freshDropURL=[NSURL fileURLWithPath:@"/tmp/retained-input.fcpxml"];
        for (NSNumber *operation in @[@(NSDragOperationNone),@(NSDragOperationCopy),@(NSDragOperationEvery)]) {
            [retention draggingSession:(NSDraggingSession *)[NSObject new] endedAtPoint:NSZeroPoint operation:operation.unsignedIntegerValue];
            if (!retention.titlePayloads || !retention.resultDate || !retention.captionRows || !retention.freshDropURL) return 36;
        }
        provider.isCurrentProject=^BOOL { return NO; };
        NSPasteboardItem *blocked=[NSPasteboardItem new];
        [provider pasteboard:nil item:blocked provideDataForType:@"com.apple.finalcutpro.xml.v1-14"];
        if (blocked.types.count) return 23;
        provider.isCurrentProject=nil;
        NSPasteboardItem *unknown=[NSPasteboardItem new];
        [provider pasteboard:nil item:unknown provideDataForType:@"public.text"];
        if (unknown.types.count) return 17;
        SubPopDragObserverTests *observer=[SubPopDragObserverTests new];
        for (int i=0;i<1000;i++) [observer playheadTimeChanged];
        if (observer.snapshotCount!=1) return 18;
        observer.titlePayloads=payloads;observer.dropGeneration=7;
        [observer sequenceTimeRangeChanged];
        if (observer.snapshotCount!=2) return 19;
        [observer activeSequenceChanged];
        if (observer.snapshotCount!=3 || observer.titlePayloads || observer.dropGeneration!=8) return 20;
        CFTimeInterval started=CACurrentMediaTime();
        for (int i=0;i<100;i++) {
            NSPasteboardItem *item=[NSPasteboardItem new];
            [provider pasteboard:nil item:item provideDataForType:@"com.apple.finalcutpro.xml.v1-14"];
        }
        printf("Cached pasteboard transfer: 100 requests, %lu bytes each, %.3f ms total; delayed-data and observer guards passed.\n",(unsigned long)expected.length,(CACurrentMediaTime()-started)*1000);
        puts("AppKit proofreading: all 3 XML versions updated, timing preserved, XML text escaped, font and size applied.");
        return 0;
    }
}
