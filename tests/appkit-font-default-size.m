/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// +[NSFont fontWithName:size:] makes a font of the default size, 12 points,
// when asked for a size of 0 or less. +[NSFont fontWithDescriptor:size:] then
// uses the descriptor's size, also after the descriptor was changed with
// fontDescriptorByAddingAttributes: or fontDescriptorWithSymbolicTraits:, and
// the default size when the descriptor has none.
// Results as on macOS 26.7.3 and 10.14.4. No display needed. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expectSize(NSFont *font, CGFloat expected, const char *label) {
    BOOL ok = font != nil && [font pointSize] == expected;
    printf("%s %s: %g, expected %g\n", ok ? "PASS" : "FAIL", label, font ? [font pointSize] : -1.0, expected);
    failures += !ok;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        expectSize([NSFont fontWithName: @"Helvetica" size: 0], 12, "a named font of size 0");
        expectSize([NSFont fontWithName: @"Helvetica" size: -3], 12, "a named font of a negative size");
        expectSize([NSFont fontWithName: @"Helvetica" size: 9], 9, "a named font of size 9");

        NSFontDescriptor *sized = [NSFontDescriptor fontDescriptorWithName: @"Helvetica" size: 17];
        expectSize([NSFont fontWithDescriptor: sized size: 0], 17, "a descriptor's size, asked for 0");
        expectSize([NSFont fontWithDescriptor: sized size: -3], 17, "a descriptor's size, asked for a negative size");
        expectSize([NSFont fontWithDescriptor: sized size: 11], 11, "a size asked for overrides the descriptor's");

        NSFontDescriptor *family = [NSFontDescriptor fontDescriptorWithFontAttributes:
                @{NSFontFamilyAttribute: @"Helvetica", NSFontSizeAttribute: @15}];
        expectSize([NSFont fontWithDescriptor: family size: 0], 15, "a family descriptor's size");

        NSFontDescriptor *unsized = [NSFontDescriptor fontDescriptorWithFontAttributes: @{NSFontFamilyAttribute: @"Helvetica"}];
        expectSize([NSFont fontWithDescriptor: unsized size: 0], 12, "a descriptor without a size gives the default size");
        expectSize([NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Helvetica" size: 0] size: 0], 12,
                   "a descriptor of size 0 gives the default size");

        NSFont *system = [NSFont systemFontOfSize: 9.5];
        NSFontDescriptor *changed = [[system fontDescriptor] fontDescriptorByAddingAttributes:
                @{NSFontFeatureSettingsAttribute: @[@{NSFontFeatureTypeIdentifierKey: @6, NSFontFeatureSelectorIdentifierKey: @0}]}];
        expectSize([NSFont fontWithDescriptor: [system fontDescriptor] size: 0], 9.5, "a font's own descriptor keeps its size");
        expectSize([NSFont fontWithDescriptor: changed size: 0], 9.5, "a descriptor with added attributes keeps the size");
        expectSize([NSFont fontWithDescriptor: [changed fontDescriptorWithSymbolicTraits: NSFontBoldTrait] size: 0], 9.5,
                   "a descriptor with changed traits keeps the size");
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
