- (void)checkForUpdates:(id)sender {
    if (self.updateAlert) return;
    NSBundle *bundle=[NSBundle bundleForClass:self.class];NSString *repository=[bundle objectForInfoDictionaryKey:@"SubPopUpdateRepository"];
    self.updateAlert=[NSAlert new];self.updateAlert.messageText=@"正在检查更新…";self.updateAlert.informativeText=@"正在连接 GitHub Releases，不会上传项目或音频。";[self.updateAlert addButtonWithTitle:@"关闭"];
    NSAlert *alert=self.updateAlert;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response==NSAlertSecondButtonReturn && self.updateURL) [NSWorkspace.sharedWorkspace openURL:self.updateURL];
        self.updateAlert=nil;self.updateURL=nil;
    }];
    if (!repository.length) {alert.messageText=@"尚未配置更新地址";alert.informativeText=@"此版本尚未关联 GitHub 下载仓库。";return;}
    NSString *current=[NSString stringWithFormat:@"%@.%@",[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest",repository]];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];[request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];[request setValue:@"SubPop-Update-Check" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;configuration.timeoutIntervalForResource=25;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        id json=data.length && data.length<1024*1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *update=[json isKindOfClass:NSDictionary.class] ? SubPopReleaseUpdate(json,current,repository) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.updateAlert!=alert) return;
            if (status==404) {alert.messageText=@"暂无公开发行版本";alert.informativeText=@"下载仓库还没有发布正式安装包。稍后可再检查。";}
            else if (error || status!=200 || !update) {alert.messageText=@"暂时无法检查更新";alert.informativeText=@"请检查网络后重试；这不会影响本机识别。";}
            else if ([update[@"newer"] boolValue] && [update[@"installer"] boolValue]) {
                alert.messageText=[@"发现新版本 " stringByAppendingString:update[@"version"]];alert.informativeText=[NSString stringWithFormat:@"当前版本 %@。打开下载页查看更新说明并下载安装。",current];
                self.updateURL=[NSURL URLWithString:update[@"url"]];[alert addButtonWithTitle:@"打开下载页"];
            } else if ([update[@"newer"] boolValue]) {alert.messageText=@"新版本正在准备安装包";alert.informativeText=@"发行记录已更新，安装包尚未就绪。稍后可再检查。";}
            else {alert.messageText=@"当前已是最新版本";alert.informativeText=[NSString stringWithFormat:@"SubPop %@",current];}
        });[session finishTasksAndInvalidate];
    }] resume];
}
