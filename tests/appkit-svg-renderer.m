// Copyright (C) 2026 Darling Developers
//
// Tests NSSVGRenderer path/shape/transform rasterization used by NSAssetCatalog for SVG renditions.
#import <AppKit/AppKit.h>
#import "../AppKit/NSSVGRenderer.h"
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 20 20\">"
                     "<rect x=\"2\" y=\"2\" width=\"16\" height=\"16\" fill=\"#ff0000\"/>"
                     "<path d=\"M6 6 L14 6 L14 14 L6 14 Z\" fill=\"#0000ff\"/>"
                     "</svg>";
    NSData *data = [svg dataUsingEncoding: NSUTF8StringEncoding];
    NSBitmapImageRep *rep = NSRenderSVGData(data, NSMakeSize(20, 20), 1.0);
    CHECK(rep != nil);
    CHECK([rep pixelsWide] == 20 && [rep pixelsHigh] == 20);

    // Corner outside rect (0,0) is transparent; rect (3,3) is red; inner path (10,10) is blue.
    const unsigned char *p = [rep bitmapData];
    NSInteger bpr = [rep bytesPerRow];
    const unsigned char *c0 = p + 0 * bpr + 0 * 4;
    const unsigned char *c1 = p + 3 * bpr + 3 * 4;
    const unsigned char *c2 = p + 10 * bpr + 10 * 4;
    CHECK(c0[3] == 0);
    CHECK(c1[0] > 240 && c1[1] < 15 && c1[2] < 15 && c1[3] > 240);
    CHECK(c2[0] < 15 && c2[1] < 15 && c2[2] > 240 && c2[3] > 240);

    // Nil/empty data returns nil.
    CHECK(NSRenderSVGData(nil, NSMakeSize(16, 16), 1.0) == nil);
    CHECK(NSRenderSVGData([NSData data], NSMakeSize(16, 16), 1.0) == nil);

    [pool release];
    return failures ? 1 : 0;
}
