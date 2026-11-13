#import <Foundation/Foundation.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFString.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    @autoreleasepool {
        const char *inputs[] = {"<FEFF00410042>", "(\\376\\377\\000A\\000B)"};
        const unsigned char expected[] = {0xFE, 0xFF, 0, 'A', 0, 'B'};
        unsigned failures = 0;
        for (unsigned i = 0; i < 2; i++) {
            O2PDFObject *object = nil;
            O2PDFInteger end = 0;
            if (!O2PDFScanObject(inputs[i], strlen(inputs[i]), 0, &end, &object) ||
                ![object isKindOfClass:[O2PDFString class]] ||
                [(O2PDFString *)object length] != sizeof(expected) ||
                memcmp([(O2PDFString *)object bytes], expected, sizeof(expected))) {
                fprintf(stderr, "parsed PDF string byte mismatch: %s\n", inputs[i]);
                failures++;
            }
        }
        O2PDFString *copy = [O2PDFString pdfObjectWithBytes:expected length:sizeof(expected)];
        if ([copy length] != sizeof(expected) || memcmp([copy bytes], expected, sizeof(expected))) {
            fprintf(stderr, "copied PDF string byte mismatch\n");
            failures++;
        }
        if (failures) return failures;
        puts("parsed PDF string bytes preserved");
    }
    return 0;
}
