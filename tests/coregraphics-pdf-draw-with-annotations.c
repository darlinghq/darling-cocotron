// CGContextDrawPDFPageWithAnnotations (Apple SPI, declared by WebKit's
// CoreGraphicsSPI.h): with a NULL callback it draws the page as
// CGContextDrawPDFPage does.
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } else printf("PASS %s\n", #cond); } while (0)

static CGContextRef bitmap(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 20, 20, 8, 80, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return context;
}

int main(void) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData(data);
    CGRect box = CGRectMake(0, 0, 20, 20);
    CGContextRef pdf = CGPDFContextCreate(consumer, &box, NULL);
    CGContextBeginPage(pdf, &box);
    CGContextSetRGBFillColor(pdf, 1, 0, 0, 1);
    CGContextFillRect(pdf, CGRectMake(5, 5, 10, 10));
    CGContextEndPage(pdf);
    CGPDFContextClose(pdf);
    CGContextRelease(pdf);
    CGDataConsumerRelease(consumer);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CHECK(document != NULL);
    CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
    CHECK(page != NULL);

    CGContextRef plain = bitmap(), annotated = bitmap();
    CGContextDrawPDFPage(plain, page);
    CGContextDrawPDFPageWithAnnotations(annotated, page, NULL);
    const unsigned char *a = CGBitmapContextGetData(plain), *b = CGBitmapContextGetData(annotated);
    CHECK(memcmp(a, b, 80 * 20) == 0);
    CHECK(a[(10 * 20 + 10) * 4] > 200 && a[(10 * 20 + 10) * 4 + 3] > 200); // the red square was drawn

    CGContextRelease(plain);
    CGContextRelease(annotated);
    CGPDFDocumentRelease(document);
    CGDataProviderRelease(provider);
    CFRelease(data);
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
