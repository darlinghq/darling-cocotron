// Contract: Apple CoreGraphics documentation pages CGPDFDocument.outline (C name
// CGPDFDocumentGetOutline: CFDictionaryRef from a CGPDFDocumentRef) and
// CGPDFContextSetOutline(_:_:) (void, a CGContextRef and a CFDictionaryRef), both
// with an optional dictionary. Neither page says what the dictionary holds, and both
// functions are placeholders for now (see the commit message), so this only
// checks what they promise: the functions exist; a document with no /Outlines entry
// gives NULL (the optional result); setting an outline, or NULL, on a PDF context
// leaves the generated file a valid one-page document. What the document function
// returns for a file that does have an outline, and whether the writer stores one,
// are GUESS and are not pinned: the NULL result is only checked for the cases where
// no outline was set.
// Exit codes: 10 a function is missing, 20 context not created, 30 + i the file of
// case i is not a one-page document, 40 + i case i (0 or 1) has an outline.
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
    // Case 0 never sets an outline, case 1 sets NULL, case 2 sets a dictionary.
    NSDictionary *outline = [NSDictionary dictionaryWithObject:@"Chapter" forKey:@"Title"];
    for (unsigned i = 0; i < 3; i++) {
        NSMutableData *data = [NSMutableData data];
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
        CGRect box = CGRectMake(0, 0, 100, 200);
        CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
        CGDataConsumerRelease(consumer);
        if (!context) return 20;
        if (i == 1) CGPDFContextSetOutline(context, NULL);
        if (i == 2) CGPDFContextSetOutline(context, (CFDictionaryRef)outline);
        CGPDFContextBeginPage(context, NULL);
        CGPDFContextEndPage(context);
        CGPDFContextClose(context);
        CGContextRelease(context);
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
        CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
        CGDataProviderRelease(provider);
        if (!document || CGPDFDocumentGetNumberOfPages(document) != 1) return 30 + i;
        if (i < 2 && CGPDFDocumentGetOutline(document) != NULL) return 40 + i;
        CGPDFDocumentRelease(document);
    }
    [pool drain];
    puts("PDF outline interface passed");
    return 0;
}
