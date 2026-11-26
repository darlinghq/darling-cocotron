/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSView.h>

#import <AppKit/NSDisplay.h>
#import <ApplicationServices/ApplicationServices.h>

#import "NSPoofAnimation.h"
#import "NSGraphics-Private.h"

const CGFloat NSBlack = 0;
const CGFloat NSDarkGray = 0.333;
const CGFloat NSLightGray = 0.667;
const CGFloat NSWhite = 1.0;

NSString *const NSDeviceBlackColorSpace = @"NSDeviceBlackColorSpace";
NSString *const NSDeviceWhiteColorSpace = @"NSDeviceWhiteColorSpace";
NSString *const NSDeviceRGBColorSpace = @"NSDeviceRGBColorSpace";
NSString *const NSDeviceCMYKColorSpace = @"NSDeviceCMYKColorSpace";
NSString *const NSCalibratedBlackColorSpace = @"NSCalibratedBlackColorSpace";
NSString *const NSCalibratedWhiteColorSpace = @"NSCalibratedWhiteColorSpace";
NSString *const NSCalibratedRGBColorSpace = @"NSCalibratedRGBColorSpace";
NSString *const NSNamedColorSpace = @"NSNamedColorSpace";
NSString *const NSPatternColorSpace = @"NSPatternColorSpace";
NSString *const NSCustomColorSpace = @"NSCustomColorSpace";

NSString *const NSDeviceIsScreen = @"NSDeviceIsScreen";
NSString *const NSDeviceIsPrinter = @"NSDeviceIsPrinter";
NSString *const NSDeviceSize = @"NSDeviceSize";
NSString *const NSDeviceResolution = @"NSDeviceResolution";
NSString *const NSDeviceColorSpaceName = @"NSDeviceColorSpaceName";
NSString *const NSDeviceBitsPerSample = @"NSDeviceBitsPerSample";

static inline CGBlendMode blendModeForCompositeOp(NSCompositingOperation op) {
    static CGBlendMode table[] = {
            kCGBlendModeClear,
            kCGBlendModeCopy,
            kCGBlendModeNormal,
            kCGBlendModeSourceIn,
            kCGBlendModeSourceOut,
            kCGBlendModeSourceAtop,
            kCGBlendModeDestinationOver,
            kCGBlendModeDestinationIn,
            kCGBlendModeDestinationOut,
            kCGBlendModeDestinationAtop,
            kCGBlendModeXOR,
            kCGBlendModePlusDarker,
            kCGBlendModeNormal, // FIXME: highlight
            kCGBlendModePlusLighter,
    };

    if (op < NSCompositeClear || op > NSCompositePlusLighter)
        return NSCompositeCopy;

    return table[op];
}

void NSRectClipList(const NSRect *rects, NSInteger count) {
    CGContextRef graphicsPort = NSCurrentGraphicsPort();

    CGContextClipToRects(graphicsPort, rects, count);
}

void NSRectClip(NSRect rect) {
    CGContextRef graphicsPort = NSCurrentGraphicsPort();

    CGContextClipToRect(graphicsPort, rect);
}

static BOOL focusRingBeforeRects(CGContextRef context, const NSRect *rects, NSInteger count) {
    BOOL paint = YES;

    if ([[NSGraphicsContext currentContext] _focusRingPlacement] == 0)
        return YES;
    for (NSInteger i = 0; i < count; i++) {
        CGPathRef path = CGPathCreateWithRect(rects[i], NULL);

        paint = _NSFocusRingBeforePaintingPath(context, path);
        CGPathRelease(path);
    }
    return paint;
}

static void focusRingAfterRects(CGContextRef context, const NSRect *rects, NSInteger count) {
    if ([[NSGraphicsContext currentContext] _focusRingPlacement] == 0)
        return;
    for (NSInteger i = 0; i < count; i++) {
        CGPathRef path = CGPathCreateWithRect(rects[i], NULL);

        _NSFocusRingAfterPaintingPath(context, path);
        CGPathRelease(path);
    }
}

void NSRectFillListWithColors(const NSRect *rects,
                              NSColor *const _Nonnull *_Nonnull colors,
                              NSInteger count)
{
    CGContextRef context = NSCurrentGraphicsPort();
    int i;

    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    for (i = 0; i < count; i++) {
        [colors[i] setFill];
        // FIXME: the groove/button rect generating code can generate negative
        // size rects which draw incorrectly this either needs to be fixed in
        // the drawing or the rect generation
        if (rects[i].size.width > 0 && rects[i].size.height > 0)
            NSRectFill(rects[i]);
    }
    CGContextRestoreGState(context);
}

void NSRectFillListWithGrays(const NSRect *rects, const CGFloat *grays,
                             NSInteger count)
{
    CGContextRef context = NSCurrentGraphicsPort();
    int i;

    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    for (i = 0; i < count; i++) {
        CGContextSetGrayFillColor(context, grays[i], 1.0);
        // FIXME: the groove/button rect generating code can generate negative
        // size rects which draw incorrectly this either needs to be fixed in
        // the drawing or the rect generation
        if (rects[i].size.width > 0 && rects[i].size.height > 0)
            CGContextFillRect(context, rects[i]);
    }
    CGContextRestoreGState(context);
}

void NSRectFillList(const NSRect *rects, NSInteger count) {
    CGContextRef context = NSCurrentGraphicsPort();
    BOOL paint = focusRingBeforeRects(context, rects, count);

    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    if (paint)
        CGContextFillRects(NSCurrentGraphicsPort(), rects, count);
    CGContextRestoreGState(context);
    focusRingAfterRects(context, rects, count);
}

void NSRectFill(NSRect rect) {
    NSRectFillList(&rect, 1);
}

void NSEraseRect(NSRect rect) {
    CGContextRef context = NSCurrentGraphicsPort();
    CGContextSaveGState(context);
    [[NSColor whiteColor] setFill];
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextFillRect(NSCurrentGraphicsPort(), rect);
    CGContextRestoreGState(context);
}

void NSRectFillListUsingOperation(const NSRect *rects, NSInteger count,
                                  NSCompositingOperation operation)
{
    CGContextRef context = NSCurrentGraphicsPort();
    BOOL paint = focusRingBeforeRects(context, rects, count);

    CGContextSaveGState(context);
    CGContextSetBlendMode(context, blendModeForCompositeOp(operation));
    if (paint)
        CGContextFillRects(NSCurrentGraphicsPort(), rects, count);
    CGContextRestoreGState(context);
    focusRingAfterRects(context, rects, count);
}

void NSRectFillListWithColorsUsingOperation(
        const NSRect *rects, NSColor *const _Nonnull *_Nonnull colors,
        NSInteger count, NSCompositingOperation operation)
{
    CGContextRef context = NSCurrentGraphicsPort();
    NSInteger i;

    CGContextSaveGState(context);
    for (i = 0; i < count; i++) {
        [colors[i] setFill];
        NSRectFillUsingOperation(rects[i], operation);
    }
    CGContextRestoreGState(context);
}

void NSRectFillUsingOperation(NSRect rect, NSCompositingOperation op) {
    NSRectFillListUsingOperation(&rect, 1, op);
}

void NSFrameRectWithWidth(NSRect rect, CGFloat width) {
    NSFrameRectWithWidthUsingOperation(rect, width, NSCompositeCopy);
}

void NSFrameRectWithWidthUsingOperation(NSRect rect, CGFloat width,
                                        NSCompositingOperation operation)
{
    CGContextRef context = NSCurrentGraphicsPort();
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, blendModeForCompositeOp(operation));
    CGRect edge[4];
    // left
    edge[0].origin.x = rect.origin.x;
    edge[0].origin.y = rect.origin.y;
    edge[0].size.width = width;
    edge[0].size.height = rect.size.height;
    // right
    edge[1].origin.x = NSMaxX(rect) - width;
    edge[1].origin.y = rect.origin.y;
    edge[1].size.width = width;
    edge[1].size.height = rect.size.height;
    // bottom
    edge[2].origin.x = rect.origin.x + width;
    edge[2].origin.y = rect.origin.y;
    edge[2].size.width = rect.size.width - width * 2;
    edge[2].size.height = width;
    // top
    edge[3].origin.x = rect.origin.x + width;
    edge[3].origin.y = NSMaxY(rect) - width;
    edge[3].size.width = rect.size.width - width * 2;
    edge[3].size.height = width;

    CGContextFillRects(NSCurrentGraphicsPort(), edge, 4);
    CGContextRestoreGState(context);
}

void NSFrameRect(NSRect rect) {
    CGContextStrokeRectWithWidth(NSCurrentGraphicsPort(), rect, 1);
}

void NSDottedFrameRect(NSRect rect) {
    [[NSColor blackColor] setFill];
    /* Win32 has poor dashed line support...

        DrawFocusRect produces dark spots for the gaps sometimes
        If we use a brush, it becomes black&white, not black&transparent
        The PS_DOT pen is not a single pixel dot.

        Fortunately this is not used heavily...
     */
    if (rect.size.width <= 0 || rect.size.height <= 0)
        return; {
        NSRect rects[(int) rect.size.width + 2 + (int) rect.size.height + 2];
        int count = 0;
        int x, y, maxx = NSMaxX(rect), maxy = NSMaxY(rect);
        BOOL on = NO;

        for (x = rect.origin.x; x < maxx; x++, on = !on)
            if (on)
                rects[count++] = NSMakeRect(x, rect.origin.y, 1, 1);

        for (y = rect.origin.y; y < maxy; y++, on = !on)
            if (on)
                rects[count++] = NSMakeRect(maxx - 1, y, 1, 1);

        for (x = maxx; --x >= rect.origin.x; on = !on)
            if (on)
                rects[count++] = NSMakeRect(x, maxy, 1, 1);

        for (y = maxy; --y >= rect.origin.y; on = !on)
            if (on)
                rects[count++] = NSMakeRect(rect.origin.x, y, 1, 1);

        CGContextFillRects(NSCurrentGraphicsPort(), rects, count);
    }
}

static NSRect NSDrawColorRects(NSRect boundsRect, NSRect clipRect,
                               const NSRect *sides, NSColor **colors, int count)
{
    CGContextRef graphicsPort = NSCurrentGraphicsPort();

    CGContextSaveGState(graphicsPort);
    CGContextClipToRect(graphicsPort, clipRect);
    NSRectFillListWithColors(sides, colors, count);
    CGContextRestoreGState(graphicsPort);

    return boundsRect;
}

void NSDrawButton(NSRect rect, NSRect clipRect) {
    NSRect rects[7];
    NSColor *colors[7];
    int i;

    for (i = 0; i < 7; i++)
        rects[i] = rect;

    if ([[NSGraphicsContext currentContext] isFlipped]) {
        colors[0] = [NSColor blackColor];
        rects[0].origin.y += rect.size.height - 1;
        rects[0].size.height = 1;

        colors[1] = [NSColor blackColor];
        rects[1].origin.x += rect.size.width - 1;
        rects[1].size.width = 1;

        colors[2] = [NSColor darkGrayColor];
        rects[2].origin.x += 1;
        rects[2].size.width -= 2;
        rects[2].origin.y += rect.size.height - 2;
        rects[2].size.height = 1;

        colors[3] = [NSColor darkGrayColor];
        rects[3].origin.x += rect.size.width - 2;
        rects[3].origin.y += 1;
        rects[3].size.width = 1;
        rects[3].size.height -= 2;

        colors[4] = [NSColor whiteColor];
        rects[4].size.height = 1;
        rects[4].size.width -= 1;

        colors[5] = [NSColor whiteColor];
        rects[5].size.width = 1;
        rects[5].size.height -= 1;

        colors[6] = [NSColor controlColor];
        rects[6].origin.x += 1;
        rects[6].origin.y += 1;
        rects[6].size.width -= 3;
        rects[6].size.height -= 3;
    } else {
        colors[0] = [NSColor blackColor];
        rects[0].size.height = 1;

        colors[1] = [NSColor blackColor];
        rects[1].origin.x += rect.size.width - 1;
        rects[1].size.width = 1;

        colors[2] = [NSColor darkGrayColor];
        rects[2].origin.x += 1;
        rects[2].origin.y += 1;
        rects[2].size.width -= 2;
        rects[2].size.height = 1;

        colors[3] = [NSColor darkGrayColor];
        rects[3].origin.x += rect.size.width - 2;
        rects[3].origin.y += 2;
        rects[3].size.width = 1;
        rects[3].size.height -= 2;

        colors[4] = [NSColor whiteColor];
        rects[4].origin.y += 1;
        rects[4].size.width = 1;
        rects[4].size.height -= 1;

        colors[5] = [NSColor whiteColor];
        rects[5].origin.y += rect.size.height - 1;
        rects[5].size.width -= 1;
        rects[5].size.height = 1;

        colors[6] = [NSColor controlColor];
        rects[6].origin.x += 1;
        rects[6].origin.y += 2;
        rects[6].size.width -= 3;
        rects[6].size.height -= 3;
    }

    NSDrawColorRects(rect, clipRect, rects, colors, 7);
}

void NSDrawGrayBezel(NSRect rect, NSRect clipRect) {
    NSRect rects[4];
    NSColor *colors[4];
    int i;

    for (i = 0; i < 4; i++)
        rects[i] = rect;

    if ([[NSGraphicsContext currentContext] isFlipped]) {
        colors[0] = [NSColor whiteColor];
        colors[1] = [NSColor controlShadowColor];
        rects[1].size.width -= 1;
        rects[1].size.height -= 1;
        colors[2] = [NSColor blackColor];
        rects[2].origin.x += 1;
        rects[2].origin.y += 1;
        rects[2].size.width -= 3;
        rects[2].size.height -= 3;
        colors[3] = [NSColor controlColor];
        rects[3].origin.x += 2;
        rects[3].origin.y += 2;
        rects[3].size.width -= 3;
        rects[3].size.height -= 3;
    } else {
        colors[0] = [NSColor whiteColor];
        colors[1] = [NSColor controlShadowColor];
        rects[1].origin.y += 1;
        rects[1].size.width -= 1;
        rects[1].size.height -= 1;
        colors[2] = [NSColor blackColor];
        rects[2].origin.x += 1;
        rects[2].origin.y += 2;
        rects[2].size.width -= 3;
        rects[2].size.height -= 3;
        colors[3] = [NSColor controlColor];
        rects[3].origin.x += 2;
        rects[3].origin.y += 1;
        rects[3].size.width -= 3;
        rects[3].size.height -= 3;
    }

    NSDrawColorRects(rect, clipRect, rects, colors, 4);
}

void NSDrawWhiteBezel(NSRect rect, NSRect clipRect) {
    NSRect rects[7];
    NSColor *colors[7];
    int i;

    for (i = 0; i < 7; i++)
        rects[i] = rect;

    if ([[NSGraphicsContext currentContext] isFlipped]) {
        colors[0] = [NSColor whiteColor];
        colors[1] = [NSColor controlShadowColor];
        rects[1].size.height = 1;
        colors[2] = [NSColor controlShadowColor];
        rects[2].size.width = 1;
        rects[2].size.height -= 1;
        colors[3] = [NSColor controlColor];
        rects[3].origin.x += 1;
        rects[3].origin.y += 1;
        rects[3].size.width -= 2;
        rects[3].size.height -= 2;
        colors[4] = [NSColor blackColor];
        rects[4].origin.x += 1;
        rects[4].origin.y += 1;
        rects[4].size.width -= 2;
        rects[4].size.height = 1;
        colors[5] = [NSColor blackColor];
        rects[5].origin.x += 1;
        rects[5].origin.y += 1;
        rects[5].size.width = 1;
        rects[5].size.height -= 3;
        colors[6] = [NSColor whiteColor];
        rects[6].origin.x += 2;
        rects[6].origin.y += 2;
        rects[6].size.width -= 4;
        rects[6].size.height -= 4;
    } else {
        colors[0] = [NSColor whiteColor];
        colors[1] = [NSColor controlShadowColor];
        rects[1].origin.y += rect.size.height;
        rects[1].size.height = 1;
        colors[2] = [NSColor controlShadowColor];
        rects[2].size.width = 1;
        rects[2].origin.y += 1;
        rects[2].size.height -= 1;
        colors[3] = [NSColor controlColor];
        rects[3].origin.x += 1;
        rects[3].origin.y += 1;
        rects[3].size.width -= 2;
        rects[3].size.height -= 2;
        colors[4] = [NSColor blackColor];
        rects[4].origin.x += 1;
        rects[4].origin.y += rect.size.height - 1;
        rects[4].size.width -= 2;
        rects[4].size.height = 1;
        colors[5] = [NSColor blackColor];
        rects[5].origin.x += 1;
        rects[5].origin.y += 2;
        rects[5].size.width = 1;
        rects[5].size.height -= 3;
        colors[6] = [NSColor whiteColor];
        rects[6].origin.x += 2;
        rects[6].origin.y += 2;
        rects[6].size.width -= 4;
        rects[6].size.height -= 3;
    }

    NSDrawColorRects(rect, clipRect, rects, colors, 7);
}

void NSDrawDarkBezel(NSRect rect, NSRect clipRect) {
    NSDrawGrayBezel(rect, clipRect);
}

void NSDrawLightBezel(NSRect rect, NSRect clipRect) {
    NSDrawWhiteBezel(rect, clipRect);
}

void NSDrawGroove(NSRect rect, NSRect clipRect) {
    NSRect rects[4];
    NSColor *colors[4];
    int i;

    for (i = 0; i < 4; i++)
        rects[i] = rect;

    if ([[NSGraphicsContext currentContext] isFlipped]) {
        colors[0] = [NSColor controlShadowColor];
        colors[1] = [NSColor whiteColor];
        rects[1].origin.x += 1;
        rects[1].origin.y += 1;
        colors[2] = [NSColor controlShadowColor];
        rects[2].origin.x += 2;
        rects[2].origin.y += 2;
        rects[2].size.width -= 3;
        rects[2].size.height -= 3;
        colors[3] = [NSColor controlColor];
        rects[3].origin.x += 2;
        rects[3].origin.y += 2;
        rects[3].size.width -= 4;
        rects[3].size.height -= 4;
    } else {
        colors[0] = [NSColor controlShadowColor];
        colors[1] = [NSColor whiteColor];
        rects[1].origin.x += 1;
        rects[1].size.height -= 1;
        colors[2] = [NSColor controlShadowColor];
        rects[2].origin.x += 2;
        rects[2].origin.y += 1;
        rects[2].size.width -= 3;
        rects[2].size.height -= 3;
        colors[3] = [NSColor controlColor];
        rects[3].origin.x += 2;
        rects[3].origin.y += 2;
        rects[3].size.width -= 4;
        rects[3].size.height -= 4;
    }

    NSDrawColorRects(rect, clipRect, rects, colors, 4);
}

void NSDrawWindowBackground(NSRect rect) {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(rect);
}

// Private: paints the background of a menu, its background colour, over the
// bounds (limited to clipRect unless that is empty). The menu window's frame
// line is not part of it. The flags (pop-up menu or not) do not change the
// colour in Darling.
void NSDrawMenuBackground(NSRect bounds, NSRect clipRect, NSUInteger flags) {
    NSRect rect = NSIsEmptyRect(clipRect) ? bounds : NSIntersectionRect(bounds, clipRect);

    if (NSIsEmptyRect(rect))
        return;
    [[NSColor menuBackgroundColor] setFill];
    NSRectFill(rect);
}

// Private: the parameters CoreGraphics takes for a focus ring style
// (CGStyleCreateFocusRingWithColor). Field layout as WebKit declares it, in
// its BSD-licensed PAL headers (pal/spi/cg/CoreGraphicsSPI.h).
struct _NSCGFocusRingStyle {
    unsigned int version;
    int32_t tint;     // 0 blue, 1 graphite
    int32_t ordering; // 0 ring only, 1 below the shape, 2 above it
    CGFloat alpha;
    CGFloat radius;
    CGFloat threshold;
    CGRect bounds;
    int accumulate;
};

// Private: fills in the focus ring style for a placement at a time into the
// ring's appearance animation, and returns whether the animation is still
// running. Observed on macOS 26.7.3 and 10.14.4 (black-box, the same on both):
// the ring settles 0.25 s in at alpha 0.5, radius 3.00438541 and threshold
// 0.15; before that it grows in from radius 28 and alpha 0, and the call
// returns YES. Version, tint (whatever the control tint), bounds and
// accumulation are 0; the ordering is the placement's.
// Darling's focus rings do not animate, so every time gets the settled style,
// and the call returns NO.
// Test: tests/appkit-webkit-private-functions.m
BOOL NSInitializeCGFocusRingStyleForTime(NSFocusRingPlacement placement, void *style, NSTimeInterval time) {
    struct _NSCGFocusRingStyle *ring = style;

    if (ring == NULL)
        return NO;

    memset(ring, 0, sizeof(*ring));
    switch (placement) {
    case NSFocusRingBelow:
        ring->ordering = 1;
        break;
    case NSFocusRingAbove:
        ring->ordering = 2;
        break;
    default:
        ring->ordering = 0;
        break;
    }
    ring->alpha = 0.5;
    ring->radius = 3.00438541;
    ring->threshold = 0.15;
    ring->bounds = CGRectZero;
    return NO;
}

NSRect NSDrawTiledRects(NSRect bounds, NSRect clip, const NSRectEdge *sides,
                        const CGFloat *grays, int count)
{
    return bounds;
}

void NSHighlightRect(NSRect rect) {
    [[NSColor highlightColor] setFill];
    CGContextFillRect(NSCurrentGraphicsPort(), rect);
}

void NSCopyBits(int gState, NSRect rect, NSPoint point) {
    CGContextCopyBits(NSCurrentGraphicsPort(), rect, point, gState);
}

// NSBestDepth and the NSWindowDepth helpers. The depths a window can use are
// the three RGB depths declared in NSGraphics.h; the helpers describe those.
// NSBestDepth picks the smallest available depth whose samples are at least
// the requested size, falling back to the deepest one, and reports an exact
// match only for an RGB colour space and a non-planar request that names the
// samples and pixels of that depth.
static const NSWindowDepth availableDepths[] = {
    NSWindowDepthTwentyfourBitRGB, NSWindowDepthSixtyfourBitRGB,
    NSWindowDepthOnehundredtwentyeightBitRGB, 0
};

const NSWindowDepth *NSAvailableWindowDepths(void) {
    return availableDepths;
}

NSInteger NSBitsPerSampleFromDepth(NSWindowDepth depth) {
    switch (depth) {
    case NSWindowDepthTwentyfourBitRGB:
        return 8;
    case NSWindowDepthSixtyfourBitRGB:
        return 16;
    case NSWindowDepthOnehundredtwentyeightBitRGB:
        return 32;
    }

    return 0;
}

BOOL NSPlanarFromDepth(NSWindowDepth depth) {
    return NO;
}

NSColorSpaceName NSColorSpaceFromDepth(NSWindowDepth depth) {
    if (NSBitsPerSampleFromDepth(depth) == 0)
        return nil;

    return NSCalibratedRGBColorSpace;
}

NSWindowDepth NSBestDepth(NSColorSpaceName colorSpace, NSInteger bitsPerSample,
                          NSInteger bitsPerPixel, BOOL planar,
                          BOOL *exactMatch)
{
    NSWindowDepth best = NSWindowDepthOnehundredtwentyeightBitRGB;
    int i;

    for (i = 0; availableDepths[i] != 0; i++) {
        if (NSBitsPerSampleFromDepth(availableDepths[i]) >= bitsPerSample) {
            best = availableDepths[i];
            break;
        }
    }

    if (exactMatch != NULL) {
        BOOL rgb = [colorSpace isEqualToString: NSCalibratedRGBColorSpace] ||
                   [colorSpace isEqualToString: NSDeviceRGBColorSpace];

        *exactMatch = rgb && !planar &&
                      NSBitsPerSampleFromDepth(best) == bitsPerSample &&
                      NSBitsPerPixelFromDepth(best) == bitsPerPixel;
    }

    return best;
}

void NSBeep(void) {
    [[NSDisplay currentDisplay] beep];
}

void NSEnableScreenUpdates(void) {
}

void NSDisableScreenUpdates(void) {
}

void NSShowAnimationEffect(NSAnimationEffect effect, NSPoint center,
                           NSSize size, id delegate, SEL didEndSelector,
                           void *context)
{
    [NSPoofAnimation poofAtLocation: center
                               size: size
                  animationDelegate: delegate
                     didEndSelector: didEndSelector
                        contextInfo: context];
}

void NSSetFocusRingStyle(NSFocusRingPlacement placement) {
    [[NSGraphicsContext currentContext] _setFocusRingPlacement: (NSInteger) placement + 1 outerOnly: NO];
}

// The focus ring is a band along the outline of the shape: two points outside it (a bright first point and a faint
// second one) and, unless the ring is drawn from outside the shape, two points inside it.
//
// QUIRK: the band profile and colour are the ones sampled from a keyboard-focused push button rendered on macOS
// 10.14.4 at 1x (black-box observation, tier 2): over a white bezel the rows across the edge, from outside inwards,
// were about 7%, 49%, then 42% of one blue (62, 150, 253), 0% two points out. The documentation only describes a
// soft blue ring in the keyboard focus indicator colour. Test: appkit-focus-ring.m
// (test_quirk_focus_ring_push_button_profile)
static const CGFloat kFocusRingRed = 62.0 / 255.0, kFocusRingGreen = 150.0 / 255.0, kFocusRingBlue = 253.0 / 255.0;

static void focusRingStroke(CGContextRef context, CGPathRef path, CGFloat width, CGFloat alpha) {
    CGContextSetRGBStrokeColor(context, kFocusRingRed, kFocusRingGreen, kFocusRingBlue, alpha);
    CGContextSetLineWidth(context, width);
    CGContextSetLineDash(context, 0, NULL, 0);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextBeginPath(context);
    CGContextAddPath(context, path);
    CGContextStrokePath(context);
}

static void focusRingBand(CGContextRef context, CGPathRef path, BOOL outside, BOOL inside) {
    // a rectangle around the shape, for the clip that leaves out the inside of the shape
    CGRect clipBounds = CGRectInset(CGPathGetBoundingBox(path), -8, -8);

    if (outside) {
        CGContextSaveGState(context);
        CGContextBeginPath(context);
        CGContextAddRect(context, clipBounds);
        CGContextAddPath(context, path);
        CGContextEOClip(context);
        // 2 points out at 7%, the first point out at 49% in all (7% below it)
        focusRingStroke(context, path, 4.0, 0.075);
        focusRingStroke(context, path, 2.0, 0.449);
        CGContextRestoreGState(context);
    }
    if (inside) {
        CGContextSaveGState(context);
        CGContextBeginPath(context);
        CGContextAddPath(context, path);
        CGContextClip(context);
        focusRingStroke(context, path, 4.0, 0.45);
        CGContextRestoreGState(context);
    }
}

// Called by the fill and stroke functions with the shape about to be painted; draws what the focus ring style asks
// for before the shape and returns NO if the shape itself is not to be painted (NSFocusRingOnly).
BOOL _NSFocusRingBeforePaintingPath(CGContextRef context, CGPathRef path) {
    NSGraphicsContext *current = [NSGraphicsContext currentContext];
    NSInteger placement = [current _focusRingPlacement];

    if (placement == 0 || [current graphicsPort] != context)
        return YES;

    BOOL outerOnly = [current _focusRingOuterOnly];

    if (placement - 1 == NSFocusRingAbove)
        return YES;
    CGContextSaveGState(context);
    focusRingBand(context, path, YES, !outerOnly && placement - 1 == NSFocusRingOnly);
    CGContextRestoreGState(context);
    return placement - 1 != NSFocusRingOnly;
}

void _NSFocusRingAfterPaintingPath(CGContextRef context, CGPathRef path) {
    NSGraphicsContext *current = [NSGraphicsContext currentContext];

    if ([current _focusRingPlacement] - 1 != NSFocusRingAbove || [current graphicsPort] != context)
        return;
    CGContextSaveGState(context);
    focusRingBand(context, path, YES, ![current _focusRingOuterOnly]);
    CGContextRestoreGState(context);
}

// The two frames below are measured from the observable behaviour of the functions on macOS 26.7.3 and 10.14.4
// (black-box: the pixels they draw into a bitmap context, identical on both): a frame inside the rect, the inside
// untouched, darker at the top than at the sides and the bottom, lighter when disabled. Probe:
// vd-upstream/mac-probes/gog-blockers/appkit-carbon-theme.m. Test: appkit-carbon-theme-draw.

typedef struct {
    CGFloat top, side, bottom, topCorner, bottomCorner;
} ThemeRing;

static void themeFillGray(NSRect rect, CGFloat gray) {
    [[NSColor colorWithDeviceWhite: gray alpha: 1.0] set];
    NSRectFill(rect);
}

// One frame ring of `rect`, one point wide. The top row is the one at the largest y unless the context is flipped.
static void themeDrawRing(NSRect rect, BOOL flipped, ThemeRing ring) {
    if (rect.size.width < 2 || rect.size.height < 2)
        return;
    CGFloat topY = flipped ? NSMinY(rect) : NSMaxY(rect) - 1;
    CGFloat bottomY = flipped ? NSMaxY(rect) - 1 : NSMinY(rect);
    CGFloat sideMinY = MIN(topY, bottomY) + 1, sideHeight = rect.size.height - 2;

    themeFillGray(NSMakeRect(NSMinX(rect), topY, rect.size.width, 1), ring.top);
    themeFillGray(NSMakeRect(NSMinX(rect), bottomY, rect.size.width, 1), ring.bottom);
    if (sideHeight > 0) {
        themeFillGray(NSMakeRect(NSMinX(rect), sideMinY, 1, sideHeight), ring.side);
        themeFillGray(NSMakeRect(NSMaxX(rect) - 1, sideMinY, 1, sideHeight), ring.side);
    }
    themeFillGray(NSMakeRect(NSMinX(rect), topY, 1, 1), ring.topCorner);
    themeFillGray(NSMakeRect(NSMaxX(rect) - 1, topY, 1, 1), ring.topCorner);
    themeFillGray(NSMakeRect(NSMinX(rect), bottomY, 1, 1), ring.bottomCorner);
    themeFillGray(NSMakeRect(NSMaxX(rect) - 1, bottomY, 1, 1), ring.bottomCorner);
}

void _NSDrawCarbonThemeBezel(NSRect rect, BOOL enabled, BOOL flipped) {
    static const ThemeRing enabledOuter = {0x7c / 255.0, 0xc3 / 255.0, 0xdd / 255.0, 0x69 / 255.0, 0xb9 / 255.0};
    static const ThemeRing enabledInner = {0xc3 / 255.0, 0xf0 / 255.0, 0xfe / 255.0, 0xb9 / 255.0, 0xf0 / 255.0};
    static const ThemeRing disabledOuter = {0xbe / 255.0, 0xe1 / 255.0, 0xee / 255.0, 0xb4 / 255.0, 0xdc / 255.0};
    static const ThemeRing disabledInner = {0xe1 / 255.0, 0xf8 / 255.0, 1.0, 0xdc / 255.0, 0xf8 / 255.0};
    themeDrawRing(rect, flipped, enabled ? enabledOuter : disabledOuter);
    themeDrawRing(NSInsetRect(rect, 1, 1), flipped, enabled ? enabledInner : disabledInner);
}

void _NSDrawCarbonThemeListBox(NSRect rect, BOOL enabled, BOOL flipped, BOOL active) {
    static const ThemeRing activeRing = {0x73 / 255.0, 0x99 / 255.0, 0x99 / 255.0, 0x73 / 255.0, 0x99 / 255.0};
    static const ThemeRing inactiveRing = {0x8e / 255.0, 0xbe / 255.0, 0xbe / 255.0, 0x8e / 255.0, 0xbe / 255.0};
    static const ThemeRing disabledRing = {0x99 / 255.0, 0xac / 255.0, 0xac / 255.0, 0x99 / 255.0, 0xac / 255.0};
    themeDrawRing(rect, flipped, !enabled ? disabledRing : (active ? activeRing : inactiveRing));
}
