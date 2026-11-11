#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

// CGPDFPageGetBoxRect follows the page boundaries of PDF 32000-1 14.11.2:
//  - a missing CropBox is the MediaBox, a missing BleedBox, TrimBox or ArtBox the CropBox;
//  - a rectangle is any two opposite corners (7.9.5), so reversed corners are the same box;
//  - every box other than the MediaBox is clipped to the MediaBox.
// Exits non-zero on failure.

static void append(CFMutableDataRef data, const char *format, ...) {
    char buffer[1024];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    CFDataAppendBytes(data, (const UInt8 *)buffer, length);
}

static CGPDFDocumentRef documentWithPage(const char *pageEntries) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CFIndex offsets[3];
    append(data, "%%PDF-1.4\n");
    offsets[0] = CFDataGetLength(data);
    append(data, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[1] = CFDataGetLength(data);
    append(data, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[2] = CFDataGetLength(data);
    append(data, "3 0 obj\n<< /Type /Page /Parent 2 0 R %s >>\nendobj\n", pageEntries);
    CFIndex xref = CFDataGetLength(data);
    append(data, "xref\n0 4\n0000000000 65535 f \n");
    for (int i = 0; i < 3; i++)
        append(data, "%010ld 00000 n \n", (long)offsets[i]);
    append(data, "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n%ld\n%%%%EOF\n", (long)xref);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    CFRelease(data);
    return document;
}

static int failures;

static void expectBox(const char *pageEntries, CGPDFBox box, const char *boxName, CGRect expected) {
    CGPDFDocumentRef document = documentWithPage(pageEntries);
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    if (page == NULL) {
        printf("FAIL: no page for '%s'\n", pageEntries);
        failures++;
    } else {
        CGRect rect = CGPDFPageGetBoxRect(page, box);
        if (fabs(rect.origin.x - expected.origin.x) > 0.001 || fabs(rect.origin.y - expected.origin.y) > 0.001 ||
            fabs(rect.size.width - expected.size.width) > 0.001 || fabs(rect.size.height - expected.size.height) > 0.001) {
            printf("FAIL: %s of '%s' is {%g %g %g %g}, expected {%g %g %g %g}\n", boxName, pageEntries,
                   rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
                   expected.origin.x, expected.origin.y, expected.size.width, expected.size.height);
            failures++;
        }
    }
    if (document)
        CGPDFDocumentRelease(document);
}

int main(void) {
    const char *mediaOnly = "/MediaBox [0 0 200 100]";
    CGRect media = CGRectMake(0, 0, 200, 100);
    expectBox(mediaOnly, kCGPDFMediaBox, "MediaBox", media);
    expectBox(mediaOnly, kCGPDFCropBox, "CropBox", media);
    expectBox(mediaOnly, kCGPDFBleedBox, "BleedBox", media);
    expectBox(mediaOnly, kCGPDFTrimBox, "TrimBox", media);
    expectBox(mediaOnly, kCGPDFArtBox, "ArtBox", media);

    const char *withCrop = "/MediaBox [0 0 200 100] /CropBox [10 20 110 80]";
    CGRect crop = CGRectMake(10, 20, 100, 60);
    expectBox(withCrop, kCGPDFCropBox, "CropBox", crop);
    expectBox(withCrop, kCGPDFBleedBox, "BleedBox", crop);
    expectBox(withCrop, kCGPDFTrimBox, "TrimBox", crop);
    expectBox(withCrop, kCGPDFArtBox, "ArtBox", crop);

    expectBox("/MediaBox [200 100 0 0]", kCGPDFMediaBox, "reversed MediaBox", media);
    expectBox("/MediaBox [0 0 200 100] /CropBox [110 80 10 20]", kCGPDFCropBox, "reversed CropBox", crop);

    expectBox("/MediaBox [0 0 200 100] /CropBox [-10 -10 300 50]", kCGPDFCropBox, "CropBox beyond the MediaBox",
              CGRectMake(0, 0, 200, 50));
    expectBox("/MediaBox [0 0 200 100] /TrimBox [150 50 250 150]", kCGPDFTrimBox, "TrimBox beyond the MediaBox",
              CGRectMake(150, 50, 50, 50));

    if (failures)
        return failures;
    puts("PDF page box defaults and clipping passed");
    return 0;
}
