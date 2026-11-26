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
    WaylandColorObjectRepresentationSurface,
    WaylandColorObjectLast = WaylandColorObjectRepresentationSurface,
} WaylandColorObjectKind;

// Owned by a backend's display/connection. The backend binds the globals with its own
// -bindGlobal:, installing the backend's dispatcher (and passing this manager as the object),
// and passes the proxies here. The manager installs that dispatcher on the child objects it creates.
@interface WaylandColorManager : NSObject {
@public
    struct wl_proxy *_colorManager;
    struct wl_proxy *_representationManager;
    uint32_t _colorManagerVersion, _colorManagerName, _representationManagerName;
    BOOL _featuresKnown, _parametricSupported, _iccSupported, _representationKnown;
    uint32_t _alphaModes;
    NSMutableSet *_namedTransferFunctions, *_namedPrimaries;
    NSMutableArray *_outputs;
    NSMutableDictionary *_outputObservers;
    NSMutableDictionary *_outputInfos;
    NSMutableDictionary *_pendingOutputDescriptions;
    NSMutableDictionary *_pendingSurfaceDescriptions;
    NSMutableDictionary *_pendingInfos;
    NSMutableDictionary *_pendingColorSpaces;
    NSMutableSet *_colorSurfaces;
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
- (void) observeOutput: (struct wl_proxy *) output;
- (NSDictionary *) infoForOutput: (struct wl_proxy *) output;

// The caller owns the returned per-surface proxies and releases them with the
// matching -destroy... method before the wl_surface goes away.
- (struct wl_proxy *) newColorSurfaceForSurface: (struct wl_proxy *) surface;
- (struct wl_proxy *) newRepresentationSurfaceForSurface: (struct wl_proxy *) surface;
- (void) destroyColorSurface: (struct wl_proxy *) proxy;
- (void) destroyRepresentationSurface: (struct wl_proxy *) proxy;

// Describes the surface's contents. The color space is retained until the
// compositor's feature advertisement is complete.
- (void) setColorSpace: (CGColorSpaceRef) space onSurface: (struct wl_proxy *) surfaceManager;

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
@end

#endif
