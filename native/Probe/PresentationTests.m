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
        controller.templatePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[controller.templatePicker addItemsWithTitles:@[@"Basic",@"Tap5a"]];
        controller.tap5aURL=[NSURL fileURLWithPath:@"/tmp/Titles.localized/Tap5a/Tap5a Autosize Text Background/Tap5a Autosize Text Background.moti"];
        if (SubPopTap5aUID([NSURL fileURLWithPath:@"/tmp/Other.moti"])) return 24;
        [controller.templatePicker selectItemAtIndex:1];[controller rebuildTitles];
        for (NSString *v in basic) {
            NSXMLDocument *before=[[NSXMLDocument alloc] initWithData:basic[v] options:0 error:nil];
            NSXMLDocument *after=[[NSXMLDocument alloc] initWithData:controller.titlePayloads[v] options:0 error:nil];
            NSXMLElement *effect=[after nodesForXPath:@"/fcpxml/resources/effect[@id='r2']" error:nil].firstObject;
            if (![[effect attributeForName:@"uid"].stringValue isEqual:SubPopTap5aUID(controller.tap5aURL)]) return 25;
            NSArray *a=[before nodesForXPath:@"//title" error:nil],*b=[after nodesForXPath:@"//title" error:nil];
            if (a.count!=b.count) return 26;
            for (NSUInteger i=0;i<a.count;i++) {
                for (NSString *key in @[@"offset",@"start",@"duration",@"ref"]) if (![[a[i] attributeForName:key].stringValue isEqual:[b[i] attributeForName:key].stringValue]) return 27;
                if (![[a[i] nodesForXPath:@"text" error:nil].firstObject.XMLString isEqual:[b[i] nodesForXPath:@"text" error:nil].firstObject.XMLString]) return 28;
                NSArray *params=[b[i] nodesForXPath:@"param[@key='9999/10658/100/1825821409/2/100'][@value='1']" error:nil];if (params.count!=1) return 29;
            }
            [controller.titlePayloads[v] writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"Tap5a-%@.fcpxml",v]] atomically:YES];
        }
        [controller.templatePicker selectItemAtIndex:0];[controller rebuildTitles];
        for (NSString *v in basic) {
            NSXMLDocument *after=[[NSXMLDocument alloc] initWithData:controller.titlePayloads[v] options:0 error:nil];
            if ([after nodesForXPath:@"//title/param" error:nil].count || ![[[after nodesForXPath:@"/fcpxml/resources/effect/@uid" error:nil] firstObject].stringValue isEqual:SubPopBasicTitleUID]) return 30;
        }
        printf("Tap5a conversion: text, timing, background enabled, and round-trip to Basic passed.\n");
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
