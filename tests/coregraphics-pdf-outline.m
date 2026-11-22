// Contract: CGPDFDocumentGetOutline (CFDictionaryRef from a CGPDFDocumentRef) and CGPDFContextSetOutline
// (a CGContextRef and a CFDictionaryRef): the documentation pages give the signatures and the optional
// dictionary. The behaviour is pinned to what was observed on macOS 26.7.3 and Mac OS X 10.14.4 (identical):
//  - a PDF written by CGPDFContext without an outline gives NULL; GetOutline(NULL) gives NULL;
//  - after CGPDFContextSetOutline with a dictionary, even an empty one, the closed document gives a non-NULL
//    dictionary with one key.
// Beyond that (not observed, a Darling design): the titles and nesting of kCGPDFOutlineChildren survive a round
// trip through the file. A NULL outline is only checked to leave a valid one-page document.
// Exit codes: 10 a function is missing, 20 context not created, 30 + i the file of case i is not a one-page
// document, 40 + i case i: wrong answer for the outline presence, 50 + i the key count is not one, 60 round trip.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

extern CFDictionaryRef CGPDFDocumentGetOutline(CGPDFDocumentRef) __attribute__((weak_import));
extern void CGPDFContextSetOutline(CGContextRef, CFDictionaryRef) __attribute__((weak_import));

int main(void) {
    if (CGPDFDocumentGetOutline == NULL || CGPDFContextSetOutline == NULL) {
        fputs("missing PDF outline interface\n", stderr);
        return 10;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *chapter = [NSDictionary dictionaryWithObjectsAndKeys:
            @"Chapter 1", @"Title",
            [NSArray arrayWithObject: [NSDictionary dictionaryWithObject: @"Section 1.1" forKey: @"Title"]], @"Children",
            nil];
    NSDictionary *outline = [NSDictionary dictionaryWithObject:
            [NSArray arrayWithObjects: chapter, [NSDictionary dictionaryWithObject: @"Chapter 2" forKey: @"Title"], nil]
            forKey: @"Children"];
    // Case 0 never sets an outline, 1 sets NULL, 2 an empty dictionary, 3 the nested outline.
    for (unsigned i = 0; i < 4; i++) {
        NSMutableData *data = [NSMutableData data];
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
        CGRect box = CGRectMake(0, 0, 100, 200);
        CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
        CGDataConsumerRelease(consumer);
        if (!context) return 20;
        if (i == 1) CGPDFContextSetOutline(context, NULL);
        if (i == 2) CGPDFContextSetOutline(context, (CFDictionaryRef)[NSDictionary dictionary]);
        if (i == 3) CGPDFContextSetOutline(context, (CFDictionaryRef)outline);
        CGPDFContextBeginPage(context, NULL);
        CGPDFContextEndPage(context);
        CGPDFContextClose(context);
        CGContextRelease(context);
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
        CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
        CGDataProviderRelease(provider);
        if (!document || CGPDFDocumentGetNumberOfPages(document) != 1) return 30 + i;
        CFDictionaryRef read = CGPDFDocumentGetOutline(document);
        if (i < 2 && read != NULL) return 40 + i;
        if (i >= 2 && read == NULL) return 40 + i;
        if (i >= 2 && CFDictionaryGetCount(read) != 1) return 50 + i;
        if (i == 3) {
            NSArray *top = [(NSDictionary *)read objectForKey: (id)kCGPDFOutlineChildren];
            NSDictionary *first = [top count] == 2 ? [top objectAtIndex: 0] : nil;
            NSArray *sub = [first objectForKey: (id)kCGPDFOutlineChildren];
            if (![[first objectForKey: (id)kCGPDFOutlineTitle] isEqual: @"Chapter 1"] ||
                ![[[top objectAtIndex: 1] objectForKey: (id)kCGPDFOutlineTitle] isEqual: @"Chapter 2"] ||
                [sub count] != 1 ||
                ![[[sub objectAtIndex: 0] objectForKey: (id)kCGPDFOutlineTitle] isEqual: @"Section 1.1"])
                return 60;
        }
        CGPDFDocumentRelease(document);
    }
    if (CGPDFDocumentGetOutline(NULL) != NULL) return 61;
    [pool drain];
    puts("PDF outline interface passed");
    return 0;
}
