#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

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
@property NSView *outgoingRow;
@property NSUInteger transitionGeneration;
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
    self.row.frame=self.bounds;
    CGFloat height=ceil(self.currentLabel.intrinsicContentSize.height);
    self.currentLabel.frame=NSMakeRect(70,round((self.bounds.size.height-height)/2),MAX(0,self.bounds.size.width-88),height);
    self.wave.frame=NSMakeRect(18,(self.bounds.size.height-38)/2,38,38);
    [CATransaction commit];
}
- (void)clearTransition {
    self.transitionGeneration++;
    [self.outgoingRow removeFromSuperview];self.outgoingRow=nil;
    [self.row.layer removeAllAnimations];self.row.layer.filters=nil;
    self.row.layerUsesCoreImageFilters=NO;
}
- (void)animateRow:(NSView *)row entering:(BOOL)entering {
    row.wantsLayer=YES;row.layerUsesCoreImageFilters=YES;
    CIFilter *blur=[CIFilter filterWithName:@"CIGaussianBlur"];blur.name=@"phaseBlur";
    [blur setValue:@0 forKey:kCIInputRadiusKey];if (blur) row.layer.filters=@[blur];
    CABasicAnimation *move=[CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    // AppKit's default coordinates grow upward: the new row enters from below.
    move.fromValue=entering ? @(-12) : @0;move.toValue=entering ? @0 : @10;
    CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue=entering ? @0 : @1;fade.toValue=entering ? @1 : @0;
    CABasicAnimation *soften=[CABasicAnimation animationWithKeyPath:@"filters.phaseBlur.inputRadius"];
    soften.fromValue=entering ? @3 : @0;soften.toValue=entering ? @0 : @3;
    CAAnimationGroup *group=[CAAnimationGroup animation];group.animations=blur ? @[move,fade,soften] : @[move,fade];
    group.duration=entering ? .28 : .20;
    group.timingFunction=entering ? [CAMediaTimingFunction functionWithControlPoints:.16 :1 :.3 :1] : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    if (!entering) {group.fillMode=kCAFillModeForwards;group.removedOnCompletion=NO;}
    [row.layer addAnimation:group forKey:@"phase-change"];
}
- (void)prepareOutgoingRow {
    [self clearTransition];
    NSView *old=[[NSView alloc] initWithFrame:self.row.frame];old.wantsLayer=YES;
    NSTextField *label=[NSTextField labelWithString:self.currentLabel.stringValue];label.font=self.currentLabel.font;label.textColor=self.currentLabel.textColor;label.frame=self.currentLabel.frame;[old addSubview:label];
    SubPopSignalView *icon=[[SubPopSignalView alloc] initWithFrame:self.wave.frame];icon.visualStage=self.wave.visualStage;[old addSubview:icon];[icon layoutSubtreeIfNeeded];
    [old setAccessibilityElement:NO];[label setAccessibilityElement:NO];
    [self addSubview:old positioned:NSWindowBelow relativeTo:self.row];self.outgoingRow=old;
    [self animateRow:old entering:NO];
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];if (!self.window) [self clearTransition];
}
- (void)showStage:(NSString *)state active:(BOOL)active {
    NSInteger next=[state isEqual:@"recognize"] ? 1 : ([state isEqual:@"generate-titles"] ? 2 : 0);
    BOOL changed=![self.currentState isEqual:state];BOOL wasVisible=!self.hidden;
    self.hidden=!active;self.stage=next;self.currentState=state;
    if (changed) {
        BOOL animate=active && wasVisible && self.window && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
        if (animate) [self prepareOutgoingRow];else [self clearTransition];
        [self.wave setWorking:NO];self.wave.visualStage=next;self.wave.needsLayout=YES;
        NSDictionary *labels=@{@"preparing":@"正在唤醒本机识别",@"validate":@"正在读取项目",@"decode":@"正在准备音频",@"recognize":@"正在聆听，生成字幕",@"generate-titles":@"正在整理断句与时间"};
        self.currentLabel.stringValue=labels[state] ?: @"正在处理";
        self.needsLayout=YES;
        if (animate) {
            [self animateRow:self.row entering:YES];
            NSUInteger generation=self.transitionGeneration;__weak SubPopActivityView *weakSelf=self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.30*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                SubPopActivityView *view=weakSelf;if (view && view.transitionGeneration==generation) [view clearTransition];
            });
        }
    }
    if (!active) [self clearTransition];
    [self.wave setWorking:active];
    if (active && !wasVisible) SubPopReveal(self.row);
}
@end
