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

@class NSImage;

@interface NSAssetCatalog : NSObject {
    NSDictionary *_colors; // name -> NSArray of NSAssetCatalogColor
    NSData *_data;
    // Built on the first image lookup: name -> identifier, identifier -> NSArray of renditions,
    // and the decoded packed images (rendition key -> NSData of RGBA pixels).
    NSDictionary *_identifiers;
    NSDictionary *_renditions;
    NSMutableDictionary *_packedImages;
}

// The catalog Assets.car in the bundle (the main bundle if nil), parsed once
// per file; nil if the bundle has none.
+ (NSAssetCatalog *) catalogForBundle: (NSBundle *) bundle;

// The stored values of the named color: at most one per appearance, the
// default appearance's first. nil if the catalog has no color of that name.
- (NSArray *) colorsNamed: (NSString *) name;

// A new image of the named image set: a bitmap representation for each scale
// (and the PDF when the set keeps its vector data). nil if the catalog has no
// image of that name or none of its renditions can be read.
- (NSImage *) imageNamed: (NSString *) name;

@end
