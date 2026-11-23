// Copyright (C) 2026 Lubos Dolezel
//
// -[NSFontManager availableFontNamesWithTraits:], from the public contract
// (https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontnames(with:)):
//  - it returns the names (not NSFont objects) of the fonts whose traits are
//    described exactly by the mask;
//  - 0 returns all fonts that are neither italic nor bold, the same result as
//    NSUnitalicFontMask | NSUnboldFontMask.
// The answer is checked against the members -availableMembersOfFontFamily:
// lists for every family. The GUESS choice of the implementation is pinned
// too: a font with an extra trait (narrow, expanded) is still part of the
// answer for a mask that does not mention that trait.
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

// names of the fonts whose italic and bold traits are exactly the given ones
static NSSet *expectedNames(NSFontManager *fm, BOOL italic, BOOL bold) {
    NSMutableSet *names = [NSMutableSet set];
    for (NSString *family in [fm availableFontFamilies]) {
        for (NSArray *member in [fm availableMembersOfFontFamily: family]) {
            NSFontTraitMask traits = [[member objectAtIndex: 3] unsignedIntegerValue];
            if (((traits & NSItalicFontMask) != 0) == italic && ((traits & NSBoldFontMask) != 0) == bold)
                [names addObject: [member objectAtIndex: 0]];
        }
    }
    return names;
}

static void checkMask(NSFontManager *fm, NSFontTraitMask mask, BOOL italic, BOOL bold, const char *label) {
    NSArray *names = [fm availableFontNamesWithTraits: mask];
    CHECK(names != nil, "%s: an array, not nil", label);
    NSSet *got = [NSSet setWithArray: names];
    CHECK([got count] == [names count], "%s: no name twice", label);
    for (id name in names)
        CHECK([name isKindOfClass: [NSString class]] && [name length] > 0, "%s: string name", label);
    NSSet *want = expectedNames(fm, italic, bold);
    CHECK([got isEqualToSet: want], "%s: got %lu names, the families list %lu", label, (unsigned long) [got count],
          (unsigned long) [want count]);
}

int main(void) {
    @autoreleasepool {
        NSFontManager *fm = [NSFontManager sharedFontManager];

        checkMask(fm, 0, NO, NO, "0");
        checkMask(fm, NSUnitalicFontMask | NSUnboldFontMask, NO, NO, "unitalic|unbold");
        checkMask(fm, NSItalicFontMask, YES, NO, "italic");
        checkMask(fm, NSBoldFontMask, NO, YES, "bold");
        checkMask(fm, NSItalicFontMask | NSBoldFontMask, YES, YES, "italic|bold");

        NSSet *plain = [NSSet setWithArray: [fm availableFontNamesWithTraits: 0]];
        CHECK([plain count] > 0, "an installed system has fonts that are neither italic nor bold");
        CHECK([plain isEqualToSet: [NSSet setWithArray: [fm availableFontNamesWithTraits: NSUnitalicFontMask | NSUnboldFontMask]]],
              "0 is the same as unitalic|unbold");
        for (NSString *name in [fm availableFontNamesWithTraits: NSItalicFontMask])
            CHECK(![plain containsObject: name], "%s: italic and plain lists overlap", [name UTF8String]);

        // plain fonts can be created by name and report neither trait
        NSUInteger checked = 0;
        for (NSString *name in plain) {
            NSFont *font = [NSFont fontWithName: name size: 12];
            if (font == nil)
                continue;
            CHECK(!([fm traitsOfFont: font] & (NSItalicFontMask | NSBoldFontMask)), "%s: plain font has italic or bold",
                  [name UTF8String]);
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
