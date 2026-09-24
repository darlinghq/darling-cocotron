#include <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>

typedef struct {
    int moves, closes, curves;
    CGFloat minX, minY, maxX, maxY;
} Shape;

static void addPoint(Shape *shape, CGPoint p) {
    if (p.x < shape->minX) shape->minX = p.x;
    if (p.y < shape->minY) shape->minY = p.y;
    if (p.x > shape->maxX) shape->maxX = p.x;
    if (p.y > shape->maxY) shape->maxY = p.y;
}

static void visit(void *info, const CGPathElement *element) {
    Shape *shape = info;
    int points = 0;

    switch (element->type) {
    case kCGPathElementMoveToPoint: shape->moves++; points = 1; break;
    case kCGPathElementAddLineToPoint: points = 1; break;
    case kCGPathElementAddQuadCurveToPoint: shape->curves++; points = 2; break;
    case kCGPathElementAddCurveToPoint: shape->curves++; points = 3; break;
    case kCGPathElementCloseSubpath: shape->closes++; break;
    }
    for (int i = 0; i < points; i++)
        addPoint(shape, element->points[i]);
}

static int failures;

static void expect(int condition, const char *label) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", label);
    failures += !condition;
}

static Shape shapeOf(CTFontRef font, UniChar character, const CGAffineTransform *xform) {
    Shape shape = {0, 0, 0, INFINITY, INFINITY, -INFINITY, -INFINITY};
    CGGlyph glyph = 0;

    if (!CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) || glyph == 0) {
        printf("FAIL no glyph for '%c'\n", character);
        failures++;
        return shape;
    }
    CGPathRef path = CTFontCreatePathForGlyph(font, glyph, xform);
    if (path == NULL) {
        printf("FAIL no path for '%c'\n", character);
        failures++;
        return shape;
    }
    CGPathApply(path, &shape, visit);
    CGPathRelease(path);
    return shape;
}

static int near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }

int main(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 100, NULL);
    CTFontRef half = CTFontCreateWithName(CFSTR("Helvetica"), 50, NULL);
    CGRect fontBox = CTFontGetBoundingBox(font);

    Shape H = shapeOf(font, 'H', NULL);
    printf("H: moves=%d closes=%d box=(%g,%g)-(%g,%g)\n", H.moves, H.closes, H.minX, H.minY, H.maxX, H.maxY);
    expect(H.moves == 1 && H.closes == 1, "H is one closed contour");
    expect(fabs(H.minY) < 0.5 && H.maxY > 55 && H.maxY < 85, "H stands on the baseline at cap height");
    expect(H.minX >= fontBox.origin.x && H.maxX <= CGRectGetMaxX(fontBox) &&
           H.minY >= fontBox.origin.y && H.maxY <= CGRectGetMaxY(fontBox), "H lies inside the font bounding box");

    CGGlyph hGlyph;
    UniChar hChar = 'H';
    CGSize advance;
    CTFontGetGlyphsForCharacters(font, &hChar, &hGlyph, 1);
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &hGlyph, &advance, 1);
    expect(H.minX >= 0 && H.maxX <= advance.width, "H lies within its advance");

    Shape O = shapeOf(font, 'O', NULL);
    expect(O.moves == 2 && O.closes == 2 && O.curves > 0, "O is two closed curved contours");
    Shape i = shapeOf(font, 'i', NULL);
    expect(i.moves == 2 && i.closes == 2, "i is two closed contours");
    Shape p = shapeOf(font, 'p', NULL);
    expect(p.minY < -10, "p descends below the baseline");

    Shape H50 = shapeOf(half, 'H', NULL);
    expect(near(H50.minX * 2, H.minX) && near(H50.maxX * 2, H.maxX) && near(H50.maxY * 2, H.maxY),
           "outline scales with the font size");

    CGAffineTransform xform = CGAffineTransformMake(2, 0, 0, 2, 10, 20);
    Shape Ht = shapeOf(font, 'H', &xform);
    expect(near(Ht.minX, H.minX * 2 + 10) && near(Ht.maxX, H.maxX * 2 + 10) &&
           near(Ht.minY, H.minY * 2 + 20) && near(Ht.maxY, H.maxY * 2 + 20), "transform is applied");

    UniChar spaceChar = ' ';
    CGGlyph space = 0;
    CTFontGetGlyphsForCharacters(font, &spaceChar, &space, 1);
    CGPathRef spacePath = CTFontCreatePathForGlyph(font, space, NULL);
    expect(spacePath != NULL && CGPathIsEmpty(spacePath), "space has an empty outline");
    if (spacePath) CGPathRelease(spacePath);

    CFRelease(half);
    CFRelease(font);
    printf("failures=%d\n", failures);
    return failures != 0;
}
