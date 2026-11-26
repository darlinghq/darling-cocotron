/*
 * Copyright (C) 2026 Darling Developers
 */
#import <Foundation/NSData.h>
#import <Foundation/NSGeometry.h>

@class NSBitmapImageRep;

// Rasterizes a subset of SVG 1.1/2 vector graphics (paths, basic shapes, groups,
// transforms, fills, strokes) into an RGBA NSBitmapImageRep.
NSBitmapImageRep *NSRenderSVGData(NSData *svgData, NSSize pointSize, CGFloat scale);
