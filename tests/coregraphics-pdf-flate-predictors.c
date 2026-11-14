#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// FlateDecode with a Predictor (PDF 32000-1 7.4.4.4) gives back the original
// bytes: with the PNG predictors (10-15) each row starts with its filter type,
// None, Sub, Up, Average or Paeth (PNG specification 9.2), the left neighbour
// being the same byte of the pixel before and the row above the decoded one;
// with TIFF predictor 2 each component adds the one of the pixel before. An
// RGB image of 4x5 pixels, one row per PNG filter type, is drawn 1:1 into a
// bitmap and compared with the pixels it was made from.
// Exits non-zero on failure.

#define WIDTH 4
#define HEIGHT 5
#define ROW (WIDTH * 3)

static int failures;
static uint8_t raw[HEIGHT][ROW];

static void append(CFMutableDataRef data, const char *format, ...) {
    char buffer[1024];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    CFDataAppendBytes(data, (const UInt8 *)buffer, length);
}

// zlib data (RFC 1950) holding the bytes in one stored deflate block (RFC 1951).
static CFDataRef zlibStored(const uint8_t *bytes, size_t length) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    uint8_t header[7] = {0x78, 0x01, 1, length & 0xFF, length >> 8, ~length & 0xFF, (~length >> 8) & 0xFF};
    uint32_t a = 1, b = 0;
    CFDataAppendBytes(data, header, 7);
    CFDataAppendBytes(data, bytes, length);
    for (size_t i = 0; i < length; i++) {
        a = (a + bytes[i]) % 65521;
        b = (b + a) % 65521;
    }
    uint32_t adler = (b << 16) | a;
    uint8_t trailer[4] = {adler >> 24, adler >> 16, adler >> 8, adler};
    CFDataAppendBytes(data, trailer, 4);
    return data;
}

static int paeth(int left, int up, int upLeft) {
    int p = left + up - upLeft;
    int pa = abs(p - left), pb = abs(p - up), pc = abs(p - upLeft);
    if (pa <= pb && pa <= pc)
        return left;
    return pb <= pc ? up : upLeft;
}

// Row r filtered with PNG filter type r (0 None, 1 Sub, 2 Up, 3 Average, 4 Paeth).
static size_t encodePNG(uint8_t *out) {
    uint8_t *p = out;
    for (int r = 0; r < HEIGHT; r++) {
        *p++ = r;
        for (int i = 0; i < ROW; i++) {
            int left = i >= 3 ? raw[r][i - 3] : 0;
            int up = r > 0 ? raw[r - 1][i] : 0;
            int upLeft = (r > 0 && i >= 3) ? raw[r - 1][i - 3] : 0;
            int predicted = r == 1 ? left : r == 2 ? up : r == 3 ? (left + up) / 2 : r == 4 ? paeth(left, up, upLeft) : 0;
            *p++ = (uint8_t)(raw[r][i] - predicted);
        }
    }
    return p - out;
}

static size_t encodeTIFF(uint8_t *out) {
    for (int r = 0; r < HEIGHT; r++)
        for (int i = 0; i < ROW; i++)
            *out++ = (uint8_t)(raw[r][i] - (i >= 3 ? raw[r][i - 3] : 0));
    return HEIGHT * ROW;
}

static CGPDFDocumentRef documentWithImage(int predictor, CFDataRef imageData) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    const char *content = "q 4 0 0 5 0 0 cm /Im1 Do Q\n";
    CFIndex offsets[5];

    append(data, "%%PDF-1.4\n");
    offsets[0] = CFDataGetLength(data);
    append(data, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[1] = CFDataGetLength(data);
    append(data, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[2] = CFDataGetLength(data);
    append(data, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] "
                 "/Resources << /XObject << /Im1 5 0 R >> >> /Contents 4 0 R >>\nendobj\n",
           WIDTH, HEIGHT);
    offsets[3] = CFDataGetLength(data);
    append(data, "4 0 obj\n<< /Length %zu >>\nstream\n%s\nendstream\nendobj\n", strlen(content), content);
    offsets[4] = CFDataGetLength(data);
    append(data, "5 0 obj\n<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB "
                 "/BitsPerComponent 8 /Filter /FlateDecode "
                 "/DecodeParms << /Predictor %d /Colors 3 /BitsPerComponent 8 /Columns %d >> "
                 "/Length %ld >>\nstream\n",
           WIDTH, HEIGHT, predictor, WIDTH, (long)CFDataGetLength(imageData));
    CFDataAppendBytes(data, CFDataGetBytePtr(imageData), CFDataGetLength(imageData));
    append(data, "\nendstream\nendobj\n");
    CFIndex xref = CFDataGetLength(data);
    append(data, "xref\n0 6\n0000000000 65535 f \n");
    for (int i = 0; i < 5; i++)
        append(data, "%010ld 00000 n \n", (long)offsets[i]);
    append(data, "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%ld\n%%%%EOF\n", (long)xref);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    CFRelease(data);
    return document;
}

static void check(const char *what, int predictor, const uint8_t *encoded, size_t length) {
    CFDataRef imageData = zlibStored(encoded, length);
    CGPDFDocumentRef document = documentWithImage(predictor, imageData);
    CFRelease(imageData);
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    if (page == NULL) {
        printf("FAIL: %s: no page\n", what);
        failures++;
        if (document)
            CGPDFDocumentRelease(document);
        return;
    }
    unsigned char pixels[WIDTH * HEIGHT * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, WIDTH, HEIGHT, 8, WIDTH * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, WIDTH, HEIGHT));
    CGContextDrawPDFPage(context, page);
    CGContextRelease(context);
    CGPDFDocumentRelease(document);

    // Image row 0 is the top one, as is bitmap row 0.
    for (int r = 0; r < HEIGHT; r++)
        for (int x = 0; x < WIDTH; x++) {
            const uint8_t *got = pixels + (r * WIDTH + x) * 4;
            const uint8_t *want = raw[r] + x * 3;
            if (abs(got[0] - want[0]) > 2 || abs(got[1] - want[1]) > 2 || abs(got[2] - want[2]) > 2) {
                printf("FAIL: %s: row %d pixel %d is %u %u %u, expected %u %u %u\n", what, r, x,
                       got[0], got[1], got[2], want[0], want[1], want[2]);
                failures++;
            }
        }
}

int main(void) {
    // Bytes that differ from their left and upper neighbours, so a wrong
    // predictor or a wrong neighbour shows.
    for (int r = 0; r < HEIGHT; r++)
        for (int i = 0; i < ROW; i++)
            raw[r][i] = (uint8_t)(37 * r * r + 59 * i + 11 * (i % 3) * r + 23);

    uint8_t encoded[HEIGHT * (ROW + 1)];
    size_t length = encodePNG(encoded);
    check("PNG predictors None, Sub, Up, Average and Paeth", 15, encoded, length);
    length = encodeTIFF(encoded);
    check("TIFF predictor 2", 2, encoded, length);
    if (failures)
        return failures;
    puts("FlateDecode predictors passed");
    return 0;
}
