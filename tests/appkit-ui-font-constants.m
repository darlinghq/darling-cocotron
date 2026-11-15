// Copyright (C) 2026 Lubos Dolezel
// The UIKit font names AppKit exports for UIKit-for-Mac applications hold the values the exported constants hold on macOS 26.7.3
// (black-box observation): the nine UIFontWeight numbers equal the NSFontWeight numbers and the string constants hold the
// descriptor spellings. Without the constants the lookups below find nothing. Not run in Darling (prepared only).
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        static const struct { const char *name; float value; } weights[] = {
        { "UIFontWeightUltraLight", -0.8f },
        { "UIFontWeightThin", -0.6f },
        { "UIFontWeightLight", -0.4f },
        { "UIFontWeightRegular", 0 },
        { "UIFontWeightMedium", 0.23f },
        { "UIFontWeightSemibold", 0.3f },
        { "UIFontWeightBold", 0.4f },
        { "UIFontWeightHeavy", 0.56f },
        { "UIFontWeightBlack", 0.62f }
        };
        static const struct { const char *name; const char *value; } strings[] = {
        { "UIFontDescriptorFamilyAttribute", "NSFontFamilyAttribute" },
        { "UIFontDescriptorNameAttribute", "NSFontNameAttribute" },
        { "UIFontDescriptorSizeAttribute", "NSFontSizeAttribute" },
        { "UIFontDescriptorTraitsAttribute", "NSCTFontTraitsAttribute" },
        { "UIFontDescriptorFeatureSettingsAttribute", "NSCTFontFeatureSettingsAttribute" },
        { "UIFontDescriptorTextStyleAttribute", "NSCTFontUIUsageAttribute" },
        { "UIFontFeatureTypeIdentifierKey", "CTFeatureTypeIdentifier" },
        { "UIFontFeatureSelectorIdentifierKey", "CTFeatureSelectorIdentifier" },
        { "UIFontWeightTrait", "NSCTFontWeightTrait" },
        { "UIFontDescriptorSystemDesignDefault", "NSCTFontUIFontDesignDefault" },
        { "UIFontDescriptorSystemDesignSerif", "NSCTFontUIFontDesignSerif" },
        { "UIFontDescriptorSystemDesignRounded", "NSCTFontUIFontDesignRounded" },
        { "UIFontDescriptorSystemDesignMonospaced", "NSCTFontUIFontDesignMonospaced" },
        { "UIFontSystemFontDesignTrait", "NSCTFontUIFontDesignTrait" },
        { "UIFontSystemFontDesignDefault", "NSCTFontUIFontDesignDefault" },
        { "UIFontSystemFontDesignSerif", "NSCTFontUIFontDesignSerif" },
        { "UIFontSystemFontDesignRounded", "NSCTFontUIFontDesignRounded" },
        { "UIFontSystemFontDesignCompact", "NSCTFontUIFontDesignCompact" },
        { "UIFontSystemFontDesignCondensed", "NSCTFontUIFontDesignCondensed" },
        { "NSFontSystemDesignRounded", "NSCTFontUIFontDesignRounded" }
        };

        for (unsigned i = 0; i < sizeof weights / sizeof *weights; i++)
        {
            const CGFloat *symbol = (const CGFloat *)dlsym(RTLD_DEFAULT, weights[i].name);
            expect(symbol != NULL, [NSString stringWithFormat:@"%s is exported", weights[i].name]);
            // The values are single-precision numbers widened to CGFloat, so compare the widened value exactly.
            expect(*symbol == (CGFloat)weights[i].value, [NSString stringWithFormat:@"%s is %.17g, expected the widened %.9g", weights[i].name, (double)*symbol, (double)weights[i].value]);
        }
        for (unsigned i = 0; i < sizeof strings / sizeof *strings; i++)
        {
            NSString *const *symbol = (NSString *const *)dlsym(RTLD_DEFAULT, strings[i].name);
            expect(symbol != NULL, [NSString stringWithFormat:@"%s is exported", strings[i].name]);
            expect([*symbol isEqualToString:@(strings[i].value)], [NSString stringWithFormat:@"%s is \"%@\", expected \"%s\"", strings[i].name, *symbol, strings[i].value]);
        }

        // The UIKit names are interchangeable with the AppKit ones when a descriptor is built or read.
        NSFontDescriptor *descriptor = [NSFontDescriptor fontDescriptorWithFontAttributes:
            @{ *(NSString *const *)dlsym(RTLD_DEFAULT, "UIFontDescriptorSizeAttribute"): @17 }];
        expect([[descriptor objectForKey:NSFontSizeAttribute] doubleValue] == 17, @"a descriptor keyed with the UIKit size name reads through the AppKit name");
        expect(NSFontWeightRegular == *(const CGFloat *)dlsym(RTLD_DEFAULT, "UIFontWeightRegular"), @"UIFontWeightRegular equals NSFontWeightRegular");
        expect(NSFontWeightBlack == *(const CGFloat *)dlsym(RTLD_DEFAULT, "UIFontWeightBlack"), @"UIFontWeightBlack equals NSFontWeightBlack");
        NSLog(@"appkit-ui-font-constants: ok");
    }
    return 0;
}
