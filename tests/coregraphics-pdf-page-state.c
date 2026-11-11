#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// CGContextDrawPDFPage draws the page from the PDF initial graphics state
// (PDF 32000-1 8.4.1: the fill colour is black, whatever the context was set to),
// and leaves the context's own graphics state as it was, even when the page saves
// a state (q) it never restores (Q). The streams end with whitespace, so the last
// operator does not depend on the scanner delimiting a token at the end of the data.
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

static int failures;

static void expectPixel(const char *what, const unsigned char *pixels, int x, int y, int r, int g, int b) {
    const unsigned char *p = pixels + ((SIZE - 1 - y) * SIZE + x) * 4;
    if (abs(p[0] - r) > 2 || abs(p[1] - g) > 2 || abs(p[2] - b) > 2) {
        printf("FAIL: %s: pixel (%d,%d) is %u %u %u, expected %d %d %d\n", what, x, y, p[0], p[1], p[2], r, g, b);
        failures++;
    }
}

// The context fill colour is green before the page; the page fills the bottom-left
// quarter with `content`, then the context fills the top-right quarter on its own.
static void check(const char *what, const char *content, int r, int g, int b) {
    CGPDFDocumentRef document = documentWithContent(content);
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    if (page == NULL) {
        printf("FAIL: %s: no page\n", what);
        failures++;
        if (document)
            CGPDFDocumentRelease(document);
        return;
    }
    unsigned char pixels[SIZE * SIZE * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, SIZE, SIZE, 8, SIZE * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, SIZE, SIZE));
    CGContextSetRGBFillColor(context, 0, 1, 0, 1);
    CGContextDrawPDFPage(context, page);
    CGContextFillRect(context, CGRectMake(10, 10, 10, 10));
    CGContextRelease(context);
    CGPDFDocumentRelease(document);

    expectPixel(what, pixels, 5, 5, r, g, b);
    expectPixel("context fill colour after the page", pixels, 15, 15, 0, 255, 0);
}

int main(void) {
    check("page without a fill colour draws in black", "0 0 10 10 re f\n", 0, 0, 0);
    check("page that saves a state and never restores it", "q 0 0 1 rg 0 0 10 10 re f\n", 0, 0, 255);
    if (failures)
        return failures;
    puts("PDF page initial graphics state passed");
    return 0;
}
