/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSSlider.h>
#import <AppKit/AppKitIvarLayout.h>

@interface NSSliderCell (NSSliderOrientation)
- (void) _setOrientationFromFrame: (NSRect) frame;
@end

@interface NSSliderAccessory : NSObject {
    NS_LEGACY_IVAR_PAD(_NSSliderAccessoryReserved, 28)
}
@end

@interface NSSliderAccessoryBehavior : NSObject
@end

@interface NSSliderCell (NSSliderVertical)
- (void) _setVerticalForSize: (NSSize) size;
@end

@implementation NSSlider

+ (Class) cellClass {
    return [NSSliderCell class];
}

- initWithFrame: (NSRect) frame {
    if ((self = [super initWithFrame: frame]) == nil)
        return nil;
    // A new slider reports its orientation before it is drawn (macOS 26.7.3): taller than wide is vertical.
    if ([[self cell] respondsToSelector: @selector(_setOrientationFromFrame:)])
        [[self cell] _setOrientationFromFrame: frame];
    return self;
}

// Sliders are flipped views on macOS 10.14.4 and 26.7.3; the cell mirrors its drawing to match.
- (BOOL) isFlipped {
    return YES;
}

// Like macOS, a slider knows whether it is vertical from its frame before it is first drawn.
- (void) setFrameSize: (NSSize) size {
    [super setFrameSize: size];
    if ([[self cell] isKindOfClass: [NSSliderCell class]])
        [(NSSliderCell *) [self cell] _setVerticalForSize: size];
}

// QUIRK: the intrinsic size of a linear slider has no length and is 15, 13 or 12 points thick for the regular, small
// and mini control sizes (21, 18 or 15 with tick marks below and 22, 17 or 15 above a horizontal slider; 22, 18 or 15 right and 21, 17
// or 15 left of a vertical one);
// a circular slider's is 24 x 24 points (18 x 18 for the small size). Not documented. Evidence: black-box
// observation on macOS 10.14.4 (tier 2). Test: test_quirk_slider_cell_size in tests/appkit-small-controls-aqua.m
- (NSSize) intrinsicContentSize {
    NSSliderCell *cell = [self cell];
    NSControlSize size = [cell controlSize];
    int z = size == NSSmallControlSize ? 1 : (size == NSMiniControlSize ? 2 : 0);

    if (![cell isKindOfClass: [NSSliderCell class]])
        return [super intrinsicContentSize];
    if ([cell sliderType] == NSCircularSlider)
        return z == 1 ? NSMakeSize(18, 18) : NSMakeSize(24, 24);

    // [no tick marks, horizontal below, horizontal above, vertical right, vertical left][control size]
    static const CGFloat thickness[5][3] = {{15, 13, 12}, {21, 18, 15}, {22, 17, 15}, {22, 18, 15}, {21, 17, 15}};
    int t = [cell numberOfTickMarks] <= 0 ? 0 : ([cell tickMarkPosition] == NSTickMarkBelow ? 1 : 2);
    BOOL vertical = NSHeight([self bounds]) > NSWidth([self bounds]);
    CGFloat t2 = thickness[vertical && t ? t + 2 : t][z];

    return vertical ? NSMakeSize(t2, NSViewNoIntrinsicMetric) : NSMakeSize(NSViewNoIntrinsicMetric, t2);
}

- (double) minValue {
    return [[self selectedCell] minValue];
}

- (double) maxValue {
    return [[self selectedCell] maxValue];
}

- (double) altIncrementValue {
    return [[self selectedCell] altIncrementValue];
}

- (NSInteger) numberOfTickMarks {
    return [[self selectedCell] numberOfTickMarks];
}

- (NSTickMarkPosition) tickMarkPosition {
    return [[self selectedCell] tickMarkPosition];
}

- (BOOL) allowsTickMarkValuesOnly {
    return [[self selectedCell] allowsTickMarkValuesOnly];
}

- (CGFloat) knobThickness {
    return [[self selectedCell] knobThickness];
}

- (void) setMinValue: (double) value {
    [[self selectedCell] setMinValue: value];
    [self setNeedsDisplay: YES];
}

- (void) setMaxValue: (double) value {
    [[self selectedCell] setMaxValue: value];
    [self setNeedsDisplay: YES];
}

- (void) setAltIncrementValue: (double) value {
    [[self selectedCell] setAltIncrementValue: value];
}

- (void) setNumberOfTickMarks: (NSInteger) value {
    [[self selectedCell] setNumberOfTickMarks: value];
    [self setNeedsDisplay: YES];
}

- (void) setTickMarkPosition: (NSTickMarkPosition) position {
    [[self selectedCell] setTickMarkPosition: position];
    [self setNeedsDisplay: YES];
}

- (void) setAllowsTickMarkValuesOnly: (BOOL) valuesOnly {
    [[self selectedCell] setAllowsTickMarkValuesOnly: valuesOnly];
}

- (void) setKnobThickness: (CGFloat) thickness {
    [[self selectedCell] setKnobThickness: thickness];
    [self setNeedsDisplay: YES];
}

- (NSInteger) isVertical {
    return [[self selectedCell] isVertical];
}

- (void) setVertical: (BOOL) vertical {
    [[self selectedCell] setVertical: vertical];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (NSInteger) indexOfTickMarkAtPoint: (NSPoint) point {
    return [[self selectedCell] indexOfTickMarkAtPoint: point];
}

- (double) tickMarkValueAtIndex: (NSInteger) index {
    return [[self selectedCell] tickMarkValueAtIndex: index];
}

- (double) closestTickMarkValueToValue: (double) value {
    return [[self selectedCell] closestTickMarkValueToValue: value];
}

- (NSRect) rectOfTickMarkAtIndex: (NSInteger) index {
    return [[self selectedCell] rectOfTickMarkAtIndex: index];
}

- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

- (void) keyDown: (NSEvent *) event {
    [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

- (void) moveUp: (id) sender {
    [[self selectedCell] moveUp: sender];
    [self sendAction: [self action] to: [self target]];
    [self setNeedsDisplay: YES];
}

- (void) moveDown: (id) sender {
    [[self selectedCell] moveDown: sender];
    [self sendAction: [self action] to: [self target]];
    [self setNeedsDisplay: YES];
}

- (void) moveLeft: (id) sender {
    [[self selectedCell] moveLeft: sender];
    [self sendAction: [self action] to: [self target]];
    [self setNeedsDisplay: YES];
}

- (void) moveRight: (id) sender {
    [[self selectedCell] moveRight: sender];
    [self sendAction: [self action] to: [self target]];
    [self setNeedsDisplay: YES];
}

@end

@implementation NSSliderAccessory

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSSliderAccessoryBehavior

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
