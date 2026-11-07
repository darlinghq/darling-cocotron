#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFPage.h>
#include <dlfcn.h>
#include <stdio.h>

static NSData *documentData(const char *rootRotate, const char *pageRotate) {
    NSMutableData *data = [NSMutableData dataWithData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
    NSString *objects[] = {
        @"<< /Type /Catalog /Pages 2 0 R >>",
        [NSString stringWithFormat:@"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 100 200] %s >>", rootRotate],
        [NSString stringWithFormat:@"<< /Type /Page /Parent 2 0 R %s >>", pageRotate]
    };
    NSUInteger offsets[3];
    for (NSUInteger i = 0; i < 3; i++) {
        offsets[i] = [data length];
        NSString *object = [NSString stringWithFormat:@"%lu 0 obj\n%@\nendobj\n", (unsigned long)i + 1, objects[i]];
        [data appendData:[object dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSUInteger xref = [data length];
    [data appendData:[@"xref\n0 4\n0000000000 65535 f \n" dataUsingEncoding:NSASCIIStringEncoding]];
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *entry = [NSString stringWithFormat:@"%010lu 00000 n \n", (unsigned long)offsets[i]];
        [data appendData:[entry dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSString *trailer = [NSString stringWithFormat:@"trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n%lu\n%%%%EOF\n", (unsigned long)xref];
    [data appendData:[trailer dataUsingEncoding:NSASCIIStringEncoding]];
    return data;
}

int main(void) {
    @autoreleasepool {
        int (*rotation)(CGPDFPageRef) = dlsym(RTLD_DEFAULT, "CGPDFPageGetRotationAngle");
        unsigned failures = 0;
        if (!rotation) {
            fprintf(stderr, "missing PDF page rotation export\n");
            failures++;
        }
        struct { const char *root; const char *page; int expected; } cases[] = {
            {"", "", 0}, {"/Rotate 90", "", 90}, {"/Rotate 90", "/Rotate 270", 270},
            {"", "/Rotate -90", -90}, {"", "/Rotate 450", 450}
        };
        for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)documentData(cases[i].root, cases[i].page));
            CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
            CGDataProviderRelease(provider);
            CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
            if (!page) return 20 + i;
            int internal = [(O2PDFPage *)page rotationAngle];
            if (internal != cases[i].expected || (rotation && rotation(page) != cases[i].expected)) {
                fprintf(stderr, "parsed page rotation case%u: got%d expected%d\n", i, internal, cases[i].expected);
                failures++;
            }
            CGPDFDocumentRelease(document);
        }
        const char *invalid[] = {"/Rotate 45", "/Rotate /Wrong", "/Rotate 2147483648"};
        for (unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)documentData("/Rotate 90", invalid[i]));
            CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
            CGDataProviderRelease(provider);
            CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
            BOOL rejected = NO;
            @try {
                if (rotation) rotation(page);
                else [(O2PDFPage *)page rotationAngle];
            } @catch (NSException *exception) {
                rejected = [[exception name] isEqualToString:NSInvalidArgumentException];
            }
            if (!rejected) {
                fprintf(stderr, "invalid page rotation accepted: %s\n", invalid[i]);
                failures++;
            }
            CGPDFDocumentRelease(document);
        }
        if (failures) return failures;
        puts("parsed PDF inherited page rotation passed");
    }
    return 0;
}
