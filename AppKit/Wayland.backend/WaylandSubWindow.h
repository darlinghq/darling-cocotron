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
#import <QuartzCore/CAMetalLayerSurface.h>
@class WaylandWindow;
struct wl_proxy;
struct wl_egl_window;

// UI-thread geometry, EGL swap and flush form one presentation transaction.
// CALayerContext releases its EGL surface before releasing this native window.
@interface WaylandSubWindow : CGSubWindow <CAMetalLayerSurfaceProvider> {
    WaylandWindow *_parent;
    struct wl_proxy *_surface, *_subsurface, *_viewport, *_fractionalScale;
    uint32_t _preferredScale120;
    BOOL _scaleUpdatePending, _needsScaleRedraw, _scaleRedrawRequested;
    struct wl_egl_window *_eglWindow;
    CGSize _drawablePixelSize;
    CGRect _frame, _fullRect, _pendingRect, _presentedRect;
    BOOL _visible, _clipped;
    int _flushPending; // a flush hop to the main thread is queued (atomic)
    // Color-management objects for this subwindow's EGL surface.
    struct wl_proxy *_colorSurface, *_representationSurface, *_surfaceFeedback;
    // OpenGL layers that asked for EDR content, by layer (not retained).
    NSHashTable *_edrLayers;
    // The surfaces Metal layers present to, by layer (not retained): WaylandMetalSurface objects.
    NSMapTable *_metalSurfaces;
}
- (id) initWithParentWindow: (WaylandWindow *) parent frame: (CGRect) frame;
- (void) updateGeometry;
- (void) preferredScaleChanged: (uint32_t) scale120;
- (struct wl_proxy *) presentedSurface;
- (void) placeAboveSurface: (struct wl_proxy *) surface;
// Stacks the Metal layers' surfaces above `below`; returns the topmost surface.
- (struct wl_proxy *) stackMetalSurfacesAbove: (struct wl_proxy *) below;
- (void) detachMetalSubsurfaces;
- (void) attachMetalSubsurfaces;
// The parent window replaces its wl_surface (see -[WaylandWindow prepareSurfaceForRole:]): the
// subsurfaces made for the old one go first, and the new one gets them when it has its role.
- (void) parentSurfaceWillBeReplaced;
- (void) parentSurfaceReplaced;
// Color management for this subwindow and its Metal surfaces. Returns whether the feedback
// belonged to one of them; the parent window uses that to route compositor callbacks.
- (BOOL) preferredColorInfoChangedForFeedback: (struct wl_proxy *) feedback;
- (void) colorManagerAvailable;
@end
