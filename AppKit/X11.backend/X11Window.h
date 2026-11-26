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
    BOOL _fullscreenRequested;
    BOOL _fullscreenReported; // what the window manager last said, told to the delegate
    BOOL _isOpaque;
    NSSize _opaqueRegionSize; // device size of the _NET_WM_OPAQUE_REGION currently set, zero for none (see -updateOpaqueRegion)
    BOOL _hasAlpha;   // created with the 32-bit visual and an alpha surface
    BOOL _wasMapped;  // the visual is settled when the window is first mapped
    BOOL _hasShadow;
    BOOL _wantsInputFocus;
    BOOL _keyRequested; // the application asked for this window to become key and the focus has not answered yet
    BOOL _ignoresMouseEvents; // the input region currently set
    CGFloat _appliedAlpha; // the window's alpha value as last applied to the X window
    BOOL _alphaIsZero; // _appliedAlpha is 0
    BOOL _chromeless; // no window manager frame and no title bar: rounded corners and an outline (see -updateWindowShape)
    BOOL _roundedShapeSet; // the bounding shape currently has rounded corners
    BOOL _invisibleWithoutCompositor; // alpha 0 made the window invisible by shape (see -updateInvisibility)
    // The subwindow whose layer tree draws into _cglWindow instead of its
    // own drawable (see -[X11SubWindow sharedCGLWindow]), and whether its
    // frames wait for the display refresh.
    id _layerDrawableOwner;
    BOOL _layerDrawableSyncs;
    // The union of a series of Expose events received so far (see -addExposedRect:isLast:exposedUnion:).
    O2Rect _pendingExpose;
    BOOL _hasPendingExpose;
    // The presentation hints as last written to the window.
    BOOL _bypassCompositorHint;
    BOOL _variableRefreshHint;

@public
    XIC _xic;
    // Set once the context delivers the composition through callbacks (on-the-spot
    // preedit), with the callbacks and the composition's code points and caret.
    BOOL _onTheSpotPreedit;
    XIMCallback _preeditCallbacks[4];
    NSMutableData *_preedit;
    int _preeditCaret;
    // YES while X11Display delivers FocusIn for this window (see -makeKey).
    BOOL _receivingFocus;
    // -isMiniaturized as last read from _NET_WM_STATE; PropertyNotify on that
    // property, mapping and unmapping make it read again.
    BOOL _miniaturizedKnown;
    BOOL _miniaturized;
    // The state the delegate was last told of (platformWindowMiniaturized: and platformWindowDeminiaturized:).
    BOOL _miniaturizedReported;
    // Whether X11Display found the window covered (see X11Occlusion.h).
    BOOL _occluded;
    // Geometry of the last ConfigureNotify (see -noteConfigureGeometryChanged:).
    BOOL _configureKnown;
    int _configureX, _configureY, _configureWidth, _configureHeight;
}

+ (void) removeDecorationForWindow: (Window) w onDisplay: (Display *) dpy;
- (instancetype) initWithDelegate: (NSWindow *) delegate;
- (void) createXInputContext;
// The input method's composition, as its preedit callbacks report it, passed on to the
// text input client of the window's first responder (see NSTextInputContext).
- (void) preeditReplaceCharactersFrom: (int) first
                               length: (int) length
                             withText: (NSString *) text
                                caret: (int) caret;
- (void) preeditMoveCaretTo: (int) position direction: (XIMCaretDirection) direction;
- (void) preeditDone;
- (void) updateInputMethodSpot;
- (O2Rect) frame;
- (Visual *) visual;
- (Drawable) drawable;
- (NSPoint) transformPoint: (NSPoint) pos;
- (O2Rect) transformFrame: (O2Rect) frame;
// Device pixels from the window's top-left corner (as X delivers them) to
// window coordinates in points, y up (as AppKit reports them).
- (NSPoint) logicalPoint: (NSPoint) devicePoint;

// Device pixels per point, read from the display so that this window and its
// NSScreen always report the same value (-[NSWindow backingScaleFactor] prefers
// the platform window's answer, so a window that disagreed with its screen
// would win).
- (CGFloat) backingScaleFactor;

// Called by the display after it re-read a changed scale (see
// -[X11Display reevaluateBackingScale]).
- (void) displayBackingScaleChangedFrom: (CGFloat) oldScale;
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
// What the stacking of unmanaged and managed windows by level looks at (see
// X11LevelStacking.h). A menu, pop-up and the menu bar are not stacked by
// level: they are above the windows they belong to by their own means.
- (int) stackingLevel;
- (BOOL) isUnmanaged;
- (BOOL) takesPartInLevelStacking;
// Restacks the windows of the other kind around this one after it was
// ordered to the front, mapped or given another level.
- (void) restackForLevels;
- (BOOL) isMapped;
- (void) setOccluded: (BOOL) occluded;
// Records the geometry of a ConfigureNotify; NO when it repeats the previous one.
- (BOOL) noteConfigureGeometryChanged: (XConfigureEvent *) event;
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
- (BOOL) isFullyTransparent;
- (BOOL) takeKeyRequest;
- (BOOL) isMenuOrPopup;
- (void) mapNotified;

// X reports an exposed area as a series of rectangles. Collects them and, for the last one of
// the series, returns YES with their union in *exposedUnion.
- (BOOL) addExposedRect: (O2Rect) rect isLast: (BOOL) last exposedUnion: (O2Rect *) exposedUnion;
@end

// Whether an EWMH window manager is running on the display.
__attribute__((visibility("hidden"))) BOOL
X11WindowManagerIsRunning(Display *display);

void CGNativeBorderFrameWidthsForStyle(NSUInteger styleMask, CGFloat *top,
                                       CGFloat *left, CGFloat *bottom,
                                       CGFloat *right);
