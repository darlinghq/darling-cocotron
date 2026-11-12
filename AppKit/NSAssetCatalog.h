/*
 * Copyright (C) 2026 Darling Developers
 *
 * Private reader for compiled asset catalogs (Assets.car), shared by the AppKit
 * classes that load named assets from a bundle.
 */
#import <Foundation/Foundation.h>

// The color space a catalog color is stored in.
typedef NS_ENUM(NSUInteger, NSAssetCatalogColorSpace) {
    NSAssetCatalogColorSpaceSRGB = 1,
    NSAssetCatalogColorSpaceGrayGamma22 = 2,
    NSAssetCatalogColorSpaceDisplayP3 = 3,
};

// One stored value of a named color: the one for the default appearance, or
// the one for a dark appearance.
@interface NSAssetCatalogColor : NSObject {
@public
    NSAssetCatalogColorSpace colorSpace;
    BOOL dark;
    NSUInteger componentCount;
    double components[4];
}
@end

@interface NSAssetCatalog : NSObject {
    NSDictionary *_colors; // name -> NSArray of NSAssetCatalogColor
}

// The catalog Assets.car in the bundle (the main bundle if nil), parsed once
// per file; nil if the bundle has none.
+ (NSAssetCatalog *) catalogForBundle: (NSBundle *) bundle;

// The stored values of the named color: at most one per appearance, the
// default appearance's first. nil if the catalog has no color of that name.
- (NSArray *) colorsNamed: (NSString *) name;

@end
