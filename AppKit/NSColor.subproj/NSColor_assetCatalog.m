/*
 * Copyright (C) 2026 Darling Developers
 */
#import "NSAssetCatalog.h"
#import <AppKit/NSAppearance.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColor_catalog.h>
#import <AppKit/NSColorSpace.h>

@interface NSColor (NSAssetCatalog)
+ (NSColor *) _colorNamedInAssetCatalog: (NSString *) name bundle: (NSBundle *) bundle;
@end

static NSColor *colorFromCatalogValue(NSAssetCatalogColor *value) {
    double *c = value->components;

    switch (value->colorSpace) {
    case NSAssetCatalogColorSpaceDisplayP3:
        return [NSColor colorWithDisplayP3Red: c[0] green: c[1] blue: c[2] alpha: c[3]];
    case NSAssetCatalogColorSpaceGrayGamma22:
        // Calibrated spaces: AppKit's color conversions don't handle the space +colorWithSRGBRed: tags colors with.
        return [NSColor colorWithCalibratedWhite: c[0] alpha: c[1]];
    default:
        return [NSColor colorWithCalibratedRed: c[0] green: c[1] blue: c[2] alpha: c[3]];
    }
}

@implementation NSColor (NSAssetCatalog)

// A color with one stored value is a catalog color of the bundle; one with default and dark values follows
// the appearance it is used with.
+ (NSColor *) _colorNamedInAssetCatalog: (NSString *) name bundle: (NSBundle *) bundle {
    NSArray *values = [[NSAssetCatalog catalogForBundle: bundle] colorsNamed: name];
    if ([values count] == 0)
        return nil;

    NSColor *normal = colorFromCatalogValue([values objectAtIndex: 0]);
    if ([values count] > 1) {
        NSColor *dark = colorFromCatalogValue([values objectAtIndex: 1]);
        return [NSColor colorWithName: name
                      dynamicProvider: ^NSColor *(NSAppearance *appearance) {
                          NSAppearanceName best = [appearance bestMatchFromAppearancesWithNames:
                                  [NSArray arrayWithObjects: NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]];
                          return [best isEqualToString: NSAppearanceNameDarkAqua] ? dark : normal;
                      }];
    }

    NSString *identifier = [(bundle ? bundle : [NSBundle mainBundle]) bundleIdentifier];
    NSString *catalogName = [@"$assets-" stringByAppendingString: identifier ? identifier : @""];
    return [NSColor_catalog colorWithCatalogName: catalogName colorName: name color: normal];
}

@end
