#import <Cocoa/Cocoa.h>
// Drag the idle field to scrub; click to enter ordinary text editing.
@interface SubPopNumberField : NSTextField
@property double minimumValue;
@property double maximumValue;
@property NSPoint dragOrigin;
@property double dragValue;
@property BOOL scrubbing;
@end
@implementation SubPopNumberField
- (void)resetCursorRects {[super resetCursorRects];[self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor];}
- (void)mouseDown:(NSEvent *)event {
    self.dragOrigin=event.locationInWindow;self.dragValue=self.doubleValue;self.scrubbing=NO;
}
- (void)mouseDragged:(NSEvent *)event {
    CGFloat delta=event.locationInWindow.x-self.dragOrigin.x;
    if (!self.scrubbing && fabs(delta)<3) return;
    if (!self.scrubbing) {[self.window makeFirstResponder:nil];self.scrubbing=YES;}
    double step=(event.modifierFlags&NSEventModifierFlagShift) ? .1 : 1;
    double value=MAX(self.minimumValue,MIN(self.maximumValue,self.dragValue+delta*step));
    self.stringValue=[NSString stringWithFormat:@"%.10g",round(value*10)/10];
    [self sendAction:self.action to:self.target];
}
- (void)mouseUp:(NSEvent *)event {
    if (!self.scrubbing) [self selectText:nil];
    self.scrubbing=NO;
}
@end
