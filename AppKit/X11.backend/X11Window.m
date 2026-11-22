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

#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import "X11Touch.h"
#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputBackend.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>
#import "../NSWindow-Private.h"
#import "../DarlingWindowPresentation.h"
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#import <Foundation/NSMutableData.h>
#import <Foundation/NSProcessInfo.h>
#import <Onyx2D/O2BitmapContext.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2ImageSource.h>
#import <Onyx2D/O2Surface.h>
#import <QuartzCore/CAWindowOpenGLContext.h>

#import "X11Display.h"
#import "../../CoreGraphics/X11.backend/X11Monitors.h"
#import "../../CoreGraphics/X11.backend/X11WindowOwner.h"
#import "X11Fullscreen.h"
#import "X11InputShape.h"
#import "X11RoundedShape.h"
#import "X11InvisibleWindow.h"
#import "X11SubWindow.h"
#import "X11Window.h"
#import "X11AppMenu.h"
#import <X11/Xatom.h>
#import <X11/Xutil.h>
#include <math.h>
#include <wchar.h>

// The visual of opaque windows. Rendering goes through EGL, and a visual that
// glXChooseVisual picks can be one that only GLX can draw to (NVIDIA's EGL
// rejects such visuals with EGL_BAD_CONFIG), so the default visual comes first
// when it is TrueColor with at least 24 bits.
static XVisualInfo *X11OpaqueVisualInfo(Display *display) {
    static XVisualInfo *visualInfo;

    if (visualInfo != NULL)
        return visualInfo;

    int screen = DefaultScreen(display);
    XVisualInfo visualTemplate = {
        .visualid = XVisualIDFromVisual(DefaultVisual(display, screen)),
        .screen = screen,
    };
    int count = 0;
    visualInfo = XGetVisualInfo(display, VisualIDMask | VisualScreenMask,
                                &visualTemplate, &count);
    if (visualInfo != NULL &&
        (visualInfo->class != TrueColor || visualInfo->depth < 24)) {
        XFree(visualInfo);
        visualInfo = NULL;
    }

    if (visualInfo == NULL) {
        int attributes[] = {GLX_RGBA,       GLX_DOUBLEBUFFER, GLX_RED_SIZE,
                            4,              GLX_GREEN_SIZE,   4,
                            GLX_BLUE_SIZE,  4,                GLX_DEPTH_SIZE,
                            4,              None};
        visualInfo = glXChooseVisual(display, screen, attributes);
        if (visualInfo == NULL)
            NSLog(@"glXChooseVisual failed at %s %d", __FILE__, __LINE__);
    }
    return visualInfo;
}

// A 32-bit TrueColor visual with an alpha channel, for windows that let what
// is behind them show through, or NULL if the screen has none.
static XVisualInfo *X11AlphaVisualInfo(Display *display) {
    static XVisualInfo visualInfo;
    static BOOL looked;

    if (!looked) {
        looked = YES;
        XVisualInfo visualTemplate = {
            .screen = DefaultScreen(display),
            .depth = 32,
            .class = TrueColor,
        };
        int count = 0;
        XVisualInfo *visuals = XGetVisualInfo(
                display, VisualScreenMask | VisualDepthMask | VisualClassMask,
                &visualTemplate, &count);
        for (int i = 0; i < count && visualInfo.visual == NULL; i++) {
            if (visuals[i].red_mask == 0xff0000 &&
                visuals[i].green_mask == 0x00ff00 &&
                visuals[i].blue_mask == 0x0000ff)
                visualInfo = visuals[i];
        }
        if (visuals != NULL)
            XFree(visuals);
    }
    return visualInfo.visual != NULL ? &visualInfo : NULL;
}

// Set once EGL could not create an alpha surface for the alpha visual; later
// windows are then created opaque straight away.
static BOOL alphaSurfaceFailed;

// Whether the input method offers the on-the-spot preedit style: it then reports the
// composition through callbacks and the application draws it itself.
static BOOL inputMethodHasPreeditCallbacks(XIM xim) {
    XIMStyles *styles = NULL;
    BOOL found = NO;

    if (xim == NULL)
        return NO;
#if defined(DARLING) && defined(__arm64__)
    // Variadic, see createInputContext() below.
    char *failed = ((char *(*)(XIM, const char *, void *, void *)) XGetIMValues)(
            xim, XNQueryInputStyle, &styles, NULL);
#else
    char *failed = XGetIMValues(xim, XNQueryInputStyle, &styles, NULL);
#endif
    if (failed != NULL || styles == NULL)
        return NO;
    for (unsigned short i = 0; i < styles->count_styles; i++) {
        if (styles->supported_styles[i] == (XIMPreeditCallbacks | XIMStatusNothing))
            found = YES;
    }
    XFree(styles);
    return found;
}

// Sets the preedit attribute list `list` on the context. Returns whether Xlib accepted it.
static BOOL setPreeditAttributes(XIC ic, XVaNestedList list) {
#if defined(DARLING) && defined(__arm64__)
    char *failed = ((char *(*)(XIC, const char *, void *, void *)) XSetICValues)(
            ic, XNPreeditAttributes, list, NULL);
#else
    char *failed = XSetICValues(ic, XNPreeditAttributes, list, NULL);
#endif
    XFree(list);
    return failed == NULL;
}

static XVaNestedList preeditCallbackList(const char *name1, XIMCallback *cb1,
                                         const char *name2, XIMCallback *cb2) {
#if defined(DARLING) && defined(__arm64__)
    return ((XVaNestedList (*)(int, const char *, void *, const char *, void *, void *))
            XVaCreateNestedList)(0, name1, cb1, name2, cb2, NULL);
#else
    return XVaCreateNestedList(0, name1, cb1, name2, cb2, NULL);
#endif
}

// An input context for the window. With an input method that supports on-the-spot preedit the
// composition is delivered through the callbacks in `callbacks` (client data: the window);
// otherwise the input method shows its own preedit and status.
static XIC createInputContext(XIM xim, Window window, XIMCallback callbacks[4], BOOL *onTheSpot) {
    XIC ic;
    BOOL wantsCallbacks = inputMethodHasPreeditCallbacks(xim);

    *onTheSpot = NO;
    long style = wantsCallbacks ? (XIMPreeditCallbacks | XIMStatusNothing)
                                : (XIMPreeditNothing | XIMStatusNothing);
#if defined(DARLING) && defined(__arm64__)
    // XCreateIC() is variadic and lives in the native (Linux) libX11. Darwin arm64 passes
    // variadic arguments on the stack, Linux arm64 in registers, so call it through a
    // non-variadic prototype: all 8 arguments then go in x0-x7, where libX11 reads them.
    ic = ((XIC (*)(XIM, const char *, long, const char *, Window, const char *, Window, void *)) XCreateIC)(
        xim,
        XNInputStyle, style,
        XNClientWindow, window,
        XNFocusWindow, window,
        NULL);
#else
    ic = XCreateIC(xim,
        XNInputStyle, style,
        XNClientWindow, window,
        XNFocusWindow, window,
        NULL);
#endif
    if (ic == NULL || !wantsCallbacks)
        return ic;

    // The callbacks are set after creation, two to a call, so that no call needs more
    // arguments than a non-variadic arm64 call can pass in registers.
    if (setPreeditAttributes(ic, preeditCallbackList(XNPreeditStartCallback, &callbacks[0],
                                                     XNPreeditDoneCallback, &callbacks[1])) &&
        setPreeditAttributes(ic, preeditCallbackList(XNPreeditDrawCallback, &callbacks[2],
                                                     XNPreeditCaretCallback, &callbacks[3]))) {
        *onTheSpot = YES;
        return ic;
    }

    // Without the callbacks the composition would be invisible: use the input method's own.
    XDestroyIC(ic);
#if defined(DARLING) && defined(__arm64__)
    return ((XIC (*)(XIM, const char *, long, const char *, Window, const char *, Window, void *)) XCreateIC)(
        xim,
        XNInputStyle, (long) (XIMPreeditNothing | XIMStatusNothing),
        XNClientWindow, window,
        XNFocusWindow, window,
        NULL);
#else
    return XCreateIC(xim,
        XNInputStyle, (long) (XIMPreeditNothing | XIMStatusNothing),
        XNClientWindow, window,
        XNFocusWindow, window,
        NULL);
#endif
}

// NSView replaces the user CTM whenever it locks focus, so the backing scale has to
// live in the device transform, as WaylandDrawingContext does (see
// AppKit/Wayland.backend/WaylandWindow.m): O2ContextSetCTM rebuilds the device
// transform from _userToDeviceTransform on every call, so a scale held anywhere
// else is discarded on the first lock.
@interface X11DrawingContext : O2Context_builtin_FT
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize;
@end

@implementation X11DrawingContext
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize {
    if ((self = [super initWithSurface: surface flipped: NO]) != nil) {
        CGFloat sx = O2SurfaceGetWidth(surface) / logicalSize.width;
        CGFloat sy = O2SurfaceGetHeight(surface) / logicalSize.height;
        _userToDeviceTransform = O2AffineTransformMake(sx, 0, 0, -sy, 0,
                O2SurfaceGetHeight(surface));
        O2ContextSetCTM(self, O2AffineTransformIdentity);
    }
    return self;
}
@end

@implementation X11Window

#pragma mark - Input method composition

// The composition is held as the code points the input method sent: its draw callback
// replaces a range of characters, counted in characters, not UTF-16 units.

static int preeditStartCallback(XIC ic, XPointer clientData, XPointer callData) {
    // The composition may be any length.
    return -1;
}

static void preeditDoneCallback(XIC ic, XPointer clientData, XPointer callData) {
    [(X11Window *) clientData preeditDone];
}

static void preeditDrawCallback(XIC ic, XPointer clientData, XPointer callData) {
    XIMPreeditDrawCallbackStruct *draw = (XIMPreeditDrawCallbackStruct *) callData;
    NSString *text = nil;

    if (draw == NULL)
        return;
    if (draw->text != NULL) {
        if (draw->text->encoding_is_wchar) {
            // wchar_t is 32 bits wide on the host the library runs on.
            const wchar_t *wide = draw->text->string.wide_char;
            if (wide != NULL)
                text = [[[NSString alloc] initWithBytes: wide
                                                 length: wcslen(wide) * sizeof(wchar_t)
                                               encoding: NSUTF32LittleEndianStringEncoding] autorelease];
        } else if (draw->text->string.multi_byte != NULL) {
            // The locale's multi-byte encoding is UTF-8, as for Xutf8LookupString().
            text = [NSString stringWithUTF8String: draw->text->string.multi_byte];
        }
    }
    [(X11Window *) clientData preeditReplaceCharactersFrom: draw->chg_first
                                                    length: draw->chg_length
                                                  withText: text ?: @""
                                                     caret: draw->caret];
}

static void preeditCaretCallback(XIC ic, XPointer clientData, XPointer callData) {
    XIMPreeditCaretCallbackStruct *caret = (XIMPreeditCaretCallbackStruct *) callData;

    if (caret != NULL)
        [(X11Window *) clientData preeditMoveCaretTo: caret->position
                                           direction: caret->direction];
}

- (void) createXInputContext {
    X11Display *display = (X11Display *) [NSDisplay currentDisplay];

    _preeditCallbacks[0] = (XIMCallback) { (XPointer) self, (XIMProc) preeditStartCallback };
    _preeditCallbacks[1] = (XIMCallback) { (XPointer) self, (XIMProc) preeditDoneCallback };
    _preeditCallbacks[2] = (XIMCallback) { (XPointer) self, (XIMProc) preeditDrawCallback };
    _preeditCallbacks[3] = (XIMCallback) { (XPointer) self, (XIMProc) preeditCaretCallback };
    _xic = createInputContext(display->_xim, _window, _preeditCallbacks, &_onTheSpotPreedit);
}

- (NSTextInputContext *) textInputContext {
    return [NSTextInputContext inputContextForWindow: [self delegate]];
}

- (NSString *) preeditString {
    NSUInteger count = [_preedit length] / sizeof(uint32_t);

    if (count == 0)
        return @"";
    return [[[NSString alloc] initWithBytes: [_preedit bytes]
                                     length: count * sizeof(uint32_t)
                                   encoding: NSUTF32LittleEndianStringEncoding] autorelease];
}

// The caret as a UTF-16 offset in the composition string.
- (NSUInteger) preeditCaretUTF16Offset {
    const uint32_t *chars = [_preedit bytes];
    NSUInteger count = [_preedit length] / sizeof(uint32_t);
    NSUInteger offset = 0;

    for (NSUInteger i = 0; i < _preeditCaret && i < count; i++)
        offset += chars[i] > 0xFFFF ? 2 : 1;
    return offset;
}

- (void) sendPreeditToClient {
    NSTextInputContext *context = [self textInputContext];
    NSString *text = [self preeditString];

    if ([text length] == 0) {
        [context cancelComposition];
        return;
    }
    [context updateComposition: text
                     selection: NSMakeRange([self preeditCaretUTF16Offset], 0)];
}

- (void) preeditReplaceCharactersFrom: (int) first
                               length: (int) length
                             withText: (NSString *) text
                                caret: (int) caret {
    NSData *incoming = [text dataUsingEncoding: NSUTF32LittleEndianStringEncoding];
    NSUInteger count = [_preedit length] / sizeof(uint32_t);

    if (_preedit == nil)
        _preedit = [[NSMutableData alloc] init];
    // The server's range is trusted only as far as it lies in the string.
    if (first < 0 || (NSUInteger) first > count)
        first = (int) count;
    if (length < 0 || (NSUInteger) (first + length) > count)
        length = (int) (count - first);
    [_preedit replaceBytesInRange: NSMakeRange(first * sizeof(uint32_t), length * sizeof(uint32_t))
                        withBytes: [incoming bytes]
                           length: [incoming length]];
    count = [_preedit length] / sizeof(uint32_t);
    _preeditCaret = caret < 0 ? 0 : ((NSUInteger) caret > count ? (int) count : caret);
    [self sendPreeditToClient];
}

- (void) preeditMoveCaretTo: (int) position direction: (XIMCaretDirection) direction {
    switch (direction) {
    case XIMForwardChar:
        position = _preeditCaret + 1;
        break;
    case XIMBackwardChar:
        position = _preeditCaret - 1;
        break;
    case XIMAbsolutePosition:
        break;
    default:
        return; // Word and line moves: the caret stays where the last draw put it.
    }
    NSUInteger count = [_preedit length] / sizeof(uint32_t);
    _preeditCaret = position < 0 ? 0 : ((NSUInteger) position > count ? (int) count : position);
    [self sendPreeditToClient];
}

// The composition ended, by commit or by cancel; the committed text, if any, arrives as a key
// event or as a commit and replaces nothing that is still marked.
- (void) preeditDone {
    [_preedit setLength: 0];
    _preeditCaret = 0;
    [[self textInputContext] cancelComposition];
}

// Gives the input method the spot where the client's composition is, so that it places its
// candidate window there.
- (void) updateInputMethodSpot {
    if (_xic == NULL || !_onTheSpotPreedit)
        return;

    NSWindow *window = [self delegate];
    NSRect rect = [[self textInputContext] candidateRectOnScreen];
    if (window == nil || NSEqualRects(rect, NSZeroRect))
        return;

    rect = [window convertRectFromScreen: rect];
    CGFloat scale = [self backingScaleFactor];
    // The bottom-left corner of the caret rectangle: the baseline side, in X's device pixels.
    NSPoint spot = [self transformPoint: NSMakePoint(NSMinX(rect), NSMinY(rect))];
    XPoint point = { (short) lround(spot.x * scale), (short) lround(spot.y * scale) };
    // Only some styles take a spot; the error for one that does not is of no interest.
#if defined(DARLING) && defined(__arm64__)
    XVaNestedList list = ((XVaNestedList (*)(int, const char *, void *, void *))
            XVaCreateNestedList)(0, XNSpotLocation, &point, NULL);
#else
    XVaNestedList list = XVaCreateNestedList(0, XNSpotLocation, &point, NULL);
#endif
    setPreeditAttributes(_xic, list);
}

+ (Visual *) visual {
    static Visual *ret = NULL;

    if (!ret) {
        int visuals_matched, i;
        XVisualInfo match = {0};
        Display *dpy = [(X11Display *) [NSDisplay currentDisplay] display];

        XVisualInfo *info = XGetVisualInfo(dpy, 0, &match, &visuals_matched);

        for (i = 0; i < visuals_matched; i++) {
            if (info[i].depth == 32 && (info[i].red_mask == 0xff0000 &&
                                        info[i].green_mask == 0x00ff00 &&
                                        info[i].blue_mask == 0x0000ff)) {
                ret = info[i].visual;
            }
        }
        XFree(info);
        if (!ret)
            ret = DefaultVisual(dpy, DefaultScreen(dpy));
    }

    return ret;
}

// The edge lengths the window icon is offered at. The window manager picks the one that fits its
// title bar, task bar or switcher best.
static const int WindowIconSides[] = {16, 32, 48, 64, 128, 256};

// _NET_WM_ICON: for each size the width and height, then width * height ARGB pixels (not premultiplied),
// every value in a long as the property is a 32 bit format. nil when the application has no icon.
static NSData *makeWindowIcon(X11Display *display) {
    NSMutableData *res = nil;

    for (size_t i = 0; i < sizeof(WindowIconSides) / sizeof(WindowIconSides[0]); i++) {
        int side = WindowIconSides[i];
        NSData *pixels = [display applicationIconPixelsOfSide: side];
        if (pixels == nil)
            return nil;
        if (res == nil)
            res = [NSMutableData data];

        long header[2] = {side, side};
        [res appendBytes: header length: sizeof(header)];
        NSMutableData *data = [NSMutableData dataWithLength: (size_t) side * side * sizeof(long)];
        long *out = (long *) [data mutableBytes];
        const uint32_t *in = (const uint32_t *) [pixels bytes];
        for (int p = 0; p < side * side; p++) {
            uint32_t argb = in[p];
            uint32_t alpha = argb >> 24;
            if (alpha != 0 && alpha != 255) {
                uint32_t red = MIN(255u, ((argb >> 16) & 0xff) * 255 / alpha);
                uint32_t green = MIN(255u, ((argb >> 8) & 0xff) * 255 / alpha);
                uint32_t blue = MIN(255u, (argb & 0xff) * 255 / alpha);
                argb = (alpha << 24) | (red << 16) | (green << 8) | blue;
            }
            out[p] = argb;
        }
        [res appendData: data];
    }
    return res;
}

// Sets _NET_WM_ICON from the application icon, or removes it when there is none (so the window manager
// falls back to its own choice).
- (void) setWindowIcon {
    Atom property = XInternAtom(_display, "_NET_WM_ICON", False);
    NSData *data = makeWindowIcon((X11Display *) [NSDisplay currentDisplay]);

    if (data == nil) {
        XDeleteProperty(_display, _window, property);
        return;
    }
    XChangeProperty(_display, _window, property, XInternAtom(_display, "CARDINAL", False), 32, PropModeReplace,
                    [data bytes], [data length] / sizeof(long));
}

- (instancetype) initWithDelegate: (NSWindow *) delegate {
    _delegate = delegate;
    _level = [delegate level];
    _styleMask = [delegate styleMask];
    _backingType = (CGSBackingStoreType)[delegate backingType];
    _deviceDictionary = [NSMutableDictionary new];

    X11Display* x11disp = (X11Display *) [NSDisplay currentDisplay];
    _display = [x11disp display];

    _frame = [self transformFrame: [delegate frame]];
    BOOL isPanel = [delegate isKindOfClass: [NSPanel class]];
    BOOL isSheetPanel = isPanel && (_styleMask & NSDocModalWindowMask);
    if (isSheetPanel)
        _styleMask = NSBorderlessWindowMask;
    _hasAlpha = [self wantsAlphaVisual];
    _appliedAlpha = 1.0;
    if (![self createXWindow]) {
        [self release];
        return nil;
    }

    return self;
}

// Creates the X window for the current _frame, _styleMask and _hasAlpha, and
// everything attached to it. Without an alpha surface for the alpha visual
// the window is created opaque instead.
- (BOOL) createXWindow {
    NSWindow *delegate = _delegate;
    X11Display *x11disp = (X11Display *) [NSDisplay currentDisplay];
    BOOL isPanel = [delegate isKindOfClass: [NSPanel class]];
    BOOL isSheetPanel =
            isPanel && ([delegate styleMask] & NSDocModalWindowMask);

    XSetWindowAttributes xattr;
    unsigned long xattr_mask;
    // Only windows that must stay out of the window manager's hands are
    // unmanaged: menus, popups, sheets and anything that cannot become key
    // (NSWindow answers NO for a borderless window unless its class overrides
    // -canBecomeKeyWindow, so only such windows change). A borderless
    // window that can become key (a borderless fullscreen game, a custom-chrome
    // app window) is a normal application window; left override-redirect it never
    // receives keyboard focus from a compositor and cannot be made fullscreen.
    // The menu bar window is a dock window: the window manager has to manage
    // it for its strut to count.
    _dock = [delegate isKindOfClass: [NSMenuBarWindow class]];
    // Menu and pop-up windows are panels, but they are the first kind named
    // above: a managed window would take the input focus from the window the
    // menu belongs to when it is clicked, and the application would see
    // itself deactivated while its own menu is open. Being unmanaged, they
    // leave the focus where it is, and the keys typed while a menu is open
    // still go to the window that has it.
    BOOL isMenuWindow = [delegate isKindOfClass: [NSMenuWindow class]] ||
                        [delegate isKindOfClass: [NSPopUpWindow class]];
    _menuWindow = isMenuWindow;
    // Borderless means no frame of any kind; a miniaturizable or closable bit alone does not give a
    // window a frame, so a pop-up created with such a mask is as borderless as one with none.
    BOOL borderless = (_styleMask & ~(NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskClosable)) ==
                      NSBorderlessWindowMask;
    xattr.override_redirect =
            (borderless && !_dock &&
             (isMenuWindow || (!isPanel && ![delegate canBecomeKeyWindow])))
                    ? True
                    : False;
    if (isSheetPanel) {
        xattr.override_redirect = True;
    }
    _overrideRedirect = xattr.override_redirect;
    xattr.border_pixel = 0;

    for (;;) {
        _visualInfo = _hasAlpha ? X11AlphaVisualInfo(_display)
                                : X11OpaqueVisualInfo(_display);
        if (_visualInfo == NULL)
            return NO;

        xattr.colormap = XCreateColormap(
                _display, RootWindow(_display, _visualInfo->screen),
                _visualInfo->visual, AllocNone);
        // A window of another depth than its parent needs a border pixel of
        // its own, or creating it fails with BadMatch.
        xattr_mask = CWOverrideRedirect | CWColormap |
                     (_hasAlpha ? CWBorderPixel : 0);

        // _frame is in points; X wants device pixels.
        O2Rect deviceFrame = [self deviceRect: _frame];
        _window = XCreateWindow(
                _display, DefaultRootWindow(_display), deviceFrame.origin.x,
                deviceFrame.origin.y, deviceFrame.size.width,
                deviceFrame.size.height, 0, _visualInfo->depth, InputOutput, _visualInfo->visual,
                xattr_mask, &xattr);
        if (!_hasAlpha) {
            _cglWindow = CGLGetWindow((void *) _window);
            break;
        }

        // EGL needs a configuration with alpha for this visual; without one,
        // draw the window opaque rather than not at all.
        _cglWindow = CGLGetWindowWithAlpha((void *) _window,
                                           _visualInfo->visualid);
        if (_cglWindow != NULL)
            break;
        XDestroyWindow(_display, _window);
        XFreeColormap(_display, xattr.colormap);
        _hasAlpha = NO;
        alphaSurfaceFailed = YES;
    }

    [self syncDelegateProperties];

    Atom atm = XInternAtom(_display, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(_display, _window, &atm, 1);

    const char *name = [[[NSProcessInfo processInfo] processName] UTF8String];

    XClassHint classHint = {.res_name = (char *) name,
                            .res_class = (char *) name};
    XSetClassHint(_display, _window, &classHint);

    // _NET_WM_PID and WM_CLIENT_MACHINE, so that other clients, and other
    // Darling processes listing windows, know whose window this is.
    X11WindowOwnerPublish(_display, _window);

    // Until the first frame, a translucent window shows its background:
    // make that transparent rather than black.
    if (_hasAlpha)
        XSetWindowBackground(_display, _window, 0);
    else
        XSetWindowBackgroundPixmap(_display, _window, None);

    [self updateWindowManagerHints];

    [self createXInputContext];

    [(X11Display *) [NSDisplay currentDisplay] setWindow: self forID: _window];

    // A window of the application's own, not a popup or its menu bar, shows
    // the application's menu in the desktop's global menu.
    if (!_dock && !_overrideRedirect && !isMenuWindow)
        [[x11disp appMenu] windowCreated: _window];

    [self setStyleMaskInternal: _styleMask force: YES];

    [self setWindowIcon];

    return YES;
}

// What the window manager is told about the window, from what the window is (see
// DarlingWindowPresentation.h for the rule and the documentation it rests on): its type, whether it
// is listed in a task bar or pager, which window it belongs to, whether it takes the input focus,
// and that it is positioned by the application. Asked at creation and again just before each
// mapping, as a child window is attached and a window becomes the main window after it was created.
// A window manager reads these when the window is mapped, and a window whose properties change
// while it is mapped is not asked to move or restack.
- (void) updateWindowManagerHints {
    NSWindow *delegate = _delegate;
    BOOL isPanel = [delegate isKindOfClass: [NSPanel class]];
    BOOL isMenu = [delegate isKindOfClass: [NSMenuWindow class]];
    BOOL isPopUp = [delegate isKindOfClass: [NSPopUpWindow class]];
    DarlingWindowPresentation presentation = DarlingWindowPresentationApplication;
    if (!_dock && [delegate respondsToSelector: @selector(_windowPresentation)])
        presentation = (DarlingWindowPresentation) [delegate _windowPresentation];
    BOOL canBecomeKey = [delegate canBecomeKeyWindow];

    _isModal = [delegate isSheet] || [NSApp modalWindow] == delegate;
    // FIXME: There should be no need for this.
    _isModal |= [delegate isKindOfClass: NSClassFromString(@"NSSavePanel")];

    const char *windowType;
    BOOL isTransient = YES;
    if (_isModal) {
        windowType = "_NET_WM_WINDOW_TYPE_DIALOG";
    } else if (_dock) {
        windowType = "_NET_WM_WINDOW_TYPE_DOCK";
        isTransient = NO;
    } else if (isMenu) {
        // EWMH: _MENU is for torn-off managed windows; the menus of a menu bar
        // are dropdown menus, which are typically unmanaged.
        windowType = "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU";
    } else if (isPopUp) {
        windowType = "_NET_WM_WINDOW_TYPE_POPUP_MENU";
    } else if (presentation == DarlingWindowPresentationPopup) {
        // A tool tip never takes the focus and does not react to the mouse; any other pop-up is a
        // pop-up menu to the window manager.
        windowType = !canBecomeKey && [delegate ignoresMouseEvents] ? "_NET_WM_WINDOW_TYPE_TOOLTIP"
                                                                    : "_NET_WM_WINDOW_TYPE_POPUP_MENU";
    } else if (isPanel) {
        windowType = "_NET_WM_WINDOW_TYPE_UTILITY";
    } else if (presentation == DarlingWindowPresentationAuxiliary) {
        windowType = "_NET_WM_WINDOW_TYPE_NORMAL";
    } else {
        windowType = "_NET_WM_WINDOW_TYPE_NORMAL";
        isTransient = NO;
    }
    long windowTypeAtom = (long) XInternAtom(_display, windowType, False);
    XChangeProperty(_display, _window,
                    XInternAtom(_display, "_NET_WM_WINDOW_TYPE", False),
                    XA_ATOM, 32, PropModeReplace,
                    (const unsigned char *) &windowTypeAtom, 1);

    _skipTaskbar = !_dock && presentation != DarlingWindowPresentationApplication;

    // The window a window belongs to: the one it is attached to as a child window, else the
    // application's main window. A window must not become its own ancestor.
    X11Window *parent = nil;
    if (isTransient) {
        NSWindow *candidates[3] = {[delegate parentWindow], [NSApp mainWindow], [NSApp keyWindow]};
        for (int i = 0; i < 3 && parent == nil; i++) {
            X11Window *platform = (X11Window *) [candidates[i] platformWindow];
            if (![platform isKindOfClass: [X11Window class]] || platform == self || platform->_window == 0)
                continue;
            const void *ancestors[16];
            int count = 0;
            for (X11Window *up = platform->_transientParent; up != nil && count < 16; up = up->_transientParent)
                ancestors[count++] = up;
            if (DarlingWindowParentAllowed(self, platform, ancestors, count))
                parent = platform;
        }
    }
    if (parent != _transientParent) {
        [parent retain];
        [_transientParent release];
        _transientParent = parent;
    }
    if (parent != nil)
        XSetTransientForHint(_display, _window, parent->_window);
    else
        XDeleteProperty(_display, _window, XA_WM_TRANSIENT_FOR);

    // Whether the window takes the input focus when the window manager maps it (ICCCM 4.1.7). A
    // window that is not an application window, or one of an application that is not active, is
    // not given the focus by being shown either: the user time 0 says no user action caused it
    // (EWMH _NET_WM_USER_TIME). Making it the key window
    // asks for the focus explicitly (-requestInputFocus).
    XWMHints hints = {0};
    hints.flags = InputHint;
    hints.input = canBecomeKey ? True : False;
    XSetWMHints(_display, _window, &hints);
    Atom userTime = XInternAtom(_display, "_NET_WM_USER_TIME", False);
    // An application that is not active does not take the focus by showing a window either.
    if (!_dock && (presentation != DarlingWindowPresentationApplication || ![NSApp _mayTakeInputFocus])) {
        unsigned long zero = 0;
        XChangeProperty(_display, _window, userTime, XA_CARDINAL, 32, PropModeReplace,
                        (const unsigned char *) &zero, 1);
    } else {
        XDeleteProperty(_display, _window, userTime);
    }
    [self updateSizeHints: _styleMask];
}

// The window's presentation can change while it is on screen (its collection behavior): tell the window
// manager whether the window is listed in the task bar and pager now.
- (void) presentationChanged {
    if (!_mapped || _window == 0 || _dock)
        return;
    BOOL wasSkipping = _skipTaskbar;
    [self updateWindowManagerHints];
    if (_skipTaskbar == wasSkipping)
        return;
    XEvent event = {0};
    event.xclient.type = ClientMessage;
    event.xclient.window = _window;
    event.xclient.message_type = XInternAtom(_display, "_NET_WM_STATE", False);
    event.xclient.format = 32;
    event.xclient.data.l[0] = _skipTaskbar ? 1 : 0; // add or remove
    event.xclient.data.l[1] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_TASKBAR", False);
    event.xclient.data.l[2] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_PAGER", False);
    event.xclient.data.l[3] = 1; // source indication: application
    XSendEvent(_display, DefaultRootWindow(_display), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &event);
    XFlush(_display);
}

- (void) dealloc {
    [self invalidate];
    [_preedit release];
    [_deviceDictionary release];
    [super dealloc];
}

- (NSUInteger) styleMask {
    return _styleMask;
}

// The mask is passed in rather than read from _styleMask because
// -setStyleMask: hands the new mask here before it stores it. The hinted size is
// _frame's, so a caller that just resized has to re-issue these.
- (void) updateSizeHints: (NSUInteger) mask {
    XSizeHints *sh = XAllocSizeHints();
    if (mask & NSWindowStyleMaskResizable) {
        // Make resizable
        sh->flags = 0;
    } else {
        // Make non-resizable
        sh->flags = PMinSize | PMaxSize;
        // WM size hints are in device pixels too.
        NSSize device = [self deviceSize: _frame.size];
        sh->min_width = sh->max_width = device.width;
        sh->min_height = sh->max_height = device.height;
    }

    // AppKit always gives a window an explicit frame, so every managed window positions itself:
    // say so, or a window manager may place it as it likes, typically in the middle of the screen
    // or over its parent (ICCCM 4.1.2.3).
    if (!_overrideRedirect)
        sh->flags |= USPosition | PPosition;

    // The frame is the client window's own rectangle, so a move must put the
    // client window, not the window manager's frame around it, where the frame
    // says (ICCCM 4.1.2.3, StaticGravity); with the default NorthWestGravity a
    // decorated window lands lower and to the right by the size of its frame.
    if (!_overrideRedirect) {
        sh->flags |= PWinGravity;
        sh->win_gravity = StaticGravity;
    }

    XSetWMSizeHints(_display, _window, sh, XA_WM_NORMAL_HINTS);
    XFree(sh);
}

// Whether the window manager should hold this window fullscreen: the
// application asked for it, or it is a managed borderless window sitting exactly on
// a monitor (see X11Fullscreen.h). `frame` is in Cocoa's global space, like
// -frame.
- (BOOL) wantsFullscreenWithStyleMask: (NSUInteger) mask frame: (O2Rect) frame {
    BOOL styleFullScreen = (mask & NSWindowStyleMaskFullScreen) != 0;
    BOOL titled = (mask & NSWindowStyleMaskTitled) != 0;
    BOOL coversMonitor = NO;
    // The monitor test is a server round trip; skip it when it cannot change the answer.
    if (!_overrideRedirect && !styleFullScreen && !titled) {
        O2Rect device = [self deviceRect: [self transformFrame: frame]];
        X11FullscreenRect rect = {(int) device.origin.x, (int) device.origin.y,
                                  (unsigned int) device.size.width,
                                  (unsigned int) device.size.height};
        coversMonitor = X11FullscreenRectIsMonitor(_display, rect);
    }
    return X11FullscreenWanted(_overrideRedirect, styleFullScreen, titled,
                               coversMonitor);
}

- (void) requestFullscreen: (BOOL) fullscreen force: (BOOL) force {
    if (!_mapped) {
        long states[4];
        int states_cnt = 0;
        if (_skipTaskbar) {
            states[states_cnt++] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_TASKBAR", False);
            states[states_cnt++] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_PAGER", False);
        }
        if (_isModal) {
            states[states_cnt++] =
                    (long) XInternAtom(_display, "_NET_WM_STATE_MODAL", False);
        }
        if (fullscreen) {
            states[states_cnt++] = (long) XInternAtom(
                    _display, "_NET_WM_STATE_FULLSCREEN", False);
        }
        XChangeProperty(_display, _window,
                        XInternAtom(_display, "_NET_WM_STATE", False), XA_ATOM,
                        32, PropModeReplace, (const unsigned char *) states,
                        states_cnt);
    } else if (force || fullscreen != _fullscreenRequested) {
        X11FullscreenRequest(_display, _window, fullscreen);
    }
    _fullscreenRequested = fullscreen;
    [self updateLayerPresentationHints];
}

// The window manager changes _NET_WM_STATE on its own too (it leaves fullscreen
// on a keybinding), so follow it: a later setFrame: onto the same monitor then
// asks again instead of trusting the last request. While the window is unmapped
// the property is ours.
- (void) propertyNotify: (XPropertyEvent *) event {
    if (event->atom != XInternAtom(_display, "_NET_WM_STATE", False))
        return;
    _miniaturizedKnown = NO;
    // The window manager may have hidden or restored the window (_NET_WM_STATE_HIDDEN),
    // whoever asked: tell the delegate when the state differs from the last one told.
    BOOL miniaturized = [self isMiniaturized];
    if (miniaturized != _miniaturizedReported) {
        _miniaturizedReported = miniaturized;
        SEL changed = miniaturized ? @selector(platformWindowMiniaturized:)
                                   : @selector(platformWindowDeminiaturized:);
        if ([_delegate respondsToSelector: changed])
            [_delegate performSelector: changed withObject: self];
    }
    if ([_delegate respondsToSelector: @selector(platformWindowOcclusionChanged:)])
        [_delegate platformWindowOcclusionChanged: self];
    if (_mapped) {
        _fullscreenRequested = X11FullscreenIsSet(_display, _window);
        [self updateLayerPresentationHints];
        if (_fullscreenRequested != _fullscreenReported) {
            _fullscreenReported = _fullscreenRequested;
            if ([_delegate respondsToSelector: @selector(platformWindow:didChangeFullScreen:)])
                [_delegate platformWindow: self didChangeFullScreen: _fullscreenReported];
        }
    }
}

// Whether the window manager currently holds the window fullscreen.
- (BOOL) isFullScreen {
    return _mapped && _fullscreenReported;
}

// Hints for a compositor about a window that presents a full-size layer tree
// in its own drawable (see -[X11SubWindow sharedCGLWindow]), such as a game's
// Metal view: while the window is also fullscreen, it may show the window's
// frames without compositing them (_NET_WM_BYPASS_COMPOSITOR, EWMH), and while
// the layers' frames do not wait for the display refresh (CAMetalLayer's
// displaySyncEnabled is NO), it may refresh the display when a frame arrives
// (_VARIABLE_REFRESH, read by Mesa and X compositors). Each property is deleted
// when its condition ends.
- (void) updateLayerPresentationHints {
    BOOL presenting = _layerDrawableOwner != nil;
    [self setCardinalHint: "_NET_WM_BYPASS_COMPOSITOR"
                       on: presenting && _fullscreenRequested
                  current: &_bypassCompositorHint];
    [self setCardinalHint: "_VARIABLE_REFRESH"
                       on: presenting && !_layerDrawableSyncs
                  current: &_variableRefreshHint];
}

- (void) setCardinalHint: (const char *) name
                      on: (BOOL) on
                 current: (BOOL *) current
{
    if (on == *current || _window == 0)
        return;
    Atom atom = XInternAtom(_display, name, False);
    if (on) {
        unsigned long value = 1;
        XChangeProperty(_display, _window, atom, XA_CARDINAL, 32,
                        PropModeReplace, (const unsigned char *) &value, 1);
    } else {
        XDeleteProperty(_display, _window, atom);
    }
    *current = on;
}

- (void *) layerDrawableFor: (id) owner {
    if (_layerDrawableOwner != nil && _layerDrawableOwner != owner)
        return NULL;
    // A layer tree draws opaque frames; an alpha surface's configuration is
    // not the one the owner's context was created for.
    if (_hasAlpha)
        return NULL;
    return _cglWindow;
}

- (void) acquireLayerDrawable: (id) owner syncsToDisplay: (BOOL) syncs {
    if (_layerDrawableOwner != nil && _layerDrawableOwner != owner)
        return;
    _layerDrawableOwner = owner;
    _layerDrawableSyncs = syncs;
    [self updateLayerPresentationHints];
}

- (void) setLayerDrawable: (id) owner syncsToDisplay: (BOOL) syncs {
    if (_layerDrawableOwner != owner)
        return;
    _layerDrawableSyncs = syncs;
    [self updateLayerPresentationHints];
}

- (void) releaseLayerDrawable: (id) owner {
    if (_layerDrawableOwner != owner)
        return;
    _layerDrawableOwner = nil;
    [self updateLayerPresentationHints];
}

// A window gets the window manager's full frame (with a title bar) when it
// has a title bar (see -[NSWindow _hasTitlebarForStyleMask:]: a titled
// window, or a resizable one in a program built against an old SDK); other
// masks ask for no frame. The mask is passed in rather than read from
// _styleMask because -setStyleMask: hands the new mask here before it stores
// it.
- (void) updateDecorationsForStyleMask: (NSUInteger) mask {
    // A window that shows nothing of a title bar of its own (see NSWindow) has the content as all
    // there is (the application draws its own header), so the window manager's frame would be a
    // second title bar on top of it.
    BOOL titlebarInvisible = [self hasInvisibleTitlebarForStyleMask: mask];

    if ([self hasTitlebarForStyleMask: mask] && !_invisibleWithoutCompositor && !titlebarInvisible)
        XDeleteProperty(_display, _window,
                        XInternAtom(_display, "_MOTIF_WM_HINTS", False));
    else
        [[self class] removeDecorationForWindow: _window onDisplay: _display];
    BOOL chromeless = titlebarInvisible && (mask & NSWindowStyleMaskTitled) != 0;
    if (_window != 0 && chromeless != _chromeless) {
        _chromeless = chromeless;
        // Whether the window positions itself depends on it.
        [self updateSizeHints: mask];
    }
    _chromeless = chromeless;
    [self updateWindowShape];
}

- (BOOL) hasTitlebarForStyleMask: (NSUInteger) mask {
    if ([_delegate respondsToSelector: @selector(_hasTitlebarForStyleMask:)])
        return [(NSWindow *) _delegate _hasTitlebarForStyleMask: mask];
    return (mask & NSWindowStyleMaskTitled) != 0;
}

- (BOOL) hasInvisibleTitlebarForStyleMask: (NSUInteger) mask {
    return [_delegate respondsToSelector: @selector(_hasInvisibleTitlebarForStyleMask:)] &&
           [(NSWindow *) _delegate _hasInvisibleTitlebarForStyleMask: mask];
}

// Corner radius, in points, of a window that has no frame of its own to be drawn by the window manager.
// QUIRK: macOS draws such a window (a titled window that shows no title bar of its own, see
// -[NSWindow _hasInvisibleTitlebarForStyleMask:]) with rounded corners of about 5 points, a thin outline and
// a shadow; the window manager draws none of them for a window it was asked not to decorate. The corners are
// cut with the SHAPE extension and the outline is drawn into the window (-flushBuffer), neither of which needs
// a compositor; the shadow can only come from a compositor and is not drawn. Evidence: black-box observation
// of such windows on macOS 10.14.4 (tier 2).
// Test: tests/x11-chromeless-corners.sh (shape of the window), tests/x11-rounded-shape.c (the shape).
static const int X11ChromelessCornerRadius = 5;

// The bounding shape follows the window's size and whether it is drawn without a frame; a window that is
// invisible without a compositor keeps its empty shape.
- (void) updateWindowShape {
    if (_window == 0 || _invisibleWithoutCompositor || (!_chromeless && !_roundedShapeSet))
        return;
    CGFloat scale = [self backingScaleFactor];
    NSSize device = [self deviceSize: _frame.size];
    if (X11WindowSetRoundedCorners(_display, _window, (int) device.width, (int) device.height,
                                   _chromeless ? (int) lround(X11ChromelessCornerRadius * scale) : 0))
        _roundedShapeSet = _chromeless;
}

// The outline of a window without a frame: one device pixel along the rounded edge, drawn over the content
// every time the window is flushed. The window's backing keeps what is drawn on it, so drawing it again must
// change nothing: every pixel is either the opaque outline colour or untouched. The straight sides are
// pixel-aligned rectangles, because a stroked outline is not exact along its whole length (its side drifts by a
// fraction of a pixel, and from some row on it colours the pixel beside the edge too, which showed as a second
// line along part of the left edge). The corners are quarter arcs drawn without antialiasing, so that their
// partial coverage cannot accumulate over repeated flushes.
- (void) drawChromelessOutline {
    if (!_chromeless || _context == nil || _invisibleWithoutCompositor)
        return;
    CGFloat width = _frame.size.width, height = _frame.size.height, radius = X11ChromelessCornerRadius;
    CGFloat line = 1.0 / [self backingScaleFactor];
    CGFloat inset = line / 2;
    if (width < 2 * radius + 2 || height < 2 * radius + 2)
        return;
    O2ContextRef context = _context;
    O2ContextSaveGState(context);
    O2Float color[4] = {0.45, 0.45, 0.45, 1.0};
    O2ContextSetFillColor(context, color);
    O2ContextSetStrokeColor(context, color);
    O2ContextSetShouldAntialias(context, NO);
    O2ContextFillRect(context, O2RectMake(radius, 0, width - 2 * radius, line));
    O2ContextFillRect(context, O2RectMake(radius, height - line, width - 2 * radius, line));
    O2ContextFillRect(context, O2RectMake(0, radius, line, height - 2 * radius));
    O2ContextFillRect(context, O2RectMake(width - line, radius, line, height - 2 * radius));
    O2ContextSetLineWidth(context, line);
    O2ContextBeginPath(context);
    O2ContextMoveToPoint(context, inset, inset + radius);
    O2ContextAddArcToPoint(context, inset, inset, inset + radius, inset, radius);
    O2ContextMoveToPoint(context, width - inset - radius, inset);
    O2ContextAddArcToPoint(context, width - inset, inset, width - inset, inset + radius, radius);
    O2ContextMoveToPoint(context, width - inset, height - inset - radius);
    O2ContextAddArcToPoint(context, width - inset, height - inset, width - inset - radius, height - inset, radius);
    O2ContextMoveToPoint(context, inset + radius, height - inset);
    O2ContextAddArcToPoint(context, inset, height - inset, inset, height - inset - radius, radius);
    O2ContextStrokePath(context);
    O2ContextRestoreGState(context);
}

- (void) setStyleMaskInternal: (NSUInteger) mask force: (BOOL) force {
    if (force || (mask & NSWindowStyleMaskResizable) !=
                         (_styleMask & NSWindowStyleMaskResizable)) {
        [self updateSizeHints: mask];
    }
    if (force ||
        (mask & (NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView)) !=
                (_styleMask & (NSWindowStyleMaskTitled | NSWindowStyleMaskResizable |
                               NSWindowStyleMaskFullSizeContentView))) {
        [self updateDecorationsForStyleMask: mask];
    }

    BOOL fullscreen =
            !X11FullscreenStyleLeft(
                    (_styleMask & NSWindowStyleMaskFullScreen) != 0,
                    (mask & NSWindowStyleMaskFullScreen) != 0) &&
            [self wantsFullscreenWithStyleMask: mask frame: [self frame]];
    [self requestFullscreen: fullscreen force: force];
}

- (void) setStyleMask: (NSUInteger) mask {
    [self setStyleMaskInternal: mask force: NO];

    _styleMask = mask;
}

+ (void) removeDecorationForWindow: (Window) w onDisplay: (Display *) dpy {
    struct {
        unsigned long flags;
        unsigned long functions;
        unsigned long decorations;
        long input_mode;
        unsigned long status;
    } hints = {
            2, 0, 0, 0, 0,
    };
    XChangeProperty(dpy, w, XInternAtom(dpy, "_MOTIF_WM_HINTS", False),
                    XInternAtom(dpy, "_MOTIF_WM_HINTS", False), 32,
                    PropModeReplace, (const unsigned char *) &hints,
                    sizeof(hints) / sizeof(long));
}

// Whether what is behind the window can show through it: a window that is not
// opaque and whose background has alpha (a pattern image may have).
- (BOOL) isTranslucent {
    if (_delegate == nil || [_delegate isOpaque])
        return NO;
    NSColor *background = [_delegate backgroundColor];
    return background == nil || [background alphaComponent] < 1.0 ||
           [[background colorSpaceName] isEqualToString: NSPatternColorSpace];
}

- (BOOL) wantsAlphaVisual {
    return !alphaSurfaceFailed && X11AlphaVisualInfo(_display) != NULL &&
           [self isTranslucent];
}

// The visual of an X window is fixed when it is created, which is usually
// before the application makes the window non-opaque. Until the window is
// first mapped, replace it with one of the right visual, keeping its children.
- (void) settleVisual {
    if (_wasMapped || _window == 0 || _delegate == nil)
        return;
    BOOL alpha = [self wantsAlphaVisual];
    if (alpha != _hasAlpha)
        [self recreateXWindowWithAlpha: alpha];
}

- (void) recreateXWindowWithAlpha: (BOOL) alpha {
    Window oldWindow = _window;
    XVisualInfo *oldVisualInfo = _visualInfo;

    [_caContext release];
    _caContext = nil;
    if (_cglContext != NULL) {
        CGLReleaseContext(_cglContext);
        _cglContext = NULL;
    }
    if (_cglWindow != NULL) {
        CGLDestroyWindow(_cglWindow);
        _cglWindow = NULL;
    }
    if (_xic != NULL) {
        XDestroyIC(_xic);
        _xic = NULL;
    }
    [_preedit setLength: 0];
    _preeditCaret = 0;
    _onTheSpotPreedit = NO;
    [(X11Display *) [NSDisplay currentDisplay] setWindow: nil
                                                   forID: oldWindow];

    // The new window has no input shape or presentation hints yet.
    _ignoresMouseEvents = NO;
    _bypassCompositorHint = NO;
    _variableRefreshHint = NO;
    _hasAlpha = alpha;
    if (![self createXWindow]) {
        // No usable visual: keep the old window rather than none.
        _window = oldWindow;
        _visualInfo = oldVisualInfo;
        _hasAlpha = !alpha;
        _cglWindow = _hasAlpha ? CGLGetWindowWithAlpha((void *) _window,
                                                       _visualInfo->visualid)
                               : CGLGetWindow((void *) _window);
        [self createXInputContext];
        [(X11Display *) [NSDisplay currentDisplay] setWindow: self
                                                       forID: _window];
        return;
    }

    Window root, parent, *children = NULL;
    unsigned int count = 0;
    if (XQueryTree(_display, oldWindow, &root, &parent, &children, &count)) {
        for (unsigned int i = 0; i < count; i++) {
            XWindowAttributes attributes;
            if (XGetWindowAttributes(_display, children[i], &attributes))
                XReparentWindow(_display, children[i], _window, attributes.x,
                                attributes.y);
        }
        if (children != NULL)
            XFree(children);
    }
    XDestroyWindow(_display, oldWindow);

    // the new window has neither opacity nor shape yet
    _invisibleWithoutCompositor = NO;
    if (_appliedAlpha < 1.0)
        [self setAlphaValue: _appliedAlpha];

    NSString *title = [_delegate title];
    if (title != nil)
        [self setTitle: title];
    [self updateLayerPresentationHints];
}

- (void) ensureMapped {
    if (!_mapped) {
        // What the window is can have changed since it was created or last shown.
        [self updateWindowManagerHints];
        // A withdrawn window loses _NET_WM_STATE (EWMH), so the window has to say
        // again, before it is mapped, what it is: fullscreen if it covers a monitor,
        // and modal, which requestFullscreen: writes as well.
        [self requestFullscreen: [self wantsFullscreenWithStyleMask: _styleMask
                                                              frame: [self frame]]
                          force: NO];
        [self settleVisual];
        if (_dock)
            [self publishDockHints];
        XMapWindow(_display, _window);
        _mapped = YES;
        _wasMapped = YES;
        _miniaturizedKnown = NO;
        if (_menuWindow)
            [(X11Display *) [NSDisplay currentDisplay] menuWindowMapped: self];
    }
}

// What a dock window tells the window manager before it is mapped: it is on
// every desktop, outside the taskbar and pager, above other windows, and
// reserves the strip it covers along the top edge of the screen (EWMH
// _NET_WM_STRUT_PARTIAL, and _NET_WM_STRUT for older managers).
- (void) publishDockHints {
    long state[4] = {
        (long) XInternAtom(_display, "_NET_WM_STATE_STICKY", False),
        (long) XInternAtom(_display, "_NET_WM_STATE_ABOVE", False),
        (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_TASKBAR", False),
        (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_PAGER", False)};
    long desktop = (long) 0xFFFFFFFFul;
    long top = (long) (_frame.origin.y + _frame.size.height);
    long left = (long) _frame.origin.x;
    long right = (long) (_frame.origin.x + _frame.size.width) - 1;
    long partial[12] = {0, 0, top, 0, 0, 0, 0, 0, left, right, 0, 0};
    long strut[4] = {0, 0, top, 0};

    XChangeProperty(_display, _window,
                    XInternAtom(_display, "_NET_WM_STATE", False), XA_ATOM, 32,
                    PropModeReplace, (const unsigned char *) state, 4);
    XChangeProperty(_display, _window,
                    XInternAtom(_display, "_NET_WM_DESKTOP", False), XA_CARDINAL,
                    32, PropModeReplace, (const unsigned char *) &desktop, 1);
    XChangeProperty(_display, _window,
                    XInternAtom(_display, "_NET_WM_STRUT_PARTIAL", False),
                    XA_CARDINAL, 32, PropModeReplace,
                    (const unsigned char *) partial, 12);
    XChangeProperty(_display, _window,
                    XInternAtom(_display, "_NET_WM_STRUT", False), XA_CARDINAL,
                    32, PropModeReplace, (const unsigned char *) strut, 4);
}

// Restacking a window only maps it while AppKit shows it.
// -[NSWindow orderWindow:relativeTo:] marks the window visible before it
// restacks, so ordering a window in still maps it.
- (void) ensureMappedIfVisible {
    if (_delegate == nil || [_delegate isVisible])
        [self ensureMapped];
}

- (BOOL) isMapped {
    return _mapped;
}

- (BOOL) isFullscreen {
    return _fullscreenRequested;
}

- (void) showWindowWithoutActivation {
    [self ensureMapped];
}

- (void) setDelegate: delegate {
    _delegate = delegate;
    [self syncDelegateProperties];
}

- delegate {
    return _delegate;
}

- (void) syncDelegateProperties {
    long mask = KeyPressMask | KeyReleaseMask | ExposureMask |
                StructureNotifyMask | EnterWindowMask | LeaveWindowMask |
                ButtonPressMask | ButtonReleaseMask | ButtonMotionMask |
                VisibilityChangeMask | FocusChangeMask | PropertyChangeMask |
                SubstructureRedirectMask;

    if ([_delegate acceptsMouseMovedEvents]) {
        mask |= PointerMotionMask;
    }
    XSelectInput(_display, _window, mask);
    X11TouchSelectWindow(_display, _window);

    // Click-through windows (overlays, tooltips) must not take the pointer from
    // the window below. Only a change needs a request.
    BOOL ignoresMouseEvents = [_delegate ignoresMouseEvents] || _invisibleWithoutCompositor;
    if (ignoresMouseEvents != _ignoresMouseEvents && _window != 0 &&
        X11WindowSetIgnoresMouseEvents(_display, _window, ignoresMouseEvents)) {
        _ignoresMouseEvents = ignoresMouseEvents;
        XFlush(_display);
    }

    // An alpha value set before the window had its X window (or its delegate) is applied now.
    if (_window != 0 && _delegate != nil && [_delegate alphaValue] != _appliedAlpha)
        [self setAlphaValue: [_delegate alphaValue]];

    // TODO: background color
}

// Window opacity through the EWMH _NET_WM_WINDOW_OPACITY property (a CARDINAL
// where 0xffffffff is fully opaque), honoured by compositing window managers.
- (void) setAlphaValue: (CGFloat) value {
    // After -invalidate there is no X window (CGSSetWindowAlpha can still find
    // this object by number until it is deallocated).
    if (_window == 0)
        return;

    Atom opacity = XInternAtom(_display, "_NET_WM_WINDOW_OPACITY", False);

    if (value >= 1.0) {
        XDeleteProperty(_display, _window, opacity);
    } else {
        unsigned long cardinal =
                (unsigned long) (MAX(value, 0.0) * (double) 0xffffffffUL);
        XChangeProperty(_display, _window, opacity, XA_CARDINAL, 32,
                        PropModeReplace, (unsigned char *) &cardinal, 1);
    }
    _appliedAlpha = value;
    _alphaIsZero = value <= 0.0;
    [self updateInvisibility];
    XFlush(_display);
}

// Without a compositing manager nothing applies _NET_WM_WINDOW_OPACITY, so a window with alpha 0 would stay
// visible, including the window manager's frame. It is made invisible instead, while staying mapped (and so able
// to keep the keyboard focus and stay the key window): the window manager is asked for no frame and the bounding
// shape of the window is emptied. Partial alpha without a compositor is left alone, and with a compositor the
// opacity property is all that is needed. The compositor is looked for whenever the alpha changes, not watched
// for: a compositor that starts or stops while the window has alpha 0 takes effect at the next change.
- (void) updateInvisibility {
    BOOL invisible = _alphaIsZero && !X11CompositorRunning(_display, DefaultScreen(_display));

    if (invisible == _invisibleWithoutCompositor || _window == 0)
        return;
    if (!X11WindowSetBoundingEmpty(_display, _window, invisible))
        return;
    _invisibleWithoutCompositor = invisible;
    // A frame follows the shape, but its decorations would come back with a window manager that draws them
    // outside the client, and the window must not take pointer events from what is below it either.
    [self updateDecorationsForStyleMask: _styleMask];
    BOOL ignoresMouseEvents = invisible || [_delegate ignoresMouseEvents];
    if (ignoresMouseEvents != _ignoresMouseEvents &&
        X11WindowSetIgnoresMouseEvents(_display, _window, ignoresMouseEvents))
        _ignoresMouseEvents = ignoresMouseEvents;
}

- (void) invalidate {
    // This is essentially dealloc; we release our contexts
    // and windows, but unlike dealloc, this method can be called
    // several times, so set everything to nil/NULL/0.
    [_context release];
    _context = nil;

    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;
    [_transientParent release];
    _transientParent = nil;

    [_caContext release];
    _caContext = nil;

    if (_cglContext != NULL) {
        CGLReleaseContext(_cglContext);
        _cglContext = NULL;
    }
    if (_cglWindow != NULL) {
        CGLDestroyWindow(_cglWindow);
        _cglWindow = NULL;
    }

    if (_window) {
        // _xic is NULL when there is no input method; XDestroyIC() doesn't accept NULL.
        if (_xic != NULL) {
            XDestroyIC(_xic);
            _xic = NULL;
        }

        if (_menuWindow)
            [(X11Display *) [NSDisplay currentDisplay] menuWindowUnmapped: self];
        [(X11Display *) [NSDisplay currentDisplay] setWindow: nil
                                                       forID: _window];
        XDestroyWindow(_display, _window);
        _window = 0;
    }
}

- (Window) windowHandle {
    return _window;
}

- (unsigned long) platformWindowID {
    return _window;
}

- (O2Context *) createCGContextIfNeeded {
    if (_context == nil) {
        // The backing surface has the device size, rounded as the X window is,
        // because the GL viewport follows the surface.
        NSSize device = [self deviceSize: _frame.size];
        // The drawing context divides by the logical size, so a degenerate one
        // would put inf/NaN in the device transform.
        if (!isfinite(_frame.size.width) || !isfinite(_frame.size.height) ||
            _frame.size.width < 1 || _frame.size.height < 1 ||
            device.width > 65535 || device.height > 65535)
            return nil;
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc]
                   initWithBytes: NULL
                           width: device.width
                          height: device.height
                bitsPerComponent: 8
                     bytesPerRow: 0
                      colorSpace: colorSpace
                      bitmapInfo: kO2ImageAlphaPremultipliedFirst |
                                  kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        _context = [[X11DrawingContext alloc] initWithSurface: surface
                                                  logicalSize: _frame.size];
        [surface release];
    }
    return _context;
}

- (O2Context *) cgContext {
    return [self createCGContextIfNeeded];
}

- (void) invalidateContextWithNewSize: (NSSize) size
                         forceRebuild: (BOOL) forceRebuild
{
    if (!NSEqualSizes(_frame.size, size) || forceRebuild) {
        _frame.size = size;
        if (![_context resizeWithNewSize: size]) {
            [_context release];
            _context = nil;
            [_delegate platformWindowDidInvalidateCGContext: self];
        }
    }
}

- (void) invalidateContextWithNewSize: (NSSize) size {
    [self invalidateContextWithNewSize: size forceRebuild: NO];
}

- (void) setTitle: (NSString *) title {
    const char *text = [title UTF8String];
    // -setTitle: nil is undefined, but it used to reach here without a crash and
    // strlen(NULL) would not survive it.
    if (text == NULL)
        text = "";
    int length = (int) strlen(text);

    // EWMH says the title is _NET_WM_NAME as UTF8_STRING, and nothing set it, so
    // a title outside Latin-1 arrived as whatever XStringListToTextProperty could
    // do with it. The bytes used to come from -[NSString cString], which converts
    // to the system encoding and raises when a character does not fit. WM_NAME
    // gets the same bytes for a window manager predating EWMH.
    //
    // No return check here. XChangeProperty reports through the X error handler, not
    // its return value: it returns 1 on success, so comparing against Success (0)
    // logged "failed" on every title, including the ones that demonstrably landed.
    // -[X11Display handleError:] is what reports a real failure, with request and
    // error codes.
    XChangeProperty(_display, _window,
                    XInternAtom(_display, "_NET_WM_NAME", False),
                    XInternAtom(_display, "UTF8_STRING", False), 8,
                    PropModeReplace, (const unsigned char *) text, length);

    XChangeProperty(_display, _window, XA_WM_NAME, XA_STRING, 8, PropModeReplace,
                    (const unsigned char *) text, length);
}

- (void) setFrame: (O2Rect) frame {
    O2Rect transformed = [self transformFrame: frame];
    NSSize previousSize = _frame.size;
    // Leave fullscreen before moving to a frame that does not cover a monitor,
    // or the manager keeps imposing its fullscreen size, and before moving a
    // fullscreen window elsewhere, which the manager would ignore; enter it after
    // moving onto a monitor.
    BOOL fullscreen = [self wantsFullscreenWithStyleMask: _styleMask
                                                   frame: frame];
    BOOL moved = _frame.origin.x != transformed.origin.x ||
                 _frame.origin.y != transformed.origin.y;
    if (X11FullscreenLeaveBeforeMove(fullscreen, _fullscreenRequested, moved))
        [self requestFullscreen: NO force: NO];
    frame = transformed;
    // _frame stays in points; only the X call and the surface are in device
    // pixels.
    O2Rect deviceFrame = [self deviceRect: frame];
    XMoveResizeWindow(_display, _window, deviceFrame.origin.x,
                      deviceFrame.origin.y, deviceFrame.size.width,
                      deviceFrame.size.height);
    [self invalidateContextWithNewSize: frame.size];
    _frame = frame;
    [self updateWindowShape];
    // A non-resizable window hints PMinSize == PMaxSize, and a window manager
    // refuses any resize that falls outside the pair, so the hints have to follow
    // the size. Only on a real change so a drag does not re-issue them per pixel.
    if (!NSEqualSizes(previousSize, frame.size))
        [self updateSizeHints: _styleMask];
    if (fullscreen && !_fullscreenRequested)
        [self requestFullscreen: YES force: NO];
}

- (void) setHasShadow: (BOOL) value {
    _hasShadow = value;
}

- (void) setLevel: (int) value {
    if (value == _level)
        return;
    _level = value;
    [self restackForLevels];
}

- (int) stackingLevel {
    return _level;
}

- (BOOL) isUnmanaged {
    return _overrideRedirect;
}

- (BOOL) takesPartInLevelStacking {
    return _mapped && !_dock && !_menuWindow && _window != 0;
}

- (void) restackForLevels {
    if ([self takesPartInLevelStacking])
        [(X11Display *) [NSDisplay currentDisplay] restackWindowsForLevelsAround: self];
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
}

- (void) sheetOrderFrontFromFrame: (NSRect) frame
                      aboveWindow: (CGWindow *) aboveWindow
{
    [self setFrame: frame];
    [self placeAboveWindow: [aboveWindow windowNumber]];
}

- (void) sheetOrderOutToFrame: (NSRect) frame {
    [self hideWindow];
}

- (void) showWindowForAppActivation: (O2Rect) frame {
    [self showWindowWithoutActivation];
}

- (void) hideWindowForAppDeactivation: (O2Rect) frame {
    /* Ignored */
}

- (void) hideWindow {
    XUnmapWindow(_display, _window);
    _mapped = NO;
    _occluded = NO;
    _miniaturizedKnown = NO;
    if (_menuWindow)
        [(X11Display *) [NSDisplay currentDisplay] menuWindowUnmapped: self];
    // The window manager drops the fullscreen state of a withdrawn window.
    _fullscreenRequested = NO;
    _fullscreenReported = NO;
    // A focus request still waiting for MapNotify is void once the window is
    // ordered out; otherwise a later non-key orderFront would take focus.
    _wantsInputFocus = NO;
    _keyRequested = NO;
}

// Stacks this window directly above or below another top-level window. With a window manager the two client
// windows live in frames of their own and are not siblings, so a plain stacking request naming the other window
// as sibling is a BadMatch; XReconfigureWMWindow makes the ICCCM request for that case (a ConfigureRequest sent
// to the root window, which the window manager carries out for the frames).
- (void) stackRelativeToWindow: (Window) sibling mode: (int) mode {
    XWindowChanges changes;
    changes.sibling = sibling;
    changes.stack_mode = mode;
    XReconfigureWMWindow(_display, _window, DefaultScreen(_display), CWSibling | CWStackMode, &changes);
}

- (void) placeAboveWindow: (NSInteger) otherNumber {
    X11Window *other = [X11Window windowWithWindowNumber: otherNumber];
    [self ensureMappedIfVisible];

    if (!other) {
        XRaiseWindow(_display, _window);
    } else {
        [self stackRelativeToWindow: other->_window mode: Above];
    }
    [self restackForLevels];
}

- (void) placeBelowWindow: (NSInteger) otherNumber {
    X11Window *other = [X11Window windowWithWindowNumber: otherNumber];
    [self ensureMappedIfVisible];

    if (!other) {
        XLowerWindow(_display, _window);
    } else {
        [self stackRelativeToWindow: other->_window mode: Below];
    }
}

// Without a window manager nothing moves X input focus: it stays PointerRoot, so
// key events went to whichever window was under the pointer and no window ever
// received FocusIn, which left -[NSApplication keyWindow] nil. Ask for focus
// explicitly: through the EWMH _NET_ACTIVE_WINDOW request when a window manager
// is running, otherwise with XSetInputFocus once the window is viewable.
static Window supportingWMCheckWindow(Display *display, Window window,
                                      Atom check)
{
    Atom type;
    int format;
    unsigned long count, remaining;
    unsigned char *data = NULL;
    Window result = None;

    if (XGetWindowProperty(display, window, check, 0, 1, False, XA_WINDOW,
                           &type, &format, &count, &remaining, &data) ==
                Success &&
        data != NULL && type == XA_WINDOW && format == 32 && count == 1)
        result = (Window) * (long *) data;
    if (data != NULL)
        XFree(data);
    return result;
}

BOOL X11WindowManagerIsRunning(Display *display) {
    Atom check = XInternAtom(display, "_NET_SUPPORTING_WM_CHECK", True);
    if (check == None)
        return NO;

    // A window manager that exited can leave the root property behind. Per
    // EWMH the child window it names must carry the same property naming
    // itself; a stale id fails that (the BadWindow is only logged).
    Window child =
            supportingWMCheckWindow(display, DefaultRootWindow(display), check);
    return child != None &&
           supportingWMCheckWindow(display, child, check) == child;
}

- (void) requestInputFocus {
    Window focused;
    int revert;
    XGetInputFocus(_display, &focused, &revert);
    if (focused == _window) {
        _wantsInputFocus = NO;
        return;
    }

    if (X11WindowManagerIsRunning(_display)) {
        XEvent event;
        memset(&event, 0, sizeof(event));
        event.xclient.type = ClientMessage;
        event.xclient.window = _window;
        event.xclient.message_type =
                XInternAtom(_display, "_NET_ACTIVE_WINDOW", False);
        event.xclient.format = 32;
        event.xclient.data.l[0] = 1; // source indication: application
        event.xclient.data.l[1] = CurrentTime;
        XSendEvent(_display, DefaultRootWindow(_display), False,
                   SubstructureRedirectMask | SubstructureNotifyMask, &event);
        XFlush(_display);
        _wantsInputFocus = NO;
        return;
    }

    XWindowAttributes attributes;
    if (XGetWindowAttributes(_display, _window, &attributes) &&
        attributes.map_state == IsViewable) {
        XSetInputFocus(_display, _window, RevertToPointerRoot, CurrentTime);
        // Send it now: an idle run loop may not flush Xlib's output buffer until the
        // next event, so key events typed meanwhile would still go to the old window.
        XFlush(_display);
        _wantsInputFocus = NO;
    } else {
        // Not viewable yet (the map request is still pending): retry on MapNotify.
        _wantsInputFocus = YES;
    }
}

- (void) mapNotified {
    // The window manager has stacked the frame by now.
    [self restackForLevels];
    if (_wantsInputFocus)
        [self requestInputFocus];
}

// A window with alphaValue 0 is ordered in (mapped, and invisible by opacity or shape) and can be the
// key window; the window manager's focus moving to another window of the application does not take
// the key status from it (see -[NSWindow platformWindowActivated:displayIfNeeded:]).
- (BOOL) isFullyTransparent {
    return _alphaIsZero;
}

// Whether the application asked for this window to become the key window and the focus now arriving
// is the answer to that; reading it clears the request. Without one, the focus the window manager
// gives a window that was ordered in is not a request for the key status.
- (BOOL) takeKeyRequest {
    BOOL requested = _keyRequested;
    _keyRequested = NO;
    return requested;
}

- (BOOL) isMenuOrPopup {
    return _menuWindow || _overrideRedirect;
}

- (void) makeKey {
    // FocusIn activates the NSWindow, which makes it key again and ends up here.
    // The focus change came from the window manager, which also stacks the
    // window, so leave both alone. Answering a FocusIn that is already stale
    // (focus has moved on since) with a raise or a focus request moves focus
    // back: window managers that focus a window that raises itself, xfwm4 among
    // them, then bounce focus between two windows forever.
    if (_receivingFocus)
        return;
    _keyRequested = YES;
    // Making a window key does not put it on the screen: one that has not been
    // ordered in has no mapped X window, and cannot take the input focus
    // before it has. Ordering a window in (which maps it) comes first when
    // an application asks for both.
    if (!_mapped)
        return;
    XRaiseWindow(_display, _window);
    [self restackForLevels];
    [self requestInputFocus];
    // The window already holds the focus (the window manager gave it when the window was ordered in
    // and that did not make it key), so no FocusIn follows to report the request.
    Window focused;
    int revert;
    XGetInputFocus(_display, &focused, &revert);
    if (focused == _window && ![_delegate isKeyWindow])
        [(X11Display *) [NSDisplay currentDisplay] windowHoldsFocus: self];
}

- (void) makeMain {
}

- (void) captureEvents {
}

// -[NSApplication requestUserAttention:] reaches this unconditionally about
// three seconds later, and without an override CGWindow raises
// NSInvalidAbstractInvocation, so any app that asks for attention died there.
// The EWMH request is per-window; XBell would ring the screen bell instead.
- (void) flashWindow {
    // -invalidate leaves no X window behind.
    if (_window == 0)
        return;

    XEvent event = {0};
    event.xclient.type = ClientMessage;
    event.xclient.window = _window;
    event.xclient.message_type = XInternAtom(_display, "_NET_WM_STATE", False);
    event.xclient.format = 32;
    event.xclient.data.l[0] = 1; // add
    event.xclient.data.l[1] =
        (long) XInternAtom(_display, "_NET_WM_STATE_DEMANDS_ATTENTION", False);
    event.xclient.data.l[2] = 1; // source indication: application
    event.xclient.data.l[3] = CurrentTime;
    XSendEvent(_display, DefaultRootWindow(_display), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &event);
    // Nothing else happens on this path, and an idle run loop may sit on the
    // request until the next event or the next X call.
    XFlush(_display);
}

// Whether the window manager lists the atom in _NET_SUPPORTED on the root window (EWMH).
static BOOL X11WindowManagerSupports(Display *display, const char *name) {
    Atom wanted = XInternAtom(display, name, False);
    Atom type;
    int format;
    unsigned long count, after;
    unsigned char *data = NULL;
    BOOL found = NO;
    if (XGetWindowProperty(display, DefaultRootWindow(display),
                           XInternAtom(display, "_NET_SUPPORTED", False), 0, 4096, False, XA_ATOM,
                           &type, &format, &count, &after, &data) == Success &&
        data != NULL && type == XA_ATOM && format == 32) {
        Atom *atoms = (Atom *) data;
        for (unsigned long i = 0; i < count && !found; i++)
            found = atoms[i] == wanted;
    }
    if (data != NULL)
        XFree(data);
    return found;
}

// -[NSWindow performWindowDragWithEvent:]: the window manager moves the window
// for as long as the left button stays down (EWMH _NET_WM_MOVERESIZE). The
// pointer grab the press gave this client is released first, as EWMH asks, so
// the button release goes to the window manager. NO when the window manager
// cannot do it, the window is not managed, or the button is already up.
- (BOOL) moveByWindowManagerForEvent: (NSEvent *) event {
    if (_window == 0 || _overrideRedirect ||
        !X11WindowManagerSupports(_display, "_NET_WM_MOVERESIZE"))
        return NO;

    Window root, child;
    int rootX, rootY, winX, winY;
    unsigned int mask = 0;
    if (!XQueryPointer(_display, _window, &root, &child, &rootX, &rootY, &winX, &winY, &mask) ||
        !(mask & Button1Mask))
        return NO;

    XUngrabPointer(_display, CurrentTime);
    XEvent message = {0};
    message.xclient.type = ClientMessage;
    message.xclient.window = _window;
    message.xclient.message_type = XInternAtom(_display, "_NET_WM_MOVERESIZE", False);
    message.xclient.format = 32;
    message.xclient.data.l[0] = rootX;
    message.xclient.data.l[1] = rootY;
    message.xclient.data.l[2] = 8; // _NET_WM_MOVERESIZE_MOVE
    message.xclient.data.l[3] = Button1;
    message.xclient.data.l[4] = 1; // source indication: application
    XSendEvent(_display, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &message);
    XFlush(_display);
    return YES;
}

- (void) miniaturize {
    XIconifyWindow(_display, _window, DefaultScreen(_display));
}

// ICCCM: a client asks to leave the iconic state by mapping its window again (raising an iconified
// window does not restore it).
- (void) deminiaturize {
    XMapRaised(_display, _window);
}

// NSWindow asks this of every window on each pass of the event loop, and
// reading the property is a round trip. The window selects PropertyChangeMask,
// so a change of _NET_WM_STATE, whoever makes it, arrives as PropertyNotify.
- (BOOL) isMiniaturized {
    if (!_miniaturizedKnown) {
        _miniaturized = [self readMiniaturized];
        _miniaturizedKnown = YES;
    }
    return _miniaturized;
}

- (BOOL) isOccluded {
    return _occluded;
}

- (BOOL) noteConfigureGeometryChanged: (XConfigureEvent *) event {
    if (_configureKnown && event->x == _configureX && event->y == _configureY &&
        event->width == _configureWidth && event->height == _configureHeight)
        return NO;
    _configureKnown = YES;
    _configureX = event->x;
    _configureY = event->y;
    _configureWidth = event->width;
    _configureHeight = event->height;
    return YES;
}

- (void) setOccluded: (BOOL) occluded {
    _occluded = occluded;
}

- (BOOL) readMiniaturized {
    Atom wmState = XInternAtom(_display, "_NET_WM_STATE", FALSE);
    Atom hiddenState = XInternAtom(_display, "_NET_WM_STATE_HIDDEN", FALSE);

    Atom type;
    int format;
    unsigned long nItem, bytesAfter;
    unsigned char *properties = NULL;
    BOOL rv = NO;

    if (XGetWindowProperty(_display, _window, wmState, 0, (~0L), FALSE, XA_ATOM,
                           &type, &format, &nItem, &bytesAfter,
                           &properties) == Success) {
        Atom *atoms = (Atom *) properties;
        for (int i = 0; i < nItem; i++) {
            if (atoms[i] == hiddenState) {
                rv = YES;
                break;
            }
        }
        XFree(properties);
    }

    return rv;
}

- (CGLContextObj) cglContext {
    return _cglContext;
}

- (void) createCGLContextObjIfNeeded {
    if (_cglContext == NULL) {
        CGLError error;

        // A context for an alpha surface has to use the surface's
        // configuration.
        error = _hasAlpha ? CGLCreateContextForWindow(_cglWindow, &_cglContext)
                          : CGLCreateContext(NULL, NULL, &_cglContext);
        if (error != kCGLNoError) {
            NSLog(@"CGLCreateContext failed at %s %d with error %d", __FILE__,
                  __LINE__, error);

            [NSException raise: NSGenericException
                        format: @"Failed to create GL context, CGL error %d",
                                error];
        }
        if ((error = CGLContextMakeCurrentAndAttachToWindow(
                     _cglContext, _cglWindow)) != kCGLNoError)
            NSLog(@"CGLContextMakeCurrentAndAttachToWindow failed with error "
                  @"%d",
                  error);
    }
    if (_cglContext != nil && _caContext == nil) {
        _caContext =
                [[CAWindowOpenGLContext alloc] initWithCGLContext: _cglContext];
    }
}

- (void) openGLFlushBuffer {
    // The layer tree covering the window presents into its drawable; drawing
    // the window's own backing (which it covers) would replace those frames.
    if (_layerDrawableOwner != nil)
        return;

    CGLError error;

    CGLContextObj prevContext = CGLGetCurrentContext();

    [self createCGLContextObjIfNeeded];
    if (_caContext == nil)
        return;

    O2Surface *surface = [_context surface];
    size_t width = O2ImageGetWidth(surface);
    size_t height = O2ImageGetHeight(surface);

    [_caContext prepareViewportWidth: width height: height];
    [_caContext renderSurface: surface];

    glFlush();
    CGLFlushDrawable(_cglContext);

    CGLSetCurrentContext(prevContext);
}

- (BOOL) addExposedRect: (O2Rect) rect isLast: (BOOL) last exposedUnion: (O2Rect *) exposedUnion {
    if (_hasPendingExpose)
        rect = NSUnionRect(_pendingExpose, rect);
    if (!last) {
        _pendingExpose = rect;
        _hasPendingExpose = YES;
        return NO;
    }
    _hasPendingExpose = NO;
    *exposedUnion = rect;
    return YES;
}

- (void) flushBuffer {
    if (_context == nil)
        return;
    [self drawChromelessOutline];
    O2ContextFlush(_context);
    [self openGLFlushBuffer];
    // Layer trees in child windows show the pixels drawn beneath them (see
    // -[X11SubWindow createBackdropImage]).
    [[NSNotificationCenter defaultCenter]
            postNotificationName: X11WindowBackingDidFlushNotification
                          object: self];
}

- (O2ImageRef) createBackingImageInDeviceRect: (O2Rect) rect {
    if (_context == nil)
        return NULL;
    O2Surface *surface = [(O2Context_builtin *) _context surface];
    O2ImageRef whole = O2SurfaceCreateImage(surface);
    O2Rect bounds = O2RectMake(0, 0, O2SurfaceGetWidth(surface), O2SurfaceGetHeight(surface));
    O2ImageRef result = whole != NULL ? O2ImageCreateWithImageInRect(whole, O2RectIntersection(rect, bounds)) : NULL;

    O2ImageRelease(whole);
    return result;
}

// The point is in window coordinates in points (y up), as an event reports it.
// It is kept from the top-left corner, so that a resize in between does not
// move it.
- (void) setLastKnownCursorPosition: (CGPoint) point {
    _lastMotionPos = [self transformPoint: point];
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return [self transformPoint: _lastMotionPos];
}

// Device pixels from the top-left corner of the window, as X delivers them, to
// window coordinates in points with y up, as AppKit reports them.
- (NSPoint) logicalPoint: (NSPoint) devicePoint {
    CGFloat scale = [self backingScaleFactor];
    return [self transformPoint: NSMakePoint(devicePoint.x / scale,
                                             devicePoint.y / scale)];
}

// _frame is kept in root coordinates; -frame is in Cocoa's global space.
- (O2Rect) frame {
    return [self untransformFrame: _frame];
}

NSString *const X11WindowBackingDidFlushNotification = @"X11WindowBackingDidFlush";

static int ignoreBadWindow(Display *display, XErrorEvent *errorEvent) {
    if (errorEvent->error_code == BadWindow)
        return 0;
    char buf[512];
    XGetErrorText(display, errorEvent->error_code, buf, 512);
    [NSException raise: NSInternalInconsistencyException
                format: @"X11 error: %s", buf];
    return 0;
}

- (void) frameChanged {
    XErrorHandler previousHandler = XSetErrorHandler(ignoreBadWindow);
    @try {
        Window root, parent;
        Window window = _window;
        int x, y;
        unsigned int w, h, d, b, nchild;
        Window *children;
        O2Rect rect = NSZeroRect;
        // Walk up the parents to get the absolute position. The root window has
        // no parent (QueryTree reports None), which ends the walk; the depth is
        // bounded as well so that a parent cycle cannot hold the ConfigureNotify
        // path. A reparenting window manager makes the chain deeper.
        for (int depth = 0; window && depth < 64; depth++) {
            XGetGeometry(_display, window, &root, &x, &y, &w, &h, &b, &d);

            // first iteration: save our own w, h
            if (window == _window)
                rect = NSMakeRect(0, 0, w, h);
            rect.origin.x += x;
            rect.origin.y += y;

            if (!XQueryTree(_display, window, &root, &parent, &children, &nchild))
                break;
            if (children)
                XFree(children);
            if (parent == window)
                break;
            window = parent;
        }

        // XGetGeometry reports device pixels, _frame is in points: convert once
        // here rather than at every reader.
        CGFloat scale = [self backingScaleFactor];
        rect = NSMakeRect(rect.origin.x / scale, rect.origin.y / scale,
                          rect.size.width / scale, rect.size.height / scale);
        [self invalidateContextWithNewSize: rect.size];
        _frame = rect;
        [self updateWindowShape];
    } @finally {
        XSetErrorHandler(previousHandler);
    }
}

- (Visual *) visual {
    return _visualInfo != NULL ? _visualInfo->visual
                               : DefaultVisual(_display, DefaultScreen(_display));
}

- (Drawable) drawable {
    return _window;
}

- (void) addEntriesToDeviceDictionary: (NSDictionary *) entries {
    [_deviceDictionary addEntriesFromDictionary: entries];
}

// Cocoa's global origin is the bottom-left corner of the main monitor, so both
// axes are relative to that monitor's rectangle, not to the root window. With one
// monitor that is the whole root and this is the plain flip against its height.
- (O2Rect) transformFrame: (O2Rect) frame {
    X11Frame root = X11FrameToRoot([self primaryFrameInPoints],
                                   (X11Frame){frame.origin.x, frame.origin.y,
                                              frame.size.width, frame.size.height});
    return NSMakeRect(root.x, root.y, fmax(root.width, 1.0), fmax(root.height, 1.0));
}

// The inverse of -transformFrame:, root coordinates to Cocoa's global space.
- (O2Rect) untransformFrame: (O2Rect) rect {
    X11Frame frame = X11FrameFromRoot([self primaryFrameInPoints],
                                      (X11Frame){rect.origin.x, rect.origin.y,
                                                 rect.size.width, rect.size.height});
    return NSMakeRect(frame.x, frame.y, frame.width, frame.height);
}

// The main monitor in root coordinates, in the unit of _frame.
- (X11Frame) primaryFrameInPoints {
    return [(X11Display *) [NSDisplay currentDisplay] primaryFrameInPoints];
}

- (CGFloat) backingScaleFactor {
    return [(X11Display *) [NSDisplay currentDisplay] backingScale];
}

// The display's device pixels per point changed. _frame stays in points, so the
// X window is resized to the same points at the new scale, the backing surface
// is rebuilt at the new device size, and the window and its views are told
// before they redraw.
- (void) displayBackingScaleChangedFrom: (CGFloat) oldScale {
    O2Rect deviceFrame = [self deviceRect: _frame];
    XMoveResizeWindow(_display, _window, deviceFrame.origin.x,
                      deviceFrame.origin.y, deviceFrame.size.width,
                      deviceFrame.size.height);
    [_context release];
    _context = nil;
    [_delegate platformWindowDidInvalidateCGContext: self];
    if ([_delegate respondsToSelector: @selector(platformWindow:didChangeBackingScaleFrom:)])
        [_delegate platformWindow: self didChangeBackingScaleFrom: oldScale];
    [_delegate platformWindowExposed: self
                              inRect: NSMakeRect(0, 0, _frame.size.width,
                                                 _frame.size.height)];
}

// Rounds points to whole device pixels. Origins are rounded plainly, extents
// are at least one pixel (a zero-size X window is invalid); one rounding for
// both keeps the X window and the backing surface in agreement.
static CGFloat X11ScaledOrigin(CGFloat logical, CGFloat scale) {
    return floor(logical * scale + 0.5);
}

static CGFloat X11ScaledExtent(CGFloat logical, CGFloat scale) {
    return fmax(X11ScaledOrigin(logical, scale), 1.0);
}

- (NSSize) deviceSize: (NSSize) size {
    CGFloat scale = [self backingScaleFactor];
    return NSMakeSize(X11ScaledExtent(size.width, scale),
                      X11ScaledExtent(size.height, scale));
}

- (O2Rect) deviceRect: (O2Rect) rect {
    CGFloat scale = [self backingScaleFactor];
    NSSize size = [self deviceSize: rect.size];
    return NSMakeRect(X11ScaledOrigin(rect.origin.x, scale),
                      X11ScaledOrigin(rect.origin.y, scale), size.width,
                      size.height);
}

- (NSPoint) transformPoint: (NSPoint) pos; {
    return NSMakePoint(pos.x, _frame.size.height - pos.y);
}

- (X11SubWindow *) createSubWindowWithFrame: (CGRect) frame {
    // Subwindows take this window's visual, so settle it before they exist.
    [self settleVisual];
    return [[[X11SubWindow alloc] initWithParentWindow: self
                                                 frame: frame] autorelease];
}

@end
