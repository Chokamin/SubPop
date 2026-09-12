#import "ProbePresentation.h"
NSDictionary<NSString *, NSString *> *SubPopPresentation(NSString *state) {
    NSDictionary *states=@{
        @"idle":@[@"等待导入项目",@"拖入项目后，即可识别完整视频的中文字幕。"],
        @"inactive":@[@"请打开这个项目的时间线",@"在 Final Cut Pro 中打开 Subloom-Original，再开始识别。"],
        @"input":@[@"项目已就绪",@"点击“开始识别”。处理会在本机完成。"],
        @"validate":@[@"正在读取项目",@"检查音频与时间线，保留剪切、空隙和静音。"],
        @"decode":@[@"正在准备音频",@"按时间线顺序整理整段音频，请稍候。"],
        @"recognize":@[@"正在识别语音",@"正在生成文字并对齐时间，无需操作 Final Cut Pro。"],
        @"generate-titles":@[@"正在整理字幕",@"检查句子、时间和已有字幕。"],
        @"ready":@[@"字幕已准备好",@"拖到原项目起点上方，再用“将片段项分开”逐句编辑。"],
        @"duplicate":@[@"这些字幕已经在时间线上",@"没有重复生成。你可以直接在 Final Cut Pro 中继续编辑。"],
        @"conflict":@[@"检测到重叠字幕",@"已保留现有编辑。请先整理时间线上的字幕，再拖入项目识别。"],
        @"silent":@[@"没有可识别的音频",@"整段音频为静音。请检查片段或音频组件是否已启用。"],
        @"expired":@[@"请重新拖入项目",@"快照或字幕结果已过期。重新拖入可确保时间线与识别内容一致。"],
        @"error":@[@"这次未能完成识别",@"请检查项目，或在“模型与设置”中重新准备识别。技术详情可在“诊断”中查看。"],
        @"invalid-input":@[@"这个项目暂不支持",@"当前测试版请拖入浏览器中的 Subloom-Original 项目。"],
        @"sent":@[@"字幕已拖出",@"请在 Final Cut Pro 中确认落点，再将片段项分开以逐句编辑。"],
        @"disconnected":@[@"准备开始识别",@"首次使用请点击下方按钮，允许 SubPop 在本机处理字幕。"],
        @"preparing":@[@"正在准备本机识别",@"识别程序会自动在后台运行。首次使用请完成系统显示的文件夹授权。"],
        @"setup-needed":@[@"需要完成首次设置",@"请完成 SubPop 的文件夹授权，然后点击下方按钮重试。"],
        @"wrong-directory":@[@"尚未完成设置",@"请再次准备识别，使用默认打开的任务文件夹。"],
        @"unsupported":@[@"这个项目包含暂不支持的音频",@"目前支持连续单声道片段、空隙、静音和恒定音量衰减。请移除变速或音频效果后重试。"]
    };
    NSArray *copy=states[state] ?: states[@"idle"];
    return @{@"title":copy[0],@"detail":copy[1]};
}
