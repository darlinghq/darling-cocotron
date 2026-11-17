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
#import <AppKit/NSImage.h>
#import <AppKit/NSStepper.h>
#import <AppKit/NSStepperCell.h>
#import <AppKit/NSWindow.h>

@interface NSStepperCell (NSStepperCell_private)
- (NSImage *) _stepUpImage;
- (NSImage *) _stepDownImage;
@end

@implementation NSStepper

+ (Class) cellClass {
    return [NSStepperCell class];
}

// An NSArchiver archive of a stepper has four more ints after the control part (unused).
- initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) != nil && ![coder allowsKeyedCoding]) {
        int unused[4];

        [coder decodeValuesOfObjCTypes: "iiii", &unused[0], &unused[1], &unused[2], &unused[3]];
    }
    return self;
}

- (double) minValue {
    return [_cell minValue];
}

- (double) increment {
    return [_cell increment];
}

- (double) maxValue {
    return [_cell maxValue];
}

- (BOOL) autorepeat {
    return [_cell autorepeat];
}

- (BOOL) valueWraps {
    return [_cell valueWraps];
}

- (void) setMinValue: (double) value {
    [_cell setMinValue: value];
}

- (void) setIncrement: (double) value {
    [_cell setIncrement: value];
}

- (void) setMaxValue: (double) value {
    [_cell setMaxValue: value];
}

- (void) setAutorepeat: (BOOL) flag {
    [_cell setAutorepeat: flag];
}

- (void) setValueWraps: (BOOL) flag {
    [_cell setValueWraps: flag];
}

// The size of a stepper's two arrows, by control size.
// QUIRK: a stepper has an intrinsic size of its own, 19x27, 15x22 and 13x15 points at the regular,
// small and mini control sizes. Not documented. Evidence: black-box observation on macOS 10.14.4
// (tier 2) of the intrinsic size and alignment insets; 26.7.3 differs and is not followed.
// Test: tests/appkit-popup-stepper-intrinsic-size.m (test_quirk_stepper_intrinsic_size)
- (NSSize) intrinsicContentSize {
    switch ([[self cell] controlSize]) {
    case NSSmallControlSize:
        return NSMakeSize(15, 22);
    case NSMiniControlSize:
        return NSMakeSize(13, 15);
    default:
        return NSMakeSize(19, 27);
    }
}

- (void) sizeToFit {
    // the stepper's own size (it used to ask for two images that do not exist, which raised an exception)
    [self setFrameSize: [self intrinsicContentSize]];
}

- (void) mouseDown: (NSEvent *) event {
    BOOL sendAction = NO;

    if (![self isEnabled])
        return;

    [self lockFocus];
    sendAction = [_cell trackMouse: event
                            inRect: [self bounds]
                            ofView: self
                      untilMouseUp: YES];
    [self unlockFocus];

    if (sendAction == YES)
        [self sendAction: [self action] to: [self target]];

    [self setNeedsDisplay: YES];
}

- (void) keyDown: (NSEvent *) event {
    [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

- (void) moveUp: (id) sender {
    [self lockFocus];
    [[self selectedCell] moveUp: sender];
    [self unlockFocus];

    [self setNeedsDisplay: YES];
}

- (void) moveDown: (id) sender {
    [self lockFocus];
    [[self selectedCell] moveDown: sender];
    [self unlockFocus];

    [self setNeedsDisplay: YES];
}

@end
