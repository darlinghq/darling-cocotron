#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFString.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static NSData *documentData(void) {
    NSMutableData *data = [NSMutableData dataWithData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
    const char *objects[] = {
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [] /Count 0 >>",
        "<< /Title (Inspection fixture) /Kind /Fixture /Number 7 >>"
    };
    NSUInteger offsets[3];
    for (NSUInteger i = 0; i < 3; i++) {
        offsets[i] = [data length];
        NSString *object = [NSString stringWithFormat:@"%lu 0 obj\n%s\nendobj\n",
            (unsigned long)i + 1, objects[i]];
        [data appendData:[object dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSUInteger xref = [data length];
    [data appendData:[@"xref\n0 4\n0000000000 65535 f \n" dataUsingEncoding:NSASCIIStringEncoding]];
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *entry = [NSString stringWithFormat:@"%010lu 00000 n \n", (unsigned long)offsets[i]];
        [data appendData:[entry dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSString *trailer = [NSString stringWithFormat:
        @"trailer\n<< /Size 4 /Root 1 0 R /Info 3 0 R >>\nstartxref\n%lu\n%%%%EOF\n",
        (unsigned long)xref];
    [data appendData:[trailer dataUsingEncoding:NSASCIIStringEncoding]];
    return data;
}

int main(void) {
    @autoreleasepool {
        bool (*getName)(CGPDFDictionaryRef, const char *, const char **) = dlsym(RTLD_DEFAULT, "CGPDFDictionaryGetName");
        bool (*getString)(CGPDFDictionaryRef, const char *, CGPDFStringRef *) = dlsym(RTLD_DEFAULT, "CGPDFDictionaryGetString");
        if (!getName || !getString) {
            fprintf(stderr, "missing PDF dictionary inspection exports\n");
            return 10;
        }
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)documentData());
        CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
        CGDataProviderRelease(provider);
        if (!document) return 20;
        CGPDFDictionaryRef dictionary = (CGPDFDictionaryRef)[(O2PDFDocument *)document infoDictionary];
        const char *name = NULL;
        CGPDFStringRef string = NULL;
        if (!getName(dictionary, "Kind", &name) || strcmp(name, "Fixture")) return 30;
        if (!getString(dictionary, "Title", &string)) return 31;
        O2PDFString *title = (O2PDFString *)string;
        if ([title length] != 18 || memcmp([title bytes], "Inspection fixture", 18)) return 32;
        if (!getName(dictionary, "Kind", NULL) || !getString(dictionary, "Title", NULL)) return 33;
        const char *originalName = name;
        CGPDFStringRef originalString = string;
        const char *wrongKeys[] = {"Title", "Number", "Missing"};
        for (unsigned i = 0; i < 3; i++)
            if (getName(dictionary, wrongKeys[i], &name) || getName(dictionary, wrongKeys[i], NULL)) return 40 + i;
        const char *wrongStringKeys[] = {"Kind", "Number", "Missing"};
        for (unsigned i = 0; i < 3; i++)
            if (getString(dictionary, wrongStringKeys[i], &string) || getString(dictionary, wrongStringKeys[i], NULL)) return 50 + i;
        const char *again = NULL;
        CGPDFStringRef stringAgain = NULL;
        if (!getName(dictionary, "Kind", &again) || again != originalName) return 60;
        if (!getString(dictionary, "Title", &stringAgain) || stringAgain != originalString) return 61;
        CGPDFDocumentRelease(document);
        puts("parsed PDF dictionary inspection passed");
    }
    return 0;
}
