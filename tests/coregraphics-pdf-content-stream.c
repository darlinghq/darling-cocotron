#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Drawing a page whose content stream
//  - ends with its last operator and no whitespace after it: the end of the data
//    delimits the token (PDF 32000-1 7.2.2), so the operator is executed;
//  - uses an operator the consumer does not know: it is ignored together with its
//    operands and the rest of the stream is still drawn (PDF 32000-1 7.8.2).
// Exits non-zero on failure.

#define SIZE 20

static void append(CFMutableDataRef data, const char *format, ...) {
    char buffer[1024];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    CFDataAppendBytes(data, (const UInt8 *)buffer, length);
}

// A one-page document with a 20x20 MediaBox and the given content stream.
static CGPDFDocumentRef documentWithContent(const char *content) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CFIndex offsets[4];
    append(data, "%%PDF-1.4\n");
    offsets[0] = CFDataGetLength(data);
    append(data, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[1] = CFDataGetLength(data);
    append(data, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[2] = CFDataGetLength(data);
    append(data, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R >>\nendobj\n", SIZE, SIZE);
    offsets[3] = CFDataGetLength(data);
    append(data, "4 0 obj\n<< /Length %zu >>\nstream\n%s\nendstream\nendobj\n", strlen(content), content);
    CFIndex xref = CFDataGetLength(data);
    append(data, "xref\n0 5\n0000000000 65535 f \n");
    for (int i = 0; i < 4; i++)
        append(data, "%010ld 00000 n \n", (long)offsets[i]);
    append(data, "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n%ld\n%%%%EOF\n", (long)xref);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    CFRelease(data);
    return document;
}

// Draws the page on white and returns the R, G, B of the pixel at (x, y), y up.
static int drawAndSample(const char *content, int x, int y, unsigned char rgb[3]) {
    CGPDFDocumentRef document = documentWithContent(content);
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    if (page == NULL) {
        printf("FAIL: no page for content '%s'\n", content);
        if (document)
            CGPDFDocumentRelease(document);
        return 0;
    }
    unsigned char pixels[SIZE * SIZE * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, SIZE, SIZE, 8, SIZE * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, SIZE, SIZE));
    CGContextDrawPDFPage(context, page);
    CGContextRelease(context);
    CGPDFDocumentRelease(document);
    memcpy(rgb, pixels + ((SIZE - 1 - y) * SIZE + x) * 4, 3);
    return 1;
}

static int failures;

static void expect(const char *what, const char *content, int x, int y, int r, int g, int b) {
    unsigned char rgb[3];
    if (!drawAndSample(content, x, y, rgb)) {
        failures++;
        return;
    }
    if (abs(rgb[0] - r) > 2 || abs(rgb[1] - g) > 2 || abs(rgb[2] - b) > 2) {
        printf("FAIL: %s: pixel (%d,%d) is %u %u %u, expected %d %d %d\n", what, x, y, rgb[0], rgb[1], rgb[2], r, g, b);
        failures++;
    }
}

int main(void) {
    expect("operator at the end of the stream", "1 0 0 rg 0 0 10 10 re f", 5, 5, 255, 0, 0);
    expect("operator at the end, area outside the fill", "1 0 0 rg 0 0 10 10 re f", 15, 15, 255, 255, 255);
    expect("unknown operator and its operands are skipped", "0 0 1 rg 3 /Name (text) zzunknown 0 0 10 10 re f", 5, 5, 0, 0, 255);
    expect("unknown operator at the end", "0 1 0 rg 0 0 10 10 re f 7 zzunknown", 5, 5, 0, 255, 0);
    if (failures)
        return failures;
    puts("PDF content stream tokens and unknown operators passed");
    return 0;
}
