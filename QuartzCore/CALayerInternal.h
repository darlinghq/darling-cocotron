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
@end
