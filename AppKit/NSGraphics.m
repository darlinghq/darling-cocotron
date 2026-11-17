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
