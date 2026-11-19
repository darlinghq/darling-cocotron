/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009 Markus Hitter <mah@jump-ing.de>

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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSStringDrawing.h>
#import <CoreText/CoreText.h>

// NSStringDrawingContext lives in UIFoundation, as on macOS; the setter is
// only used here to report the layout results.
@interface NSStringDrawingContext ()
@property NSRect totalBounds;
@end

// The drawing and measuring entry points all funnel into the helpers below.
// Without NSStringDrawingUsesLineFragmentOrigin the text is a single
// unwrapped line whose baseline sits at the rect origin; with it the rect
// origin is the top-left of the first line fragment and the text wraps to the
// rect width.

static NSString *const ellipsisString = @"…";

static NSSize sizeOf(NSAttributedString *text, NSSize maxSize) {
    return [[NSStringDrawer sharedStringDrawer] sizeOfAttributedString: text
                                                                inSize: maxSize];
}

static NSSize fittedSizeOf(NSAttributedString *text, NSSize limit) {
    return [[NSStringDrawer sharedStringDrawer] sizeOfAttributedString: text
                                                         fittingInSize: limit
                                                         lastLineRange: NULL
                                                         hasHiddenText: NULL];
}

static NSSize limitedSize(NSSize size) {
    if (size.width <= 0)
        size.width = NSStringDrawerLargeDimension;
    if (size.height <= 0)
        size.height = NSStringDrawerLargeDimension;
    return size;
}

static NSFont *firstFont(NSAttributedString *text) {
    NSFont *font = nil;
    if ([text length] > 0)
        font = [text attribute: NSFontAttributeName atIndex: 0 effectiveRange: NULL];
    return font != nil ? font : [NSFont systemFontOfSize: 12];
}

// Distance from the baseline to the bottom of the line fragment.
static CGFloat lineDescent(NSAttributedString *text) {
    return ceil(-[firstFont(text) descender]);
}

// Replaces the end of the last line that fits with an ellipsis when more text
// follows it, as NSStringDrawingTruncatesLastVisibleLine describes.
static NSAttributedString *truncateLastVisibleLine(NSAttributedString *text, NSSize size) {
    BOOL hidden = NO;
    NSRange line;
    [[NSStringDrawer sharedStringDrawer] sizeOfAttributedString: text
                                                  fittingInSize: size
                                                  lastLineRange: &line
                                                  hasHiddenText: &hidden];
    if (!hidden || line.length == 0)
        return text;

    NSString *plain = [text string];
    NSUInteger end = NSMaxRange(line);
    while (end > line.location) {
        unichar c = [plain characterAtIndex: end - 1];
        if (c != '\n' && c != '\r' && c != 0x2028 && c != 0x2029)
            break;
        end--;
    }

    NSDictionary *attributes = [text attributesAtIndex: end > line.location ? end - 1 : line.location
                                        effectiveRange: NULL];
    NSAttributedString *ellipsis =
            [[[NSAttributedString alloc] initWithString: ellipsisString
                                             attributes: attributes] autorelease];

    // Longest prefix of the line that still fits next to the ellipsis.
    NSUInteger low = 0, high = end - line.location;
    while (low < high) {
        NSUInteger mid = (low + high + 1) / 2;
        NSUInteger cut = line.location + mid;
        if (cut < [plain length]) {
            NSRange cluster = [plain rangeOfComposedCharacterSequenceAtIndex: cut];
            cut = cluster.location;
        }
        NSMutableAttributedString *candidate = [[[NSMutableAttributedString alloc]
                initWithAttributedString: [text attributedSubstringFromRange:
                        NSMakeRange(line.location, cut - line.location)]] autorelease];
        [candidate appendAttributedString: ellipsis];
        if (sizeOf(candidate, NSZeroSize).width <= size.width)
            low = mid;
        else
            high = mid - 1;
    }
    NSUInteger cut = line.location + low;
    if (cut < [plain length])
        cut = [plain rangeOfComposedCharacterSequenceAtIndex: cut].location;

    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc]
            initWithAttributedString: [text attributedSubstringFromRange:
                    NSMakeRange(0, cut)]] autorelease];
    [result appendAttributedString: ellipsis];
    return result;
}

// Bounds of the ink of a single line, with the baseline at y == 0, y up.
static NSRect inkBounds(NSAttributedString *text) {
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef) text);
    NSRect bounds = NSZeroRect;
    BOOL any = NO;
    for (id run in (NSArray *) CTLineGetGlyphRuns(line)) {
        CFIndex count = CTRunGetGlyphCount((CTRunRef) run);
        if (count == 0)
            continue;
        NSDictionary *attributes = (NSDictionary *) CTRunGetAttributes((CTRunRef) run);
        CTFontRef font = (CTFontRef) [attributes objectForKey: (id) kCTFontAttributeName];
        if (font == NULL)
            continue;
        CGGlyph *glyphs = malloc(sizeof(CGGlyph) * count);
        CGPoint *positions = malloc(sizeof(CGPoint) * count);
        CGRect *rects = malloc(sizeof(CGRect) * count);
        CTRunGetGlyphs((CTRunRef) run, CFRangeMake(0, count), glyphs);
        CTRunGetPositions((CTRunRef) run, CFRangeMake(0, count), positions);
        CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, glyphs, rects, count);
        for (CFIndex i = 0; i < count; i++) {
            if (CGRectIsEmpty(rects[i]))
                continue;
            NSRect r = NSOffsetRect(NSRectFromCGRect(rects[i]), positions[i].x, positions[i].y);
            bounds = any ? NSUnionRect(bounds, r) : r;
            any = YES;
        }
        free(glyphs);
        free(positions);
        free(rects);
    }
    CFRelease(line);
    return bounds;
}

// Bounding rect relative to the rect origin the string would be drawn at.
// *drawn receives the string that is actually laid out (it differs from text
// when the last visible line is truncated).
static NSRect boundsOf(NSAttributedString *text, NSSize size, NSStringDrawingOptions options,
                       NSAttributedString **drawn) {
    BOOL lineFragmentOrigin = (options & NSStringDrawingUsesLineFragmentOrigin) != 0;
    NSSize limit = limitedSize(size);

    if (lineFragmentOrigin &&
        (options & NSStringDrawingTruncatesLastVisibleLine) != 0 &&
        limit.height < NSStringDrawerLargeDimension)
        text = truncateLastVisibleLine(text, limit);
    if (drawn != NULL)
        *drawn = text;

    NSSize used = lineFragmentOrigin ? fittedSizeOf(text, limit) : sizeOf(text, NSZeroSize);
    NSRect bounds;
    if (lineFragmentOrigin) {
        bounds = NSMakeRect(0, 0, used.width, used.height);
    } else {
        CGFloat width = size.width > 0 ? MIN(used.width, size.width) : used.width;
        bounds = NSMakeRect(0, -lineDescent(text), width, used.height);
    }

    if ((options & NSStringDrawingUsesDeviceMetrics) != 0 && [text length] > 0) {
        NSRect ink = inkBounds(text);
        if (!NSIsEmptyRect(ink)) {
            // The ink rectangle replaces the typographic one; the line
            // fragment origin variant keeps the rect pinned to y == 0.
            bounds.origin.x = ink.origin.x;
            bounds.size = ink.size;
            bounds.origin.y = lineFragmentOrigin ? 0 : ink.origin.y;
        }
    }
    return bounds;
}

static NSRect boundingRect(NSAttributedString *text, NSSize size, NSStringDrawingOptions options,
                           NSStringDrawingContext *context) {
    NSRect bounds = boundsOf(text, size, options, NULL);
    [context setTotalBounds: bounds];
    return bounds;
}

static void drawInRect(NSAttributedString *text, NSRect rect, NSStringDrawingOptions options,
                       NSStringDrawingContext *context) {
    NSAttributedString *drawn = text;
    NSRect bounds = boundsOf(text, rect.size, options, &drawn);
    [context setTotalBounds: bounds];
    if ([drawn length] == 0)
        return;

    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    NSStringDrawer *drawer = [NSStringDrawer sharedStringDrawer];

    if ((options & NSStringDrawingUsesLineFragmentOrigin) != 0) {
        NSSize limit = limitedSize(rect.size);
        NSSize used = fittedSizeOf(drawn, limit);
        NSPoint point = flipped ? rect.origin : NSMakePoint(rect.origin.x, NSMaxY(rect) - used.height);
        // A container as tall as the fitting lines, so no clipped extra line is drawn.
        [drawer drawAttributedString: drawn atPoint: point inSize: NSMakeSize(limit.width, used.height)];
        return;
    }

    // Single line with its baseline on the rect origin, clipped to the width.
    NSSize used = sizeOf(drawn, NSZeroSize);
    CGFloat descent = lineDescent(drawn);
    NSPoint point = rect.origin;
    point.y = flipped ? rect.origin.y - (used.height - descent) : rect.origin.y - descent;

    CGContextRef port = NSCurrentGraphicsPort();
    CGContextSaveGState(port);
    if (rect.size.width > 0)
        CGContextClipToRect(port, CGRectMake(rect.origin.x, rect.origin.y - used.height * 2,
                                             rect.size.width, used.height * 4));
    [drawer drawAttributedString: drawn atPoint: point inSize: NSZeroSize];
    CGContextRestoreGState(port);
}

static NSAttributedString *attributedString(NSString *string, NSDictionary *attributes) {
    return [[[NSAttributedString alloc] initWithString: string
                                            attributes: attributes] autorelease];
}

@implementation NSString (NSStringDrawing)

- (void) drawAtPoint: (NSPoint) point
        withAttributes: (NSDictionary *) attributes
{
    [[NSStringDrawer sharedStringDrawer] drawString: self
                                     withAttributes: attributes
                                            atPoint: point
                                             inSize: NSZeroSize];
}

- (void) drawInRect: (NSRect) rect withAttributes: (NSDictionary *) attributes {
    [[NSStringDrawer sharedStringDrawer] drawString: self
                                     withAttributes: attributes
                                             inRect: rect];
}

- (NSSize) sizeWithAttributes: (NSDictionary *) attributes {
    NSRect rect = [self boundingRectWithSize: NSZeroSize
                                     options: 0
                                  attributes: attributes];
    return rect.size;
}

- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options
                     attributes: (NSDictionary *) attributes
                        context: (NSStringDrawingContext *) context
{
    return boundingRect(attributedString(self, attributes), size, options, context);
}

- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options
                     attributes: (NSDictionary *) attributes
{
    return [self boundingRectWithSize: size options: options attributes: attributes context: nil];
}

- (void) drawWithRect: (NSRect) rect
              options: (NSStringDrawingOptions) options
           attributes: (NSDictionary *) attributes
              context: (NSStringDrawingContext *) context
{
    drawInRect(attributedString(self, attributes), rect, options, context);
}

- (void) drawWithRect: (NSRect) rect
              options: (NSStringDrawingOptions) options
           attributes: (NSDictionary *) attributes
{
    [self drawWithRect: rect options: options attributes: attributes context: nil];
}

@end

@implementation NSAttributedString (NSStringDrawing)

- (void) drawAtPoint: (NSPoint) point {
    [[NSStringDrawer sharedStringDrawer] drawAttributedString: self
                                                      atPoint: point
                                                       inSize: NSZeroSize];
}

- (void) drawInRect: (NSRect) rect {
    [[NSStringDrawer sharedStringDrawer] drawAttributedString: self
                                                       inRect: rect];
}

- (void) drawWithRect: (NSRect) rect
              options: (NSStringDrawingOptions) options
              context: (NSStringDrawingContext *) context
{
    drawInRect(self, rect, options, context);
}

- (void) drawWithRect: (NSRect) rect options: (NSStringDrawingOptions) options {
    [self drawWithRect: rect options: options context: nil];
}

- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options
                        context: (NSStringDrawingContext *) context
{
    return boundingRect(self, size, options, context);
}

- (NSRect) boundingRectWithSize: (NSSize) size options: (NSStringDrawingOptions) options {
    return [self boundingRectWithSize: size options: options context: nil];
}

- (NSSize) size {
    return [[NSStringDrawer sharedStringDrawer]
            sizeOfAttributedString: self
                            inSize: NSZeroSize];
}

@end
