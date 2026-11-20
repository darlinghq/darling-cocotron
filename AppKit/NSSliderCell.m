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
#import "NSCoder+AppKit.h"
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>


@interface NSColorScaleSliderCell : NSSliderCell
@end

@implementation NSSliderCell

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    // The class version is asked before the superclass part is decoded.
    NSInteger version = [coder allowsKeyedCoding] ? 0 : [coder versionForClassName: @"NSSliderCell"];

    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        _type = [keyed decodeIntForKey: @"NSSliderType"];
        _minValue = [keyed decodeDoubleForKey: @"NSMinValue"];
        _maxValue = [keyed decodeDoubleForKey: @"NSMaxValue"];
        if ([keyed containsValueForKey: @"NSValue"]) {
            // This cell prefers NSValue to NSContents
            [NS_EXTRA(NSCell, self)->_objectValue release];
            NS_EXTRA(NSCell, self)->_objectValue = [[keyed decodeObjectForKey: @"NSValue"] retain];
        }
        _numberOfTickMarks = [keyed decodeIntForKey: @"NSNumberOfTickMarks"];
        _tickMarkPosition = [keyed decodeIntForKey: @"NSTickMarkPosition"];
        _allowsTickMarkValuesOnly =
                [keyed decodeBoolForKey: @"NSAllowsTickMarkValuesOnly"];
    } else {
        double value = 0;
        int numberOfTickMarks = 0, tickMarkPositionWord = 0, flags = 0;
        id unknown1 = nil, unknown2 = nil;
        float unknownFloat1 = 0, unknownFloat2 = 0;

        _altIncrementValue = 0;
        _numberOfTickMarks = 0;
        _tickMarkPosition = NSTickMarkBelow;
        _allowsTickMarkValuesOnly = NO;

        // Layouts per class version as recorded from Mac archives. Floats, objects and
        // the colours of the older layouts are read and dropped (their meaning is not
        // known). Maximum comes before minimum in every layout.
        if (version >= 226) {
            [coder decodeValuesOfObjCTypes: "ddddiii", &_maxValue, &_minValue, &value, &_altIncrementValue,
                                            &numberOfTickMarks, &tickMarkPositionWord, &flags];
        } else if (version >= 42) {
            [coder decodeValuesOfObjCTypes: "dddfd@@iii", &_maxValue, &_minValue, &value, &unknownFloat1,
                                            &_altIncrementValue, &unknown1, &unknown2, &numberOfTickMarks,
                                            &tickMarkPositionWord, &flags];
        } else if (version == 41) {
            [coder decodeValuesOfObjCTypes: "dddfd@@", &_maxValue, &_minValue, &value, &unknownFloat1,
                                            &_altIncrementValue, &unknown1, &unknown2];
        } else if (version >= 17) {
            [coder decodeValuesOfObjCTypes: "dddfd", &_maxValue, &_minValue, &value, &unknownFloat1, &_altIncrementValue];
            unknown1 = [[coder decodeObject] retain];
            unknown2 = [[coder decodeObject] retain];
        } else if (version >= 6) {
            [coder decodeValuesOfObjCTypes: "dddf@d@", &_maxValue, &_minValue, &value, &unknownFloat1, &unknown1,
                                            &_altIncrementValue, &unknown2];
        } else if (version == 5) {
            [coder decodeValuesOfObjCTypes: "dddf@fd", &_maxValue, &_minValue, &value, &unknownFloat1, &unknown1,
                                            &unknownFloat2, &_altIncrementValue];
            [coder decodeNXColor];
        } else if (version >= 3) {
            [coder decodeValuesOfObjCTypes: "dddf@f", &_maxValue, &_minValue, &value, &unknownFloat1, &unknown1,
                                            &unknownFloat2];
            [coder decodeNXColor];
        } else if (version == 2) {
            [coder decodeValuesOfObjCTypes: "dddf@", &_maxValue, &_minValue, &value, &unknownFloat1, &unknown1];
        } else {
            [coder decodeValuesOfObjCTypes: "ddd", &_maxValue, &_minValue, &value];
            [self setTitle: @""];
        }
        [unknown1 release];
        [unknown2 release];

        if (version >= 42) {
            _numberOfTickMarks = numberOfTickMarks;
            // The second word is the position of the marks (1 above or right).
            _tickMarkPosition = tickMarkPositionWord;
            if (version >= 226 && (flags & 0x20000001) == 0x20000001) {
                // A circular slider archives bit 0 and bit 29 of the flag word; its
                // snapping to marks is the top bit.
                _type = NSCircularSlider;
                _allowsTickMarkValuesOnly = (flags & 0x80000000) != 0;
            } else {
                _allowsTickMarkValuesOnly = (flags & 1) != 0;
            }
        }

        [self setDoubleValue: value];
    }

    return self;
}

static void initSliderCellState(NSSliderCell *self) {
    NS_EXTRA(NSCell, self)->_isContinuous = YES; // NSCell defaults to NO, NSSliderCell defaults to YES
    self->_type = NSLinearSlider;
    self->_minValue = 0;
    self->_maxValue = 1.0;
    self->_altIncrementValue = 0;
    self->_isVertical = -1;
    self->_lastRect = NSZeroRect;
    self->_numberOfTickMarks = 0;
    self->_tickMarkPosition = NSTickMarkBelow;
    self->_allowsTickMarkValuesOnly = NO;
}

// Like -[NSCell init], this does not go through -initImageCell: or -initTextCell:.
- init {
    [super init];
    initSliderCellState(self);
    return self;
}

- initTextCell: (NSString *) string {
    [super initTextCell: string];
    initSliderCellState(self);
    return self;
}

- initImageCell: (NSImage *) image {
    [super initImageCell: image];
    initSliderCellState(self);
    return self;
}

+ (BOOL) prefersTrackingUntilMouseUp {
    return YES;
}

- (NSSliderType) sliderType {
    return _type;
}

- (double) minValue {
    return _minValue;
}

- (double) maxValue {
    return _maxValue;
}

- (double) altIncrementValue {
    return _altIncrementValue;
}

- (NSInteger) numberOfTickMarks {
    return _numberOfTickMarks;
}

- (NSTickMarkPosition) tickMarkPosition {
    return _tickMarkPosition;
}

- (BOOL) allowsTickMarkValuesOnly {
    return _allowsTickMarkValuesOnly;
}

// QUIRK: 21, 15 and 12 points for the regular, small and mini control sizes; with tick marks 19, 13 and 11 for a
// horizontal slider and 20, 14 and 12 for a vertical one. Not documented. Evidence: black-box observation on
// macOS 10.14.4 (tier 2). Test: test_quirk_slider_cell_size in tests/appkit-small-controls-aqua.m
- (CGFloat) knobThickness {
    int z = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);

    if (_numberOfTickMarks <= 0)
        return (CGFloat[]){21, 15, 12}[z];
    if ([self isVertical] == 1)
        return (CGFloat[]){20, 14, 12}[z];
    return (CGFloat[]){19, 13, 11}[z];
}

- (void) setSliderType: (NSSliderType) value {
    _type = value;
}

- (void) setMinValue: (double) minValue {
    _minValue = minValue;
}

- (void) setMaxValue: (double) maxValue {
    _maxValue = maxValue;
}

- (void) setAltIncrementValue: (double) value {
    _altIncrementValue = value;
}

- (void) setNumberOfTickMarks: (NSInteger) number {
    _numberOfTickMarks = number;
}

- (void) setTickMarkPosition: (NSTickMarkPosition) position {
    _tickMarkPosition = position;
}

- (void) setAllowsTickMarkValuesOnly: (BOOL) valuesOnly {
    _allowsTickMarkValuesOnly = valuesOnly;
}

- (void) setKnobThickness: (CGFloat) thickness {
    // deprecated, do nothing
}

// _isVertical is -1 until the orientation is known, then 0 or 1: taken from the frame the cell
// draws in, or with kVerticalSet added when it was set explicitly, which the frame does not change.
enum { kVerticalSet = 2 };

- (NSInteger) isVertical {
    return _isVertical < 0 ? _isVertical : (_isVertical & 1);
}

- (void) setVertical: (BOOL) vertical {
    _isVertical = kVerticalSet | (vertical ? 1 : 0);
}

// Takes the orientation from a frame unless it is already known; drawing updates it from the
// frame the cell draws in, as before.
- (void) _setOrientationFromFrame: (NSRect) frame {
    if (_isVertical < 0)
        _isVertical = (frame.size.height > frame.size.width) ? 1 : 0;
}

// Follows the slider's frame unless the orientation was set with -setVertical:.
- (void) _setVerticalForSize: (NSSize) size {
    if (_isVertical >= 0 && (_isVertical & kVerticalSet))
        return;
    _isVertical = size.height > size.width ? 1 : 0;
}

- (NSInteger) indexOfTickMarkAtPoint: (NSPoint) point {
    int i;

    for (i = 0; i < _numberOfTickMarks; i++) {
        NSRect check = [self rectOfTickMarkAtIndex: i];

        check = NSInsetRect(check, -1, -1);

        if (NSPointInRect(point, check))
            return i;
    }

    return NSNotFound;
}

- (double) tickMarkValueAtIndex: (NSInteger) index {
    double scale =
            (_numberOfTickMarks == 1)
                    ? 0.5
                    : (((double) index) / ((double) (_numberOfTickMarks - 1)));

    return _minValue + (_maxValue - _minValue) * scale;
}

- (double) closestTickMarkValueToValue: (double) value {
    if (_numberOfTickMarks < 1) {
        return value;
    }
    double closestValue = [self tickMarkValueAtIndex: 0];
    NSInteger i;

    for (i = 1; i < _numberOfTickMarks; i++) {
        double check = [self tickMarkValueAtIndex: i];

        if (ABS(value - check) < ABS(value - closestValue))
            closestValue = check;
    }

    return closestValue;
}

- (NSRect) trackRect {
    return _lastRect;
}

// QUIRK: the geometry of a linear slider on macOS 10.14 (light appearance). Not documented. Evidence: black-box
// renders of NSSlider on macOS 10.14.4 at 1x (tier 2), vd-upstream/mac-probes/aqua-small-controls.m, at the
// thickness of -cellSize (19, 15 and 13 points without tick marks, 24, 18 and 15 with them), for the regular, small
// and mini control sizes:
// - the knob's centre is at floor(k / 2 + f * (length - k)) points from the minimum end, with f the value's fraction
//   of the range and k 21, 13 and 11, with or without tick marks; tick marks are at the same positions;
// - the round knob is 15, 11 and 9 points across, the pointed one as wide and 17, 12 and 9 points long;
// - the track ends 3, 1 and 1 points from the ends of the view;
// - across the slider the knob, the track and the tick marks are at the offsets of the table below, and in a
//   thicker or thinner view they move by half the difference, rounded down for a horizontal slider and up for a
//   vertical one.
// Test: test_quirk_slider_geometry in tests/appkit-small-controls-aqua.m
typedef struct {
    CGFloat k;          // knob length used for positions
    CGFloat d;          // knob width along the track
    CGFloat knobLength; // knob extent across the track
    CGFloat inset;      // track inset from the ends
    CGFloat thickness;  // the thickness these offsets were measured at
    CGFloat knobTop, trackTop, tickTop, tickLength; // offsets across, from the top (left for vertical sliders)
} NSAquaSliderGeometry;

- (NSAquaSliderGeometry) _aquaGeometry {
    // index: control size; [vertical][0 no ticks, 1 ticks at bottom or right, 2 ticks at top or left]
    static const CGFloat knobTop[2][3][3] = {{{2, 2, 1}, {2, 2, 2}, {5, 4, 4}}, {{2, 2, 3}, {2, 2, 2}, {5, 4, 4}}};
    static const CGFloat trackTop[2][3][3] = {{{8, 6, 4}, {8, 5, 4}, {14, 10, 7}}, {{8, 6, 6}, {7, 5, 5}, {14, 10, 8}}};
    static const CGFloat tickTop[2][3][3] = {{{0, 0, 0}, {18, 13, 10}, {3, 3, 3}}, {{0, 0, 0}, {17, 12, 9}, {2, 2, 2}}};
    int z = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);
    int v = [self isVertical] == 1;
    int t = _numberOfTickMarks <= 0 ? 0 : (_tickMarkPosition == NSTickMarkBelow ? 1 : 2);
    NSAquaSliderGeometry g;

    g.k = (CGFloat[]){21, 13, 11}[z];
    g.d = (CGFloat[]){15, 11, 9}[z];
    g.knobLength = t ? (CGFloat[]){17, 12, 9}[z] : g.d;
    g.inset = z == 0 ? 3 : 1;
    g.thickness = t ? (CGFloat[]){24, 18, 15}[z] : (CGFloat[]){19, 15, 13}[z];
    g.knobTop = knobTop[v][t][z];
    g.trackTop = trackTop[v][t][z];
    g.tickTop = tickTop[v][t][z];
    g.tickLength = z == 0 ? 4 : 3;
    return g;
}

- (BOOL) _drawsFlipped {
    return _controlView == nil ? NO : [_controlView isFlipped];
}

// A rectangle in the cell frame given from its top left corner on the screen for a horizontal slider; for a
// vertical one x is across the slider (from the left) and y along it (from the top).
- (NSRect) _aquaRectAcross: (CGFloat) across along: (CGFloat) along thickness: (CGFloat) thickness length: (CGFloat) length {
    NSRect frame = _lastRect;
    BOOL vertical = [self isVertical] == 1;
    NSAquaSliderGeometry g = [self _aquaGeometry];
    CGFloat crossSize = vertical ? NSWidth(frame) : NSHeight(frame);
    CGFloat x, y, w, h;

    // centred across, odd leftovers going above a horizontal slider and left of a vertical one
    across += vertical ? ceil((crossSize - g.thickness) / 2) : floor((crossSize - g.thickness) / 2);
    if (vertical) {
        x = across;
        y = along;
        w = thickness;
        h = length;
    } else {
        x = along;
        y = across;
        w = length;
        h = thickness;
    }
    if ([self _drawsFlipped])
        return NSMakeRect(NSMinX(frame) + x, NSMinY(frame) + y, w, h);
    return NSMakeRect(NSMinX(frame) + x, NSMaxY(frame) - y - h, w, h);
}

- (CGFloat) _aquaLength {
    return [self isVertical] == 1 ? NSHeight(_lastRect) : NSWidth(_lastRect);
}

// The position of a point along the slider, in points from its top (vertical) or left end, for a value fraction
// or a tick mark position.
- (CGFloat) _aquaPositionForFraction: (double) fraction {
    NSAquaSliderGeometry g = [self _aquaGeometry];
    CGFloat length = [self _aquaLength];
    CGFloat p = floor(g.k / 2 + fraction * (length - g.k));

    // the minimum of a vertical slider is at the bottom
    return [self isVertical] == 1 ? length - 1 - p : p;
}

- (double) _valueFraction {
    double range = _maxValue - _minValue;
    double fraction = (range > 0) ? ([self doubleValue] - _minValue) / range : 0;

    return MAX(0, MIN(1, fraction));
}

- (double) _tickMarkFractionAtIndex: (NSInteger) index {
    return (_numberOfTickMarks == 1) ? 0.5 : (double) index / (double) (_numberOfTickMarks - 1);
}

- (NSRect) rectOfTickMarkAtIndex: (NSInteger) index {
    NSAquaSliderGeometry g = [self _aquaGeometry];

    if (index < 0 || index >= _numberOfTickMarks)
        return NSZeroRect;
    return [self _aquaRectAcross: g.tickTop
                           along: [self _aquaPositionForFraction: [self _tickMarkFractionAtIndex: index]]
                       thickness: g.tickLength
                          length: 1];
}

- (NSRect) _knobBodyRect {
    NSAquaSliderGeometry g = [self _aquaGeometry];
    CGFloat centre = [self _aquaPositionForFraction: [self _valueFraction]];

    return [self _aquaRectAcross: g.knobTop along: centre - (g.d - 1) / 2 thickness: g.knobLength length: g.d];
}

- (NSRect) _trackRect {
    NSAquaSliderGeometry g = [self _aquaGeometry];

    return [self _aquaRectAcross: g.trackTop along: g.inset thickness: 3 length: [self _aquaLength] - 2 * g.inset];
}

- (void) drawBarInside: (NSRect) frame flipped: (BOOL) isFlipped {
    NSRect track = [self _trackRect];
    NSRect fill = NSZeroRect;

    if (_numberOfTickMarks <= 0 && [self sliderType] == NSSliderTypeLinear) {
        // the blue part runs from the minimum to the middle of the knob
        NSRect body = [self _knobBodyRect];

        fill = track;
        if ([self isVertical] == 1) {
            BOOL minAtLowY = !isFlipped;
            if (minAtLowY)
                fill.size.height = MAX(0, NSMidY(body) - NSMinY(track));
            else {
                fill.origin.y = MIN(NSMaxY(track), NSMidY(body));
                fill.size.height = NSMaxY(track) - fill.origin.y;
            }
        } else
            fill.size.width = MAX(0, NSMidX(body) - NSMinX(track));
    }
    [[_controlView graphicsStyle] drawAquaSliderTrackInRect: track
                                                   fillRect: fill
                                                    enabled: [self isEnabled]
                                                     active: [[_controlView window] isKeyWindow]];
}

// QUIRK: the knob rectangle is -knobThickness long along the slider and, across it, as thick as the knob without
// tick marks (21, 15 or 12 points), 22, 17 or 12 points with tick marks below and 24, 17 or 12 above a horizontal
// slider, and 23, 17 or 11 points with tick marks on a vertical slider. Not documented. Evidence: black-box
// observation on macOS 10.14.4 (tier 2). There the rectangle of a slider without tick marks is centred on the
// drawn knob (rounded up); with tick marks it is offset from it, which is not replicated: here it is centred too.
// Test: test_quirk_slider_knob_rect in tests/appkit-small-controls-aqua.m
- (NSRect) knobRectFlipped: (BOOL) flipped {
    int z = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);
    BOOL vertical = [self isVertical] == 1;
    NSRect body = [self _knobBodyRect];
    CGFloat along = [self knobThickness], across;

    if (_numberOfTickMarks <= 0)
        across = along;
    else if (vertical)
        across = (CGFloat[]){23, 17, 11}[z];
    else
        across = _tickMarkPosition == NSTickMarkBelow ? (CGFloat[]){22, 17, 12}[z] : (CGFloat[]){24, 17, 12}[z];
    if (vertical)
        return NSMakeRect(floor(NSMidX(body) - across / 2 + 0.5), floor(NSMidY(body) - along / 2 + 0.5), across, along);
    return NSMakeRect(floor(NSMidX(body) - along / 2 + 0.5), floor(NSMidY(body) - across / 2 + 0.5), along, across);
}

// QUIRK: the bar rectangle of a linear slider is the track grown across the slider: 5 points thick (4 at the mini
// size), starting 3 points (1 for small and mini) from the minimum end and ending as far from the maximum end.
// Across the slider it starts at floor((thickness of the view - c) / 2) from the bottom of the view when `flipped`
// is NO and from its top when it is YES, with c from the table below, which depends on the control size, on
// whether and where the tick marks are, and (for a horizontal slider only) on `flipped`. It is computed for the
// view's bounds whether or not the slider has been drawn. Not documented. Evidence: black-box observation on
// macOS 10.14.4 (tier 2) of -barRectFlipped: for view thicknesses 10 to 40 points, all control sizes, tick mark
// positions and both values of the argument (vd-upstream/mac-probes/aqua-leftovers-bar.m); circular sliders
// are not covered. Test: test_quirk_slider_bar_rect in tests/appkit-slider-bar-rect.m
- (NSRect) barRectFlipped: (BOOL) flipped {
    // c by [vertical][ticks: none, below or right, above or left][control size][flipped: NO, YES]
    static const int offsets[2][3][3][2] = {
        {{{5, 5}, {5, 5}, {5, 5}}, {{0, 10}, {0, 10}, {1, 7}}, {{12, -2}, {10, 0}, {7, 1}}},
        {{{4, 4}, {4, 4}, {2, 2}}, {{11, 11}, {9, 9}, {6, 6}}, {{-3, -3}, {-1, -1}, {0, 0}}}};
    NSRect frame = NSIsEmptyRect(_lastRect) && _controlView != nil ? [_controlView bounds] : _lastRect;
    int z = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);
    int v = [self isVertical] == 1;
    int t = _numberOfTickMarks <= 0 ? 0 : (_tickMarkPosition == NSTickMarkBelow ? 1 : 2);
    CGFloat inset = z == 0 ? 3 : 1, thickness = z == 2 ? 4 : 5;
    CGFloat crossSize = v ? NSWidth(frame) : NSHeight(frame);
    CGFloat across = floor((crossSize - offsets[v][t][z][flipped ? 1 : 0]) / 2);
    CGFloat length = (v ? NSHeight(frame) : NSWidth(frame)) - 2 * inset;

    if (v)
        return NSMakeRect(NSMinX(frame) + across, NSMinY(frame) + inset, thickness, length);
    return NSMakeRect(NSMinX(frame) + inset, NSMinY(frame) + across, length, thickness);
}

- (void) drawKnob {
    [self drawKnob: [self knobRectFlipped: [[self controlView] isFlipped]]];
}

- (void) drawKnob: (NSRect) rect {
    // the knob is drawn where -knobRectFlipped: puts it, moved along with the given rectangle
    NSRect own = [self knobRectFlipped: [_controlView isFlipped]];
    NSRect body = NSOffsetRect([self _knobBodyRect], NSMinX(rect) - NSMinX(own), NSMinY(rect) - NSMinY(own));
    NSInteger pointing = -1;

    if (_numberOfTickMarks > 0) {
        if ([self isVertical] == 1)
            pointing = _tickMarkPosition == NSTickMarkRight ? NSMaxXEdge : NSMinXEdge;
        else
            pointing = _tickMarkPosition == NSTickMarkBelow ? NSMinYEdge : NSMaxYEdge;
    }
    [[_controlView graphicsStyle] drawAquaSliderKnobInRect: body
                                                  pointing: pointing
                                                   enabled: [self isEnabled]
                                                   flipped: [self _drawsFlipped]];
}

- (void) drawTickMarks {
    NSGraphicsStyle *style = [_controlView graphicsStyle];
    NSInteger i;

    for (i = 0; i < _numberOfTickMarks; i++)
        [style drawAquaSliderTickInRect: [self rectOfTickMarkAtIndex: i]];
}

- (void) drawLinearSliderWithFrame: (NSRect) frame
                            inView: (NSView *) controlView
{
    if (!(_isVertical >= 0 && (_isVertical & kVerticalSet)))
        _isVertical = (frame.size.height > frame.size.width) ? 1 : 0;

    [self drawBarInside: frame flipped: [controlView isFlipped]];
    [self drawTickMarks];
    [self drawKnob];
}

// QUIRK: a circular slider is a disc 22 points across (16 for the small size; the mini size draws the regular one),
// centred in the view (rounded down), with a dark dot 6 points across whose centre is 4 points inside the edge of
// the disc, clockwise from the top as the value grows; tick marks are not drawn. Not documented. Evidence:
// black-box renders on macOS 10.14.4 at 1x (tier 2). Test: test_quirk_circular_slider in
// tests/appkit-small-controls-aqua.m
- (void) drawCircularSliderWithFrame: (NSRect) frame
                              inView: (NSView *) controlView
{
    CGFloat d = [self controlSize] == NSSmallControlSize ? 16 : 22;
    BOOL flipped = [self _drawsFlipped];
    CGFloat left = floor((NSWidth(frame) - d) / 2), top = floor((NSHeight(frame) - d) / 2);
    NSRect disc = NSMakeRect(NSMinX(frame) + left, flipped ? NSMinY(frame) + top : NSMaxY(frame) - top - d, d, d);
    double angle = [self _valueFraction] * 2 * M_PI;
    CGFloat distance = d / 2 - 4;
    // clockwise from the top on the screen
    CGFloat dx = sin(angle) * distance, dyDown = -cos(angle) * distance;
    NSPoint centre = NSMakePoint(NSMidX(disc) + dx, NSMidY(disc) + (flipped ? dyDown : -dyDown));
    NSRect knob = NSMakeRect(centre.x - 3, centre.y - 3, 6, 6);

    [[controlView graphicsStyle] drawAquaCircularSliderInRect: disc knobRect: knob enabled: [self isEnabled] flipped: flipped];
}

// QUIRK: -cellSize is 40000 points along a linear slider and 19, 15 or 13 points across it (24, 18 or 15 with tick
// marks); a circular slider's is 28 x 30 points (18 x 20 for the small size). Not documented. Evidence:
// black-box observation on macOS 10.14.4 (tier 2). Test: test_quirk_slider_cell_size in
// tests/appkit-small-controls-aqua.m
- (NSSize) cellSize {
    if ([self sliderType] == NSCircularSlider)
        return [self controlSize] == NSSmallControlSize ? NSMakeSize(18, 20) : NSMakeSize(28, 30);
    CGFloat thickness = [self _aquaGeometry].thickness;

    return [self isVertical] == 1 ? NSMakeSize(thickness, 40000) : NSMakeSize(40000, thickness);
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) controlView {
    _controlView = controlView;
    _lastRect = frame;

    switch ([self sliderType]) {
    case NSLinearSlider:
        [self drawLinearSliderWithFrame: frame inView: controlView];
        break;
    case NSCircularSlider:
        [self drawCircularSliderWithFrame: frame inView: controlView];
        break;
    }

}

// the ring is drawn around the knob
- (NSBezierPath *) _focusRingPathWithFrame: (NSRect) frame inView: (NSView *) controlView {
    return [NSBezierPath bezierPathWithOvalInRect: [self knobRectFlipped: [controlView isFlipped]]];
}

- (void) setClosestDoubleValue: (double) value {
    if ([self allowsTickMarkValuesOnly])
        value = [self closestTickMarkValueToValue: value];

    [self setDoubleValue: value];
}

// just a guess, but we'll try moving it 10% of its total range of values...
- (void) _incrementByPercentageAndConstrain: (CGFloat) percentage
                                  decrement: (BOOL) decrement
{
    double originalValue = [self doubleValue];

    if (decrement)
        originalValue -= (_maxValue - _minValue) * percentage;
    else
        originalValue += (_maxValue - _minValue) * percentage;

    if (originalValue > _maxValue)
        originalValue = _maxValue;
    else if (originalValue < _minValue)
        originalValue = _minValue;

    [self setClosestDoubleValue: originalValue];
}

- (void) moveUp: (id) sender {
    if ([self isVertical])
        [self _incrementByPercentageAndConstrain: 0.10 decrement: NO];
}

- (void) moveDown: (id) sender {
    if ([self isVertical])
        [self _incrementByPercentageAndConstrain: 0.10 decrement: YES];
}

- (void) moveLeft: (id) sender {
    if ([self isVertical] == NO)
        [self _incrementByPercentageAndConstrain: 0.10 decrement: YES];
}

- (void) moveRight: (id) sender {
    if ([self isVertical] == NO)
        [self _incrementByPercentageAndConstrain: 0.10 decrement: NO];
}

// linear sliderCell behavior:
// 	1. test hit in knob.. if so, go on to 3
//	2. test hit in bar. if hit, move knob to click location
//	3. track knob.
- (void) _setLinearDoubleValueFromPoint: (NSPoint) point {
    // the inverse of -_aquaPositionForFraction:, so that the knob follows the mouse
    NSAquaSliderGeometry g = [self _aquaGeometry];
    CGFloat length = [self _aquaLength] - g.k;
    CGFloat position;

    if ([self isVertical] == 1) {
        // from the bottom on the screen
        position = [_controlView isFlipped] ? NSMaxY(_lastRect) - point.y : point.y - NSMinY(_lastRect);
    } else
        position = point.x - NSMinX(_lastRect);

    double percentPixels = length > 0 ? (position - g.k / 2) / length : 0;

    if (percentPixels > 1.0)
        percentPixels = 1.0;
    if (percentPixels < 0.0)
        percentPixels = 0.0;

    double range = _maxValue - _minValue;
    [self setClosestDoubleValue: (range > 0) ? (percentPixels * range) + _minValue : _minValue];
}

// circular sliderCell behavior:
// 	1. set value based on angle of click
//	2. track mouse to continue calc'ing angles.
- (void) _setCircularDoubleValueFromPoint: (NSPoint) point
                                  flipped: (BOOL) flipped
{
    NSPoint center = NSMakePoint(NSMidX(_lastRect), NSMidY(_lastRect));

    if (flipped == NO) {
        point.y = center.y - (point.y - center.y);
    }
    // Get the angle and ensure it's in 0..2*PI - 0˙ is top center
    double angle = fmod(atan2(center.y - point.y, center.x - point.x) - M_PI_2 +
                                M_PI * 2.f,
                        M_PI * 2.f);

    // Convert to degrees
    angle *= 180.f / M_PI;

    double percentAngle = angle / 360.f;

    double value = (percentAngle * (_maxValue - _minValue)) + _minValue;

    [self setDoubleValue: value];
}

- (BOOL) startTrackingLinearSliderAt: (NSPoint) startPoint
                              inView: (NSView *) controlView
{
    NSPoint localPoint = [controlView convertPoint: startPoint fromView: nil];

    if (NSMouseInRect(localPoint,
                      [self knobRectFlipped: [controlView isFlipped]],
                      [controlView isFlipped])) {
        [self highlight: YES withFrame: _lastRect inView: controlView];
    }

    [self _setLinearDoubleValueFromPoint: localPoint];
    return YES;
}

- (BOOL) startTrackingCircularSliderAt: (NSPoint) startPoint
                                inView: (NSView *) controlView
{
    NSPoint localPoint = [controlView convertPoint: startPoint fromView: nil];

    [self _setCircularDoubleValueFromPoint: localPoint
                                   flipped: [controlView isFlipped]];
    return YES;
}

- (BOOL) startTrackingAt: (NSPoint) startPoint inView: (NSView *) controlView {
    switch ([self sliderType]) {
    case NSLinearSlider:
        return [self startTrackingLinearSliderAt: startPoint
                                          inView: controlView];
        break;
    case NSCircularSlider:
        return [self startTrackingCircularSliderAt: startPoint
                                            inView: controlView];
        break;
    }
    return YES; // what happened here?
}

- (BOOL) continueTrackingLinearSliderAtPoint: (NSPoint) lastPoint
                                          at: (NSPoint) currentPoint
                                      inView: (NSView *) controlView
{
    NSPoint localPoint = [controlView convertPoint: currentPoint fromView: nil];
    [self _setLinearDoubleValueFromPoint: localPoint];
    [controlView setNeedsDisplayInRect: _lastRect];

    return YES;
}

- (BOOL) continueTrackingCircularSliderAtPoint: (NSPoint) lastPoint
                                            at: (NSPoint) currentPoint
                                        inView: (NSView *) controlView
{
    NSPoint localPoint = [controlView convertPoint: currentPoint fromView: nil];
    [self _setCircularDoubleValueFromPoint: localPoint
                                   flipped: [controlView isFlipped]];
    [controlView setNeedsDisplayInRect: _lastRect];
    return YES;
}

- (BOOL) continueTracking: (NSPoint) lastPoint
                       at: (NSPoint) currentPoint
                   inView: (NSView *) controlView
{
    switch ([self sliderType]) {
    case NSLinearSlider:
        return [self continueTrackingLinearSliderAtPoint: lastPoint
                                                      at: currentPoint
                                                  inView: controlView];
        break;
    case NSCircularSlider:
        return [self continueTrackingCircularSliderAtPoint: lastPoint
                                                        at: currentPoint
                                                    inView: controlView];
        break;
    }
    return YES;
}

- (void) stopTracking: (NSPoint) lastPoint
                   at: (NSPoint) stopPoint
               inView: (NSView *) controlView
            mouseIsUp: (BOOL) flag
{
    [self highlight: NO withFrame: _lastRect inView: controlView];
}

@end

@implementation NSColorScaleSliderCell

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
