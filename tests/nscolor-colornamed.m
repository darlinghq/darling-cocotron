// Copyright (C) 2026 Lubos Dolezel
//
// +[NSColor colorNamed:bundle:] against an asset catalog compiled with actool
// from our own input (vd-upstream/mac-fixtures/assets/Assets.car: named colors
// FixtureRed, FixtureHalfBlue, FixtureP3Green, FixtureGray, FixtureAppearance
// with a dark variant, FixtureSystemRef).
//
// usage: nscolor-colornamed <path of Assets.car>
//
// The test builds a bundle directory with that catalog and checks:
//  - catalog colors carry the authored components (sRGB red and half blue,
//    gray 0.3 with alpha 1, Display P3 green in the P3 space) and are of type
//    NSColorTypeCatalog;
//  - FixtureAppearance is white under the Aqua appearance and 0.1 gray under
//    Dark Aqua;
//  - a name that is not in the catalog, a nil name, and the names of NSColor's
//    own class methods (labelColor, redColor) give nil, as on macOS;
//  - a bundle without a catalog gives nil.
// FixtureSystemRef (a reference to a system color) is not checked: it resolves
// to the live system color on macOS.
#import <AppKit/AppKit.h>
#include <math.h>
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

static BOOL near(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.002;
}

static void expectRGB(NSColor *color, NSColorSpace *space, CGFloat r, CGFloat g, CGFloat b, CGFloat a, const char *what) {
    NSColor *converted = [color colorUsingColorSpace: space];
    CHECK(converted != nil, "%s: converts to %@", what, space);
    if (converted == nil)
        return;
    CGFloat cr, cg, cb, ca;
    [converted getRed: &cr green: &cg blue: &cb alpha: &ca];
    CHECK(near(cr, r) && near(cg, g) && near(cb, b) && near(ca, a), "%s: %g %g %g %g, expected %g %g %g %g", what, cr, cg, cb, ca,
          r, g, b, a);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s Assets.car\n", argv[0]);
            return 2;
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent: [NSString stringWithFormat: @"colornamed-%d", getpid()]];
        NSString *resources = [root stringByAppendingPathComponent: @"Fixture.bundle/Contents/Resources"];
        NSString *contents = [root stringByAppendingPathComponent: @"Fixture.bundle/Contents"];
        NSString *empty = [root stringByAppendingPathComponent: @"Empty.bundle/Contents"];
        CHECK([fm createDirectoryAtPath: resources withIntermediateDirectories: YES attributes: nil error: NULL], "mkdir");
        CHECK([fm createDirectoryAtPath: [empty stringByAppendingPathComponent: @"Resources"] withIntermediateDirectories: YES
                             attributes: nil
                                  error: NULL],
              "mkdir");
        CHECK([fm copyItemAtPath: [NSString stringWithUTF8String: argv[1]]
                          toPath: [resources stringByAppendingPathComponent: @"Assets.car"]
                           error: NULL],
              "copy catalog");
        NSDictionary *info = @{@"CFBundleIdentifier" : @"org.darlinghq.test.colornamed", @"CFBundleName" : @"Fixture"};
        [info writeToFile: [contents stringByAppendingPathComponent: @"Info.plist"] atomically: YES];
        [@{@"CFBundleIdentifier" : @"org.darlinghq.test.empty"} writeToFile: [empty stringByAppendingPathComponent: @"Info.plist"] atomically: YES];

        NSBundle *bundle = [NSBundle bundleWithPath: [root stringByAppendingPathComponent: @"Fixture.bundle"]];
        NSBundle *emptyBundle = [NSBundle bundleWithPath: [root stringByAppendingPathComponent: @"Empty.bundle"]];
        CHECK(bundle != nil && emptyBundle != nil, "bundles");

        NSColor *red = [NSColor colorNamed: @"FixtureRed" bundle: bundle];
        CHECK(red != nil, "FixtureRed found");
        if (red != nil) {
            CHECK([red type] == NSColorTypeCatalog, "FixtureRed type %ld", (long) [red type]);
            expectRGB(red, [NSColorSpace sRGBColorSpace], 1, 0, 0, 1, "FixtureRed");
        }
        NSColor *half = [NSColor colorNamed: @"FixtureHalfBlue" bundle: bundle];
        CHECK(half != nil, "FixtureHalfBlue found");
        if (half != nil)
            expectRGB(half, [NSColorSpace sRGBColorSpace], 0.2, 0.4, 0.8, 0.5, "FixtureHalfBlue");
        NSColor *gray = [NSColor colorNamed: @"FixtureGray" bundle: bundle];
        CHECK(gray != nil, "FixtureGray found");
        if (gray != nil) {
            CGFloat w, a;
            [[gray colorUsingColorSpaceName: NSCalibratedWhiteColorSpace] getWhite: &w alpha: &a];
            CHECK(near(w, 0.3) && near(a, 1), "FixtureGray white %g alpha %g", w, a);
        }
        NSColor *green = [NSColor colorNamed: @"FixtureP3Green" bundle: bundle];
        CHECK(green != nil, "FixtureP3Green found");
        if (green != nil)
            expectRGB(green, [NSColorSpace displayP3ColorSpace], 0.125, 0.75, 0.25, 1, "FixtureP3Green in P3");

        NSColor *appearance = [NSColor colorNamed: @"FixtureAppearance" bundle: bundle];
        CHECK(appearance != nil, "FixtureAppearance found");
        if (appearance != nil) {
            NSAppearance *saved = [NSAppearance currentAppearance];
            [NSAppearance setCurrentAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
            expectRGB(appearance, [NSColorSpace sRGBColorSpace], 1, 1, 1, 1, "FixtureAppearance under Aqua");
            [NSAppearance setCurrentAppearance: [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]];
            expectRGB(appearance, [NSColorSpace sRGBColorSpace], 0.1, 0.1, 0.1, 1, "FixtureAppearance under Dark Aqua");
            [NSAppearance setCurrentAppearance: saved];
        }

        CHECK([NSColor colorNamed: @"NoSuchColor" bundle: bundle] == nil, "unknown name gives nil");
        CHECK([NSColor colorNamed: nil bundle: bundle] == nil, "nil name gives nil");
        CHECK([NSColor colorNamed: @"labelColor" bundle: bundle] == nil, "labelColor is not a catalog color");
        CHECK([NSColor colorNamed: @"redColor" bundle: bundle] == nil, "redColor is not a catalog color");
        CHECK([NSColor colorNamed: @"FixtureRed" bundle: emptyBundle] == nil, "a bundle without a catalog has no colors");

        [fm removeItemAtPath: root error: NULL];
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSColor colorNamed: from an asset catalog");
    return 0;
}
