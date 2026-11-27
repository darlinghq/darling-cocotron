/*
 * Copyright (C) 2026 Darling Developers
 */
#import <Foundation/NSData.h>
#import <Foundation/NSGeometry.h>

@class NSBitmapImageRep;

// Rasterizes a subset of SVG 1.1/2 vector graphics (paths, basic shapes, groups,
// transforms, fills, strokes) into an RGBA NSBitmapImageRep. Internal helper of the asset catalog and
// symbol glyph code: not exported from AppKit.
__attribute__((visibility("hidden")))
NSBitmapImageRep *NSRenderSVGData(NSData *svgData, NSSize pointSize, CGFloat scale);
