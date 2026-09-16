/* Permission is hereby granted, free of charge, to any person obtaining a copy of
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

#import <CoreGraphics/CGSubWindow.h>
@class WaylandWindow;
struct wl_proxy;
struct wl_egl_window;

// UI-thread geometry, EGL swap and flush form one presentation transaction.
// CALayerContext releases its EGL surface before releasing this native window.
@interface WaylandSubWindow : CGSubWindow {
    WaylandWindow *_parent;
    struct wl_proxy *_surface, *_subsurface, *_viewport, *_fractionalScale;
    uint32_t _preferredScale120;
    BOOL _scaleUpdatePending, _needsScaleRedraw, _scaleRedrawRequested;
    struct wl_egl_window *_eglWindow;
    CGSize _drawablePixelSize;
    CGRect _frame, _pendingRect, _presentedRect;
    BOOL _visible, _clipped;
}
- (id) initWithParentWindow: (WaylandWindow *) parent frame: (CGRect) frame;
- (void) updateGeometry;
- (void) preferredScaleChanged: (uint32_t) scale120;
- (struct wl_proxy *) presentedSurface;
- (void) placeAboveSurface: (struct wl_proxy *) surface;
@end
