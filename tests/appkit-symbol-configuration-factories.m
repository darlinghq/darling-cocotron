// Copyright (C) 2026 Lubos Dolezel
//
// NSImageSymbolConfiguration factories for a text style and for the monochrome and hierarchical
// rendering preferences. The contract is the NSImage.SymbolConfiguration reference
// (https://developer.apple.com/documentation/appkit/nsimage/symbolconfiguration-swift.class):
//  - +configurationWithTextStyle: and +configurationWithTextStyle:scale: create a configuration for
//    an NSFontTextStyle (and a symbol scale);
//  - +configurationPreferringMonochrome and +configurationPreferringHierarchical create a
//    configuration that prefers that variant of a symbol;
//  - -configurationByApplyingConfiguration: gives a new configuration object, taking priority
//    from the argument.
// The tests check that the objects exist, that they are new objects (configurations are
// immutable), that they can be applied to each other and to a symbol image, and that the image
// keeps being a usable template. They do not check which variant is drawn: that needs the symbol
// artwork. Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-symbol-configuration-factories.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// -isEqual: on a configuration is Darling's own (the reference does not define it), used here to
// tell configurations apart.
static void test_text_style(void) {
    NSImageSymbolConfiguration *body = [NSImageSymbolConfiguration configurationWithTextStyle: NSFontTextStyleBody];
    NSImageSymbolConfiguration *title = [NSImageSymbolConfiguration configurationWithTextStyle: NSFontTextStyleTitle1
                                                                                         scale: NSImageSymbolScaleLarge];
    NSImageSymbolConfiguration *sized = [NSImageSymbolConfiguration configurationWithPointSize: 20 weight: NSFontWeightBold
                                                                                         scale: NSImageSymbolScaleLarge];
    CHECK([body isKindOfClass: [NSImageSymbolConfiguration class]]);
    CHECK([title isKindOfClass: [NSImageSymbolConfiguration class]]);
    CHECK(![body isEqual: title]);
    CHECK(![title isEqual: [NSImageSymbolConfiguration configurationWithTextStyle: NSFontTextStyleBody
                                                                            scale: NSImageSymbolScaleLarge]]);

    NSImageSymbolConfiguration *applied = [body configurationByApplyingConfiguration: title];
    CHECK(applied != nil && applied != body && applied != title);
    CHECK([applied isEqual: title]);
    CHECK(![[title configurationByApplyingConfiguration: body] isEqual: title]);
    // The argument's size specification wins over the receiver's (GUESS for text style against point size).
    CHECK([[sized configurationByApplyingConfiguration: title] isEqual: title]);
    CHECK([[title configurationByApplyingConfiguration: sized] isEqual: sized]);
}

static void test_preferences(void) {
    NSImageSymbolConfiguration *mono = [NSImageSymbolConfiguration configurationPreferringMonochrome];
    NSImageSymbolConfiguration *hier = [NSImageSymbolConfiguration configurationPreferringHierarchical];
    CHECK([mono isKindOfClass: [NSImageSymbolConfiguration class]]);
    CHECK([hier isKindOfClass: [NSImageSymbolConfiguration class]]);
    CHECK(![mono isEqual: hier]);
    CHECK(![mono isEqual: [NSImageSymbolConfiguration configurationPreferringMulticolor]]);

    // The argument's monochrome or hierarchical preference wins; a multicolor argument does not replace a
    // monochrome or hierarchical receiver (black-box observation on macOS 26.7.3).
    NSImageSymbolConfiguration *multi = [NSImageSymbolConfiguration configurationPreferringMulticolor];
    CHECK([[mono configurationByApplyingConfiguration: hier] isEqual: hier]);
    CHECK([[hier configurationByApplyingConfiguration: mono] isEqual: mono]);
    CHECK([[multi configurationByApplyingConfiguration: mono] isEqual: mono]);
    CHECK([[multi configurationByApplyingConfiguration: hier] isEqual: hier]);
    CHECK([[mono configurationByApplyingConfiguration: multi] isEqual: mono]);
    CHECK([[hier configurationByApplyingConfiguration: multi] isEqual: hier]);
    CHECK([[multi configurationByApplyingConfiguration: multi] isEqual: multi]);

    NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize: 20 weight: NSFontWeightBold];
    CHECK([mono configurationByApplyingConfiguration: size] != nil);
    CHECK(![[mono configurationByApplyingConfiguration: size] isEqual: mono]);
    CHECK(![[size configurationByApplyingConfiguration: hier] isEqual: size]);
}

static void test_apply_to_image(void) {
    NSImage *symbol = [NSImage imageWithSystemSymbolName: @"folder" accessibilityDescription: nil];
    NSArray *configurations = [NSArray arrayWithObjects:
            [NSImageSymbolConfiguration configurationWithTextStyle: NSFontTextStyleHeadline],
            [NSImageSymbolConfiguration configurationWithTextStyle: NSFontTextStyleCallout scale: NSImageSymbolScaleSmall],
            [NSImageSymbolConfiguration configurationPreferringMonochrome],
            [NSImageSymbolConfiguration configurationPreferringHierarchical], nil];
    CHECK(symbol != nil);
    for (NSImageSymbolConfiguration *configuration in configurations) {
        NSImage *configured = [symbol imageWithSymbolConfiguration: configuration];
        CHECK(configured != nil);
    }
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_text_style());
    RUN(test_preferences());
    RUN(test_apply_to_image());
    if (failures == 0)
        printf("PASS appkit-symbol-configuration-factories\n");
    [pool release];
    return failures != 0;
}
