- (void)checkForUpdates:(id)sender {
    if(self.updatesPanel || !self.view.window)return;
    self.updatesPanel=[SubPopUpdatePanel new];
    __weak typeof(self) weakSelf=self;
    self.updatesPanel.onClose=^{weakSelf.updatesPanel=nil;};
    [self.updatesPanel showForWindow:self.view.window bundle:[NSBundle bundleForClass:self.class]];
}
