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

#import <QuartzCore/CAMetalLayer.h>

#import <OpenGL/gl.h>

#include <memory>
#include <array>

class CAMetalDrawableActual;

@interface CAMetalLayerInternal : CAMetalLayer {
	id<MTLDevice> _device;
	MTLPixelFormat _pixelFormat;
	CGColorSpaceRef _colorspace;
	BOOL _framebufferOnly;
	CGSize _drawableSize;
	BOOL _presentsWithTransaction;
	BOOL _displaySyncEnabled;
	BOOL _wantsExtendedDynamicRangeContent;
	CAEDRMetadata* _EDRMetadata;
	NSUInteger _maximumDrawableCount;
	BOOL _allowsNextDrawableTimeout;
	NSDictionary* _developerHUDProperties;

	std::array<std::shared_ptr<CAMetalDrawableActual>, 3> _drawables;
	std::array<NSUInteger, 3> _queuedDrawables;
	NSUInteger _queuedDrawableCount;
	uint8_t _usableDrawablesBitmap;
	NSCondition* _drawableCondition;
	std::shared_ptr<CAMetalDrawableActual> _lastPresentedDrawable;

	GLuint _tex;
}

- (void)queuePresent: (NSUInteger)drawableID;
- (void)releaseDrawable: (NSUInteger)drawableID;

- (void)prepareRender;

@end
