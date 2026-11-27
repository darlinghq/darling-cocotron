// Copyright (C) 2026 Darling Developers
// Build: clang -framework AppKit appkit-svg-root-attributes.m (no ARC)
#import <AppKit/AppKit.h>
// NSRenderSVGData has hidden visibility in AppKit; compile the unit under distinct symbols.
#define _NSSVGState SVGTestState
#define _NSSVGParserDelegate SVGTestParserDelegate
#define NSRenderSVGData SVGTestRenderSVGData
#include "../AppKit/NSSVGRenderer.m"
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static const unsigned char *pixelAt(NSBitmapImageRep *rep, int x, int y) {
    return [rep bitmapData] + y * [rep bytesPerRow] + x * 4;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString *svg =
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 20 20\" "
        "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
        "<rect x=\"2\" y=\"2\" width=\"6\" height=\"6\"/>"
        "<path d=\"M12 4h6\"/>"
        "<rect x=\"12\" y=\"12\" width=\"6\" height=\"6\" fill=\"#ff0000\" stroke=\"none\"/>"
        "</svg>";
    NSData *data = [svg dataUsingEncoding: NSUTF8StringEncoding];
    NSBitmapImageRep *rep = SVGTestRenderSVGData(data, NSMakeSize(20, 20), 1.0);
    CHECK(rep != nil);
    if (rep != nil) {
        CHECK([rep pixelsWide] == 20 && [rep pixelsHigh] == 20);
        CHECK(pixelAt(rep, 0, 0)[3] == 0);

        const unsigned char *border = pixelAt(rep, 2, 5);
        const unsigned char *interior = pixelAt(rep, 5, 5);
        CHECK(border[0] < 20 && border[1] < 20 && border[2] < 20 && border[3] > 200);
        CHECK(interior[3] == 0);

        const unsigned char *strokeMid = pixelAt(rep, 15, 4);
        CHECK(strokeMid[0] < 20 && strokeMid[1] < 20 && strokeMid[2] < 20 && strokeMid[3] > 200);

        const unsigned char *redFill = pixelAt(rep, 15, 15);
        CHECK(redFill[0] > 240 && redFill[1] < 15 && redFill[2] < 15 && redFill[3] > 240);
    }

    [pool release];
    if (failures == 0)
        printf("PASS appkit-svg-root-attributes\n");
    return failures ? 1 : 0;
}
