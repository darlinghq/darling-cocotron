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

#import "CGSSurfaceWayland.h"
#import "CGSWindowWayland.h"
#import "WaylandLibrary.h"

#import <Foundation/NSString.h>

@implementation CGSSurfaceWayland

- (instancetype) initWithWindow: (CGSWindow *) window
                      surfaceID: (CGSSurfaceID) surfaceID
{
    self = [super initWithWindow: window surfaceID: surfaceID];
    if (self == nil)
        return nil;

    _waylandWindow = (CGSWindowWayland *) window;

    if (!WL.hasEGL) {
        NSLog(@"CoreGraphics Wayland backend: libwayland-egl is unavailable, so "
              @"this window cannot be given a drawable surface");
        [self release];
        return nil;
    }

    CGRect frame;
    [_waylandWindow getRect: &frame];
    _size = frame.size;

    _eglWindow = WL.wl_egl_window_create(
            (struct wl_surface *) _waylandWindow->_surface,
            (int) _size.width, (int) _size.height);
    if (_eglWindow == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot create a %g x %g EGL window",
              _size.width, _size.height);
        [self release];
        return nil;
    }
    return self;
}

- (void) dealloc {
    if (_eglWindow != NULL)
        WL.wl_egl_window_destroy(_eglWindow);
    [_waylandWindow surfaceDestroyed: self];
    [super dealloc];
}

- (void) windowResizedTo: (CGSize) size {
    if (_eglWindow == NULL || CGSizeEqualToSize(size, _size))
        return;
    _size = size;
    WL.wl_egl_window_resize(_eglWindow, (int) size.width, (int) size.height, 0, 0);
}

- (CGError) setBounds: (CGRect) rect {
    if (!(rect.size.width >= 1) || !(rect.size.height >= 1))
        return kCGErrorIllegalArgument;

    if (rect.origin.x != 0 || rect.origin.y != 0) {
        // Offsetting a surface inside its window needs a wl_subsurface of its
        // own, which this backend does not create (see -createSurface).
        NSLog(@"CoreGraphics Wayland backend: a surface offset within its "
              @"window is not implemented");
        return kCGErrorNotImplemented;
    }

    [self windowResizedTo: rect.size];
    return kCGSErrorSuccess;
}

- (void *) nativeWindow {
    return _eglWindow;
}

@end
