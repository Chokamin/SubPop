- (void)showFeedback:(id)sender {
    if (self.feedbackPanel || !self.view.window || self.view.window.attachedSheet) return;
    self.feedbackPanel=[SubPopFeedbackPanel new];
    __weak typeof(self) weakSelf=self;
    self.feedbackPanel.onClose=^{weakSelf.feedbackPanel=nil;};
    [self.feedbackPanel showForWindow:self.view.window bundle:[NSBundle bundleForClass:self.class]];
}
