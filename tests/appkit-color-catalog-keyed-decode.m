// Copyright (C) 2026 Lubos Dolezel
//
// Contract: a catalog color (named color) read from a keyed archive stands
// for the named color of the named list as the running system defines it;
// the color value archived next to the names is only a fallback for names the
// system does not know. A color the nib compiler saved for another
// appearance or version of the system must therefore not replace the live
// system color. Prints PASS or FAIL.
#import <AppKit/AppKit.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static id uid(int n) { return @{@"CF$UID": @(n)}; }

// A catalog color archived with the given names and a gray fallback.
static NSColor *decodeCatalogColor(NSString *list, NSString *name, double fallbackWhite) {
    NSString *white = [NSString stringWithFormat:@"%g 1", fallbackWhite];
    NSMutableData *whiteData = [[white dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [whiteData appendBytes:"\0" length:1];
    NSDictionary *archive = @{
        @"$archiver": @"NSKeyedArchiver", @"$version": @100000,
        @"$top": @{@"root": uid(1)},
        @"$objects": @[
            @"$null",
            @{@"$class": uid(5), @"NSColorSpace": @6, @"NSCatalogName": uid(2), @"NSColorName": uid(3), @"NSColor": uid(4)},
            list, name,
            @{@"$class": uid(5), @"NSColorSpace": @3, @"NSWhite": whiteData},
            @{@"$classname": @"NSColor", @"$classes": @[@"NSColor", @"NSObject"]},
        ],
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:archive format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

static double gray(NSColor *c) {
    NSColor *g = [c colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    return [g redComponent];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // A name the system defines: the live color wins over the archived value.
        NSColor *live = [NSColor controlBackgroundColor];
        NSColor *c = decodeCatalogColor(@"System", @"controlBackgroundColor", 0.3);
        CHECK(c != nil, "color not decoded");
        CHECK([[c catalogNameComponent] isEqual:@"System"] && [[c colorNameComponent] isEqual:@"controlBackgroundColor"], "names not kept");
        CHECK(fabs(gray(c) - gray(live)) < 0.01, "decoded %g, live system color %g (archived fallback 0.3 used)", gray(c), gray(live));

        NSColor *c2 = decodeCatalogColor(@"System", @"textBackgroundColor", 0.3);
        CHECK(fabs(gray(c2) - gray([NSColor textBackgroundColor])) < 0.01, "textBackgroundColor: decoded %g, live %g", gray(c2), gray([NSColor textBackgroundColor]));

        // Decoding does not change what the system color is afterwards.
        CHECK(fabs(gray([NSColor controlBackgroundColor]) - gray(live)) < 0.01, "system color changed by decoding");

        // Names the system does not know keep the archived value.
        NSColor *u = decodeCatalogColor(@"System", @"vdNoSuchColor", 0.3);
        CHECK(u != nil && fabs(gray(u) - 0.3) < 0.02, "unknown name: got %g, want the archived 0.3", u ? gray(u) : -1);
        NSColor *l = decodeCatalogColor(@"VDNoSuchList", @"controlBackgroundColor", 0.3);
        CHECK(l != nil && fabs(gray(l) - 0.3) < 0.02, "unknown list: got %g, want the archived 0.3", l ? gray(l) : -1);

        // Decoding an unknown name leaves it out of the catalog.
        CHECK([[NSColorList colorListNamed:@"System"] colorWithKey:@"vdNoSuchColor"] == nil, "archived color was registered in the System list");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
