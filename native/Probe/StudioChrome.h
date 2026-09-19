#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

static NSColor *SubPopAccent(void) { return [NSColor colorWithCalibratedRed:0.64 green:0.59 blue:1 alpha:1]; }

// A small waveform mark. It moves only while work is active, and settles when done.
@interface SubPopSignalView : NSView
@property NSArray<CALayer *> *bars;
@property BOOL running;
@property NSInteger visualStage;
- (void)setWorking:(BOOL)working;
@end
@implementation SubPopSignalView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.visualStage=1;self.wantsLayer=YES;NSMutableArray *bars=[NSMutableArray new];
        for (int i=0;i<5;i++) { CALayer *bar=[CALayer layer];bar.backgroundColor=SubPopAccent().CGColor;bar.cornerRadius=2;[self.layer addSublayer:bar];[bars addObject:bar]; }
        self.bars=bars;[self setAccessibilityElement:NO];
    } return self;
}
- (void)layout {
    [super layout];CGFloat heights[]={10,20,28,18,10};
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for (int i=0;i<5;i++) {
        CALayer *bar=self.bars[i];bar.hidden=self.visualStage!=1 && i>=3;
        if (self.visualStage==0) bar.frame=CGRectMake((self.bounds.size.width-22)/2+i*8,(self.bounds.size.height-5)/2,5,5);
        else if (self.visualStage==2) bar.frame=CGRectMake((self.bounds.size.width-24)/2,(self.bounds.size.height-20)/2+i*8,i==0 ? 16 : 24,4);
        else bar.frame=CGRectMake((self.bounds.size.width-30)/2+i*6,(self.bounds.size.height-heights[i])/2,4,heights[i]);
    }
    [CATransaction commit];
}
- (void)setWorking:(BOOL)working {
    BOOL animate=working && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && self.window!=nil;
    if (animate==self.running) return;self.running=animate;
    for (int i=0;i<5;i++) {
        CALayer *bar=self.bars[i];[bar removeAllAnimations];
        if (animate && (self.visualStage==1 || i<3)) {
            CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:self.visualStage==1 ? @"transform.scale.y" : @"opacity"];
            a.fromValue=self.visualStage==1 ? @.45 : @.2;a.toValue=@1;
            a.duration=self.visualStage==1 ? .5+i*.055 : .65;
            a.beginTime=CACurrentMediaTime()+i*.045;a.autoreverses=YES;a.repeatCount=HUGE_VALF;
            a.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];[bar addAnimation:a forKey:@"working"];
        }
    }
}
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow];if (!self.window) [self setWorking:NO]; }
@end

static void SubPopReveal(NSView *view) {
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) return;
    view.wantsLayer=YES;
    CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];fade.fromValue=@0;fade.toValue=@1;fade.duration=.22;
    [view.layer addAnimation:fade forKey:@"reveal"];
}

// A clipped rolling row shows only the current phase, never a process checklist.
@interface SubPopActivityView : NSView
@property SubPopSignalView *wave;
@property NSView *row;
@property NSTextField *currentLabel;
@property NSInteger stage;
@property NSString *currentState;
- (void)showStage:(NSString *)state active:(BOOL)active;
@end
@implementation SubPopActivityView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.wantsLayer=YES;self.layer.cornerRadius=12;self.layer.masksToBounds=YES;
        self.layer.backgroundColor=[SubPopAccent() colorWithAlphaComponent:.07].CGColor;
        self.row=[[NSView alloc] initWithFrame:self.bounds];self.row.wantsLayer=YES;[self addSubview:self.row];
        self.wave=[[SubPopSignalView alloc] initWithFrame:NSMakeRect(18,9,38,38)];[self.row addSubview:self.wave];
        self.currentLabel=[NSTextField labelWithString:@""];self.currentLabel.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];self.currentLabel.textColor=SubPopAccent();[self.row addSubview:self.currentLabel];
        self.stage=-1;self.hidden=YES;
    }return self;
}
- (void)layout {
    [super layout];
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.row.frame=self.bounds;self.currentLabel.frame=NSMakeRect(70,19,MAX(0,self.bounds.size.width-88),20);
    [CATransaction commit];
}
- (void)showStage:(NSString *)state active:(BOOL)active {
    NSInteger next=[state isEqual:@"recognize"] ? 1 : ([state isEqual:@"generate-titles"] ? 2 : 0);
    BOOL changed=![self.currentState isEqual:state];BOOL wasVisible=!self.hidden;
    self.hidden=!active;self.stage=next;self.currentState=state;
    if (changed) {
        [self.wave setWorking:NO];self.wave.visualStage=next;self.wave.needsLayout=YES;
        // CATransition retains the outgoing contents while pushing in the next row.
        // Both move downward; clipping keeps previous phases out of the resting UI.
        if (active && wasVisible && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
            CATransition *roll=[CATransition animation];roll.type=kCATransitionPush;roll.subtype=kCATransitionFromBottom;
            roll.duration=.28;roll.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self.row.layer addAnimation:roll forKey:@"stage-roll"];
        }
        NSDictionary *labels=@{@"preparing":@"正在唤醒本机识别",@"validate":@"正在读取项目",@"decode":@"正在准备音频",@"recognize":@"正在聆听，生成字幕",@"generate-titles":@"正在整理断句与时间"};
        self.currentLabel.stringValue=labels[state] ?: @"正在处理";
    }
    if (!active) [self.row.layer removeAllAnimations];
    [self.wave setWorking:active];
    if (active && !wasVisible) SubPopReveal(self.row);
}
@end
