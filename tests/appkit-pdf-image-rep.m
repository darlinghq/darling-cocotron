/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSPDFImageRep recognizes PDF data and refuses data that is not a readable
// PDF document, without raising.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSData *pdf = [@"%PDF-1.4\n" dataUsingEncoding: NSASCIIStringEncoding];
        NSData *garbage = [@"%PDF-not really a document" dataUsingEncoding: NSASCIIStringEncoding];
        NSData *text = [@"plain text" dataUsingEncoding: NSASCIIStringEncoding];

        expect([NSPDFImageRep canInitWithData: pdf], "PDF data is recognized");
        expect(![NSPDFImageRep canInitWithData: text], "other data is not recognized");
        expect(![NSPDFImageRep canInitWithData: [NSData data]], "empty data is not recognized");
        expect([NSImageRep imageRepClassForData: pdf] == [NSPDFImageRep class],
               "NSImageRep is registered to pick NSPDFImageRep for PDF data");

        NSPDFImageRep *broken = [[NSPDFImageRep alloc] initWithData: garbage];
        expect(broken == nil, "unreadable PDF data gives nil");
        NSPDFImageRep *empty = [[NSPDFImageRep alloc] initWithData: [NSData data]];
        expect(empty == nil, "empty data gives nil");
    }
    printf("pdf image rep: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
