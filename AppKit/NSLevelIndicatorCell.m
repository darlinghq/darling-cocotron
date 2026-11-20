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

#import <AppKit/NSLevelIndicatorCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSView.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBezierPath.h>
#import <objc/runtime.h>

@implementation NSLevelIndicatorCell

// An NSArchiver archive holds the value, minimum, maximum, warning and critical values, the
// numbers of tick marks and major tick marks, a flag word (bits 28-29 the style, bit 27 the
// tick marks above) and four more ints (two of unknown meaning, two unused). Keyed archives
// are read by NSCell and NSActionCell only.
- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if (![coder allowsKeyedCoding]) {
        double value;
        int flags, unused[4];

        [coder decodeValuesOfObjCTypes: "dddddiiiiiii", &value, &_minValue, &_maxValue, &_warningValue,
                                        &_criticalValue, &_numberOfTickMarks, &_numberOfMajorTickMarks, &flags,
                                        &unused[0], &unused[1], &unused[2], &unused[3]];
        [NS_EXTRA(NSCell, self)->_objectValue release];
        NS_EXTRA(NSCell, self)->_objectValue = [[NSNumber numberWithDouble: value] retain];
        _style = ((unsigned) flags >> 28) & 3;
        _tickMarkPosition = ((unsigned) flags >> 27) & 1 ? NSTickMarkAbove : NSTickMarkBelow;
    }
    return self;
}

// QUIRK: -init makes a discrete capacity indicator; the maximum is 100 for the relevancy and continuous capacity
// styles and 5 for the discrete capacity and rating styles, and the warning and critical values are 0. Not
// documented. Evidence: black-box observation on macOS 10.14.4 (tier 2),
// vd-upstream/mac-probes/aqua-small-controls-2.m. Test: test_quirk_level_indicator_defaults in
// tests/appkit-small-controls-aqua.m
- init {
    return [self initWithLevelIndicatorStyle: NSDiscreteCapacityLevelIndicatorStyle];
}

- initWithLevelIndicatorStyle: (NSLevelIndicatorStyle) style {
    [super init];
    _style = style;
    _minValue = 0;
    _maxValue = (_style == NSRelevancyLevelIndicatorStyle || _style == NSContinuousCapacityLevelIndicatorStyle) ? 100 : 5;
    _warningValue = 0;
    _criticalValue = 0;
    _numberOfTickMarks = 0;
    _numberOfMajorTickMarks = 0;
    _tickMarkPosition = NSTickMarkBelow;
    return self;
}

- (NSLevelIndicatorStyle) levelIndicatorStyle {
    return _style;
}

- (double) minValue {
    return _minValue;
}

- (double) maxValue {
    return _maxValue;
}

- (double) warningValue {
    return _warningValue;
}

- (double) criticalValue {
    return _criticalValue;
}

- (int) numberOfTickMarks {
    return _numberOfTickMarks;
}

- (int) numberOfMajorTickMarks {
    return _numberOfMajorTickMarks;
}

- (NSTickMarkPosition) tickMarkPosition {
    return _tickMarkPosition;
}

- (void) setLevelIndicatorStyle: (NSLevelIndicatorStyle) style {
    _style = style;
}

- (void) setMinValue: (double) value {
    _minValue = value;
}

- (void) setMaxValue: (double) value {
    _maxValue = value;
}

- (void) setWarningValue: (double) value {
    _warningValue = value;
}

- (void) setCriticalValue: (double) value {
    _criticalValue = value;
}

- (void) setNumberOfTickMarks: (int) count {
    _numberOfTickMarks = count;
}

- (void) setNumberOfMajorTickMarks: (int) count {
    _numberOfMajorTickMarks = count;
}

- (void) setTickMarkPosition: (NSTickMarkPosition) position {
    _tickMarkPosition = position;
}

- (void) setImage: (NSImage *) image {
}

// The rating images are kept as associated objects: they are rarely set, and this keeps the instance layout of
// the cell, which the legacy ABI fixes, unchanged.
static char ratingImageKey, ratingPlaceholderImageKey;

// Not documented what the defaults are: both are nil in a new cell. Evidence: black-box observation on macOS
// 10.14.4 and 26.7.3 (tier 2). Test: test_quirk_rating_style in tests/appkit-level-indicator-styles.m
- (NSImage *) ratingImage {
    return objc_getAssociatedObject(self, &ratingImageKey);
}

- (void) setRatingImage: (NSImage *) image {
    objc_setAssociatedObject(self, &ratingImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSImage *) ratingPlaceholderImage {
    return objc_getAssociatedObject(self, &ratingPlaceholderImageKey);
}

- (void) setRatingPlaceholderImage: (NSImage *) image {
    objc_setAssociatedObject(self, &ratingPlaceholderImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// QUIRK: a rating indicator shows round(maximum - minimum) units in a row from the left edge of the cell, each
// 12 points square (or the size of the rating image when one is set), and a click on a unit makes its number
// (counted from the minimum) the value; positions past the last unit give the last one. Evidence: black-box
// observation on macOS 10.14.4 (tier 2). Test: test_quirk_rating_style in tests/appkit-level-indicator-styles.m
- (NSSize) _ratingUnitSize {
    NSImage *image = [self ratingImage];

    if (image != nil && [image size].width > 0 && [image size].height > 0)
        return [image size];
    return NSMakeSize(12, 12);
}

- (int) _ratingUnits {
    return MAX(0, (int) floor(_maxValue - _minValue + 0.5));
}

- (double) _ratingValueAtPoint: (NSPoint) point inRect: (NSRect) frame {
    int units = [self _ratingUnits];
    int unit = (int) floor((point.x - NSMinX(frame)) / [self _ratingUnitSize].width) + 1;

    return _minValue + MAX(1, MIN(units, unit));
}

- (double) tickMarkValueAtIndex: (int) index {
    if (_numberOfTickMarks <= 1)
        return _minValue;
    return _minValue + (_maxValue - _minValue) * index / (_numberOfTickMarks - 1);
}

- (NSRect) rectOfTickMarkAtIndex: (int) index {
    NSUnimplementedMethod();
    return NSZeroRect;
}

// QUIRK: the filled part is green, yellow from the warning value on and red from the critical value on, in the
// direction in which the critical value lies from the warning value (so both thresholds work downwards when the
// critical value is the smaller one); when the two are equal (as by default) it stays green. The colours are
// (54, 210, 66), (254, 206, 9) and (252, 44, 49). Not documented beyond the thresholds' existence. Evidence:
// black-box observation on macOS 10.14.4 (tier 2), vd-upstream/mac-probes/aqua-small-controls-2.m.
// Test: test_quirk_level_indicator_colors in tests/appkit-small-controls-aqua.m
- (NSColor *) _fillColor {
    double value = [self doubleValue];

    if (_criticalValue != _warningValue) {
        BOOL rising = _criticalValue > _warningValue;

        if (rising ? value >= _criticalValue : value <= _criticalValue)
            return [NSColor colorWithCalibratedRed: 252 / 255.0 green: 44 / 255.0 blue: 49 / 255.0 alpha: 1];
        if (rising ? value >= _warningValue : value <= _warningValue)
            return [NSColor colorWithCalibratedRed: 254 / 255.0 green: 206 / 255.0 blue: 9 / 255.0 alpha: 1];
    }
    return [NSColor colorWithCalibratedRed: 54 / 255.0 green: 210 / 255.0 blue: 66 / 255.0 alpha: 1];
}

// QUIRK: -cellSize of a capacity indicator is 40000 x 18 points and of a relevancy indicator 40000 x 12. Not
// documented. Evidence: black-box observation on macOS 10.14.4 (tier 2). Test: test_quirk_level_indicator_defaults
// in tests/appkit-small-controls-aqua.m
- (NSSize) cellSize {
    if (_style == NSContinuousCapacityLevelIndicatorStyle || _style == NSDiscreteCapacityLevelIndicatorStyle)
        return NSMakeSize(40000, 18);
    if (_style == NSRelevancyLevelIndicatorStyle)
        return NSMakeSize(40000, 12);
    if (_style == NSRatingLevelIndicatorStyle) {
        NSSize unit = [self _ratingUnitSize];

        return NSMakeSize(unit.width * [self _ratingUnits], unit.height);
    }
    return [super cellSize];
}

// QUIRK: a relevancy indicator is a 12 point high strip centred in the cell, black at 10% (alpha 26/255), with
// the part up to round(width * fraction) drawn in columns of alternating strength, black at 55% (140/255) on the
// even columns counted from the left edge of the cell and 33% (83/255) on the odd ones. It looks the same in
// every control size and when disabled. Evidence: black-box renders of NSLevelIndicator on macOS 10.14.4 and
// 26.7.3 at 1x (tier 2). Test: test_quirk_relevancy_style in tests/appkit-level-indicator-styles.m
- (void) _drawRelevancyInFrame: (NSRect) frame fraction: (double) fraction flipped: (BOOL) flipped {
    CGFloat top = floor((NSHeight(frame) - 12) / 2);
    CGFloat y = flipped ? NSMinY(frame) + top : NSMaxY(frame) - top - 12;
    NSRect strip = NSMakeRect(NSMinX(frame), y, NSWidth(frame), 12);
    int filled = (int) floor(NSWidth(frame) * fraction + 0.5);

    // the stripes replace the strip, they are not drawn over it
    [[NSColor colorWithCalibratedWhite: 0 alpha: 26 / 255.0] setFill];
    NSRectFillUsingOperation(NSMakeRect(NSMinX(strip) + filled, y, NSWidth(strip) - filled, 12), NSCompositeSourceOver);
    for (int x = 0; x < filled; x++) {
        [[NSColor colorWithCalibratedWhite: 0 alpha: (x % 2 == 0 ? 140 : 83) / 255.0] setFill];
        NSRectFillUsingOperation(NSMakeRect(NSMinX(frame) + x, y, 1, 12), NSCompositeSourceOver);
    }
}

// QUIRK: the stars of a rating indicator are regular five-pointed stars in a 12 point square, vertically centred
// in the cell: centre (6, 6.93) from the square's top left corner, tips 6.17 from the centre, inner points
// 2.41 from it, black at 50% (127/255) when filled and 10% (25/255) when not. Units up to round(value - minimum)
// are filled. They look the same when disabled, editable or in another control size. Evidence: black-box renders
// of NSLevelIndicator on macOS 10.14.4 and 26.7.3 at 1x (tier 2), shape fitted to the coverage. A rating image
// and a placeholder image replace the filled and the empty stars when set (documented API).
// Test: test_quirk_rating_style in tests/appkit-level-indicator-styles.m
- (void) _drawRatingInFrame: (NSRect) frame flipped: (BOOL) flipped {
    NSSize unit = [self _ratingUnitSize];
    int units = [self _ratingUnits];
    int filled = (int) floor([self doubleValue] - _minValue + 0.5);
    CGFloat top = floor((NSHeight(frame) - unit.height) / 2);
    CGFloat y = flipped ? NSMinY(frame) + top : NSMaxY(frame) - top - unit.height;

    for (int i = 0; i < units; i++) {
        NSRect box = NSMakeRect(NSMinX(frame) + i * unit.width, y, unit.width, unit.height);
        NSImage *image = i < filled ? [self ratingImage] : [self ratingPlaceholderImage];

        if ([self ratingImage] != nil) {
            if (image != nil)
                [image drawInRect: box fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1
                   respectFlipped: YES hints: nil];
            continue;
        }
        NSBezierPath *star = [NSBezierPath bezierPath];

        for (int k = 0; k < 10; k++) {
            double angle = (-90 + 36 * k) * M_PI / 180, radius = k % 2 == 0 ? 6.17 : 2.41;
            CGFloat px = 6 + radius * cos(angle), py = 6.93 + radius * sin(angle);
            NSPoint point = NSMakePoint(NSMinX(box) + px, flipped ? NSMinY(box) + py : NSMaxY(box) - py);

            if (k == 0)
                [star moveToPoint: point];
            else
                [star lineToPoint: point];
        }
        [star closePath];
        [[NSColor colorWithCalibratedWhite: 0 alpha: (i < filled ? 127 : 25) / 255.0] setFill];
        [star fill];
    }
}

// QUIRK: a capacity indicator is a 16 point high bar along the top of the cell (each segment of a discrete one is
// a separate rounded rectangle, one per unit of the range), filled to the value; tick marks are below it, 2 points
// apart from it, at floor(i * (width - 1) / (count - 1)), major ones evenly among them. Not documented. Evidence:
// black-box renders of NSLevelIndicator on macOS 10.14.4 at 1x (tier 2), which also show that a disabled
// indicator looks the same. Tick marks above the bar were not observed and mirror this layout.
// Test: test_quirk_level_indicator in tests/appkit-small-controls-aqua.m
- (void) drawWithFrame: (NSRect) frame inView: (NSView *) controlView {
    NSGraphicsStyle *style = [controlView graphicsStyle];
    BOOL flipped = [controlView isFlipped];
    BOOL ticksAbove = _numberOfTickMarks > 0 && _tickMarkPosition == NSTickMarkAbove;
    double range = _maxValue - _minValue;
    double fraction = range > 0 ? ([self doubleValue] - _minValue) / range : 0;
    CGFloat barTop = ticksAbove ? NSHeight(frame) - 16 : 0;
    // rectangles from the top of the cell on the screen
#define FROM_TOP(x, y, w, h) NSMakeRect(NSMinX(frame) + (x), flipped ? NSMinY(frame) + (y) : NSMaxY(frame) - (y) - (h), (w), (h))
    NSRect bar = FROM_TOP(0, barTop, NSWidth(frame), 16);

    fraction = MAX(0, MIN(1, fraction));
    if (_style == NSContinuousCapacityLevelIndicatorStyle) {
        NSRect fill = bar;

        [style drawLevelIndicatorTrackInRect: bar];
        fill.size.width = round(NSWidth(bar) * fraction);
        if (NSWidth(fill) > 0)
            [style drawLevelIndicatorFillInRect: bar clipRect: fill color: [self _fillColor]];
    } else if (_style == NSDiscreteCapacityLevelIndicatorStyle) {
        int segments = (int) round(range);
        int filled = (int) round(fraction * segments);
        NSColor *color = [self _fillColor];

        for (int i = 0; i < segments; i++) {
            CGFloat x0 = floor(i * NSWidth(frame) / segments), x1 = floor((i + 1) * NSWidth(frame) / segments);
            NSRect segment = FROM_TOP(x0, barTop, x1 - x0, 16);

            if (i < filled)
                [style drawLevelIndicatorFillInRect: segment clipRect: segment color: color];
            else
                [style drawLevelIndicatorTrackInRect: segment];
        }
    } else if (_style == NSRelevancyLevelIndicatorStyle) {
        [self _drawRelevancyInFrame: frame fraction: fraction flipped: flipped];
        return;
    } else {
        [self _drawRatingInFrame: frame flipped: flipped];
        return;
    }

    for (int i = 0; i < _numberOfTickMarks; i++) {
        BOOL major = NO;
        CGFloat x = _numberOfTickMarks > 1 ? floor(i * (NSWidth(frame) - 1) / (_numberOfTickMarks - 1)) : floor(NSWidth(frame) / 2);

        if (_numberOfMajorTickMarks > 1 && _numberOfTickMarks > 1)
            major = (i * (_numberOfMajorTickMarks - 1)) % (_numberOfTickMarks - 1) == 0;
        else if (_numberOfMajorTickMarks == 1)
            major = i == _numberOfTickMarks / 2;
        CGFloat length = major ? 6 : 3;
        CGFloat y = ticksAbove ? (major ? 0 : 1) : 16 + 2 + (major ? 0 : 1);

        [style drawLevelIndicatorTickInRect: FROM_TOP(x, y, 1, length) major: major];
    }
#undef FROM_TOP
}

@end
