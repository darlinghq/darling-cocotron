/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <QuartzCore/CALayer.h>

// A layer for very large content. The tile size and level of detail
// properties are stored, copied by -initWithLayer: and archived, but the layer
// does not split its drawing into tiles: -drawInContext: receives the whole layer.
@interface CATiledLayer : CALayer {
    CGSize _tileSize;
    size_t _levelsOfDetail;
    size_t _levelsOfDetailBias;
}

// Seconds a newly drawn tile takes to fade in; 0.25.
+ (CFTimeInterval) fadeDuration;

@property CGSize tileSize;                // default 256 x 256
@property size_t levelsOfDetail;          // default 1
@property size_t levelsOfDetailBias;      // default 0

@end
