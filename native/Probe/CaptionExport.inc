- (void)downloadSRT:(id)sender { [self saveCaptionsAsSRT:YES]; }
- (void)downloadFCPXML:(id)sender { [self saveCaptionsAsSRT:NO]; }

- (void)saveCaptionsAsSRT:(BOOL)srt {
    if (self.exportInProgress || !self.titlePayloads || !self.captionRows.count) return;
    // Commit the active caption edit before taking a snapshot for either format.
    [self.view.window makeFirstResponder:nil];
    if (!srt && ![self rebuildTitles]) {
        self.exportStatus.stringValue=@"字幕数据不完整，请重新生成后重试。";
        [self updateInterface];return;
    }
    NSError *error=nil;
    NSInteger previous=[NSUserDefaults.standardUserDefaults integerForKey:@"subtitleExportSequence"];
    NSUInteger sequence=(NSUInteger)MAX(0,previous)+1;
    NSString *project=[self.dropName isKindOfClass:NSString.class] && self.dropName.length ? self.dropName : @"SubPop";
    NSData *data=srt ? SubPopSRTExportData(self.captionRows,self.resultManifest[@"frameDuration"],&error)
                     : SubPopTitleExportXML(self.titlePayloads[@"1.12"],project,sequence,&error);
    if (!data) {
        self.exportStatus.stringValue=error.localizedDescription ?: @"字幕导出失败，请重试。";
        [self updateInterface];return;
    }
    NSMutableString *safeName=[NSMutableString new];
    NSCharacterSet *forbidden=[NSCharacterSet characterSetWithCharactersInString:@"/:\\\n\r"];
    for (NSUInteger i=0;i<MIN(project.length,60);i++) {
        unichar character=[project characterAtIndex:i];
        [safeName appendFormat:@"%@",[forbidden characterIsMember:character] ? @"-" : [NSString stringWithCharacters:&character length:1]];
    }
    if (!safeName.length) [safeName appendString:@"SubPop"];
    NSString *extension=srt ? @"srt" : @"fcpxml";
    NSSavePanel *panel=[NSSavePanel savePanel];
    panel.title=srt ? @"下载 SRT 字幕" : @"下载 FCPXML 字幕";
    panel.nameFieldStringValue=[NSString stringWithFormat:@"%@-字幕-%03lu.%@",safeName,(unsigned long)sequence,extension];
    panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:extension conformingToType:srt ? UTTypePlainText : UTTypeXML]];
    panel.canCreateDirectories=YES;
    panel.directoryURL=[[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    self.exportInProgress=YES;[self updateInterface];
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response==NSModalResponseOK && panel.URL) {
            NSURL *url=panel.URL;
            BOOL scoped=[url startAccessingSecurityScopedResource];
            NSError *writeError=nil;
            BOOL saved=[data writeToURL:url options:NSDataWritingAtomic error:&writeError];
            if (scoped) [url stopAccessingSecurityScopedResource];
            if (saved) {
                [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)sequence forKey:@"subtitleExportSequence"];
                self.exportStatus.stringValue=[NSString stringWithFormat:@"已保存到 %@",url.lastPathComponent];
            } else {
                self.exportStatus.stringValue=[NSString stringWithFormat:@"保存失败：%@",writeError.localizedDescription ?: @"请重试"];
            }
        }
        self.exportInProgress=NO;[self updateInterface];
    }];
}
