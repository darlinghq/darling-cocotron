/* Copyright (c) 2008 Johannes Fortmann

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

#import <CoreGraphics/CGWindowPrivate.h>
#import <CoreGraphics/CGSWindow.h>
#import <GL/glx.h>
#import <Onyx2D/O2Geometry.h>
#import <Onyx2D/O2Image.h>
#import <OpenGL/CGLInternal.h>
#import <X11/Xlib.h>
#import <X11/Xresource.h>
#import <X11/Xlocale.h>

@class X11Display, CAWindowOpenGLContext, NSWindow, O2Context, CGSWindow;

// Posted, with the window as the object, after its backing pixels were flushed.
extern NSString *const X11WindowBackingDidFlushNotification;

@class NSCGSInputMethod;

@interface X11Window : CGWindow {
    int _level; // TODO: care about this value
    Display *_display;
    XVisualInfo *_visualInfo;
    Window _window;
    // The CoreGraphics window that is the window system's window: made, shown, hidden, placed, sized,
    // titled, made translucent and destroyed through it; _window is its native handle.
    CGSWindow *_cgsWindow;
    CGLContextObj _cglContext;
    CGLWindowRef _cglWindow;
    CAWindowOpenGLContext *_caContext;

    NSWindow *_delegate;
    CGSBackingStoreType _backingType; // stored, but ignored
    O2Context *_context;

    NSMutableDictionary *_deviceDictionary;
    O2Rect _frame;
    NSUInteger _styleMask;
    BOOL _mapped;
    // The window was ordered out and is still mapped: the unmap waits for the end of the run loop pass, in
    // case the window is ordered in again within it (see -hideWindow).
    BOOL _unmapPending;
    CGPoint _lastMotionPos;
    BOOL _isModal;
    BOOL _overrideRedirect;
    BOOL _dock; // the menu bar window (see X11MenuBarWindow)
    BOOL _menuWindow; // a menu or pop-up window
    BOOL _skipTaskbar; // not an application window: no task-bar or pager entry (see -updateWindowManagerHints)
    X11Window *_transientParent; // the window named by WM_TRANSIENT_FOR (retained)
    BOOL _isOpaque;
    BOOL _hasAlpha;   // created with the 32-bit visual and an alpha surface
    BOOL _wasMapped;  // the visual is settled when the window is first mapped
    BOOL _hasShadow;
    BOOL _keyRequested; // the application asked for this window to become key and the focus has not answered yet
    CGFloat _appliedAlpha; // the window's alpha value as last applied to the X window
    BOOL _alphaIsZero; // _appliedAlpha is 0
    BOOL _chromeless; // no window manager frame and no title bar: rounded corners and an outline (see -setTitlebarKind:)
    int _titlebarKind; // the CGSToplevelTitlebarKind NSWindow asked for
    BOOL _invisibleWithoutCompositor; // alpha 0 made the window invisible by shape (see -updateInvisibility)
    // The subwindow whose layer tree draws into _cglWindow instead of its
    // own drawable (see -[X11SubWindow sharedCGLWindow]), and whether its
    // frames wait for the display refresh.
    id _layerDrawableOwner;
    BOOL _layerDrawableSyncs;
    // The presentation hints as last written to the window.
    BOOL _bypassCompositorHint;
    BOOL _variableRefreshHint;

@public
    // The window's use of the window system's input method (see NSCGSInputMethod.h); nil when there is none.
    NSCGSInputMethod *_inputMethod;
    // YES while X11Display delivers FocusIn for this window (see -makeKey).
    BOOL _receivingFocus;
}

- (instancetype) initWithDelegate: (NSWindow *) delegate;
// Lets the window use the window system's input method, which is CoreGraphics' (made once; again is a no-op).
- (void) createXInputContext;
// The client's caret moved: the input method is told where its candidates belong.
- (void) updateInputMethodSpot;
- (O2Rect) frame;
- (Visual *) visual;
- (Drawable) drawable;
- (NSPoint) transformPoint: (NSPoint) pos;
// Device pixels from the window's top-left corner (as X delivers them) to
// window coordinates in points, y up (as AppKit reports them).
- (NSPoint) logicalPoint: (NSPoint) devicePoint;

// Device pixels per point, as the window system's window has it (it keeps the window's size in points when the
// scale changes, and tells the delegate).
- (CGFloat) backingScaleFactor;

- (void) setWindowIcon;

// Points to the device pixels libX11 takes. AppKit-level geometry is in points;
// every value handed to X is in device pixels. One rounding serves the X window
// and the backing surface, which the GL viewport follows.
- (NSSize) deviceSize: (NSSize) size;
- (O2Rect) deviceRect: (O2Rect) rect;
// A copy of the window's drawn pixels in a rectangle of device pixels from the top-left
// corner, or NULL if the window has no backing yet. Release it.
- (O2ImageRef) createBackingImageInDeviceRect: (O2Rect) rect;

- (Window) windowHandle;
- (BOOL) isMapped;
// Whether the window is fullscreen (_NET_WM_STATE_FULLSCREEN), as last asked
// for or as the window manager last set it.
- (BOOL) isFullscreen;

// The window's own drawable for a subwindow that covers it, NULL when it
// cannot be lent (another subwindow has it, or it has an alpha surface).
- (void *) layerDrawableFor: (id) owner;
- (void) acquireLayerDrawable: (id) owner syncsToDisplay: (BOOL) syncs;
- (void) setLayerDrawable: (id) owner syncsToDisplay: (BOOL) syncs;
- (void) releaseLayerDrawable: (id) owner;

- (void) setLastKnownCursorPosition: (CGPoint) point;

- (void) setStyleMaskInternal: (NSUInteger) styleMask force: (BOOL) force;

- (BOOL) isFullyTransparent;
- (BOOL) takeKeyRequest;
- (BOOL) isMenuOrPopup;

// What the window system said about the window (see CGSToplevelEvent), passed on to the delegate.
- (void) toplevelEvent: (const CGSToplevelEvent *) event;
@end

void CGNativeBorderFrameWidthsForStyle(NSUInteger styleMask, CGFloat *top,
                                       CGFloat *left, CGFloat *bottom,
                                       CGFloat *right);
