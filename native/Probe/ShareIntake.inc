- (void)showShareHelp:(id)sender {
    NSAlert *alert=[NSAlert new];alert.messageText=@"从 Final Cut Pro 发送成片音频";
    alert.informativeText=@"首次设置：在 FCP「设置 → 目的位置」添加「导出文件」，格式选「仅音频」，音频格式选 WAV 或 AIFF；在「打开方式 → 其他」选择 SubPop。可将目的位置命名为“发送到 SubPop”。\n\n之后打开完整项目，清除范围选择，再从「共享」选择这个目的位置。FCP 渲染完成后，回到扩展点击「接收 FCP 音频」。无需手动寻找导出的音频，也无需先拖入项目。\n\n接收的是共享设置中的声音。若只要对白，请在 FCP 共享设置中选择对白角色，并合成为一个音频文件；混音中的音乐不能在 SubPop 内再按角色分离。时间线修改后请重新共享。";
    [alert addButtonWithTitle:@"知道了"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
}
- (void)showRecognitionReview:(id)sender {
    NSDictionary *review=self.resultManifest[@"recognitionReview"];
    NSArray *warnings=review[@"warnings"];
    if (![warnings isKindOfClass:NSArray.class] || !warnings.count) return;
    NSMutableArray *lines=[NSMutableArray new];
    for (NSDictionary *warning in warnings) {
        if (lines.count>=20) break;
        double start=[warning[@"start"] doubleValue],end=[warning[@"end"] doubleValue];
        if (!isfinite(start) || !isfinite(end) || start<0 || end<=start) continue;
        NSString *reason=[warning[@"reason"] isEqual:@"signal-without-text"] ? @"有音频信号但未得到文字（也可能是音乐或环境声）" : @"文字重复较多（也可能是原本就有重复）";
        [lines addObject:[NSString stringWithFormat:@"%02ld:%05.2f–%02ld:%05.2f  %@",(long)(start/60),fmod(start,60),(long)(end/60),fmod(end,60),reason]];
    }
    NSAlert *alert=[NSAlert new];alert.messageText=@"这些时段值得试听核对";
    alert.informativeText=[NSString stringWithFormat:@"%@\n\n时间从本次完整音频的起点计算。请在 FCP 试听并对照字幕；这些提示不能证明存在漏识别，原文字和时间均未改动。%@",[lines componentsJoinedByString:@"\n"],[review[@"warningCount"] unsignedIntegerValue]>lines.count ? @"这里只显示前 20 项。" : @""];
    [alert addButtonWithTitle:@"完成"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
}
- (void)receiveSharedAudio:(id)sender {
    if (self.requestID || self.pendingRecognition || self.referenceRequestID || self.fallbackImporting || self.shareReceiving || self.sharePromptOpen || self.importInProgress || self.exportInProgress) return;
    NSArray *shares=SubPopPendingShares(self.bridgeURL);if (!shares.count) return;
    NSAlert *alert=[NSAlert new];alert.messageText=@"接收 FCP 渲染的音频";
    alert.informativeText=@"请选择本次共享，并在 FCP 打开对应的完整项目。接收会替换 SubPop 当前输入和字幕结果，FCP 中的内容不变。识别使用共享的声音；修改时间线后需要重新共享。";
    NSPopUpButton *picker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,420,28) pullsDown:NO];
    for (NSDictionary *share in shares) {
        double seconds=CMTimeGetSeconds(SubPopShareTime(share[@"duration"]));
        [picker addItemWithTitle:[NSString stringWithFormat:@"%@ · %02ld:%02ld · %@",share[@"projectName"],(long)(seconds/60),(long)seconds%60,[share[@"shareID"] substringToIndex:8]]];
    }
    alert.accessoryView=picker;[alert addButtonWithTitle:@"接收音频"];[alert addButtonWithTitle:@"取消"];[alert addButtonWithTitle:@"丢弃此项"];
    self.sharePromptOpen=YES;[self updateInterface];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        self.sharePromptOpen=NO;
        NSDictionary *share=shares[picker.indexOfSelectedItem];
        if (response==NSAlertFirstButtonReturn) [self acceptSharedAudio:share];
        else if (response==NSAlertThirdButtonReturn) {
            NSURL *dir=[[self.bridgeURL URLByAppendingPathComponent:@"share-inbox"] URLByAppendingPathComponent:share[@"shareID"]];
            // A terminal marker prevents replay; receiver also retains its transaction.
            if (SubPopFinishShare(dir,@"discarded")) {
                for (NSString *name in @[share[@"xmlFile"],share[@"audioFile"]]) [NSFileManager.defaultManager removeItemAtURL:[dir URLByAppendingPathComponent:name] error:nil];
            }
        }
        self.pendingShares=SubPopPendingShares(self.bridgeURL);[self updateInterface];
    }];
}
- (BOOL)acceptSharedAudio:(NSDictionary *)share {
    if (self.requestID || self.pendingRecognition || self.referenceRequestID || self.fallbackImporting || self.shareReceiving || self.importInProgress || self.exportInProgress) return NO;
    if (self.timeline) [self snapshot:@"share-intake-state"];
    if (self.requestID || self.pendingRecognition || self.referenceRequestID || self.fallbackImporting || self.shareReceiving || self.importInProgress || self.exportInProgress) return NO;
    CMTime duration=SubPopShareTime(share[@"duration"]);
    if (!self.observed || ![self.observedProjectUID isEqual:share[@"projectUID"]] || !CMTIME_IS_NUMERIC(self.observedProjectDuration) || !CMTIME_IS_NUMERIC(duration) || CMTimeCompare(duration,self.observedProjectDuration)) {
        self.visibleError=@"请先在 FCP 打开这次共享的完整项目；当前项目或时长不一致。音频仍保留，可稍后接收。";
        self.displayState=@"error";[self updateInterface];return NO;
    }
    NSURL *dir=[[self.bridgeURL URLByAppendingPathComponent:@"share-inbox"] URLByAppendingPathComponent:share[@"shareID"]];
    NSDictionary *current=SubPopShareManifest(dir);
    if (![current isEqual:share]) return NO;
    NSUInteger generation=self.dropGeneration;
    self.shareReceiving=YES;self.fallbackImporting=YES;[self updateInterface];
    NSURL *destination=[self evidenceDirectory];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil;NSString *failure=nil;
        NSURL *xml=[destination URLByAppendingPathComponent:[NSString stringWithFormat:@"drop-%@.fcpxml",NSUUID.UUID.UUIDString]];
        NSURL *audio=[destination URLByAppendingPathComponent:[NSString stringWithFormat:@"fallback-%@.%@",NSUUID.UUID.UUIDString,[share[@"audioFile"] pathExtension]]];
        if (!SubPopShareManifest(dir) || ![NSFileManager.defaultManager copyItemAtURL:[dir URLByAppendingPathComponent:share[@"xmlFile"]] toURL:xml error:&error] || ![NSFileManager.defaultManager copyItemAtURL:[dir URLByAppendingPathComponent:share[@"audioFile"]] toURL:audio error:&error]) failure=@"无法复制共享文件，请重新共享。";
        NSData *data=failure ? nil : [NSData dataWithContentsOfURL:xml];
        if (!failure && (![[self sha256:data] isEqual:share[@"xmlSHA256"]] || ![[self sha256File:audio] isEqual:share[@"audioSHA256"]])) failure=@"共享文件已改变，请重新共享。";
        NSXMLDocument *doc=data ? [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil] : nil;
        NSArray *projects=[doc nodesForXPath:@"/fcpxml/project | /fcpxml/library/event/project" error:nil];
        NSXMLElement *project=projects.count==1 ? projects[0] : nil;
        NSXMLElement *sequence=[project elementsForName:@"sequence"].firstObject;
        CMTime xmlDuration=SubPopShareTime([sequence attributeForName:@"duration"].stringValue);
        if (!failure && (![[project attributeForName:@"uid"].stringValue isEqual:share[@"projectUID"]] || !CMTIME_IS_NUMERIC(xmlDuration) || CMTimeCompare(xmlDuration,duration))) failure=@"共享的项目资料与音频不匹配，请重新共享完整项目。";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.shareReceiving=NO;
            BOOL stale=generation!=self.dropGeneration || ![self.observedProjectUID isEqual:share[@"projectUID"]] || !CMTIME_IS_NUMERIC(self.observedProjectDuration) || CMTimeCompare(duration,self.observedProjectDuration);
            if (stale || failure) {
                [NSFileManager.defaultManager removeItemAtURL:xml error:nil];[NSFileManager.defaultManager removeItemAtURL:audio error:nil];
                if (!stale) {self.fallbackImporting=NO;self.visibleError=failure;self.displayState=@"error";[self updateInterface];}
                else if (generation==self.dropGeneration) {self.fallbackImporting=NO;[self updateInterface];}
                return;
            }
            if (!SubPopShareManifest(dir) || !SubPopFinishShare(dir,@"received")) {
                [NSFileManager.defaultManager removeItemAtURL:xml error:nil];[NSFileManager.defaultManager removeItemAtURL:audio error:nil];
                self.fallbackImporting=NO;self.visibleError=@"无法确认接收状态，未开始识别；请重试。";self.displayState=@"error";[self updateInterface];return;
            }
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"pendingSession"];
            [self clearFallbackAudio];[self resetChineseText];
            self.dropGeneration++;self.validatingDrop=NO;self.resultRevalidationURL=nil;self.resultTimelineChanged=NO;self.historicalResult=NO;
            self.freshDropURL=xml;self.freshDropDate=NSDate.date;self.dropUID=share[@"projectUID"];self.dropName=share[@"projectName"];self.dropDuration=duration;self.snapshotConsumed=NO;
            self.fallbackAudioURL=audio;self.fallbackAudioSHA=share[@"audioSHA256"];self.fallbackImporting=NO;
            self.titlePayloads=nil;self.captionRows=nil;self.resultManifest=nil;self.resultDate=nil;self.resultRequestID=nil;self.resultWasDragged=NO;
            self.referenceUndoRows=nil;self.referenceUndoPayloads=nil;self.referenceMessage=nil;self.referenceDraft=nil;
            self.visibleError=nil;self.displayState=@"input";
            for (NSString *name in @[share[@"xmlFile"],share[@"audioFile"]]) [NSFileManager.defaultManager removeItemAtURL:[dir URLByAppendingPathComponent:name] error:nil];
            self.pendingShares=SubPopPendingShares(self.bridgeURL);
            [self.audioPicker selectItemAtIndex:1];[self.captionTable reloadData];[self updateInterface];
            // Receiving is local-only. Generate remains explicit, including the
            // existing per-job cloud upload/cost confirmation if selected.
        });
    });
    return YES;
}
