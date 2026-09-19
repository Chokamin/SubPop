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

// Decorative activity, not a waveform measurement or an invented percentage.
@interface SubPopActivityView : NSView
@property SubPopSignalView *wave;
@property NSArray<NSTextField *> *stageLabels;
@property NSInteger stage;
- (void)showStage:(NSString *)state active:(BOOL)active;
@end
@implementation SubPopActivityView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.wantsLayer=YES;self.layer.cornerRadius=10;
        self.layer.backgroundColor=[SubPopAccent() colorWithAlphaComponent:.07].CGColor;
        self.wave=[[SubPopSignalView alloc] initWithFrame:NSMakeRect(8,9,38,38)];[self addSubview:self.wave];
        NSMutableArray *labels=[NSMutableArray new];
        for (NSString *title in @[@"准备音频",@"识别语音",@"整理字幕"]) {
            NSTextField *label=[NSTextField labelWithString:title];label.font=[NSFont systemFontOfSize:11 weight:NSFontWeightMedium];[self addSubview:label];[labels addObject:label];
        }
        self.stageLabels=labels;self.stage=-1;self.hidden=YES;
    }return self;
}
- (void)layout {
    [super layout];CGFloat width=(self.bounds.size.width-24)/3;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.wave.frame=NSMakeRect(12+MAX(0,self.stage)*width,9,30,38);
    for (NSInteger i=0;i<3;i++) {
        CGFloat inset=i==self.stage ? 36 : 8;
        self.stageLabels[i].frame=NSMakeRect(12+i*width+inset,20,width-inset-4,17);
    }
    [CATransaction commit];
}
- (void)showStage:(NSString *)state active:(BOOL)active {
    NSInteger next=[state isEqual:@"recognize"] ? 1 : ([state isEqual:@"generate-titles"] ? 2 : 0);
    BOOL changed=self.hidden==active || next!=self.stage;
    self.hidden=!active;self.stage=next;
    NSArray *titles=@[@"准备音频",@"识别语音",@"整理字幕"];
    for (NSInteger i=0;i<3;i++) {
        NSTextField *label=self.stageLabels[i];
        label.stringValue=i==next ? titles[i] : [NSString stringWithFormat:@"%@  %@",i<next ? @"✓" : @"○",titles[i]];
        label.textColor=i==next ? SubPopAccent() : (i<next ? NSColor.labelColor : NSColor.secondaryLabelColor);
    }
    if (changed) { [self.wave setWorking:NO];self.wave.visualStage=next;self.wave.needsLayout=YES; }
    self.needsLayout=YES;
    [self.wave setWorking:active];
    if (changed && active) {SubPopReveal(self.wave);SubPopReveal(self.stageLabels[next]);}
}
@end
