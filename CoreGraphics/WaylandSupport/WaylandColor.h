/* Wayland color-management and color-representation client support shared by the
   CoreGraphics and AppKit Wayland backends.

   Permission is hereby granted, free of charge, to any person obtaining a copy of
   this software and associated documentation files (the "Software"), to deal in
   the Software without restriction, including without limitation the rights to
   use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
   of the Software, and to permit persons to whom the Software is furnished to do
   so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. */

#ifndef WAYLAND_COLOR_H
#define WAYLAND_COLOR_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <wayland-client-core.h>
#include <wayland-util.h>

@class WaylandColorManager;

// The backends forward all objects in this range to the manager. The values are
// outside their own object-kind enums, so one range check routes them all.
typedef enum {
    WaylandColorObjectManager = 1000,
    WaylandColorObjectRepresentationManager,
    WaylandColorObjectOutput,
    WaylandColorObjectImageDescription,
    WaylandColorObjectImageDescriptionInfo,
    WaylandColorObjectSurface,
    WaylandColorObjectSurfaceFeedback,
    WaylandColorObjectRepresentationSurface,
    WaylandColorObjectLast = WaylandColorObjectRepresentationSurface,
} WaylandColorObjectKind;

// Static HDR metadata of the content, in the units of
// wp_image_description_creator_params_v1. All fields are optional; the
// compositor's defaults apply when a flag is NO. Chromaticities are CIE 1931
// xy coordinates multiplied by one million, in r, g, b, white x/y order.
typedef struct {
    BOOL hasMasteringDisplayPrimaries;
    int32_t masteringDisplayPrimaries[8];
    BOOL hasMasteringLuminance;
    uint32_t masteringMinLuminance; // cd/m^2 * 10000
    uint32_t masteringMaxLuminance; // cd/m^2
    BOOL hasPrimaryVolumeLuminance;
    uint32_t primaryVolumeMinLuminance; // cd/m^2 * 10000
    uint32_t primaryVolumeMaxLuminance; // cd/m^2
    uint32_t primaryVolumeReferenceLuminance; // cd/m^2
    BOOL hasMaxCLL;
    uint32_t maxCLL; // cd/m^2
    BOOL hasMaxFALL;
    uint32_t maxFALL; // cd/m^2
} WaylandColorHDRMetadata;

// Static HDR metadata a backend can derive from a compositor's preferred image description. The
// keys of `info` are the kCGSDisplayColor* keys; values of an unrecognized type are ignored.

// Owned by a backend's display/connection. The backend binds the globals with its own
// -bindGlobal:, installing the backend's dispatcher (and passing this manager as the object),
// and passes the proxies here. The manager installs that dispatcher on the child objects it creates.
@interface WaylandColorManager : NSObject {
@public
    struct wl_proxy *_colorManager;
    struct wl_proxy *_representationManager;
    uint32_t _colorManagerVersion, _colorManagerName, _representationManagerName;
    BOOL _featuresKnown, _parametricSupported, _iccSupported, _representationKnown;
    uint32_t _features, _supportedIntents;
    uint32_t _alphaModes;
    // The coefficients/range pairs the compositor advertised, packed as (coefficients << 8) | range.
    NSMutableSet *_supportedCoefficientsAndRanges;
    NSMutableSet *_namedTransferFunctions, *_namedPrimaries;
    NSMutableArray *_outputs;
    NSMutableDictionary *_outputObservers;
    NSMutableDictionary *_outputInfos;
    NSMutableDictionary *_pendingOutputDescriptions;
    NSMutableDictionary *_pendingSurfaceDescriptions;
    NSMutableDictionary *_pendingDescriptionIntents;
    NSMutableDictionary *_pendingInfos;
    NSMutableSet *_colorSurfaces;
    NSMutableDictionary *_pendingSurfaceContents;
    NSMutableSet *_surfaceFeedbacks;
    NSMutableDictionary *_preferredInfos;
    NSMutableDictionary *_pendingPreferredDescriptions;
    NSMutableDictionary *_pendingPreferredInfos;
    NSMutableDictionary *_preferredIdentities;
    NSMutableSet *_representationSurfaces;
    NSMutableArray *_pendingRepresentationSurfaces;
    wl_dispatcher_func_t _dispatcher;
    id _owner; // Not retained; the display/connection outlives the manager.
}

- (instancetype) initWithDispatcher: (wl_dispatcher_func_t) dispatcher owner: (id) owner;

- (void) bindColorManager: (struct wl_proxy *) proxy
                  version: (uint32_t) version
                    name: (uint32_t) name;
- (void) bindRepresentationManager: (struct wl_proxy *) proxy
                           version: (uint32_t) version
                             name: (uint32_t) name;
- (void) globalRemoved: (uint32_t) name;
// Whether the compositor offers color management or color representation. The framework above uses
// this instead of the instance variables, as the class lives in another image.
- (BOOL) hasColorGlobals;
// Whether any output reports a maximum luminance above its reference white.
- (BOOL) hasExtendedDynamicRange;
- (void) observeOutput: (struct wl_proxy *) output;
- (NSDictionary *) infoForOutput: (struct wl_proxy *) output;

// The caller owns the returned per-surface proxies and releases them with the
// matching -destroy... method before the wl_surface goes away.
- (struct wl_proxy *) newColorSurfaceForSurface: (struct wl_proxy *) surface;
- (struct wl_proxy *) newRepresentationSurfaceForSurface: (struct wl_proxy *) surface;
- (void) destroyColorSurface: (struct wl_proxy *) proxy;
- (void) destroyRepresentationSurface: (struct wl_proxy *) proxy;

// Creates the compositor's preferred-description feedback object for a surface. The caller owns it
// and releases it with -destroySurfaceFeedback: before the wl_surface goes away.
- (struct wl_proxy *) newSurfaceFeedbackForSurface: (struct wl_proxy *) surface;
- (void) destroySurfaceFeedback: (struct wl_proxy *) proxy;
// The information events of the preferred description, keyed with the private
// kCGSDisplayColor* keys. nil until the first description is ready.
- (NSDictionary *) preferredInfoForFeedback: (struct wl_proxy *) proxy;

// Describes the surface's contents. The color space and metadata are retained until the
// compositor's feature advertisement is complete. An unsupported rendering intent falls back to
// perceptual, which every compositor supporting the protocol accepts.
- (void) setColorSpace: (CGColorSpaceRef) space onSurface: (struct wl_proxy *) surfaceManager;
- (void) setColorSpace: (CGColorSpaceRef) space
        renderingIntent: (uint32_t) intent
             hdrMetadata: (const WaylandColorHDRMetadata *) metadata
               onSurface: (struct wl_proxy *) surfaceManager;
// The HDR metadata a surface of `space` should carry, from the color info of an output or a surface
// feedback (nil: none). A method so that the framework above, which does not link this file, can use it.
- (WaylandColorHDRMetadata) hdrMetadataForColorInfo: (NSDictionary *) info space: (CGColorSpaceRef) space;

// Describes non-RGB contents of a representation surface. The values are sent only when they are
// allowed for the surface's pixel format; the caller is responsible for the chroma location of 4:2:0
// buffers. RGB surfaces use -applyRepresentationToSurface: and need neither call.
- (void) setCoefficients: (uint32_t) coefficients range: (uint32_t) range
                onSurface: (struct wl_proxy *) surfaceManager;
- (void) setChromaLocation: (uint32_t) location onSurface: (struct wl_proxy *) surfaceManager;

// Sends the protocol's destructor requests while the display is still connected. Called by the
// owner before it disconnects, and by -dealloc as a fallback.
- (void) shutdown;

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandColorObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) arguments;
@end

// The owner implements these to learn that an output's description changed, or that a color
// manager global went away and its descriptions are no longer available.
@interface NSObject (WaylandColorManagerOwner)
- (void) waylandColorManagerOutputInfoChanged: (WaylandColorManager *) manager;
- (void) waylandColorManagerDidLoseGlobal: (WaylandColorManager *) manager;
// The compositor's preferred image description for a surface changed. The feedback proxy identifies
// the surface; -preferredInfoForFeedback: answers its information.
- (void) waylandColorManagerPreferredInfoChanged: (WaylandColorManager *) manager
                                     forFeedback: (struct wl_proxy *) feedback;
@end

#endif
