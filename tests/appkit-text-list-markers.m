/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSTextList's marker formats (Apple's NSTextList reference): each
// NSTextListMarker... constant is a "{keyword}" format, and
// markerForItemNumber: puts the item's marker where the keyword is, keeping
// the rest of the format. The numbers are written as the CSS counter styles
// the keywords are named after write them. The constants' strings other than
// decimal, disc and hyphen, and the bullet characters, are inferred, not
// printed on macOS.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

static NSString *marker(NSString *format, int number) {
    NSTextList *list = [[[NSTextList alloc] initWithMarkerFormat: format options: 0] autorelease];
    return [list markerForItemNumber: number];
}

int main(void) {
    @autoreleasepool {
        NSString *constants[] = {
            NSTextListMarkerBox, NSTextListMarkerCheck, NSTextListMarkerCircle, NSTextListMarkerDiamond,
            NSTextListMarkerDisc, NSTextListMarkerHyphen, NSTextListMarkerSquare,
            NSTextListMarkerLowercaseHexadecimal, NSTextListMarkerUppercaseHexadecimal, NSTextListMarkerOctal,
            NSTextListMarkerLowercaseAlpha, NSTextListMarkerUppercaseAlpha, NSTextListMarkerLowercaseLatin,
            NSTextListMarkerUppercaseLatin, NSTextListMarkerLowercaseRoman, NSTextListMarkerUppercaseRoman,
            NSTextListMarkerDecimal,
        };
        BOOL allFormats = YES;
        for (unsigned i = 0; i < sizeof(constants) / sizeof(constants[0]); i++)
            allFormats = allFormats && [constants[i] hasPrefix: @"{"] && [constants[i] hasSuffix: @"}"];
        CHECK(allFormats, "every marker constant is a {keyword} format");
        CHECK([NSTextListMarkerCircle isEqualToString: @"{circle}"], "the circle marker is {circle}");
        CHECK([NSTextListMarkerLowercaseRoman isEqualToString: @"{lower-roman}"], "the lowercase roman marker is {lower-roman}");

        CHECK([marker(NSTextListMarkerDecimal, 12) isEqualToString: @"12"], "decimal");
        CHECK([marker(NSTextListMarkerOctal, 8) isEqualToString: @"10"], "octal");
        CHECK([marker(NSTextListMarkerLowercaseHexadecimal, 255) isEqualToString: @"ff"], "lowercase hexadecimal");
        CHECK([marker(NSTextListMarkerUppercaseHexadecimal, 255) isEqualToString: @"FF"], "uppercase hexadecimal");
        CHECK([marker(NSTextListMarkerLowercaseAlpha, 1) isEqualToString: @"a"], "letters start at a");
        CHECK([marker(NSTextListMarkerUppercaseAlpha, 28) isEqualToString: @"AB"], "letters go on after Z with AA");
        CHECK([marker(NSTextListMarkerLowercaseLatin, 26) isEqualToString: @"z"], "latin letters are the alphabet");
        CHECK([marker(NSTextListMarkerLowercaseRoman, 1994) isEqualToString: @"mcmxciv"], "lowercase roman numerals");
        CHECK([marker(NSTextListMarkerUppercaseRoman, 4) isEqualToString: @"IV"], "uppercase roman numerals");
        CHECK([marker(NSTextListMarkerUppercaseRoman, 0) isEqualToString: @"0"], "a number roman numerals cannot write is decimal");
        CHECK([marker(NSTextListMarkerDisc, 3) isEqualToString: @"•"], "a disc is a bullet");
        CHECK([marker(@"({decimal}).", 3) isEqualToString: @"(3)."], "the rest of the format is kept");
        CHECK([marker(@"{unknown}-{decimal}", 5) isEqualToString: @"{unknown}-5"], "a keyword that is no marker is kept");
        CHECK([marker(@"no keyword", 5) isEqualToString: @"no keyword"], "a format without a keyword is the marker");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
