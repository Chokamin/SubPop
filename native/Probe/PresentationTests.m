// AppKit regression harness. No FCP host, no windows, no timeline writes.
#import "ProbeViewController.m"
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
        puts("AppKit proofreading: all 3 XML versions updated, timing preserved, XML text escaped, font and size applied.");
        return 0;
    }
}
