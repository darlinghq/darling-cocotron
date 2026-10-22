/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

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

typedef NSString* CAEmitterLayerEmitterShape NS_TYPED_ENUM;
typedef NSString* CAEmitterLayerEmitterMode NS_TYPED_ENUM;
typedef NSString* CAEmitterLayerRenderMode NS_TYPED_ENUM;

@class CAEmitterCell;

@interface CAEmitterLayer : CALayer {
    NSArray *_emitterCells;
    float _birthRate;
    float _lifetime;
    CGPoint _emitterPosition;
    CGFloat _emitterZPosition;
    CGSize _emitterSize;
    CGFloat _emitterDepth;
    CAEmitterLayerEmitterShape _emitterShape;
    CAEmitterLayerEmitterMode _emitterMode;
    CAEmitterLayerRenderMode _renderMode;
    BOOL _preservesDepth;
    float _velocity;
    float _scale;
    float _spin;
    unsigned int _seed;
}

@property (copy) NSArray<CAEmitterCell *> *emitterCells;
@property float birthRate;
@property float lifetime;
@property CGPoint emitterPosition;
@property CGFloat emitterZPosition;
@property CGSize emitterSize;
@property CGFloat emitterDepth;
@property (copy) CAEmitterLayerEmitterShape emitterShape;
@property (copy) CAEmitterLayerEmitterMode emitterMode;
@property (copy) CAEmitterLayerRenderMode renderMode;
@property BOOL preservesDepth;
@property float velocity;
@property float scale;
@property float spin;
@property unsigned int seed;

@end

CA_EXPORT CAEmitterLayerEmitterShape const kCAEmitterLayerPoint;
CA_EXPORT CAEmitterLayerEmitterShape const kCAEmitterLayerLine;
CA_EXPORT CAEmitterLayerEmitterShape const kCAEmitterLayerRectangle;
CA_EXPORT CAEmitterLayerEmitterShape const kCAEmitterLayerCuboid;
CA_EXPORT CAEmitterLayerEmitterShape const kCAEmitterLayerCircle;
CA_EXPORT CAEmitterLayerEmitterShape const kCAEmitterLayerSphere;

CA_EXPORT CAEmitterLayerEmitterMode const kCAEmitterLayerPoints;
CA_EXPORT CAEmitterLayerEmitterMode const kCAEmitterLayerOutline;
CA_EXPORT CAEmitterLayerEmitterMode const kCAEmitterLayerSurface;
CA_EXPORT CAEmitterLayerEmitterMode const kCAEmitterLayerVolume;

CA_EXPORT CAEmitterLayerRenderMode const kCAEmitterLayerUnordered;
CA_EXPORT CAEmitterLayerRenderMode const kCAEmitterLayerOldestFirst;
CA_EXPORT CAEmitterLayerRenderMode const kCAEmitterLayerOldestLast;
CA_EXPORT CAEmitterLayerRenderMode const kCAEmitterLayerBackToFront;
CA_EXPORT CAEmitterLayerRenderMode const kCAEmitterLayerAdditive;
