// Copyright (C) 2026 Lubos Dolezel
//
// Images that a nib takes from the system symbols, and archived symbol
// configurations. Expected values are from black-box runs of this test on
// macOS 26.7.3 (x86_64); Mac OS X 10.14 has no system symbols.
//  - test_nib_symbol_images (with the path of fixtures/symbols/Symbols.nib,
//    compiled by ibtool from Symbols.xib): an image view naming the "folder"
//    system symbol and a button naming "eject.fill" with a small symbol scale get
//    template images of the size +imageWithSystemSymbolName: gives (with that
//    configuration applied, which the image reports); a plain image reference
//    (NSFolder) is still looked up by name. +imageNamed: of a symbol name is nil.
//  - test_configuration_coding: NSImageSymbolConfiguration supports secure
//    coding; it archives point size, weight and scale as NSPointSize,
//    NSFontWeight and NSSymbolScale and unarchives to an equal configuration.
//  - test_glyphs_differ: folder, network, plus.square and eject.fill draw
//    different images.
// Usage: appkit-nib-system-symbol-images [Symbols.nib]
// Build: clang -framework AppKit appkit-nib-system-symbol-images.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static BOOL sameSize(NSSize a, NSSize b) {
    return fabs(a.width - b.width) < 0.5 && fabs(a.height - b.height) < 0.5;
}

static NSImage *imageOfView(NSView *view) {
    if ([view isKindOfClass: [NSImageView class]])
        return [(NSImageView *) view image];
    if ([view isKindOfClass: [NSButton class]])
        return [(NSButton *) view image];
    return nil;
}

static void test_nib_symbol_images(const char *path) {
    NSNib *nib = [[NSNib alloc] initWithNibData: [NSData dataWithContentsOfFile: [NSString stringWithUTF8String: path]]
                                         bundle: nil];
    NSArray *objects = nil;
    CHECK([nib instantiateWithOwner: nil topLevelObjects: &objects]);
    NSImage *plain = nil, *configured = nil, *named = nil;
    for (id object in objects) {
        if (![object isKindOfClass: [NSView class]])
            continue;
        for (NSView *view in [object subviews]) {
            if ([[view identifier] isEqualToString: @"plain"]) plain = imageOfView(view);
            if ([[view identifier] isEqualToString: @"configured"]) configured = imageOfView(view);
            if ([[view identifier] isEqualToString: @"named"]) named = imageOfView(view);
        }
    }
    NSImage *folder = [NSImage imageWithSystemSymbolName: @"folder" accessibilityDescription: nil];
    NSImageSymbolConfiguration *small = [NSImageSymbolConfiguration configurationWithPointSize: 13 weight: 0
                                                                                        scale: NSImageSymbolScaleSmall];
    NSImage *eject = [[NSImage imageWithSystemSymbolName: @"eject.fill" accessibilityDescription: nil]
            imageWithSymbolConfiguration: small];
    CHECK(plain != nil && [plain isTemplate] && [[plain representations] count] > 0);
    CHECK(sameSize([plain size], [folder size]));
    CHECK(configured != nil && [configured isTemplate]);
    CHECK(sameSize([configured size], [eject size]));
    CHECK(!sameSize([configured size], [[NSImage imageWithSystemSymbolName: @"eject.fill" accessibilityDescription: nil] size]));
    CHECK([[configured symbolConfiguration] isEqual: small]);
    CHECK([[named name] isEqualToString: @"NSFolder"]);
    CHECK([NSImage imageNamed: @"folder"] == nil);
    CHECK([NSImage imageNamed: @"eject.fill"] == nil);
}

static void test_configuration_coding(void) {
    NSImageSymbolConfiguration *configuration =
            [NSImageSymbolConfiguration configurationWithPointSize: 13 weight: NSFontWeightBold
                                                             scale: NSImageSymbolScaleLarge];
    CHECK([NSImageSymbolConfiguration supportsSecureCoding]);
    CHECK([configuration conformsToProtocol: @protocol(NSSecureCoding)]);
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: configuration requiringSecureCoding: YES error: NULL];
    CHECK(data != nil);
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData: data options: 0 format: NULL error: NULL];
    NSDictionary *archived = [[plist objectForKey: @"$objects"] objectAtIndex: 1];
    CHECK(fabs([[archived objectForKey: @"NSPointSize"] doubleValue] - 13) < 0.001);
    CHECK(fabs([[archived objectForKey: @"NSFontWeight"] doubleValue] - NSFontWeightBold) < 0.001);
    CHECK([[archived objectForKey: @"NSSymbolScale"] integerValue] == NSImageSymbolScaleLarge);
    id back = [NSKeyedUnarchiver unarchivedObjectOfClass: [NSImageSymbolConfiguration class] fromData: data error: NULL];
    CHECK([back isEqual: configuration]);
}

// 32 x 32 RGBA pixels of the image drawn in black.
static NSData *render(NSImage *image) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 32 pixelsHigh: 32
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSCalibratedRGBColorSpace
            bytesPerRow: 32 * 4 bitsPerPixel: 32];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [image drawInRect: NSMakeRect(0, 0, 32, 32) fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1];
    [NSGraphicsContext restoreGraphicsState];
    NSData *data = [NSData dataWithBytes: [rep bitmapData] length: 32 * 32 * 4];
    [rep release];
    return data;
}

static int coverage(NSData *pixels) {
    const unsigned char *p = [pixels bytes];
    int n = 0;
    for (NSUInteger i = 3; i < [pixels length]; i += 4)
        n += p[i] > 64;
    return n;
}

static void test_glyphs_differ(void) {
    NSArray *names = [NSArray arrayWithObjects: @"folder", @"network", @"plus.square", @"eject.fill", nil];
    NSMutableArray *renders = [NSMutableArray array];
    for (NSString *name in names) {
        NSData *pixels = render([NSImage imageWithSystemSymbolName: name accessibilityDescription: nil]);
        CHECK(coverage(pixels) > 20);
        [renders addObject: pixels];
    }
    for (NSUInteger i = 0; i < [renders count]; i++)
        for (NSUInteger j = i + 1; j < [renders count]; j++)
            if ([[renders objectAtIndex: i] isEqual: [renders objectAtIndex: j]]) {
                fprintf(stderr, "FAIL: %s and %s draw the same\n", [[names objectAtIndex: i] UTF8String],
                        [[names objectAtIndex: j] UTF8String]);
                failures++;
            }
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    if (argc > 1)
        RUN(test_nib_symbol_images(argv[1]));
    RUN(test_configuration_coding());
    RUN(test_glyphs_differ());
    if (failures == 0)
        printf("PASS appkit-nib-system-symbol-images\n");
    [pool release];
    return failures != 0;
}
