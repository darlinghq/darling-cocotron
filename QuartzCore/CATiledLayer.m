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

#import <QuartzCore/CATiledLayer.h>
#import "CAKeyedCoding.h"
#import "CALayerInternal.h"

// Defaults observed on macOS 26.7.3: tile size 256 x 256, levelsOfDetail 1,
// levelsOfDetailBias 0, +fadeDuration 0.25, superclass CALayer. The archive
// carries the keys tileSize, levelsOfDetail and levelsOfDetailBias.
@implementation CATiledLayer

+ (CFTimeInterval) fadeDuration {
    return 0.25;
}

- (void) _setTiledDefaults {
    _tileSize = CGSizeMake(256, 256);
    _levelsOfDetail = 1;
    _levelsOfDetailBias = 0;
}

- init {
    self = [super init];
    if (self != nil)
        [self _setTiledDefaults];
    return self;
}

- initWithLayer: (id) layer {
    self = [super initWithLayer: layer];
    if (self != nil) {
        [self _setTiledDefaults];
        if ([layer isKindOfClass: [CATiledLayer class]]) {
            CATiledLayer *other = layer;
            _tileSize = other->_tileSize;
            _levelsOfDetail = other->_levelsOfDetail;
            _levelsOfDetailBias = other->_levelsOfDetailBias;
        }
    }
    return self;
}

- (void) _encodeAttributes: (CAArchiveWriter *) w {
    [super _encodeAttributes: w];
    if (_tileSize.width != 256 || _tileSize.height != 256)
        [w encodeSize: _tileSize forKey: @"tileSize"];
    if (_levelsOfDetail != 1)
        [w encodeInt: (int) _levelsOfDetail forKey: @"levelsOfDetail"];
    if (_levelsOfDetailBias != 0)
        [w encodeInt: (int) _levelsOfDetailBias forKey: @"levelsOfDetailBias"];
}

- (void) _decodeAttributes: (CAArchiveReader *) r {
    [self _setTiledDefaults];
    [super _decodeAttributes: r];
    CGSize size;
    int value;
    if ([r decodeSize: &size forKey: @"tileSize"])
        _tileSize = size;
    if ([r decodeInt: &value forKey: @"levelsOfDetail"] && value >= 0)
        _levelsOfDetail = value;
    if ([r decodeInt: &value forKey: @"levelsOfDetailBias"] && value >= 0)
        _levelsOfDetailBias = value;
}

- (CGSize) tileSize {
    return _tileSize;
}

- (void) setTileSize: (CGSize) size {
    _tileSize = size;
    [self setNeedsDisplay];
}

- (size_t) levelsOfDetail {
    return _levelsOfDetail;
}

- (void) setLevelsOfDetail: (size_t) value {
    _levelsOfDetail = value;
    [self setNeedsDisplay];
}

- (size_t) levelsOfDetailBias {
    return _levelsOfDetailBias;
}

- (void) setLevelsOfDetailBias: (size_t) value {
    _levelsOfDetailBias = value;
    [self setNeedsDisplay];
}

@end
