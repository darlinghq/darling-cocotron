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

#import <AppKit/NSLevelIndicator.h>
#import <AppKit/NSLevelIndicatorCell.h>
#import <AppKit/NSImage.h>

@implementation NSLevelIndicator

+ (Class) cellClass {
    return [NSLevelIndicatorCell class];
}

- (NSLevelIndicatorCell *) _indicatorCell {
    return [self cell];
}

- (double) minValue {
    return [[self _indicatorCell] minValue];
}

- (double) maxValue {
    return [[self _indicatorCell] maxValue];
}

- (double) warningValue {
    return [[self _indicatorCell] warningValue];
}

- (double) criticalValue {
    return [[self _indicatorCell] criticalValue];
}

- (int) numberOfTickMarks {
    return [[self _indicatorCell] numberOfTickMarks];
}

- (int) numberOfMajorTickMarks {
    return [[self _indicatorCell] numberOfMajorTickMarks];
}

- (NSTickMarkPosition) tickMarkPosition {
    return [[self _indicatorCell] tickMarkPosition];
}

- (void) setMinValue: (double) value {
    [[self _indicatorCell] setMinValue: value];
    [self setNeedsDisplay: YES];
}

- (void) setMaxValue: (double) value {
    [[self _indicatorCell] setMaxValue: value];
    [self setNeedsDisplay: YES];
}

- (void) setWarningValue: (double) value {
    [[self _indicatorCell] setWarningValue: value];
    [self setNeedsDisplay: YES];
}

- (void) setCriticalValue: (double) value {
    [[self _indicatorCell] setCriticalValue: value];
    [self setNeedsDisplay: YES];
}

- (void) setNumberOfTickMarks: (int) count {
    [[self _indicatorCell] setNumberOfTickMarks: count];
    [self setNeedsDisplay: YES];
}

- (void) setNumberOfMajorTickMarks: (int) count {
    [[self _indicatorCell] setNumberOfMajorTickMarks: count];
    [self setNeedsDisplay: YES];
}

- (void) setTickMarkPosition: (NSTickMarkPosition) position {
    [[self _indicatorCell] setTickMarkPosition: position];
    [self setNeedsDisplay: YES];
}

- (NSLevelIndicatorStyle) levelIndicatorStyle {
    return [[self _indicatorCell] levelIndicatorStyle];
}

- (void) setLevelIndicatorStyle: (NSLevelIndicatorStyle) style {
    [[self _indicatorCell] setLevelIndicatorStyle: style];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (NSImage *) ratingImage {
    return [[self _indicatorCell] ratingImage];
}

- (void) setRatingImage: (NSImage *) image {
    [[self _indicatorCell] setRatingImage: image];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (NSImage *) ratingPlaceholderImage {
    return [[self _indicatorCell] ratingPlaceholderImage];
}

- (void) setRatingPlaceholderImage: (NSImage *) image {
    [[self _indicatorCell] setRatingPlaceholderImage: image];
    [self setNeedsDisplay: YES];
}

// An editable rating indicator takes the rating of the unit that is clicked or dragged over, and sends its action
// whenever that changes (tracking as documented for controls; the unit mapping is the QUIRK in the cell).
- (void) mouseDown: (NSEvent *) event {
    NSLevelIndicatorCell *cell = [self _indicatorCell];

    if (![self isEnabled] || ![self isEditable] || [cell levelIndicatorStyle] != NSRatingLevelIndicatorStyle) {
        [super mouseDown: event];
        return;
    }
    do {
        double value = [cell _ratingValueAtPoint: [self convertPoint: [event locationInWindow] fromView: nil]
                                          inRect: [self bounds]];

        if (value != [cell doubleValue]) {
            [cell setDoubleValue: value];
            [self setNeedsDisplay: YES];
            [self sendAction: [self action] to: [self target]];
        }
        if ([event type] == NSLeftMouseUp)
            break;
        event = [[self window] nextEventMatchingMask: NSLeftMouseUpMask | NSLeftMouseDraggedMask];
    } while (event != nil);
}

- (double) tickMarkValueAtIndex: (int) index {
    return [[self _indicatorCell] tickMarkValueAtIndex: index];
}

- (NSRect) rectOfTickMarkAtIndex: (int) index {
    return [[self _indicatorCell] rectOfTickMarkAtIndex: index];
}

@end
