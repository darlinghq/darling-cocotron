/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Titles drawn with a truncating line break mode (head, middle, tail) keep
 * whole composed character sequences next to the ellipsis, as AppKit's own
 * truncation does on macOS (a surrogate pair, a base letter with a combining
 * accent and a joined emoji sequence are never cut in the middle), and the
 * ellipsis is U+2026. Draws into an offscreen bitmap; no window server
 * needed. Every truncated rendering must be pixel-identical to the rendering
 * of some "kept head + ellipsis + kept tail" string whose cuts lie on
 * composed-sequence boundaries.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

@interface NSAttributedString (TitleTruncationPrivate)
- (void)_clipAndDrawInRect:(NSRect)rect lineBreakMode:(NSLineBreakMode)mode;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL onBoundary(NSString *s, NSUInteger pos)
{
    if (pos == 0 || pos >= [s length])
        return YES;
    return [s rangeOfComposedCharacterSequenceAtIndex: pos].location == pos;
}

static NSData *render(NSAttributedString *s, CGFloat width, NSLineBreakMode mode)
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL pixelsWide: 300 pixelsHigh: 30 bitsPerSample: 8
                     samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    memset([rep bitmapData], 0xff, [rep bytesPerRow] * [rep pixelsHigh]);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    [s _clipAndDrawInRect: NSMakeRect(2, 2, width, 24) lineBreakMode: mode];
    [NSGraphicsContext restoreGraphicsState];
    NSData *data = [NSData dataWithBytes: [rep bitmapData] length: [rep bytesPerRow] * [rep pixelsHigh]];
    [rep release];
    return data;
}

static void checkTruncation(NSString *name, NSString *text, NSLineBreakMode mode, const char *modeName)
{
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize: 13]};
    NSAttributedString *full = [[[NSAttributedString alloc] initWithString: text attributes: attrs] autorelease];
    NSUInteger n = [text length];
    CGFloat fullWidth = [full size].width;

    // Renderings of every candidate with cuts on composed-sequence boundaries, kept for the whole sweep.
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSUInteger a = 0; a <= n; a++) {
        for (NSUInteger b = 0; a + b <= n; b++) {
            if (mode == NSLineBreakByTruncatingTail && b)
                continue;
            if (mode == NSLineBreakByTruncatingHead && a)
                continue;
            if (!onBoundary(text, a) || !onBoundary(text, n - b))
                continue;
            NSString *s = [NSString stringWithFormat: @"%@…%@", [text substringToIndex: a],
                           [text substringFromIndex: n - b]];
            NSAttributedString *as = [[[NSAttributedString alloc] initWithString: s attributes: attrs] autorelease];
            [candidates addObject: render(as, 1000, NSLineBreakByClipping)];
        }
    }
    NSData *whole = render(full, 1000, NSLineBreakByClipping);

    // Below the width of the ellipsis itself the drawing is clipped, which no candidate string reproduces.
    NSAttributedString *dots = [[[NSAttributedString alloc] initWithString: @"\u2026" attributes: attrs] autorelease];
    int truncated = 0;
    for (CGFloat w = ceil([dots size].width) + 1; w < fullWidth; w += 3) {
        NSData *got = render(full, w, mode);
        char what[200];
        snprintf(what, sizeof what, "%s %s at width %.0f is a head/ellipsis/tail rendering on composed boundaries",
                 [name UTF8String], modeName, w);
        expect([candidates containsObject: got], what);
        if (![got isEqualToData: whole])
            truncated++;
    }
    char what[200];
    snprintf(what, sizeof what, "%s %s truncates somewhere in the sweep", [name UTF8String], modeName);
    expect(truncated > 0, what);
}

int main(void)
{
    @autoreleasepool {
        NSArray *strings = @[
            @[@"plain", @"ABCDEFGHIJ"],
            @[@"surrogate pair", @"AAAA\U0001F600BBBB"],
            @[@"combining accent", @"ABCDéFGHI"],
            @[@"joined emoji", @"AB\U0001F468‍\U0001F469‍\U0001F467CD"],
        ];
        for (NSArray *s in strings) {
            checkTruncation(s[0], s[1], NSLineBreakByTruncatingTail, "tail");
            checkTruncation(s[0], s[1], NSLineBreakByTruncatingHead, "head");
            checkTruncation(s[0], s[1], NSLineBreakByTruncatingMiddle, "middle");
        }

        // Degenerate rectangles and strings do not raise a range exception.
        NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize: 13]};
        NSAttributedString *abc = [[[NSAttributedString alloc] initWithString: @"ABC" attributes: attrs] autorelease];
        NSAttributedString *empty = [[[NSAttributedString alloc] initWithString: @"" attributes: attrs] autorelease];
        NSLineBreakMode modes[] = {NSLineBreakByTruncatingHead, NSLineBreakByTruncatingMiddle,
                                   NSLineBreakByTruncatingTail};
        for (int i = 0; i < 3; i++) {
            @try {
                render(abc, 0, modes[i]);
                render(abc, 1, modes[i]);
                render(empty, 20, modes[i]);
            } @catch (NSException *e) {
                fprintf(stderr, "FAIL: degenerate input raised %s\n", [[e reason] UTF8String]);
                failures++;
            }
        }
    }
    if (failures) {
        printf("attributed title truncation: FAIL (%d)\n", failures);
        return 1;
    }
    printf("attributed title truncation: PASS\n");
    return 0;
}
