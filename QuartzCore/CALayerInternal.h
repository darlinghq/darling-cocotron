/*
 * This file is part of Darling.
 *
 * Copyright (C) 2022 Darling developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <QuartzCore/CALayer.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CARenderer.h>

@class CAArchiveWriter, CAArchiveReader;

@interface CALayer (Internal)
- (CALayerContext *) _context;
- (void) _setContext: (CALayerContext *) context;
- (NSNumber *) _textureId;
- (void) _setTextureId: (NSNumber *) value;
// The contents object last uploaded to the layer's texture.
- (id) _textureContents;
- (void) _setTextureContents: (id) value;
// The seed of the IOSurface contents at their last upload.
- (uint32_t) _textureSeed;
- (void) _setTextureSeed: (uint32_t) value;
// For a layer whose content is not a CGImage (CAMetalLayer draws a texture the
// GPU filled in), draws the content into the current GL context. Called before
// the contents-based path, so a layer with a NULL contents is not skipped.
// Return YES if this drew the layer's content, which suppresses that path: it
// uploads into -_textureId, the very texture such a layer draws from.
- (BOOL) _drawLayerContents: (CGRect) bounds opacity: (CGFloat) opacity;
// What CARenderer draws as the layer's contents, and where. The default is
// -contents across the bounds; *rect comes in as (0, 0, bounds size), in the
// layer's own coordinates. A CALayerHost draws the hosted context's frame
// instead, at that frame's size.
- (id) _contentsForRendering: (CGRect *) rect;
// YES for a layer whose content is its own state (a path), which a delegate's
// -displayLayer: must not replace.
- (BOOL) _drawsOwnContent;
// Keyed archiving: subclasses call super, then write or read their own keys.
- (void) _encodeAttributes: (CAArchiveWriter *) writer;
- (void) _decodeAttributes: (CAArchiveReader *) reader;
@end

@interface CALayerContext (Internal)
// Draws the tree into the framebuffer bound to the current context, which is
// width x height pixels. With topRowFirst, the picture is drawn upside down,
// so that reading the framebuffer back from row 0 gives its top row first.
- (void) _drawLayerTree: (CALayer *) layer
                  width: (GLint) width
                 height: (GLint) height
            topRowFirst: (BOOL) topRowFirst;
@end

@interface CARenderer (Internal)
// Clear to transparent rather than opaque black before drawing, for frames
// that are composited again elsewhere.
- (void) _setClearsToTransparent: (BOOL) value;
@end
