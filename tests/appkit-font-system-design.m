// Copyright (C) 2026 Darling Developers
//
// Build `appkit-font-system-design.m` against AppKit and run it in a Darling guest. Pass the families
// the host's fontconfig should pick for the serif, monospaced and rounded designs, or `-` for a design
// with no installed family:
//
// ```sh
// darling shell appkit-font-system-design "$(fc-match -f '%{family[0]}' serif)" \
//     "$(fc-match -f '%{family[0]}' monospace)" -
// ```
//
// Designs apply only to the system font, and each non-default design maps to a CSS generic family in
// fontconfig (`serif`, `monospace`, `ui-rounded`). Stock fontconfig configurations have no family for
// `ui-rounded`, so the rounded design is nil there, as on a Mac without a rounded system font. To check
// the rounded path, point `FONTCONFIG_FILE` at a configuration that gives `ui-rounded` a family:
//
// ```xml
// <fontconfig>
//   <include ignore_missing="no">/etc/fonts/fonts.conf</include>
//   <match target="pattern">
//     <test name="family"><string>ui-rounded</string></test>
//     <edit name="family" mode="prepend" binding="strong"><string>Nimbus Sans</string></edit>
//   </match>
// </fontconfig>
// ```
//
// and pass `"Nimbus Sans"` (or the family you configured) as the third argument. The pre-fix AppKit
// exports none of the design constants, so the program fails to link against it.

#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSString *familyOf(NSFontDescriptor *descriptor)
{
    return [descriptor objectForKey:NSFontFamilyAttribute];
}

// expected is an installed family name, or "-" when the design has none.
static void checkDesign(NSFontDescriptor *system, NSFontDescriptorSystemDesign design,
                        const char *expected)
{
    NSFontDescriptor *result = [system fontDescriptorWithDesign:design];
    NSLog(@"%@ -> %@", design, result ? familyOf(result) : @"nil");
    if (result == nil)
    {
        expect(expected == NULL || strcmp(expected, "-") == 0,
               [NSString stringWithFormat:@"%@ unexpectedly nil", design]);
        return;
    }
    if (expected != NULL)
        expect([familyOf(result) isEqualToString:@(expected)],
               [NSString stringWithFormat:@"%@ family", design]);
    expect([result objectForKey:NSFontNameAttribute] == nil, @"old font name dropped");
    expect([result pointSize] == [system pointSize], @"point size kept");
    NSFont *font = [NSFont fontWithDescriptor:result size:[result pointSize]];
    expect([[font familyName] isEqualToString:familyOf(result)], @"descriptor resolves to its family");
    NSFontDescriptor *back = [result fontDescriptorWithDesign:NSFontDescriptorSystemDesignDefault];
    expect([familyOf(back) isEqualToString:familyOf(system)], @"a design variant switches back to the default");
    NSFontDescriptor *plain = [NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontFamilyAttribute : familyOf(result)}];
    if (![familyOf(result) isEqualToString:familyOf(system)])
        expect([plain fontDescriptorWithDesign:design] == nil, @"a non-system font has no designs");
}

// Usage: appkit-font-system-design [serif monospaced rounded], each an
// expected family name or "-" for none.
int main(int argc, char **argv)
{
    @autoreleasepool
    {
        expect([NSFontDescriptorSystemDesignDefault isEqualToString:@"NSCTFontUIFontDesignDefault"], @"default value");
        expect([NSFontDescriptorSystemDesignSerif isEqualToString:@"NSCTFontUIFontDesignSerif"], @"serif value");
        expect([NSFontDescriptorSystemDesignMonospaced isEqualToString:@"NSCTFontUIFontDesignMonospaced"], @"monospaced value");
        expect([NSFontDescriptorSystemDesignRounded isEqualToString:@"NSCTFontUIFontDesignRounded"], @"rounded value");

        NSFont *systemFont = [NSFont systemFontOfSize:13];
        expect(systemFont != nil, @"system font");
        NSFontDescriptor *system = [systemFont fontDescriptor];

        NSFontDescriptor *standard = [system fontDescriptorWithDesign:NSFontDescriptorSystemDesignDefault];
        expect([familyOf(standard) isEqualToString:[systemFont familyName]], @"default design is the system family");
        expect([system fontDescriptorWithDesign:@"NSCTFontUIFontDesignBogus"] == nil, @"unknown design");

        checkDesign(system, NSFontDescriptorSystemDesignSerif, argc > 1 ? argv[1] : NULL);
        checkDesign(system, NSFontDescriptorSystemDesignMonospaced, argc > 2 ? argv[2] : NULL);
        checkDesign(system, NSFontDescriptorSystemDesignRounded, argc > 3 ? argv[3] : NULL);
    }
    NSLog(@"PASS");
    return 0;
}
