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
#import <objc/runtime.h>
#import <Foundation/NSRaise.h>
#import <Metal/MTLDeviceInternal.h>
#import <QuartzCore/CALayerContext.h>
#import <Metal/stubs.h>

#import <Metal/MTLDeviceInternal.h>
#import <QuartzCore/CAMetalLayerSurface.h>
#import "CALayerPlane.h"

#if DARLING_METAL_ENABLED
#include <indium-kit/layer.hpp>
#endif

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

// The device, drawables and the rest of the Metal state have no archived form.
- (void)encodeWithCoder:(NSCoder *)coder
{
	[NSException raise: NSInvalidArchiveOperationException format: @"Cannot archive %@: Metal layers cannot be archived", self];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	[self release];
	[NSException raise: NSInvalidUnarchiveOperationException format: @"Metal layers cannot be unarchived"];
	return nil;
}

#if DARLING_METAL_ENABLED

static const char kCAMetalLayerInternalKey = 0;

- (CAMetalLayerInternal *)_metalInternal
{
	if ([self isMemberOfClass:[CAMetalLayerInternal class]]) {
		return (CAMetalLayerInternal *)self;
	}
	CAMetalLayerInternal *internal = (CAMetalLayerInternal *)objc_getAssociatedObject(self, &kCAMetalLayerInternalKey);
	if (!internal) {
		@synchronized(self) {
			internal = (CAMetalLayerInternal *)objc_getAssociatedObject(self, &kCAMetalLayerInternalKey);
			if (!internal) {
				internal = [[CAMetalLayerInternal alloc] init];
				if (NS_EXTRA(CALayer, self)->_context) {
					[internal _setContext:NS_EXTRA(CALayer, self)->_context];
				}
				if (!CGSizeEqualToSize(NS_EXTRA(CALayer, self)->_bounds.size, CGSizeZero)) {
					[internal setBounds:NS_EXTRA(CALayer, self)->_bounds];
				}
				objc_setAssociatedObject(self, &kCAMetalLayerInternalKey, internal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				[internal release];
			}
		}
	}
	return internal;
}

+ (instancetype)allocWithZone: (NSZone*)zone
{
	if (self == [CAMetalLayer class]) {
		return [CAMetalLayerInternal allocWithZone: zone];
	} else {
		return [super allocWithZone: zone];
	}
}

- (void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];
	if ([self class] != [CAMetalLayerInternal class]) {
		CAMetalLayerInternal *internal = [self _metalInternal];
		[internal setBounds:bounds];
	}
}

- (void)_setContext:(CALayerContext *)context
{
	[super _setContext:context];
	if ([self class] != [CAMetalLayerInternal class]) {
		CAMetalLayerInternal *internal = [self _metalInternal];
		if (CGSizeEqualToSize([internal drawableSize], CGSizeZero) && !CGSizeEqualToSize(NS_EXTRA(CALayer, self)->_bounds.size, CGSizeZero)) {
			[internal setDrawableSize:NS_EXTRA(CALayer, self)->_bounds.size];
		}
		[internal _setContext:context];
	}
}

- (void)removeFromSuperlayer
{
	if ([self class] != [CAMetalLayerInternal class]) {
		[[self _metalInternal] removeFromSuperlayer];
	}
	[super removeFromSuperlayer];
}

- (void)prepareRender
{
	if ([self class] != [CAMetalLayerInternal class]) {
		[[self _metalInternal] prepareRender];
	}
}

- (BOOL)hasQueuedDrawables
{
	if ([self class] != [CAMetalLayerInternal class]) {
		return [[self _metalInternal] hasQueuedDrawables];
	}
	return NO;
}

- (BOOL)_drawLayerContents:(CGRect)bounds opacity:(CGFloat)opacity
{
	if ([self class] != [CAMetalLayerInternal class]) {
		return [[self _metalInternal] _drawLayerContents:bounds opacity:opacity];
	}
	return NO;
}

- (NSNumber *)_textureId
{
	if ([self class] != [CAMetalLayerInternal class]) {
		return [[self _metalInternal] _textureId];
	}
	return nil;
}

- (void)display
{
	if ([self class] != [CAMetalLayerInternal class]) {
		[[self _metalInternal] display];
	} else {
		[super display];
	}
}

- (id<MTLDevice>)device
{
	return [[self _metalInternal] device];
}

- (void)setDevice: (id<MTLDevice>)device
{
	[[self _metalInternal] setDevice:device];
}

- (id<MTLDevice>)preferredDevice
{
	return [[self _metalInternal] preferredDevice];
}

- (MTLPixelFormat)pixelFormat
{
	return [[self _metalInternal] pixelFormat];
}

- (void)setPixelFormat: (MTLPixelFormat)pixelFormat
{
	[[self _metalInternal] setPixelFormat:pixelFormat];
}

- (CGColorSpaceRef)colorspace
{
	return [[self _metalInternal] colorspace];
}

- (void)setColorspace: (CGColorSpaceRef)colorspace
{
	[[self _metalInternal] setColorspace:colorspace];
}

- (BOOL)framebufferOnly
{
	return [[self _metalInternal] framebufferOnly];
}

- (void)setFramebufferOnly: (BOOL)framebufferOnly
{
	[[self _metalInternal] setFramebufferOnly:framebufferOnly];
}

- (CGSize)drawableSize
{
	return [[self _metalInternal] drawableSize];
}

- (void)setDrawableSize: (CGSize)drawableSize
{
	[[self _metalInternal] setDrawableSize:drawableSize];
}

- (BOOL)presentsWithTransaction
{
	return [[self _metalInternal] presentsWithTransaction];
}

- (void)setPresentsWithTransaction: (BOOL)presentsWithTransaction
{
	[[self _metalInternal] setPresentsWithTransaction:presentsWithTransaction];
}

- (BOOL)displaySyncEnabled
{
	return [[self _metalInternal] displaySyncEnabled];
}

- (void)setDisplaySyncEnabled: (BOOL)displaySyncEnabled
{
	[[self _metalInternal] setDisplaySyncEnabled:displaySyncEnabled];
}

- (BOOL)wantsExtendedDynamicRangeContent
{
	return [[self _metalInternal] wantsExtendedDynamicRangeContent];
}

- (void)setWantsExtendedDynamicRangeContent: (BOOL)wantsExtendedDynamicRangeContent
{
	[[self _metalInternal] setWantsExtendedDynamicRangeContent:wantsExtendedDynamicRangeContent];
}

- (CAEDRMetadata*)EDRMetadata
{
	return [[self _metalInternal] EDRMetadata];
}

- (void)setEDRMetadata: (CAEDRMetadata*)EDRMetadata
{
	[[self _metalInternal] setEDRMetadata:EDRMetadata];
}

- (NSUInteger)maximumDrawableCount
{
	return [[self _metalInternal] maximumDrawableCount];
}

- (void)setMaximumDrawableCount: (NSUInteger)maximumDrawableCount
{
	[[self _metalInternal] setMaximumDrawableCount:maximumDrawableCount];
}

- (BOOL)allowsNextDrawableTimeout
{
	return [[self _metalInternal] allowsNextDrawableTimeout];
}

- (void)setAllowsNextDrawableTimeout: (BOOL)allowsNextDrawableTimeout
{
	[[self _metalInternal] setAllowsNextDrawableTimeout:allowsNextDrawableTimeout];
}

- (NSDictionary*)developerHUDProperties
{
	return [[self _metalInternal] developerHUDProperties];
}

- (void)setDeveloperHUDProperties: (NSDictionary*)developerHUDProperties
{
	[[self _metalInternal] setDeveloperHUDProperties:developerHUDProperties];
}

- (id<CAMetalDrawable>)nextDrawable
{
	return [[self _metalInternal] nextDrawable];
}

#else

// Without Metal the accessors are forwarded like every other method; leave
// them to the runtime so that no instance variables are synthesized for them,
// which would clash with those of CAMetalLayerInternal.
@dynamic device, preferredDevice, pixelFormat, colorspace, framebufferOnly, drawableSize,
	presentsWithTransaction, displaySyncEnabled, wantsExtendedDynamicRangeContent, EDRMetadata,
	maximumDrawableCount, allowsNextDrawableTimeout, developerHUDProperties;

MTL_UNSUPPORTED_CLASS

#endif

@end


#if DARLING_METAL_ENABLED

static Indium::PixelFormat indiumPixelFormat(MTLPixelFormat pixelFormat) {
	switch (pixelFormat) {
		case MTLPixelFormatBGRA8Unorm:      return Indium::PixelFormat::BGRA8Unorm;
		case MTLPixelFormatBGRA8Unorm_sRGB: return Indium::PixelFormat::BGRA8Unorm_sRGB;
		case MTLPixelFormatRGBA16Float:     return Indium::PixelFormat::RGBA16Float;
		case MTLPixelFormatRGB10A2Unorm:    return Indium::PixelFormat::RGB10A2Unorm;
		case MTLPixelFormatBGR10A2Unorm:    return Indium::PixelFormat::BGR10A2Unorm;
		case MTLPixelFormatBGRA10_XR:       return Indium::PixelFormat::BGRA10_XR;
		case MTLPixelFormatBGRA10_XR_sRGB:  return Indium::PixelFormat::BGRA10_XR_sRGB;
		case MTLPixelFormatBGR10_XR:        return Indium::PixelFormat::BGR10_XR;
		case MTLPixelFormatBGR10_XR_sRGB:   return Indium::PixelFormat::BGR10_XR_sRGB;
		default:                            return Indium::PixelFormat::Invalid;
	}
};

// CAMetalLayerForceOpenGL makes every Metal layer present through the layer context's OpenGL
// rendering even where it could present through a swapchain on its own native window. The
// application's own value wins; otherwise the user's org.darlinghq.QuartzCore domain decides, so
// it can be set for all applications. NO when unset. Read once per process.
static BOOL forcesOpenGLPresentation(void) {
	static BOOL value;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		CFStringRef key = CFSTR("CAMetalLayerForceOpenGL");
		Boolean valid = false;
		Boolean flag = CFPreferencesGetAppBooleanValue(key, kCFPreferencesCurrentApplication, &valid);

		if (!valid)
			flag = CFPreferencesGetAppBooleanValue(key, CFSTR("org.darlinghq.QuartzCore"), &valid);
		value = valid && flag;
	});
	return value;
}

#endif

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
		// Unlike other layers, Metal layers are opaque by default.
		NS_EXTRA(CALayer, self)->_opaque = YES;
		_drawableSize = NS_EXTRA(CALayer, self)->_bounds.size; // TODO: multiply by contentsScale, once we add that to CALayer
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
	[self tearDownSwapchain];
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
	if (CGSizeEqualToSize(_drawableSize, drawableSize)) {
		return;
	}
	_drawableSizeExplicitlySet = YES;
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

- (void)setBounds: (CGRect)value
{
	CGSize oldSize = NS_EXTRA(CALayer, self)->_bounds.size;
	[super setBounds: value];

	if (!_drawableSizeExplicitlySet) {
		if (CGSizeEqualToSize(_drawableSize, CGSizeZero) || CGSizeEqualToSize(_drawableSize, oldSize)) {
			if (!CGSizeEqualToSize(_drawableSize, value.size)) {
				_drawableSize = value.size;
				[self recreateDrawables];
			}
		}
	}
}

//
// methods
//

- (id<CAMetalDrawable>)nextDrawable
{
	if ([self presentsThroughSwapchain]) {
		return [self nextSwapchainDrawable];
	}

	std::shared_ptr<CAMetalDrawableActual> drawable = nullptr;

	[_drawableCondition lock];

	NSDate* endTime = [NSDate dateWithTimeIntervalSinceNow: 1];

	while (_usableDrawablesBitmap == 0) {
		// A queued present is composited, and its drawable handed back, by a render
		// pass of the layer context, and that pass runs on the main thread. A caller
		// on the main thread would be waiting here for its own thread, so it runs the
		// pass in place. Each pass takes one queued present, so if none was taken
		// (no window to render into yet, or a pass already running) it falls through
		// to waiting instead of looping.
		// _context is not retained by the layer. Only the main thread tears a context
		// down, so on the main thread it stays valid, and the retain covers the unlocked
		// window while a presented handler runs. Other threads never read it.
		if ([NSThread isMainThread] && _queuedDrawableCount > 0) {
			CALayerContext* context = [NS_EXTRA(CALayer, self)->_context retain];
			if (context != nil) {
				NSUInteger queuedBefore = _queuedDrawableCount;
				[_drawableCondition unlock];
				BOOL rendered = [context renderPendingPresents];
				[_drawableCondition lock];
				[context release];
				if (rendered && _queuedDrawableCount < queuedBefore) {
					if (_usableDrawablesBitmap == 0) {
						// The pass above made the drawable it took the layer's displayed one, and
						// that one is only recycled when another present replaces it. This thread
						// is the one that would have to render that present, so it hands the
						// displayed drawable back itself: its content was copied into the layer's
						// texture during the pass.
						[_drawableCondition unlock];
						[self releaseDisplayedDrawable];
						[_drawableCondition lock];
					}
					continue;
				}
			}
		}

		// While this wait lasts, -queuePresent: wakes it, so that a present queued by another thread
		// after the check above is rendered here too: the main thread cannot run the block that would do it.
		BOOL isMainThread = [NSThread isMainThread];
		BOOL timedOut = NO;
		if (isMainThread) {
			_mainThreadWaitingForDrawable = YES;
		}
		if (_allowsNextDrawableTimeout) {
			timedOut = ![_drawableCondition waitUntilDate: endTime];
		} else {
			[_drawableCondition wait];
		}
		if (isMainThread) {
			_mainThreadWaitingForDrawable = NO;
		}
		if (timedOut) {
			break;
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


//
// presenting through a swapchain on a native window
//

// Where the layer is in its context's native window: points, origin at the lower left. Only used while
// the layer may be on its own plane, which it is only when nothing between it and the root is transformed.
- (CGRect)frameInContext
{
	return CALayerPlaneFrameInRoot(self, [NS_EXTRA(CALayer, self)->_context layer]);
}

- (BOOL)presentsThroughSwapchain
{
	@synchronized(self) {
		return _swapchainLayer != nullptr;
	}
}

// Drops the swapchain and the native surface it presented to.
- (void)tearDownSwapchain
{
	std::shared_ptr<IndiumKit::Layer> swapchain;
	id<CAMetalLayerSurfaceProvider> provider = nil;

	@synchronized(self) {
		swapchain = std::move(_swapchainLayer);
		_swapchainLayer = nullptr;
		provider = _surfaceProvider;
		_surfaceProvider = nil;
		_nativeSurface = (CANativeSurface) {};
	}

	// the swapchain goes before the window it presents to
	swapchain.reset();
	if (provider) {
		[provider destroyMetalSurfaceForLayer: self];
		[provider release];
	}

	[_drawableCondition lock];
	_swapchainOutstanding = 0;
	[_drawableCondition broadcast];
	[_drawableCondition unlock];
}

// Moves the native surface to where the layer is now, when that changed.
- (void)syncSurfaceFrame
{
	id<CAMetalLayerSurfaceProvider> provider;
	CGRect frame = [self frameInContext];

	@synchronized(self) {
		if (!_swapchainLayer || CGRectEqualToRect(frame, _surfaceFrame)) {
			return;
		}
		provider = [_surfaceProvider retain];
	}

	CANativeSurface surface = {};
	BOOL updated = [provider updateMetalSurface: &surface forLayer: self frame: frame];
	[provider release];

	if (updated) {
		@synchronized(self) {
			_surfaceFrame = frame;
			_nativeSurface = surface;
		}
	}
}

// Sets up, keeps in step with the layer's properties, or drops the swapchain, and says whether the layer
// presents through one. Called without the drawable lock held. It presents through a swapchain when the
// layer may be on a plane of its own (nothing is drawn over it, see -prepareRender), the context's native
// window can give it a surface of its own, the device can present to that, and the drawables are the size
// of that surface (a swapchain cannot give any other size).
- (BOOL)updateSwapchain
{
	CALayerContext* context = NS_EXTRA(CALayer, self)->_context;
	id subwindow = [context subwindow];
	BOOL possible = !forcesOpenGLPresentation() && _planeAllowed && _device != nil && context != nil &&
	                _drawableSize.width >= 1 && _drawableSize.height >= 1 &&
	                [subwindow conformsToProtocol: @protocol(CAMetalLayerSurfaceProvider)];
	Indium::PixelFormat pixelFormat = indiumPixelFormat(_pixelFormat);

	if (possible && (pixelFormat == Indium::PixelFormat::Invalid || (subwindow == _refusedSubwindow && _device == _refusedDevice))) {
		possible = NO;
	}

	std::shared_ptr<IndiumKit::Layer> swapchain;
	id<CAMetalLayerSurfaceProvider> provider = nil;
	@synchronized(self) {
		swapchain = _swapchainLayer;
		provider = _surfaceProvider;
	}

	// a different window or device than the swapchain was made for starts over
	if (swapchain && (!possible || subwindow != provider)) {
		swapchain.reset();
		[self tearDownSwapchain];
	}

	if (!possible) {
		return NO;
	}

	CGRect frame = [self frameInContext];

	// A swapchain cannot give drawables of any other size than its window's, so a layer that asks for
	// another (a drawableSize that differs from the view's size in pixels) is left to the OpenGL path.
	CGSize pixelSize = [subwindow pixelSizeForMetalSurfaceFrame: frame];
	if (fabs(pixelSize.width - _drawableSize.width) >= 1 || fabs(pixelSize.height - _drawableSize.height) >= 1) {
		if (swapchain) {
			swapchain.reset();
			[self tearDownSwapchain];
		}
		return NO;
	}

	CANativeSurface surface = {};

	if (swapchain) {
		if (![subwindow updateMetalSurface: &surface forLayer: self frame: frame]) {
			swapchain.reset();
			[self tearDownSwapchain];
			return NO;
		}
	} else {
		if (![subwindow createMetalSurface: &surface forLayer: self frame: frame]) {
			_refusedSubwindow = subwindow;
			_refusedDevice = _device;
			return NO;
		}

		VkSurfaceKHR vulkanSurface = VK_NULL_HANDLE;
		auto device = ((MTLDeviceInternal*)_device).device;

		if (surface.kind == CANativeSurfaceKindXlib) {
			vulkanSurface = IndiumKit::createXlibSurface(surface.display, surface.window);
		} else if (surface.kind == CANativeSurfaceKindWayland) {
			vulkanSurface = IndiumKit::createWaylandSurface(surface.display, surface.surface);
		}

		if (vulkanSurface != VK_NULL_HANDLE && !IndiumKit::canPresent(device, vulkanSurface)) {
			IndiumKit::destroySurface(vulkanSurface);
			vulkanSurface = VK_NULL_HANDLE;
		}

		if (vulkanSurface != VK_NULL_HANDLE) {
			swapchain = IndiumKit::Layer::make(vulkanSurface, device, surface.pixelSize.width, surface.pixelSize.height);
			if (!swapchain) {
				// the layer takes the surface only when it succeeds
				IndiumKit::destroySurface(vulkanSurface);
			}
		}

		if (swapchain && !swapchain->setPixelFormat(pixelFormat)) {
			swapchain.reset();
		}

		if (!swapchain) {
			// this device cannot present to this window system, or not in this format: do not try again
			// until the window or the device changes
			_refusedSubwindow = subwindow;
			_refusedDevice = _device;
			[subwindow destroyMetalSurfaceForLayer: self];
			return NO;
		}

		@synchronized(self) {
			_swapchainLayer = swapchain;
			_surfaceProvider = [subwindow retain];
		}
	}

	swapchain->setFramebufferSize(surface.pixelSize.width, surface.pixelSize.height);
	swapchain->setImageCount(_maximumDrawableCount);
	swapchain->setFramebufferOnly(_framebufferOnly);
	swapchain->setDisplaySyncEnabled(_displaySyncEnabled);

	@synchronized(self) {
		_surfaceFrame = frame;
		_nativeSurface = surface;
	}

	return YES;
}

- (id<CAMetalDrawable>)nextSwapchainDrawable
{
	std::shared_ptr<IndiumKit::Layer> swapchain;
	@synchronized(self) {
		swapchain = _swapchainLayer;
	}
	if (!swapchain) {
		return nil;
	}

	NSDate* endTime = [NSDate dateWithTimeIntervalSinceNow: 1];

	// at most maximumDrawableCount drawables are out at once; the one that would be the next waits
	// for a present of another
	[_drawableCondition lock];
	while (_swapchainOutstanding >= _maximumDrawableCount) {
		if (_allowsNextDrawableTimeout) {
			if (![_drawableCondition waitUntilDate: endTime]) {
				[_drawableCondition unlock];
				return nil;
			}
		} else {
			[_drawableCondition wait];
		}
	}
	++_swapchainOutstanding;
	NSUInteger drawableID = _nextSwapchainDrawableID++;
	[_drawableCondition unlock];

	std::shared_ptr<IndiumKit::Drawable> drawable;

	for (;;) {
		NSTimeInterval remaining = [endTime timeIntervalSinceNow];
		uint64_t timeout = remaining > 0 ? (uint64_t)(remaining * 1e9) : 0;
		drawable = swapchain->nextDrawable(timeout);

		if (drawable || _allowsNextDrawableTimeout) {
			break;
		}

		// without a timeout the call waits for as long as the layer is on its swapchain
		endTime = [NSDate dateWithTimeIntervalSinceNow: 1];
		@synchronized(self) {
			if (swapchain != _swapchainLayer) {
				break;
			}
		}
	}

	if (!drawable) {
		[self releaseSwapchainDrawable];
		return nil;
	}

	auto wrapped = std::make_shared<CAMetalSwapchainDrawable>(self, drawable, drawableID);
	return [[[CAMetalDrawableInternal alloc] initWithLayer: self drawable: wrapped] autorelease];
}

- (void)releaseSwapchainDrawable
{
	[_drawableCondition lock];
	if (_swapchainOutstanding > 0) {
		--_swapchainOutstanding;
	}
	[_drawableCondition broadcast];
	[_drawableCondition unlock];
}

- (void)queuePresent: (NSUInteger)drawableID
{
	std::shared_ptr<CAMetalDrawableActual> overflowed;

	[_drawableCondition lock];
	// Every entry names a drawable that is still checked out, since -nextDrawable
	// cleared its _usableDrawablesBitmap bit and -releaseDrawable: only sets it
	// back after a -prepareRender already popped the entry. So the queue cannot
	// outgrow the pool, but that bound lives in -nextDrawable and _queuedDrawables
	// is a fixed array, so check it here rather than write blind.
	if (_queuedDrawableCount < _drawables.size()) {
		_queuedDrawables[_queuedDrawableCount] = drawableID;
		++_queuedDrawableCount;
		if (_mainThreadWaitingForDrawable) {
			// Broadcast, because other threads may wait on the same condition.
			[_drawableCondition broadcast];
		}
	} else {
		overflowed = _drawables[drawableID];
	}
	[_drawableCondition unlock];

	if (overflowed) {
		// Report the present as dropped, which fires the drawable's presented
		// handlers and recycles the slot. Outside the lock, because those handlers
		// end in -releaseDrawable:, which relocks it.
		overflowed->didDrop();
	}

	// we now need to schedule a render
	//
	// FIXME: once we fix up CALayer and make it more featureful, this needs to change to `self.needsDisplay = YES` or equivalently `[self setNeedsDisplay: YES]`
	// right now, CALayer is missing all the needs-display logic (which is currently in NSView)
	[self display];
}

// Reports the drawable shown by the last composited present as presented, which
// recycles it. Called without the drawable lock held, since recycling takes it.
- (void)releaseDisplayedDrawable
{
	std::shared_ptr<CAMetalDrawableActual> displayed;

	@synchronized(self) {
		displayed = std::move(_lastPresentedDrawable);
		_lastPresentedDrawable = nullptr;
	}

	if (displayed) {
		displayed->didPresent();
	}
}

- (void)releaseDrawable: (NSUInteger)drawableID
{
	[_drawableCondition lock];
	_usableDrawablesBitmap |= 1u << drawableID;
	[_drawableCondition signal];
	[_drawableCondition unlock];
}

// Creates the texture the compositor draws the layer from, in the current GL
// context.
- (void)createRenderTexture
{
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

- (void)recreateDrawables
{
	// decided before the drawable lock is taken, as dropping a swapchain takes it
	BOOL swapchain = [self updateSwapchain];

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

	// A layer that can present to a native window through a swapchain has no use for the pool below.
	if (swapchain) {
		[_drawableCondition unlock];
		return;
	}

	if (!_device || !NS_EXTRA(CALayer, self)->_context.glContext || _drawableSize.width == 0 || _drawableSize.height == 0) {
		// can't create new drawables
		[_drawableCondition unlock];
		return;
	}

	Indium::PixelFormat pixelFormat = indiumPixelFormat(_pixelFormat);

	CGLContextObj prev = CGLGetCurrentContext();
	CGLSetCurrentContext(NS_EXTRA(CALayer, self)->_context.glContext);

	// ask the context once whether it can wait on the drawables' semaphores
	if (_semaphoreProbeContext != NS_EXTRA(CALayer, self)->_context.glContext) {
		_glImportsSemaphores = CAMetalDrawableGLImportsSemaphores();
		_semaphoreProbeContext = NS_EXTRA(CALayer, self)->_context.glContext;
	}

	// now let's start creating the new drawables
	// A drawable the device cannot make is left out rather than ending the process:
	// -nextDrawable then has fewer drawables to hand out, or none, and returns nil
	// when it runs out, as it does when the layer has no device.
	for (size_t i = 0; i < _maximumDrawableCount; ++i) {
		try {
			_drawables[i] = std::make_shared<CAMetalDrawableActual>(self, _drawableSize, i, pixelFormat, ((MTLDeviceInternal*)self.device).device, NS_EXTRA(CALayer, self)->_context.glContext, _glImportsSemaphores);
		} catch (const std::exception& e) {
			NSLog(@"CAMetalLayer: cannot create a %gx%g drawable: %s", _drawableSize.width, _drawableSize.height, e.what());
			break;
		}
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
			[self createRenderTexture];
		}
	}

	CGLSetCurrentContext(prev);
}

// Whether a present is queued that -prepareRender has not composited yet. The
// render timer uses this to keep drawing between consecutive presents.
- (BOOL)hasQueuedDrawables
{
	[_drawableCondition lock];
	BOOL queued = _queuedDrawableCount > 0;
	[_drawableCondition unlock];
	return queued;
}

- (void)prepareRender
{
	// The native surface sits above everything the layer context composites, so the layer goes on it only
	// while that looks the same as compositing it: nothing drawn over it, no transform, opacity or clip
	// that a plane cannot show. Decided again every pass, as views move, hide and stack differently.
	CALayerContext* context = NS_EXTRA(CALayer, self)->_context;
	_planeAllowed = CALayerCanPresentOnOwnPlane(self, [context layer]);

	if ([self presentsThroughSwapchain]) {
		if (_planeAllowed) {
			// A layer on a native window has no frame to composite, but it may have moved with its view.
			[self syncSurfaceFrame];
			return;
		}
		// Covered or changed in a way a plane cannot show: back to compositing, with the drawables
		// it presents from now on.
		_attemptedPlane = NO;
		[self recreateDrawables];
	} else {
		// The layer's context gets its native window after the layer was configured, so the first render
		// pass in a window is where a swapchain can be set up; it is tried again when the window or the
		// device changes, or when the layer becomes uncovered.
		id subwindow = [context subwindow];
		if (subwindow != nil && _planeAllowed &&
		    (subwindow != _attemptedSubwindow || _device != _attemptedDevice || !_attemptedPlane)) {
			_attemptedSubwindow = subwindow;
			_attemptedDevice = _device;
			_attemptedPlane = YES;
			[self recreateDrawables];
			if ([self presentsThroughSwapchain]) {
				return;
			}
		} else if (!_planeAllowed) {
			_attemptedPlane = NO;
		}
	}

	std::shared_ptr<CAMetalDrawableActual> drawable = nullptr;

	[_drawableCondition lock];
	if (_queuedDrawableCount > 0) {
		drawable = _drawables[_queuedDrawables[0]];
		--_queuedDrawableCount;
		std::copy(_queuedDrawables.begin() + 1, _queuedDrawables.end(), _queuedDrawables.begin());
	}
	[_drawableCondition unlock];

	if (drawable) {
		CAMetalDrawableWarnIfDisplayedOnAnotherDevice(std::dynamic_pointer_cast<Indium::PrivateDevice>(((MTLDeviceInternal*)_device).device));

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

// -prepareRender copies the queued drawable into _tex, so drawing the layer is
// just binding that texture and emitting the quad. Its texture parameters were
// set when it was created, and must be left alone: the contents path binds the
// same texture (via -_textureId) and reallocates it with -glTexImage2D.
- (BOOL)_drawLayerContents: (CGRect)bounds opacity: (CGFloat)opacity
{
	// The layer's native window shows the frames, over what the tree draws beneath it.
	if ([self presentsThroughSwapchain])
		return YES;

	if (_tex == 0)
		return NO;

	reportGLErrors();

	glEnable(GL_TEXTURE_2D);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	glBindTexture(GL_TEXTURE_2D, _tex);

	// An opaque layer's content has no transparency, whatever alpha the app
	// rendered into its drawables. Sampling alpha as 1 keeps the compositor's
	// blending and alpha test from making such pixels see-through or dropping
	// them.
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_A, [self isOpaque] ? GL_ONE : GL_ALPHA);

	// The texture is stored bottom-up like a CGBitmapContext, and the layer's
	// origin is its bottom-left corner, so the quad is drawn the same way the
	// contents path draws one.
	const GLfloat textureVertices[4 * 2] = {0, 1, 1, 1, 0, 0, 1, 0};
	const GLfloat vertices[4 * 2] = {0, 0, (GLfloat) bounds.size.width, 0,
									 0, (GLfloat) bounds.size.height,
									 (GLfloat) bounds.size.width,
									 (GLfloat) bounds.size.height};

	glTexCoordPointer(2, GL_FLOAT, 0, textureVertices);
	glVertexPointer(2, GL_FLOAT, 0, vertices);
	glColor4f(opacity, opacity, opacity, opacity);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisable(GL_TEXTURE_2D);

	reportGLErrors();

	return YES;
}

// A Metal layer's content is whatever the app last rendered through -nextDrawable,
// so -drawInContext: has nothing to draw and rasterising it would only produce
// a blank bitmap, which the contents path would then upload over _tex.
- (void)display
{
	[NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
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
	CALayerContext* previous = NS_EXTRA(CALayer, self)->_context;

	[super _setContext: context];

	// Sublayer changes set the same context again; keep the drawables then.
	if (context == previous) {
		return;
	}

	// The render texture and the drawables' GL objects live in the previous
	// context, so they cannot be used in the new one. Release them with that
	// context current.
	CGLContextObj prev = CGLGetCurrentContext();
	if (previous.glContext) {
		CGLSetCurrentContext(previous.glContext);
		if (_tex != 0) {
			glDeleteTextures(1, &_tex);
		}
	}
	_tex = 0;
	_semaphoreProbeContext = NULL;

	// Drop the old drawables and, once there is a GL context, make new ones in
	// it. A layer is usually configured (device, drawableSize) before it is put
	// in a window, and then this is the first point where its drawables can
	// exist.
	[self recreateDrawables];
	CGLSetCurrentContext(prev);

	if (!context.glContext) {
		return;
	}

	// create our textures now using the context's CGLContext
	CGLSetCurrentContext(context.glContext);
	[self createRenderTexture];
	CGLSetCurrentContext(prev);
}

#else

MTL_UNSUPPORTED_CLASS

#endif

@end
