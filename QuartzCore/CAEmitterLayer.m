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

@synthesize emitterCells = _emitterCells;
@synthesize birthRate = _birthRate;
@synthesize lifetime = _lifetime;
@synthesize emitterPosition = _emitterPosition;
@synthesize emitterZPosition = _emitterZPosition;
@synthesize emitterSize = _emitterSize;
@synthesize emitterDepth = _emitterDepth;
@synthesize emitterShape = _emitterShape;
@synthesize emitterMode = _emitterMode;
@synthesize renderMode = _renderMode;
@synthesize preservesDepth = _preservesDepth;
@synthesize velocity = _velocity;
@synthesize scale = _scale;
@synthesize spin = _spin;
@synthesize seed = _seed;

- (void) dealloc {
    [_emitterCells release];
    [_emitterShape release];
    [_emitterMode release];
    [_renderMode release];
    [super dealloc];
}

@end
