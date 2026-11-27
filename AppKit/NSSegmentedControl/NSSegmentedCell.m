/* Copyright (c) 2006-2007 Christopher J. W. Lloyd, 2008 Johannes Fortmann

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

#import "../NSImage+TemplateDrawing.h"
#import "NSSegmentItem.h"
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSAppearance.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSSegmentedCell.h>

@interface NSSegmentedCell (Private)
- (void) _recomputeSegmentWidths;
// Behind -[NSSegmentedControl showsMenuIndicatorForSegment:]; the documentation lists them for the control only.
- (BOOL) _showsMenuIndicatorForSegment: (NSInteger) segment;
- (void) _setShowsMenuIndicator: (BOOL) flag forSegment: (NSInteger) segment;
@end

@implementation NSSegmentedCell

static void initSegmentedCellState(NSSegmentedCell *self) {
    self->_segments = [[NSMutableArray arrayWithCapacity: 5] retain];
    self->_selectedSegment = NSNotFound;                    // initially empty
    self->_trackingMode = NSSegmentSwitchTrackingSelectOne; // default
}

// For manually created segment cells. Like -[NSCell init], this does not go through
// -initImageCell: or -initTextCell:.
- (id) init {
    if ((self = [super init]))
        initSegmentedCellState(self);
    return self;
}

- (id) initImageCell: (NSImage *) image {
    if ((self = [super initImageCell: image]))
        initSegmentedCellState(self);
    return self;
}

- (id) initTextCell: (NSString *) str {
    return [self initImageCell: nil];
}

// For nib created segment cells
- (id) initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if (![coder allowsKeyedCoding]) {
        // The segment items, the selected segment (-1 for none), a flag word whose bit 30
        // means momentary and bit 29 select-any tracking, and four unused ints.
        id items = nil;
        int selected, flags, unused[4];

        [coder decodeValuesOfObjCTypes: "@iiiiii", &items, &selected, &flags, &unused[0], &unused[1], &unused[2],
                                        &unused[3]];
        _segments = [items isKindOfClass: [NSArray class]] ? [items mutableCopy] : [[NSMutableArray alloc] init];
        [items release];
        _selectedSegment = selected < 0 ? NSNotFound : selected;
        if ((unsigned) flags & 0x40000000u)
            _trackingMode = NSSegmentSwitchTrackingMomentary;
        else if ((unsigned) flags & 0x20000000u)
            _trackingMode = NSSegmentSwitchTrackingSelectAny;
        else
            _trackingMode = NSSegmentSwitchTrackingSelectOne;

        [self _recomputeSegmentWidths];
        return self;
    }

    _segments = [[coder decodeObjectForKey: @"NSSegmentImages"] retain];
    if (!_segments)
        _segments = [[NSMutableArray arrayWithCapacity: 5] retain];

    if ([coder containsValueForKey: @"NSSelectedSegment"])
        _selectedSegment = [coder decodeIntForKey: @"NSSelectedSegment"];
    else
        _selectedSegment = NSNotFound;

    _trackingMode = [coder decodeIntForKey: @"NSTrackingMode"];

    [self _recomputeSegmentWidths];

    return self;
}

- (void) dealloc {
    [_segments release];
    [_segmentComputedWidths release];
    [super dealloc];
}

- (NSInteger) segmentCount {
    return [_segments count];
}

- (NSSegmentStyle) segmentStyle {
    return _style;
}

- (NSSegmentSwitchTracking) trackingMode {
    return _trackingMode;
}

- (NSInteger) tagForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] tag];
}

- (NSImage *) imageForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] image];
}

- (BOOL) isEnabledForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] isEnabled];
}

- (NSString *) labelForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] label];
}

- (NSMenu *) menuForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] menu];
}

- (BOOL) _showsMenuIndicatorForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] showsMenuIndicator];
}

- (NSString *) toolTipForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] toolTip];
}

- (CGFloat) widthForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] width];
}

- (NSImageScaling) imageScalingForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] imageScaling];
}

- (NSInteger) selectedSegment {

    if (_selectedSegment == NSNotFound) {
        int i, count = [_segments count];

        for (i = 0; i < count; i++)
            if ([[_segments objectAtIndex: i] isSelected])
                return i;
        return -1;
    }

    return _selectedSegment;
}

- (BOOL) isSelectedForSegment: (NSInteger) segment {
    return [[_segments objectAtIndex: segment] isSelected];
}

- (void) setSegmentCount: (NSInteger) count {
    int currentCount = [_segments count];
    if (count == currentCount)
        return;
    if (count > currentCount) {
        while ([_segments count] < count) {
            NSSegmentItem *item = [[[NSSegmentItem alloc] init] autorelease];
            [_segments addObject: item];
        }
    } else {
        while ([_segments count] > count) {
            [_segments removeLastObject];
        }
    }
    [self _recomputeSegmentWidths];
}

- (void) setSegmentStyle: (NSSegmentStyle) value {
    _style = value;
    [self _recomputeSegmentWidths];
}

- (void) setTrackingMode: (NSSegmentSwitchTracking) trackingMode {
    _trackingMode = trackingMode;
}

- (void) setTag: (NSInteger) tag forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setTag: tag];
}

- (void) setImage: (NSImage *) image forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setImage: image];
    [self _recomputeSegmentWidths];
}

- (void) setEnabled: (BOOL) enabled forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setEnabled: enabled];
}

- (void) setLabel: (NSString *) label forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setLabel: label];
    [self _recomputeSegmentWidths];
}

- (void) setMenu: (NSMenu *) menu forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setMenu: menu];
}

- (void) _setShowsMenuIndicator: (BOOL) flag forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setShowsMenuIndicator: flag];
}

- (void) setToolTip: (NSString *) string forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setToolTip: string];
}

- (void) setWidth: (CGFloat) width forSegment: (NSInteger) segment {
    [[_segments objectAtIndex: segment] setWidth: width];
    [self _recomputeSegmentWidths];
}

- (void) setImageScaling: (NSImageScaling) value
              forSegment: (NSInteger) segment
{
    [[_segments objectAtIndex: segment] setImageScaling: value];
}

- (BOOL) selectSegmentWithTag: (NSInteger) tag {
    int i, count = [_segments count];
    for (i = 0; i < count; i++)
        if ([[_segments objectAtIndex: i] tag] == tag) {
            [self setSelectedSegment: i];
            return YES;
        }
    return NO;
}

- (void) setSelected: (BOOL) flag forSegment: (NSInteger) segment {
    [self willChangeValueForKey: @"selectedSegment"];
    _selectedSegment = NSNotFound; // will be recomputed in -selectedSegment
    [[_segments objectAtIndex: segment] setSelected: flag];
    [self didChangeValueForKey: @"selectedSegment"];
}

- (void) setSelectedSegment: (NSInteger) segment {
    // -1 clears selection. Reject other invalid indices before changing either
    // the item flags or the cached selected segment.
    if (segment != -1 && (segment < 0 || (NSUInteger) segment >= [_segments count]))
        [NSException raise: NSRangeException
                    format: @"Segment index %ld is out of bounds", (long) segment];

    for (NSSegmentItem *item in _segments)
        [item setSelected: NO];

    _selectedSegment = segment;
    if (segment != -1)
        [[_segments objectAtIndex: segment] setSelected: YES];
}

- (void) makeNextSegmentKey {
    NSUnimplementedMethod();
}
- (void) makePreviousSegmentKey {
    NSUnimplementedMethod();
}

- (void) setFont: (NSFont *) font {
    [super setFont: font];
    [self _recomputeSegmentWidths];
}

- (NSFont *) _aquaFont {
    NSFont *font = [self font];

    return font != nil ? font : [NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: [self controlSize]]];
}

- (NSButtonCell *) _cellForSegment: (NSInteger) idx {
    NSSegmentItem *segment = [_segments objectAtIndex: idx];
    NSButtonCell *cell = [[NSButtonCell new] autorelease];
    NSString *label = [segment label];
    [cell setTitle: label];
    [cell setControlSize: [self controlSize]];
    [cell setFont: [self _aquaFont]];

    [cell setHighlighted: [segment isSelected]];

    // The control is enabled/disabled as a whole
    [cell setEnabled: [self isEnabled]];

    NSImage *image = [segment image];
    // QUIRK: a selected segment of a textured control that selects any number of segments and shows a template
    // image keeps the bezel of the other segments and shows its image in the accent colour instead. Evidence:
    // black-box renders of a textured rounded control with a template image on macOS 10.14.4 (tier 2): the
    // selected segment's bezel is the same as an unselected one's, its glyph blue. Test:
    // tests/appkit-template-image-tint.m (test_quirk_textured_segment_selected_template). Textured controls are
    // drawn by -_drawTexturedWithFrame:inView:, which follows the same rule for labels.
    if ([image isTemplate] && [segment isSelected] && [self isEnabled] &&
        [self trackingMode] == NSSegmentSwitchTrackingSelectAny &&
        (_style == NSSegmentStyleTexturedRounded || _style == NSSegmentStyleTexturedSquare)) {
        [cell setHighlighted: NO];
        image = [image _imageTintedWithColor: [NSColor controlAccentColor]];
    }
    if (image) {
        [cell setImage: image];
        // a button cell is created as a text cell - so we need to say that we
        // want image dimming
        [cell setImageDimsWhenDisabled: YES];

        if ([label length]) {
            [cell setImagePosition: NSImageLeft];
        } else {
            // center if no label
            [cell setImagePosition: NSImageOnly];
        }
        [cell setImageScaling: [segment imageScaling]];
    } else {
        [cell setImagePosition: NSNoImage];
    }

    [cell setLineBreakMode: NSLineBreakByTruncatingTail];

    return cell;
}

- (void) _recomputeSegmentWidths {
    if (!_segmentComputedWidths)
        _segmentComputedWidths = [[NSMutableArray arrayWithCapacity: 5] retain];
    else
        [_segmentComputedWidths removeAllObjects];

    CGFloat x = 0;
    NSDictionary *textAttrs = nil;

    int i, count = [_segments count];
    for (i = 0; i < count; i++) {
        NSSegmentItem *segment = [_segments objectAtIndex: i];
        double w = [segment width];
        if (w <= 0.0) {
            NSCell *cell = [self _cellForSegment: i];
            w = [cell cellSize].width;
            if ((_style == NSSegmentStyleAutomatic || _style == NSSegmentStyleRounded || [self _isTextured]) &&
                [segment image] == nil) {
                // QUIRK: the automatic width of a text segment of a rounded control is the width of the
                // label plus 30.5, 27 or 22.5 points (regular, small, mini). Not documented. Evidence:
                // black-box renders on macOS 10.14.4 (tier 2): total widths of 162, 139 and 116 points for
                // the labels One, Two and Three. Test: appkit-segmented-aqua.m
                // QUIRK: the first and last segments of a textured control are 1 point narrower at the mini size,
                // and those of a textured rounded control 2 points wider at the regular size (textured rounded: 166,
                // 139 and 114 points for the same labels; textured square: 162, 139 and 114). Evidence: black-box
                // renders on macOS 10.14.4 (tier 2), probe mac-probes/aqua-toolbar.m of the research notes.
                // Test: appkit-toolbar-controls-aqua.m (test_quirk_textured_segments)
                static const CGFloat padding[3] = {30.5, 27, 22.5};
                CGFloat texturedEnds[3] = {_style == NSSegmentStyleTexturedRounded ? 2 : 0, 0, -1};
                NSDictionary *attributes = [NSDictionary dictionaryWithObject: [self _aquaFont] forKey: NSFontAttributeName];
                int index = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);

                w = ceil([[segment label] sizeWithAttributes: attributes].width + padding[index]);
                if ([self _isTextured] && (i == 0 || i == count - 1))
                    w += texturedEnds[index];
            }
        }
        [_segmentComputedWidths addObject: [NSNumber numberWithDouble: w]];
    }
}

- (CGFloat) _fittedSegmentWidthsForWidth: (CGFloat) availableWidth into: (CGFloat *) widths {
    NSInteger count = [self segmentCount];
    if ([_segmentComputedWidths count] != count)
        [self _recomputeSegmentWidths];

    CGFloat total = 0;
    for (NSInteger i = 0; i < count; i++) {
        widths[i] = [[_segmentComputedWidths objectAtIndex: i] doubleValue];
        total += widths[i];
    }
    if (count == 0 || availableWidth <= 0 || total <= availableWidth)
        return total;

    CGFloat deficit = total - availableWidth;
    NSDictionary *attrs = [NSDictionary dictionaryWithObject: [self _aquaFont] forKey: NSFontAttributeName];
    CGFloat stackSlack[32];
    CGFloat *slack = count <= 32 ? stackSlack : malloc(sizeof(CGFloat) * count);
    CGFloat totalSlack = 0;
    for (NSInteger i = 0; i < count; i++) {
        NSSegmentItem *seg = [_segments objectAtIndex: i];
        CGFloat minW = 6.0;
        if ([[seg label] length] > 0)
            minW += ceil([[seg label] sizeWithAttributes: attrs].width);
        if ([seg image] != nil)
            minW += [[seg image] size].width;
        slack[i] = MAX(0.0, widths[i] - minW);
        totalSlack += slack[i];
    }

    if (totalSlack > 0) {
        CGFloat take = MIN(deficit, totalSlack);
        CGFloat taken = 0;
        for (NSInteger i = 0; i < count; i++) {
            CGFloat d = floor(slack[i] * (take / totalSlack));
            widths[i] -= d;
            slack[i] -= d;
            taken += d;
        }
        NSInteger remSlack = (NSInteger) floor(take - taken);
        for (NSInteger i = 0; i < count && remSlack > 0; i++) {
            if (slack[i] >= 1.0 && widths[i] > 1.0) {
                widths[i] -= 1.0;
                slack[i] -= 1.0;
                taken += 1.0;
                remSlack--;
            }
        }
        total -= taken;
    }
    if (slack != stackSlack)
        free(slack);

    if (total > availableWidth && total > 0) {
        CGFloat scale = availableWidth / total;
        CGFloat used = 0;
        for (NSInteger i = 0; i < count; i++) {
            widths[i] = floor(widths[i] * scale);
            used += widths[i];
        }
        NSInteger rem = (NSInteger) floor(availableWidth - used);
        for (NSInteger i = 0; i < count && rem > 0; i++, rem--)
            widths[i] += 1.0;
    }
    return availableWidth;
}

- (NSRect) rectForSegment: (NSInteger) segment inFrame: (NSRect) frame {
    NSInteger count = [self segmentCount];
    if (segment < 0 || segment >= count)
        return NSZeroRect;

    CGFloat stackWidths[32];
    CGFloat *widths = count <= 32 ? stackWidths : malloc(sizeof(CGFloat) * count);
    [self _fittedSegmentWidthsForWidth: NSWidth(frame) into: widths];

    CGFloat x = NSMinX(frame);
    for (NSInteger i = 0; i < segment; i++)
        x += widths[i];
    CGFloat w = widths[segment];
    if (widths != stackWidths)
        free(widths);

    if (_style == NSSegmentStyleAutomatic || _style == NSSegmentStyleRounded) {
        static const CGFloat heights[3] = {20, 17, 14};
        int index = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);
        return NSMakeRect(x, floor(NSMidY(frame) - heights[index] / 2.0), w, heights[index]);
    }
    return NSMakeRect(x, NSMinY(frame), w, NSHeight(frame));
}

- (void) drawSegment: (NSInteger) idx
             inFrame: (NSRect) frame
            withView: (NSView *) view
{
    NSButtonCell *cell = [self _cellForSegment: idx];

    [cell setControlView: view];
    [cell drawWithFrame: frame inView: view];
}

/* QUIRK: a rounded (or automatic) segmented control is drawn like the tab strip of a tab view: one white
   rounded strip 20, 17 or 14 points high (regular, small, mini), a blue segment for the selected one (gray in a
   window that is not active, and when the control is disabled), light dividers between segments that do not
   touch the selected one, and the selected label in white on blue. Not documented. Evidence: black-box
   renders of NSSegmentedControl on macOS 10.14.4 at 1x (tier 2), the same metrics as the tab strip. The other
   styles keep drawing button bezels. Test: appkit-segmented-aqua.m */
- (void) _drawAquaWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {
    static const CGFloat heights[3] = {20, 17, 14};
    int index = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);
    int i, count = [self segmentCount];
    if (count == 0)
        return;
    CGFloat stackWidths[32];
    CGFloat *widths = count <= 32 ? stackWidths : malloc(sizeof(CGFloat) * count);
    CGFloat total = [self _fittedSegmentWidthsForWidth: NSWidth(cellFrame) into: widths];
    NSGraphicsStyle *style = [controlView graphicsStyle];
    BOOL active = [[controlView window] isKeyWindow] && [self isEnabled];

    NSRect strip = NSMakeRect(NSMinX(cellFrame), floor(NSMidY(cellFrame) - heights[index] / 2), total, heights[index]);
    CGFloat x = NSMinX(strip);
    NSInteger selected = -1;

    [style drawTabStripInRect: strip];
    for (i = 0; i < count; i++) {
        NSRect segmentFrame = NSMakeRect(x, NSMinY(strip), widths[i], NSHeight(strip));

        if ([self isSelectedForSegment: i]) {
            selected = i;
            [style drawSelectedTabInRect: segmentFrame stripRect: strip active: active];
        }
        x += NSWidth(segmentFrame);
    }
    x = NSMinX(strip);
    for (i = 0; i < count; i++) {
        NSRect segmentFrame = NSMakeRect(x, NSMinY(strip), widths[i], NSHeight(strip));

        if (i > 0 && i != selected && i - 1 != selected)
            [style drawTabDividerInRect: NSMakeRect(NSMinX(segmentFrame), NSMinY(segmentFrame) + 1, 1,
                                                    NSHeight(segmentFrame) - 2)];
        NSButtonCell *cell = [self _cellForSegment: i];
        BOOL white = i == selected && active;
        NSString *label = [[_segments objectAtIndex: i] label];

        if ([label length] > 0) {
            NSMutableAttributedString *title = [[[NSMutableAttributedString alloc] initWithString: label] autorelease];
            NSMutableParagraphStyle *paragraph = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];

            [paragraph setAlignment: NSCenterTextAlignment];
            [paragraph setLineBreakMode: NSLineBreakByTruncatingTail];
            [title addAttribute: NSParagraphStyleAttributeName value: paragraph range: NSMakeRange(0, [label length])];
            [title addAttribute: NSFontAttributeName value: [self _aquaFont] range: NSMakeRange(0, [label length])];
            [title addAttribute: NSForegroundColorAttributeName
                          value: white ? [NSColor whiteColor]
                                       : ([self isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])
                          range: NSMakeRange(0, [label length])];
            [cell setAttributedTitle: title];
        }
        // a template image is drawn like the label: white on the selected segment, dark on the others
        NSImage *image = [[_segments objectAtIndex: i] image];
        if ([image isTemplate])
            [cell setImage: [image _imageTintedWithColor: white ? [NSColor whiteColor]
                                                                : [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.8]]];
        [cell setHighlighted: NO];
        [cell setBordered: NO];
        [cell setControlView: controlView];
        [NSGraphicsContext saveGraphicsState];
        NSRect interior = ([label length] > 0 && NSWidth(segmentFrame) > 4.0) ? NSInsetRect(segmentFrame, 2, 0) : segmentFrame;
        NSRectClip(interior);
        [cell drawInteriorWithFrame: interior inView: controlView];
        [NSGraphicsContext restoreGraphicsState];
        x += NSWidth(segmentFrame);
    }
    if (widths != stackWidths)
        free(widths);
}

- (BOOL) _isTextured {
    return _style == NSSegmentStyleTexturedRounded || _style == NSSegmentStyleTexturedSquare;
}

// QUIRK: a textured segmented control draws its bezel 23, 19 or 16 points high (regular, small, mini, with the
// point below the bezel) and centres it vertically in a taller frame, the odd point going below. Not documented.
// Evidence: black-box renders on macOS 10.14.4 (tier 2) in frames 14 to 32 points high, probes
// mac-probes/aqua-toolbar.m and aqua-toolbar-2.m of the research notes.
// Test: appkit-toolbar-controls-aqua.m (test_quirk_textured_segments)
- (CGFloat) _texturedArtworkHeight {
    static const CGFloat heights[3] = {23, 19, 16};

    return heights[[self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0)];
}

/* QUIRK: a textured segmented control draws one textured bezel across its segments, with separators between them.
   In a control that selects one segment the selected segment shows the dark on look of a textured button and a white
   label; in a control that selects any number of segments a selected segment keeps the light bezel and shows its
   label in the accent colour; a momentary control shows no selection. Other labels are black at 65% (25% when the
   control is disabled; a selected label is then white at 60%). Not documented. Evidence: black-box renders of
   NSSegmentedControl on macOS 10.14.4 at 1x (tier 2), probes mac-probes/aqua-toolbar.m and aqua-toolbar-2.m of the
   research notes. Test: appkit-toolbar-controls-aqua.m (test_quirk_textured_segments) */
- (void) _drawTexturedWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {
    BOOL square = _style == NSSegmentStyleTexturedSquare;
    BOOL flipped = [controlView isFlipped];
    BOOL enabled = [self isEnabled];
    NSSegmentSwitchTracking tracking = [self trackingMode];
    NSGraphicsStyle *style = [controlView graphicsStyle];
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    int i, count = [self segmentCount];
    if (count == 0)
        return;
    CGFloat stackWidths[32];
    CGFloat *widths = count <= 32 ? stackWidths : malloc(sizeof(CGFloat) * count);
    CGFloat total = [self _fittedSegmentWidthsForWidth: NSWidth(cellFrame) into: widths];

    NSRect art = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), total, NSHeight(cellFrame));
    if (!square) {
        CGFloat height = [self _texturedArtworkHeight];
        CGFloat above = floor((NSHeight(cellFrame) - height) / 2);

        art.origin.y += flipped ? above : NSHeight(cellFrame) - height - above;
        art.size.height = height;
    }

    // the style draws for a view that is not flipped: the bezel is mirrored about the artwork in a flipped view
    NSRect interior = [style texturedBezelInteriorForRect: art square: square];
    CGFloat x = NSMinX(art);
    CGContextSaveGState(context);
    if (flipped) {
        CGContextTranslateCTM(context, 0, 2 * art.origin.y + art.size.height);
        CGContextScaleCTM(context, 1, -1);
    }
    for (i = 0; i < count; i++) {
        CGFloat width = widths[i];
        BOOL dark = tracking == NSSegmentSwitchTrackingSelectOne && [self isSelectedForSegment: i];

        CGContextSaveGState(context);
        CGContextClipToRect(context, NSMakeRect(x, NSMinY(art), width, NSHeight(art)));
        [style drawTexturedBezelInRect: art square: square pressed: NO on: dark controlSize: [self controlSize]];
        CGContextRestoreGState(context);
        if (dark) {
            if (i > 0)
                [style drawTexturedSegmentSeparatorInRect: NSMakeRect(x, NSMinY(interior), 1, NSHeight(interior))];
            if (i < count - 1)
                [style drawTexturedSegmentSeparatorInRect: NSMakeRect(x + width - 1, NSMinY(interior), 1,
                                                                      NSHeight(interior))];
        } else if (i > 0 && !(tracking == NSSegmentSwitchTrackingSelectOne && [self isSelectedForSegment: i - 1]))
            [style drawTexturedSegmentSeparatorInRect: NSMakeRect(x, NSMinY(interior), 1, NSHeight(interior))];
        x += width;
    }
    CGContextRestoreGState(context);

    // the labels and images, centred on the bezel without the point below it
    BOOL darkLook = [[[NSAppearance currentDrawingAppearance]
        bestMatchFromAppearancesWithNames: [NSArray arrayWithObjects: NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]]
        isEqualToString: NSAppearanceNameDarkAqua];
    NSRect body = art;
    body.size.height -= 1;
    if (!flipped)
        body.origin.y += 1;
    x = NSMinX(art);
    for (i = 0; i < count; i++) {
        NSSegmentItem *segment = [_segments objectAtIndex: i];
        NSRect segmentFrame = NSMakeRect(x, NSMinY(body), widths[i], NSHeight(body));
        BOOL selected = [self isSelectedForSegment: i];
        NSColor *color;

        if (selected && tracking == NSSegmentSwitchTrackingSelectOne)
            // the selected segment of the dark look is a light bezel, with dark text
            color = [NSColor colorWithCalibratedWhite: darkLook ? 0 : 1 alpha: darkLook ? (enabled ? 0.75 : 0.35) : (enabled ? 1 : 0.6)];
        else if (selected && tracking == NSSegmentSwitchTrackingSelectAny && enabled)
            color = [NSColor controlAccentColor];
        else
            color = [NSColor colorWithCalibratedWhite: darkLook ? 1 : 0 alpha: enabled ? 0.65 : 0.25];

        NSButtonCell *cell = [self _cellForSegment: i];
        NSString *label = [segment label];

        if ([label length] > 0) {
            NSMutableAttributedString *title = [[[NSMutableAttributedString alloc] initWithString: label] autorelease];
            NSMutableParagraphStyle *paragraph = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];

            [paragraph setAlignment: NSCenterTextAlignment];
            [paragraph setLineBreakMode: NSLineBreakByTruncatingTail];
            [title addAttribute: NSParagraphStyleAttributeName value: paragraph range: NSMakeRange(0, [label length])];
            [title addAttribute: NSFontAttributeName value: [self _aquaFont] range: NSMakeRange(0, [label length])];
            [title addAttribute: NSForegroundColorAttributeName value: color range: NSMakeRange(0, [label length])];
            [cell setAttributedTitle: title];
        }
        NSImage *image = [segment image];
        if ([image isTemplate])
            [cell setImage: [image _imageTintedWithColor: color]];
        [cell setHighlighted: NO];
        [cell setBordered: NO];
        [cell setEnabled: YES];
        [cell setControlView: controlView];
        [NSGraphicsContext saveGraphicsState];
        NSRect interior = ([label length] > 0 && NSWidth(segmentFrame) > 4.0) ? NSInsetRect(segmentFrame, 2, 0) : segmentFrame;
        NSRectClip(interior);
        [cell drawInteriorWithFrame: interior inView: controlView];
        [NSGraphicsContext restoreGraphicsState];
        x += NSWidth(segmentFrame);
    }
    if (widths != stackWidths)
        free(widths);
}

- (void) drawWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {

    int i = 0, count = [self segmentCount];
    if (count == 0)
        return;
    NSRect segmentFrame = cellFrame;

    if ([_segmentComputedWidths count] != count)
        [self _recomputeSegmentWidths];

    if (_style == NSSegmentStyleAutomatic || _style == NSSegmentStyleRounded) {
        [self _drawAquaWithFrame: cellFrame inView: controlView];
        _lastDrawRect = cellFrame;
        return;
    }
    if ([self _isTextured]) {
        [self _drawTexturedWithFrame: cellFrame inView: controlView];
        _lastDrawRect = cellFrame;
        return;
    }

    CGFloat stackWidths[32];
    CGFloat *widths = count <= 32 ? stackWidths : malloc(sizeof(CGFloat) * count);
    [self _fittedSegmentWidthsForWidth: NSWidth(cellFrame) into: widths];

    for (i = 0; i < count; i++) {
        segmentFrame.size.width = widths[i];
        [NSGraphicsContext saveGraphicsState];
        // Make sure that segment drawing is not allowed to spill out into other
        // segments
        NSBezierPath *clipPath =
                [NSBezierPath bezierPathWithRect: segmentFrame];
        [clipPath addClip];
        [self drawSegment: i inFrame: segmentFrame withView: controlView];
        [NSGraphicsContext restoreGraphicsState];
        segmentFrame.origin.x += segmentFrame.size.width;
    }
    if (widths != stackWidths)
        free(widths);

    _lastDrawRect = cellFrame;
}

- (NSSize) cellSize {
    NSSize cellSize = NSMakeSize(0., 0.);

    if ((_style == NSSegmentStyleAutomatic || _style == NSSegmentStyleRounded) &&
        [_segmentComputedWidths count] == [self segmentCount]) {
        // the segments' widths are those of the strip, and it is as high as the control size says
        static const CGFloat heights[3] = {21, 18, 15};
        int index = [self controlSize] == NSSmallControlSize ? 1 : ([self controlSize] == NSMiniControlSize ? 2 : 0);

        for (NSNumber *width in _segmentComputedWidths)
            cellSize.width += [width doubleValue];
        cellSize.height = heights[index] + 1;
        return cellSize;
    }
    if ([self _isTextured] && [_segmentComputedWidths count] == [self segmentCount]) {
        // as high as the textured bezel, see -_texturedArtworkHeight
        for (NSNumber *width in _segmentComputedWidths)
            cellSize.width += [width doubleValue];
        cellSize.height = [self _texturedArtworkHeight];
        return cellSize;
    }
    for (int i = 0; i < [self segmentCount]; ++i) {
        NSCell *cell = [self _cellForSegment: i];
        NSSize size = [cell cellSize];
        cellSize.width += size.width;
        cellSize.height = MAX(size.height, cellSize.height);
    }
    return cellSize;
}

// updating this value in -drawWithFrame is not enough, because a subclass might
// have replaced it entirely. hence NSSegmentedControl will call this private
// method as well.
- (void) _wasDrawnWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {
    _lastDrawRect = cellFrame;
}

- (NSInteger) _segmentForPoint: (NSPoint) point {
    int i = 0, count = [self segmentCount];
    if (count == 0)
        return NSNotFound;
    NSRect segmentFrame = _lastDrawRect;
    if (segmentFrame.size.height <= 0.0)
        segmentFrame.size.height = 100;

    CGFloat stackWidths[32];
    CGFloat *widths = count <= 32 ? stackWidths : malloc(sizeof(CGFloat) * count);
    [self _fittedSegmentWidthsForWidth: NSWidth(segmentFrame) into: widths];

    NSInteger hit = NSNotFound;
    for (i = 0; i < count; i++) {
        segmentFrame.size.width = widths[i];
        if (NSPointInRect(point, segmentFrame)) {
            hit = i;
            break;
        }
        segmentFrame.origin.x += segmentFrame.size.width;
    }
    if (widths != stackWidths)
        free(widths);
    return hit;
}

- (BOOL) startTrackingAt: (NSPoint) startPoint inView: (NSView *) controlView {
    // save the segment clicked on and its state
    _firstTrackingSegmentIndex =
            [self _segmentForPoint: [controlView convertPoint: startPoint
                                                     fromView: nil]];
    NSSegmentItem *trackingItem =
            [_segments objectAtIndex: _firstTrackingSegmentIndex];
    if (![trackingItem isEnabled])
        return YES;

    _firstTrackingSegmentInitialState = [trackingItem isSelected];
    [trackingItem setSelected: !_firstTrackingSegmentInitialState];

    [self continueTracking: startPoint at: startPoint inView: controlView];
    return YES;
}

- (BOOL) continueTracking: (NSPoint) lastPoint
                       at: (NSPoint) currentPoint
                   inView: (NSView *) controlView
{
    currentPoint = [controlView convertPoint: currentPoint fromView: nil];
    lastPoint = [controlView convertPoint: lastPoint fromView: nil];

    NSSegmentItem *trackingItem =
            [_segments objectAtIndex: _firstTrackingSegmentIndex];
    if (![trackingItem isEnabled])
        return YES;

    int currentSegmentIdx = [self _segmentForPoint: currentPoint];

    // change segments state depending on if inside or outside
    if (currentSegmentIdx ==
        _firstTrackingSegmentIndex) // we're inside, so switch state relative to
                                    // initial state
    {
        [trackingItem setSelected: !_firstTrackingSegmentInitialState];
    } else // we're outside, so state is initial state
    {
        [trackingItem setSelected: _firstTrackingSegmentInitialState];
    }

    [controlView setNeedsDisplayInRect: _lastDrawRect];

    return YES;
}

- (void) stopTracking: (NSPoint) lastPoint
                   at: (NSPoint) stopPoint
               inView: (NSView *) controlView
            mouseIsUp: (BOOL) flag
{
    [self continueTracking: lastPoint at: stopPoint inView: controlView];

    NSSegmentItem *trackingItem =
            [_segments objectAtIndex: _firstTrackingSegmentIndex];
    if (![trackingItem isEnabled])
        return;

    [self willChangeValueForKey: @"selectedSegment"];
    _selectedSegment = NSNotFound;
    // if segment is still switched, it'll be the new "selected segment"
    if ([trackingItem isSelected] != _firstTrackingSegmentInitialState) {
        _selectedSegment = _firstTrackingSegmentIndex;
    }

    // adapt other segments to fit tracking model
    switch (_trackingMode) {
    case NSSegmentSwitchTrackingMomentary: {
        // deactivate all segments
        for (NSSegmentItem *item in _segments) {
            [item setSelected: NO];
        }
        break;
    }
    case NSSegmentSwitchTrackingSelectAny: {
        // nothing
        break;
    }
    case NSSegmentSwitchTrackingSelectOne: {
        if (_selectedSegment != NSNotFound) {
            for (NSSegmentItem *item in _segments) {
                [item setSelected: NO];
            }
            // select only the selected item
            [[_segments objectAtIndex: _selectedSegment] setSelected: YES];
        }
        break;
    }
    }
    [self didChangeValueForKey: @"selectedSegment"];
}

- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) cellFrame
              ofView: (NSView *) controlView
        untilMouseUp: (BOOL) flag
{
    NSPoint startPoint = [event locationInWindow];
    NSInteger segmentUnderMouse =
            [self _segmentForPoint: [controlView convertPoint: startPoint
                                                     fromView: nil]];

    if (segmentUnderMouse == NSNotFound)
        return YES;

    NSSegmentItem *trackingItem = [_segments objectAtIndex: segmentUnderMouse];

    if (![trackingItem isEnabled])
        return YES;

    NSMenu *menu = [trackingItem menu];

    if (menu == nil)
        return [super trackMouse: event
                          inRect: cellFrame
                          ofView: controlView
                    untilMouseUp: flag];

    [self setSelectedSegment: segmentUnderMouse];

    [NSMenu popUpContextMenu: menu withEvent: event forView: controlView];

    return YES;
}

@end

@implementation NSSegmentedCell (Bindings)

- (id) _replacementKeyPathForBinding: (id) binding {
    if ([binding isEqual: @"selectedIndex"])
        return @"selectedSegment";
    return [super _replacementKeyPathForBinding: binding];
}

@end
