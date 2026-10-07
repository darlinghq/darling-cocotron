#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFString.h>
#include <stdio.h>
#include <string.h>

extern const CFStringRef kCGPDFContextAuthor __attribute__((weak_import));
extern const CFStringRef kCGPDFContextCreator __attribute__((weak_import));

static BOOL matches(O2PDFDictionary *info, const char *key, NSString *expected) {
    O2PDFString *actual = nil;
    NSData *bytes = [expected dataUsingEncoding:NSASCIIStringEncoding];
    return [info getStringForKey:key value:&actual] &&
        [actual length] == [bytes length] &&
        (![bytes length] || !memcmp([actual bytes], [bytes bytes], [bytes length]));
}

int main(void) {
    @autoreleasepool {
        if (&kCGPDFContextAuthor == NULL || &kCGPDFContextCreator == NULL) {
            fputs("public author/creator keys are absent\n", stderr);
            return 10;
        }
        for (unsigned i = 0; i < 5; i++) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            NSString *author = i == 0 || i == 2 ? @"Public author" : @"";
            NSString *creator = i == 0 || i == 3 ? @"Public creator" : @"";
            if (i < 3) [info setObject:author forKey:(id)kCGPDFContextAuthor];
            if (i < 2 || i == 3) [info setObject:creator forKey:(id)kCGPDFContextCreator];
            NSDictionary *original = [[info copy] autorelease];
            NSMutableData *data = [NSMutableData data];
            CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
            CGRect box = CGRectMake(0, 0, 100, 200);
            CGContextRef context = CGPDFContextCreate(consumer, &box, i == 4 ? NULL : (CFDictionaryRef)info);
            CGDataConsumerRelease(consumer);
            if (!context) return 20 + i;
            CGPDFContextClose(context);
            CGContextRelease(context);
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
            CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
            CGDataProviderRelease(provider);
            if (!document) return 30 + i;
            O2PDFDictionary *metadata = [(O2PDFDocument *)document infoDictionary];
            NSString *expectedAuthor = i < 3 ? author : NSFullUserName();
            NSString *expectedCreator = i < 2 || i == 3 ? creator : [[NSProcessInfo processInfo] processName];
            if (!matches(metadata, "Author", expectedAuthor) || !matches(metadata, "Creator", expectedCreator)) {
                fprintf(stderr, "generated PDF author/creator mismatch case%u\n", i);
                return 40 + i;
            }
            if (![info isEqual:original]) return 50 + i;
            CGPDFDocumentRelease(document);
        }
        puts("generated PDF author/creator metadata passed");
    }
    return 0;
}
