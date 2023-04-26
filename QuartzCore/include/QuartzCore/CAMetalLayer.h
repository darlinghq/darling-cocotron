/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@protocol CAMetalDrawable;

@class CAEDRMetadata;

struct _CAMetalLayerPrivate;

@interface CAMetalLayer : CALayer

@property(retain) id<MTLDevice> device;
@property(readonly) id<MTLDevice> preferredDevice;
@property MTLPixelFormat pixelFormat;
@property CGColorSpaceRef colorspace;
@property BOOL framebufferOnly;
@property CGSize drawableSize;
@property BOOL presentsWithTransaction;
@property BOOL displaySyncEnabled;
@property BOOL wantsExtendedDynamicRangeContent;
@property(strong) CAEDRMetadata* EDRMetadata;
@property NSUInteger maximumDrawableCount;
@property BOOL allowsNextDrawableTimeout;
@property(copy) NSDictionary* developerHUDProperties;

- (id<CAMetalDrawable>)nextDrawable;

@end
