/* Copyright (c) 2007 Christopher J. W. Lloyd

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
#import "NSInterfaceGraphics.h"
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSInterfacePartAttributedString.h>
#import <AppKit/NSInterfacePartDisabledAttributedString.h>
#import <AppKit/NSWindow.h>

@implementation NSGraphicsStyle

static NSDictionary *sNormalMenuTextAttributes = nil;
static NSDictionary *sSelectedMenuTextAttributes = nil;
static NSDictionary *sDimmedMenuTextAttributes = nil;
static NSDictionary *sScrollerButtonAttributes = nil;

+ (void) initialize {
    if (sNormalMenuTextAttributes == nil) {
        // Menu items are drawn in 14 points, the size of a new NSMenu's font
        // on macOS 10.14.4, which is larger than menuFontOfSize:0.
        NSFont *menuFont = [NSFont menuFontOfSize: 14];
        sNormalMenuTextAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys: menuFont, NSFontAttributeName,
                                              [NSColor menuItemTextColor],
                                              NSForegroundColorAttributeName,
                                              nil] retain];
        sSelectedMenuTextAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys:
                        menuFont, NSFontAttributeName,
                        [NSColor selectedMenuItemTextColor],
                        NSForegroundColorAttributeName, nil] retain];

        sDimmedMenuTextAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys: menuFont, NSFontAttributeName,
                                              [NSColor disabledControlTextColor],
                                              NSForegroundColorAttributeName,
                                              nil] retain];


        sScrollerButtonAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys: [NSFont labelFontOfSize: 8],
                                              NSFontAttributeName,
                                              [NSColor grayColor],
                                              NSForegroundColorAttributeName,
                                              nil] retain];
    }
}

- initWithView: (NSView *) view {
    _view = [view retain];
    return self;
}

- (void) dealloc {
    [_view release];
    [super dealloc];
}

@end

@implementation NSGraphicsStyle (NSMenu)

#define TITLE_TOP_MARGIN 0
#define TITLE_BOTTOM_MARGIN 0
#define BRANCH_ARROW_LEFT_MARGIN 2
#define BRANCH_ARROW_RIGHT_MARGIN 2

- (NSInterfacePartAttributedString *) branchArrow {
    static NSInterfacePartAttributedString *sBranchArrow = nil;

    if (sBranchArrow == nil)
        sBranchArrow = [[NSInterfacePartAttributedString alloc]
                initWithMarlettCharacter: 0x34];
    return sBranchArrow;
}

- (NSInterfacePartAttributedString *) checkMark {
    static NSInterfacePartAttributedString *sCheckMark = nil;

    if (sCheckMark == nil)
        sCheckMark = [[NSInterfacePartAttributedString alloc]
                initWithMarlettCharacter: 0x61];
    return sCheckMark;
}

- (NSSize) menuItemSeparatorSize {
    return NSMakeSize(0, 9);
}

- (Margins) menuItemBranchArrowMargins {
    Margins result = [self menuItemTextMargins];

    result.left = BRANCH_ARROW_LEFT_MARGIN;
    result.right = BRANCH_ARROW_RIGHT_MARGIN;

    return result;
}

- (NSSize) menuItemBranchArrowSize {
    return NSMakeSize(5, 9);
}

- (NSSize) menuItemCheckMarkSize {
    NSSize result = [[self checkMark] size];

    return result;
}

- (Margins) menuItemGutterMargins {
    Margins result;

    result.left = 0;
    result.right = 0;
    result.top = TITLE_TOP_MARGIN;
    result.bottom = TITLE_BOTTOM_MARGIN;

    return result;
}

- (NSSize) menuItemGutterSize {
    NSSize result = NSZeroSize;
    Margins margins = [self menuItemGutterMargins];

    result = [self menuItemCheckMarkSize];

    result.height += (margins.top + margins.bottom);
    result.width += (margins.left + margins.right);

    return result;
}

- (Margins) menuItemTextMargins {
    Margins result;

    result.left = 0;
    result.right = 0;
    result.top = TITLE_TOP_MARGIN;
    result.bottom = TITLE_BOTTOM_MARGIN;

    return result;
}

- (NSSize) menuItemTextSize: (NSString *) title {
    NSSize result = NSZeroSize;
    Margins margins = [self menuItemTextMargins];

    result = [title sizeWithAttributes: sNormalMenuTextAttributes];

    result.height += (margins.top + margins.bottom);
    result.width += (margins.left + margins.right);

    return result;
}

- (NSSize) menuItemAttributedTextSize: (NSAttributedString *) title {
    NSSize result = NSZeroSize;
    Margins margins = [self menuItemTextMargins];

    result = [title size];

    result.height += (margins.top + margins.bottom);
    result.width += (margins.left + margins.right);

    return result;
}

- (CGFloat) menuBarHeight {
    NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys: [NSFont menuBarFontOfSize: 0],
                                          NSFontAttributeName, nil];
    CGFloat result = [@"Menu" sizeWithAttributes: attributes].height;

    result += 2; // border top/bottom margin
    result += 4; // border
    result += 1; // sunken title baseline

    return result;
}

- (CGFloat) menuItemGutterGap {
    return 0;
}

- (void) drawMenuSeparatorInRect: (NSRect) rect {
    // A single hairline in the separator colour, centred in the row.
    CGFloat y = rect.origin.y + floor((rect.size.height - 1) / 2);

    [[NSColor separatorColor] setFill];
    NSRectFillUsingOperation(NSMakeRect(rect.origin.x, y, rect.size.width, 1), NSCompositeSourceOver);
}

- (void) drawMenuGutterInRect: (NSRect) rect {
    // Nothing to do.
}

- (void) drawMenuItemText: (NSString *) string
                   inRect: (NSRect) rect
                  enabled: (BOOL) enabled
                 selected: (BOOL) selected
{
    // Ensure we have enough width - fractional widths give float comparison
    // trouble
    rect.size.width = ceilf(rect.size.width);

    Margins margins = [self menuItemTextMargins];

    rect.origin.x += margins.left;
    rect.origin.y += margins.top;
    rect.size.width -= (margins.left + margins.right);
    rect.size.height -= (margins.top + margins.bottom);

    if (enabled) {
        if (selected) {
            [string drawInRect: rect
                    withAttributes: sSelectedMenuTextAttributes];
        } else {
            [string drawInRect: rect withAttributes: sNormalMenuTextAttributes];
        }
    } else {
        [string drawInRect: rect withAttributes: sDimmedMenuTextAttributes];
    }
}

- (void) drawAttributedMenuItemText: (NSAttributedString *) string
                             inRect: (NSRect) rect
                            enabled: (BOOL) enabled
                           selected: (BOOL) selected
{
    // Ensure we have enough width - fractional widths give float comparison
    // trouble
    rect.size.width = ceilf(rect.size.width);

    NSMutableAttributedString *mutableString = [string mutableCopy];

    Margins margins = [self menuItemTextMargins];

    rect.origin.x += margins.left;
    rect.origin.y += margins.top;
    rect.size.width -= (margins.left + margins.right);
    rect.size.height -= (margins.top + margins.bottom);

    NSRange range = NSMakeRange(0, [string length]);

    if (enabled) {
        if (!selected) {
            [mutableString
                    addAttributes:
                            [NSDictionary
                                    dictionaryWithObject:
                                            [NSColor menuItemTextColor]
                                                  forKey: NSForegroundColorAttributeName]
                            range: range];
        }
        [mutableString drawInRect: rect];
    } else {
        if (!selected) {
            [mutableString
                    addAttributes:
                            [NSDictionary
                                    dictionaryWithObject: [NSColor disabledControlTextColor]
                                                  forKey: NSForegroundColorAttributeName]
                            range: range];
        }
        [mutableString drawInRect: rect];
    }
}

- (void) drawMenuCheckmarkInRect: (NSRect) rect
                         enabled: (BOOL) enabled
                        selected: (BOOL) selected
{
    NSColor *color;
    NSInterfacePartAttributedString *checkMark;
    Margins margins = [self menuItemTextMargins];

    if (enabled)
        color = selected ? [NSColor selectedMenuItemTextColor]
                         : [NSColor menuItemTextColor];
    else
        color = [NSColor disabledControlTextColor];

    checkMark = [[NSInterfacePartAttributedString alloc]
            initWithCharacter: 0x61
                     fontName: @"Marlett"
                    pointSize: 10
                        color: color];
    rect.origin.x += margins.left;
    rect.origin.y += margins.top;

    [checkMark drawAtPoint: rect.origin];
}

- (void) drawMenuBranchArrowInRect: (NSRect) rect
                           enabled: (BOOL) enabled
                          selected: (BOOL) selected
{
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    NSColor *color;
    Margins margins = [self menuItemBranchArrowMargins];
    NSRect themeRect = rect;

    if (enabled)
        color = selected ? [NSColor selectedMenuItemTextColor]
                         : [NSColor menuItemTextColor];
    else
        color = [NSColor disabledControlTextColor];

    [color set];

    themeRect.origin.x += margins.left;
    themeRect.origin.y += margins.top;
    themeRect.size.width -= (margins.left + margins.right);
    themeRect.size.height -= (margins.top + margins.bottom);

    CGContextBeginPath(context);
    CGContextMoveToPoint(context, NSMinX(themeRect), NSMaxY(themeRect));
    CGContextAddLineToPoint(context, NSMaxX(themeRect), NSMidY(themeRect));
    CGContextAddLineToPoint(context, NSMinX(themeRect), NSMinY(themeRect));
    CGContextClosePath(context);
    CGContextFillPath(context);
}

- (void) drawMenuSelectionInRect: (NSRect) rect enabled: (BOOL) enabled {
    if (enabled) {
        [[NSColor selectedMenuItemColor] setFill];
        NSRectFill(rect);
    }
}

- (void) drawMenuWindowBackgroundInRect: (NSRect) rect {
    [[NSColor menuBackgroundColor] setFill];
    NSRectFill(rect);
    [[NSColor windowFrameColor] set];
    NSFrameRect(rect);
}

- (void) drawMenuBarItemBorderInRect: (NSRect) rect
                               hover: (BOOL) hovering
                            selected: (BOOL) selected
{
    if (selected || hovering) {
        [[NSColor selectedMenuItemColor] setFill];
        NSRectFill(rect);
    }
}

- (void) drawMenuBarBackgroundInRect: (NSRect) rect {
    [[NSColor mainMenuBarColor] setFill];
    NSRectFill(rect);
}

@end

@implementation NSGraphicsStyle (NSButton)

- (void) drawUnborderedButtonInRect: (NSRect) rect defaulted: (BOOL) defaulted {
    if (defaulted) {
        [[NSColor blackColor] setFill];
        NSRectFill(rect);
    }
}

- (void) drawPushButtonNormalInRect: (NSRect) rect defaulted: (BOOL) defaulted {
    [self drawPushButtonInRect: rect defaulted: defaulted pressed: NO enabled: YES active: YES];
}

- (void) drawPushButtonPressedInRect: (NSRect) rect {
    [self drawPushButtonInRect: rect defaulted: NO pressed: YES enabled: YES active: YES];
}

- (void) drawPushButtonHighlightedInRect: (NSRect) rect {
    NSInterfaceDrawHighlightedButton(rect, rect);
}

- (NSSize) sizeOfButtonImage: (NSImage *) image
                     enabled: (BOOL) enabled
                       mixed: (BOOL) mixed
{
    return [image size];
}

- (void) drawButtonImage: (NSImage *) image
                  inRect: (NSRect) rect
                 enabled: (BOOL) enabled
                   mixed: (BOOL) mixed
{
    CGFloat fraction = enabled ? 1.0 : 0.5;

    [image drawInRect: rect
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: fraction];
}

@end

@implementation NSGraphicsStyle (NSBrowser)

// QUIRK: a titled browser draws nothing in its title area on macOS 10.14, neither a background nor the title.
// Evidence: black-box renders on macOS 10.14.4 (tier 2): the title area of a titled NSBrowser (titles set with
// -setTitle:ofColumn: and from the delegate) stays transparent in -cacheDisplayInRect:toBitmapImageRep:, and
// -drawTitleOfColumn:inRect: called directly draws no pixels. Test: appkit-browser-title-drawing.m
- (void) drawBrowserTitleBackgroundInRect: (NSRect) rect {
}

- (void) drawBrowserHorizontalScrollerWellInRect: (NSRect) rect
                                        clipRect: (NSRect) clipRect
{
    NSDrawGrayBezel(rect, clipRect);
}

@end

@implementation NSGraphicsStyle (NSColorWell)

- (NSRect) drawColorWellBorderInRect: (NSRect) rect
                             enabled: (BOOL) enabled
                            bordered: (BOOL) bordered
                              active: (BOOL) active
{
    if (bordered) {
        if (active)
            NSInterfaceDrawHighlightedButton(rect, rect);
        else
            NSInterfaceDrawButton(rect, rect);

        // The colour swatch of a bordered well is inset 6 points from each edge, whatever the well's size
        // (black-box on macOS 10.14.4, tests/appkit-colorwell-swatch-inset.m); the 2-point gray bezel
        // around it is inside that margin.
        rect = NSInsetRect(rect, 4, 4);

        if (enabled)
            NSDrawGrayBezel(rect, rect);
    } else {
        if (enabled) {
            NSDrawGrayBezel(rect, rect);
        }
    }

    return NSInsetRect(rect, 2, 2);
}

@end

@implementation NSGraphicsStyle (NSPopUpButton)

- (void) drawPopUpButtonWindowBackgroundInRect: (NSRect) rect {
    [self drawMenuWindowBackgroundInRect: rect];
}

@end

@implementation NSGraphicsStyle (NSOutlineView)

- (void) drawOutlineViewGridInRect: (NSRect) rect {
    NSInterfaceDrawOutlineGrid(rect, NSCurrentGraphicsPort());
}

@end

@implementation NSGraphicsStyle (NSProgressIndicator)

- (NSRect) drawProgressIndicatorBackground: (NSRect) rect
                                  clipRect: (NSRect) clipRect
                                   bezeled: (BOOL) bezeled
{
    if (bezeled) {
        NSInterfaceDrawProgressIndicatorBezel(rect, clipRect);
        return NSInsetRect(rect, 2, 2);
    } else {
        [[[_view window] backgroundColor] setFill];
        NSRectFill(rect);
        return rect;
    }
}

- (void) drawProgressIndicatorChunk: (NSRect) rect {
    [[NSColor selectedControlColor] setFill];
    NSRectFill(rect);
}

// QUIRK: the progress bar look of macOS 10.14 (light appearance). Not documented. Evidence: black-box
// renders of NSProgressIndicator (bar style) on macOS 10.14.4 at 1x (tier 2): the bar is 6 points high at every
// control size, centred in the view and inset 1 point from its left and right edges; the track is black at
// 7% with a darker edge, the fill is the blue (61,130,253) with a slightly darker edge, both with fully
// rounded ends; an indeterminate bar is the fill with a horizontal gradient towards a lighter blue.
// Test: appkit-progress-aqua.m
static const CGFloat NSAquaProgressBarHeight = 6;

static NSRect NSAquaProgressBarRect(NSRect rect) {
    return NSMakeRect(NSMinX(rect) + 1, round(NSMidY(rect) - NSAquaProgressBarHeight / 2),
                      NSWidth(rect) - 2, NSAquaProgressBarHeight);
}

static void NSAquaDrawProgressFill(NSRect bar, NSRect fill, double animation, BOOL indeterminate) {
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGFloat radius = NSHeight(bar) / 2;

    CGContextSaveGState(ctx);
    [[NSBezierPath bezierPathWithRoundedRect: bar xRadius: radius yRadius: radius] addClip];
    if (indeterminate) {
        // QUIRK: an indeterminate bar is the fill blue (61,130,253) with a lighter band, (113,166,254) at its
        // centre, that is a smooth hump over the bar's length and travels along it; at rest the band is in
        // the middle. Evidence: black-box renders of an indeterminate NSProgressIndicator on macOS 10.14.4 at
        // 1x (tier 2). Test: appkit-progress-aqua.m
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        enum { Stops = 9 };
        CGFloat comps[Stops * 4], locations[Stops];

        for (int i = 0; i < Stops; i++) {
            CGFloat u = (CGFloat) i / (Stops - 1), f = pow(sin(M_PI * u), 2.5);

            locations[i] = u;
            comps[i * 4] = (61 + (113 - 61) * f) / 255;
            comps[i * 4 + 1] = (130 + (166 - 130) * f) / 255;
            comps[i * 4 + 2] = (253 + (254 - 253) * f) / 255;
            comps[i * 4 + 3] = 1;
        }
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, locations, Stops);
        // the band travels along the bar and wraps around
        CGFloat span = NSWidth(bar), offset = fmod(animation, 1) * span;

        for (int k = -1; k <= 1; k++) {
            CGFloat x0 = NSMinX(bar) + offset + k * span;
            CGContextDrawLinearGradient(ctx, gradient, CGPointMake(x0, 0), CGPointMake(x0 + span, 0), 0);
        }
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    } else {
        // the end of a partial fill is square; the track's rounded shape clips the ends of a full one
        [[NSColor colorWithCalibratedRed: 61 / 255.0 green: 130 / 255.0 blue: 253 / 255.0 alpha: 1] setFill];
        NSRectFill(fill);
        [[NSColor colorWithCalibratedRed: 53 / 255.0 green: 113 / 255.0 blue: 220 / 255.0 alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMinX(fill), NSMinY(fill), NSWidth(fill), 1));
        NSRectFill(NSMakeRect(NSMinX(fill), NSMaxY(fill) - 1, NSWidth(fill), 1));
    }
    CGContextRestoreGState(ctx);
}

static void NSAquaDrawProgressTrack(NSRect bar) {
    CGFloat radius = NSHeight(bar) / 2;

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.07] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: bar xRadius: radius yRadius: radius] fill];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.12] setStroke];
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(bar, 0.5, 0.5)
                                                         xRadius: radius - 0.5
                                                         yRadius: radius - 0.5];
    [edge setLineWidth: 1];
    [edge stroke];
}

- (void) drawProgressIndicatorIndeterminate: (NSRect) rect
                                   clipRect: (NSRect) clipRect
                                    bezeled: (BOOL) bezeled
                                  animation: (double) animation
{
    NSRect bar = NSAquaProgressBarRect(rect);

    NSAquaDrawProgressTrack(bar);
    NSAquaDrawProgressFill(bar, bar, animation, YES);
}

- (void) drawProgressIndicatorDeterminate: (NSRect) rect
                                 clipRect: (NSRect) clipRect
                                  bezeled: (BOOL) bezeled
                                    value: (double) value
{
    NSRect bar = NSAquaProgressBarRect(rect);
    NSRect fill = bar;

    value = MAX(0, MIN(1, value));
    fill.size.width = round(NSWidth(bar) * value);
    NSAquaDrawProgressTrack(bar);
    if (NSWidth(fill) > 0)
        NSAquaDrawProgressFill(bar, fill, 0, NO);
}

@end

@implementation NSGraphicsStyle (NSScroller)

- (void) drawScrollerButtonInRect: (NSRect) rect
                          enabled: (BOOL) enabled
                          pressed: (BOOL) pressed
                         vertical: (BOOL) vertical
                         upOrLeft: (BOOL) upOrLeft
{
    /*
       unichar code=vertical?(upOrLeft?0x74:0x75):(upOrLeft?0x33:0x34);
       Class   class;
       NSInterfacePart *arrow;

       if(enabled)
        class=[NSInterfacePartAttributedString class];
       else
        class=[NSInterfacePartDisabledAttributedString class];

       arrow=[[[class alloc] initWithMarlettCharacter:code] autorelease];
    */
    NSString *arrow =
            vertical ? (upOrLeft ? @"▲" : @"▼") : (upOrLeft ? @"◀" : @"▶");

    if (!NSIsEmptyRect(rect)) {
        NSSize arrowSize =
                [arrow sizeWithAttributes: sScrollerButtonAttributes];

        if (pressed)
            [self drawPushButtonPressedInRect: rect];
        else
            [self drawPushButtonNormalInRect: rect defaulted: NO];

        if (rect.size.height > 8 && rect.size.width > 8) {
            NSPoint point = rect.origin;

            point.x += floor((rect.size.width - arrowSize.width) / 2);
            point.y += floor((rect.size.height - arrowSize.height) / 2);
            [arrow drawAtPoint: point
                    withAttributes: sScrollerButtonAttributes];
        }
    }
}

// The scroller artwork is 15 points thick for the regular control size and 11 points for the small and mini
// sizes (NSScroller places it against the far edge of a scroller of another thickness). The knob is a capsule
// across it: 8 points wide, 4 points in from the edge it is next to and 3 from the other, in the regular
// artwork; 6 points wide, 3 in and 2 from the other edge, in the small artwork. It is mid gray, also while
// highlighted, and one point shorter at each end than its rectangle.
// QUIRK: not documented. Evidence: pixel measurement of legacy scrollers of every control size drawn by
// macOS 10.14.4 (tier 2), probes mac-probes/ua5-scroller-draw.m and mac-probes/aqua-scroller-divider(-mixed).m.
// Test: tests/appkit-scroller-parts.m (test_quirk_scroller_drawing, test_quirk_scroller_control_sizes)
- (void) drawScrollerKnobInRect: (NSRect) rect
                       vertical: (BOOL) vertical
                      highlight: (BOOL) highlight
{
    CGFloat thickness = vertical ? rect.size.width : rect.size.height;
    CGFloat across = thickness >= 15 ? 8 : 6;
    CGFloat inset = floor((thickness - across) / 2) + 1;
    NSRect capsule = vertical ? NSMakeRect(NSMinX(rect) + inset, NSMinY(rect) + 1, across, rect.size.height - 2)
                              : NSMakeRect(NSMinX(rect) + 1, NSMinY(rect) + inset, rect.size.width - 2, across);

    if (thickness < across + 2 || capsule.size.width < 1 || capsule.size.height < 1)
        return;
    CGFloat radius = MIN(capsule.size.width, capsule.size.height) / 2;

    [[NSColor colorWithCalibratedWhite: 0.76 alpha: 1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: capsule xRadius: radius yRadius: radius] fill];
}

// The track is a very light gray with a darker line along each of its long edges; the line at the near edge
// (left, or top) is darker and has a lighter line inside it.
// QUIRK: same evidence as the knob. Test: tests/appkit-scroller-parts.m (test_quirk_scroller_drawing)
- (void) drawScrollerTrackInRect: (NSRect) rect
                        vertical: (BOOL) vertical
                        upOrLeft: (BOOL) upOrLeft
{
    [[NSColor colorWithCalibratedWhite: 0.98 alpha: 1] setFill];
    NSRectFill(rect);
    if (vertical) {
        [[NSColor colorWithCalibratedWhite: 0.91 alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), 1, rect.size.height));
        [[NSColor colorWithCalibratedWhite: 0.973 alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMinX(rect) + 1, NSMinY(rect), 1, rect.size.height));
        [[NSColor colorWithCalibratedWhite: 0.93 alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect), 1, rect.size.height));
    } else {
        [[NSColor colorWithCalibratedWhite: 0.91 alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), rect.size.width, 1));
        [[NSColor colorWithCalibratedWhite: 0.973 alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, rect.size.width, 1));
        [[NSColor colorWithCalibratedWhite: 0.93 alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMinX(rect), NSMaxY(rect) - 1, rect.size.width, 1));
    }
}

// The knob of an overlay scroller is a dark translucent capsule, 7 points wide in the 16 point regular
// artwork and 5 points in the 14 point small artwork, ending 2 points before the far edge, and one point
// shorter at each end than its rectangle. Over white it is a gray of 0.49.
// QUIRK: not documented. Evidence: pixel measurement of overlay scroller knobs drawn by macOS 10.14.4 through
// -drawKnob (tier 2), probe mac-probes/aqua-scroller-divider.m. Test: tests/appkit-scroller-parts.m
// (test_quirk_overlay_scroller_drawing)
- (void) drawOverlayScrollerKnobInRect: (NSRect) rect vertical: (BOOL) vertical {
    CGFloat thickness = vertical ? rect.size.width : rect.size.height;
    CGFloat across = thickness >= 16 ? 7 : 5;
    NSRect capsule = vertical ? NSMakeRect(NSMaxX(rect) - 2 - across, NSMinY(rect) + 1, across, rect.size.height - 2)
                              : NSMakeRect(NSMinX(rect) + 1, NSMaxY(rect) - 2 - across, rect.size.width - 2, across);

    if (thickness < across + 2 || capsule.size.width < 1 || capsule.size.height < 1)
        return;
    CGFloat radius = MIN(capsule.size.width, capsule.size.height) / 2;

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.51] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: capsule xRadius: radius yRadius: radius] fill];
}

- (void) drawScrollerTrackInRect: (NSRect) rect vertical: (BOOL) vertical {
    [self drawScrollerTrackInRect: rect vertical: vertical upOrLeft: NO];
}

// The corner between two legacy scrollers is the track color with the lines of the tracks' far edges along its
// right and bottom edges.
// QUIRK: same evidence as -drawScrollerTrackInRect:vertical:upOrLeft:. Test: tests/appkit-scroller-parts.m
// (test_quirk_scroll_view_corner)
- (void) drawScrollerCornerInRect: (NSRect) rect flipped: (BOOL) flipped {
    [[NSColor colorWithCalibratedWhite: 0.98 alpha: 1] setFill];
    NSRectFill(rect);
    [[NSColor colorWithCalibratedWhite: 0.93 alpha: 1] setFill];
    NSRectFill(NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect), 1, rect.size.height));
    NSRectFill(NSMakeRect(NSMinX(rect), flipped ? NSMaxY(rect) - 1 : NSMinY(rect), rect.size.width, 1));
}

@end

@implementation NSGraphicsStyle (NSSplitViewAqua)

// The dimple is a translucent black disc with a darker rim, the rim darkest at the top of the screen and
// lightest at the bottom, so it darkens whatever the divider was filled with. Over white the middle of the
// disc is a gray of about 0.86 and its rim about 0.73 at the top, 0.78 at the sides and 0.82 at the bottom.
// QUIRK: not documented. Evidence: pixel measurement of thick and pane splitter dividers drawn by
// macOS 10.14.4 (tier 2), also over a red dividerColor, probes mac-probes/aqua-scroller-divider.m and -mixed.m.
// Test: tests/appkit-split-view-divider-drawing.m (test_quirk_dimple)
- (void) drawSplitViewDimpleInRect: (NSRect) rect flipped: (BOOL) flipped {
    NSRect ring = NSInsetRect(rect, 0.5, 0.5);
    CGFloat third = rect.size.height / 3;
    // the rim is darker towards the top of the screen
    CGFloat rim[3] = {0.15, 0.10, 0.045};

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.14] setFill];
    [[NSBezierPath bezierPathWithOvalInRect: rect] fill];
    for (int band = 0; band < 3; band++) {
        CGFloat y = flipped ? NSMinY(rect) + band * third : NSMaxY(rect) - (band + 1) * third;
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect: ring];

        [NSGraphicsContext saveGraphicsState];
        NSRectClip(NSMakeRect(NSMinX(rect), y, rect.size.width, third));
        [[NSColor colorWithCalibratedWhite: 0 alpha: rim[band]] setStroke];
        [path setLineWidth: 1];
        [path stroke];
        [NSGraphicsContext restoreGraphicsState];
    }
}

// A pane splitter is opaque, whatever the divider color: a gray line of 0.835 along its bottom (or left) edge
// and one of 0.851 along its top (or right) edge, and between them a gradient from 0.984 next to the first
// line to white next to the second.
// QUIRK: not documented. Evidence: pixel measurement of pane splitter dividers drawn by macOS 10.14.4 (tier 2),
// also with a red dividerColor, probes mac-probes/aqua-scroller-divider.m and -mixed.m.
// Test: tests/appkit-split-view-divider-drawing.m (test_quirk_pane_splitter)
- (void) drawSplitViewPaneSplitterInRect: (NSRect) rect vertical: (BOOL) vertical flipped: (BOOL) flipped {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[8] = {0.984, 0.984, 0.984, 1, 1, 1, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
    NSRect darkLine, lightLine;
    CGPoint from, to;

    if (vertical) {
        // a vertical divider between panes side by side: the darker line is on the left
        darkLine = NSMakeRect(NSMinX(rect), NSMinY(rect), 1, rect.size.height);
        lightLine = NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect), 1, rect.size.height);
        from = CGPointMake(NSMinX(rect) + 1, 0);
        to = CGPointMake(NSMaxX(rect) - 1, 0);
    } else {
        // a horizontal divider between stacked panes: the darker line is at the bottom of the screen
        CGFloat bottom = flipped ? NSMaxY(rect) - 1 : NSMinY(rect);
        CGFloat top = flipped ? NSMinY(rect) : NSMaxY(rect) - 1;

        darkLine = NSMakeRect(NSMinX(rect), bottom, rect.size.width, 1);
        lightLine = NSMakeRect(NSMinX(rect), top, rect.size.width, 1);
        from = CGPointMake(0, flipped ? NSMaxY(rect) - 1 : NSMinY(rect) + 1);
        to = CGPointMake(0, flipped ? NSMinY(rect) + 1 : NSMaxY(rect) - 1);
    }
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSInsetRect(rect, vertical ? 1 : 0, vertical ? 0 : 1));
    CGContextDrawLinearGradient(ctx, gradient, from, to, 0);
    [NSGraphicsContext restoreGraphicsState];
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    [[NSColor colorWithCalibratedWhite: 0.835 alpha: 1] setFill];
    NSRectFill(darkLine);
    [[NSColor colorWithCalibratedWhite: 0.851 alpha: 1] setFill];
    NSRectFill(lightLine);
}

@end

@implementation NSGraphicsStyle (NSSlider)

- (NSSize) sliderKnobSizeForControlSize: (NSControlSize) controlSize {

    switch (controlSize) {
    default:
    // QUIRK: the knob rectangle of a slider is a square of 21, 15 and 12 points for the regular, small and
    // mini control sizes; the visible circle is 6, 4 and 3 points smaller (the rest is room for its shadow).
    // Not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2) of -knobRectFlipped:
    // and renders. Test: appkit-slider-aqua.m
    case NSRegularControlSize:
        return NSMakeSize(21, 21);

    case NSSmallControlSize:
        return NSMakeSize(15, 15);

    case NSMiniControlSize:
        return NSMakeSize(12, 12);
    }
}

- (void) drawSliderKnobInRect: (NSRect) rect
                     vertical: (BOOL) vertical
                  highlighted: (BOOL) highlighted
                 hasTickMarks: (BOOL) hasTickMarks
             tickMarkPosition: (NSTickMarkPosition) tickMarkPosition
{
    NSDrawButton(rect, rect);

    if (highlighted) {
        [[NSColor whiteColor] setFill];
        NSRectFill(NSInsetRect(rect, 1, 1));
    }
}

- (void) drawSliderTrackInRect: (NSRect) rect
                      vertical: (BOOL) vertical
                  hasTickMarks: (BOOL) hasTickMarks
{
    NSRect groove = rect;

    if (vertical) {
        groove.size.width = 4;
        groove.origin.x = floor(rect.origin.x + (rect.size.width - 4) / 2);
    } else {
        groove.size.height = 4;
        groove.origin.y = floor(rect.origin.y + (rect.size.height - 4) / 2);
    }

    NSDrawGrayBezel(groove, rect);
}

- (void) drawSliderTickInRect: (NSRect) rect {
    [[NSColor blackColor] setFill];
    NSRectFill(rect);
}

@end

@implementation NSGraphicsStyle (NSStepper)

- (void) drawStepperButtonInRect: (NSRect) rect
                        clipRect: (NSRect) clipRect
                         enabled: (BOOL) enabled
                     highlighted: (BOOL) highlighted
                       upNotDown: (BOOL) upNotDown
{
    if (highlighted)
        NSDrawWhiteBezel(rect, clipRect);
    else
        NSDrawButton(rect, clipRect);

    // The arrow is a small solid triangle centred in the button, pointing up or down. (It was a glyph of
    // the Windows Marlett font, which other platforms do not have: letters were drawn instead.)
    CGFloat halfWidth = MIN(3.0, floor(rect.size.width / 4));
    CGFloat height = MIN(halfWidth, floor(rect.size.height / 3));
    CGFloat centerX = NSMidX(rect), centerY = NSMidY(rect);
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    BOOL tipAtSmallerY = (upNotDown == flipped);
    CGFloat tipY = centerY + (tipAtSmallerY ? -height : height) / 2;
    CGFloat baseY = centerY + (tipAtSmallerY ? height : -height) / 2;
    NSBezierPath *arrow = [NSBezierPath bezierPath];

    [arrow moveToPoint: NSMakePoint(centerX, tipY)];
    [arrow lineToPoint: NSMakePoint(centerX + halfWidth, baseY)];
    [arrow lineToPoint: NSMakePoint(centerX - halfWidth, baseY)];
    [arrow closePath];
    [(enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]) setFill];
    [arrow fill];
}

@end

@implementation NSGraphicsStyle (NSTableView)

static void NSTableHeaderFill(NSRect rect, CGFloat white) {
    [[NSColor colorWithCalibratedWhite: white / 255.0 alpha: 1] setFill];
    NSRectFill(rect);
}

// QUIRK: the table header look of macOS 10.14 (light appearance). Not documented. Evidence: black-box renders of
// NSTableHeaderView and of NSTableHeaderCell drawn on its own on macOS 10.14.4 at 1x (tier 2;
// vd-upstream/mac-probes/aqua-table-header*.m):
//   - a white cell with a one point (214,214,214) line along its top and bottom edge;
//   - a one point (229,229,229) separator in the last column of points of every column, the last one included,
//     3 points shorter than the cell at each end;
//   - a highlighted (pressed) cell is (220,220,220) from below the top line to 2 points above the bottom edge,
//     keeps a white line above the bottom line and has no separator.
// Test: appkit-table-header-aqua.m (test_quirk_header_lines, test_quirk_pressed_cell)
- (void) drawTableViewHeaderInRect: (NSRect) rect
                       highlighted: (BOOL) highlighted
{
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    CGFloat top = flipped ? NSMinY(rect) : NSMaxY(rect) - 1;
    CGFloat bottom = flipped ? NSMaxY(rect) - 1 : NSMinY(rect);

    NSTableHeaderFill(rect, 255);
    if (highlighted && NSHeight(rect) > 3)
        NSTableHeaderFill(NSMakeRect(NSMinX(rect), flipped ? NSMinY(rect) + 1 : NSMinY(rect) + 2, NSWidth(rect),
                                     NSHeight(rect) - 3), 220);
    NSTableHeaderFill(NSMakeRect(NSMinX(rect), top, NSWidth(rect), 1), 214);
    NSTableHeaderFill(NSMakeRect(NSMinX(rect), bottom, NSWidth(rect), 1), 214);
    if (!highlighted && NSHeight(rect) > 8 && NSWidth(rect) >= 1)
        NSTableHeaderFill(NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect) + 3, 1, NSHeight(rect) - 6), 229);
}

// An empty stretch of header: the corner view, and the header right of its last column.
// QUIRK: both show the top and bottom lines of a header cell but no separator. Evidence: black-box renders on
// macOS 10.14.4 (tier 2): the header of three 103 point columns in a 330 point table has no separator from x 309
// to 329; next to a legacy vertical scroller the corner view is one point wider than the scroller (frame
// {315,0,16,17} in a 330 point scroll view), so that its own separator lies outside the scroll view. Darling's
// corner view is as wide as the scroller, so it draws no separator.
// Test: appkit-table-header-aqua.m (test_quirk_header_lines, test_quirk_corner_view)
- (void) drawTableViewCornerInRect: (NSRect) rect {
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];

    NSTableHeaderFill(rect, 255);
    NSTableHeaderFill(NSMakeRect(NSMinX(rect), flipped ? NSMinY(rect) : NSMaxY(rect) - 1, NSWidth(rect), 1), 214);
    NSTableHeaderFill(NSMakeRect(NSMinX(rect), flipped ? NSMaxY(rect) - 1 : NSMinY(rect), NSWidth(rect), 1), 214);
}

// QUIRK: an indicator image set with -[NSTableView setIndicatorImage:inTableColumn:] is drawn as it is, except a
// template image, whose coverage is drawn in black at half opacity. Evidence: black-box renders on macOS 10.14.4
// (tier 2): an opaque 9 x 9 template image draws (128,128,128) over the white header, a red or blue one that is
// not a template draws red or blue, NSAscendingSortIndicator draws its chevron half as dark as on its own.
// Test: appkit-table-header-aqua.m (test_quirk_indicator_image)
- (void) drawTableViewHeaderIndicatorImage: (NSImage *) image inRect: (NSRect) rect {
    if (![image isTemplate]) {
        [image drawInRect: rect
                 fromRect: NSZeroRect
                operation: NSCompositeSourceOver
                 fraction: 1.0
           respectFlipped: YES
                    hints: nil];
        return;
    }

    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    CGContextSaveGState(context);
    CGContextBeginTransparencyLayerWithRect(context, rect, NULL);
    [image drawInRect: rect
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0
       respectFlipped: YES
                hints: nil];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.5] setFill];
    NSRectFillUsingOperation(rect, NSCompositeSourceIn);
    CGContextEndTransparencyLayer(context);
    CGContextRestoreGState(context);
}

@end

@implementation NSGraphicsStyle (NSBox)

- (void) drawBoxWithLineInRect: (NSRect) rect {
    [[NSColor colorWithCalibratedWhite: 0.78 alpha: 1.0] setStroke];
    [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: 4
                                     yRadius: 4] stroke];
}

- (void) drawBoxWithBezelInRect: (NSRect) rect clipRect: (NSRect) clipRect {
    [[NSColor colorWithCalibratedWhite: 0.78 alpha: 1.0] setStroke];
    [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: 4
                                     yRadius: 4] stroke];
}

- (void) drawBoxWithGrooveInRect: (NSRect) rect clipRect: (NSRect) clipRect {
    [[NSColor colorWithCalibratedWhite: 0.78 alpha: 1.0] setStroke];
    [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: 4
                                     yRadius: 4] stroke];
}

@end

@implementation NSGraphicsStyle (NSComboBox)

- (void) drawComboBoxButtonInRect: (NSRect) rect
                          enabled: (BOOL) enabled
                         bordered: (BOOL) bordered
                          pressed: (BOOL) pressed
{
    NSImage *image = [NSImage imageNamed: @"NSComboBoxCellDown"];
    NSSize imageSize = [image size];
    NSRect imageRect;

    if (pressed)
        NSInterfaceDrawDepressedButton(rect, rect);
    else
        NSDrawButton(rect, rect);

    imageRect.origin.x = rect.origin.x +
                         (rect.size.width - imageSize.width) / 2 +
                         (pressed ? 1 : 0);
    imageRect.origin.y = rect.origin.y +
                         (rect.size.height - imageSize.height) / 2 +
                         (pressed ? -1 : 0);
    imageRect.size = imageSize;

    [self drawButtonImage: image inRect: imageRect enabled: enabled mixed: NO];
}

@end

@implementation NSGraphicsStyle (NSTabView)

- (void) drawTabInRect: (NSRect) rect
              clipRect: (NSRect) clipRect
                 color: (NSColor *) color
              selected: (BOOL) selected
{
    NSRect originalRect = rect;
    NSRect rects[8];
    NSColor *colors[8];
    int i;

    if (selected) {
        rect.origin.x -= 2;
        rect.size.width += 3;
    } else {
        rect.size.height -= 2;
    }

    for (i = 0; i < 8; i++)
        rects[i] = rect;

    colors[0] = [NSColor controlColor];
    if (selected) {
        rects[0].origin.y -= 1;
        rects[0].size.height += 1;
    }
    colors[1] = color;
    rects[1] = NSInsetRect(rect, 1, 1);
    colors[2] = [NSColor whiteColor];
    rects[2].size.width = 1;
    rects[2].size.height -= 2;
    if (selected) {
        rects[2].origin.y -= 1;
        rects[2].size.height += 1;
    }
    colors[3] = [NSColor whiteColor];
    rects[3].origin.x += 1;
    rects[3].origin.y += rect.size.height - 2;
    rects[3].size.width = 1;
    rects[3].size.height = 1;
    colors[4] = [NSColor whiteColor];
    rects[4].origin.x += 2;
    rects[4].origin.y += rect.size.height - 1;
    rects[4].size.width = rect.size.width - 4;
    rects[4].size.height = 1;
    colors[5] = [NSColor blackColor];
    rects[5].origin.x += rect.size.width - 2;
    rects[5].origin.y += rect.size.height - 2;
    rects[5].size.width = 1;
    rects[5].size.height = 1;
    colors[6] = [NSColor controlShadowColor];
    rects[6].origin.x += rect.size.width - 2;
    rects[6].size.width = 1;
    rects[6].size.height -= 2;
    colors[7] = [NSColor blackColor];
    rects[7].origin.x += rect.size.width - 1;
    rects[7].size.width = 1;
    rects[7].size.height -= 2;
    if (selected) {
        rects[7].origin.y -= 1;
        rects[7].size.height += 1;
    }

    for (i = 0; i < 8; i++) {
        [colors[i] setFill];
        NSRectFill(rects[i]);
    }

    if (selected) { // cleanup
        NSRect erase = originalRect;

        [[NSColor controlColor] setFill];
        erase.size.height = 2;
        erase = NSInsetRect(erase, 1, 0);
        NSRectFill(erase);
    }
}

- (void) drawTabPaneInRect: (NSRect) rect {
    NSDrawButton(rect, rect);
}

- (void) drawTabViewBackgroundInRect: (NSRect) rect {
    // do nothing
}

@end

@implementation NSGraphicsStyle (NSTextField)

- (void) drawTextFieldBorderInRect: (NSRect) rect
                    bezeledNotLine: (BOOL) bezeledNotLine
{
    [self drawTextFieldBorderInRect: rect bezeledNotLine: bezeledNotLine enabled: YES];
}

- (void) drawTextFieldBorderInRect: (NSRect) rect bezeledNotLine: (BOOL) bezeledNotLine enabled: (BOOL) enabled {
    if (bezeledNotLine) {
        // QUIRK: the bezel of a text field on macOS 10.14 (light appearance) is a white rectangle with a
        // one point outline of black at 20%, 10% when the field is disabled. Not documented. Evidence: black-box
        // renders of NSTextField on macOS 10.14.4 at 1x (tier 2), probe mac-probes/aqua-toolbar.m of the
        // research notes. Tests: appkit-textfield-aqua.m, appkit-toolbar-controls-aqua.m (test_quirk_field_bezels)
        [[NSColor whiteColor] setFill];
        NSRectFill(NSInsetRect(rect, 1, 1));
        // the outline is blended over what is under it (NSRectFill would replace the pixels, so that a window,
        // which has no transparency, showed the outline as solid black)
        [[NSColor colorWithCalibratedWhite: 0 alpha: enabled ? 0.2 : 0.1] setFill];
        NSRect outline[4] = {NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), 1),
                             NSMakeRect(NSMinX(rect), NSMaxY(rect) - 1, NSWidth(rect), 1),
                             NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, 1, NSHeight(rect) - 2),
                             NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect) + 1, 1, NSHeight(rect) - 2)};

        NSRectFillListUsingOperation(outline, 4, NSCompositeSourceOver);
    } else {
        [[NSColor blackColor] setStroke];
        NSFrameRect(rect);
    }
}

- (void) drawTextViewInsertionPointInRect: (NSRect) rect
                                    color: (NSColor *) color
{
    [color setFill];
    NSRectFill(rect);
}

@end

@implementation NSGraphicsStyle (NSTabViewAqua)

// QUIRK: the tab strip and box look of macOS 10.14 (light appearance). Not documented. Evidence: black-box
// renders of NSTabView on macOS 10.14.4 at 2x (tier 2): the box is a 4 point rounded rectangle
// filled with black at 4% and outlined with black at about 6%; the strip is a white 4 point rounded
// rectangle with a gray outline and a short shadow below it; the selected tab is a vertical gradient from
// (110,163,250) to (13,97,255) in an active window and light gray in an inactive one.
// Test: appkit-tabview-aqua.m
static const CGFloat NSAquaTabCornerRadius = 4;

static NSBezierPath *NSAquaRoundedPath(NSRect rect, CGFloat radius) {
    return [NSBezierPath bezierPathWithRoundedRect: rect xRadius: radius yRadius: radius];
}

- (void) drawTabViewBoxInRect: (NSRect) rect {
    NSBezierPath *path = NSAquaRoundedPath(NSInsetRect(rect, 0.5, 0.5), NSAquaTabCornerRadius);

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.04] setFill];
    [path fill];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.07] setStroke];
    [path setLineWidth: 1];
    [path stroke];
}

- (void) drawTabStripInRect: (NSRect) rect {
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.14] setFill];
    [NSAquaRoundedPath(NSOffsetRect(rect, 0, flipped ? 0.5 : -0.5), NSAquaTabCornerRadius) fill];
    [[NSColor whiteColor] setFill];
    [NSAquaRoundedPath(NSInsetRect(rect, 0.5, 0.5), NSAquaTabCornerRadius - 0.5) fill];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.2] setStroke];
    NSBezierPath *edge = NSAquaRoundedPath(NSInsetRect(rect, 0.5, 0.5), NSAquaTabCornerRadius - 0.5);
    [edge setLineWidth: 1];
    [edge stroke];
}

- (void) drawSelectedTabInRect: (NSRect) rect stripRect: (NSRect) stripRect active: (BOOL) active {
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat blue[8] = {110 / 255.0, 163 / 255.0, 250 / 255.0, 1, 13 / 255.0, 97 / 255.0, 1, 1};
    CGFloat gray[8] = {0.93, 0.93, 0.93, 1, 0.87, 0.87, 0.87, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, active ? blue : gray, NULL, 2);
    NSRect inner = NSInsetRect(stripRect, 0.5, 0.5);

    CGContextSaveGState(ctx);
    [NSAquaRoundedPath(inner, NSAquaTabCornerRadius - 0.5) addClip];
    CGContextClipToRect(ctx, NSIntersectionRect(rect, inner));
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0, flipped ? NSMinY(inner) : NSMaxY(inner)),
                                CGPointMake(0, flipped ? NSMaxY(inner) : NSMinY(inner)), 0);
    CGContextRestoreGState(ctx);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

- (void) drawTabDividerInRect: (NSRect) rect {
    [[NSColor colorWithCalibratedWhite: 0.898 alpha: 1] setFill];
    NSRectFill(rect);
}

@end

@implementation NSGraphicsStyle (NSButtonAqua)

// QUIRK: the check box and radio button look of macOS 10.14 (light appearance). Not documented.
// Evidence: black-box renders of NSButton on macOS 10.14.4 at 1x and 2x (tier 2). The box is 14, 12 or 10
// points (a radio button 16, 14 or 10) for the regular, small and mini control sizes; the off look is white
// with a gray outline and a short shade below the top edge; the on and mixed looks are a flat blue
// ((61,130,253), pressed (15,98,253)) with a white mark, and in a window that is not active the on and
// mixed looks are white with a dark mark.
// Test: appkit-button-aqua.m
static CGFloat NSAquaToggleBoxSize(BOOL radio, NSControlSize size) {
    static const CGFloat check[3] = {14, 12, 10}, round_[3] = {16, 14, 10};
    int index = size == NSSmallControlSize ? 1 : (size == NSMiniControlSize ? 2 : 0);

    return radio ? round_[index] : check[index];
}

static CGFloat NSAquaToggleBoxInset(BOOL radio, NSControlSize size) {
    static const CGFloat check[3] = {2, 3, 4}, round_[3] = {1, 2, 4};
    int index = size == NSSmallControlSize ? 1 : (size == NSMiniControlSize ? 2 : 0);

    return radio ? round_[index] : check[index];
}

/* Moves a rectangle's origin onto the device pixel grid (the transform is a scale and a translation
   there), so that the 1 point outlines of the controls are one crisp device pixel at 1x. */
static NSRect NSAquaSnapToDevicePixels(CGContextRef ctx, NSRect rect) {
    CGAffineTransform t = CGContextGetCTM(ctx);

    if (t.b != 0 || t.c != 0 || t.a == 0 || t.d == 0)
        return rect;
    rect.origin.x = (round(rect.origin.x * t.a + t.tx) - t.tx) / t.a;
    rect.origin.y = (round(rect.origin.y * t.d + t.ty) - t.ty) / t.d;
    return rect;
}

static void NSAquaDrawToggle(NSRect rect, BOOL radio, NSInteger state, BOOL highlighted, BOOL enabled,
                             BOOL active, NSControlSize controlSize)
{
    CGFloat size = NSAquaToggleBoxSize(radio, controlSize);
    NSRect box = NSMakeRect(NSMinX(rect) + NSAquaToggleBoxInset(radio, controlSize),
                            ceil(NSMidY(rect) - size / 2), size, size);
    box = NSAquaSnapToDevicePixels([[NSGraphicsContext currentContext] graphicsPort], box);
    NSBezierPath *outline = radio ? [NSBezierPath bezierPathWithOvalInRect: NSInsetRect(box, 0.5, 0.5)]
                                  : [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(box, 0.5, 0.5)
                                                                    xRadius: size * 3 / 14
                                                                    yRadius: size * 3 / 14];
    NSBezierPath *shape = radio ? [NSBezierPath bezierPathWithOvalInRect: box]
                                : [NSBezierPath bezierPathWithRoundedRect: box
                                                                  xRadius: size * 3.5 / 14
                                                                  yRadius: size * 3.5 / 14];
    BOOL blue = state != NSOffState && enabled && (active || highlighted);
    BOOL marked = state != NSOffState;
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];

    // a disabled control is drawn at half strength (explicitly: not every context honours a global alpha)
    CGFloat alpha = enabled ? 1 : 0.5;

    CGContextSaveGState(ctx);
    if (blue) {
        [highlighted ? [NSColor colorWithCalibratedRed: 15 / 255.0 green: 98 / 255.0 blue: 253 / 255.0 alpha: alpha]
                     : [NSColor colorWithCalibratedRed: 61 / 255.0 green: 130 / 255.0 blue: 253 / 255.0 alpha: alpha] setFill];
        [shape fill];
        [highlighted ? [NSColor colorWithCalibratedRed: 4 / 255.0 green: 89 / 255.0 blue: 253 / 255.0 alpha: alpha]
                     : [NSColor colorWithCalibratedRed: 46 / 255.0 green: 120 / 255.0 blue: 253 / 255.0 alpha: alpha] setStroke];
        [outline setLineWidth: 1];
        [outline stroke];
    } else {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat base = highlighted ? 0.94 : 1.0;
        CGFloat top = highlighted ? 0.86 : 0.95;
        CGFloat comps[8] = {top, top, top, alpha, base, base, base, alpha};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, NULL, 2);

        [[NSColor colorWithCalibratedWhite: base alpha: alpha] setFill];
        [shape fill];
        CGContextSaveGState(ctx);
        [shape addClip];
        // the shade below the top edge, which is its maximum y in this unflipped system
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, NSMaxY(box)),
                                    CGPointMake(0, NSMaxY(box) - size * 0.12), 0);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[NSColor colorWithCalibratedWhite: 0.68 alpha: alpha] setStroke];
        [outline setLineWidth: 1];
        [outline stroke];
    }

    if (marked) {
        NSColor *mark = blue ? [NSColor colorWithCalibratedWhite: 1 alpha: alpha]
                             : [NSColor colorWithCalibratedWhite: 0.25 alpha: alpha];
        CGFloat scale = size / 14.0;
        NSBezierPath *path = [NSBezierPath bezierPath];

        [mark setStroke];
        [mark setFill];
        if (radio) {
            CGFloat r = size * 2.5 / 16;
            [[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(NSMidX(box) - r, NSMidY(box) - r, 2 * r, 2 * r)] fill];
        } else {
            if (state == NSMixedState) {
                [path moveToPoint: NSMakePoint(NSMinX(box) + 3.5 * scale, NSMinY(box) + 7 * scale)];
                [path lineToPoint: NSMakePoint(NSMinX(box) + 10.5 * scale, NSMinY(box) + 7 * scale)];
            } else {
                [path moveToPoint: NSMakePoint(NSMinX(box) + 3.3 * scale, NSMinY(box) + 7.2 * scale)];
                [path lineToPoint: NSMakePoint(NSMinX(box) + 5.8 * scale, NSMinY(box) + 4.2 * scale)];
                [path lineToPoint: NSMakePoint(NSMinX(box) + 10.6 * scale, NSMinY(box) + 10.6 * scale)];
            }
            [path setLineWidth: MAX(1.2, 1.7 * scale)];
            [path setLineCapStyle: NSRoundLineCapStyle];
            [path setLineJoinStyle: NSRoundLineJoinStyle];
            [path stroke];
        }
    }
    CGContextRestoreGState(ctx);
}

- (void) drawCheckBoxInRect: (NSRect) rect
                      state: (NSInteger) state
                highlighted: (BOOL) highlighted
                    enabled: (BOOL) enabled
                     active: (BOOL) active
                controlSize: (NSControlSize) controlSize
{
    NSAquaDrawToggle(rect, NO, state, highlighted, enabled, active, controlSize);
}

- (void) drawRadioButtonInRect: (NSRect) rect
                         state: (NSInteger) state
                   highlighted: (BOOL) highlighted
                       enabled: (BOOL) enabled
                        active: (BOOL) active
                   controlSize: (NSControlSize) controlSize
{
    NSAquaDrawToggle(rect, YES, state, highlighted, enabled, active, controlSize);
}

- (NSBezierPath *) toggleBoxPathInRect: (NSRect) rect radio: (BOOL) radio controlSize: (NSControlSize) controlSize {
    CGFloat size = NSAquaToggleBoxSize(radio, controlSize);
    NSRect box = NSMakeRect(NSMinX(rect) + NSAquaToggleBoxInset(radio, controlSize),
                            ceil(NSMidY(rect) - size / 2), size, size);

    return radio ? [NSBezierPath bezierPathWithOvalInRect: box]
                 : [NSBezierPath bezierPathWithRoundedRect: box xRadius: size * 3.5 / 14 yRadius: size * 3.5 / 14];
}

@end

@implementation NSGraphicsStyle (NSPushButtonAqua)

// QUIRK: the rounded push button look of macOS 10.14 (light appearance). Not documented. Evidence:
// black-box renders of NSButton (rounded bezel) on macOS 10.14.4 at 1x (tier 2): the normal bezel is white
// with a black outline at about 18% and a one pixel shadow below; a default button in an active window is
// a vertical blue gradient from (107,161,250) to (17,100,255); a pressed button is a blue gradient from
// (76,139,253) to (15,88,231); a disabled button is the normal one at half strength.
// Test: appkit-button-aqua.m
- (void) drawPushButtonInRect: (NSRect) rect
                    defaulted: (BOOL) defaulted
                      pressed: (BOOL) pressed
                      enabled: (BOOL) enabled
                       active: (BOOL) active
{
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    NSRect body = NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, NSWidth(rect), NSHeight(rect) - 1);
    CGFloat radius = MIN(4.5, NSHeight(body) / 4.5);
    CGFloat alpha = enabled ? 1 : 0.5;
    BOOL blue = pressed || (defaulted && enabled && active);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 0.5, 0.5)
                                                            xRadius: radius
                                                            yRadius: radius];
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius];

    if (NSWidth(rect) < 2 || NSHeight(rect) < 4)
        return;

    // the shadow below the bezel
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.07 * alpha] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: NSOffsetRect(body, 0, -1) xRadius: radius yRadius: radius] fill];

    if (blue) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat normal[8] = {107 / 255.0, 161 / 255.0, 250 / 255.0, 1, 17 / 255.0, 100 / 255.0, 1, 1};
        CGFloat down[8] = {76 / 255.0, 139 / 255.0, 253 / 255.0, 1, 15 / 255.0, 88 / 255.0, 231 / 255.0, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, pressed ? down : normal, NULL, 2);

        CGContextSaveGState(ctx);
        [shape addClip];
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, NSMaxY(body)), CGPointMake(0, NSMinY(body)), 0);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[NSColor colorWithCalibratedRed: 0.1 green: 0.4 blue: 0.98 alpha: 0.7] setStroke];
    } else {
        // the edge is a translucent line over the background, so the white stops inside it
        [[NSColor colorWithCalibratedWhite: 1 alpha: alpha] setFill];
        [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 1, 1)
                                         xRadius: MAX(radius - 1, 0)
                                         yRadius: MAX(radius - 1, 0)] fill];
        [[NSColor colorWithCalibratedWhite: 0 alpha: 0.18 * alpha] setStroke];
    }
    [outline setLineWidth: 1];
    [outline stroke];
}

@end

@implementation NSGraphicsStyle (NSPopUpButtonAqua)

// QUIRK: the pop-up and pull-down button look of macOS 10.14 (light appearance). Not documented.
// Evidence: black-box renders of NSPopUpButton on macOS 10.14.4 at 1x and 2x (tier 2): the bezel is the
// white push button bezel with an end cap on the right that is 16, 14 and 12 points wide for the regular,
// small and mini control sizes, filled like a default push button (a pressed one like a pressed button),
// holding two white chevrons (one down chevron for a pull-down); a disabled button is white at half
// strength with gray chevrons, and the cap is not blue in a window that is not active.
// Test: appkit-popup-aqua.m
- (void) drawPopUpButtonInRect: (NSRect) rect
                     pullsDown: (BOOL) pullsDown
                       pressed: (BOOL) pressed
                       enabled: (BOOL) enabled
                        active: (BOOL) active
                   controlSize: (NSControlSize) controlSize
{
    static const CGFloat capWidths[3] = {16, 14, 12};
    int index = controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0);
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    NSRect body = NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, NSWidth(rect), NSHeight(rect) - 1);
    CGFloat radius = MIN(4.5, NSHeight(body) / 4.5);
    CGFloat capWidth = capWidths[index];
    NSRect cap = NSMakeRect(NSMaxX(body) - capWidth, NSMinY(body), capWidth, NSHeight(body));
    BOOL blue = enabled && (active || pressed);

    [self drawPushButtonInRect: rect defaulted: NO pressed: NO enabled: enabled active: active];
    if (blue) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat normal[8] = {110 / 255.0, 163 / 255.0, 250 / 255.0, 1, 13 / 255.0, 97 / 255.0, 1, 1};
        CGFloat down[8] = {76 / 255.0, 139 / 255.0, 253 / 255.0, 1, 15 / 255.0, 88 / 255.0, 231 / 255.0, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, pressed ? down : normal, NULL, 2);

        CGContextSaveGState(ctx);
        [[NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius] addClip];
        CGContextClipToRect(ctx, cap);
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, NSMaxY(body)), CGPointMake(0, NSMinY(body)), 0);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }

    NSColor *mark = blue ? [NSColor whiteColor]
                         : [NSColor colorWithCalibratedWhite: 0 alpha: enabled ? 0.55 : 0.3];
    CGFloat scale = capWidth / 16.5;
    CGFloat cx = NSMidX(cap), cy = NSMidY(cap) + 0.5;
    NSBezierPath *chevrons = [NSBezierPath bezierPath];

    if (!pullsDown) {
        [chevrons moveToPoint: NSMakePoint(cx - 3.2 * scale, cy + 2.2 * scale)];
        [chevrons lineToPoint: NSMakePoint(cx, cy + 5.4 * scale)];
        [chevrons lineToPoint: NSMakePoint(cx + 3.2 * scale, cy + 2.2 * scale)];
    }
    CGFloat down = pullsDown ? 0 : -2.2 * scale;
    [chevrons moveToPoint: NSMakePoint(cx - 3.2 * scale, cy + down + (pullsDown ? 1.6 : 0) * scale)];
    [chevrons lineToPoint: NSMakePoint(cx, cy + down - (pullsDown ? 1.6 : 3.2) * scale)];
    [chevrons lineToPoint: NSMakePoint(cx + 3.2 * scale, cy + down + (pullsDown ? 1.6 : 0) * scale)];
    [mark setStroke];
    [chevrons setLineWidth: MAX(1.2, 1.5 * scale)];
    [chevrons setLineCapStyle: NSRoundLineCapStyle];
    [chevrons setLineJoinStyle: NSRoundLineJoinStyle];
    [chevrons stroke];
}

@end

@implementation NSGraphicsStyle (NSBoxAqua)

// QUIRK: the box look of macOS 10.14 (light appearance), the same for primary and secondary boxes. Not
// documented. Evidence: black-box renders of NSBox on macOS 10.14.4 at 1x and 2x (tier 2): a 4 point
// rounded rectangle filled with black at 4% and outlined with black at about 6% (about 10% along the top
// edge), inset 3 points from the sides of the view. Test: appkit-box-aqua.m
- (void) drawAquaBoxInRect: (NSRect) rect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(rect, 0.5, 0.5) xRadius: 4 yRadius: 4];

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.04] setFill];
    [path fill];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.07] setStroke];
    [path setLineWidth: 1];
    [path stroke];
}

@end

@implementation NSGraphicsStyle (NSSearchFieldAqua)

// QUIRK: the rounded text field and search field look of macOS 10.14 (light appearance): a white rounded
// rectangle with a 4 point radius and a one point outline of black at 20% (10% when disabled); a search field has
// a dark gray magnifying glass at its left and, when it has text, a disc of black at 50% with a white cross at its
// right. The glyphs are smaller at the small and mini control sizes. Not documented. Evidence: black-box renders of
// NSSearchField and NSTextField on macOS 10.14.4 at 1x (tier 2), probes mac-probes/aqua-toolbar.m and
// aqua-toolbar-2.m of the research notes.
// Tests: appkit-textfield-aqua.m, appkit-toolbar-controls-aqua.m (test_quirk_field_bezels, test_quirk_search_glyphs)
- (void) drawRoundedTextFieldBezelInRect: (NSRect) rect radius: (CGFloat) radius {
    [self drawRoundedTextFieldBezelInRect: rect radius: radius enabled: YES];
}

- (void) drawRoundedTextFieldBezelInRect: (NSRect) rect radius: (CGFloat) radius enabled: (BOOL) enabled {
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(rect, 0.5, 0.5)
                                                            xRadius: radius - 0.5
                                                            yRadius: radius - 0.5];

    // the edge is a translucent line over the background, so the white stops inside it
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(rect, 1, 1) xRadius: MAX(radius - 1, 0)
                                     yRadius: MAX(radius - 1, 0)] fill];
    [[NSColor colorWithCalibratedWhite: 0 alpha: enabled ? 0.2 : 0.1] setStroke];
    [outline setLineWidth: 1];
    [outline stroke];
}

static int NSAquaSizeIndex(NSControlSize controlSize) {
    return controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0);
}

- (void) drawSearchGlyphInRect: (NSRect) rect {
    [self drawSearchGlyphInRect: rect controlSize: NSRegularControlSize];
}

- (void) drawSearchGlyphInRect: (NSRect) rect controlSize: (NSControlSize) controlSize {
    // the radius of the ring (to the middle of its line), how far its centre is above the middle of the rect,
    // and how far the end of the handle is from the centre, for the regular, small and mini sizes
    static const CGFloat radii[3] = {4.5, 3.5, 2.5}, raise[3] = {1, 0.5, 0.5}, reach[3] = {9.4, 8.1, 5.5};
    int index = NSAquaSizeIndex(controlSize);
    // "down" is the direction of increasing y when looking at the glyph: +1 in a flipped coordinate system
    CGFloat down = [[NSGraphicsContext currentContext] isFlipped] ? 1 : -1;
    CGFloat r = radii[index];
    NSPoint center = NSMakePoint(NSMinX(rect) + 7, NSMidY(rect) - down * raise[index]);
    NSBezierPath *glass = [NSBezierPath bezierPathWithOvalInRect: NSMakeRect(center.x - r, center.y - r, 2 * r, 2 * r)];
    NSBezierPath *handle = [NSBezierPath bezierPath];
    CGFloat start = (r + 0.5) * M_SQRT1_2, end = reach[index] * M_SQRT1_2;

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.7] setStroke];
    [glass setLineWidth: 1];
    [glass stroke];
    [handle moveToPoint: NSMakePoint(center.x + start, center.y + down * start)];
    [handle lineToPoint: NSMakePoint(center.x + end, center.y + down * end)];
    [handle setLineWidth: index == 0 ? 1.5 : 1.2];
    [handle setLineCapStyle: NSButtLineCapStyle];
    [handle stroke];
}

- (void) drawSearchCancelGlyphInRect: (NSRect) rect {
    [self drawSearchCancelGlyphInRect: rect controlSize: NSRegularControlSize];
}

- (void) drawSearchCancelGlyphInRect: (NSRect) rect controlSize: (NSControlSize) controlSize {
    static const CGFloat diameters[3] = {14, 11, 9};
    int index = NSAquaSizeIndex(controlSize);
    CGFloat d = MIN(diameters[index], MIN(NSWidth(rect), NSHeight(rect)));
    NSRect disc = NSMakeRect(NSMidX(rect) - d / 2, NSMidY(rect) - d / 2, d, d);
    NSBezierPath *cross = [NSBezierPath bezierPath];
    CGFloat r = d * 3 / 14;

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.5] setFill];
    [[NSBezierPath bezierPathWithOvalInRect: disc] fill];
    [cross moveToPoint: NSMakePoint(NSMidX(disc) - r, NSMidY(disc) - r)];
    [cross lineToPoint: NSMakePoint(NSMidX(disc) + r, NSMidY(disc) + r)];
    [cross moveToPoint: NSMakePoint(NSMidX(disc) - r, NSMidY(disc) + r)];
    [cross lineToPoint: NSMakePoint(NSMidX(disc) + r, NSMidY(disc) - r)];
    [[NSColor whiteColor] setStroke];
    [cross setLineWidth: MAX(1, 1.25 * d / 14)];
    [cross setLineCapStyle: NSButtLineCapStyle];
    [cross stroke];
}

@end

@implementation NSGraphicsStyle (NSTexturedControlsAqua)

// QUIRK: the textured button look of macOS 10.14 (light appearance), shared by textured segmented controls and
// textured pop-up buttons. The bezel is a rounded rectangle (radius 5, 4.5 for the mini size and for the textured
// square style) with a one point outline of black at 8% (17% along the bottom), filled with a light gradient
// (white 254 to 246 at 90% opacity) under a white top line. Pressed, the fill is darker (229 to 222) under a 239
// line. In the on state the bezel is black at 50% to 52% opacity with its outline at 52%, pressed 60% and 62%.
// Disabled buttons and buttons in a window that is not key keep the bezel. Not documented. Evidence: black-box
// renders of NSButton, NSSegmentedControl and NSPopUpButton on macOS 10.14.4 at 1x (tier 2), probes
// mac-probes/aqua-toolbar.m and aqua-toolbar-2.m of the research notes.
// Test: appkit-toolbar-controls-aqua.m (test_quirk_textured_bezel, test_quirk_textured_segments)
static NSRect NSAquaTexturedBody(NSRect rect, BOOL square) {
    if (square)
        return NSMakeRect(NSMinX(rect) + 1, NSMinY(rect) + 2, NSWidth(rect) - 2, NSHeight(rect) - 3);
    return NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, NSWidth(rect), NSHeight(rect) - 1);
}

- (NSRect) texturedBezelInteriorForRect: (NSRect) rect square: (BOOL) square {
    NSRect body = NSAquaTexturedBody(rect, square);

    return NSInsetRect(body, 0, 1);
}

static void NSAquaFillGradient(NSBezierPath *path, NSRect rect, const CGFloat *top, const CGFloat *bottom) {
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[8] = {top[0], top[0], top[0], top[1], bottom[0], bottom[0], bottom[0], bottom[1]};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);

    CGContextSaveGState(ctx);
    [path addClip];
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, NSMaxY(rect)), CGPointMake(0, NSMinY(rect)), 0);
    CGContextRestoreGState(ctx);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

- (void) drawTexturedBezelInRect: (NSRect) rect
                          square: (BOOL) square
                         pressed: (BOOL) pressed
                              on: (BOOL) on
                     controlSize: (NSControlSize) controlSize
{
    NSRect body = NSAquaTexturedBody(rect, square);
    CGFloat radius = (square || controlSize == NSMiniControlSize) ? 4.5 : 5;
    radius = MIN(radius, MIN(NSWidth(body), NSHeight(body)) / 2);
    NSRect inner = NSInsetRect(body, 1, 1);
    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius];
    NSBezierPath *innerPath = [NSBezierPath bezierPathWithRoundedRect: inner
                                                              xRadius: MAX(radius - 1, 0)
                                                              yRadius: MAX(radius - 1, 0)];
    NSBezierPath *ring = [NSBezierPath bezierPath];
    // fill colours as (white, alpha) at the top and the bottom of the inner area
    CGFloat normalTop[2] = {254 / 255.0, 0.9}, normalBottom[2] = {246 / 255.0, 0.906};
    CGFloat pressedTop[2] = {229 / 255.0, 0.91}, pressedBottom[2] = {222 / 255.0, 0.914};
    CGFloat onTop[2] = {0, 0.5}, onBottom[2] = {0, 0.52};
    CGFloat onPressedTop[2] = {0, 0.6}, onPressedBottom[2] = {0, 0.61};
    CGFloat outline = on ? (pressed ? 0.62 : 0.52) : 0.08;

    if (NSWidth(body) < 2 || NSHeight(body) < 2)
        return;

    [ring appendBezierPath: outer];
    [ring appendBezierPath: innerPath];
    [ring setWindingRule: NSEvenOddWindingRule];
    [[NSColor colorWithCalibratedWhite: 0 alpha: outline] setFill];
    [ring fill];

    if (on)
        NSAquaFillGradient(innerPath, inner, pressed ? onPressedTop : onTop, pressed ? onPressedBottom : onBottom);
    else
        NSAquaFillGradient(innerPath, inner, pressed ? pressedTop : normalTop, pressed ? pressedBottom : normalBottom);

    [NSGraphicsContext saveGraphicsState];
    [outer addClip];
    if (!on) {
        // the light line along the top of the inner area
        [[NSColor colorWithCalibratedWhite: pressed ? 239 / 255.0 : 1 alpha: pressed ? 0.94 : 1] setFill];
        [[NSBezierPath bezierPathWithRect: NSMakeRect(NSMinX(inner), NSMaxY(inner) - 1, NSWidth(inner), 1)] fill];
    }
    // the bottom outline line is darker
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.1] setFill];
    [[NSBezierPath bezierPathWithRect: NSMakeRect(NSMinX(body), NSMinY(body), NSWidth(body), 1)] fill];
    [NSGraphicsContext restoreGraphicsState];
}

// QUIRK: a textured segmented control draws one textured bezel across its segments; between two segments a one
// point line of black at 10% runs across the inner area, and a selected segment of a control that selects one
// segment shows the dark on look with such a line along both of its edges inside it. Evidence and test as for
// -drawTexturedBezelInRect:square:pressed:on:controlSize:.
- (void) drawTexturedSegmentSeparatorInRect: (NSRect) rect {
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.1] setFill];
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

// QUIRK: a recessed button on macOS 10.14 (light appearance) is a rounded rectangle (radius 4, 3 at the mini size)
// of a near black at 32% opacity, 37% in the on state and 49% while pressed, and draws no bezel when disabled; a
// round-rect button is a one point outline (radius 4.5 outside) of black at 30% (15% disabled), with black at 10%
// inside when on or pressed. Not documented. Evidence: black-box renders of NSButton on macOS 10.14.4 at 1x (tier 2),
// probes mac-probes/aqua-toolbar.m and aqua-toolbar-2.m of the research notes.
// Test: appkit-toolbar-controls-aqua.m (test_quirk_recessed_bezel, test_quirk_round_rect_bezel)
- (void) drawRecessedBezelInRect: (NSRect) rect
                         pressed: (BOOL) pressed
                              on: (BOOL) on
                     controlSize: (NSControlSize) controlSize
{
    NSRect body = NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, NSWidth(rect), NSHeight(rect) - 1);
    CGFloat radius = MIN(controlSize == NSMiniControlSize ? 3 : 4, MIN(NSWidth(body), NSHeight(body)) / 2);
    CGFloat gray = pressed ? 2 / 255.0 : (on ? 5 / 255.0 : 12 / 255.0);
    CGFloat alpha = pressed ? 0.49 : (on ? 0.37 : 0.32);

    [[NSColor colorWithCalibratedWhite: gray alpha: alpha] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius] fill];
}

- (void) drawRoundRectBezelInRect: (NSRect) rect filled: (BOOL) filled enabled: (BOOL) enabled {
    NSRect body = NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, NSWidth(rect), NSHeight(rect) - 1);
    CGFloat radius = MIN(4.5, MIN(NSWidth(body), NSHeight(body)) / 2);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 0.5, 0.5)
                                                            xRadius: MAX(radius - 0.5, 0)
                                                            yRadius: MAX(radius - 0.5, 0)];

    if (NSWidth(body) < 3 || NSHeight(body) < 3)
        return;
    if (filled) {
        [[NSColor colorWithCalibratedWhite: 0 alpha: 0.1] setFill];
        [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 1, 1)
                                         xRadius: MAX(radius - 1, 0)
                                         yRadius: MAX(radius - 1, 0)] fill];
    }
    [[NSColor colorWithCalibratedWhite: 0 alpha: enabled ? 0.3 : 0.15] setStroke];
    [outline setLineWidth: 1];
    [outline stroke];
}

// QUIRK: a textured pop-up button shows two dark chevrons (up over down) near its right edge and a pull-down one
// down chevron, in the colour of the title (black at 65%, 30% disabled), on the textured bezel. The chevrons are
// centred 8.5, 7.5 and 6.5 points from the right edge (regular, small, mini), 6 points wide (4 for a mini pop-up),
// 3 points high (2), and 2.5, 1.5 and 2 points above and below the middle; a pull-down chevron is centred on the
// middle. Not documented. Evidence: black-box renders of NSPopUpButton with the textured rounded bezel style on
// macOS 10.14.4 at 1x (tier 2), probe mac-probes/aqua-toolbar.m of the research notes.
// Test: appkit-toolbar-controls-aqua.m (test_quirk_textured_popup)
- (void) drawTexturedPopUpArrowsInRect: (NSRect) rect
                             pullsDown: (BOOL) pullsDown
                               enabled: (BOOL) enabled
                           controlSize: (NSControlSize) controlSize
{
    static const CGFloat fromRight[3] = {8.5, 7.5, 6.5}, gap[3] = {2.5, 1.5, 2};
    int index = NSAquaSizeIndex(controlSize);
    NSRect body = NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, NSWidth(rect), NSHeight(rect) - 1);
    CGFloat cx = NSMaxX(body) - fromRight[index], cy = NSMidY(body);
    CGFloat half = (!pullsDown && index == 2) ? 2 : 3, height = (!pullsDown && index == 2) ? 2 : 3;
    NSBezierPath *chevrons = [NSBezierPath bezierPath];

    if (pullsDown) {
        [chevrons moveToPoint: NSMakePoint(cx - half, cy + height / 2)];
        [chevrons lineToPoint: NSMakePoint(cx, cy - height / 2)];
        [chevrons lineToPoint: NSMakePoint(cx + half, cy + height / 2)];
    } else {
        [chevrons moveToPoint: NSMakePoint(cx - half, cy + gap[index])];
        [chevrons lineToPoint: NSMakePoint(cx, cy + gap[index] + height)];
        [chevrons lineToPoint: NSMakePoint(cx + half, cy + gap[index])];
        [chevrons moveToPoint: NSMakePoint(cx - half, cy - gap[index])];
        [chevrons lineToPoint: NSMakePoint(cx, cy - gap[index] - height)];
        [chevrons lineToPoint: NSMakePoint(cx + half, cy - gap[index])];
    }
    [[NSColor colorWithCalibratedWhite: 0 alpha: enabled ? 0.65 : 0.3] setStroke];
    [chevrons setLineWidth: 1.1];
    [chevrons setLineCapStyle: NSRoundLineCapStyle];
    [chevrons setLineJoinStyle: NSMiterLineJoinStyle];
    [chevrons stroke];
}

@end

@implementation NSGraphicsStyle (NSSliderAqua)

// QUIRK: the slider look of macOS 10.14 (light appearance). Not documented. Evidence: black-box renders of
// NSSlider on macOS 10.14.4 at 1x and 2x (tier 2): a track 3 points thick inset 3 points from the ends of the
// view, rounded, blue (61,130,253) from the start to the knob and black at 22% after it; a white round knob,
// 15, 11 and 9 points across for the three control sizes, with a thin dark outline and a shadow below.
// Test: appkit-slider-aqua.m
- (void) drawAquaSliderTrackInRect: (NSRect) rect
                          vertical: (BOOL) vertical
                           knobRect: (NSRect) knobRect
                           enabled: (BOOL) enabled
                            active: (BOOL) active
                           flipped: (BOOL) flipped
{
    NSRect track;
    CGFloat alpha = enabled ? 1 : 0.5;

    if (vertical)
        track = NSMakeRect(floor(NSMidX(rect) - 1.5), NSMinY(rect) + 3, 3, NSHeight(rect) - 6);
    else
        // half a point is rounded towards the top of the view
        track = NSMakeRect(NSMinX(rect) + 3, flipped ? floor(NSMidY(rect) - 1.5) : ceil(NSMidY(rect) - 1.5),
                           NSWidth(rect) - 6, 3);

    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect: track xRadius: 1.5 yRadius: 1.5];

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.22 * alpha] setFill];
    [shape fill];

    NSRect fill = track;
    if (vertical) {
        // the minimum is at the bottom of an unflipped view and at the top of a flipped one in the
        // cell's own geometry; the fill runs from the end that holds the minimum to the knob
        CGFloat y = NSMidY(knobRect);
        if (flipped)
            fill.size.height = MAX(0, MIN(NSHeight(track), NSMaxY(track) - y));
        else
            fill.size.height = MAX(0, MIN(NSHeight(track), y - NSMinY(track)));
        if (flipped)
            fill.origin.y = NSMaxY(track) - fill.size.height;
    } else
        fill.size.width = MAX(0, MIN(NSWidth(track), NSMidX(knobRect) - NSMinX(track)));
    if (NSWidth(fill) > 0 && NSHeight(fill) > 0) {
        BOOL blue = enabled && active;

        [(blue ? [NSColor colorWithCalibratedRed: 61 / 255.0 green: 130 / 255.0 blue: 253 / 255.0 alpha: 1]
               : [NSColor colorWithCalibratedWhite: 0.55 alpha: alpha]) setFill];
        [[NSBezierPath bezierPathWithRoundedRect: fill xRadius: 1.5 yRadius: 1.5] fill];
    }
}

- (void) drawAquaSliderKnobInRect: (NSRect) rect controlSize: (NSControlSize) controlSize enabled: (BOOL) enabled {
    static const CGFloat insets[3] = {3, 2, 1.5};
    int index = controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0);
    CGFloat alpha = enabled ? 1 : 0.5;
    NSRect circle = NSInsetRect(rect, insets[index], insets[index]);
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];

    // a soft shadow below, then the white disc and its outline
    for (int i = 3; i >= 1; i--) {
        [[NSColor colorWithCalibratedWhite: 0 alpha: 0.05 * alpha] setFill];
        [[NSBezierPath bezierPathWithOvalInRect: NSOffsetRect(NSInsetRect(circle, -i * 0.4, -i * 0.4), 0, flipped ? 0.8 : -0.8)] fill];
    }
    [[NSColor colorWithCalibratedWhite: 1 alpha: alpha] setFill];
    [[NSBezierPath bezierPathWithOvalInRect: circle] fill];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.28 * alpha] setStroke];
    NSBezierPath *outline = [NSBezierPath bezierPathWithOvalInRect: NSInsetRect(circle, 0.5, 0.5)];
    [outline setLineWidth: 1];
    [outline stroke];
}

@end

@implementation NSGraphicsStyle (NSStepperAqua)

// QUIRK: the stepper look of macOS 10.14 (light appearance). Not documented. Evidence: black-box renders of
// NSStepper on macOS 10.14.4 at 1x and 2x (tier 2): one white capsule (13, 11 and 9 points wide and 21, 18 and
// 14 high for the control sizes) with a gray outline and a short shadow below, and a dark gray up and down
// chevron; the capsule is inset 3, 2 and 2 points from the sides of the 19, 15 and 13 point wide view.
// Test: appkit-stepper-aqua.m
- (void) drawAquaStepperInRect: (NSRect) rect
                       enabled: (BOOL) enabled
                 upHighlighted: (BOOL) upHighlighted
               downHighlighted: (BOOL) downHighlighted
{
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    CGFloat alpha = enabled ? 1 : 0.5;
    // the capsule without its shadow row; the shadow is below it
    NSRect body = NSMakeRect(NSMinX(rect), flipped ? NSMinY(rect) : NSMinY(rect) + 1, NSWidth(rect), NSHeight(rect) - 1);
    CGFloat radius = NSWidth(body) / 2;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius];
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 0.5, 0.5)
                                                            xRadius: radius - 0.5
                                                            yRadius: radius - 0.5];

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.07 * alpha] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: NSOffsetRect(body, 0, flipped ? 1 : -1) xRadius: radius yRadius: radius] fill];
    [[NSColor colorWithCalibratedWhite: 1 alpha: alpha] setFill];
    [shape fill];
    if (upHighlighted || downHighlighted) {
        // the pressed half is light gray: its half of the capsule, without the rounded corners cut off
        NSRect half = NSMakeRect(NSMinX(body), NSMinY(body), NSWidth(body), NSHeight(body) / 2);
        BOOL halfAtMinY = upHighlighted == flipped;

        if (!halfAtMinY)
            half.origin.y = NSMidY(body);
        [[NSColor colorWithCalibratedWhite: 0.87 alpha: alpha] setFill];
        [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(half, 1, 0.5) xRadius: radius - 1 yRadius: MIN(radius - 1, NSHeight(half) / 2)] fill];
    }
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.25 * alpha] setStroke];
    [outline setLineWidth: 1];
    [outline stroke];

    // the chevrons, a quarter and three quarters of the way down the capsule
    CGFloat w = MAX(2.6, NSWidth(body) * 0.22), h = MAX(1.8, NSWidth(body) * 0.16);
    NSBezierPath *chevrons = [NSBezierPath bezierPath];

    CGFloat upDirection = flipped ? -1 : 1; // the direction of "up" along y

    for (int i = 0; i < 2; i++) {
        BOOL up = i == 0;
        CGFloat fraction = up ? 0.27 : 0.73; // of the height, from the top
        CGFloat y = flipped ? NSMinY(body) + NSHeight(body) * fraction : NSMaxY(body) - NSHeight(body) * fraction;
        CGFloat tip = h * (up ? upDirection : -upDirection);

        [chevrons moveToPoint: NSMakePoint(NSMidX(body) - w, y - tip / 2)];
        [chevrons lineToPoint: NSMakePoint(NSMidX(body), y + tip / 2)];
        [chevrons lineToPoint: NSMakePoint(NSMidX(body) + w, y - tip / 2)];
    }
    [[NSColor colorWithCalibratedWhite: 0.25 alpha: alpha] setStroke];
    [chevrons setLineWidth: 1.4];
    [chevrons setLineCapStyle: NSRoundLineCapStyle];
    [chevrons setLineJoinStyle: NSRoundLineJoinStyle];
    [chevrons stroke];
}

@end

@implementation NSView (NSGraphicsStyle)

- (NSGraphicsStyle *) graphicsStyle {
    return [[[NSGraphicsStyle alloc] initWithView: self] autorelease];
}

@end
