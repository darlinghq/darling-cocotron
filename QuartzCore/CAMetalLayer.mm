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

#define GL_GLEXT_PROTOTYPES 1
#import "CAMetalLayerInternal.h"
#import "CAMetalDrawableInternal.h"
#import <Foundation/NSRaise.h>
#import <Metal/MTLDeviceInternal.h>
#import <QuartzCore/CALayerContext.h>
#import <Metal/stubs.h>

#include <algorithm>

#import "CALayerInternal.h"

static void reportGLErrors(void) {
#if 0
	GLenum err;

	while ((err = glGetError()) != GL_NO_ERROR) {
		printf("*** OPENGL ERROR: %d ***\n", err);
	}
#endif
};

@implementation CAMetalLayer

#if DARLING_METAL_ENABLED
// FIXME: this breaks inheritance from CAMetalLayer.
//        the problem is that we need some C++ ivars, but we can't put those in the public header
//        and this code needs to compile on 32-bit (so it can't use non-fragile ivars).
//        maybe we could keep the troublesome ivars in an associated object...
//
//        then again, maybe we could get away with stubbing the entire class when compiling for 32-bit
//        since Metal is unavailable for 32-bit code.
+ (instancetype)allocWithZone: (NSZone*)zone
{
	if (self == [CAMetalLayer class]) {
		return [CAMetalLayerInternal allocWithZone: zone];
	} else {
		return [super allocWithZone: zone];
	}
}
#endif

- (id<MTLDevice>)device
{
	NSInvalidAbstractInvocation();
	return nil;
}

- (void)setDevice: (id<MTLDevice>)device
{
	NSInvalidAbstractInvocation();
}

- (id<MTLDevice>)preferredDevice
{
	NSInvalidAbstractInvocation();
	return nil;
}

- (MTLPixelFormat)pixelFormat
{
	NSInvalidAbstractInvocation();
	return MTLPixelFormatInvalid;
}

- (void)setPixelFormat: (MTLPixelFormat)pixelFormat
{
	NSInvalidAbstractInvocation();
}

- (CGColorSpaceRef)colorspace
{
	NSInvalidAbstractInvocation();
	return NULL;
}

- (void)setColorspace: (CGColorSpaceRef)colorspace
{
	NSInvalidAbstractInvocation();
}

- (BOOL)framebufferOnly
{
	NSInvalidAbstractInvocation();
	return YES;
}

- (void)setFramebufferOnly: (BOOL)framebufferOnly
{
	NSInvalidAbstractInvocation();
}

- (CGSize)drawableSize
{
	NSInvalidAbstractInvocation();
	return CGSizeZero;
}

- (void)setDrawableSize: (CGSize)drawableSize
{
	NSInvalidAbstractInvocation();
}

- (BOOL)presentsWithTransaction
{
	NSInvalidAbstractInvocation();
	return NO;
}

- (void)setPresentsWithTransaction: (BOOL)presentsWithTransaction
{
	NSInvalidAbstractInvocation();
}

- (BOOL)displaySyncEnabled
{
	NSInvalidAbstractInvocation();
	return NO;
}

- (void)setDisplaySyncEnabled: (BOOL)displaySyncEnabled
{
	NSInvalidAbstractInvocation();
}

- (BOOL)wantsExtendedDynamicRangeContent
{
	NSInvalidAbstractInvocation();
	return NO;
}

- (void)setWantsExtendedDynamicRangeContent: (BOOL)wantsExtendedDynamicRangeContent
{
	NSInvalidAbstractInvocation();
}

- (CAEDRMetadata*)EDRMetadata
{
	NSInvalidAbstractInvocation();
	return nil;
}

- (void)setEDRMetadata: (CAEDRMetadata*)EDRMetadata
{
	NSInvalidAbstractInvocation();
}

- (NSUInteger)maximumDrawableCount
{
	NSInvalidAbstractInvocation();
	return 0;
}

- (void)setMaximumDrawableCount: (NSUInteger)maximumDrawableCount
{
	NSInvalidAbstractInvocation();
}

- (BOOL)allowsNextDrawableTimeout
{
	NSInvalidAbstractInvocation();
	return NO;
}

- (void)setAllowsNextDrawableTimeout: (BOOL)allowsNextDrawableTimeout
{
	NSInvalidAbstractInvocation();
}

- (NSDictionary*)developerHUDProperties
{
	NSInvalidAbstractInvocation();
	return nil;
}

- (void)setDeveloperHUDProperties: (NSDictionary*)developerHUDProperties
{
	NSInvalidAbstractInvocation();
}

- (id<CAMetalDrawable>)nextDrawable
{
	NSInvalidAbstractInvocation();
	return nil;
}

@end

@implementation CAMetalLayerInternal

#if DARLING_METAL_ENABLED

@synthesize presentsWithTransaction = _presentsWithTransaction;
@synthesize displaySyncEnabled = _displaySyncEnabled;
@synthesize wantsExtendedDynamicRangeContent = _wantsExtendedDynamicRangeContent;
@synthesize EDRMetadata = _EDRMetadata;
@synthesize allowsNextDrawableTimeout = _allowsNextDrawableTimeout;
@synthesize developerHUDProperties = _developerHUDProperties;

// TODO: use CGL here instead of direct OpenGL calls
//       (once we CGL-ify the rest of QuartzCore)

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_pixelFormat = MTLPixelFormatBGRA8Unorm;
		_framebufferOnly = YES;
		_drawableSize = _bounds.size; // TODO: multiply by contentsScale, once we add that to CALayer
		_displaySyncEnabled = YES;
		_maximumDrawableCount = 3;
		_allowsNextDrawableTimeout = YES;
		_developerHUDProperties = [NSDictionary new];

		_drawableCondition = [NSCondition new];
	}
	return self;
}

- (void)dealloc
{
	[_device release];
	if (_colorspace) {
		CGColorSpaceRelease(_colorspace);
	}
	[_EDRMetadata release];
	[_developerHUDProperties release];
	[_drawableCondition release];

	reportGLErrors();
	if (_tex != 0) {
		glDeleteTextures(1, &_tex);
		reportGLErrors();
	}

	[super dealloc];
}

//
// properties
//

- (id<MTLDevice>)device
{
	return [[_device retain] autorelease];
}

- (void)setDevice: (id<MTLDevice>)device
{
	id<MTLDevice> old = _device;
	_device = [device retain];
	[old release];
	[self recreateDrawables];
}

- (id<MTLDevice>)preferredDevice
{
	return [MTLCreateSystemDefaultDevice() autorelease];
}

- (MTLPixelFormat)pixelFormat
{
	return _pixelFormat;
}

- (void)setPixelFormat: (MTLPixelFormat)pixelFormat
{
	_pixelFormat = pixelFormat;
	[self recreateDrawables];
}

- (CGColorSpaceRef)colorspace
{
	// TODO: retain and autorelease this? it's technically an objc object
	return _colorspace;
}

- (void)setColorspace: (CGColorSpaceRef)colorspace
{
	CGColorSpaceRef old = _colorspace;
	_colorspace = CGColorSpaceRetain(colorspace);
	if (old) {
		CGColorSpaceRelease(old);
	}
}

- (BOOL)framebufferOnly
{
	return _framebufferOnly;
}

- (void)setFramebufferOnly: (BOOL)framebufferOnly
{
	_framebufferOnly = framebufferOnly;
	[self recreateDrawables];
}

- (CGSize)drawableSize
{
	return _drawableSize;
}

- (void)setDrawableSize: (CGSize)drawableSize
{
	_drawableSize = drawableSize;
	[self recreateDrawables];
}

- (NSUInteger)maximumDrawableCount
{
	return _maximumDrawableCount;
}

- (void)setMaximumDrawableCount: (NSUInteger)maximumDrawableCount
{
	if (maximumDrawableCount < 2 || maximumDrawableCount > 3) {
		@throw [NSException exceptionWithName: NSInvalidArgumentException reason: @"Attempt to set maximumDrawableCount to an invalid value" userInfo: nil];
	}
	_maximumDrawableCount = maximumDrawableCount;
	[self recreateDrawables];
}

//
// overridden properties
//

// it appears that the drawable size does NOT change after initially being set
#if 0
- (void)setBounds: (CGRect)value
{
	[super setBounds: value];

	CGSize drawableSize = value.size;
	// TODO: multiply by contentsScale (CALayer doesn't currently have that property)

	[self setDrawableSize: drawableSize];
}
#endif

//
// methods
//

- (id<CAMetalDrawable>)nextDrawable
{
	std::shared_ptr<CAMetalDrawableActual> drawable = nullptr;

	[_drawableCondition lock];

	NSDate* endTime = [NSDate dateWithTimeIntervalSinceNow: 1];

	while (_usableDrawablesBitmap == 0) {
		if (_allowsNextDrawableTimeout) {
			if (![_drawableCondition waitUntilDate: endTime]) {
				break;
			}
		} else {
			[_drawableCondition wait];
		}
	}

	if (_usableDrawablesBitmap == 0) {
		// timeout reached
		[_drawableCondition unlock];
		return nil;
	}

	uint8_t drawableID = UINT8_MAX;

	for (uint8_t i = 0; i < _maximumDrawableCount; ++i) {
		if (_usableDrawablesBitmap & (1u << i)) {
			drawableID = i;
			break;
		}
	}

	if (drawableID == UINT8_MAX) {
		// shouldn't happen, but just in case
		[_drawableCondition unlock];
		return nil;
	}

	_usableDrawablesBitmap &= ~(1u << drawableID);

	drawable = _drawables[drawableID];

	[_drawableCondition unlock];

	return [[[CAMetalDrawableInternal alloc] initWithLayer: self drawable: drawable] autorelease];
}

- (void)queuePresent: (NSUInteger)drawableID
{
	[_drawableCondition lock];
	_queuedDrawables[_queuedDrawableCount] = drawableID;
	++_queuedDrawableCount;
	[_drawableCondition unlock];

	// we now need to schedule a render
	//
	// FIXME: once we fix up CALayer and make it more featureful, this needs to change to `self.needsDisplay = YES` or equivalently `[self setNeedsDisplay: YES]`
	// right now, CALayer is missing all the needs-display logic (which is currently in NSView)
	[self display];
}

- (void)releaseDrawable: (NSUInteger)drawableID
{
	[_drawableCondition lock];
	_usableDrawablesBitmap |= 1u << drawableID;
	[_drawableCondition signal];
	[_drawableCondition unlock];
}

- (void)recreateDrawables
{
	[_drawableCondition lock];

	// drop all queued presentations
	for (NSUInteger i = 0; i < _queuedDrawableCount; ++i) {
		auto& drawable = _drawables[_queuedDrawables[i]];

		// disown it first so it doesn't try to release itself
		// (and end up deadlocking in `releaseDrawable:`)
		drawable->disown();

		drawable->didDrop();
	}
	_queuedDrawableCount = 0;

	// clear the drawable array (and disown them so they don't try to queue with us anymore)
	for (auto& drawable: _drawables) {
		if (drawable) {
			drawable->disown();
		}
		drawable = nullptr;
	}
	_usableDrawablesBitmap = 0;

	if (!_device || !_context || _drawableSize.width == 0 || _drawableSize.height == 0) {
		// can't create new drawables
		[_drawableCondition unlock];
		return;
	}

	Indium::PixelFormat pixelFormat;

	switch (_pixelFormat) {
		case MTLPixelFormatBGRA8Unorm:      pixelFormat = Indium::PixelFormat::BGRA8Unorm;      break;
		case MTLPixelFormatBGRA8Unorm_sRGB: pixelFormat = Indium::PixelFormat::BGRA8Unorm_sRGB; break;
		case MTLPixelFormatRGBA16Float:     pixelFormat = Indium::PixelFormat::RGBA16Float;     break;
		case MTLPixelFormatRGB10A2Unorm:    pixelFormat = Indium::PixelFormat::RGB10A2Unorm;    break;
		case MTLPixelFormatBGR10A2Unorm:    pixelFormat = Indium::PixelFormat::BGR10A2Unorm;    break;
		case MTLPixelFormatBGRA10_XR:       pixelFormat = Indium::PixelFormat::BGRA10_XR;       break;
		case MTLPixelFormatBGRA10_XR_sRGB:  pixelFormat = Indium::PixelFormat::BGRA10_XR_sRGB;  break;
		case MTLPixelFormatBGR10_XR:        pixelFormat = Indium::PixelFormat::BGR10_XR;        break;
		case MTLPixelFormatBGR10_XR_sRGB:   pixelFormat = Indium::PixelFormat::BGR10_XR_sRGB;   break;
		default:                            pixelFormat = Indium::PixelFormat::Invalid;         break;
	}

	CGLContextObj prev = CGLGetCurrentContext();
	CGLSetCurrentContext(_context.glContext);

	// now let's start creating the new drawables
	for (size_t i = 0; i < _maximumDrawableCount; ++i) {
		_drawables[i] = std::make_shared<CAMetalDrawableActual>(self, _drawableSize, i, pixelFormat, ((MTLDeviceInternal*)self.device).device, _context.glContext);
		_usableDrawablesBitmap |= 1u << i;
	}

	// now signal the right number of waiters
	for (size_t i = 0; i < _maximumDrawableCount; ++i) {
		[_drawableCondition signal];
	}

	[_drawableCondition unlock];

	@synchronized(self) {
		// resize the render texture
		if (_tex != 0) {
			reportGLErrors();
			glDeleteTextures(1, &_tex);
			reportGLErrors();
			glCreateTextures(GL_TEXTURE_2D, 1, &_tex);
			reportGLErrors();
			glTextureStorage2D(_tex, 1, GL_RGBA8, _drawableSize.width, _drawableSize.height);
			reportGLErrors();
			glTextureParameteri(_tex, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
			glTextureParameteri(_tex, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTextureParameteri(_tex, GL_TEXTURE_WRAP_S, GL_REPEAT);
			glTextureParameteri(_tex, GL_TEXTURE_WRAP_T, GL_REPEAT);
			reportGLErrors();
		}
	}

	CGLSetCurrentContext(prev);
}

- (void)prepareRender
{
	std::shared_ptr<CAMetalDrawableActual> drawable = nullptr;

	[_drawableCondition lock];
	if (_queuedDrawableCount > 0) {
		drawable = _drawables[_queuedDrawables[0]];
		--_queuedDrawableCount;
		std::copy(_queuedDrawables.begin() + 1, _queuedDrawables.end(), _queuedDrawables.begin());
	}
	[_drawableCondition unlock];

	if (drawable) {
		// wait for the drawable to be fully rendered before copying it to the render texture
		// (this is a GPU-side wait)
		drawable->synchronizeRender();

		reportGLErrors();
		glCopyImageSubData(drawable->texture()->glTexture(), GL_TEXTURE_2D, 0, 0, 0, 0, _tex, GL_TEXTURE_2D, 0, 0, 0, 0, _drawableSize.width, _drawableSize.height, 1);
		reportGLErrors();
	}

	@synchronized(self) {
		// FIXME: this is wrong, but there's no good way to tell when the texture is actually fully rendered/presented.
		//        this is at least close enough. it should balance out in the long run since we're supposed to be invoked on vsync
		//        or at least a fixed interval.
		if (_lastPresentedDrawable) {
			_lastPresentedDrawable->didPresent();
		}
		_lastPresentedDrawable = drawable;
	}
}

- (NSNumber*)_textureId
{
	return [NSNumber numberWithUnsignedInt: _tex];
}

//
// overridden methods
//

- (void)removeFromSuperlayer
{
	// we're being removed from our superlayer, so we probably won't be rendered again for a while
	//
	// FIXME: if we're the layer for a root view, this won't be called (i think) so we'll just be leaked.
	//        we'll probably have to add another private method to be called when the layer is released externally (e.g. by the layer context).
	@synchronized(self) {
		if (_lastPresentedDrawable) {
			// no way to tell if it was actually presented or not, so assume it was dropped
			_lastPresentedDrawable->didDrop();
			_lastPresentedDrawable = nullptr;
		}
	}
	[super removeFromSuperlayer];
}

- (void)_setContext: (CALayerContext*)context
{
	[super _setContext: context];

	if (_tex == 0) {
		// create our textures now using the context's CGLContext
		CGLContextObj prev = CGLGetCurrentContext();
		CGLSetCurrentContext(context.glContext);

		reportGLErrors();
		glCreateTextures(GL_TEXTURE_2D, 1, &_tex);
		reportGLErrors();
		glTextureStorage2D(_tex, 1, GL_RGBA8, _drawableSize.width, _drawableSize.height);
		reportGLErrors();
		glTextureParameteri(_tex, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTextureParameteri(_tex, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTextureParameteri(_tex, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTextureParameteri(_tex, GL_TEXTURE_WRAP_T, GL_REPEAT);
		reportGLErrors();

		CGLSetCurrentContext(prev);
	}
}

#else

MTL_UNSUPPORTED_CLASS

#endif

@end
