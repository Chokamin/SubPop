#import <Cocoa/Cocoa.h>

// Import a new browser clip, never a project or a replacement timeline.
static NSData *SubPopTitleImportXML(NSData *payload, NSString *projectName, NSError **error) {
    NSXMLDocument *doc=payload.length ? [[NSXMLDocument alloc] initWithData:payload options:NSXMLNodeLoadExternalEntitiesNever error:error] : nil;
    NSArray *clips=[doc nodesForXPath:@"/fcpxml/clip" error:nil];
    NSXMLElement *clip=clips.firstObject;
    if (!doc || ![doc.rootElement.name isEqual:@"fcpxml"] || clips.count!=1 ||
        [doc nodesForXPath:@"/fcpxml/*[not(self::resources or self::clip)]" error:nil].count ||
        ![clip nodesForXPath:@"spine/title" error:nil].count) {
        if (error) *error=[NSError errorWithDomain:@"SubPopTitleImport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"字幕数据不完整，请切换字幕样式后重试。"}];
        return nil;
    }
    [clip detach];
    [clip attributeForName:@"name"].stringValue=[NSString stringWithFormat:@"%@ · Tap5a 字幕",projectName.length ? projectName : @"SubPop"];
    NSXMLElement *event=[NSXMLElement elementWithName:@"event"];
    [event addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:@"SubPop 字幕"]];
    [event addChild:clip];[doc.rootElement addChild:event];
    // FCP validates against its external DTD, so this is not a standalone document.
    doc.standalone=NO;
    return [doc XMLDataWithOptions:NSXMLNodePrettyPrint|NSXMLNodeCompactEmptyElement];
}
