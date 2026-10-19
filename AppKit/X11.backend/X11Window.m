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

#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>
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
#import "X11Fullscreen.h"
#import "X11InputShape.h"
#import "X11SubWindow.h"
#import "X11Window.h"
#import <X11/Xatom.h>
#import <X11/Xutil.h>

@implementation X11Window

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

static NSData *makeWindowIcon() {
    static NSMutableData *res;

    if (res != nil)
        return res;

    // Figure out the path.
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *name = [bundle objectForInfoDictionaryKey: @"CFBundleIconFile"];
    if (name == nil || [name length] == 0)
        return nil;
    NSString *path = [bundle pathForImageResource: name];
    if (path == nil) {
        NSLog(@"Cannot find an icon file named %@", name);
        return nil;
    }
    NSURL *url = [NSURL fileURLWithPath: path];

    O2ImageSource *imageSource = [O2ImageSource newImageSourceWithURL: url
                                                              options: nil];
    if (imageSource == nil) {
        NSLog(@"Cannot parse the icon");
        return nil;
    }

    res = [[NSMutableData alloc] initWithCapacity: 32 * 32 * 4 + 2];
    O2ColorSpace *colorSpace = O2ColorSpaceCreateDeviceRGB();

    // Go over the images, turning them into the required format
    // and appending them to res.
    for (NSUInteger i = 0; i < [imageSource count]; i++) {

        O2Image *image = [imageSource createImageAtIndex: i options: nil];
        NSUInteger width = O2ImageGetWidth(image);
        NSUInteger height = O2ImageGetHeight(image);

        // Render the image in ARGB.
        O2BitmapContext *context = (O2BitmapContext *) O2BitmapContextCreate(
                NULL, width, height, 8, width * 4, colorSpace,
                kO2ImageAlphaPremultipliedFirst | kO2BitmapByteOrder32Host);

        [context drawImage: image inRect: O2RectMake(0, 0, width, height)];
        int *imageData = O2BitmapContextGetData(context);

        // Convert to the format accepted by Xlib.
        NSMutableData *data =
                [NSMutableData dataWithLength: width * height * sizeof(long)];
        long *dataPtr = (long *) [data mutableBytes];
        int count = width * height;
        for (int i = 0; i < count; i++) {
            dataPtr[i] = imageData[i];
        }

        struct {
            long w, h;
        } size = {width, height};
        [res appendBytes: &size length: sizeof(size)];
        [res appendData: data];

        [context release];
        [image release];
    }

    [colorSpace release];
    [imageSource release];

    return res;
}

- (void) setWindowIcon {

    NSData *data = makeWindowIcon();

    if (data == nil)
        return;

    XChangeProperty(
            _display, _window, XInternAtom(_display, "_NET_WM_ICON", False),
            XInternAtom(_display, "CARDINAL", False), 32, PropModeReplace,
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
    // TODO: get rid of these glX calls
    GLint att[] = {GLX_RGBA,
                   GLX_DOUBLEBUFFER,
                   GLX_RED_SIZE,
                   4,
                   GLX_GREEN_SIZE,
                   4,
                   GLX_BLUE_SIZE,
                   4,
                   GLX_DEPTH_SIZE,
                   4,
                   None};

    int screen = DefaultScreen(_display);

    if ((_visualInfo = glXChooseVisual(_display, screen, att)) == NULL) {
        NSLog(@"glXChooseVisual failed at %s %d", __FILE__, __LINE__);
    }

    Colormap cmap =
            XCreateColormap(_display, RootWindow(_display, _visualInfo->screen),
                            _visualInfo->visual, AllocNone);

    if (cmap < 0) {
        NSLog(@"XCreateColormap failed");
        [self release];
        return nil;
    }

    XSetWindowAttributes xattr;
    unsigned long xattr_mask;
    // Only windows that must stay out of the window manager's hands are
    // unmanaged: menus, popups, sheets and anything that cannot become key
    // (NSWindow answers NO for a borderless window unless its class overrides
    // -canBecomeKeyWindow, so only such windows change). A borderless
    // window that can become key (a borderless fullscreen game, a custom-chrome
    // app window) is a normal application window; left override-redirect it never
    // receives keyboard focus from a compositor and cannot be made fullscreen.
    xattr.override_redirect =
            (_styleMask == NSBorderlessWindowMask && !isPanel &&
             ([delegate isKindOfClass: [NSMenuWindow class]] ||
              [delegate isKindOfClass: NSClassFromString(@"NSPopUpWindow")] ||
              ![delegate canBecomeKeyWindow]))
                    ? True
                    : False;
    if (isSheetPanel) {
        xattr.override_redirect = True;
    }
    _overrideRedirect = xattr.override_redirect;
    xattr_mask = CWOverrideRedirect | CWColormap;
    xattr.colormap = cmap;

    _window = XCreateWindow(
            _display, DefaultRootWindow(_display), _frame.origin.x,
            _frame.origin.y, _frame.size.width, _frame.size.height, 0,
            (_visualInfo == NULL) ? CopyFromParent : _visualInfo->depth,
            InputOutput,
            (_visualInfo == NULL) ? CopyFromParent : _visualInfo->visual,
            xattr_mask, &xattr);

    [self syncDelegateProperties];

    Atom atm = XInternAtom(_display, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(_display, _window, &atm, 1);

    const char *name = [[[NSProcessInfo processInfo] processName] UTF8String];

    XClassHint classHint = {.res_name = (char *) name,
                            .res_class = (char *) name};
    XSetClassHint(_display, _window, &classHint);

    XSetWindowBackgroundPixmap(_display, _window, None);

    _isModal = [delegate isSheet] || [NSApp modalWindow] == delegate;
    // FIXME: There should be no need for this.
    _isModal |= [delegate isKindOfClass: NSClassFromString(@"NSSavePanel")];

    const char *windowType;
    BOOL isTransient = YES;
    if (_isModal) {
        windowType = "_NET_WM_WINDOW_TYPE_DIALOG";
    } else if ([delegate isKindOfClass: [NSMenuWindow class]] ||
               [delegate isKindOfClass: [NSPopUpWindow class]]) {
        windowType = "_NET_WM_WINDOW_TYPE_MENU";
    } else if (isPanel) {
        windowType = "_NET_WM_WINDOW_TYPE_UTILITY";
    } else {
        windowType = "_NET_WM_WINDOW_TYPE_NORMAL";
        isTransient = NO;
    }
    long windowTypeAtom = (long) XInternAtom(_display, windowType, False);
    XChangeProperty(_display, _window,
                    XInternAtom(_display, "_NET_WM_WINDOW_TYPE", False),
                    XA_ATOM, 32, PropModeReplace,
                    (const unsigned char *) &windowTypeAtom, 1);

    if (isTransient && [NSApp mainWindow]) {
        X11Window *mainWindow =
                (X11Window *) [[NSApp mainWindow] platformWindow];
        XSetTransientForHint(_display, _window, [mainWindow windowHandle]);
    }

    _xic = XCreateIC(x11disp->_xim,
        XNInputStyle, XIMPreeditNothing | XIMStatusNothing,
        XNClientWindow, _window,
        XNFocusWindow, _window,
        NULL);

    _cglWindow = CGLGetWindow((void *) _window);

    [(X11Display *) [NSDisplay currentDisplay] setWindow: self forID: _window];

    // FIXME: Move this call into setStyleMaskInternal below!
    if (_styleMask == NSBorderlessWindowMask) {
        [[self class] removeDecorationForWindow: _window onDisplay: _display];
    }
    [self setStyleMaskInternal: _styleMask force: YES];

    [self setWindowIcon];

    return self;
}

- (void) dealloc {
    [self invalidate];
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
        sh->min_width = sh->max_width = _frame.size.width;
        sh->min_height = sh->max_height = _frame.size.height;
    }

    // An untitled window that is managed (a borderless game or custom-chrome window)
    // positions itself: say so, or a window manager may place it as it likes
    // (ICCCM 4.1.2.3).
    if (!_overrideRedirect && !(mask & NSWindowStyleMaskTitled))
        sh->flags |= USPosition | PPosition;

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
        O2Rect device = [self transformFrame: frame];
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
        long states[2];
        int states_cnt = 0;
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
}

// The window manager changes _NET_WM_STATE on its own too (it leaves fullscreen
// on a keybinding), so follow it: a later setFrame: onto the same monitor then
// asks again instead of trusting the last request. While the window is unmapped
// the property is ours.
- (void) propertyNotify: (XPropertyEvent *) event {
    if (_mapped && event->atom == XInternAtom(_display, "_NET_WM_STATE", False))
        _fullscreenRequested = X11FullscreenIsSet(_display, _window);
}

- (void) setStyleMaskInternal: (NSUInteger) mask force: (BOOL) force {
    if (force || (mask & NSWindowStyleMaskResizable) !=
                         (_styleMask & NSWindowStyleMaskResizable)) {
        [self updateSizeHints: mask];
    }

    [self requestFullscreen: [self wantsFullscreenWithStyleMask: mask
                                                          frame: [self frame]]
                      force: force];
}

- (void) setStyleMask: (NSUInteger) mask {
    NSLog(@"X11Window setStyleMask: 0x%lx\n", (unsigned long) mask);

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

- (void) ensureMapped {
    if (!_mapped) {
        // A withdrawn window loses _NET_WM_STATE (EWMH), so a window that covers a
        // monitor has to say again, before it is mapped, that it is fullscreen.
        if ([self wantsFullscreenWithStyleMask: _styleMask frame: [self frame]])
            [self requestFullscreen: YES force: NO];
        XMapWindow(_display, _window);
        _mapped = YES;
    }
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

    // Click-through windows (overlays, tooltips) must not take the pointer from
    // the window below. Only a change needs a request.
    BOOL ignoresMouseEvents = [_delegate ignoresMouseEvents];
    if (ignoresMouseEvents != _ignoresMouseEvents && _window != 0 &&
        X11WindowSetIgnoresMouseEvents(_display, _window, ignoresMouseEvents)) {
        _ignoresMouseEvents = ignoresMouseEvents;
        XFlush(_display);
    }

    // TODO: background color
}

- (void) invalidate {
    // This is essentially dealloc; we release our contexts
    // and windows, but unlike dealloc, this method can be called
    // several times, so set everything to nil/NULL/0.
    [_context release];
    _context = nil;

    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;

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
        XDestroyIC(_xic);

        [(X11Display *) [NSDisplay currentDisplay] setWindow: nil
                                                       forID: _window];
        XDestroyWindow(_display, _window);
        _window = 0;
    }
}

- (Window) windowHandle {
    return _window;
}

- (O2Context *) createCGContextIfNeeded {
    if (_context == nil) {
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc]
                   initWithBytes: NULL
                           width: _frame.size.width
                          height: _frame.size.height
                bitsPerComponent: 8
                     bytesPerRow: 0
                      colorSpace: colorSpace
                      bitmapInfo: kO2ImageAlphaPremultipliedFirst |
                                  kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        _context = [[O2Context_builtin_FT alloc] initWithSurface: surface
                                                         flipped: NO];
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
    XTextProperty prop;
    const char *text = [title cString];
    XStringListToTextProperty((char **) &text, 1, &prop);
    XSetWMName(_display, _window, &prop);
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
    XMoveResizeWindow(_display, _window, frame.origin.x, frame.origin.y,
                      frame.size.width, frame.size.height);
    [self invalidateContextWithNewSize: frame.size];
    _frame = frame;
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
    _level = value;
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
    // The window manager drops the fullscreen state of a withdrawn window.
    _fullscreenRequested = NO;
    // A focus request still waiting for MapNotify is void once the window is
    // ordered out; otherwise a later non-key orderFront would take focus.
    _wantsInputFocus = NO;
}

- (void) placeAboveWindow: (NSInteger) otherNumber {
    X11Window *other = [X11Window windowWithWindowNumber: otherNumber];
    [self ensureMapped];

    if (!other) {
        XRaiseWindow(_display, _window);
    } else {
        Window w[2] = {_window, other->_window};
        XRestackWindows(_display, w, 1);
    }
}

- (void) placeBelowWindow: (NSInteger) otherNumber {
    X11Window *other = [X11Window windowWithWindowNumber: otherNumber];
    [self ensureMapped];

    if (!other) {
        XLowerWindow(_display, _window);
    } else {
        Window w[2] = {other->_window, _window};
        XRestackWindows(_display, w, 1);
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

static BOOL windowManagerIsRunning(Display *display) {
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

    if (windowManagerIsRunning(_display)) {
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
    if (_wantsInputFocus)
        [self requestInputFocus];
}

- (void) makeKey {
    [self ensureMapped];
    XRaiseWindow(_display, _window);
    // FocusIn activates the NSWindow, which makes it key again and ends up here.
    // Requesting focus from that path would answer every (possibly stale) FocusIn
    // with a new focus change, and two windows would bounce focus forever.
    if (!_receivingFocus)
        [self requestInputFocus];
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

- (void) miniaturize {
    XIconifyWindow(_display, _window, DefaultScreen(_display));
}

- (void) deminiaturize {
    XRaiseWindow(_display, _window);
}

- (BOOL) isMiniaturized {
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

        if ((error = CGLCreateContext(NULL, NULL, &_cglContext)) !=
            kCGLNoError) {
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

- (void) flushBuffer {
    if (_context == nil)
        return;
    O2ContextFlush(_context);
    [self openGLFlushBuffer];
}

- (void) setLastKnownCursorPosition: (CGPoint) point {
    _lastMotionPos = [self transformPoint: point];
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return [self transformPoint: _lastMotionPos];
}

// _frame is kept in root coordinates; -frame is in Cocoa's global space.
- (O2Rect) frame {
    return [self untransformFrame: _frame];
}

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
        // recursively get geometry to get absolute position
        BOOL success = YES;
        while (window && success) {
            XGetGeometry(_display, window, &root, &x, &y, &w, &h, &b, &d);
            success = XQueryTree(_display, window, &root, &parent, &children,
                                 &nchild);
            if (children)
                XFree(children);

            // first iteration: save our own w, h
            if (window == _window)
                rect = NSMakeRect(0, 0, w, h);
            rect.origin.x += x;
            rect.origin.y += y;
            window = parent;
        };

        [self invalidateContextWithNewSize: rect.size];
        _frame = rect;
    } @finally {
        XSetErrorHandler(previousHandler);
    }
}

- (Visual *) visual {
    return DefaultVisual(_display, DefaultScreen(_display));
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

- (NSPoint) transformPoint: (NSPoint) pos; {
    return NSMakePoint(pos.x, _frame.size.height - pos.y);
}

- (X11SubWindow *) createSubWindowWithFrame: (CGRect) frame {
    return [[[X11SubWindow alloc] initWithParentWindow: self
                                                 frame: frame] autorelease];
}

@end
