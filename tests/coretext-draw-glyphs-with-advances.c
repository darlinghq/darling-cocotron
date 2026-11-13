/* Copyright (C) 2026 Lubos Dolezel */
/* CTFontDrawGlyphsWithAdvances draws from the context's text position, uses
 * the font and size of the CTFont, and advances the text position by the
 * advances (observed on macOS 10.14.4). */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

extern void CTFontDrawGlyphsWithAdvances(CTFontRef, const CGGlyph *, const CGSize *, size_t, CGContextRef);
extern bool CTFontShouldAntiAlias(CTFontRef);

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 40, NULL);
    CHECK(font != NULL);
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceRGB();
    unsigned char pixels[200 * 100 * 4];
    memset(pixels, 0, sizeof pixels);
    CGContextRef ctx = CGBitmapContextCreate(pixels, 200, 100, 8, 800, gray, kCGImageAlphaPremultipliedLast);
    CHECK(ctx != NULL);
    CGContextSetGrayFillColor(ctx, 1, 1);

    UniChar chars[2] = {'H', 'H'};
    CGGlyph glyphs[2];
    CHECK(CTFontGetGlyphsForCharacters(font, chars, glyphs, 2));
    CGSize advances[2] = {{50, 0}, {60, 0}};

    CGContextSetTextPosition(ctx, 10, 20);
    CTFontDrawGlyphsWithAdvances(font, glyphs, advances, 2, ctx);
    CGPoint after = CGContextGetTextPosition(ctx);
    CHECK(after.x == 120 && after.y == 20);

    int lit = 0;
    for (size_t i = 0; i < sizeof pixels; i++)
        lit += pixels[i] != 0;
    CHECK(lit > 0);

    // Nothing to draw, or nowhere to draw it, is not an error.
    CTFontDrawGlyphsWithAdvances(font, glyphs, advances, 0, ctx);
    CTFontDrawGlyphsWithAdvances(font, glyphs, advances, 2, NULL);
    CHECK(CGContextGetTextPosition(ctx).x == 120);

    (void)CTFontShouldAntiAlias(font);

    CGContextRelease(ctx);
    CGColorSpaceRelease(gray);
    CFRelease(font);
    if (!failures)
        puts("PASS");
    return failures != 0;
}
