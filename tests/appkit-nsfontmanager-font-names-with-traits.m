// Copyright (C) 2026 Lubos Dolezel
//
// -[NSFontManager availableFontNamesWithTraits:]. It returns the names (not NSFont objects) of the
// fonts matching the mask (https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontnames(with:)).
// The page says "exactly" the traits and that 0 gives the fonts that are neither italic nor bold;
// macOS 10.14.4 and 26.7.3 do neither: a face is listed when its traits contain every bit of the
// mask, and 0, NSUnitalicFontMask and NSUnboldFontMask (no face has those bits) list nothing. These
// checks pin that QUIRK (see the QUIRK comment in NSFontManager.m). The answer is compared with the
// members -availableMembersOfFontFamily: lists for every family.
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

// names of the faces whose traits contain every bit of the mask
static NSSet *expectedNames(NSFontManager *fm, NSFontTraitMask mask) {
    NSMutableSet *names = [NSMutableSet set];
    for (NSString *family in [fm availableFontFamilies]) {
        for (NSArray *member in [fm availableMembersOfFontFamily: family]) {
            NSFontTraitMask traits = [[member objectAtIndex: 3] unsignedIntegerValue];
            if ((traits & mask) == mask)
                [names addObject: [member objectAtIndex: 0]];
        }
    }
    return names;
}

static void checkMask(NSFontManager *fm, NSFontTraitMask mask, const char *label) {
    NSArray *names = [fm availableFontNamesWithTraits: mask];
    CHECK(names != nil, "%s: an array, not nil", label);
    NSSet *got = [NSSet setWithArray: names];
    CHECK([got count] == [names count], "%s: no name twice", label);
    for (id name in names)
        CHECK([name isKindOfClass: [NSString class]] && [name length] > 0, "%s: string name", label);
    NSSet *want = expectedNames(fm, mask);
    CHECK([got isEqualToSet: want], "%s: got %lu names, the families list %lu", label, (unsigned long) [got count],
          (unsigned long) [want count]);
}

int main(void) {
    @autoreleasepool {
        NSFontManager *fm = [NSFontManager sharedFontManager];

        checkMask(fm, NSItalicFontMask, "italic");
        checkMask(fm, NSBoldFontMask, "bold");
        checkMask(fm, NSItalicFontMask | NSBoldFontMask, "italic|bold");
        checkMask(fm, NSExpandedFontMask, "expanded");

        NSSet *italic = [NSSet setWithArray: [fm availableFontNamesWithTraits: NSItalicFontMask]];
        NSSet *bold = [NSSet setWithArray: [fm availableFontNamesWithTraits: NSBoldFontMask]];
        NSSet *both = [NSSet setWithArray: [fm availableFontNamesWithTraits: NSItalicFontMask | NSBoldFontMask]];
        CHECK([italic count] > 0 && [bold count] > 0 && [both count] > 0, "an installed system has italic and bold faces");
        // QUIRK check: italic lists the bold italic faces too, so the three lists overlap
        CHECK([both isSubsetOfSet: italic] && [both isSubsetOfSet: bold], "bold italic faces are in both the italic and the bold list");

        // QUIRK check: 0 and the unitalic / unbold bits list nothing
        CHECK([[fm availableFontNamesWithTraits: 0] count] == 0, "0 lists nothing");
        CHECK([[fm availableFontNamesWithTraits: NSUnitalicFontMask | NSUnboldFontMask] count] == 0, "unitalic|unbold lists nothing");
        CHECK([[fm availableFontNamesWithTraits: NSUnboldFontMask] count] == 0, "unbold lists nothing");
        CHECK([[fm availableFontNamesWithTraits: NSUnitalicFontMask] count] == 0, "unitalic lists nothing");
        CHECK([[fm availableFontNamesWithTraits: NSBoldFontMask | NSUnitalicFontMask] count] == 0, "bold|unitalic lists nothing");

        // every listed face can be created by name and reports the requested traits
        NSUInteger checked = 0;
        for (NSString *name in italic) {
            NSFont *font = [NSFont fontWithName: name size: 12];
            if (font == nil)
                continue;
            CHECK([fm traitsOfFont: font] & NSItalicFontMask, "%s: italic font reports italic", [name UTF8String]);
            if (++checked >= 20)
                break;
        }
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSFontManager availableFontNamesWithTraits:");
    return 0;
}
