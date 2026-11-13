#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

static BOOL rejectsURL(NSURL *url) {
    CGDataConsumerRef consumer = CGDataConsumerCreateWithURL((CFURLRef)url);
    if (consumer == NULL)
        return YES;
    CGDataConsumerRelease(consumer);
    return NO;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSProcessInfo processInfo] globallyUniqueString]];
    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:NO
                             attributes:nil error:NULL])
        return 10;
    NSString *missing = [directory stringByAppendingPathComponent:@"missing/output.pdf"];
    BOOL missingRejected = rejectsURL([NSURL fileURLWithPath:missing]);
    BOOL directoryRejected = rejectsURL([NSURL fileURLWithPath:directory]);
    BOOL nonfileRejected = rejectsURL(
        [NSURL URLWithString:@"https://example.invalid/output.pdf"]);
    if (!missingRejected || !directoryRejected || !nonfileRejected) {
        [manager removeItemAtPath:directory error:NULL];
        fputs("invalid destination returned a consumer\n", stderr);
        return 20;
    }
    NSString *path = [directory stringByAppendingPathComponent:@"output.pdf"];
    NSURL *url = [NSURL fileURLWithPath:path];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithURL((CFURLRef)url);
    if (consumer == NULL)
        return 30;
    CGRect box = CGRectMake(0, 0, 123, 456);
    CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
    if (context == NULL)
        return 30;
    CGContextBeginPage(context, &box);
    CGContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
    CGDataConsumerRelease(consumer);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef)url);
    BOOL valid = document != NULL && CGPDFDocumentGetNumberOfPages(document) == 1;
    if (valid) {
        CGRect readBox = CGPDFPageGetBoxRect(CGPDFDocumentGetPage(document, 1),
                                            kCGPDFMediaBox);
        valid = readBox.size.width == 123 && readBox.size.height == 456;
    }
    CGPDFDocumentRelease(document);
    [manager removeItemAtPath:directory error:NULL];
    [pool drain];
    if (!valid)
        return 40;
    puts("invalid destinations rejected and file PDF roundtrip passed");
    return 0;
}
