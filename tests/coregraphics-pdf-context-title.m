#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFString.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    @autoreleasepool {
        const char *titles[] = {"Public metadata title", ""};
        for (unsigned i = 0; i < 3; i++) {
            NSMutableData *data = [NSMutableData data];
            CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
            NSString *title = i < 2 ? [NSString stringWithUTF8String:titles[i]] : nil;
            NSDictionary *info = title ? [NSDictionary dictionaryWithObject:title forKey:(id)kCGPDFContextTitle] : nil;
            CGRect box = CGRectMake(0, 0, 100, 200);
            CGContextRef context = CGPDFContextCreate(consumer, &box, (CFDictionaryRef)info);
            CGDataConsumerRelease(consumer);
            if (!context) return 10 + i;
            CGPDFContextClose(context);
            CGContextRelease(context);
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
            CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
            CGDataProviderRelease(provider);
            if (!document) return 20 + i;
            if (title) {
                O2PDFString *actual = nil;
                if (![[(O2PDFDocument *)document infoDictionary] getStringForKey:"Title" value:&actual] ||
                    [actual length] != strlen(titles[i]) ||
                    ([actual length] && memcmp([actual bytes], titles[i], [actual length]))) {
                    fprintf(stderr, "generated PDF title does not match auxiliary metadata case%u\n", i);
                    return 30 + i;
                }
                if ([info count] != 1 || ![[info objectForKey:(id)kCGPDFContextTitle] isEqual:title]) return 40 + i;
            }
            CGPDFDocumentRelease(document);
        }
        puts("generated PDF title metadata passed");
    }
    return 0;
}
