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
#import <AppKit/NSAppearance.h>
#import <AppKit/NSWindow.h>

/* Whether the control being drawn takes the dark look: the drawing appearance (set from the view's effective
   appearance while it displays) is DarkAqua or one derived from it. */
static BOOL NSAquaDrawsDark(void) {
    NSAppearanceName name = [[NSAppearance currentDrawingAppearance]
        bestMatchFromAppearancesWithNames: [NSArray arrayWithObjects: NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]];

    return [name isEqualToString: NSAppearanceNameDarkAqua];
}

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
// Space between the arrow and the right edge of the menu.
#define BRANCH_ARROW_RIGHT_MARGIN 14

- (NSInterfacePartAttributedString *) branchArrow {
    static NSInterfacePartAttributedString *sBranchArrow = nil;

    if (sBranchArrow == nil)
        sBranchArrow = [[NSInterfacePartAttributedString alloc]
                initWithMarlettCharacter: 0x34];
    return sBranchArrow;
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
    // The state mark is an image (a template, drawn in the text colour), 16 points square.
    return NSMakeSize(16, 16);
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
    [self drawMenuStateImage: [NSImage imageNamed: @"NSMenuCheckmark"]
                      inRect: rect
                     enabled: enabled
                    selected: selected];
}

// Draws the image of a menu item's state (NSMenuItem onStateImage, mixedStateImage or offStateImage). A template
// image is filled with the text colour of the item; any other image is drawn as it is.
- (void) drawMenuStateImage: (NSImage *) image
                     inRect: (NSRect) rect
                    enabled: (BOOL) enabled
                   selected: (BOOL) selected
{
    if (image == nil)
        return;

    NSColor *color;
    if (enabled)
        color = selected ? [NSColor selectedMenuItemTextColor] : [NSColor menuItemTextColor];
    else
        color = [NSColor disabledControlTextColor];

    NSSize size = [image size];
    NSRect imageRect = NSMakeRect(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2, size.width,
                                  size.height);
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];

    if (![image isTemplate]) {
        [image drawInRect: imageRect
                 fromRect: NSZeroRect
                operation: NSCompositeSourceOver
                 fraction: enabled ? 1.0 : 0.5
           respectFlipped: YES
                    hints: nil];
        return;
    }

    NSRect proposed = NSMakeRect(0, 0, size.width, size.height);
    CGImageRef mask = [image CGImageForProposedRect: &proposed context: nil hints: nil];
    if (mask == NULL)
        return;

    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, imageRect.origin.x, imageRect.origin.y);
    if (flipped) {
        CGContextTranslateCTM(context, 0, size.height);
        CGContextScaleCTM(context, 1, -1);
    }
    CGRect maskRect = CGRectMake(0, 0, size.width, size.height);
    CGContextClipToMask(context, maskRect, mask);
    CGContextSetFillColorWithColor(context, [[color colorUsingColorSpaceName: NSCalibratedRGBColorSpace] CGColor]);
    CGContextFillRect(context, maskRect);
    CGContextRestoreGState(context);
}

- (void) drawMenuBranchArrowInRect: (NSRect) rect
                           enabled: (BOOL) enabled
                          selected: (BOOL) selected
{
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    NSColor *color;
    NSRect themeRect = rect;

    if (enabled)
        color = selected ? [NSColor selectedMenuItemTextColor]
                         : [NSColor menuItemTextColor];
    else
        color = [NSColor disabledControlTextColor];

    [color set];

    // The rectangle is the arrow itself (menuItemBranchArrowSize); the space
    // around it is the caller's layout. Taking the margins off a rectangle of
    // that size left a sliver one point wide.

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

// A button without a border has no bezel to emphasise, so nothing is drawn for it, whether or not it is the
// window default button cell (a check box or radio button that is the default cell looks as it does otherwise).
// Observed on macOS 10.14.4 and 26.7.3: the renderings with and without the cell being the default are identical.
- (void) drawUnborderedButtonInRect: (NSRect) rect defaulted: (BOOL) defaulted {
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

// QUIRK: the colour well of macOS 10.14 (light appearance). Not documented. Evidence: black-box renders of
// NSColorWell on macOS 10.14.4 at 1x (tier 2): a bordered well is a square bezel with a 1 point gray (175) outline
// around a vertical gradient from 227 at the top through 240 halfway to 247 at the bottom, and the swatch is inset 6 points inside a 1
// point gray (138) frame; a disabled well has the bezel at half opacity and a lighter (168) frame. A borderless well
// has a 1 point frame, 142 along the top and 190 elsewhere, and the swatch 2 points inside. The well looks the same
// while it is active. Test: test_quirk_color_well in tests/appkit-small-controls-aqua.m
- (NSRect) drawColorWellBorderInRect: (NSRect) rect
                             enabled: (BOOL) enabled
                            bordered: (BOOL) bordered
                              active: (BOOL) active
{
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    // edges on the screen
    NSRect top = NSMakeRect(NSMinX(rect), flipped ? NSMinY(rect) : NSMaxY(rect) - 1, NSWidth(rect), 1);
    NSRect bottom = NSMakeRect(NSMinX(rect), flipped ? NSMaxY(rect) - 1 : NSMinY(rect), NSWidth(rect), 1);
    NSRect left = NSMakeRect(NSMinX(rect), NSMinY(rect), 1, NSHeight(rect));
    NSRect right = NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect), 1, NSHeight(rect));

    if (!bordered) {
        [[NSColor colorWithCalibratedWhite: 190 / 255.0 alpha: 1] setFill];
        NSRectFill(left);
        NSRectFill(right);
        NSRectFill(bottom);
        [[NSColor colorWithCalibratedWhite: 142 / 255.0 alpha: 1] setFill];
        NSRectFill(top);
        return NSInsetRect(rect, 2, 2);
    }

    CGFloat alpha = enabled ? 1 : 0.5;
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    NSRect inside = NSInsetRect(rect, 1, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGFloat comps[6] = {227 / 255.0, alpha, 240 / 255.0, alpha, 247 / 255.0, alpha};
    CGFloat locations[3] = {0, 0.5, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, locations, 3);
    // from the centre of the top row to the centre of the bottom row of the inside, on the screen
    CGFloat yTop = flipped ? NSMinY(inside) + 0.5 : NSMaxY(inside) - 0.5;
    CGFloat yBottom = flipped ? NSMaxY(inside) - 0.5 : NSMinY(inside) + 0.5;

    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, inside);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, yTop), CGPointMake(0, yBottom),
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(ctx);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    [[NSColor colorWithCalibratedWhite: 175 / 255.0 alpha: alpha] setFill];
    NSRectFillUsingOperation(top, NSCompositeSourceOver);
    NSRectFillUsingOperation(bottom, NSCompositeSourceOver);
    NSRectFillUsingOperation(NSInsetRect(left, 0, 1), NSCompositeSourceOver);
    NSRectFillUsingOperation(NSInsetRect(right, 0, 1), NSCompositeSourceOver);

    NSRect frame = NSInsetRect(rect, 5, 5);
    [[NSColor colorWithCalibratedWhite: (enabled ? 138 : 168) / 255.0 alpha: 1] setFill];
    NSRectFill(NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), 1));
    NSRectFill(NSMakeRect(NSMinX(frame), NSMaxY(frame) - 1, NSWidth(frame), 1));
    NSRectFill(NSMakeRect(NSMinX(frame), NSMinY(frame), 1, NSHeight(frame)));
    NSRectFill(NSMakeRect(NSMaxX(frame) - 1, NSMinY(frame), 1, NSHeight(frame)));
    return NSInsetRect(rect, 6, 6);
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
    // QUIRK: the filled part ends at floor(view width * fraction) counted from the left edge of the view (the
    // bar itself starts 1 point in), so it is floor(width * fraction) - 1 points wide, never negative and at
    // most the bar's width: nothing is drawn below about 1/width, a full value fills the bar with its rounded
    // ends, and no thin sliver is drawn (the product is taken with a 1e-6 tolerance: 58 percent of 100 points is
    // 58, not 57). Not documented. Evidence: black-box renders of NSProgressIndicator at
    // 1x on macOS 10.14.4 (tier 2), the number of blue columns for every value 0 to 100 of a 0 to 100 range in
    // views 20, 37, 60, 100 and 200 points wide (vd-upstream/mac-probes/aqua-leftovers-progress-3.m).
    // Test: test_quirk_progress_bar_fill in tests/appkit-progress-bar-fill.m
    fill.size.width = MAX(0, MIN(NSWidth(bar), floor(NSWidth(rect) * value + 1e-6) - 1));
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

// The one point outline of a text field bezel, blended over what is under it (NSRectFill would replace the pixels,
// so that a window, which has no transparency, showed the outline as solid black).
static void textFieldBezelOutline(NSRect rect, BOOL enabled) {
    [[NSColor colorWithCalibratedWhite: 0 alpha: enabled ? 0.2 : 0.1] setFill];
    NSRect outline[4] = {NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), 1),
                         NSMakeRect(NSMinX(rect), NSMaxY(rect) - 1, NSWidth(rect), 1),
                         NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, 1, NSHeight(rect) - 2),
                         NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect) + 1, 1, NSHeight(rect) - 2)};

    NSRectFillListUsingOperation(outline, 4, NSCompositeSourceOver);
}

- (void) drawTextFieldBorderInRect: (NSRect) rect bezeledNotLine: (BOOL) bezeledNotLine enabled: (BOOL) enabled {
    if (bezeledNotLine) {
        // QUIRK: the bezel of a text field on macOS 10.14 (light appearance) is a white rectangle with a
        // one point outline of black at 20%, 10% when the field is disabled. Not documented. Evidence: black-box
        // renders of NSTextField on macOS 10.14.4 at 1x (tier 2), probe mac-probes/aqua-toolbar.m of the
        // research notes. Tests: appkit-textfield-aqua.m, appkit-toolbar-controls-aqua.m (test_quirk_field_bezels)
        [[NSColor whiteColor] setFill];
        NSRectFill(NSInsetRect(rect, 1, 1));
        textFieldBezelOutline(rect, enabled);
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

// QUIRK: the box is placed in an 18 point high rectangle centred in the cell (rounded down), 2, 3 and 5
// points below its top for a check box and 1, 2 and 4 for a radio button, for the regular, small and mini sizes.
// Not documented. Evidence: black-box renders of NSButton on macOS 10.14.4 at 1x in 18 and 40 point high frames
// (tier 2). Test: test_quirk_toggle_placement in tests/appkit-small-controls-aqua.m
static NSRect NSAquaToggleBoxRect(NSRect rect, BOOL radio, NSControlSize controlSize) {
    static const CGFloat check[3] = {2, 3, 5}, round_[3] = {1, 2, 4};
    int index = controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0);
    CGFloat size = NSAquaToggleBoxSize(radio, controlSize);
    // rect is unflipped (its top is its maximum y) and is the image's rectangle, which the cell centres in its frame
    // rounding its top down; the 18 point rectangle the offsets are measured from is centred the same way
    CGFloat top = -floor((18 - NSHeight(rect)) / 2) + (radio ? round_[index] : check[index]);

    return NSMakeRect(NSMinX(rect) + NSAquaToggleBoxInset(radio, controlSize), NSMaxY(rect) - top - size, size, size);
}

static void NSAquaDrawToggleUncached(NSRect rect, BOOL radio, NSInteger state, BOOL highlighted, BOOL enabled,
                                     BOOL active, NSControlSize controlSize)
{
    BOOL dark = NSAquaDrawsDark();
    CGFloat size = NSAquaToggleBoxSize(radio, controlSize);
    NSRect box = NSAquaToggleBoxRect(rect, radio, controlSize);
    // a disabled button shows no pressed look
    highlighted = highlighted && enabled;
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
        CGGradientRef gradient;

        if (dark) {
            // the dark look is a translucent white box, lighter while pressed, darker towards its top edge, so
            // that it shows the window colour through it
            CGFloat fill = highlighted ? 0.36 : 0.25, shade = highlighted ? 0.30 : 0.18;
            CGFloat darkComps[8] = {1, 1, 1, shade * alpha, 1, 1, 1, fill * alpha};

            memcpy(comps, darkComps, sizeof(comps));
        }
        gradient = CGGradientCreateWithColorComponents(space, comps, NULL, 2);

        if (dark)
            [[NSColor colorWithCalibratedWhite: 1 alpha: (highlighted ? 0.36 : 0.25) * alpha] setFill];
        else
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
        [(dark ? [NSColor colorWithCalibratedWhite: 1 alpha: 0.12 * alpha] : [NSColor colorWithCalibratedWhite: 0.68 alpha: alpha]) setStroke];
        [outline setLineWidth: 1];
        [outline stroke];
    }

    if (marked) {
        NSColor *mark = (blue || dark) ? [NSColor colorWithCalibratedWhite: 1 alpha: alpha]
                                       : [NSColor colorWithCalibratedWhite: 0.25 alpha: alpha];
        CGFloat scale = size / 14.0;
        NSBezierPath *path = [NSBezierPath bezierPath];

        [mark setStroke];
        [mark setFill];
        if (state == NSMixedState) {
            // QUIRK: the mixed state of check boxes and radio buttons alike is a bar 8, 7 or 6 points long and 2 high,
            // centred, with a dark line under it on the blue look. Not documented. Evidence: black-box renders of
            // NSButton on macOS 10.14.4 at 1x (tier 2). Test: test_quirk_toggle_mixed in
            // tests/appkit-small-controls-aqua.m
            static const CGFloat lengths[3] = {8, 7, 6};
            CGFloat length = lengths[controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0)];
            NSRect bar = NSAquaSnapToDevicePixels([[NSGraphicsContext currentContext] graphicsPort],
                                                  NSMakeRect(NSMidX(box) - length / 2, NSMidY(box) - 1, length, 2));

            if (blue) {
                [[NSColor colorWithCalibratedWhite: 0 alpha: 0.5 * alpha] setFill];
                NSRectFillUsingOperation(NSOffsetRect(bar, 0, -1), NSCompositeSourceOver);
            }
            [mark setFill];
            NSRectFillUsingOperation(bar, NSCompositeSourceOver);
        } else if (radio) {
            CGFloat r = size * 2.5 / 16;
            [[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(NSMidX(box) - r, NSMidY(box) - r, 2 * r, 2 * r)] fill];
        } else {
            {
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

/* A toggle looks the same wherever it is drawn: once its box is on the device pixel grid, the pixels depend only
   on the kind, state, highlight, enabled and active flags, the control size and the scale. Drawing it takes several
   path rasterizations (fill, shade, outline, mark), and a window of options draws dozens of them every time a
   view is displayed, so the first draw at a whole number scale renders the toggle into an image that later draws
   reuse. Other transforms (rotated, skewed, fractional scales) draw directly. */
#define NSAQUA_TOGGLE_PAD 2 // points around the box in the cached image, for the antialiased outline

static CGImageRef NSAquaCachedToggleImage(BOOL radio, NSInteger state, BOOL highlighted, BOOL enabled, BOOL active,
                                          NSControlSize controlSize, int scale)
{
    static NSMutableDictionary *cache;
    NSString *key = [NSString stringWithFormat: @"%d.%ld.%d.%d.%d.%ld.%d.%d", radio, (long) state, highlighted, enabled, active,
                                                 (long) controlSize, scale, NSAquaDrawsDark()];

    @synchronized([NSGraphicsStyle class]) {
        if (cache == nil)
            cache = [NSMutableDictionary new];
        id found = [cache objectForKey: key];

        if (found != nil)
            return (CGImageRef) found == (CGImageRef) [NSNull null] ? NULL : (CGImageRef) found;
    }

    CGFloat size = NSAquaToggleBoxSize(radio, controlSize);
    size_t pixels = (size_t) ceil((size + 2 * NSAQUA_TOGGLE_PAD) * scale);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(NULL, pixels, pixels, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGImageRef image = NULL;

    if (bitmap != NULL) {
        CGContextScaleCTM(bitmap, scale, scale);
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithGraphicsPort: bitmap flipped: NO];

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: context];
        // A rectangle 18 points high puts the box at the pad from the left and bottom edges of the image.
        CGFloat topOffset = NSAquaToggleBoxRect(NSMakeRect(0, 0, 18, 18), radio, controlSize).origin.y;
        NSRect rect = NSMakeRect(NSAQUA_TOGGLE_PAD - NSAquaToggleBoxInset(radio, controlSize),
                                 NSAQUA_TOGGLE_PAD - topOffset, 18, 18);
        NSAquaDrawToggleUncached(rect, radio, state, highlighted, enabled, active, controlSize);
        [NSGraphicsContext restoreGraphicsState];
        image = CGBitmapContextCreateImage(bitmap);
        CGContextRelease(bitmap);
    }
    CGColorSpaceRelease(space);

    @synchronized([NSGraphicsStyle class]) {
        [cache setObject: image != NULL ? (id) image : (id) [NSNull null] forKey: key];
    }
    if (image != NULL)
        CGImageRelease(image); // the cache holds it now
    return image;
}

static void NSAquaDrawToggle(NSRect rect, BOOL radio, NSInteger state, BOOL highlighted, BOOL enabled,
                             BOOL active, NSControlSize controlSize)
{
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGAffineTransform t = CGContextGetCTM(ctx);
    CGFloat sx = fabs(t.a), sy = fabs(t.d);
    // a disabled button shows no pressed look
    BOOL pressed = highlighted && enabled;

    if (t.b == 0 && t.c == 0 && sx == sy && sx >= 1 && sx <= 4 && sx == floor(sx)) {
        NSRect box = NSAquaSnapToDevicePixels(ctx, NSAquaToggleBoxRect(rect, radio, controlSize));
        // The blue look needs the active flag only when the box is not pressed.
        BOOL activeKey = active || pressed;
        CGImageRef image = NSAquaCachedToggleImage(radio, state, pressed, enabled, activeKey, controlSize, (int) sx);

        if (image != NULL) {
            CGRect target = CGRectMake(NSMinX(box) - NSAQUA_TOGGLE_PAD, NSMinY(box) - NSAQUA_TOGGLE_PAD,
                                       NSWidth(box) + 2 * NSAQUA_TOGGLE_PAD, NSHeight(box) + 2 * NSAQUA_TOGGLE_PAD);

            CGContextDrawImage(ctx, target, image);
            return;
        }
    }
    NSAquaDrawToggleUncached(rect, radio, state, highlighted, enabled, active, controlSize);
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
    NSRect box = NSAquaToggleBoxRect(rect, radio, controlSize);

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
    BOOL dark = NSAquaDrawsDark();
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 0.5, 0.5)
                                                            xRadius: radius
                                                            yRadius: radius];
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius];

    if (NSWidth(rect) < 2 || NSHeight(rect) < 4)
        return;

    // the shadow below the bezel
    if (dark) {
        // The dark bezel is translucent, so the shadow is only the part outside the bezel (under it, it would
        // darken the fill).
        NSBezierPath *shadow = [NSBezierPath bezierPathWithRoundedRect: NSOffsetRect(body, 0, -1) xRadius: radius yRadius: radius];

        [shadow appendBezierPath: shape];
        [shadow setWindingRule: NSEvenOddWindingRule];
        [[NSColor colorWithCalibratedWhite: 0 alpha: 0.14 * alpha] setFill];
        [shadow fill];
    } else {
        [[NSColor colorWithCalibratedWhite: 0 alpha: 0.07 * alpha] setFill];
        [[NSBezierPath bezierPathWithRoundedRect: NSOffsetRect(body, 0, -1) xRadius: radius yRadius: radius] fill];
    }

    if (blue) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat normal[8] = {107 / 255.0, 161 / 255.0, 250 / 255.0, 1, 17 / 255.0, 100 / 255.0, 1, 1};
        CGFloat down[8] = {76 / 255.0, 139 / 255.0, 253 / 255.0, 1, 15 / 255.0, 88 / 255.0, 231 / 255.0, 1};
        // the blue of the dark look is deeper
        CGFloat darkNormal[8] = {26 / 255.0, 98 / 255.0, 231 / 255.0, 1, 23 / 255.0, 89 / 255.0, 206 / 255.0, 1};
        CGFloat darkDown[8] = {39 / 255.0, 118 / 255.0, 244 / 255.0, 1, 34 / 255.0, 109 / 255.0, 231 / 255.0, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(
                space, dark ? (pressed ? darkDown : darkNormal) : (pressed ? down : normal), NULL, 2);

        CGContextSaveGState(ctx);
        [shape addClip];
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, NSMaxY(body)), CGPointMake(0, NSMinY(body)), 0);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        if (dark) {
            // a light line along the top edge of the blue
            [[NSColor colorWithCalibratedWhite: 1 alpha: 0.18] setFill];
            CGContextSaveGState(ctx);
            [shape addClip];
            NSRectFillUsingOperation(NSMakeRect(NSMinX(body), NSMaxY(body) - 1, NSWidth(body), 1), NSCompositeSourceOver);
            CGContextRestoreGState(ctx);
            [[NSColor colorWithCalibratedWhite: 0 alpha: 0.2] setStroke];
        } else
            [[NSColor colorWithCalibratedRed: 0.1 green: 0.4 blue: 0.98 alpha: 0.7] setStroke];
    } else if (dark) {
        // translucent white over the window colour, with a lighter line along the top edge
        NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 1, 1)
                                                              xRadius: MAX(radius - 1, 0)
                                                              yRadius: MAX(radius - 1, 0)];

        [[NSColor colorWithCalibratedWhite: 1 alpha: 0.25 * alpha] setFill];
        [inner fill];
        CGContextSaveGState(ctx);
        [inner addClip];
        [[NSColor colorWithCalibratedWhite: 1 alpha: 0.08 * alpha] setFill];
        NSRectFillUsingOperation(NSMakeRect(NSMinX(body), NSMaxY(body) - 2, NSWidth(body), 1), NSCompositeSourceOver);
        CGContextRestoreGState(ctx);
        [[NSColor colorWithCalibratedWhite: 0 alpha: 0.08 * alpha] setStroke];
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
    BOOL dark = NSAquaDrawsDark();

    [self drawPushButtonInRect: rect defaulted: NO pressed: NO enabled: enabled active: active];
    if (blue) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat normal[8] = {110 / 255.0, 163 / 255.0, 250 / 255.0, 1, 13 / 255.0, 97 / 255.0, 1, 1};
        CGFloat down[8] = {76 / 255.0, 139 / 255.0, 253 / 255.0, 1, 15 / 255.0, 88 / 255.0, 231 / 255.0, 1};
        CGFloat darkNormal[8] = {26 / 255.0, 98 / 255.0, 231 / 255.0, 1, 23 / 255.0, 89 / 255.0, 206 / 255.0, 1};
        CGFloat darkDown[8] = {39 / 255.0, 118 / 255.0, 244 / 255.0, 1, 34 / 255.0, 109 / 255.0, 231 / 255.0, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(
                space, dark ? (pressed ? darkDown : darkNormal) : (pressed ? down : normal), NULL, 2);

        CGContextSaveGState(ctx);
        [[NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius] addClip];
        CGContextClipToRect(ctx, cap);
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, NSMaxY(body)), CGPointMake(0, NSMinY(body)), 0);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }

    NSColor *mark = blue ? [NSColor whiteColor]
                         : [NSColor colorWithCalibratedWhite: dark ? 1 : 0 alpha: enabled ? (dark ? 0.85 : 0.55) : 0.3];
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
    BOOL dark = NSAquaDrawsDark();

    if (dark) {
        // translucent white over the window colour: light grey, lighter while pressed and light in the on state
        // (the on look is a lighter bezel with dark text, not a darker one)
        normalTop[0] = normalBottom[0] = pressedTop[0] = pressedBottom[0] = onTop[0] = onBottom[0] = 1;
        onPressedTop[0] = onPressedBottom[0] = 1;
        normalTop[1] = normalBottom[1] = 0.25;
        pressedTop[1] = pressedBottom[1] = 0.356;
        onTop[1] = onBottom[1] = 0.6;
        onPressedTop[1] = onPressedBottom[1] = 0.67;
        outline = 0.08;
    }

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
        if (dark)
            [[NSColor colorWithCalibratedWhite: 1 alpha: pressed ? 0.07 : 0.06] setFill];
        else
            [[NSColor colorWithCalibratedWhite: pressed ? 239 / 255.0 : 1 alpha: pressed ? 0.94 : 1] setFill];
        [[NSBezierPath bezierPathWithRect: NSMakeRect(NSMinX(inner), NSMaxY(inner) - 1, NSWidth(inner), 1)] fill];
    } else if (dark) {
        [[NSColor colorWithCalibratedWhite: 1 alpha: 0.04] setFill];
        [[NSBezierPath bezierPathWithRect: NSMakeRect(NSMinX(inner), NSMaxY(inner) - 1, NSWidth(inner), 1)] fill];
    }
    // the bottom outline line is darker
    [[NSColor colorWithCalibratedWhite: 0 alpha: dark ? 0.18 : 0.1] setFill];
    [[NSBezierPath bezierPathWithRect: NSMakeRect(NSMinX(body), NSMinY(body), NSWidth(body), 1)] fill];
    [NSGraphicsContext restoreGraphicsState];
}

// QUIRK: a textured segmented control draws one textured bezel across its segments; between two segments a one
// point line of black at 10% runs across the inner area, and a selected segment of a control that selects one
// segment shows the dark on look with such a line along both of its edges inside it. Evidence and test as for
// -drawTexturedBezelInRect:square:pressed:on:controlSize:.
- (void) drawTexturedSegmentSeparatorInRect: (NSRect) rect {
    [[NSColor colorWithCalibratedWhite: NSAquaDrawsDark() ? 1 : 0 alpha: 0.1] setFill];
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

    if (NSAquaDrawsDark()) {
        // translucent white instead of near black; the on state is the lightest
        gray = 1;
        alpha = pressed ? 0.36 : (on ? 0.55 : 0.25);
    }

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
    CGFloat ink = NSAquaDrawsDark() ? 1 : 0;

    if (filled) {
        [[NSColor colorWithCalibratedWhite: ink alpha: 0.1] setFill];
        [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(body, 1, 1)
                                         xRadius: MAX(radius - 1, 0)
                                         yRadius: MAX(radius - 1, 0)] fill];
    }
    [[NSColor colorWithCalibratedWhite: ink alpha: enabled ? 0.3 : 0.15] setStroke];
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
    [[NSColor colorWithCalibratedWhite: NSAquaDrawsDark() ? 1 : 0 alpha: enabled ? (NSAquaDrawsDark() ? 0.85 : 0.65) : 0.3] setStroke];
    [chevrons setLineWidth: 1.1];
    [chevrons setLineCapStyle: NSRoundLineCapStyle];
    [chevrons setLineJoinStyle: NSMiterLineJoinStyle];
    [chevrons stroke];
}

@end

@implementation NSGraphicsStyle (NSSliderAqua)

// QUIRK: the slider look of macOS 10.14 (light appearance). Not documented. Evidence: black-box renders of
// NSSlider on macOS 10.14.4 at 1x (tier 2), vd-upstream/mac-probes/aqua-small-controls.m: the track is 3 points
// thick and rounded, black at 22% (11% when disabled); without tick marks it is blue (61,130,253) from the minimum
// to the knob in an enabled slider; the knob is white (251 when disabled) with a thin dark rim that is heavier
// below it (half as strong when disabled); with tick marks it has a point towards them; tick marks are 1 point
// black lines at 36%. setHighlighted: does not change the look. Test: test_quirk_slider_* in
// tests/appkit-small-controls-aqua.m
- (void) drawAquaSliderTrackInRect: (NSRect) rect
                          fillRect: (NSRect) fillRect
                           enabled: (BOOL) enabled
                            active: (BOOL) active
{
    [[NSColor colorWithCalibratedWhite: 0 alpha: enabled ? 0.22 : 0.11] setFill];
    [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: 1.5 yRadius: 1.5] fill];
    if (enabled && NSWidth(fillRect) > 0 && NSHeight(fillRect) > 0) {
        // in a window that is not active the fill is gray, like the other accent-coloured parts
        [(active ? [NSColor colorWithCalibratedRed: 61 / 255.0 green: 130 / 255.0 blue: 253 / 255.0 alpha: 1]
                 : [NSColor colorWithCalibratedWhite: 0.55 alpha: 1]) setFill];
        [[NSBezierPath bezierPathWithRoundedRect: fillRect xRadius: 1.5 yRadius: 1.5] fill];
    }
}

/* Adds the outline of a knob to the context's path, in a coordinate system whose origin is the top left corner of
   the knob's rectangle on the screen and whose y axis points down the screen. */
static void NSAquaAddKnobPath(CGContextRef ctx, CGFloat width, CGFloat height, NSInteger pointing) {
    if (pointing < 0) {
        CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, width, height));
        return;
    }
    BOOL across = (pointing == NSMinXEdge || pointing == NSMaxXEdge);
    // the knob pointing down: d across, h long; sides are straight for s, then the point at 45 degrees
    CGFloat d = across ? height : width, h = across ? width : height;
    CGFloat r = d > 12 ? 2 : 1.5, s = h - d / 2;
    CGPoint pts[6] = {{0, 0}, {d, 0}, {d, s}, {d / 2, h}, {0, s}, {0, 0}};

    for (int i = 0; i < 6; i++) {
        CGFloat u = pts[i].x, v = pts[i].y;

        if (pointing == NSMaxYEdge)
            v = h - v;
        else if (pointing == NSMinXEdge) {
            CGFloat t = u;
            u = h - v;
            v = t;
        } else if (pointing == NSMaxXEdge) {
            CGFloat t = u;
            u = v;
            v = t;
        }
        pts[i] = CGPointMake(u, v);
    }
    // start in the middle of the side opposite to the point; the two corners there are rounded
    CGContextMoveToPoint(ctx, (pts[0].x + pts[1].x) / 2, (pts[0].y + pts[1].y) / 2);
    CGContextAddArcToPoint(ctx, pts[1].x, pts[1].y, pts[2].x, pts[2].y, r);
    CGContextAddLineToPoint(ctx, pts[2].x, pts[2].y);
    CGContextAddLineToPoint(ctx, pts[3].x, pts[3].y);
    CGContextAddLineToPoint(ctx, pts[4].x, pts[4].y);
    CGContextAddArcToPoint(ctx, pts[0].x, pts[0].y, pts[1].x, pts[1].y, r);
    CGContextClosePath(ctx);
}

/* Moves the origin to the top left corner of rect on the screen, with y pointing down the screen. */
static void NSAquaBeginScreenDown(CGContextRef ctx, NSRect rect, BOOL flipped) {
    CGContextSaveGState(ctx);
    if (flipped)
        CGContextTranslateCTM(ctx, NSMinX(rect), NSMinY(rect));
    else {
        CGContextTranslateCTM(ctx, NSMinX(rect), NSMaxY(rect));
        CGContextScaleCTM(ctx, 1, -1);
    }
}

/* A white knob shape with the rim of the Aqua slider knobs: dark at 13% around it and 15% more one point below. */
static void NSAquaDrawKnobShape(CGContextRef ctx, NSRect rect, NSInteger pointing, BOOL enabled, BOOL flipped) {
    CGFloat strength = enabled ? 1 : 0.5;

    NSAquaBeginScreenDown(ctx, rect, flipped);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.15 * strength);
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, 0, 1);
    NSAquaAddKnobPath(ctx, NSWidth(rect), NSHeight(rect), pointing);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);
    CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.13 * strength);
    CGContextSetLineWidth(ctx, 2);
    NSAquaAddKnobPath(ctx, NSWidth(rect), NSHeight(rect), pointing);
    CGContextStrokePath(ctx);
    CGContextSetGrayFillColor(ctx, enabled ? 1 : 251 / 255.0, 1);
    NSAquaAddKnobPath(ctx, NSWidth(rect), NSHeight(rect), pointing);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);
}

- (void) drawAquaSliderKnobInRect: (NSRect) rect
                         pointing: (NSInteger) pointing
                          enabled: (BOOL) enabled
                          flipped: (BOOL) flipped
{
    NSAquaDrawKnobShape([[NSGraphicsContext currentContext] graphicsPort], rect, pointing, enabled, flipped);
}

- (void) drawAquaSliderTickInRect: (NSRect) rect {
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.36] setFill];
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

// QUIRK: a circular slider is a white disc with the same rim as the knob of a linear slider, and a dark gray
// (75) dot for its knob. Not documented. Evidence: black-box renders of a circular NSSlider on macOS 10.14.4 at
// 1x (tier 2). Test: test_quirk_circular_slider in tests/appkit-small-controls-aqua.m
- (void) drawAquaCircularSliderInRect: (NSRect) rect knobRect: (NSRect) knobRect enabled: (BOOL) enabled flipped: (BOOL) flipped {
    NSAquaDrawKnobShape([[NSGraphicsContext currentContext] graphicsPort], rect, -1, enabled, flipped);
    [[NSColor colorWithCalibratedWhite: 75 / 255.0 alpha: enabled ? 1 : 0.5] setFill];
    [[NSBezierPath bezierPathWithOvalInRect: knobRect] fill];
}

@end

@implementation NSGraphicsStyle (NSStepperAqua)

// QUIRK: the stepper look of macOS 10.14 (light appearance). Not documented. Evidence: black-box renders of
// NSStepper on macOS 10.14.4 at 1x (tier 2): a white capsule (13 x 22, 11 x 19 and 9 x 15 points for the three
// control sizes, corner radius 5, 4 and 4) with a black rim at 18%, heavier along the bottom, and a faint shadow
// below; two dark (black at 80%) chevrons, 5 points wide and 2.5 high (4 and 2 at the mini size), whose tips are
// 6, 5 and 4 points from the ends; a pressed half is a blue gradient ((39,109,239) to (3,71,220)) with a white chevron; a disabled
// stepper is drawn at half strength. Test: test_quirk_stepper in tests/appkit-small-controls-aqua.m
- (void) drawAquaStepperInRect: (NSRect) rect
                   controlSize: (NSControlSize) controlSize
                       enabled: (BOOL) enabled
                 upHighlighted: (BOOL) upHighlighted
               downHighlighted: (BOOL) downHighlighted
{
    static const CGFloat radii[3] = {5, 4, 4}, tips[3] = {6, 5, 4}, arms[3] = {2.5, 2.5, 2};
    int index = controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0);
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGFloat w = NSWidth(rect), h = NSHeight(rect), r = radii[index];

    // a disabled stepper is drawn at half strength (explicitly: not every context honours a global alpha)
    CGFloat k = enabled ? 1 : 0.5;

    NSAquaBeginScreenDown(ctx, rect, flipped);
    CGRect body = CGRectMake(0, 0, w, h);
    CGPathRef shape = CGPathCreateWithRoundedRect(body, r, r, NULL);
    CGPathRef inner = CGPathCreateWithRoundedRect(CGRectInset(body, 1, 1), r - 1, r - 1, NULL);

    // the faint shadow below
    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, CGRectMake(0, h / 2, w, h / 2 + 1));
    CGContextAddPath(ctx, shape);
    CGContextTranslateCTM(ctx, 0, 1);
    CGContextAddPath(ctx, shape);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.03 * k);
    CGContextEOFillPath(ctx);
    CGContextRestoreGState(ctx);
    // the rim (between the outline and the white inside), and its heavier bottom row
    CGContextAddPath(ctx, shape);
    CGContextAddPath(ctx, inner);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.18 * k);
    CGContextEOFillPath(ctx);
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, shape);
    CGContextClip(ctx);
    CGContextAddPath(ctx, shape);
    CGContextTranslateCTM(ctx, 0, -1);
    CGContextAddPath(ctx, shape);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.11 * k);
    CGContextEOFillPath(ctx);
    CGContextRestoreGState(ctx);
    CGContextAddPath(ctx, inner);
    CGContextSetGrayFillColor(ctx, 1, k);
    CGContextFillPath(ctx);

    for (int i = 0; i < 2; i++) {
        BOOL up = i == 0;
        BOOL pressed = up ? upHighlighted : downHighlighted;
        CGFloat tipY = up ? tips[index] : h - tips[index];
        CGFloat arm = arms[index], armY = up ? tipY + arm : tipY - arm;

        if (pressed) {
            CGRect half = up ? CGRectMake(0, 0, w, floor(h / 2)) : CGRectMake(0, floor(h / 2), w, h - floor(h / 2));
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGFloat comps[8] = {39 / 255.0, 109 / 255.0, 239 / 255.0, k, 3 / 255.0, 71 / 255.0, 220 / 255.0, k};
            CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, NULL, 2);

            CGContextSaveGState(ctx);
            CGContextAddPath(ctx, shape);
            CGContextClip(ctx);
            CGContextClipToRect(ctx, half);
            CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, CGRectGetMinY(half)),
                                        CGPointMake(0, CGRectGetMaxY(half)), 0);
            // the rim over the blue
            CGContextAddPath(ctx, shape);
            CGContextAddPath(ctx, inner);
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.1 * k);
            CGContextEOFillPath(ctx);
            CGContextRestoreGState(ctx);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(space);
        }
        CGContextMoveToPoint(ctx, w / 2 - arm, armY);
        CGContextAddLineToPoint(ctx, w / 2, tipY);
        CGContextAddLineToPoint(ctx, w / 2 + arm, armY);
        if (pressed)
            CGContextSetRGBStrokeColor(ctx, 1, 1, 1, k);
        else
            CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.8 * k);
        CGContextSetLineWidth(ctx, 1.25);
        CGContextSetLineCap(ctx, kCGLineCapButt);
        CGContextSetLineJoin(ctx, kCGLineJoinMiter);
        CGContextStrokePath(ctx);
    }
    CGPathRelease(shape);
    CGPathRelease(inner);
    CGContextRestoreGState(ctx);
}

@end

@implementation NSGraphicsStyle (NSProgressIndicatorAqua)

// QUIRK: the spinning progress indicator of macOS 10.14 (light appearance). Not documented. Evidence: black-box
// renders of NSProgressIndicator (spinning style) on macOS 10.14.4 at 1x (tier 2): 12 black spokes with round
// ends, 3, 2 and 1.25 points wide in the 32, 16 and 10 point sizes, from the edge of the square to 27% of its
// width from the centre; the leading spoke is opaque and each one behind it, counterclockwise, has 85% of the
// alpha of the one before. The determinate style is a ring and a wedge, both black at 50%, filled clockwise from
// the top. Test: test_quirk_spinning_indicator in tests/appkit-small-controls-aqua.m
- (void) drawSpinningProgressIndicatorInRect: (NSRect) rect phase: (NSInteger) phase {
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGFloat d = MIN(NSWidth(rect), NSHeight(rect));
    CGFloat width = d >= 32 ? 3 * d / 32 : (d >= 16 ? 2 * d / 16 : 1.25 * d / 10);
    CGFloat outer = d / 2 - width / 2, inner = d * 0.27;
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];

    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, NSMidX(rect), NSMidY(rect));
    if (!flipped)
        CGContextScaleCTM(ctx, 1, -1);
    // now y points down the screen; spoke i is i twelfths of a turn clockwise from the top
    CGContextSetLineWidth(ctx, width);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    for (int i = 0; i < 12; i++) {
        int behind = (int) (((phase - i) % 12 + 12) % 12);
        CGFloat angle = i * M_PI / 6, sx = sin(angle), sy = -cos(angle);

        CGContextSetRGBStrokeColor(ctx, 0, 0, 0, pow(0.85, behind));
        CGContextMoveToPoint(ctx, sx * inner, sy * inner);
        CGContextAddLineToPoint(ctx, sx * outer, sy * outer);
        CGContextStrokePath(ctx);
    }
    CGContextRestoreGState(ctx);
}

- (void) drawSpinningProgressPieInRect: (NSRect) rect value: (double) value flipped: (BOOL) flipped {
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGFloat d = MIN(NSWidth(rect), NSHeight(rect));
    NSRect square = NSMakeRect(NSMidX(rect) - d / 2, NSMidY(rect) - d / 2, d, d);

    value = MAX(0, MIN(1, value));
    NSAquaBeginScreenDown(ctx, square, flipped);
    CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.5);
    CGContextSetLineWidth(ctx, 1);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(0.5, 0.5, d - 1, d - 1));
    if (value > 0) {
        CGFloat c = d / 2, radius = d / 2 - 1;

        CGContextMoveToPoint(ctx, c, c);
        // y points down the screen, so increasing angles turn clockwise
        CGContextAddArc(ctx, c, c, radius, -M_PI_2, -M_PI_2 + value * 2 * M_PI, 0);
        CGContextClosePath(ctx);
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.5);
        CGContextFillPath(ctx);
    }
    CGContextRestoreGState(ctx);
}

@end

@implementation NSGraphicsStyle (NSLevelIndicatorAqua)

// QUIRK: the capacity level indicators of macOS 10.14 (light appearance). Not documented. Evidence: black-box
// renders of NSLevelIndicator on macOS 10.14.4 at 1x (tier 2): a bar (or each segment of a discrete one) is a
// rounded rectangle (radius 3) 16 points high, black at 7% inside a 1 point rim at 19%; the filled part is
// green (54,210,66), yellow (254,206,9) at the warning value and red (252,44,49) at the critical value, each with
// a rim 13% darker; tick marks are 1 point black lines below, 6 points at 25% (major) or 3 points at 19%.
// A disabled indicator looks the same. Test: test_quirk_level_indicator in tests/appkit-small-controls-aqua.m
- (void) drawLevelIndicatorTrackInRect: (NSRect) rect {
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect: rect xRadius: 3 yRadius: 3];
    NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(rect, 1, 1) xRadius: 2 yRadius: 2];

    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.07] setFill];
    [inner fill];
    [shape appendBezierPath: inner];
    [shape setWindingRule: NSEvenOddWindingRule];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.19] setFill];
    [shape fill];
}

- (void) drawLevelIndicatorFillInRect: (NSRect) rect clipRect: (NSRect) clipRect color: (NSColor *) color {
    NSColor *rgb = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    NSColor *rim = [NSColor colorWithCalibratedRed: [rgb redComponent] * 0.87 green: [rgb greenComponent] * 0.87
                                              blue: [rgb blueComponent] * 0.87 alpha: [rgb alphaComponent]];
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect: rect xRadius: 3 yRadius: 3];
    NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(rect, 1, 1) xRadius: 2 yRadius: 2];

    [NSGraphicsContext saveGraphicsState];
    NSRectClip(clipRect);
    [rim setFill];
    [shape fill];
    [rgb setFill];
    [inner fill];
    [NSGraphicsContext restoreGraphicsState];
}

- (void) drawLevelIndicatorTickInRect: (NSRect) rect major: (BOOL) major {
    [[NSColor colorWithCalibratedWhite: 0 alpha: major ? 0.25 : 0.19] setFill];
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

@end

@implementation NSView (NSGraphicsStyle)

- (NSGraphicsStyle *) graphicsStyle {
    return [[[NSGraphicsStyle alloc] initWithView: self] autorelease];
}

@end
