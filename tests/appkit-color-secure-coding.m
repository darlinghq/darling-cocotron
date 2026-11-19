// Copyright (C) 2026 Lubos Dolezel
//
// NSColor adopts NSSecureCoding (macOS 10.x onwards), so colors go through
// +[NSKeyedArchiver archivedDataWithRootObject:requiringSecureCoding:error:]
// and +[NSKeyedUnarchiver unarchivedObjectOfClass:fromData:error:]:
//  - NSColor conforms to NSSecureCoding and +supportsSecureCoding is YES;
//  - a component color and a catalog (system) color round-trip with secure
//    coding, the catalog color keeping its list and color names;
//  - a color made with +colorWithName:dynamicProvider: archives (macOS 10.15+):
//    it comes back as a catalog color of the list "#$customDynamic", named
//    after the color or, without a name, with some non-empty name, and it
//    stands for the color the provider gave when it was archived;
//  - an object that does not adopt NSSecureCoding still fails, with
//    NSCoderInvalidValueError (4866) over NSCoderReadCorruptError (4864).
// Passes on macOS 26.7.3 (x86_64) and 10.14.4 (i386, without the
// dynamic-provider part).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); failures++; } } while (0)

@interface PlainCoding : NSObject <NSCoding>
@end

@implementation PlainCoding
- (void) encodeWithCoder: (NSCoder *) coder {}
- (id) initWithCoder: (NSCoder *) coder { return [super init]; }
@end

static NSColor *roundTrip(NSColor *color) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: color requiringSecureCoding: YES error: &error];
    if (data == nil) {
        printf("archiving %s failed: %s\n", [[color description] UTF8String], [[error description] UTF8String]);
        return nil;
    }
    NSColor *back = [NSKeyedUnarchiver unarchivedObjectOfClass: [NSColor class] fromData: data error: &error];
    if (back == nil)
        printf("unarchiving %s failed: %s\n", [[color description] UTF8String], [[error description] UTF8String]);
    return back;
}

static BOOL sameRGB(NSColor *a, NSColor *b) {
    NSColor *x = [a colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    NSColor *y = [b colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    if (x == nil || y == nil)
        return NO;
    return fabs([x redComponent] - [y redComponent]) < 0.01 && fabs([x greenComponent] - [y greenComponent]) < 0.01 &&
           fabs([x blueComponent] - [y blueComponent]) < 0.01 && fabs([x alphaComponent] - [y alphaComponent]) < 0.01;
}

int main(void) {
    @autoreleasepool {
        CHECK([NSColor conformsToProtocol: @protocol(NSSecureCoding)]);
        CHECK([NSColor supportsSecureCoding]);

        NSColor *rgb = [NSColor colorWithCalibratedRed: 0.1 green: 0.2 blue: 0.3 alpha: 0.4];
        NSColor *back = roundTrip(rgb);
        CHECK(back != nil && sameRGB(back, rgb));

        NSColor *catalog = [NSColor controlTextColor];
        back = roundTrip(catalog);
        CHECK(back != nil && [back type] == NSColorTypeCatalog);
        CHECK([[back catalogNameComponent] isEqualToString: [catalog catalogNameComponent]]);
        CHECK([[back colorNameComponent] isEqualToString: @"controlTextColor"]);

        if ([NSColor respondsToSelector: @selector(colorWithName:dynamicProvider:)]) {
            NSColor *red = [NSColor colorWithSRGBRed: 1 green: 0 blue: 0 alpha: 1];
            NSColor *dynamic = [NSColor colorWithName: @"testDynamic" dynamicProvider: ^NSColor *(NSAppearance *appearance) {
                return red;
            }];
            back = roundTrip(dynamic);
            CHECK(back != nil && [back type] == NSColorTypeCatalog);
            CHECK([[back catalogNameComponent] isEqualToString: @"#$customDynamic"]);
            CHECK([[back colorNameComponent] isEqualToString: @"testDynamic"]);
            CHECK(back != nil && sameRGB(back, red));

            NSColor *unnamed = [NSColor colorWithName: nil dynamicProvider: ^NSColor *(NSAppearance *appearance) {
                return red;
            }];
            back = roundTrip(unnamed);
            CHECK(back != nil && [[back colorNameComponent] length] > 0);
            CHECK(back != nil && sameRGB(back, red));
        } else {
            printf("no +colorWithName:dynamicProvider:, skipping that part\n");
        }

        // Still refused: a class that does not adopt NSSecureCoding
        NSError *error = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: [[PlainCoding new] autorelease] requiringSecureCoding: YES error: &error];
        CHECK(data == nil);
        CHECK([[error domain] isEqualToString: @"NSCocoaErrorDomain"] && [error code] == 4866);
        CHECK([[[error userInfo] objectForKey: @"NSUnderlyingError"] code] == 4864);
    }

    if (failures)
        printf("FAIL: %d check(s) failed\n", failures);
    else
        printf("PASS\n");
    return failures ? 1 : 0;
}
