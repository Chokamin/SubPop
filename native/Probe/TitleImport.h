#import <Cocoa/Cocoa.h>

static NSString *SubPopTitleImportEventName(NSUInteger sequence) {
    return [NSString stringWithFormat:@"SubPop 字幕 %03lu",(unsigned long)sequence];
}
static NSString *SubPopTitleImportClipName(NSString *projectName,NSUInteger sequence) {
    return [NSString stringWithFormat:@"%@ · Tap5a 字幕 %03lu",projectName.length ? projectName : @"SubPop",(unsigned long)sequence];
}
// Package the generated clip in a fresh event. The file imports a browser clip,
// never a project or a replacement timeline.
static NSData *SubPopTitleEventXML(NSData *payload, NSString *eventName, NSString *clipName, NSError **error) {
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
    [clip attributeForName:@"name"].stringValue=clipName;
    NSXMLElement *event=[NSXMLElement elementWithName:@"event"];
    [event addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:eventName]];
    [event addChild:clip];[doc.rootElement addChild:event];
    // FCP validates against its external DTD, so this is not a standalone document.
    doc.standalone=NO;
    return [doc XMLDataWithOptions:NSXMLNodePrettyPrint|NSXMLNodeCompactEmptyElement];
}

// A fresh event keeps FCP's imported result separate from the previous browser
// selection. Reusing one event leaves old clips selected after repeated imports.
static NSData *SubPopTitleImportXML(NSData *payload, NSString *projectName, NSUInteger sequence, NSError **error) {
    return SubPopTitleEventXML(payload,SubPopTitleImportEventName(sequence),
                               SubPopTitleImportClipName(projectName,sequence),error);
}

static NSData *SubPopTitleExportXML(NSData *payload, NSString *projectName, NSUInteger sequence, NSError **error) {
    NSString *name=projectName.length ? projectName : @"SubPop";
    return SubPopTitleEventXML(payload,
        [NSString stringWithFormat:@"SubPop 导出字幕 %03lu",(unsigned long)sequence],
        [NSString stringWithFormat:@"%@ · 字幕 %03lu",name,(unsigned long)sequence],error);
}
