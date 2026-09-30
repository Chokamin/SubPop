#import <Foundation/Foundation.h>
#import <math.h>

static double SubPopPreviewSeconds(NSString *value) {
    if (!value.length) return 0;
    NSString *s=[value hasSuffix:@"s"] ? [value substringToIndex:value.length-1] : value;
    NSArray *parts=[s componentsSeparatedByString:@"/"];if (parts.count>2) return NAN;
    double numerator=0,denominator=1;NSScanner *scan=[NSScanner scannerWithString:parts[0]];
    if (![scan scanDouble:&numerator] || !scan.isAtEnd) return NAN;
    if (parts.count==2) {scan=[NSScanner scannerWithString:parts[1]];if (![scan scanDouble:&denominator] || !scan.isAtEnd || denominator==0) return NAN;}
    return numerator/denominator;
}

// Resolve primary picture through ordinary clip/gap containers. This supplies a
// source-media frame, not FCP's composited/effected output. Keep unsupported
// retimes, multicam and reference compositions out of this approximation.
static NSDictionary *SubPopPreviewNode(NSXMLElement *node,double clock,NSDictionary *assets,NSUInteger depth,NSUInteger *budget) {
    if (depth>64 || !*budget) return nil;--*budget;
    if ([[node attributeForName:@"enabled"].stringValue isEqual:@"0"] || [[node attributeForName:@"srcEnable"].stringValue isEqual:@"audio"]) return nil;
    NSString *tag=node.name;
    BOOL leaf=[tag isEqual:@"asset-clip"] || [tag isEqual:@"video"];
    if (!leaf && ![tag isEqual:@"clip"] && ![tag isEqual:@"gap"]) return nil;
    NSXMLElement *asset=leaf ? assets[[node attributeForName:@"ref"].stringValue ?: @""] : nil;
    double offset=SubPopPreviewSeconds([node attributeForName:@"offset"].stringValue);
    double duration=SubPopPreviewSeconds([node attributeForName:@"duration"].stringValue ?: [asset attributeForName:@"duration"].stringValue);
    if (!isfinite(offset) || !isfinite(duration) || duration<=0 || !(clock>=offset && clock<offset+duration)) return nil;
    if ([node elementsForName:@"timeMap"].count) return nil;
    for (NSXMLElement *rate in [node elementsForName:@"conform-rate"]) if (![[rate attributeForName:@"scaleEnabled"].stringValue isEqual:@"0"]) return nil;
    double start=SubPopPreviewSeconds([node attributeForName:@"start"].stringValue ?: [asset attributeForName:@"start"].stringValue);
    double local=start+clock-offset;if (!isfinite(local)) return nil;
    if (leaf) {
        if (![[asset attributeForName:@"hasVideo"].stringValue isEqual:@"1"]) return nil;
        NSXMLElement *rep=[asset nodesForXPath:@"media-rep[@kind='original-media']" error:nil].firstObject;
        NSURL *url=[NSURL URLWithString:[rep attributeForName:@"src"].stringValue ?: @""];
        double source=local-SubPopPreviewSeconds([asset attributeForName:@"start"].stringValue);
        if (!url.isFileURL || (url.host.length && ![url.host isEqual:@"localhost"]) || !isfinite(source) || source<0) return nil;
        return @{@"url":url,@"seconds":@(source),@"bookmark":[[rep elementsForName:@"bookmark"].firstObject stringValue] ?: @""};
    }
    // Child offsets live in their container's source clock, not project time.
    // Ignore connected music, titles and adjustment layers when choosing the
    // primary picture; do not accidentally treat their effect refs as assets.
    for (NSXMLNode *child in node.children) {
        if (![child isKindOfClass:NSXMLElement.class]) continue;
        NSXMLElement *element=(NSXMLElement *)child;
        NSString *lane=[element attributeForName:@"lane"].stringValue;
        if (lane.length && ![lane isEqual:@"0"]) continue;
        NSDictionary *source=SubPopPreviewNode(element,local,assets,depth+1,budget);
        if (source) return source;
    }
    return nil;
}

static NSDictionary *SubPopPreviewSource(NSData *data,double seconds) {
    if (!data.length || data.length>16*1024*1024 || !isfinite(seconds) || seconds<0) return nil;
    NSString *xml=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!xml || [xml.uppercaseString containsString:@"<!ENTITY"]) return nil;
    NSXMLDocument *doc=[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
    NSArray *sequences=[doc nodesForXPath:@"//project/sequence" error:nil];if (sequences.count!=1) return nil;
    NSXMLElement *sequence=sequences.firstObject;
    double timeline=SubPopPreviewSeconds([sequence attributeForName:@"tcStart"].stringValue)+seconds;
    if (!isfinite(timeline)) return nil;
    NSMutableDictionary *assets=[NSMutableDictionary new];
    for (NSXMLElement *asset in [doc nodesForXPath:@"/fcpxml/resources/asset" error:nil]) {
        NSString *identifier=[asset attributeForName:@"id"].stringValue;if (identifier.length) assets[identifier]=asset;
    }
    NSUInteger budget=5000;
    for (NSXMLElement *node in [sequence nodesForXPath:@"spine/*" error:nil]) {
        NSString *lane=[node attributeForName:@"lane"].stringValue;if (lane.length && ![lane isEqual:@"0"]) continue;
        NSDictionary *source=SubPopPreviewNode(node,timeline,assets,0,&budget);if (source) return source;
    }
    return nil;
}
