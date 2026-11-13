#import <Foundation/Foundation.h>
#import <CoreGraphics/CGPDFString.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFString.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    CFStringRef (*copyText)(CGPDFStringRef) = dlsym(RTLD_DEFAULT, "CGPDFStringCopyTextString");
    if (!copyText) {
        fprintf(stderr, "missing PDF text string export\n");
        return 10;
    }
    const UniChar plain[] = {'P', 'l', 'a', 'i', 'n', ' ', 't', 'e', 'x', 't'};
    const UniChar symbols[] = {0x02D8, 0x2022, 0x2212, 0x20AC, 0x00E9};
    const UniChar unicode[] = {'A', 0, 'B', 0xD83D, 0xDE00};
    struct {
        const char *input;
        const UniChar *expected;
        CFIndex length;
    } cases[] = {
        {"(Plain\\040text)", plain, 10},
        {"<18808AA0E9>", symbols, 5},
        {"<FEFF004100000042D83DDE00>", unicode, 5},
        {"(\\376\\377\\000A\\000\\000\\000B)", unicode, 3},
        {"()", NULL, 0},
        {"<FEFF>", NULL, 0},
        {"<FEFF00>", NULL, -1},
        {"<FEFFD800>", NULL, -1},
        {"<FEFFDC00>", NULL, -1},
        {"<7F>", NULL, -1}
    };
    CFStringRef results[sizeof(cases) / sizeof(cases[0])] = {0};
    @autoreleasepool {
        for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
            O2PDFObject *object = nil;
            O2PDFInteger end = 0;
            if (!O2PDFScanObject(cases[i].input, strlen(cases[i].input), 0, &end, &object) ||
                ![object isKindOfClass:[O2PDFString class]]) return 20 + i;
            results[i] = copyText((CGPDFStringRef)object);
        }
    }
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (cases[i].length < 0) {
            if (results[i]) return 40 + i;
            continue;
        }
        if (!results[i] || CFStringGetLength(results[i]) != cases[i].length) return 60 + i;
        for (CFIndex j = 0; j < cases[i].length; j++)
            if (CFStringGetCharacterAtIndex(results[i], j) != cases[i].expected[j]) return 80 + i;
        CFRelease(results[i]);
    }
    puts("parsed PDF text strings and ownership passed");
    return 0;
}
