#import <Cocoa/Cocoa.h>

static NSString * const SubPopBasicTitleUID=@".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti";
static NSString *SubPopTap5aUID(NSURL *url) {
    NSArray *parts=url.path.pathComponents;
    NSUInteger index=[parts indexOfObject:@"Titles.localized"];
    if (index==NSNotFound || parts.count<index+4 || ![url.lastPathComponent isEqual:@"Tap5a Autosize Text Background.moti"]) return nil;
    return [@"~/" stringByAppendingString:[[parts subarrayWithRange:NSMakeRange(index,parts.count-index)] componentsJoinedByString:@"/"]];
}
static BOOL SubPopValidTap5a(NSURL *url) {
    if (!SubPopTap5aUID(url)) return NO;
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (!data || data.length>2*1024*1024) return NO;
    NSXMLDocument *doc=[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
    return [doc.rootElement.name isEqual:@"ozml"] && [doc nodesForXPath:@"//publishSettings/target[@object='1825821409']" error:nil].count==1 && [doc nodesForXPath:@"//publishSettings/target[@object='10924']" error:nil].count==2;
}
static void SubPopSetTitleTemplate(NSXMLDocument *doc, NSURL *tap5aURL) {
    NSString *tap5aUID=SubPopTap5aUID(tap5aURL);
    NSXMLElement *effect=[doc nodesForXPath:@"/fcpxml/resources/effect[@id='r2']" error:nil].firstObject;
    [effect attributeForName:@"uid"].stringValue=tap5aUID ?: SubPopBasicTitleUID;
    [effect attributeForName:@"name"].stringValue=tap5aUID ? @"Tap5a Autosize Text Background" : @"基本字幕";
    [effect removeAttributeForName:@"src"];
    // Match FCP export: a user-installed Motion title needs both UID and source URL.
    if (tap5aUID) [effect addAttribute:[NSXMLNode attributeWithName:@"src" stringValue:tap5aURL.absoluteString]];
    for (NSXMLElement *title in [doc nodesForXPath:@"/fcpxml/clip/spine/title" error:nil]) {
        // Only SubPop-owned flat title payloads enter this function.
        for (NSXMLNode *param in [title elementsForName:@"param"]) [param detach];
        if (tap5aUID) {
            NSArray *params=@[@[@"Enable",@"9999/10658/100/1825821409/2/100",@"1"],@[@"Enable",@"9999/10658/100/1825821410/2/100",@"0"]];
            for (NSArray *values in params) {
                NSXMLElement *param=[NSXMLElement elementWithName:@"param"];
                for (NSUInteger i=0;i<3;i++) [param addAttribute:[NSXMLNode attributeWithName:@[@"name",@"key",@"value"][i] stringValue:values[i]]];
                [title insertChild:param atIndex:0];
            }
        }
    }
}
