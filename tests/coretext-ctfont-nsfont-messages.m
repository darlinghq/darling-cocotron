/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CTFontRef and NSFont are toll-free bridged, so a font made with a CoreText
 * function can be sent NSFont's messages, and text set in it can be laid out
 * and drawn by AppKit. The program builds and runs on macOS too, where the
 * same expectations hold (macOS 26.7.3).
 */
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

#define TRY(label, expr)                                                         \
    do {                                                                         \
        BOOL ok_ = NO;                                                           \
        @try {                                                                   \
            ok_ = (expr);                                                        \
        } @catch (NSException * e) {                                             \
            printf("  raised %s\n", [[e reason] UTF8String]);                    \
        }                                                                        \
        expect(ok_, label);                                                      \
    } while (0)

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        CTFontRef ctFont = CTFontCreateWithName(CFSTR("Helvetica"), 13, NULL);
        expect(ctFont != NULL, "CTFontCreateWithName gives a font");
        NSFont *font = (NSFont *) ctFont;

        TRY("a CTFont answers -coveredCharacterSet with 'A' in it",
            [[font coveredCharacterSet] characterIsMember:'A']);
        TRY("a CTFont responds to -screenFontWithRenderingMode:",
            [font respondsToSelector:@selector(screenFontWithRenderingMode:)]);
        TRY("its screen font has the same size",
            [[font screenFontWithRenderingMode:NSFontDefaultRenderingMode] pointSize] == 13 ||
                [font screenFontWithRenderingMode:NSFontDefaultRenderingMode] == nil);
        TRY("a CTFont answers -renderingMode", ([font renderingMode], YES));
        TRY("a CTFont answers -isFixedPitch with NO for Helvetica", ![font isFixedPitch]);
        TRY("a CTFont answers -displayName", [[font displayName] length] > 0);
        TRY("a CTFont answers -fontDescriptor", [font fontDescriptor] != nil);

        NSDictionary *attributes = @{NSFontAttributeName: (id) ctFont};
        NSMutableAttributedString *text =
                [[NSMutableAttributedString alloc] initWithString:@"Line 1" attributes:attributes];
        TRY("fixing the attributes of a string set in a CTFont does not raise",
            ([text fixAttributesInRange:NSMakeRange(0, [text length])], YES));

        NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:text];
        NSLayoutManager *lm = [[NSLayoutManager alloc] init];
        NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(500, 100)];
        [lm addTextContainer:container];
        [storage addLayoutManager:lm];
        TRY("text set in a CTFont is laid out",
            ([lm ensureLayoutForTextContainer:container], NSWidth([lm usedRectForTextContainer:container]) > 10));

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL pixelsWide:100 pixelsHigh:30 bitsPerSample:8
                         samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                          colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        TRY("a string set in a CTFont is drawn",
            ([@"Line 1" drawAtPoint:NSMakePoint(2, 5) withAttributes:attributes], YES));
        TRY("a CTFont can be made the current font with -set", ([font set], YES));
        [NSGraphicsContext restoreGraphicsState];

        [rep release];
        [container release];
        [lm release];
        [storage release];
        [text release];
        CFRelease(ctFont);
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
