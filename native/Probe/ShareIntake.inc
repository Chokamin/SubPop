// The sandboxed extension asks its containing app to install only the bundled
// preset. No file path, Apple event, or FCP launch is supplied by the caller.
- (void)installShareDestination:(id)sender {
    if (!self.shareHelpButton.enabled || self.shareSetupRequestID) return;
    NSString *host=self.host.bundleIdentifier;
    if (![@[@"com.apple.FinalCut",@"com.apple.FinalCutApp"] containsObject:host] || !self.bridgeURL) {
        self.shareSetupStatus.stringValue=@"请在 Final Cut Pro 中打开 SubPop，再添加共享目的位置。";
        self.shareSetupStatus.hidden=NO;return;
    }
    NSString *request=NSUUID.UUID.UUIDString;
    self.shareSetupRequestID=request;self.shareSetupStarted=NSDate.date;
    self.shareSetupStatus.stringValue=@"正在添加共享目的位置…";self.shareSetupStatus.hidden=NO;
    NSURLComponents *components=[NSURLComponents new];components.scheme=@"subpop-probe";components.host=@"share-destination";
    components.queryItems=@[[NSURLQueryItem queryItemWithName:@"host" value:host],[NSURLQueryItem queryItemWithName:@"request" value:request]];
    NSWorkspaceOpenConfiguration *config=[NSWorkspaceOpenConfiguration configuration];config.activates=NO;
    [self updateInterface];
    [NSWorkspace.sharedWorkspace openURL:components.URL configuration:config completionHandler:^(NSRunningApplication *app,NSError *error) {
        if (error) dispatch_async(dispatch_get_main_queue(),^{
            if (![self.shareSetupRequestID isEqual:request]) return;
            self.shareSetupRequestID=nil;self.shareSetupStarted=nil;
            self.shareSetupStatus.stringValue=@"无法打开 SubPop 主程序。请确认已安装到“应用程序”，然后重试。";
            [self updateInterface];
        });
    }];
}
- (void)pollShareDestinationSetup {
    if (!self.shareSetupRequestID) return;
    NSURL *resultURL=[[self.bridgeURL URLByAppendingPathComponent:@"share-destination"] URLByAppendingPathComponent:[self.shareSetupRequestID stringByAppendingPathExtension:@"json"]];
    NSDictionary *result=[self readJSON:resultURL];
    if ([result[@"requestID"] isEqual:self.shareSetupRequestID]) {
        NSString *status=result[@"status"];
        if ([status isEqual:@"installed"] || [status isEqual:@"already-installed"]) {
            self.shareSetupStatus.stringValue=@"共享预设已就位。请在 FCP「共享」中查看“发送到 SubPop”；若未显示，保存工作后重启 FCP。";
            self.shareHelpButton.title=@"检查共享配置";
        } else if ([status isEqual:@"conflict"]) {
            self.shareSetupStatus.stringValue=@"发现同名的不同预设，已保留原设置。请在 FCP「设置 → 目的位置」检查 SubPop 项目。";
        } else {
            id message=result[@"message"];
            BOOL validMessage=[status isEqual:@"failed"] && [message isKindOfClass:NSString.class] && [message length]<=8192 && [[message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]>0;
            // Keep recovery details (including retained backup paths) as plain
            // text. Malformed or oversized receipts use the existing fallback.
            self.shareSetupStatus.stringValue=validMessage ? message : @"未能添加共享预设，已有设置已保留。请重新安装 SubPop 后重试。";
        }
        self.shareSetupRequestID=nil;self.shareSetupStarted=nil;
    } else if (self.shareSetupStarted && -self.shareSetupStarted.timeIntervalSinceNow>30) {
        self.shareSetupRequestID=nil;self.shareSetupStarted=nil;
        self.shareSetupStatus.stringValue=@"暂未收到配置结果。请检查 FCP「共享」菜单，或稍后重试。";
    }
}
- (void)showShareHelp:(id)sender {
    self.shareGuideExpanded=!self.shareGuideExpanded;
    self.shareGuideDetail.hidden=!self.shareGuideExpanded;
    [self.view layoutSubtreeIfNeeded];
    if (self.shareGuideExpanded) [self.shareGuideDetail scrollRectToVisible:self.shareGuideDetail.bounds];
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
    NSURL *dir=[[self.bridgeURL URLByAppendingPathComponent:@"share-inbox"] URLByAppendingPathComponent:share[@"shareID"]];
    NSDictionary *current=SubPopShareManifest(dir);
    if (![current isEqual:share]) return NO;
    NSBundle *bundle=[NSBundle bundleForClass:self.class];
    NSMutableDictionary *context=[@{@"share":share.copy,@"directory":dir,@"bridge":self.bridgeURL,@"generation":@(self.dropGeneration),@"attempts":@0,
        @"diagnostic":[@{@"shareID":share[@"shareID"],@"version":[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
            @"build":[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",@"startedAt":[[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
            @"finished":@NO,@"accepted":@NO,@"snapshots":[NSMutableArray new]} mutableCopy]} mutableCopy];
    self.shareReceiving=YES;self.fallbackImporting=YES;[self updateInterface];
    [self recordShareIntake:context flags:@{}];
    // Return control to the host before any synchronous SDK read. A sheet
    // completion, like a drop callback, can still be inside host modal work.
    [self performSelector:@selector(confirmSharedAudio:) withObject:context afterDelay:.1 inModes:@[NSDefaultRunLoopMode]];
    return YES;
}
- (void)recordShareIntake:(NSMutableDictionary *)context flags:(NSDictionary *)flags {
    NSMutableDictionary *diagnostic=context[@"diagnostic"];
    [diagnostic addEntriesFromDictionary:flags];
    diagnostic[@"updatedAt"]=[[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
    // This local diagnostic belongs only to the explicitly selected share.
    // No project names, file paths, media, model settings or credentials enter it.
    NSURL *dir=context[@"directory"],*url=[dir URLByAppendingPathComponent:@"share-intake.json"];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSDictionary *attrs=[fm attributesOfItemAtPath:dir.path error:nil];
    if (![attrs.fileType isEqual:NSFileTypeDirectory] || [attrs[NSFileOwnerAccountID] unsignedIntegerValue]!=getuid() || [attrs[NSFilePosixPermissions] unsignedIntegerValue]!=0700) return;
    NSDictionary *existing=[fm attributesOfItemAtPath:url.path error:nil];
    if (existing && (![existing.fileType isEqual:NSFileTypeRegular] || [existing[NSFileOwnerAccountID] unsignedIntegerValue]!=getuid())) return;
    NSData *data=[NSJSONSerialization dataWithJSONObject:diagnostic options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    if ([data writeToURL:url options:NSDataWritingAtomic error:nil]) [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];
}
- (BOOL)shareIntakeContextCurrent:(NSDictionary *)context {
    return self.shareReceiving && [context[@"generation"] unsignedIntegerValue]==self.dropGeneration && [context[@"bridge"] isEqual:self.bridgeURL];
}
- (void)stopShareIntake:(NSMutableDictionary *)context failure:(NSString *)failure {
    BOOL current=[self shareIntakeContextCurrent:context];
    [self recordShareIntake:context flags:@{@"finished":@YES,@"accepted":@NO,@"cancelled":@(!current)}];
    self.shareReceiving=NO;
    // A project switch or close already owns the new UI state and input.
    if (current) {
        self.fallbackImporting=NO;
        if (failure) {self.visibleError=failure;self.displayState=@"error";}
    }
    [self updateInterface];
}
- (void)confirmSharedAudio:(NSMutableDictionary *)context {
    if (![self shareIntakeContextCurrent:context]) { [self stopShareIntake:context failure:nil];return; }
    NSDictionary *share=context[@"share"];
    if (![SubPopShareManifest(context[@"directory"]) isEqual:share]) { [self stopShareIntake:context failure:@"这次共享已改变或已接收，请重新选择。原输入已保留。"];return; }
    NSUInteger attempt=[context[@"attempts"] unsignedIntegerValue]+1;context[@"attempts"]=@(attempt);
    if (self.timeline) [self snapshot:@"share-intake-state"];
    CMTime duration=SubPopShareTime(share[@"duration"]),hostDuration=self.observedProjectDuration;
    BOOL current=[self shareIntakeContextCurrent:context];
    BOOL validDuration=self.observed && CMTIME_IS_NUMERIC(hostDuration) && CMTimeGetSeconds(hostDuration)>0;
    BOOL identityMismatch=self.observed && self.observedProjectUID.length && ![self.observedProjectUID isEqual:share[@"projectUID"]];
    BOOL durationMismatch=validDuration && CMTimeCompare(duration,hostDuration)!=0;
    BOOL notReady=!self.observed || !self.observedProjectUID.length || !validDuration;
    NSMutableArray *snapshots=context[@"diagnostic"][@"snapshots"];
    [snapshots addObject:@{@"observed":@(self.observed),@"hasTimeline":@(self.timeline!=nil),@"current":@(current),
        @"expectedProjectUID":share[@"projectUID"],@"observedProjectUID":self.observedProjectUID ?: @"",
        @"expectedDuration":Time(duration),@"observedDuration":Time(hostDuration),@"notReady":@(notReady),
        @"identityMismatch":@(identityMismatch),@"durationMismatch":@(durationMismatch)}];
    [self recordShareIntake:context flags:@{}];
    // SDK reads may deliver an observer callback while waiting for the reply.
    if (!current) { [self stopShareIntake:context failure:nil];return; }
    if (identityMismatch || durationMismatch) {
        [self stopShareIntake:context failure:@"请先在 FCP 打开这次共享的完整项目；当前项目或时长不一致。音频仍保留，可稍后接收。"];return;
    }
    if (notReady) {
        if (attempt<3) [self performSelector:@selector(confirmSharedAudio:) withObject:context afterDelay:.25*attempt inModes:@[NSDefaultRunLoopMode]];
        else [self stopShareIntake:context failure:@"暂时无法读取 FCP 当前项目，音频仍保留。请确认完整项目已打开，再点击接收 FCP 音频重试。"];return;
    }
    [self copyConfirmedSharedAudio:context];
}
- (void)copyConfirmedSharedAudio:(NSMutableDictionary *)context {
    NSDictionary *share=context[@"share"];
    NSURL *dir=context[@"directory"];
    NSUInteger generation=[context[@"generation"] unsignedIntegerValue];
    CMTime duration=SubPopShareTime(share[@"duration"]);
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
            BOOL stale=![self shareIntakeContextCurrent:context] || !self.observed || ![self.observedProjectUID isEqual:share[@"projectUID"]] || !CMTIME_IS_NUMERIC(self.observedProjectDuration) || CMTimeCompare(duration,self.observedProjectDuration);
            [self recordShareIntake:context flags:@{@"contentVerified":@(!failure),@"cancelled":@(stale)}];
            if (stale || failure) {
                [NSFileManager.defaultManager removeItemAtURL:xml error:nil];[NSFileManager.defaultManager removeItemAtURL:audio error:nil];
                self.shareReceiving=NO;
                [self recordShareIntake:context flags:@{@"finished":@YES,@"accepted":@NO}];
                if (!stale) {self.fallbackImporting=NO;self.visibleError=failure;self.displayState=@"error";[self updateInterface];}
                else if (generation==self.dropGeneration) {self.fallbackImporting=NO;[self updateInterface];}
                return;
            }
            if (![SubPopShareManifest(dir) isEqual:share] || !SubPopFinishShare(dir,@"received")) {
                [NSFileManager.defaultManager removeItemAtURL:xml error:nil];[NSFileManager.defaultManager removeItemAtURL:audio error:nil];
                [self stopShareIntake:context failure:@"无法确认接收状态，未开始识别；请重试。"];return;
            }
            self.shareReceiving=NO;
            [self recordShareIntake:context flags:@{@"finished":@YES,@"accepted":@YES}];
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
}
