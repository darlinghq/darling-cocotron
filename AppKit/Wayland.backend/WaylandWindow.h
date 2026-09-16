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

#import <CoreGraphics/CGWindowPrivate.h>
#import <Onyx2D/O2Geometry.h>
#include <wayland-util.h>

#import "WaylandDisplay.h"

@class NSWindow, O2Context, WaylandSubWindow;

struct WaylandBuffer {
    struct wl_proxy *buffer;
    void *data;
    size_t size;
    int32_t width, height;
    uint32_t format;
    BOOL busy; // attached and not yet released by the compositor
};

// A top-level window: an xdg_toplevel whose content is Onyx2D's CPU rendering,
// copied into wl_shm buffers.
@interface WaylandWindow : CGWindow {
    NSWindow *_delegate;
    WaylandDisplay *_display;
    BOOL _invalidated;
    NSMutableArray *_subwindows; // nonretained pointers; children retain their parent
    int _level;
    NSUInteger _styleMask;
    CGSBackingStoreType _backingType; // stored, but ignored
    O2Context *_context;
    NSMutableDictionary *_deviceDictionary;
    // AppKit screen coordinates. The origin is only what AppKit asked for: the
    // compositor places the window and doesn't say where.
    O2Rect _frame;
    NSString *_title;
    CGPoint _lastMotionPos;
    BOOL _isOpaque;
    BOOL _hasShadow;

    struct wl_proxy *_surface;
    struct wl_proxy *_xdgSurface;
    struct wl_proxy *_toplevel;
    struct wl_proxy *_popup;
    WaylandWindow *_popupParent;
    uint32_t _popupGrabSerial;
    uint32_t _repositionToken;
    int32_t _pendingPopupX, _pendingPopupY;
    struct wl_proxy *_decoration;
    struct wl_proxy *_frameCallback;
    struct WaylandBuffer _buffers[2];
    int32_t _pendingWidth, _pendingHeight;
    BOOL _pendingActivated;
    BOOL _mapped;
    BOOL _configured;
    BOOL _needsPresent;
    BOOL _activated;
    NSMutableSet *_surfaceOutputs;
    int32_t _bufferScale; // Integer output fallback, not fractional wire scale.
    uint32_t _preferredScale120, _renderScale120;
    struct wl_proxy *_fractionalScale, *_viewport;
    BOOL _scaleUpdatePending, _subwindowRedrawPending, _subwindowRedrawNeeded;
    BOOL _clientDecorated, _pendingClientDecorated;
    BOOL _maximized, _pendingMaximized;
    BOOL _configureUpdatePending;
    NSUInteger _surfaceGeneration;
}

- (instancetype) initWithDelegate: (NSWindow *) delegate;

- (O2Rect) frame;
- (O2Context *) cgContext;
- (struct wl_proxy *) surface;
- (struct wl_proxy *) ensureSurface;
- (WaylandDisplay *) waylandDisplay;
- (void) addSubwindow: (WaylandSubWindow *) child;
- (void) removeSubwindow: (WaylandSubWindow *) child;
- (void) updateSubwindows;
- (void) scheduleSubwindowRedraw;
- (void) stackSubwindows;
- (BOOL) isInvalidated;
- (BOOL) isMapped;
- (int32_t) bufferScale;
- (uint32_t) renderScale120;
- (void) preferredScaleChanged: (uint32_t) scale120;
- (void) outputRemoved: (struct wl_proxy *) output;
- (void) scheduleScaleUpdate;
- (BOOL) isPopup;
- (WaylandWindow *) popupParent;
- (uint32_t) popupGrabSerial;
- (struct wl_proxy *) xdgSurface;
- (void) unmap;
- (NSPoint) contentOffset;
- (BOOL) isDecorationPoint: (CGPoint) point;
- (BOOL) decorationButton: (uint32_t) button pressed: (BOOL) pressed
                   serial: (uint32_t) serial atPoint: (CGPoint) point;

// Converts a surface-local point (origin top left) to window coordinates.
- (NSPoint) transformPoint: (CGPoint) surfacePoint;
- (void) setLastKnownCursorPosition: (CGPoint) point;

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args;

@end
