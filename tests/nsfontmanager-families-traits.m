// Copyright (C) 2026 Lubos Dolezel
//
// NSFontManager family enumeration and trait conversion, from the public
// contract:
//  - availableFontFamilies lists installed families with no nil or empty names;
//  - availableMembersOfFontFamily: returns, for every listed family, entries
//    that each hold a PostScript name, a style name, a weight and a trait mask
//    (no nil elements), and an unknown family or nil gives no members and does
//    not raise;
//  - -convertFont:toHaveTrait: / -convertFont:toNotHaveTrait: on a family that
//    has regular, italic and bold faces switch the italic or bold trait of the
//    font while keeping the family, and the faces they pick are the regular
//    ones for the family rather than a thin or condensed variant;
//  - fonts found by their member names come back from +[NSFont fontWithName:size:].
// Needs at least one family with a regular face and both an italic and a bold
// face installed (any common sans or serif family does).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

static NSFontTraitMask traitsOf(NSFont *font) {
    return [[NSFontManager sharedFontManager] traitsOfFont: font];
}

int main(void) {
    @autoreleasepool {
        NSFontManager *fm = [NSFontManager sharedFontManager];
        NSArray *families = [fm availableFontFamilies];
        CHECK([families count] > 0, "there are font families");

        NSString *tested = nil;
        NSUInteger checkedFamilies = 0;
        for (NSString *family in families) {
            CHECK([family isKindOfClass: [NSString class]] && [family length] > 0, "family name %@", family);
            if (checkedFamilies++ > 60)
                break;
            NSArray *members = [fm availableMembersOfFontFamily: family];
            BOOL hasRegular = NO, hasItalic = NO, hasBold = NO;
            for (NSArray *member in members) {
                CHECK([member count] >= 4, "%@: member has %lu elements", family, (unsigned long) [member count]);
                if ([member count] < 4)
                    continue;
                for (NSUInteger i = 0; i < 4; i++)
                    CHECK([member objectAtIndex: i] != nil && ![[member objectAtIndex: i] isKindOfClass: [NSNull class]],
                          "%@: member element %lu is nil", family, (unsigned long) i);
                NSFontTraitMask traits = [[member objectAtIndex: 3] unsignedIntegerValue];
                if (traits & NSItalicFontMask)
                    hasItalic = YES;
                if (traits & NSBoldFontMask)
                    hasBold = YES;
                if (!(traits & (NSItalicFontMask | NSBoldFontMask)))
                    hasRegular = YES;
            }
            if (tested == nil && hasRegular && hasItalic && hasBold)
                tested = family;
        }

        CHECK([[fm availableMembersOfFontFamily: nil] count] == 0, "nil family has no members");
        CHECK([[fm availableMembersOfFontFamily: @"No Such Family Installed"] count] == 0, "unknown family has no members");

        CHECK(tested != nil, "a family with regular, italic and bold faces exists");
        if (tested != nil) {
            NSFont *regular = nil;
            for (NSArray *member in [fm availableMembersOfFontFamily: tested]) {
                NSFontTraitMask traits = [[member objectAtIndex: 3] unsignedIntegerValue];
                if (!(traits & (NSItalicFontMask | NSBoldFontMask))) {
                    regular = [NSFont fontWithName: [member objectAtIndex: 0] size: 14];
                    break;
                }
            }
            CHECK(regular != nil, "%@: the regular face can be created by name", tested);
            if (regular != nil) {
                CHECK(!(traitsOf(regular) & (NSItalicFontMask | NSBoldFontMask)), "%@: regular has no italic or bold trait",
                      tested);
                NSFont *italic = [fm convertFont: regular toHaveTrait: NSItalicFontMask];
                CHECK(traitsOf(italic) & NSItalicFontMask, "%@: italic requested, got %@", tested, italic);
                CHECK([[italic familyName] isEqualToString: [regular familyName]], "%@: italic stays in the family", tested);
                CHECK([italic pointSize] == 14, "size kept");

                NSFont *bold = [fm convertFont: regular toHaveTrait: NSBoldFontMask];
                CHECK(traitsOf(bold) & NSBoldFontMask, "%@: bold requested, got %@", tested, bold);

                NSFont *back = [fm convertFont: italic toNotHaveTrait: NSItalicFontMask];
                CHECK(!(traitsOf(back) & NSItalicFontMask), "%@: italic removed, got %@", tested, back);
                CHECK([[back fontName] isEqualToString: [regular fontName]], "%@: removing italic returns the regular face (%@ vs %@)",
                      tested, [back fontName], [regular fontName]);

                NSFont *unbold = [fm convertFont: bold toNotHaveTrait: NSBoldFontMask];
                CHECK(!(traitsOf(unbold) & NSBoldFontMask), "%@: bold removed, got %@", tested, unbold);
                CHECK([[unbold fontName] isEqualToString: [regular fontName]], "%@: removing bold returns the regular face", tested);
            }
        }
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSFontManager families and trait conversion");
    return 0;
}
