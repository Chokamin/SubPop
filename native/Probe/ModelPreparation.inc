// A confirmed download belongs to one captured project and selection. The
// continuation is intentionally session-local: closing or replacing the input
// never starts recognition later in the background.
- (BOOL)selectedModelDownloadInProgress {
    NSDictionary *task=[self modelTaskState];
    return [@[@"queued",@"running"] containsObject:task[@"status"]] &&
        [task[@"operation"] isEqual:@"install"] && [task[@"modelID"] isEqual:self.selectedModelID] &&
        [task[@"requestID"] isEqual:self.modelRequestID] &&
        ![NSFileManager.defaultManager fileExistsAtPath:[[[self.bridgeURL URLByAppendingPathComponent:self.modelRequestID] URLByAppendingPathComponent:@"cancel.json"] path]];
}
- (NSDictionary *)recognitionContext {
    if (!self.freshDropURL || !self.freshDropDate || ![self isolatedProjectActive] || self.historicalResult || self.snapshotConsumed) return nil;
    NSData *data=[NSData dataWithContentsOfURL:self.freshDropURL];
    if (!data.length || !self.selectedModelID.length) return nil;
    return @{@"modelID":self.selectedModelID,@"projectUID":self.dropUID,@"generation":@(self.dropGeneration),
        @"inputURL":self.freshDropURL,@"inputSHA":[self sha256:data],@"audioIndex":@(self.audioPicker.indexOfSelectedItem),
        @"vocabulary":[self effectiveVocabulary],@"referenceSHA":[self referenceHash:[self effectiveReferenceScript]]};
}
- (BOOL)recognitionContextMatches:(NSDictionary *)context {
    return context && !self.historicalResult && !self.snapshotConsumed && self.freshDropDate && [self isolatedProjectActive] &&
        [context[@"modelID"] isEqual:self.selectedModelID] && [context[@"projectUID"] isEqual:self.dropUID] &&
        [context[@"generation"] unsignedIntegerValue]==self.dropGeneration && [context[@"inputURL"] isEqual:self.freshDropURL] &&
        [context[@"audioIndex"] integerValue]==self.audioPicker.indexOfSelectedItem &&
        [context[@"vocabulary"] isEqual:[self effectiveVocabulary]] &&
        [context[@"referenceSHA"] isEqual:[self referenceHash:[self effectiveReferenceScript]]];
}
- (void)clearPendingRecognition {
    self.pendingRecognition=nil;self.modelReadyObservedDate=nil;
    NSAlert *alert=self.modelDownloadAlert;self.modelDownloadAlert=nil;
    if (alert.window.sheetParent) [alert.window.sheetParent endSheet:alert.window returnCode:NSAlertSecondButtonReturn];
}
- (void)confirmModelDownload {
    if (self.modelDownloadAlert || self.pendingRecognition || [self selectedCloudModel]) return;
    NSDictionary *context=[self recognitionContext];if (!context) return;
    BOOL downloading=[self selectedModelDownloadInProgress];
    if ([self modelOperationBusy] && !downloading) return;
    NSAlert *alert=[NSAlert new];self.modelDownloadAlert=alert;
    NSString *name=[self selectedModel][@"name"] ?: @"所选模型";
    alert.messageText=downloading ? @"模型下载完成后开始识别？" : @"需要先下载识别模型";
    if (downloading) alert.informativeText=[NSString stringWithFormat:@"%@ 正在下载。确认后会在下载并校验完成时，自动识别「%@」。",name,self.dropName ?: @"当前项目"];
    else {
        NSDictionary *catalog=[self readJSON:[[NSBundle bundleForClass:self.class] URLForResource:@"models" withExtension:@"json"]];
        unsigned long long bytes=0;for (NSNumber *size in [[self selectedModel][@"files"] allValues]) bytes+=size.unsignedLongLongValue;
        BOOL needsAligner=![self selectedModel][@"engine"];
        if (needsAligner) for (NSNumber *size in [catalog[@"aligner"][@"files"] allValues]) bytes+=size.unsignedLongLongValue;
        alert.informativeText=[NSString stringWithFormat:@"%@ 尚未下载完整。确认后会先下载并校验，再自动识别「%@」。\n\n下载内容最多约 %.2f GB%@，已下载的文件会复用。只需首次准备，之后可离线使用。",name,self.dropName ?: @"当前项目",bytes/1e9,needsAligner ? @"（含时间对齐模型）" : @""];
    }
    [alert addButtonWithTitle:downloading ? @"下载后开始识别" : @"下载并开始识别"];
    [alert addButtonWithTitle:@"取消"];
    [self updateInterface];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (self.modelDownloadAlert!=alert) return;
        self.modelDownloadAlert=nil;
        if (response==NSAlertFirstButtonReturn && [self recognitionContextMatches:context]) [self prepareModelForRecognition:context];
        [self updateInterface];
    }];
}
- (void)prepareModelForRecognition:(NSDictionary *)context {
    if (![self recognitionContextMatches:context] || self.requestID || self.referenceRequestID || self.pendingRecognition || [self selectedCloudModel]) return;
    // Another explicit download may have completed while the confirmation was open.
    if ([self selectedModelAvailable]) { [self submitWorkerJob];return; }
    NSString *request=[self selectedModelDownloadInProgress] ? self.modelRequestID : [self submitModelOperation:@"install" model:context[@"modelID"]];
    if (!request) {self.displayState=@"model-download-failed";[self updateInterface];return;}
    NSMutableDictionary *pending=context.mutableCopy;pending[@"downloadRequestID"]=request;
    self.pendingRecognition=pending;self.modelReadyObservedDate=nil;self.visibleError=nil;
    self.displayState=@"model-download";self.cancelButton.enabled=YES;[self updateInterface];
}
- (void)failModelPreparation:(NSString *)message {
    [self clearPendingRecognition];self.visibleError=message;self.displayState=@"model-download-failed";
}
- (void)pollModelPreparation {
    NSDictionary *context=self.pendingRecognition;if (!context) return;
    if (![self recognitionContextMatches:context]) {
        [self clearPendingRecognition];self.displayState=self.freshDropURL ? @"input" : @"idle";return;
    }
    if (![self workerAvailable]) { [self failModelPreparation:@"本机服务连接中断。项目已保留，恢复连接后可继续下载和识别。"];return; }
    NSString *request=context[@"downloadRequestID"];
    NSURL *directory=[self.bridgeURL URLByAppendingPathComponent:request];
    if ([NSFileManager.defaultManager fileExistsAtPath:[[directory URLByAppendingPathComponent:@"cancel.json"] path]]) {
        [self clearPendingRecognition];self.displayState=@"model-download-cancelled";return;
    }
    NSDictionary *response=[self readJSON:[directory URLByAppendingPathComponent:@"response.json"]];
    if (!response) return;
    if (![response[@"requestID"] isEqual:request] || ![response[@"modelID"] isEqual:context[@"modelID"]] || ![response[@"operation"] isEqual:@"install"]) {
        [self failModelPreparation:@"下载任务状态异常。项目已保留，请点击“生成字幕”重试。"];return;
    }
    NSString *status=response[@"status"];
    if ([status isEqual:@"cancelled"]) { [self clearPendingRecognition];self.displayState=@"model-download-cancelled";return; }
    if ([status isEqual:@"failed"]) { [self failModelPreparation:response[@"error"] ?: @"请检查网络和磁盘空间后重试。"];return; }
    if (![status isEqual:@"ready"]) return;
    // The atomic download result can precede the next service catalog heartbeat.
    // Wait for both; never infer installed state from progress reaching 100%.
    if (![self selectedModelAvailable]) {
        if (!self.modelReadyObservedDate) self.modelReadyObservedDate=NSDate.date;
        if (-self.modelReadyObservedDate.timeIntervalSinceNow>15) [self failModelPreparation:@"模型尚未通过就绪检查。项目已保留，请点击“生成字幕”重试。"];return;
    }
    NSData *data=[NSData dataWithContentsOfURL:self.freshDropURL];
    if (!data || ![[self sha256:data] isEqual:context[@"inputSHA"]]) {
        [self clearPendingRecognition];self.freshDropURL=nil;self.freshDropDate=nil;self.displayState=@"expired";return;
    }
    [self clearPendingRecognition];
    [self submitWorkerJob];
}
- (void)updateModelPreparationInterface {
    if ([self.displayState isEqual:@"model-download-failed"] && self.visibleError.length) self.statusDetail.stringValue=[NSString stringWithFormat:@"%@\n项目已保留。点击“生成字幕”重试，已下载部分会继续使用。",self.visibleError];
    if (!self.pendingRecognition) return;
    NSDictionary *task=[self modelTaskState];NSString *stage=task[@"stage"];
    BOOL hasProgress=[task[@"progress"] isKindOfClass:NSNumber.class];double progress=MAX(0,MIN(1,[task[@"progress"] doubleValue]));
    self.generateButton.title=@"下载后自动识别";self.generateButton.enabled=NO;
    self.statusTitle.stringValue=[stage isEqual:@"checking"] || [task[@"status"] isEqual:@"ready"] ? @"正在校验识别模型" : (hasProgress ? [NSString stringWithFormat:@"正在下载识别模型 · %.0f%%",progress*100] : @"正在准备下载识别模型");
    self.statusDetail.stringValue=[task[@"totalBytes"] doubleValue]>0 ? [NSString stringWithFormat:@"%@ · %.2f / %.2f GB\n完成后自动识别当前项目，无需再次点击。",[self selectedModel][@"name"],[task[@"completedBytes"] doubleValue]/1e9,[task[@"totalBytes"] doubleValue]/1e9] : @"项目已保留，下载并校验完成后会自动开始识别。";
    self.jobBar.hidden=!hasProgress;self.jobBar.doubleValue=progress;
    self.cancelButton.hidden=NO;[self.activity showStage:@"model-download" active:YES];
}
