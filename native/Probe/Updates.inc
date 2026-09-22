- (void)checkForUpdates:(id)sender {
    if(self.updatesPanel || !self.view.window)return;
    self.updatesPanel=[SubPopUpdatePanel new];
    __weak typeof(self) weakSelf=self;
    self.updatesPanel.canInstall=^BOOL{typeof(self) owner=weakSelf;return owner && !owner.requestID && !owner.referenceRequestID && !owner.importInProgress && ![owner modelOperationBusy];};
    self.updatesPanel.onClose=^{weakSelf.updatesPanel=nil;};
    [self.updatesPanel showForWindow:self.view.window bundle:[NSBundle bundleForClass:self.class]];
}
