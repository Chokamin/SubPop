- (void)openTitleImportURL:(NSURL *)fileURL applicationURL:(NSURL *)applicationURL completion:(void (^)(NSError *))completion {
    NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];
    configuration.activates=YES;
    [NSWorkspace.sharedWorkspace openURLs:@[fileURL] withApplicationAtURL:applicationURL configuration:configuration completionHandler:^(NSRunningApplication *app,NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{completion(error);});
    }];
}
- (void)importTitlesToFCP:(id)sender {
    if (![self usesFileImport] || ![self canDragResult] || self.importInProgress ||
        (self.lastImportAttempt && -self.lastImportAttempt.timeIntervalSinceNow<2)) return;
    [self.view.window makeFirstResponder:nil];
    if (![self resolveTap5a]) {
        self.importMessage=@"无法读取 Tap5a 模板，请重新选择已安装的模板后再导入。";[self updateInterface];return;
    }
    [self rebuildTitles];
    // These titles use features common to all supported payload versions.
    NSData *snapshot=self.titlePayloads[@"1.12"];
    NSError *error=nil;
    // Reserve a persistent import number, including retries; never reuse names
    // after relaunch or when importing the same recognition with new styling.
    NSInteger previous=[NSUserDefaults.standardUserDefaults integerForKey:@"titleImportSequence"];
    NSUInteger sequence=(NSUInteger)MAX(0,previous)+1;
    [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)sequence forKey:@"titleImportSequence"];
    NSData *data=SubPopTitleImportXML(snapshot,self.dropName,sequence,&error);
    NSURL *applicationURL=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.FinalCut"];
    if (!data || !applicationURL) {
        self.importMessage=error.localizedDescription ?: @"找不到 Final Cut Pro，请确认它已安装后重试。";[self updateInterface];return;
    }
    NSURL *directory=[[self evidenceDirectory] URLByAppendingPathComponent:@"TitleExports" isDirectory:YES];
    NSURL *fileURL=[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"SubPop-%@.fcpxml",NSUUID.UUID.UUIDString]];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![data writeToURL:fileURL options:NSDataWritingAtomic error:&error]) {
        self.importMessage=[NSString stringWithFormat:@"无法准备字幕文件：%@",error.localizedDescription ?: @"请重试"];
        [self updateInterface];return;
    }
    // Retain the file: Launch Services acknowledgement is not proof FCP has read it.
    self.lastImportAttempt=NSDate.date;self.importInProgress=YES;self.importMessage=@"正在打开 Final Cut Pro 的字幕导入…";
    NSUInteger generation=self.dropGeneration;
    [self saveDraft];[self updateInterface];
    [self openTitleImportURL:fileURL applicationURL:applicationURL completion:^(NSError *openError) {
        self.importInProgress=NO;
        if (self.dropGeneration==generation && [self usesFileImport] && [self.titlePayloads[@"1.12"] isEqual:snapshot]) {
            self.importMessage=openError ? [NSString stringWithFormat:@"未能发送到 Final Cut Pro：%@。请重试。",openError.localizedDescription] : @"已发送导入请求。若 FCP 询问资源库，请选择原项目所在资源库；然后从“SubPop 字幕”事件拖回时间线起点上方。再次点击会重新导入。";
        }
        [self record:@{@"reason":@"title-file-import",@"status":openError ? @"failed" : @"request-sent",@"file":fileURL.lastPathComponent,@"error":openError.localizedDescription ?: @""}];
    }];
}
