/* CoreGraphics Wayland backend: a window-server surface.

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

// CGSSurface exists so CGL can render into a window: -nativeWindow is what
// CGLSetSurface() hands EGL as its EGLNativeWindowType. On Wayland that type is
// a wl_egl_window, so this wraps the window's wl_surface in one. eglSwapBuffers
// then attaches and commits, which is also what maps the toplevel.
//
// Creating the surface fails, loudly, when libwayland-egl is not loadable:
// handing EGL a wl_surface where it expects a wl_egl_window would be a type
// confusion that fails much later and much less clearly.

#ifndef CGSSURFACEWAYLAND_H
#define CGSSURFACEWAYLAND_H

#import <CoreGraphics/CGSSurface.h>

struct wl_egl_window;

@class CGSWindowWayland;

@interface CGSSurfaceWayland : CGSSurface {
    CGSWindowWayland *_waylandWindow; // Not retained; it owns us.
    struct wl_egl_window *_eglWindow;
    CGSize _size;
}

- (void) windowResizedTo: (CGSize) size;

@end

#endif
