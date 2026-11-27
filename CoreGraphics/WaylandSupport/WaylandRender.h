/* Shared client support for the Linux render protocols used by both Wayland backends:
   dma-buf buffer negotiation, explicit synchronization and the fifo barrier.

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

#ifndef WAYLAND_RENDER_H
#define WAYLAND_RENDER_H

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>
#include <wayland-client-core.h>
#include <wayland-util.h>

// The backends forward every object in this range to the render manager. They are outside
// their own object-kind enums, so one range check routes them all.
typedef enum {
    WaylandRenderObjectManager = 1199,
    WaylandRenderObjectFeedback = 1200,
    WaylandRenderObjectParams = 1201,
    WaylandRenderObjectLast = WaylandRenderObjectParams,
} WaylandRenderObjectKind;

// A format/modifier pair from the compositor's dma-buf feedback.
typedef struct {
    uint32_t format;
    uint64_t modifier;
} WaylandRenderFormat;

// The memory layout of the IOSurface behind a buffer. The caller must request the format that
// matches its pixels; a compositor that does not advertise it is handled by the caller's shm or
// OpenGL fallback. Negotiating a wide format does not convert 8-bit content to HDR.
typedef NS_ENUM(NSUInteger, WaylandRenderPixelFormat) {
    WaylandRenderPixelFormat8Bit = 0,
    WaylandRenderPixelFormatFloat16 = 1,
};

// Owned by a backend's display/connection and shared by every surface on it. The backend binds
// the three globals with its own -bindGlobal: and passes the proxies here.
@interface WaylandRenderManager : NSObject {
@public
    struct wl_proxy *_dmabuf;
    struct wl_proxy *_syncobjManager;
    struct wl_proxy *_fifoManager;
    uint32_t _dmabufVersion, _dmabufName, _syncobjManagerName, _fifoManagerName;

@private
    wl_dispatcher_func_t _dispatcher;
    NSMutableDictionary *_feedbacks;   // surface key or NSNull -> feedback state
    NSMutableDictionary *_feedbackOwners; // feedback proxy -> surface key
    struct wl_proxy *_defaultFeedback;
    NSMutableArray *_legacyFormats;    // DRM formats from the pre-v3 events
    NSMutableArray *_legacyModifiers;  // modifiers from the pre-v3 events
    NSMutableDictionary *_surfaceObjects; // surface key -> per-surface protocol objects
    NSMutableDictionary *_buffers;      // wl_buffer -> per-buffer timeline objects
    NSMutableDictionary *_params;       // params proxy -> wl_buffer, pending create_immed failure
}

- (instancetype) initWithDispatcher: (wl_dispatcher_func_t) dispatcher;
- (void) bindDMABuf: (struct wl_proxy *) proxy version: (uint32_t) version name: (uint32_t) name;
- (void) bindSyncobjManager: (struct wl_proxy *) proxy name: (uint32_t) name;
- (void) bindFifoManager: (struct wl_proxy *) proxy name: (uint32_t) name;
- (void) globalRemoved: (uint32_t) name;

// Creates the per-surface feedback object when dma-buf v4 or newer is available. Call once when
// the surface is created; the manager keeps the state and releases it in -destroySurface:.
- (void) observeSurface: (struct wl_proxy *) surface;
- (void) destroySurface: (struct wl_proxy *) surface;

// Whether the compositor accepted the given format/modifier pair for this surface. Before its
// feedback arrives, the legacy format events (or the implicit modifier) are used.
- (BOOL) supportsFormat: (uint32_t) format modifier: (uint64_t) modifier
              forSurface: (struct wl_proxy *) surface;
// The preferred pair for RGBA content of `pixelFormat`, or NO when no pair was advertised. When
// needsAlpha is YES, only a format with an alpha channel can be used.
- (BOOL) preferredFormat: (uint32_t *) format modifier: (uint64_t *) modifier
              forSurface: (struct wl_proxy *) surface
              needsAlpha: (BOOL) needsAlpha
              pixelFormat: (WaylandRenderPixelFormat) pixelFormat;

// Creates a wl_buffer from one plane of an IOSurface. The surface must stay alive at least until
// the compositor releases the buffer. Returns NULL when the host cannot export the surface or the
// compositor did not advertise the pair. Call -bufferDestroyed: when the wl_buffer is destroyed.
- (struct wl_proxy *) newBufferForIOSurface: (IOSurfaceRef) surface
                                     format: (uint32_t) format
                                   modifier: (uint64_t) modifier
                                  forSurface: (struct wl_proxy *) target
                                      width: (int32_t) width
                                     height: (int32_t) height
                                     offset: (uint32_t) offset
                                     stride: (uint32_t) stride;
- (void) bufferDestroyed: (struct wl_proxy *) buffer;
// YES when the compositor rejected a dma-buf created for this buffer. Such a buffer must be
// destroyed and recreated, preferably with the shm fallback.
- (BOOL) bufferCreationFailed: (struct wl_proxy *) buffer;

// Sends the fifo requests and, for buffers made by -newBufferForIOSurface:, the explicit
// synchronization points for a frame, both before wl_surface.commit. Returns YES when explicit
// synchronization was used for the buffer; then the compositor's release is reported by the
// timeline and -releasePointSignalledForBuffer: must be used instead of wl_buffer.release.
- (BOOL) beginFrameForSurface: (struct wl_proxy *) surface buffer: (struct wl_proxy *) buffer;
- (BOOL) releasePointSignalledForBuffer: (struct wl_proxy *) buffer;

// Requests sent while the connection is still alive.
- (void) shutdown;
- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandRenderObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args;
@end

#endif
