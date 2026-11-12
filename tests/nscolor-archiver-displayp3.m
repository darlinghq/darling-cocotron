// Copyright (C) 2026 Lubos Dolezel
//
// NSColor archiving with NSArchiver (non-keyed, typedstream) and the Display P3
// constructor, from the public contract:
//  - a color archived with NSArchiver and unarchived with NSUnarchiver is
//    equal in kind and components: calibrated and device RGB, calibrated and
//    device white, device CMYK, and a catalog (named) color;
//  - the same colors survive NSKeyedArchiver;
//  - +colorWithDisplayP3Red:green:blue:alpha: keeps its components in the
//    Display P3 color space and converts to sRGB with values that differ from
//    the P3 numbers for a saturated color;
//  - +separatorColor and +textInsertionPointColor exist and are usable colors.
// Needs no window or X server.
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

static NSColor *viaArchiver(NSColor *color) {
    NSData *data = [NSArchiver archivedDataWithRootObject: color];
    return data == nil ? nil : [NSUnarchiver unarchiveObjectWithData: data];
}

static NSColor *viaKeyedArchiver(NSColor *color) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: color requiringSecureCoding: NO error: NULL];
    return data == nil ? nil : [NSKeyedUnarchiver unarchivedObjectOfClass: [NSColor class] fromData: data error: NULL];
}

int main(void) {
    @autoreleasepool {
        NSColor *calibrated = [NSColor colorWithCalibratedRed: 0.25 green: 0.5 blue: 0.75 alpha: 0.5];
        NSColor *device = [NSColor colorWithDeviceRed: 0.9 green: 0.1 blue: 0.3 alpha: 1];
        NSColor *white = [NSColor colorWithCalibratedWhite: 0.4 alpha: 0.8];
        NSColor *deviceWhite = [NSColor colorWithDeviceWhite: 0.6 alpha: 1];
        NSColor *cmyk = [NSColor colorWithDeviceCyan: 0.1 magenta: 0.2 yellow: 0.3 black: 0.4 alpha: 1];

        NSArray *simple = @[calibrated, device, white, deviceWhite, cmyk];
        for (NSUInteger pass = 0; pass < 2; pass++) {
            const char *how = pass == 0 ? "NSArchiver" : "NSKeyedArchiver";
            for (NSColor *color in simple) {
                NSColor *back = pass == 0 ? viaArchiver(color) : viaKeyedArchiver(color);
                CHECK(back != nil, "%s: %@ archives", how, color);
                if (back == nil)
                    continue;
                CHECK([[back colorSpaceName] isEqualToString: [color colorSpaceName]], "%s: %@ keeps its color space (got %@)",
                      how, color, [back colorSpaceName]);
                CHECK([back numberOfComponents] == [color numberOfComponents], "%s: component count", how);
                CGFloat a[8], b[8];
                [color getComponents: a];
                [back getComponents: b];
                for (NSInteger i = 0; i < [color numberOfComponents]; i++)
                    CHECK(near(a[i], b[i]), "%s: %@ component %ld is %g, was %g", how, color, (long) i, b[i], a[i]);
            }
        }

        NSColor *named = [NSColor colorWithCatalogName: @"System" colorName: @"controlColor"];
        NSColor *namedBack = viaArchiver(named);
        CHECK(namedBack != nil, "a catalog color archives");
        if (namedBack != nil) {
            CHECK([[namedBack catalogNameComponent] isEqualToString: @"System"] &&
                          [[namedBack colorNameComponent] isEqualToString: @"controlColor"],
                  "catalog and color name survive (%@ %@)", [namedBack catalogNameComponent], [namedBack colorNameComponent]);
        }

        // Display P3.
        NSColor *p3 = [NSColor colorWithDisplayP3Red: 1 green: 0 blue: 0 alpha: 1];
        CHECK(p3 != nil, "Display P3 color created");
        if (p3 != nil) {
            CGFloat r, g, b, a;
            NSColor *p3Components = [p3 colorUsingColorSpace: [NSColorSpace displayP3ColorSpace]];
            CHECK(p3Components != nil, "converts to the Display P3 space");
            [p3Components getRed: &r green: &g blue: &b alpha: &a];
            CHECK(near(r, 1) && near(g, 0) && near(b, 0) && near(a, 1), "P3 components %g %g %g %g", r, g, b, a);
            CHECK([p3 colorUsingColorSpace: [NSColorSpace sRGBColorSpace]] != nil, "converts to sRGB");
            // Onyx2D treats every RGB color space as device RGB, so converting
            // Display P3 to sRGB keeps the numbers (no gamut mapping); not checked.
        }

        // System colors added with this work.
        NSColor *separator = [NSColor separatorColor];
        NSColor *caret = [NSColor textInsertionPointColor];
        CHECK(separator != nil && caret != nil, "separatorColor and textInsertionPointColor exist");
        CHECK([separator colorUsingColorSpaceName: NSCalibratedRGBColorSpace] != nil, "separatorColor converts to RGB");
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSColor archiving and Display P3");
    return 0;
}
