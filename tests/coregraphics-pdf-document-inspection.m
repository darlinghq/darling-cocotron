#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFString.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static NSData *documentData(BOOL metadata, BOOL encrypted) {
    NSMutableData *data = [NSMutableData data];
    const char *objects[] = {
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [] /Count 0 >>",
        "<< /Title (Inspection fixture) >>",
        "<< /Filter /Standard /V 1 /R 2 /Length 40 /P -4 "
        "/O <0000000000000000000000000000000000000000000000000000000000000000> "
        "/U <0000000000000000000000000000000000000000000000000000000000000000> >>"
    };
    [data appendData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
    NSUInteger offsets[4];
    for (NSUInteger i = 0; i < 4; i++) {
        offsets[i] = [data length];
        NSString *object = [NSString stringWithFormat:@"%lu 0 obj\n%s\nendobj\n",
            (unsigned long)i + 1, objects[i]];
        [data appendData:[object dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSUInteger xref = [data length];
    [data appendData:[@"xref\n0 5\n0000000000 65535 f \n" dataUsingEncoding:NSASCIIStringEncoding]];
    for (NSUInteger i = 0; i < 4; i++) {
        NSString *entry = [NSString stringWithFormat:@"%010lu 00000 n \n", (unsigned long)offsets[i]];
        [data appendData:[entry dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSString *trailer = [NSString stringWithFormat:
        @"trailer\n<< /Size 5 /Root 1 0 R %@ %@ >>\nstartxref\n%lu\n%%%%EOF\n",
        metadata ? @"/Info 3 0 R" : @"", encrypted ? @"/Encrypt 4 0 R" : @"",
        (unsigned long)xref];
    [data appendData:[trailer dataUsingEncoding:NSASCIIStringEncoding]];
    return data;
}

int main(void) {
    @autoreleasepool {
        CGPDFDictionaryRef (*getInfo)(CGPDFDocumentRef) = dlsym(RTLD_DEFAULT, "CGPDFDocumentGetInfo");
        bool (*isEncrypted)(CGPDFDocumentRef) = dlsym(RTLD_DEFAULT, "CGPDFDocumentIsEncrypted");
        if (!getInfo || !isEncrypted) {
            fprintf(stderr, "missing PDF document inspection exports\n");
            return 10;
        }
        for (unsigned mode = 0; mode < 4; mode++) {
            BOOL metadata = (mode & 1) != 0, encrypted = (mode & 2) != 0;
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)documentData(metadata, encrypted));
            CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
            CGDataProviderRelease(provider);
            if (!document) return 20 + mode;
            O2PDFDictionary *info = (O2PDFDictionary *)getInfo(document);
            if ((info != nil) != metadata || isEncrypted(document) != encrypted) return 30 + mode;
            if (metadata) {
                O2PDFString *title = nil;
                if (![info getStringForKey:"Title" value:&title] || [title length] != 18 ||
                    memcmp([title bytes], "Inspection fixture", 18) != 0) return 40 + mode;
                if (getInfo(document) != (CGPDFDictionaryRef)info) return 50 + mode;
            }
            CGPDFDocumentRelease(document);
        }
        puts("parsed PDF document inspection passed");
    }
    return 0;
}
