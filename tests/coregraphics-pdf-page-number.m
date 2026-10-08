#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

extern size_t CGPDFPageGetPageNumber(CGPDFPageRef page)
    __attribute__((weak_import));

static NSData *nestedPDF(void) {
    NSArray *objects = @[
        @"<< /Type /Catalog /Pages 2 0 R >>",
        @"<< /Type /Pages /Kids [3 0 R 8 0 R] /Count 4 >>",
        @"<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 7 0 R] /Count 2 >>",
        @"<< /Type /Page /Parent 3 0 R /MediaBox [0 0 1 40] >>",
        @"<< /Type /Page /Parent 8 0 R /MediaBox [0 0 4 40] >>",
        @"<< /Type /Page /Parent 8 0 R /MediaBox [0 0 3 40] >>",
        @"<< /Type /Page /Parent 3 0 R /MediaBox [0 0 2 40] >>",
        @"<< /Type /Pages /Parent 2 0 R /Kids [6 0 R 5 0 R] /Count 2 >>",
    ];
    NSMutableData *data = [NSMutableData data];
    [data appendData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
    NSUInteger offsets[8];
    for (NSUInteger i = 0; i < [objects count]; i++) {
        offsets[i] = [data length];
        NSString *object = [NSString stringWithFormat:@"%lu 0 obj\n%@\nendobj\n",
                            (unsigned long)i + 1, [objects objectAtIndex:i]];
        [data appendData:[object dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSUInteger xref = [data length];
    NSMutableString *trailer = [NSMutableString stringWithString:
        @"xref\n0 9\n0000000000 65535 f \n"];
    for (NSUInteger i = 0; i < 8; i++)
        [trailer appendFormat:@"%010lu 00000 n \n", (unsigned long)offsets[i]];
    [trailer appendFormat:@"trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n%lu\n%%%%EOF\n",
                          (unsigned long)xref];
    [data appendData:[trailer dataUsingEncoding:NSASCIIStringEncoding]];
    return data;
}

int main(void) {
    if (CGPDFPageGetPageNumber == NULL) {
        fputs("missing CGPDFPageGetPageNumber\n", stderr);
        return 10;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)nestedPDF());
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    if (document == NULL || CGPDFDocumentGetNumberOfPages(document) != 4)
        return 20;
    CGPDFPageRef retained = NULL;
    for (size_t number = 1; number <= 4; number++) {
        CGPDFPageRef page = CGPDFDocumentGetPage(document, number);
        if (page == NULL || CGPDFPageGetPageNumber(page) != number ||
            CGPDFPageGetPageNumber(page) != number ||
            CGPDFPageGetBoxRect(page, kCGPDFMediaBox).size.width != number)
            return 30;
        if (number == 4)
            retained = CGPDFPageRetain(page);
    }
    CGPDFDocumentRelease(document);
    [pool drain];
    if (CGPDFPageGetPageNumber(retained) != 4)
        return 40;
    CGPDFPageRelease(retained);
    if (CGPDFPageGetPageNumber(NULL) != 0)
        return 50;
    puts("nested PDF page numbers and retained-page lifetime passed");
    return 0;
}
