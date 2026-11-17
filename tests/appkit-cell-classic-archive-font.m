// Copyright (C) 2026 Lubos Dolezel
//
// A text cell read from a classic (non-keyed) archive keeps its font. Interface Builder nibs of
// Mac OS X 10.3 and 10.4 are such archives, and every control in them has its own font and size.
// The archives below were written by NSArchiver on macOS 10.14.4 (black-box fixtures: a text cell
// with Helvetica 10, and one with Courier 22 right aligned); both read them back with the same fonts.
#import <AppKit/AppKit.h>
#include <stdio.h>

static const unsigned char cellHelvetica10[] = {4,11,115,116,114,101,97,109,116,121,112,101,100,129,232,3,132,1,64,132,132,132,15,78,83,84,101,120,116,70,105,101,108,100,67,101,108,108,62,132,132,12,78,83,65,99,116,105,111,110,67,101,108,108,17,132,132,6,78,83,67,101,108,108,65,132,132,8,78,83,79,98,106,101,99,116,0,133,132,2,105,105,130,0,0,0,4,0,132,4,64,64,64,64,132,132,132,8,78,83,83,116,114,105,110,103,1,150,132,1,43,5,72,101,108,108,111,134,132,132,132,6,78,83,70,111,110,116,30,150,132,1,105,28,132,5,91,50,56,99,93,6,0,0,0,20,0,0,0,255,254,72,0,101,0,108,0,118,0,101,0,116,0,105,0,99,0,97,0,132,1,102,10,132,1,99,0,159,1,159,0,159,0,134,133,133,132,2,105,58,0,133,146,133,146,133,132,3,99,64,64,0,132,132,132,7,78,83,67,111,108,111,114,0,150,159,6,132,3,64,64,64,132,152,154,6,83,121,115,116,101,109,134,132,152,154,19,116,101,120,116,66,97,99,107,103,114,111,117,110,100,67,111,108,111,114,134,132,156,159,3,132,2,102,102,1,1,134,134,132,156,159,6,163,157,132,152,154,16,99,111,110,116,114,111,108,84,101,120,116,67,111,108,111,114,134,132,156,159,3,164,0,1,134,134,134};
static const unsigned char cellCourier22[] = {4,11,115,116,114,101,97,109,116,121,112,101,100,129,232,3,132,1,64,132,132,132,15,78,83,84,101,120,116,70,105,101,108,100,67,101,108,108,62,132,132,12,78,83,65,99,116,105,111,110,67,101,108,108,17,132,132,6,78,83,67,101,108,108,65,132,132,8,78,83,79,98,106,101,99,116,0,133,132,2,105,105,130,0,0,0,4,130,0,0,0,4,132,4,64,64,64,64,132,132,132,8,78,83,83,116,114,105,110,103,1,150,132,1,43,12,75,105,108,108,115,10,68,101,97,116,104,115,134,132,132,132,6,78,83,70,111,110,116,30,150,132,1,105,24,132,5,91,50,52,99,93,6,0,0,0,16,0,0,0,255,254,67,0,111,0,117,0,114,0,105,0,101,0,114,0,132,1,102,22,132,1,99,0,159,1,159,0,159,0,134,133,133,132,2,105,58,0,133,146,133,146,133,132,3,99,64,64,0,132,132,132,7,78,83,67,111,108,111,114,0,150,159,6,132,3,64,64,64,132,152,154,6,83,121,115,116,101,109,134,132,152,154,19,116,101,120,116,66,97,99,107,103,114,111,117,110,100,67,111,108,111,114,134,132,156,159,3,132,2,102,102,1,1,134,134,132,156,159,6,163,157,132,152,154,16,99,111,110,116,114,111,108,84,101,120,116,67,111,108,111,114,134,132,156,159,3,164,0,1,134,134,134};

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void checkCell(const unsigned char *bytes, size_t length, NSString *font, CGFloat size, NSString *string, NSTextAlignment alignment) {
    NSData *data = [NSData dataWithBytes: bytes length: length];
    NSTextFieldCell *cell = nil;
    @try {
        cell = [NSUnarchiver unarchiveObjectWithData: data];
    } @catch (NSException *e) {
        CHECK(NO, "unarchiving raised %s", [[e reason] UTF8String]);
    }
    CHECK([cell isKindOfClass: [NSTextFieldCell class]], "not a text field cell");
    if (![cell isKindOfClass: [NSTextFieldCell class]])
        return;
    CHECK([[[cell font] fontName] isEqualToString: font], "font %s", [[[cell font] fontName] UTF8String]);
    CHECK([[cell font] pointSize] == size, "size %g", [[cell font] pointSize]);
    CHECK([[cell stringValue] isEqualToString: string], "string %s", [[cell stringValue] UTF8String]);
    CHECK([cell alignment] == alignment, "alignment %ld", (long) [cell alignment]);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        checkCell(cellHelvetica10, sizeof cellHelvetica10, @"Helvetica", 10, @"Hello", NSLeftTextAlignment);
        checkCell(cellCourier22, sizeof cellCourier22, @"Courier", 22, @"Kills\nDeaths", NSRightTextAlignment);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
