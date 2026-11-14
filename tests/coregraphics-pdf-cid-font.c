#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// A Type0 font with the Identity-H CMap and an embedded CIDFontType2
// (TrueType) font program (PDF 32000-1 9.7): each pair of bytes of a string is
// a CID, CIDToGIDMap turns it into a glyph of the font program, W and DW give
// the widths. The text position advances by the width times the font size
// (9.4.4), so does a TJ adjustment, and the next Tj starts where the last one
// ended.
//
// The font program is built here: a TrueType font without a cmap, as PDF
// producers embed subsets, with a narrow bar (glyph 1) and a wide block
// (glyph 2), both 700 units tall on a 1000 unit em. The page is drawn into a
// bitmap at 1 pixel per unit, and ink is looked for halfway up the glyphs.
// Exits non-zero on failure.

#define WIDTH 400
#define HEIGHT 300

static int failures;

static void append(CFMutableDataRef data, const char *format, ...) {
    char buffer[2048];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    CFDataAppendBytes(data, (const UInt8 *)buffer, length);
}

// ---- TrueType font program ----

static void put16(uint8_t **p, unsigned value) {
    (*p)[0] = value >> 8;
    (*p)[1] = value;
    *p += 2;
}

static void put32(uint8_t **p, uint32_t value) {
    put16(p, value >> 16);
    put16(p, value & 0xFFFF);
}

// A glyph that is one rectangle from (0,0) to (width,700), its contour
// clockwise as TrueType fills it.
static size_t rectangleGlyph(uint8_t *out, int width) {
    uint8_t *p = out;
    put16(&p, 1); // numberOfContours
    put16(&p, 0);
    put16(&p, 0);
    put16(&p, width);
    put16(&p, 700); // bounding box
    put16(&p, 3); // endPtsOfContours[0]
    put16(&p, 0); // instructionLength
    for (int i = 0; i < 4; i++)
        *p++ = 0x01; // on curve, two-byte coordinates
    // x: 0, 0, width, width (deltas)
    put16(&p, 0);
    put16(&p, 0);
    put16(&p, width);
    put16(&p, 0);
    // y: 0, 700, 700, 0 (deltas)
    put16(&p, 0);
    put16(&p, 700);
    put16(&p, 0);
    put16(&p, (uint16_t)-700);
    return p - out;
}

struct table {
    const char *tag;
    uint8_t data[128];
    size_t length;
};

static uint32_t checksum(const uint8_t *data, size_t length) {
    uint32_t sum = 0;
    for (size_t i = 0; i < length; i += 4) {
        uint32_t word = 0;
        for (size_t j = 0; j < 4; j++)
            word = (word << 8) | (i + j < length ? data[i + j] : 0);
        sum += word;
    }
    return sum;
}

// Writes the font program into `out`, returns its length.
static size_t buildFont(uint8_t *out) {
    struct table tables[6] = {{"glyf"}, {"head"}, {"hhea"}, {"hmtx"}, {"loca"}, {"maxp"}};
    uint8_t *p;

    // glyf: glyph 0 (.notdef) is empty, glyph 1 is 100 units wide, glyph 2 600.
    size_t bar = rectangleGlyph(tables[0].data, 100);
    size_t block = rectangleGlyph(tables[0].data + bar, 600);
    tables[0].length = bar + block;

    p = tables[1].data; // head
    put32(&p, 0x00010000);
    put32(&p, 0x00010000);
    put32(&p, 0); // checkSumAdjustment
    put32(&p, 0x5F0F3CF5);
    put16(&p, 0x000B); // flags
    put16(&p, 1000); // unitsPerEm
    for (int i = 0; i < 4; i++)
        put32(&p, 0); // created, modified
    put16(&p, 0);
    put16(&p, 0);
    put16(&p, 600);
    put16(&p, 700); // bounding box
    put16(&p, 0); // macStyle
    put16(&p, 8); // lowestRecPPEM
    put16(&p, 2); // fontDirectionHint
    put16(&p, 0); // indexToLocFormat: short offsets
    put16(&p, 0); // glyphDataFormat
    tables[1].length = p - tables[1].data;

    p = tables[2].data; // hhea
    put32(&p, 0x00010000);
    put16(&p, 800); // ascender
    put16(&p, (uint16_t)-200); // descender
    put16(&p, 0); // lineGap
    put16(&p, 1000); // advanceWidthMax
    put16(&p, 0);
    put16(&p, 0);
    put16(&p, 600); // minLeftSideBearing, minRightSideBearing, xMaxExtent
    put16(&p, 1);
    put16(&p, 0);
    put16(&p, 0); // caret
    for (int i = 0; i < 4; i++)
        put16(&p, 0); // reserved
    put16(&p, 0); // metricDataFormat
    put16(&p, 3); // numberOfHMetrics
    tables[2].length = p - tables[2].data;

    p = tables[3].data; // hmtx: the font's own advances, unlike the PDF's W
    put16(&p, 500);
    put16(&p, 0);
    put16(&p, 500);
    put16(&p, 0);
    put16(&p, 500);
    put16(&p, 0);
    tables[3].length = p - tables[3].data;

    p = tables[4].data; // loca, offsets / 2
    put16(&p, 0);
    put16(&p, 0);
    put16(&p, bar / 2);
    put16(&p, (bar + block) / 2);
    tables[4].length = p - tables[4].data;

    p = tables[5].data; // maxp 1.0
    put32(&p, 0x00010000);
    put16(&p, 3); // numGlyphs
    put16(&p, 4); // maxPoints
    put16(&p, 1); // maxContours
    put16(&p, 0);
    put16(&p, 0);
    put16(&p, 2); // maxZones
    for (int i = 0; i < 7; i++)
        put16(&p, 0);
    tables[5].length = p - tables[5].data;

    p = out;
    put32(&p, 0x00010000);
    put16(&p, 6); // numTables
    put16(&p, 64);
    put16(&p, 2);
    put16(&p, 32); // searchRange, entrySelector, rangeShift
    size_t offset = 12 + 6 * 16;
    for (int i = 0; i < 6; i++) {
        memcpy(p, tables[i].tag, 4);
        p += 4;
        put32(&p, checksum(tables[i].data, tables[i].length));
        put32(&p, offset);
        put32(&p, tables[i].length);
        offset += (tables[i].length + 3) & ~3;
    }
    for (int i = 0; i < 6; i++) {
        memcpy(p, tables[i].data, tables[i].length);
        memset(p + tables[i].length, 0, ((tables[i].length + 3) & ~3) - tables[i].length);
        p += (tables[i].length + 3) & ~3;
    }
    return p - out;
}

// ---- PDF ----

static CGPDFDocumentRef documentWithContent(const char *content) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CFIndex offsets[8];
    uint8_t font[1024];
    size_t fontLength = buildFont(font);
    // CIDToGIDMap: CID 0 -> 0, 1 -> 2 (block), 2 -> 1 (bar), 3 -> 1 (bar).
    static const uint8_t cidToGID[] = {0, 0, 0, 2, 0, 1, 0, 1};

    append(data, "%%PDF-1.4\n");
    offsets[0] = CFDataGetLength(data);
    append(data, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[1] = CFDataGetLength(data);
    append(data, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[2] = CFDataGetLength(data);
    append(data, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] "
                 "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>\nendobj\n",
           WIDTH, HEIGHT);
    offsets[3] = CFDataGetLength(data);
    append(data, "4 0 obj\n<< /Length %zu >>\nstream\n%s\nendstream\nendobj\n", strlen(content), content);
    offsets[4] = CFDataGetLength(data);
    append(data, "5 0 obj\n<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-H "
                 "/DescendantFonts [6 0 R] >>\nendobj\n");
    offsets[5] = CFDataGetLength(data);
    // CID 1 is 700 wide, CID 2 300 (a range entry), CID 3 has the default 1000.
    append(data, "6 0 obj\n<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Test "
                 "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> "
                 "/FontDescriptor 7 0 R /DW 1000 /W [1 [700] 2 2 300] /CIDToGIDMap 8 0 R >>\nendobj\n");
    offsets[6] = CFDataGetLength(data);
    append(data, "7 0 obj\n<< /Type /FontDescriptor /FontName /Test /Flags 4 "
                 "/FontBBox [0 0 600 700] /ItalicAngle 0 /Ascent 800 /Descent -200 "
                 "/CapHeight 700 /StemV 80 /FontFile2 9 0 R >>\nendobj\n");
    offsets[7] = CFDataGetLength(data);
    append(data, "8 0 obj\n<< /Length %zu >>\nstream\n", sizeof(cidToGID));
    CFDataAppendBytes(data, cidToGID, sizeof(cidToGID));
    append(data, "\nendstream\nendobj\n");
    CFIndex fontOffset = CFDataGetLength(data);
    append(data, "9 0 obj\n<< /Length %zu /Length1 %zu >>\nstream\n", fontLength, fontLength);
    CFDataAppendBytes(data, font, fontLength);
    append(data, "\nendstream\nendobj\n");

    CFIndex xref = CFDataGetLength(data);
    append(data, "xref\n0 10\n0000000000 65535 f \n");
    for (int i = 0; i < 8; i++)
        append(data, "%010ld 00000 n \n", (long)offsets[i]);
    append(data, "%010ld 00000 n \n", (long)fontOffset);
    append(data, "trailer\n<< /Size 10 /Root 1 0 R >>\nstartxref\n%ld\n%%%%EOF\n", (long)xref);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    CFRelease(data);
    return document;
}

static unsigned char pixels[WIDTH * HEIGHT];

static int render(const char *what, const char *content) {
    CGPDFDocumentRef document = documentWithContent(content);
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    if (page == NULL) {
        printf("FAIL: %s: no page\n", what);
        failures++;
        if (document)
            CGPDFDocumentRelease(document);
        return 0;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(pixels, WIDTH, HEIGHT, 8, WIDTH, space, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(space);
    CGContextSetGrayFillColor(context, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, WIDTH, HEIGHT));
    CGContextDrawPDFPage(context, page);
    CGContextRelease(context);
    CGPDFDocumentRelease(document);
    return 1;
}

// Ink (dark) or paper (light) at x, at height y (page coordinates).
static void expect(const char *what, int x, int y, int ink) {
    unsigned char value = pixels[(HEIGHT - 1 - y) * WIDTH + x];
    if (ink ? value > 64 : value < 192) {
        printf("FAIL: %s: at x=%d, y=%d expected %s, got %u\n", what, x, y, ink ? "ink" : "paper", value);
        failures++;
    }
}

int main(void) {
    // Glyphs are 100 units of text space per 1000 font units: 70 high, the
    // bar 10 wide and the block 60. Rows sit at y = 20, 120 and 220; ink is
    // looked for at mid-height (+35).
    if (render("CID text",
               "BT /F1 100 Tf 10 20 Td <00010002> Tj (\\000\\002) Tj ET\n"
               "BT /F1 100 Tf 10 120 Td [<0002> -1000 <0002>] TJ ET\n"
               "BT /F1 100 Tf 10 220 Td <00030002> Tj ET\n")) {
        // CID 1 -> glyph 2 (block) at 10..70; it advances 700/1000 * 100 = 70.
        expect("CID 1 maps to the block", 40, 55, 1);
        expect("the block ends at 70", 75, 55, 0);
        // CID 2 -> glyph 1 (bar) at 80..90; it advances 30.
        expect("CID 2 maps to the bar, placed by CID 1's width", 85, 55, 1);
        expect("the bar ends at 90", 95, 55, 0);
        // The next Tj, a literal string holding a NUL byte, starts at 110.
        expect("the next Tj starts where the last one ended", 115, 55, 1);
        expect("nothing past the second bar", 125, 55, 0);

        // TJ: bar at 10..20, advance 30, then -1000 moves right by 100: bar at 140..150.
        expect("first bar of the TJ", 15, 155, 1);
        expect("no glyph at the unadjusted position", 45, 155, 0);
        expect("the TJ adjustment is scaled by the font size", 145, 155, 1);

        // CID 3 is not in W: DW 1000 -> the next glyph at 10 + 100.
        expect("CID 3 maps to the bar", 15, 255, 1);
        expect("no glyph before the default width", 85, 255, 0);
        expect("a CID without a W entry advances by DW", 115, 255, 1);
    }

    if (failures)
        return failures;
    puts("PDF CID fonts passed");
    return 0;
}
