#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

static NSColor *SubPopAccent(void) { return [NSColor colorWithCalibratedRed:0.64 green:0.59 blue:1 alpha:1]; }

// A small waveform mark. It moves only while work is active, and settles when done.
@interface SubPopSignalView : NSView
@property NSArray<CALayer *> *bars;
@property BOOL running;
- (void)setWorking:(BOOL)working;
@end
@implementation SubPopSignalView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.wantsLayer=YES;NSMutableArray *bars=[NSMutableArray new];
        for (int i=0;i<5;i++) { CALayer *bar=[CALayer layer];bar.backgroundColor=SubPopAccent().CGColor;bar.cornerRadius=2;[self.layer addSublayer:bar];[bars addObject:bar]; }
        self.bars=bars;[self setAccessibilityElement:NO];
    } return self;
}
- (void)layout {
    [super layout];CGFloat heights[]={10,20,28,18,10};
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for (int i=0;i<5;i++) self.bars[i].frame=CGRectMake((self.bounds.size.width-30)/2+i*6,(self.bounds.size.height-heights[i])/2,4,heights[i]);
    [CATransaction commit];
}
- (void)setWorking:(BOOL)working {
    BOOL animate=working && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && self.window!=nil;
    if (animate==self.running) return;self.running=animate;
    for (int i=0;i<5;i++) {
        CALayer *bar=self.bars[i];[bar removeAllAnimations];
        if (animate) { CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"transform.scale.y"];a.fromValue=@0.45;a.toValue=@1;a.duration=.5+i*.055;a.autoreverses=YES;a.repeatCount=HUGE_VALF;a.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];[bar addAnimation:a forKey:@"working"]; }
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
