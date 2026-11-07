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

#import <CoreGraphics/CGWindow.h>
#import <GL/glx.h>
#import <Onyx2D/O2Geometry.h>
#import <OpenGL/CGLInternal.h>
#import <X11/Xlib.h>
#import <X11/Xresource.h>
#import <X11/Xlocale.h>

@class X11Display, CAWindowOpenGLContext, NSWindow, O2Context;

@interface X11Window : CGWindow {
    int _level; // TODO: care about this value
    Display *_display;
    XVisualInfo *_visualInfo;
    Window _window;
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
    CGPoint _lastMotionPos;
    BOOL _isModal;
    BOOL _overrideRedirect;
    BOOL _fullscreenRequested;
    BOOL _isOpaque;
    BOOL _hasAlpha;   // created with the 32-bit visual and an alpha surface
    BOOL _wasMapped;  // the visual is settled when the window is first mapped
    BOOL _hasShadow;
    BOOL _wantsInputFocus;
    BOOL _ignoresMouseEvents; // the input region currently set
    // The subwindow whose layer tree draws into _cglWindow instead of its
    // own drawable (see -[X11SubWindow sharedCGLWindow]), and whether its
    // frames wait for the display refresh.
    id _layerDrawableOwner;
    BOOL _layerDrawableSyncs;
    // The presentation hints as last written to the window.
    BOOL _bypassCompositorHint;
    BOOL _variableRefreshHint;

@public
    XIC _xic;
    // YES while X11Display delivers FocusIn for this window (see -makeKey).
    BOOL _receivingFocus;
    // -isMiniaturized as last read from _NET_WM_STATE; PropertyNotify on that
    // property, mapping and unmapping make it read again.
    BOOL _miniaturizedKnown;
    BOOL _miniaturized;
}

+ (void) removeDecorationForWindow: (Window) w onDisplay: (Display *) dpy;
- (instancetype) initWithDelegate: (NSWindow *) delegate;
- (O2Rect) frame;
- (Visual *) visual;
- (Drawable) drawable;
- (NSPoint) transformPoint: (NSPoint) pos;
- (O2Rect) transformFrame: (O2Rect) frame;

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

- (void) frameChanged;
- (void) setLastKnownCursorPosition: (CGPoint) point;

- (void) setStyleMaskInternal: (NSUInteger) styleMask force: (BOOL) force;

- (void) requestInputFocus;
- (void) mapNotified;

@end

// Whether an EWMH window manager is running on the display.
__attribute__((visibility("hidden"))) BOOL
X11WindowManagerIsRunning(Display *display);

void CGNativeBorderFrameWidthsForStyle(NSUInteger styleMask, CGFloat *top,
                                       CGFloat *left, CGFloat *bottom,
                                       CGFloat *right);
