// Copyright (C) 2026 Lubos Dolezel
// The System color catalog answers for the documented color names with macOS 10.14's light
// appearance values and has no color for any other name, and it agrees with the class methods
// of the same names. Values observed on macOS 10.14.4 (sRGB; mac-probes/ua3-system-colors.m).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static BOOL near(NSColor *c, CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
    c = [c colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    return c && fabs(c.redComponent - r) < 0.002 && fabs(c.greenComponent - g) < 0.002 &&
           fabs(c.blueComponent - b) < 0.002 && fabs(c.alphaComponent - a) < 0.002;
}

static NSColor *catalog(NSString *name)
{
    return [NSColor colorWithCatalogName: @"System" colorName: name];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        struct { NSString *name; CGFloat r, g, b, a; } expected[] = {
            { @"secondaryLabelColor", 0, 0, 0, 0.498 },
            { @"tertiaryLabelColor", 0, 0, 0, 0.247 },
            { @"quaternaryLabelColor", 0, 0, 0, 0.098 },
            { @"placeholderTextColor", 0, 0, 0, 0.247 },
            { @"windowFrameTextColor", 0, 0, 0, 0.847 },
            { @"separatorColor", 0, 0, 0, 0.098 },
            { @"windowBackgroundColor", 0.925, 0.925, 0.925, 1 },
            { @"underPageBackgroundColor", 0.588, 0.588, 0.588, 0.898 },
            { @"findHighlightColor", 1, 1, 0, 1 },
            { @"unemphasizedSelectedTextBackgroundColor", 0.863, 0.863, 0.863, 1 },
            { @"controlAccentColor", 0, 0.478, 1, 1 },
            { @"systemRedColor", 1, 0.231, 0.188, 1 },
            { @"systemGreenColor", 0.157, 0.804, 0.255, 1 },
            { @"systemBlueColor", 0, 0.478, 1, 1 },
            { @"systemOrangeColor", 1, 0.584, 0, 1 },
            { @"systemYellowColor", 1, 0.8, 0, 1 },
            { @"systemBrownColor", 0.635, 0.518, 0.369, 1 },
            { @"systemPinkColor", 1, 0.176, 0.333, 1 },
            { @"systemPurpleColor", 0.686, 0.322, 0.871, 1 },
            { @"systemGrayColor", 0.557, 0.557, 0.576, 1 },
        };
        for (size_t i = 0; i < sizeof(expected) / sizeof(expected[0]); i++) {
            NSColor *c = catalog(expected[i].name);
            if (!near(c, expected[i].r, expected[i].g, expected[i].b, expected[i].a)) {
                printf("FAIL: catalog color %s\n", [expected[i].name UTF8String]);
                g_failures++;
            }
            // The class method of the same name gives that color too.
            NSColor *viaClass = [NSColor performSelector: NSSelectorFromString(expected[i].name)];
            if (!near(viaClass, expected[i].r, expected[i].g, expected[i].b, expected[i].a)) {
                printf("FAIL: class method %s\n", [expected[i].name UTF8String]);
                g_failures++;
            }
        }

        // An unknown name has no color (it must not come back as a placeholder color).
        CHECK(catalog(@"noSuchColorName") == nil);
        CHECK([NSColor colorWithCatalogName: @"NoSuchCatalog" colorName: @"noSuchColorName"] == nil);
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
