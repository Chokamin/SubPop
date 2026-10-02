// Keep proofreading separate from the selected output script. Conversion is
// always derived from this base, never by round-tripping the displayed output.
static NSString *SubPopChineseModeID(SubPopChineseTextMode mode) {
    return mode==SubPopChineseTextSimplified ? @"simplified" : mode==SubPopChineseTextTraditional ? @"traditional" : @"keep";
}
static NSMutableArray *SubPopMutableCaptionRows(NSArray *rows) {
    NSMutableArray *copy=[NSMutableArray new];
    for (NSDictionary *row in rows) [copy addObject:row.mutableCopy];
    return copy;
}
- (void)resetChineseText {
    self.captionSourceRows=nil;self.chineseTextMode=SubPopChineseTextKeep;
    [self.chineseTextPicker selectItemAtIndex:SubPopChineseTextKeep];
}
- (BOOL)applyChineseTextMode:(SubPopChineseTextMode)mode {
    if (mode<SubPopChineseTextKeep || mode>SubPopChineseTextTraditional || !self.titlePayloads || !self.captionRows.count) return NO;
    NSArray *source=self.captionSourceRows ?: self.captionRows;
    if (![self referenceRows:source matchTimingOf:self.captionRows]) return NO;
    NSMutableArray *converted=[NSMutableArray new];NSError *error=nil;
    for (NSDictionary *row in source) {
        NSString *text=SubPopChineseConvert(row[@"text"],mode,&error);
        if (!text.length || text.length>500) {
            self.exportStatus.stringValue=error.localizedDescription ?: @"文字转换未完成，字幕保持原样。";
            [self updateInterface];return NO;
        }
        NSMutableDictionary *output=row.mutableCopy;output[@"text"]=text;[converted addObject:output];
    }
    NSMutableArray *previousRows=self.captionRows,*previousSource=self.captionSourceRows;
    SubPopChineseTextMode previousMode=self.chineseTextMode;
    self.captionSourceRows=SubPopMutableCaptionRows(source);self.captionRows=converted;self.chineseTextMode=mode;
    if (![self rebuildTitles]) {
        self.captionRows=previousRows;self.captionSourceRows=previousSource;self.chineseTextMode=previousMode;
        self.exportStatus.stringValue=@"字幕文件未能更新，文字形式保持原样。";[self updateInterface];return NO;
    }
    [self.chineseTextPicker selectItemAtIndex:mode];
    if (self.tap5aPreview && self.captionRows.count) {
        NSInteger index=MAX(0,MIN((NSInteger)self.captionRows.count-1,self.tap5aPreviewIndex));
        self.tap5aPreview.caption=self.captionRows[index][@"text"];self.tap5aPreview.needsDisplay=YES;
    }
    return YES;
}
- (void)chineseTextChanged:(id)sender {
    SubPopChineseTextMode mode=self.chineseTextPicker.indexOfSelectedItem;
    if (self.requestID || self.referenceRequestID || self.pendingRecognition || self.importInProgress || self.exportInProgress || !self.titlePayloads) {
        [self.chineseTextPicker selectItemAtIndex:self.chineseTextMode];return;
    }
    // The picker has already changed when this action arrives. Commit the
    // active cell using the previous mode before deriving the new output.
    if (![self.view.window makeFirstResponder:nil] && self.view.window) {
        [self.chineseTextPicker selectItemAtIndex:self.chineseTextMode];return;
    }
    [self applyChineseTextMode:mode];
    [self.chineseTextPicker selectItemAtIndex:self.chineseTextMode];
}
- (BOOL)restoreChineseTextDraft:(NSDictionary *)draft {
    if (![draft isKindOfClass:NSDictionary.class]) return NO;
    NSString *identifier=draft[@"chineseTextMode"] ?: @"keep";
    NSArray *ids=@[@"keep",@"simplified",@"traditional"];
    if (![identifier isKindOfClass:NSString.class] || ![ids containsObject:identifier]) return NO;
    NSArray *source=draft[@"sourceCaptions"] ?: draft[@"captions"];
    if (![self referenceRows:source matchTimingOf:self.captionRows]) return NO;
    NSMutableArray *previous=self.captionSourceRows;self.captionSourceRows=SubPopMutableCaptionRows(source);
    if ([self applyChineseTextMode:(SubPopChineseTextMode)[ids indexOfObject:identifier]]) return YES;
    self.captionSourceRows=previous;return NO;
}
