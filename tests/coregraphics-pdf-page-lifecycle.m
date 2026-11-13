#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

extern void CGPDFContextBeginPage(CGContextRef, CFDictionaryRef)
    __attribute__((weak_import));
extern void CGPDFContextEndPage(CGContextRef) __attribute__((weak_import));
extern const CFStringRef kCGPDFContextCropBox __attribute__((weak_import));
extern const CFStringRef kCGPDFContextBleedBox __attribute__((weak_import));
extern const CFStringRef kCGPDFContextTrimBox __attribute__((weak_import));
extern const CFStringRef kCGPDFContextArtBox __attribute__((weak_import));

static NSArray *boxKeys(void) {
    return @[(id)kCGPDFContextMediaBox, (id)kCGPDFContextCropBox,
             (id)kCGPDFContextBleedBox, (id)kCGPDFContextTrimBox,
             (id)kCGPDFContextArtBox];
}

static NSMutableDictionary *boxInfo(const CGRect *boxes, NSUInteger count) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < count; i++) {
        CFDataRef value = CFDataCreate(NULL, (const UInt8 *)&boxes[i], sizeof(CGRect));
        [info setObject:(id)value forKey:[boxKeys() objectAtIndex:i]];
        CFRelease(value);
    }
    return info;
}

static CGContextRef contextForData(NSMutableData *data, const CGRect *box,
                                   NSDictionary *info) {
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
    CGContextRef context = CGPDFContextCreate(consumer, box, (CFDictionaryRef)info);
    CGDataConsumerRelease(consumer);
    return context;
}

static BOOL checkPages(NSData *data, const CGRect *boxes, size_t count) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    BOOL valid = document != NULL && CGPDFDocumentGetNumberOfPages(document) == count;
    for (size_t page = 0; valid && page < count; page++) {
        CGPDFPageRef current = CGPDFDocumentGetPage(document, page + 1);
        for (NSUInteger box = 0; valid && box < 5; box++) {
            CGRect actual = CGPDFPageGetBoxRect(current, (CGPDFBox)box);
            valid = CGRectEqualToRect(actual, boxes[page * 5 + box]);
        }
    }
    CGPDFDocumentRelease(document);
    return valid;
}

static void finishPage(CGContextRef context, NSDictionary *info) {
    CGPDFContextBeginPage(context, (CFDictionaryRef)info);
    CGPDFContextEndPage(context);
}

int main(void) {
    if (CGPDFContextBeginPage == NULL || CGPDFContextEndPage == NULL ||
        &kCGPDFContextCropBox == NULL || &kCGPDFContextBleedBox == NULL ||
        &kCGPDFContextTrimBox == NULL || &kCGPDFContextArtBox == NULL) {
        fputs("missing PDF page lifecycle interface\n", stderr);
        return 10;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CGRect creation = CGRectMake(11, 22, 300, 400);
    CGRect defaults[5] = {
        CGRectMake(13, 24, 280, 380), CGRectMake(20, 30, 250, 350),
        CGRectMake(21, 31, 240, 340), CGRectMake(22, 32, 230, 330),
        CGRectMake(23, 33, 220, 320)};
    CGRect overrides[5] = {
        CGRectMake(30, 40, 500, 600), CGRectMake(40, 50, 450, 550),
        CGRectMake(41, 51, 440, 540), CGRectMake(42, 52, 430, 530),
        CGRectMake(43, 53, 420, 520)};
    NSMutableDictionary *auxiliary = boxInfo(defaults, 5);
    NSDictionary *auxiliarySnapshot = [NSDictionary dictionaryWithDictionary:auxiliary];
    NSMutableData *data = [NSMutableData data];
    CGContextRef context = contextForData(data, &creation, auxiliary);
    if (context == NULL || ![auxiliary isEqual:auxiliarySnapshot])
        return 20;
    [auxiliary removeAllObjects];
    finishPage(context, nil);
    NSMutableDictionary *pageInfo = boxInfo(overrides, 5);
    NSDictionary *pageSnapshot = [NSDictionary dictionaryWithDictionary:pageInfo];
    finishPage(context, pageInfo);
    if (![pageInfo isEqual:pageSnapshot])
        return 30;
    finishPage(context, nil);
    CGPDFContextClose(context);
    CGContextRelease(context);
    CGRect expected[15];
    for (NSUInteger i = 0; i < 5; i++) {
        expected[i] = defaults[i];
        expected[5 + i] = overrides[i];
        expected[10 + i] = defaults[i];
    }
    if (!checkPages(data, expected, 3))
        return 40;

    data = [NSMutableData data];
    context = contextForData(data, &creation, nil);
    CGRect saved = creation;
    creation = CGRectZero;
    finishPage(context, nil);
    finishPage(context, boxInfo(overrides, 2));
    finishPage(context, nil);
    CGPDFContextClose(context);
    CGContextRelease(context);
    for (NSUInteger i = 0; i < 5; i++) {
        expected[i] = saved;
        expected[5 + i] = overrides[i == 0 ? 0 : 1];
        expected[10 + i] = saved;
    }
    if (!checkPages(data, expected, 3))
        return 50;

    data = [NSMutableData data];
    context = contextForData(data, NULL, nil);
    NSUInteger before = [data length];
    NSDictionary *invalid = @{(id)kCGPDFContextMediaBox:[NSData data]};
    BOOL raised = NO;
    @try {
        CGPDFContextBeginPage(context, (CFDictionaryRef)invalid);
    } @catch (NSException *exception) {
        raised = [[exception name] isEqual:NSInvalidArgumentException];
    }
    if (!raised || [data length] != before)
        return 60;
    finishPage(context, nil);
    CGPDFContextClose(context);
    CGContextRelease(context);
    for (NSUInteger i = 0; i < 5; i++)
        expected[i] = CGRectMake(0, 0, 612, 792);
    if (!checkPages(data, expected, 1))
        return 70;
    CGRect nonfinite = CGRectMake(NAN, 0, 10, 10);
    NSArray *badInfo = @[invalid, @{(id)kCGPDFContextCropBox:@"not data"},
                        boxInfo(&nonfinite, 1)];
    for (NSDictionary *info in badInfo) {
        data = [NSMutableData data];
        context = contextForData(data, NULL, info);
        if (context != NULL || [data length] != 0)
            return 80;
    }
    [pool drain];
    puts("PDF lifecycle defaults, overrides, corners and rejection passed");
    return 0;
}
