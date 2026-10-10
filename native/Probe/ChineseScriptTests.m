// Real AppKit result/edit/export/draft regression. No FCP, ASR or network calls.
#import "ProbeViewController.m"

@interface SubPopChineseScriptTestController : SubPopProbeViewController
@property NSURL *testEvidenceURL;
@property NSDictionary *testReferenceSettings;
@property NSURL *testOutputURL;
@property NSMutableSet *testOutputCases;
@end
@implementation SubPopChineseScriptTestController
- (NSURL *)evidenceDirectory { return self.testEvidenceURL; }
- (void)updateInterface {}
- (void)record:(NSDictionary *)value {}
- (NSDictionary *)referenceSettings { return self.testReferenceSettings ?: @{}; }
- (BOOL)workerAvailable { return YES; }
- (BOOL)isolatedProjectActive { return YES; }
- (NSString *)titleTemplateDisplayNameForNaming {
    if (self.templatePicker.indexOfSelectedItem==SubPopTitleTemplateTap5a) return nil;
    return self.templatePicker.indexOfSelectedItem==SubPopTitleTemplateNative ? @"Subtitle" : @"基本字幕";
}
@end

static void check(BOOL condition,NSString *message) {
    if (!condition) {
        fprintf(stderr,"Chinese script check failed: %s\n",message.UTF8String);
        exit(1);
    }
}
static NSMutableArray *copyRows(NSArray *rows) {
    NSMutableArray *copy=[NSMutableArray new];
    for (NSDictionary *row in rows) [copy addObject:row.mutableCopy];
    return copy;
}
static NSArray *titleTiming(NSData *data) {
    NSXMLDocument *document=[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
    check(document!=nil,@"title payload parses");
    NSMutableArray *rows=[NSMutableArray new];
    for (NSXMLElement *title in [document nodesForXPath:@"/fcpxml/clip/spine/title" error:nil]) {
        NSMutableDictionary *timing=[NSMutableDictionary new];
        for (NSString *key in @[@"offset",@"start",@"duration",@"lane",@"ref"]) {
            NSString *value=[title attributeForName:key].stringValue;
            if (value) timing[key]=value;
        }
        [rows addObject:timing];
    }
    return rows;
}
static NSDictionary *splitFirstCaptionPayloads(NSDictionary *payloads,NSDictionary *row,long long middle,NSString *frameDuration) {
    long long numerator=0,denominator=0;
    check(SubPopParseFrameDuration(frameDuration,&numerator,&denominator),@"split fixture uses valid frame duration");
    long long begin=[row[@"start_frame"] longLongValue],end=[row[@"end_frame"] longLongValue];
    NSMutableDictionary *result=[NSMutableDictionary new];
    for (NSString *version in payloads) {
        NSXMLDocument *document=[[NSXMLDocument alloc] initWithData:payloads[version] options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        NSXMLElement *first=[document nodesForXPath:@"/fcpxml/clip/spine/title" error:nil].firstObject;
        NSXMLElement *second=first.copy;
        [first attributeForName:@"duration"].stringValue=[NSString stringWithFormat:@"%lld/%llds",(middle-begin)*numerator,denominator];
        [second attributeForName:@"offset"].stringValue=[NSString stringWithFormat:@"%lld/%llds",middle*numerator,denominator];
        [second attributeForName:@"duration"].stringValue=[NSString stringWithFormat:@"%lld/%llds",(end-middle)*numerator,denominator];
        NSXMLElement *definition=[second nodesForXPath:@"text-style-def" error:nil].firstObject;
        NSString *identifier=[[definition attributeForName:@"id"].stringValue stringByAppendingString:@"-split"];
        [definition attributeForName:@"id"].stringValue=identifier;
        [[second nodesForXPath:@"text/text-style" error:nil].firstObject attributeForName:@"ref"].stringValue=identifier;
        NSXMLElement *spine=(NSXMLElement *)first.parent;
        [spine insertChild:second atIndex:[spine.children indexOfObjectIdenticalTo:first]+1];
        result[version]=[document XMLDataWithOptions:0];
    }
    return result;
}
static void checkOutputs(SubPopChineseScriptTestController *controller,NSDictionary *timings,NSArray *baseline) {
    check([controller referenceRows:controller.captionRows matchTimingOf:baseline],@"display preserves all non-text caption data");
    // This corpus is single-line text. Keep the expected template labels
    // independent of the implementation that resolves/names FCP templates.
    NSInteger template=controller.templatePicker.indexOfSelectedItem;
    NSString *templateName=template==SubPopTitleTemplateNative ? @"Subtitle" : @"基本字幕";
    for (NSString *version in @[@"1.12",@"1.13",@"1.14"]) {
        NSData *data=controller.titlePayloads[version];
        check([titleTiming(data) isEqual:timings[version]],@"conversion preserves every title timing in all XML versions");
        NSXMLDocument *document=[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        NSArray *titles=[document nodesForXPath:@"/fcpxml/clip/spine/title" error:nil];
        check(titles.count==controller.captionRows.count,@"conversion preserves subtitle count");
        for (NSUInteger i=0;i<titles.count;i++) {
            NSXMLElement *title=titles[i];NSString *expected=controller.captionRows[i][@"text"];
            NSString *expectedName=template==SubPopTitleTemplateTap5a ? expected : [NSString stringWithFormat:@"%@ - %@",expected,templateName];
            check([[title attributeForName:@"name"].stringValue isEqual:expectedName],@"XML title name uses current converted text with the automatic template suffix, except unchanged Tap5a");
            check([[title nodesForXPath:@"text/text-style" error:nil].firstObject.stringValue isEqual:expected],@"XML text matches display, including escaped characters");
        }
        NSError *error=nil;
        NSData *export=SubPopTitleExportXML(data,@"简繁测试",1,&error);
        check(export!=nil && error==nil,@"converted payload remains exportable");
        NSXMLDocument *exported=[[NSXMLDocument alloc] initWithData:export options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        check([[exported nodesForXPath:@"//title[1]/text/text-style" error:nil].firstObject.stringValue isEqual:controller.captionRows[0][@"text"]],@"FCPXML file export matches preview/display text");
        check([[exported nodesForXPath:@"//title[1]/@name" error:nil].firstObject.stringValue isEqual:[titles.firstObject attributeForName:@"name"].stringValue],@"FCPXML file export preserves the converted automatic name");
    }
    NSError *error=nil;
    NSData *srt=SubPopSRTExportData(controller.captionRows,controller.resultManifest[@"frameDuration"],&error);
    NSString *srtText=[[NSString alloc] initWithData:srt encoding:NSUTF8StringEncoding];
    check(srt!=nil && error==nil,@"converted rows remain SRT exportable");
    for (NSDictionary *row in controller.captionRows) check([srtText containsString:row[@"text"]],@"SRT includes current converted text");
    NSData *originalSRT=SubPopSRTExportData(baseline,controller.resultManifest[@"frameDuration"],nil);
    NSString *originalText=[[NSString alloc] initWithData:originalSRT encoding:NSUTF8StringEncoding];
    NSArray *oldLines=[originalText componentsSeparatedByString:@"\n"],*newLines=[srtText componentsSeparatedByString:@"\n"];
    NSMutableArray *oldTimes=[NSMutableArray new],*newTimes=[NSMutableArray new];
    for (NSString *line in oldLines) if ([line containsString:@" --> "]) [oldTimes addObject:line];
    for (NSString *line in newLines) if ([line containsString:@" --> "]) [newTimes addObject:line];
    check([oldTimes isEqual:newTimes],@"SRT timestamps unchanged by conversion");
    [controller loadTap5aPreviewFrame];
    check([controller.tap5aPreview.caption isEqual:controller.captionRows[0][@"text"]],@"style preview uses current converted text");
    if (controller.testOutputURL) {
        NSString *template=SubPopTitleTemplateID(controller.templatePicker.indexOfSelectedItem);
        NSString *mode=SubPopChineseModeID(controller.chineseTextMode);
        NSString *name=[NSString stringWithFormat:@"Chinese-%@-%@",template,mode];
        // Emit each initial template/mode once. Later draft/undo checks must
        // not overwrite the fixed text used for the real FCP comparison.
        if (![controller.testOutputCases containsObject:name]) {
            NSUInteger sequence=controller.testOutputCases.count+1;
            NSString *project=[NSString stringWithFormat:@"SubPop 简繁验证 %@ %@ %@",template,mode,controller.testEvidenceURL.lastPathComponent];
            NSData *xml=SubPopTitleExportXML(controller.titlePayloads[@"1.14"],project,sequence,&error);
            check(xml!=nil && error==nil,@"isolated host-validation XML exports");
            check([xml writeToURL:[controller.testOutputURL URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"fcpxml"]] atomically:YES],@"isolated host-validation XML saved");
            check([srt writeToURL:[controller.testOutputURL URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"srt"]] atomically:YES],@"matching host-validation SRT saved");
            [controller.testOutputCases addObject:name];
        }
    }
}
static NSDictionary *state(SubPopChineseScriptTestController *controller) {
    return @{@"source":copyRows(controller.captionSourceRows),@"display":copyRows(controller.captionRows),@"payloads":controller.titlePayloads ?: @{},@"mode":@(controller.chineseTextMode)};
}
static void checkDraftRejected(SubPopChineseScriptTestController *controller,NSDictionary *draft,NSString *message) {
    NSDictionary *before=state(controller);
    check(![controller restoreChineseTextDraft:draft],message);
    check([state(controller) isEqual:before],@"invalid draft must not partially alter base, display, XML or selection");
}

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        check(argc==2 || argc==3,@"expected captions/XML fixture directory, optional output directory");
        [NSApplication sharedApplication];NSString *directory=@(argv[1]);
        NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"captions.json"]] options:0 error:nil];
        check([manifest[@"captions"] count]>0,@"caption fixture exists");
        SubPopChineseScriptTestController *c=[SubPopChineseScriptTestController new];
        c.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,840,850)];
        c.testEvidenceURL=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        check([NSFileManager.defaultManager createDirectoryAtURL:c.testEvidenceURL withIntermediateDirectories:YES attributes:nil error:nil],@"isolated draft directory created");
        if (argc==3) {
            c.testOutputURL=[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];c.testOutputCases=[NSMutableSet new];
            check([NSFileManager.defaultManager createDirectoryAtURL:c.testOutputURL withIntermediateDirectories:YES attributes:nil error:nil],@"optional host-validation output directory created");
        }
        c.resultManifest=manifest;c.captionRows=copyRows(manifest[@"captions"]);
        NSString *source=@"頭髮／發展；汉语字幕 USB-C 3.5% iPhone 18 😀 & <校对>";
        c.captionRows[0][@"text"]=source;
        c.fontPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[c.fontPicker addItemWithTitle:@"Helvetica"];
        c.sizePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[c.sizePicker addItemWithTitle:@"72"];
        c.templatePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[c.templatePicker addItemsWithTitles:@[@"普通字幕",@"原生底框",@"自适应底框"]];
        c.chineseTextPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        for (NSString *identifier in @[@"keep",@"simplified",@"traditional"]) {
            [c.chineseTextPicker addItemWithTitle:identifier];c.chineseTextPicker.lastItem.representedObject=identifier;
        }
        c.captionTable=[NSTableView new];c.exportStatus=[NSTextField labelWithString:@""];
        c.tap5aPreview=[[SubPopStylePreview alloc] initWithFrame:NSMakeRect(0,0,640,360)];c.tap5aPreviewLabel=[NSTextField labelWithString:@""];
        c.basicStyle=SubPopNormalizeBasicStyle(nil);c.nativeStyle=SubPopNormalizeNativeStyle(nil);c.tap5aStyle=SubPopNormalizeTap5aStyle(nil);
        c.tap5aURL=[NSURL fileURLWithPath:@"/tmp/Titles.localized/Tap5a/Test/Tap5a Autosize Text Background.moti"];
        NSMutableDictionary *payloads=[NSMutableDictionary new],*timings=[NSMutableDictionary new];
        for (NSString *version in @[@"1.12",@"1.13",@"1.14"]) {
            NSData *data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"TitleProbe-%@.fcpxml",version]]];
            check(data!=nil,@"three version fixtures exist");payloads[version]=data;timings[version]=titleTiming(data);
        }
        c.titlePayloads=payloads;c.resultRequestID=NSUUID.UUID.UUIDString.lowercaseString;c.requestSHA=@"fixture";c.requestModelID=@"qwen3-asr-0.6b";
        NSArray *baseline=copyRows(c.captionRows);
        check([c applyChineseTextMode:SubPopChineseTextKeep],@"existing recognized rows initialize unchanged base");
        check([c.captionSourceRows isEqual:baseline] && [c.captionRows isEqual:baseline],@"keep captures mixed-script recognition text without conversion");
        for (NSNumber *template in @[@(SubPopTitleTemplateBasic),@(SubPopTitleTemplateNative),@(SubPopTitleTemplateTap5a)]) {
            [c.templatePicker selectItemAtIndex:template.integerValue];
            check([c rebuildTitles],@"selected template builds before conversion");
            for (NSString *version in c.titlePayloads) timings[version]=titleTiming(c.titlePayloads[version]);
            check([c applyChineseTextMode:SubPopChineseTextSimplified],@"simplified conversion succeeds offline");
            check([c.captionRows[0][@"text"] containsString:@"头发"] && [c.captionRows[0][@"text"] containsString:@"汉语字幕"],@"traditional words convert to simplified Chinese");
            check([c.captionRows[0][@"text"] containsString:@"USB-C 3.5% iPhone 18 😀 & <校对>"],@"conversion preserves English, numbers, emoji and symbols");
            checkOutputs(c,timings,baseline);
            check([c applyChineseTextMode:SubPopChineseTextTraditional],@"traditional conversion succeeds offline");
            check([c.captionRows[0][@"text"] containsString:@"漢語字幕"] && [c.captionRows[0][@"text"] containsString:@"<校對>"],@"simplified words convert to traditional Chinese");
            check([c.captionRows[0][@"text"] containsString:@"USB-C 3.5% iPhone 18 😀 &"],@"traditional conversion preserves non-Chinese content");
            checkOutputs(c,timings,baseline);
            check([c applyChineseTextMode:SubPopChineseTextKeep] && [c.captionRows isEqual:baseline] && [c.captionSourceRows isEqual:baseline],@"switching never destroys ambiguous original Chinese characters");
        }
        [c.templatePicker selectItemAtIndex:SubPopTitleTemplateBasic];
        check([c rebuildTitles],@"return to ordinary template before proofreading");
        for (NSString *version in c.titlePayloads) timings[version]=titleTiming(c.titlePayloads[version]);
        check([c applyChineseTextMode:SubPopChineseTextTraditional],@"prepare converted-mode proofreading");
        c.referenceUndoRows=baseline;c.referenceUndoPayloads=payloads;
        NSString *edited=@"我改过汉语字幕 USB-C 3.5% 😀 & <校对>";
        NSTableColumn *textColumn=[[NSTableColumn alloc] initWithIdentifier:@"text"];
        [c tableView:c.captionTable setObjectValue:edited forTableColumn:textColumn row:0];
        check([c.captionSourceRows[0][@"text"] isEqual:edited],@"manual proofreading records exact input into canonical base");
        check([c.captionRows[0][@"text"] containsString:@"漢語字幕"] && !c.referenceUndoRows && !c.referenceUndoPayloads,@"proofreading reapplies selected script and clears stale reference undo");
        check([c applyChineseTextMode:SubPopChineseTextKeep] && [c.captionRows[0][@"text"] isEqual:edited],@"returning to keep preserves converted-mode proofreading");
        check([c applyChineseTextMode:SubPopChineseTextSimplified] && [c.captionRows[0][@"text"] isEqual:edited],@"other script selection preserves proofreading");
        NSArray *corrected=copyRows(c.captionSourceRows);
        check([c applyChineseTextMode:SubPopChineseTextTraditional],@"save converted corrected draft");
        // Exercise the native reference response/undo path with a controlled
        // local reply; the separate ReferenceTests harness runs the real worker.
        c.bridgeURL=c.testEvidenceURL;c.dropUID=@"chinese-reference-test";
        c.testReferenceSettings=@{@"enabled":@YES,@"text":@"我校正过汉语字幕 USB-C 3.5%"};
        [c startReferenceRefinement];
        check(c.referenceRequestID.length>0,@"reference refinement starts for converted result");
        NSURL *referenceDirectory=[c.bridgeURL URLByAppendingPathComponent:c.referenceRequestID];
        NSDictionary *request=[c readJSON:[referenceDirectory URLByAppendingPathComponent:@"request.json"]];
        check([request[@"captions"] isEqual:corrected] && ![request[@"captions"] isEqual:c.captionRows],@"reference worker receives canonical proofreading instead of converted display");
        NSMutableArray *refined=copyRows(corrected);refined[0][@"text"]=@"我校正过汉语字幕 USB-C 3.5% 😀";
        NSDictionary *reply=@{@"requestID":c.referenceRequestID,@"projectUID":c.dropUID,@"status":@"ready",@"referenceSHA256":c.referenceProcessingSHA,@"captions":refined,@"referenceReview":@{@"correctionCount":@1,@"boundaryCount":@0}};
        check([[NSJSONSerialization dataWithJSONObject:reply options:0 error:nil] writeToURL:[referenceDirectory URLByAppendingPathComponent:@"response.json"] atomically:YES],@"controlled reference response written locally");
        [c pollReferenceRefinement];
        check(!c.referenceRequestID && [c.captionSourceRows isEqual:refined] && [c.captionRows[0][@"text"] containsString:@"我校正過漢語字幕"] && c.chineseTextMode==SubPopChineseTextTraditional,@"reference correction updates base and reapplies current script");
        checkOutputs(c,timings,baseline);
        [c undoReferenceRefinement:nil];
        check([c.captionSourceRows isEqual:corrected] && [c.captionRows[0][@"text"] containsString:@"我改過漢語字幕"] && c.chineseTextMode==SubPopChineseTextTraditional && !c.referenceUndoRows && !c.referenceUndoPayloads,@"reference undo restores corrected base while keeping selected script");
        // Initial recognition with a script may change caption boundaries and
        // count. Undo must restore the corresponding original rows AND XML,
        // rather than requiring the pre-undo display to have the same timing.
        NSDictionary *originalPayloads=c.titlePayloads;
        NSMutableArray *splitRows=copyRows(corrected);
        NSDictionary *firstOriginal=corrected[0];
        long long begin=[firstOriginal[@"start_frame"] longLongValue],end=[firstOriginal[@"end_frame"] longLongValue];
        check(end-begin>=2,@"fixture's first caption can be split at a measured frame");
        long long middle=begin+(end-begin)/2;
        NSMutableDictionary *secondHalf=firstOriginal.mutableCopy;
        splitRows[0][@"end_frame"]=@(middle);splitRows[0][@"text"]=@"分句后的前半段汉语字幕";
        secondHalf[@"start_frame"]=@(middle);secondHalf[@"text"]=@"分句后的后半段汉语字幕";
        [splitRows insertObject:secondHalf atIndex:1];
        c.captionRows=copyRows(splitRows);c.captionSourceRows=copyRows(splitRows);
        c.titlePayloads=splitFirstCaptionPayloads(originalPayloads,firstOriginal,middle,c.resultManifest[@"frameDuration"]);
        check([c applyChineseTextMode:SubPopChineseTextTraditional] && c.captionRows.count==corrected.count+1,@"initial reference fixture has a different subtitle count and boundaries");
        c.referenceUndoRows=corrected;c.referenceUndoPayloads=originalPayloads;c.referenceUndoWasOriginal=YES;
        // A failed undo keeps the current display and the usable undo history.
        NSMutableDictionary *brokenUndo=originalPayloads.mutableCopy;
        NSXMLDocument *missingUndoText=[[NSXMLDocument alloc] initWithData:originalPayloads[@"1.13"] options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        [[missingUndoText nodesForXPath:@"/fcpxml/clip/spine/title[1]/text/text-style" error:nil].firstObject detach];
        brokenUndo[@"1.13"]=[missingUndoText XMLDataWithOptions:0];c.referenceUndoPayloads=brokenUndo;
        NSDictionary *beforeFailedUndo=state(c);NSArray *undoRows=copyRows(c.referenceUndoRows);
        [c undoReferenceRefinement:nil];
        check([state(c) isEqual:beforeFailedUndo] && [c.referenceUndoRows isEqual:undoRows] && [c.referenceUndoPayloads isEqual:brokenUndo],@"failed initial-reference undo rolls back display/base/XML and preserves undo history");
        c.referenceUndoPayloads=originalPayloads;[c undoReferenceRefinement:nil];
        check(c.captionRows.count==corrected.count && [c.captionSourceRows isEqual:corrected] && c.chineseTextMode==SubPopChineseTextTraditional && c.referenceUndone && !c.referenceUndoRows && !c.referenceUndoPayloads,@"initial reference undo restores original count/timing while preserving selected script");
        checkOutputs(c,timings,baseline);
        [c saveDraft];
        NSDictionary *draft=[c readJSON:[c.testEvidenceURL URLByAppendingPathComponent:[@"draft-" stringByAppendingString:c.resultRequestID]]];
        check([draft[@"sourceCaptions"] isEqual:corrected] && [draft[@"captions"] isEqual:c.captionRows] && [draft[@"chineseTextMode"] isEqual:@"traditional"],@"draft saves canonical corrected text, derived text and stable mode id");
        [c resetChineseText];c.captionRows=copyRows(baseline);
        check([c restoreChineseTextDraft:draft],@"new draft restores onto verified timing");
        check(c.chineseTextMode==SubPopChineseTextTraditional && [c.captionSourceRows isEqual:corrected] && [c.captionRows[0][@"text"] containsString:@"漢語字幕"],@"restored mode is reapplied to corrected canonical text");
        [c rebuildTitles];checkOutputs(c,timings,baseline);
        for (NSNumber *template in @[@(SubPopTitleTemplateBasic),@(SubPopTitleTemplateNative)]) {
            [c.templatePicker selectItemAtIndex:template.integerValue];
            check([c rebuildTitles],@"prepare converted draft for each automatic-name template");
            for (NSString *version in c.titlePayloads) timings[version]=titleTiming(c.titlePayloads[version]);
            [c saveDraft];
            NSDictionary *namedDraft=[c readJSON:[c.testEvidenceURL URLByAppendingPathComponent:[@"draft-" stringByAppendingString:c.resultRequestID]]];
            NSString *expectedID=template.integerValue==SubPopTitleTemplateNative ? @"native" : @"basic";
            check([namedDraft[@"templateID"] isEqual:expectedID],@"draft retains the template that defines automatic naming");
            NSMutableDictionary *stalePayloads=[NSMutableDictionary new];
            for (NSString *version in @[@"1.12",@"1.13",@"1.14"]) {
                NSXMLDocument *xml=[[NSXMLDocument alloc] initWithData:c.titlePayloads[version] options:NSXMLNodeLoadExternalEntitiesNever error:nil];
                NSXMLElement *first=[xml nodesForXPath:@"/fcpxml/clip/spine/title" error:nil].firstObject;
                [first removeAttributeForName:@"name"];
                if (![version isEqual:@"1.12"]) [first addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:[version isEqual:@"1.13"] ? @"" : @"草稿里的旧名称"]];
                stalePayloads[version]=[xml XMLDataWithOptions:0];
            }
            c.titlePayloads=stalePayloads;[c resetChineseText];c.captionRows=copyRows(baseline);
            // The result loader selects the saved template before restoring
            // caption text; exercise the same order without a host/worker.
            [c.templatePicker selectItemAtIndex:SubPopTitleTemplateFromDraft(namedDraft)];
            check([c restoreChineseTextDraft:namedDraft],@"converted draft restores while rebuilding stale/empty/missing clip names");
            checkOutputs(c,timings,baseline);
        }
        [c.templatePicker selectItemAtIndex:SubPopTitleTemplateBasic];
        check([c rebuildTitles],@"return to basic before legacy draft migration");
        for (NSString *version in c.titlePayloads) timings[version]=titleTiming(c.titlePayloads[version]);
        NSDictionary *legacy=@{@"captions":corrected};
        check([c restoreChineseTextDraft:legacy] && c.chineseTextMode==SubPopChineseTextKeep && [c.captionSourceRows isEqual:corrected] && [c.captionRows isEqual:corrected],@"legacy draft keeps previous proofreading and defaults to unchanged script");
        checkOutputs(c,timings,baseline);
        checkDraftRejected(c,@{@"captions":corrected,@"sourceCaptions":corrected,@"chineseTextMode":@"unknown"},@"unknown saved mode rejected");
        checkDraftRejected(c,@{@"captions":corrected,@"sourceCaptions":corrected,@"chineseTextMode":@1},@"non-string saved mode rejected");
        NSMutableArray *wrongTiming=copyRows(corrected);wrongTiming[0][@"start_frame"]=@([wrongTiming[0][@"start_frame"] longLongValue]+1);
        checkDraftRejected(c,@{@"captions":corrected,@"sourceCaptions":wrongTiming,@"chineseTextMode":@"traditional"},@"changed source timing rejected");
        checkDraftRejected(c,@{@"captions":corrected,@"sourceCaptions":@[],@"chineseTextMode":@"traditional"},@"missing source rows rejected");
        NSMutableArray *invalidSource=copyRows(corrected);invalidSource[0][@"text"]=@0;
        checkDraftRejected(c,@{@"captions":corrected,@"sourceCaptions":invalidSource,@"chineseTextMode":@"simplified"},@"invalid source text rejected");
        NSMutableArray *emptySource=copyRows(corrected);emptySource[0][@"text"]=@"";
        checkDraftRejected(c,@{@"captions":corrected,@"sourceCaptions":emptySource,@"chineseTextMode":@"simplified"},@"empty source text rejected");
        NSMutableArray *longSource=copyRows(corrected);longSource[0][@"text"]=[@"字" stringByPaddingToLength:501 withString:@"字" startingAtIndex:0];
        checkDraftRejected(c,@{@"captions":corrected,@"sourceCaptions":longSource,@"chineseTextMode":@"simplified"},@"oversized source text rejected");
        NSDictionary *beforeInvalid=state(c);
        check(![c applyChineseTextMode:(SubPopChineseTextMode)99] && [state(c) isEqual:beforeInvalid],@"invalid runtime mode rejects without altering results");
        for (NSString *busyProperty in @[@"requestID",@"referenceRequestID",@"pendingRecognition",@"importInProgress",@"exportInProgress"]) {
            NSDictionary *before=state(c);[c.chineseTextPicker selectItemAtIndex:2];
            id busy=[busyProperty hasSuffix:@"InProgress"] ? @YES : ([busyProperty isEqual:@"pendingRecognition"] ? @{} : @"busy");
            [c setValue:busy forKey:busyProperty];[c chineseTextChanged:c.chineseTextPicker];
            check([state(c) isEqual:before],[@"conversion action is blocked during " stringByAppendingString:busyProperty]);
            [c setValue:[busyProperty hasSuffix:@"InProgress"] ? @NO : nil forKey:busyProperty];
        }
        // Rejected source data must never overwrite a previously valid display.
        c.captionSourceRows=invalidSource;NSDictionary *invalidState=state(c);
        check(![c applyChineseTextMode:SubPopChineseTextTraditional] && [state(c) isEqual:invalidState],@"conversion failure leaves existing result intact");
        c.captionSourceRows=copyRows(corrected);
        NSDictionary *validPayloads=c.titlePayloads;
        NSMutableDictionary *brokenPayloads=validPayloads.mutableCopy;brokenPayloads[@"1.13"]=[@"<fcpxml>" dataUsingEncoding:NSUTF8StringEncoding];
        c.titlePayloads=brokenPayloads;NSDictionary *brokenState=state(c);
        check(![c applyChineseTextMode:SubPopChineseTextTraditional] && [state(c) isEqual:brokenState],@"a malformed XML version must not leave preview/SRT converted but drag/XML unchanged");
        c.titlePayloads=validPayloads;
        NSMutableDictionary *shortPayloads=validPayloads.mutableCopy;
        NSXMLDocument *shortXML=[[NSXMLDocument alloc] initWithData:validPayloads[@"1.14"] options:NSXMLNodeLoadExternalEntitiesNever error:nil];
        [[shortXML nodesForXPath:@"/fcpxml/clip/spine/title" error:nil].lastObject detach];
        shortPayloads[@"1.14"]=[shortXML XMLDataWithOptions:0];c.titlePayloads=shortPayloads;
        NSDictionary *shortState=state(c);
        check(![c applyChineseTextMode:SubPopChineseTextTraditional] && [state(c) isEqual:shortState],@"one XML version missing a title rejects conversion atomically");
        c.titlePayloads=validPayloads;
        for (NSString *missingPath in @[@"/fcpxml/clip/spine/title[1]/text/text-style",@"/fcpxml/clip/spine/title[1]/text-style-def/text-style"]) {
            NSMutableDictionary *missingPayloads=validPayloads.mutableCopy;
            NSXMLDocument *missingXML=[[NSXMLDocument alloc] initWithData:validPayloads[@"1.12"] options:NSXMLNodeLoadExternalEntitiesNever error:nil];
            [[missingXML nodesForXPath:missingPath error:nil].firstObject detach];
            missingPayloads[@"1.12"]=[missingXML XMLDataWithOptions:0];c.titlePayloads=missingPayloads;
            NSDictionary *missingState=state(c);
            check(![c applyChineseTextMode:SubPopChineseTextTraditional] && [state(c) isEqual:missingState],@"missing XML text/style node cannot split table/SRT output from drag/XML output");
        }
        c.titlePayloads=validPayloads;
        [c resetChineseText];
        check(!c.captionSourceRows && c.chineseTextMode==SubPopChineseTextKeep,@"reset removes previous project conversion base and mode");
        c.captionRows=nil;c.titlePayloads=nil;
        [c.chineseTextPicker selectItemAtIndex:2];[c chineseTextChanged:c.chineseTextPicker];
        check(!c.captionRows && !c.captionSourceRows && !c.titlePayloads && c.chineseTextMode==SubPopChineseTextKeep,@"empty result cannot gain stale text through conversion");
        [NSFileManager.defaultManager removeItemAtURL:c.testEvidenceURL error:nil];
        puts("Chinese script: offline switching, lossless base, proofreading, reference-response/undo, three templates/XML versions, SRT/preview timing, draft migration and rejection, busy guards and reset passed.");
    }
    return 0;
}
