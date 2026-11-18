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
#import <OpenGL/CGLTypes.h>

#import <QuartzCore/CAMetalLayerSurface.h>

#include <memory>
#include <array>

class CAMetalDrawableActual;

namespace IndiumKit {
	class Layer;
};

@interface CAMetalLayerInternal : CAMetalLayer {
	id<MTLDevice> _device;
	MTLPixelFormat _pixelFormat;
	CGColorSpaceRef _colorspace;
	BOOL _framebufferOnly;
	CGSize _drawableSize;
	BOOL _drawableSizeExplicitlySet;
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
	// YES while the main thread waits for a drawable in -nextDrawable; guarded by _drawableCondition.
	BOOL _mainThreadWaitingForDrawable;
	std::shared_ptr<CAMetalDrawableActual> _lastPresentedDrawable;

	GLuint _tex;

	// the GL context _glImportsSemaphores was found for
	CGLContextObj _semaphoreProbeContext;
	BOOL _glImportsSemaphores;

	// Presenting through a Vulkan swapchain on a native window instead of through the layer context's
	// OpenGL rendering: the swapchain's layer (null in the OpenGL mode), the provider of the native
	// surface it presents to, that surface, and where it was last placed. Guarded by @synchronized(self).
	std::shared_ptr<IndiumKit::Layer> _swapchainLayer;
	id<CAMetalLayerSurfaceProvider> _surfaceProvider;
	CANativeSurface _nativeSurface;
	CGRect _surfaceFrame;
	// Drawables handed out and not presented yet, and the next drawable ID; guarded by _drawableCondition.
	NSUInteger _swapchainOutstanding;
	NSUInteger _nextSwapchainDrawableID;
	// The window and device a swapchain could not be made for; not tried again until either changes.
	id _refusedSubwindow;
	id _refusedDevice;
	// The window and device the last render pass looked for a swapchain with, and whether the layer
	// could be shown on its own plane then.
	id _attemptedSubwindow;
	id _attemptedDevice;
	BOOL _attemptedPlane;
	// Whether the layer, where it is in its tree, may be shown on a native surface of its own above the
	// composited tree (CALayerCanPresentOnOwnPlane). Decided by every render pass, on the main thread.
	BOOL _planeAllowed;
}

- (void)queuePresent: (NSUInteger)drawableID;
- (void)releaseDrawable: (NSUInteger)drawableID;
- (void)releaseDisplayedDrawable;
// A drawable from the swapchain is no longer in use.
- (void)releaseSwapchainDrawable;
// Whether the layer presents through a swapchain on a native window.
- (BOOL)presentsThroughSwapchain;

- (BOOL)hasQueuedDrawables;

- (void)prepareRender;

@end

@interface CAMetalLayer (DARLING_INTERNAL)
- (void)prepareRender;
- (BOOL)hasQueuedDrawables;
@end
