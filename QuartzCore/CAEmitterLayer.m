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

#import <QuartzCore/CAEmitterLayer.h>

#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSInvocation.h>

CAEmitterLayerEmitterShape const kCAEmitterLayerPoint = @"point";
CAEmitterLayerEmitterShape const kCAEmitterLayerLine = @"line";
CAEmitterLayerEmitterShape const kCAEmitterLayerRectangle = @"rectangle";
CAEmitterLayerEmitterShape const kCAEmitterLayerCuboid = @"cuboid";
CAEmitterLayerEmitterShape const kCAEmitterLayerCircle = @"circle";
CAEmitterLayerEmitterShape const kCAEmitterLayerSphere = @"sphere";

CAEmitterLayerEmitterMode const kCAEmitterLayerPoints = @"points";
CAEmitterLayerEmitterMode const kCAEmitterLayerOutline = @"outline";
CAEmitterLayerEmitterMode const kCAEmitterLayerSurface = @"surface";
CAEmitterLayerEmitterMode const kCAEmitterLayerVolume = @"volume";

CAEmitterLayerRenderMode const kCAEmitterLayerUnordered = @"unordered";
CAEmitterLayerRenderMode const kCAEmitterLayerOldestFirst = @"oldestFirst";
CAEmitterLayerRenderMode const kCAEmitterLayerOldestLast = @"oldestLast";
CAEmitterLayerRenderMode const kCAEmitterLayerBackToFront = @"backToFront";
CAEmitterLayerRenderMode const kCAEmitterLayerAdditive = @"additive";

@implementation CAEmitterLayer

NS_EXTRA_SYNTHESIZE_COPY(CAEmitterLayer, emitterCells, _emitterCells, NSArray<CAEmitterCell *> *, emitterCells, setEmitterCells:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, birthRate, _birthRate, float, birthRate, setBirthRate:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, lifetime, _lifetime, float, lifetime, setLifetime:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, emitterPosition, _emitterPosition, CGPoint, emitterPosition, setEmitterPosition:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, emitterZPosition, _emitterZPosition, CGFloat, emitterZPosition, setEmitterZPosition:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, emitterSize, _emitterSize, CGSize, emitterSize, setEmitterSize:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, emitterDepth, _emitterDepth, CGFloat, emitterDepth, setEmitterDepth:)
NS_EXTRA_SYNTHESIZE_COPY(CAEmitterLayer, emitterShape, _emitterShape, CAEmitterLayerEmitterShape, emitterShape, setEmitterShape:)
NS_EXTRA_SYNTHESIZE_COPY(CAEmitterLayer, emitterMode, _emitterMode, CAEmitterLayerEmitterMode, emitterMode, setEmitterMode:)
NS_EXTRA_SYNTHESIZE_COPY(CAEmitterLayer, renderMode, _renderMode, CAEmitterLayerRenderMode, renderMode, setRenderMode:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, preservesDepth, _preservesDepth, BOOL, preservesDepth, setPreservesDepth:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, velocity, _velocity, float, velocity, setVelocity:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, scale, _scale, float, scale, setScale:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, spin, _spin, float, spin, setSpin:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAEmitterLayer, seed, _seed, unsigned int, seed, setSeed:)

- (void) _setEmitterDefaults {
    NS_EXTRA(CAEmitterLayer, self)->_birthRate = 1;
    NS_EXTRA(CAEmitterLayer, self)->_lifetime = 1;
    NS_EXTRA(CAEmitterLayer, self)->_velocity = 1;
    NS_EXTRA(CAEmitterLayer, self)->_scale = 1;
    NS_EXTRA(CAEmitterLayer, self)->_spin = 1;
    NS_EXTRA(CAEmitterLayer, self)->_emitterShape = [kCAEmitterLayerPoint copy];
    NS_EXTRA(CAEmitterLayer, self)->_emitterMode = [kCAEmitterLayerVolume copy];
    NS_EXTRA(CAEmitterLayer, self)->_renderMode = [kCAEmitterLayerUnordered copy];
}

- init {
    self = [super init];
    if (self != nil)
        [self _setEmitterDefaults];
    return self;
}

- initWithLayer: (id) layer {
    self = [super initWithLayer: layer];
    if (self != nil)
        [self _setEmitterDefaults];
    return self;
}

- (void) dealloc {
    [NS_EXTRA(CAEmitterLayer, self)->_emitterCells release];
    [NS_EXTRA(CAEmitterLayer, self)->_emitterShape release];
    [NS_EXTRA(CAEmitterLayer, self)->_emitterMode release];
    [NS_EXTRA(CAEmitterLayer, self)->_renderMode release];
    [super dealloc];
}

@end
