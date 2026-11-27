/*
 * This file is part of Darling.
 *
 * Copyright (C) 2026 Lubos Dolezel
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

// Darling-specific. How a CAMetalLayer finds a native window to present to.
//
// QuartzCore sits below AppKit and does not know about windows. The window system backends
// (AppKit's X11 and Wayland ones) therefore implement CAMetalLayerSurfaceProvider on the
// subwindow object (CGSubWindow) that a layer context draws into; a CAMetalLayer whose
// context's subwindow conforms asks it for a native surface and presents to that through a
// Vulkan swapchain. When there is no provider, or the device cannot present to the
// surface, the layer presents through the layer context's OpenGL rendering instead.
//
// The layer needs a native surface whose pixels it alone draws. The provider creates one
// as a child of the subwindow, at the layer's place in the layer tree, and keeps it there
// as the layer's frame changes.

#ifdef __OBJC__

#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGColorSpace.h>
#import <Foundation/Foundation.h>

@class CAMetalLayer;

typedef NS_ENUM(NSInteger, CANativeSurfaceKind) {
    CANativeSurfaceKindNone = 0,
    // An X11 window: display is the Display *, window the Window.
    CANativeSurfaceKindXlib = 1,
    // A Wayland surface: display is the wl_display *, surface the wl_surface *.
    CANativeSurfaceKindWayland = 2,
};

typedef struct CANativeSurface {
    CANativeSurfaceKind kind;
    void *display;
    unsigned long window;
    void *surface;
    // Size of the surface in device pixels; this is the size of the drawables
    // a Vulkan swapchain on it can give.
    CGSize pixelSize;
} CANativeSurface;

// The color description a layer wants its native surface to carry. This is the
// layer's own state, in window-system color-description units; a backend
// translates it to its own protocol requests when it applies it. No object in
// the struct is owned by the provider.
typedef struct CAEDRSurfaceColorDescription {
    CGColorSpaceRef colorSpace; // may be NULL: use the surface's preferred description
    BOOL wantsExtendedDynamicRange;
    BOOL hasHDRMetadata;
    int transfer; // HDR10 = 1, HLG = 2
    BOOL hasMasteringDisplayPrimaries;
    // CIE 1931 xy times one million, in r, g, b, white x/y order.
    int32_t masteringDisplayPrimaries[8];
    BOOL hasMasteringLuminance;
    uint32_t masteringMinLuminance; // cd/m^2 * 10000
    uint32_t masteringMaxLuminance; // cd/m^2
    BOOL hasMaxCLL;
    uint32_t maxCLL; // cd/m^2
    BOOL hasMaxFALL;
    uint32_t maxFALL; // cd/m^2
    float opticalOutputScale; // nits corresponding to a linear value of 1
} CAEDRSurfaceColorDescription;

@protocol CAMetalLayerSurfaceProvider <NSObject>

// The size in device pixels that a surface covering `frame` (same coordinates as below) has.
- (CGSize) pixelSizeForMetalSurfaceFrame: (CGRect) frame;

// Creates the native surface for `layer`, covering `frame`: points, relative to
// the subwindow's content, origin at its lower left. Returns NO when none can be made.
- (BOOL) createMetalSurface: (CANativeSurface *) surface
                   forLayer: (CAMetalLayer *) layer
                      frame: (CGRect) frame;

// Moves and resizes the layer's surface; `surface` receives its new description.
// Returns NO when the layer has no surface.
- (BOOL) updateMetalSurface: (CANativeSurface *) surface
                   forLayer: (CAMetalLayer *) layer
                      frame: (CGRect) frame;

// The layer is done with its surface; the provider destroys it. Called on the
// thread that created it, only after the swapchain on it is gone.
- (void) destroyMetalSurfaceForLayer: (CAMetalLayer *) layer;

@optional
// The layer's EDR state, static HDR metadata, or color space changed. The
// provider may apply it to the native surface; a backend without color
// management does not implement this.
- (void) updateMetalSurfaceColorForLayer: (CAMetalLayer *) layer
                             description: (const CAEDRSurfaceColorDescription *) description;

@end

#endif
