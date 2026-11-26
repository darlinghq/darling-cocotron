// CGPDFContextSetURLForRect, CGPDFContextAddDestinationAtPoint and
// CGPDFContextSetDestinationForRect (Apple's CGPDFContext reference): a URL
// link or a link to a named destination covers a rect of the current page,
// and a named destination marks a point on it. Read back as PDF 1.3 defines
// them (sections 8.2.1, 8.4.5 and 8.5.3): link annotations in the page's
// Annots, the destinations in the catalog's name tree. The rect and the point
// are in user space, so the CTM applies.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFDictionary.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static BOOL textEquals(CGPDFStringRef string, NSString *expected) {
    CFStringRef text = string ? CGPDFStringCopyTextString(string) : NULL;
    BOOL same = text != NULL && [(NSString *)text isEqualToString:expected];
    if (text)
        CFRelease(text);
    return same;
}

static BOOL rectIs(CGPDFArrayRef rect, CGFloat x0, CGFloat y0, CGFloat x1, CGFloat y1) {
    CGFloat v[4];
    if (rect == NULL || CGPDFArrayGetCount(rect) != 4)
        return NO;
    for (size_t i = 0; i < 4; i++)
        if (!CGPDFArrayGetNumber(rect, i, &v[i]))
            return NO;
    return fabs(v[0] - x0) < 1e-6 && fabs(v[1] - y0) < 1e-6 && fabs(v[2] - x1) < 1e-6 && fabs(v[3] - y1) < 1e-6;
}

int main(void) {
    @autoreleasepool {
        NSMutableData *data = [NSMutableData data];
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
        CGRect box = CGRectMake(0, 0, 200, 300);
        CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
        CGDataConsumerRelease(consumer);
        CHECK(context != NULL);

        // outside a page, nothing is recorded
        CGPDFContextAddDestinationAtPoint(context, CFSTR("early"), CGPointMake(1, 1));

        CGPDFContextBeginPage(context, NULL);
        CGContextTranslateCTM(context, 10, 20);
        CGPDFContextSetURLForRect(context, (CFURLRef)[NSURL URLWithString:@"https://example.com/a"], CGRectMake(0, 0, 50, 10));
        CGPDFContextAddDestinationAtPoint(context, CFSTR("section"), CGPointMake(5, 100));
        CGPDFContextSetDestinationForRect(context, CFSTR("section"), CGRectMake(0, 30, 40, 10));
        CGPDFContextEndPage(context);
        CGPDFContextClose(context);
        CGContextRelease(context);

        // a context that is not a PDF context ignores the calls
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(NULL, 4, 4, 8, 0, space, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        CGPDFContextSetURLForRect(bitmap, (CFURLRef)[NSURL URLWithString:@"https://example.com/"], CGRectMake(0, 0, 1, 1));
        CGPDFContextAddDestinationAtPoint(bitmap, CFSTR("x"), CGPointZero);
        CGContextRelease(bitmap);

        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
        CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
        CGDataProviderRelease(provider);
        CHECK(document != NULL && CGPDFDocumentGetNumberOfPages(document) == 1);
        if (document == NULL)
            return 1;

        CGPDFDictionaryRef page = CGPDFPageGetDictionary(CGPDFDocumentGetPage(document, 1));
        CGPDFArrayRef annotations = NULL;
        CHECK(page && CGPDFDictionaryGetArray(page, "Annots", &annotations) && CGPDFArrayGetCount(annotations) == 2);

        CGPDFDictionaryRef uriLink = NULL, destLink = NULL;
        if (annotations && CGPDFArrayGetCount(annotations) == 2) {
            CGPDFArrayGetDictionary(annotations, 0, &uriLink);
            CGPDFArrayGetDictionary(annotations, 1, &destLink);
        }
        const char *name = NULL;
        CGPDFArrayRef rect = NULL;
        CHECK(uriLink && CGPDFDictionaryGetName(uriLink, "Subtype", &name) && strcmp(name, "Link") == 0);
        CHECK(uriLink && CGPDFDictionaryGetArray(uriLink, "Rect", &rect) && rectIs(rect, 10, 20, 60, 30));
        CGPDFDictionaryRef action = NULL;
        CGPDFStringRef string = NULL;
        CHECK(uriLink && CGPDFDictionaryGetDictionary(uriLink, "A", &action)
              && CGPDFDictionaryGetName(action, "S", &name) && strcmp(name, "URI") == 0
              && CGPDFDictionaryGetString(action, "URI", &string) && textEquals(string, @"https://example.com/a"));

        CHECK(destLink && CGPDFDictionaryGetName(destLink, "Subtype", &name) && strcmp(name, "Link") == 0);
        CHECK(destLink && CGPDFDictionaryGetArray(destLink, "Rect", &rect) && rectIs(rect, 10, 50, 50, 60));
        CHECK(destLink && CGPDFDictionaryGetString(destLink, "Dest", &string) && textEquals(string, @"section"));

        // the catalog's Names / Dests tree holds only the destination made on a page
        O2PDFDictionary *catalog = [(O2PDFDocument *)document catalog];
        O2PDFDictionary *names = nil, *dests = nil;
        CHECK([catalog getDictionaryForKey:"Names" value:&names] && [names getDictionaryForKey:"Dests" value:&dests]);
        CGPDFArrayRef pairs = NULL;
        CHECK(dests && CGPDFDictionaryGetArray((CGPDFDictionaryRef)dests, "Names", &pairs) && CGPDFArrayGetCount(pairs) == 2);
        CGPDFArrayRef destination = NULL;
        CGFloat x = 0, y = 0;
        CHECK(pairs && CGPDFArrayGetString(pairs, 0, &string) && textEquals(string, @"section"));
        CHECK(pairs && CGPDFArrayGetArray(pairs, 1, &destination) && CGPDFArrayGetCount(destination) == 5
              && CGPDFArrayGetName(destination, 1, &name) && strcmp(name, "XYZ") == 0
              && CGPDFArrayGetNumber(destination, 2, &x) && CGPDFArrayGetNumber(destination, 3, &y)
              && fabs(x - 15) < 1e-6 && fabs(y - 120) < 1e-6 && CGPDFArrayGetNull(destination, 4));
        CGPDFDictionaryRef target = NULL;
        CHECK(destination && CGPDFArrayGetDictionary(destination, 0, &target)
              && CGPDFDictionaryGetName(target, "Type", &name) && strcmp(name, "Page") == 0);

        CGPDFDocumentRelease(document);
    }
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
