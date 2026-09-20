/* CoreGraphics Wayland backend: a window-server window.

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

// An xdg_toplevel on its own wl_surface. The window carries no pixels itself:
// content arrives through its CGSSurface, which wraps the same wl_surface in a
// wl_egl_window so that CGL can render and swap into it. A Wayland toplevel is
// mapped by its first committed buffer, so the window becomes visible when the
// first swap happens, not when it is created or ordered in.

#ifndef CGSWINDOWWAYLAND_H
#define CGSWINDOWWAYLAND_H

#import <CoreGraphics/CGSWindow.h>
#import "CGSConnectionWayland.h"

@class CGSSurfaceWayland;

@interface CGSWindowWayland : CGSWindow {
@public
    CGSConnectionWayland *_waylandConnection; // Not retained; it owns us.
    struct wl_proxy *_surface;

@protected
    struct wl_proxy *_xdgSurface;
    struct wl_proxy *_toplevel;
    // The rect the caller asked for. Wayland never reports where the compositor
    // put a toplevel, so the origin stays the requested one; the size follows
    // the compositor's configure once it sends a non-zero one.
    CGRect _frame;
    NSString *_title;
    CGSSurfaceWayland *_surfaceObject; // Not retained; held by _surfaces.
}

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
           arguments: (union wl_argument *) args;

- (void) surfaceDestroyed: (CGSSurfaceWayland *) surface;

@end

#endif
