/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSColor: the system colors added in 10.10 - 11, highlightWithLevel: and shadowWithLevel:,
 * colorWithSystemEffect:, colorUsingType:, the localized catalog names and colorWithColorSpace:hue:...
 * Expected values are what macOS 10.14.4 and 26.7.3 answer in the Aqua appearance (probes:
 * vd-upstream/mac-probes/v615_color_*.m); the effects are fitted numbers, checked to 0.01. Where the
 * two systems differ the value is not checked. No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

// The API under test, declared here so that the test also builds against an SDK that predates it.
@interface NSColor (V615Test)
+ (NSColor *) quinaryLabelColor;
+ (NSColor *) placeholderTextColor;
+ (NSColor *) underPageBackgroundColor;
+ (NSColor *) findHighlightColor;
+ (NSColor *) systemFillColor;
+ (NSColor *) secondarySystemFillColor;
+ (NSColor *) tertiarySystemFillColor;
+ (NSColor *) quaternarySystemFillColor;
+ (NSColor *) quinarySystemFillColor;
+ (NSColor *) colorWithColorSpace: (NSColorSpace *) space hue: (CGFloat) hue saturation: (CGFloat) saturation brightness: (CGFloat) brightness alpha: (CGFloat) alpha;
- (NSColor *) highlightWithLevel: (CGFloat) level;
- (NSColor *) shadowWithLevel: (CGFloat) level;
- (NSColor *) colorWithSystemEffect: (NSInteger) effect;
- (NSColor *) colorUsingType: (NSInteger) type;
- (NSString *) localizedCatalogNameComponent;
- (NSString *) localizedColorNameComponent;
@end

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            failures++; \
            printf("FAIL line %d: ", __LINE__); \
            printf(__VA_ARGS__); \
            printf("\n"); \
        } \
    } while (0)

static BOOL near(CGFloat a, CGFloat b, CGFloat tolerance) { return a > b - tolerance && a < b + tolerance; }

static NSColor *srgb(NSColor *c) { return [c colorUsingColorSpace: [NSColorSpace sRGBColorSpace]]; }

static BOOL isColor(NSColor *c, CGFloat r, CGFloat g, CGFloat b, CGFloat a, CGFloat tolerance) {
    NSColor *s = srgb(c);
    return s != nil && near([s redComponent], r, tolerance) && near([s greenComponent], g, tolerance) &&
            near([s blueComponent], b, tolerance) && near([s alphaComponent], a, tolerance);
}

static void testSystemColors(void) {
    CHECK(isColor([NSColor underPageBackgroundColor], 0.5882, 0.5882, 0.5882, 0.898, 0.005), "underPageBackgroundColor");
    CHECK(isColor([NSColor findHighlightColor], 1, 1, 0, 1, 0.005), "findHighlightColor");
    NSColor *placeholder = srgb([NSColor placeholderTextColor]);
    CHECK([placeholder redComponent] == 0 && [placeholder alphaComponent] > 0.2 && [placeholder alphaComponent] < 0.52, "placeholderTextColor is translucent black");
    CHECK([[NSColor placeholderTextColor] type] == NSColorTypeCatalog, "system colors are catalog colors");

    // 11 and later (not on 10.14): black at falling alpha
    if ([NSColor respondsToSelector: @selector(systemFillColor)]) {
        CGFloat expected[] = { 0.0980, 0.0784, 0.0471, 0.0275, 0.0078 };
        NSColor *fills[] = { [NSColor systemFillColor], [NSColor secondarySystemFillColor], [NSColor tertiarySystemFillColor],
                             [NSColor quaternarySystemFillColor], [NSColor quinarySystemFillColor] };
        for (int i = 0; i < 5; i++)
            CHECK(isColor(fills[i], 0, 0, 0, expected[i], 0.005), "system fill %d", i);
    }
    if ([NSColor respondsToSelector: @selector(quinaryLabelColor)])
        CHECK(isColor([NSColor quinaryLabelColor], 0, 0, 0, 0.0471, 0.005), "quinaryLabelColor");
}

static void testLevels(void) {
    NSColor *base = [NSColor colorWithSRGBRed: 0.2 green: 0.4 blue: 0.8 alpha: 1.0];
    CHECK(isColor([base highlightWithLevel: 0], 0.2, 0.4, 0.8, 1, 0.002), "highlight 0 keeps the color");
    CHECK(isColor([base shadowWithLevel: 0], 0.2, 0.4, 0.8, 1, 0.002), "shadow 0 keeps the color");
    CHECK(isColor([base highlightWithLevel: 1], 1, 1, 1, 1, 0.002), "highlight 1 is white");
    CHECK(isColor([base shadowWithLevel: 1], 0, 0, 0, 1, 0.002), "shadow 1 is black");
    CHECK(isColor([base highlightWithLevel: 2], 1, 1, 1, 1, 0.002), "highlight above 1 is limited");
    CHECK(isColor([base shadowWithLevel: 2], 0, 0, 0, 1, 0.002), "shadow above 1 is limited");
    CHECK(isColor([base highlightWithLevel: -0.5], 0.2, 0.4, 0.8, 1, 0.002), "highlight below 0 is limited");
    NSColor *light = srgb([base highlightWithLevel: 0.5]);
    NSColor *dark = srgb([base shadowWithLevel: 0.5]);
    CHECK([light redComponent] > 0.2 && [light blueComponent] > 0.8 - 0.0001 && [dark redComponent] < 0.2 && [dark blueComponent] < 0.8, "highlight lightens, shadow darkens");
    CHECK([[base highlightWithLevel: 0.5] type] == NSColorTypeComponentBased, "the result is a component color");
    CHECK([[[base highlightWithLevel: 0.5] colorSpaceName] isEqual: NSCalibratedRGBColorSpace], "calibrated RGB");

    // The blend includes the alpha: half way to an opaque color
    NSColor *translucent = [NSColor colorWithSRGBRed: 0.2 green: 0.4 blue: 0.8 alpha: 0.5];
    CHECK(near([[translucent highlightWithLevel: 0.5] alphaComponent], 0.75, 0.002), "highlight blends the alpha");
    CHECK(near([[translucent shadowWithLevel: 0.5] alphaComponent], 0.75, 0.002), "shadow blends the alpha");

    // A catalog color gives a component color, a pattern none
    NSColor *fromCatalog = [[NSColor textColor] highlightWithLevel: 0.5];
    CHECK(fromCatalog != nil && [fromCatalog type] == NSColorTypeComponentBased, "catalog color: a component color");
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(2, 2)] autorelease];
    CHECK([[NSColor colorWithPatternImage: image] highlightWithLevel: 0.5] == nil, "pattern color: nil");
}

static void testSystemEffects(void) {
    NSColor *base = [NSColor colorWithSRGBRed: 0.2 green: 0.4 blue: 0.8 alpha: 1.0];
    CHECK(isColor([base colorWithSystemEffect: 0], 0.2, 0.4, 0.8, 1, 0.002), "no effect");
    CHECK(isColor([base colorWithSystemEffect: 1], 0.1059, 0.2902, 0.6588, 1, 0.01), "pressed");
    CHECK(isColor([base colorWithSystemEffect: 2], 0.0300, 0.2020, 0.5451, 1, 0.01), "deep pressed");
    CHECK(isColor([base colorWithSystemEffect: 3], 0.2, 0.4, 0.8, 0.35, 0.005), "disabled keeps the color and thins the alpha");
    CHECK(isColor([base colorWithSystemEffect: 4], 0.0300, 0.2020, 0.5451, 1, 0.01), "rollover");
    CHECK([[base colorWithSystemEffect: 1] type] == NSColorTypeCatalog, "the result is a dynamic (catalog) color");

    NSColor *white = [NSColor colorWithSRGBRed: 1 green: 1 blue: 1 alpha: 1];
    CHECK(isColor([white colorWithSystemEffect: 1], 0.8431, 0.8431, 0.8431, 1, 0.01), "white pressed");
    CHECK(isColor([white colorWithSystemEffect: 2], 0.7176, 0.7176, 0.7176, 1, 0.01), "white deep pressed");
    NSColor *label = [NSColor colorWithSRGBRed: 0 green: 0 blue: 0 alpha: 0.8471];
    CHECK(isColor([label colorWithSystemEffect: 1], 0, 0, 0, 0.9373, 0.01), "translucent black pressed: more opaque");
    CHECK(isColor([label colorWithSystemEffect: 2], 0, 0, 0, 1.0, 0.01), "translucent black deep pressed: opaque");
    CHECK(isColor([label colorWithSystemEffect: 3], 0, 0, 0, 0.2965, 0.01), "translucent black disabled");

    // Works on a catalog color, and changes with what it was made from
    NSColor *fromLabel = [[NSColor labelColor] colorWithSystemEffect: 1];
    CHECK(fromLabel != nil && [srgb(fromLabel) alphaComponent] > [srgb([NSColor labelColor]) alphaComponent], "effect of a catalog color");
}

static void testTypes(void) {
    NSColor *rgb = [NSColor colorWithSRGBRed: 0.2 green: 0.4 blue: 0.8 alpha: 1.0];
    NSColor *catalog = [NSColor textColor];
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(2, 2)] autorelease];
    NSColor *pattern = [NSColor colorWithPatternImage: image];
    CHECK([rgb type] == NSColorTypeComponentBased && [catalog type] == NSColorTypeCatalog && [pattern type] == NSColorTypePattern, "types");

    CHECK([rgb colorUsingType: NSColorTypeComponentBased] == rgb, "component to component: itself");
    CHECK([rgb colorUsingType: NSColorTypeCatalog] == nil, "component to catalog: nil");
    CHECK([rgb colorUsingType: NSColorTypePattern] == nil, "component to pattern: nil");
    NSColor *resolved = [catalog colorUsingType: NSColorTypeComponentBased];
    CHECK(resolved != nil && [resolved type] == NSColorTypeComponentBased, "catalog to component: what it stands for");
    CHECK([catalog colorUsingType: NSColorTypeCatalog] == catalog, "catalog to catalog: itself");
    CHECK([catalog colorUsingType: NSColorTypePattern] == nil, "catalog to pattern: nil");
    CHECK([[[NSColor labelColor] colorUsingType: NSColorTypeComponentBased] type] == NSColorTypeComponentBased, "system color to component");
    CHECK([pattern colorUsingType: NSColorTypeComponentBased] == nil, "pattern to component: nil");
    CHECK([pattern colorUsingType: NSColorTypeCatalog] == nil, "pattern to catalog: nil");
    CHECK([pattern colorUsingType: NSColorTypePattern] == pattern, "pattern to pattern: itself");
}

static void testCatalogNames(void) {
    NSColor *text = [NSColor textColor];
    CHECK([[text catalogNameComponent] isEqual: @"System"] && [[text colorNameComponent] isEqual: @"textColor"], "catalog and color name");
    CHECK([[text localizedCatalogNameComponent] isEqual: @"Developer"], "localized catalog name of the System list: %s", [[text localizedCatalogNameComponent] UTF8String]);
    CHECK([[text localizedColorNameComponent] isEqual: @"textColor"], "localized color name");
    BOOL raised = NO;
    @try { [[NSColor colorWithSRGBRed: 0.5 green: 0.5 blue: 0.5 alpha: 1] localizedCatalogNameComponent]; }
    @catch (NSException *e) { raised = [[e name] isEqual: NSInvalidArgumentException]; }
    CHECK(raised, "a component color has no catalog name");
}

static void testHSB(void) {
    NSColor *c = [NSColor colorWithColorSpace: [NSColorSpace sRGBColorSpace] hue: 0.6 saturation: 0.5 brightness: 0.4 alpha: 0.9];
    CHECK(isColor(c, 0.2, 0.28, 0.4, 0.9, 0.002), "hsb in sRGB");
    CHECK([[[c colorSpace] localizedName] length] > 0, "keeps the space");
    NSColor *p3 = [NSColor colorWithColorSpace: [NSColorSpace displayP3ColorSpace] hue: 0.6 saturation: 0.5 brightness: 0.4 alpha: 0.9];
    CGFloat r, g, b, a;
    [p3 getRed: &r green: &g blue: &b alpha: &a];
    CHECK(near(r, 0.2, 0.002) && near(g, 0.28, 0.002) && near(b, 0.4, 0.002) && near(a, 0.9, 0.002), "hsb in P3: components are in that space");
    NSColor *red = [NSColor colorWithColorSpace: [NSColorSpace sRGBColorSpace] hue: 0 saturation: 1 brightness: 1 alpha: 1];
    CHECK(isColor(red, 1, 0, 0, 1, 0.002), "hue 0 is red");
    NSColor *green = [NSColor colorWithColorSpace: [NSColorSpace sRGBColorSpace] hue: 1.0 / 3 saturation: 1 brightness: 1 alpha: 1];
    CHECK(isColor(green, 0, 1, 0, 1, 0.002), "hue 1/3 is green");
    NSColor *blue = [NSColor colorWithColorSpace: [NSColorSpace sRGBColorSpace] hue: 2.0 / 3 saturation: 1 brightness: 1 alpha: 1];
    CHECK(isColor(blue, 0, 0, 1, 1, 0.002), "hue 2/3 is blue");
    BOOL raised = NO;
    @try { [NSColor colorWithColorSpace: [NSColorSpace genericGrayColorSpace] hue: 0.1 saturation: 0.1 brightness: 0.1 alpha: 1]; }
    @catch (NSException *e) { raised = [[e name] isEqual: NSInvalidArgumentException]; }
    CHECK(raised, "a gray space is refused");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSAppearance setCurrentAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
        testSystemColors();
        testLevels();
        testSystemEffects();
        testTypes();
        testCatalogNames();
        testHSB();
    }
    if (failures)
        return 1;
    puts("color api: PASS");
    return 0;
}
