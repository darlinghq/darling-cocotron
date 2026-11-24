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

#import "X11Display.h"
#import "NSEvent_mouse.h"
#import "X11Cursor.h"
#import "X11DraggingManager.h"
#import "X11Pasteboard.h"
#import "X11LevelStacking.h"
#import "X11Crossing.h"
#import "../private-include/AppKit/NSEventTime.h"
#import "X11Window.h"
#import "X11AppMenu.h"
#import "X11DockSupport.h"
#import "../private-include/AppKit/NSGlobalMenu+Private.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSDebug.h>

#ifndef DARLING
#import <Foundation/NSSelectInputSource.h>
#import <Foundation/NSSocket_bsd.h>
#endif

#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontTypeface.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>

#import <Onyx2D/O2Font_freetype.h>

#import <OpenGL/CGLInternal.h>

#import "X11Touch.h"
#import "X11Gesture.h"
#import "X11Occlusion.h"
#import <X11/XKBlib.h>
#import <X11/Xutil.h>
#import <X11/extensions/XKBrules.h>
#import <X11/extensions/Xrandr.h>
#import "../../CoreGraphics/X11.backend/X11Monitors.h"
#import "../../CoreGraphics/X11.backend/X11RandR.h"
#import <CoreGraphics/CGWindowPrivate.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <X11/keysym.h>
#import <fcntl.h>
#import <fontconfig/fontconfig.h>
#import <stddef.h>

void NSColorSetCatalogColor(NSColorListName catalogName, NSColorName colorName, NSColor *color);

// A boolean preference of the user's org.darlinghq.AppKit domain, NO when unset.
// These are Darling's own settings for behaviour macOS does not have.
static BOOL appKitPreference(CFStringRef key) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(
            key, CFSTR("org.darlinghq.AppKit"), &valid);
    return valid && value;
}

@implementation X11Display

static int errorHandler(Display *display, XErrorEvent *errorEvent) {
    return [(X11Display *) [X11Display currentDisplay] handleError: errorEvent];
}

- init {
    if (self = [super init]) {
        // The process has one connection to the X server and CoreGraphics owns it: it reads its
        // socket, handles the events that are its own (hot keys, keymap, the displays) and gives the
        // rest to this display through the observer registered at the end. EGL also uses this Display
        // from compositor threads; CoreGraphics made Xlib thread-safe before opening it.
        if (_CGSNativeConnectionKind() != CGSNativeConnectionKindX11) {
            [self release];
            return nil;
        }
        _display = (Display *) _CGSNativeConnectionDisplay();
        if (_display == NULL) {
            [self release];
            return nil;
        }

        XSetErrorHandler(errorHandler);
        CGLRegisterNativeDisplay(_display);

        _windowsByID = [NSMutableDictionary new];

        [[NSNotificationCenter defaultCenter]
                addObserver: self
                   selector: @selector(_displayOverlayWindowCreated:)
                       name: (NSString *) _kCGSDisplayOverlayWindowCreated
                     object: nil];

        XSetLocaleModifiers("");
        _xim = XOpenIM(_display, NULL, NULL, NULL);

        if (!_xim) {
            NSLog(@"Failed to open XIM, falling back to im=none\n");

            XSetLocaleModifiers("@im=none");
            _xim = XOpenIM(_display, NULL, NULL, NULL);
        }

        // RandR events are CoreGraphics', which reports the new layout (see -nativeConnectionDisplayLayoutChanged).
        // The window manager publishes the focused window and the stacking order on the root window.
        XSelectInput(_display, DefaultRootWindow(_display), PropertyChangeMask);
        _occlusionDirty = YES;

        X11TouchInit(_display);

        int xwaylandOpcode, xwaylandEvent, xwaylandError;
        _isXwayland = XQueryExtension(_display, "XWAYLAND", &xwaylandOpcode,
                                      &xwaylandEvent, &xwaylandError);

        lastFocusedWindow = nil;
        _confinesPointer = appKitPreference(CFSTR("ConfinePointerToFullscreenWindows"));
        _controlActsAsCommand = appKitPreference(CFSTR("ControlKeyActsAsCommand"));

        // The general pasteboard and the CLIPBOARD selection show the same contents.
        NSPasteboardRegisterHostClipboard([X11Pasteboard hostClipboardOfDisplay: self]);

        // From here on CoreGraphics hands this display the events of the connection.
        _CGSSetNativeConnectionObserver(self);
    }
    return self;
}

// A display overlay window (CGLSetFullScreen) belongs to no NSWindow, so the
// application's input for it is taken up here: its key and pointer events are
// selected on this connection and the keyboard focus goes to it. Its events
// reach the application with no window and screen coordinates, as those of a
// captured display do on macOS. Relative mouse mode, if the application asked
// for it, takes its grab on the overlay.
- (void) _displayOverlayWindowCreated: (NSNotification *) notification {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread: _cmd
                               withObject: notification
                            waitUntilDone: YES];
        return;
    }
    NSNumber *native = [[notification userInfo] objectForKey: @"NativeWindow"];
    if (native == nil)
        return;
    Window overlay = (Window) [native unsignedLongValue];
    if (_overlayWindows == nil)
        _overlayWindows = [NSMutableSet new];
    [_overlayWindows addObject: native];
    _overlayWindow = overlay;
    _overlayPointerKnown = NO;
    XSelectInput(_display, overlay,
                 KeyPressMask | KeyReleaseMask | ButtonPressMask |
                 ButtonReleaseMask | PointerMotionMask | StructureNotifyMask);
    XSetInputFocus(_display, overlay, RevertToPointerRoot, CurrentTime);
    XFlush(_display);
    if (_relativeRequested && !_relativeMouse.active)
        [self beginRelativeMouse];
}

// The overlay is gone: the server released any grab on it.
- (void) _overlayWindowDestroyed: (Window) overlay {
    if (![_overlayWindows containsObject: @((unsigned long) overlay)])
        return;
    [_overlayWindows removeObject: @((unsigned long) overlay)];
    if (_overlayWindow == overlay)
        _overlayWindow = None;
    if (_relativeWindow == overlay)
        [self suspendRelativeMouse];
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    _CGSSetNativeConnectionObserver(nil);
    [_overlayWindows release];
    X11RelativeMouseEnd(&_relativeMouse);
    [_blankCursor release];
    [_defaultCursor release];

    // -init releases self when it cannot use the connection, so none of these may exist yet.
    // The connection itself is CoreGraphics'; it stays open.
    if (_xim)
        XCloseIM(_xim);

    [_appMenu release];
    [_windowsByID release];
    [super dealloc];
}

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    return [[X11Window alloc] initWithDelegate: delegate];
}

- (Display *) display {
    return _display;
}

// Device pixels per point. X11 has no scale protocol; CoreGraphics decides the scale of the displays (see
// X11ScaleChoose()), and the main display's is the one window geometry here uses.
- (CGFloat) backingScale {
    if (_backingScale > 0)
        return _backingScale;

    _backingScale = (CGFloat) _CGSDisplayBackingScaleFactor(CGMainDisplayID());
    return _backingScale;
}

// The layout of the monitors changed. The displays are CoreGraphics', which reads RandR on the shared
// connection: it has brought them up to date (and reported the change to the display reconfiguration
// callbacks, which is what posts NSApplicationDidChangeScreenParametersNotification) before it says so
// here, so what this display derives from the layout is dropped now.
- (void) nativeConnectionDisplayLayoutChanged {
    _pointerKnown = NO;
    // The root may have shrunk or a monitor gone: the pointer's reachable
    // area, and with it a relative-mode grab's bounds, changed.
    [self resnapshotRelativeMouse];
    _primaryRootFrameValid = NO;
    // Whether the focused window covers a monitor depends on the layout.
    _occlusionCoverValid = NO;
    _occlusionDirty = YES;
    [self reevaluateBackingScale];
}

// Called when the displays changed, from any thread: the main monitor's rectangle is read again.
- (void) _invalidateScreens {
    [super _invalidateScreens];
    _primaryRootFrameValid = NO;
}

// X11 has no scale event: the scale comes from the user's setting or the
// session's GDK_SCALE (CoreGraphics reads them with the displays), so the places
// where it is looked at again are the moments the display layout changes. When
// the value differs from the one in use, the screens drop their cached frames and every window
// keeps its size in points at the new scale, and learns of the change (which
// posts NSWindowDidChangeBackingPropertiesNotification).
- (void) reevaluateBackingScale {
    CGFloat oldScale = _backingScale;
    if (oldScale <= 0)
        return; // Nothing has used a scale yet; the first use reads it.
    _backingScale = 0;
    CGFloat newScale = [self backingScale];
    if (newScale == oldScale)
        return;

    [self _invalidateScreens];
    for (id window in [_windowsByID allValues]) {
        if ([window isKindOfClass: [X11Window class]])
            [window displayBackingScaleChangedFrom: oldScale];
    }
}

// The windows carry the application icon in _NET_WM_ICON: when the application sets another one,
// the windows already shown are given it too.
- (void) applicationIconImageChanged {
    [super applicationIconImageChanged];
    for (id window in [_windowsByID allValues]) {
        if ([window isKindOfClass: [X11Window class]])
            [window setWindowIcon];
    }
    XFlush(_display);
}

// The main monitor's rectangle in root coordinates, device pixels: the origin
// of the global coordinate space, as on macOS. With one monitor, or without
// RandR, it is the root window. It is the monitor CoreGraphics lists first (the
// choice is X11Monitors.h's).
- (NSRect) primaryRootFrame {
    if (!_primaryRootFrameValid) {
        int count = 0, primary = -1;
        X11Monitor *monitors = X11MonitorsCopy(_display, &count, &primary);

        _primaryRootFrame =
                monitors != NULL && primary >= 0
                        ? NSMakeRect(monitors[primary].x, monitors[primary].y,
                                     monitors[primary].width, monitors[primary].height)
                        : NSMakeRect(0, 0, DisplayWidth(_display, DefaultScreen(_display)),
                                     DisplayHeight(_display, DefaultScreen(_display)));
        free(monitors);
        _primaryRootFrameValid = YES;
    }
    return _primaryRootFrame;
}

// The main monitor in root coordinates, in the unit of window frames: points.
- (X11Frame) primaryFrameInPoints {
    NSRect primary = [self primaryRootFrame];
    CGFloat scale = [self backingScale];
    return (X11Frame){NSMinX(primary) / scale, NSMinY(primary) / scale,
                      NSWidth(primary) / scale, NSHeight(primary) / scale};
}

// Converts a point in root coordinates (device pixels) to CoreGraphics' global
// space (points).
- (NSPoint) cgPointFromRoot: (NSPoint) root {
    CGFloat scale = [self backingScale];
    X11Point point = X11CGPointFromRoot([self primaryFrameInPoints],
                                        (X11Point){root.x / scale, root.y / scale});
    return NSMakePoint(point.x, point.y);
}

- (void) textInputCandidateRectChangedInWindow: (NSWindow *) window {
    X11Window *platformWindow = (X11Window *) [window platformWindow];

    if ([platformWindow isKindOfClass: [X11Window class]])
        [platformWindow updateInputMethodSpot];
}

// The file chooser portal names a parent window of an X11 client as "x11:"
// and the window's id in hexadecimal.
- (NSString *) portalParentHandleForWindow: (NSWindow *) window {
    X11Window *platformWindow = (X11Window *) [window platformWindow];

    if (![platformWindow isKindOfClass: [X11Window class]])
        return nil;
    return [NSString stringWithFormat: @"x11:%lx", (unsigned long) [platformWindow windowHandle]];
}

- (int) keyboardLayoutId {
    int major = XkbMajorVersion, minor = XkbMinorVersion;
    XkbStateRec state;

    if (!XkbLibraryVersion(&major, &minor))
        return -1;
    if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
        return -1;
    if (XkbGetState(_display, XkbUseCoreKbd, &state) == Success)
        return state.group;

    return -1;
}

- (void) keyboardLayoutName: (NSString **) name
                   fullName: (NSString **) fullName
{
    int major = XkbMajorVersion, minor = XkbMinorVersion;

    if (name)
        *name = @"?";
    if (fullName)
        *fullName = @"?";

    if (!XkbLibraryVersion(&major, &minor))
        return;
    if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
        return;

    XkbStateRec state;
    if (XkbGetState(_display, XkbUseCoreKbd, &state) != Success)
        return;

    XkbDescPtr desc =
            XkbGetKeyboard(_display, XkbAllComponentsMask, XkbUseCoreKbd);
    if (!desc)
        return;

    if (fullName != NULL) {
        char *group = XGetAtomName(_display, desc->names->groups[state.group]);

        if (group != NULL) {
            *fullName = [NSString stringWithUTF8String: group];
            XFree(group);
        }
    }

    XkbRF_VarDefsRec vd;
    if (name != NULL && XkbRF_GetNamesProp(_display, NULL, &vd)) {
        char *saveptr;
        char *tok = strtok_r(vd.layout, ",", &saveptr);

        for (int i = 0; i < state.group; i++) {
            tok = strtok_r(NULL, ",", &saveptr);
            if (tok == NULL)
                break;
        }

        if (tok != NULL) {
            *name = [NSString stringWithUTF8String: tok];
        }
    }
}

- (NSUInteger) currentModifierFlags {
    XkbStateRec r;
    if (XkbGetState(_display, XkbUseCoreKbd, &r) != Success)
        return 0;

    return [self modifierFlagsForState: r.mods];
}

- (NSUInteger) pressedMouseButtons {
    Window root, child;
    int rootX, rootY, winX, winY;
    unsigned int mask = 0;

    if (!XQueryPointer(_display, DefaultRootWindow(_display), &root, &child,
                       &rootX, &rootY, &winX, &winY, &mask))
        return 0;

    // X numbers the buttons by position (1 left, 2 middle, 3 right); Cocoa
    // numbers them 0 left, 1 right, 2 middle. The core protocol only reports
    // the state of buttons 1 to 5, and 4 and 5 are the wheel.
    NSUInteger buttons = 0;
    if (mask & Button1Mask)
        buttons |= 1 << 0;
    if (mask & Button3Mask)
        buttons |= 1 << 1;
    if (mask & Button2Mask)
        buttons |= 1 << 2;
    return buttons;
}

- (NSDraggingManager *) draggingManager {
    return [X11DraggingManager sharedManager];
}

// Activating another process asks the window manager to activate its
// frontmost window with an EWMH _NET_ACTIVE_WINDOW request, which CoreGraphics
// makes (its window system layer owns the process-to-window mapping). The
// window manager decides, and may refuse to steal focus; without one, nothing
// can be activated. The current process is activated through its own windows
// by NSApplication.
- (BOOL) activateProcessIdentifier: (pid_t) processIdentifier {
    if (processIdentifier <= 0 || processIdentifier == getpid() ||
        !X11WindowManagerIsRunning(_display))
        return NO;

    return _CGSActivateProcess(processIdentifier,
                               kCGSActivateProcessFrontWindowOnly) ==
           kCGErrorSuccess;
}

- (void) hideCursor {
    if (!_blankCursor)
        _blankCursor = [[X11Cursor alloc] initBlank];
    [self setCursor: _blankCursor];
}

- (void) unhideCursor {
    NSCursor *current = [NSCursor currentCursor];
    if (current != nil) {
        [current push];
        [current pop];
    } else {
        if (!_defaultCursor)
            _defaultCursor = [[X11Cursor alloc] init];
        [self setCursor: _defaultCursor];
    }
}

- (BOOL) cursorAwaitsPointerMotion {
    return _cursorHiddenUntilMouseMoves;
}

// Windows re-select their events when the wait for motion starts and when it ends.
- (void) selectPointerMotionOnWindows {
    for (id window in [_windowsByID allValues]) {
        if ([window isKindOfClass: [X11Window class]])
            [window syncDelegateProperties];
    }
}

- (void) setCursorHiddenUntilMouseMoves: (BOOL) flag {
    BOOL awaited = _cursorHiddenUntilMouseMoves;

    [super setCursorHiddenUntilMouseMoves: flag];
    if (awaited != _cursorHiddenUntilMouseMoves)
        [self selectPointerMotionOnWindows];
}

- (void) pointerMoved {
    BOOL awaited = _cursorHiddenUntilMouseMoves;

    [super pointerMoved];
    if (awaited)
        [self selectPointerMotionOnWindows];
}

// Arrow, IBeam, HorizontalResize, VerticalResize
- (id) cursorWithName: (NSString *) name {
    unsigned int shape = XC_left_ptr;
    const char *xname = "left_ptr";

    if ([name isEqualToString: @"arrowCursor"])
        xname = "left_ptr";
    else if ([name isEqualToString: @"closedHandCursor"])
        xname = "hand3";
    else if ([name isEqualToString: @"crosshairCursor"])
        xname = "crosshair";
    // else if([name isEqualToString:@"disappearingItemCursor"])
    // shape = XC_left_ptr;
    else if ([name isEqualToString: @"IBeamCursor"])
        xname = "xterm";
    else if ([name isEqualToString: @"IBeamCursorForVerticalLayout"])
        xname = "vertical-text";
    else if ([name isEqualToString: @"zoomInCursor"])
        xname = "zoom-in";
    else if ([name isEqualToString: @"zoomOutCursor"])
        xname = "zoom-out";
    else if ([name isEqualToString: @"openHandCursor"])
        xname = "fleur";
    else if ([name isEqualToString: @"pointingHandCursor"])
        xname = "hand";
    else if ([name isEqualToString: @"resizeDownCursor"])
        xname = "bottom_side";
    else if ([name isEqualToString: @"resizeLeftCursor"])
        xname = "left_side";
    else if ([name isEqualToString: @"resizeLeftRightCursor"])
        xname = "h_double_arrow";
    else if ([name isEqualToString: @"resizeRightCursor"])
        xname = "right_side";
    else if ([name isEqualToString: @"resizeUpCursor"])
        xname = "top_side";
    else if ([name isEqualToString: @"resizeUpDownCursor"])
        xname = "v_double_arrow";
    else if ([name isEqualToString: @"frameResizeNorthWestCursor"])
        xname = "top_left_corner";
    else if ([name isEqualToString: @"frameResizeNorthEastCursor"])
        xname = "top_right_corner";
    else if ([name isEqualToString: @"frameResizeSouthEastCursor"])
        xname = "bottom_right_corner";
    else if ([name isEqualToString: @"frameResizeSouthWestCursor"])
        xname = "bottom_left_corner";
    else if ([name isEqualToString: @"frameResizeNorthWestSouthEastCursor"])
        xname = "fd_double_arrow";
    else if ([name isEqualToString: @"frameResizeNorthEastSouthWestCursor"])
        xname = "bd_double_arrow";

    return [[[X11Cursor alloc] initWithName: xname] autorelease];
}

- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot {
    return [[[X11Cursor alloc] initWithImage: image
                                    hotPoint: hotSpot] autorelease];
}

- (void) setCursor: (id) cursor {
    Cursor c = ((X11Cursor *) cursor).cursor;
    Window root = DefaultRootWindow(_display);

    // Define the cursor on the window the pointer is actually over. Defining it only on the
    // key window left every other window with its own cursor, so moving between windows
    // showed two pointers at once - the stale cursor of the window under the mouse plus the
    // key window's cursor. XQueryPointer reports the child window under the pointer; fall
    // back to the root (and the key window) when there is none, so the cursor always has a
    // defined target.
    Window child = None, returnedRoot = None, target = None;
    int rx, ry, wx, wy;
    unsigned int mask;
    XQueryPointer(_display, root, &returnedRoot, &child, &rx, &ry, &wx, &wy, &mask);
    target = child;

    if (target == None) {
        CGWindow *key = [[NSApp keyWindow] platformWindow];
        if (key != nil)
            target = [(X11Window *) key windowHandle];
    }

    XDefineCursor(_display, target != None ? target : root, c);
    XSync(_display, False);
    _cursorHidden = cursor != nil && cursor == _blankCursor;
}

- (void) beep {
    XBell(_display, 100);
}



- (BOOL) queryPointerRootX: (int *) x y: (int *) y state: (unsigned int *) state {
    if (_pointerKnown) {
        *x = _pointerRootX;
        *y = _pointerRootY;
        *state = _pointerState;
        return YES;
    }
    // Not known from the event stream: ask the server, and again next time.
    Window root, child;
    int winX, winY;
    return XQueryPointer(_display, DefaultRootWindow(_display), &root, &child,
                         x, y, &winX, &winY, state);
}

// Tracks the pointer from the event stream, so that asking for the mouse
// location, as applications do every frame, costs no round trip while the
// pointer moves over our windows. Motion over other clients' windows is not
// reported, which is why every event that can precede such motion forgets it.
- (void) trackPointerForEvent: (XEvent *) ev {
    switch (ev->type) {
    case MotionNotify:
        _pointerKnown = ev->xmotion.same_screen &&
                ev->xmotion.root == DefaultRootWindow(_display);
        _pointerRootX = ev->xmotion.x_root;
        _pointerRootY = ev->xmotion.y_root;
        _pointerState = ev->xmotion.state;
        break;
    case ButtonPress:
    case ButtonRelease:
    case KeyPress:
    case KeyRelease:
    case EnterNotify:
    case LeaveNotify:
    case FocusIn:
    case FocusOut:
    case KeymapNotify:
        _pointerKnown = NO;
        break;
    default:
        break;
    }
}

- (NSPoint) mouseLocation {
    int root_x = 0, root_y = 0;
    unsigned int mask;

    if (_relativeMouse.active) {
        // The cursor is disassociated: report the frozen (virtual) position, as macOS does.
        root_x = (int) _relativeMouse.virtualX;
        root_y = (int) _relativeMouse.virtualY;
    } else {
        [self queryPointerRootX: &root_x y: &root_y state: &mask];
    }
    // Cocoa's global space, as +[NSEvent mouseLocation] reports on macOS: points,
    // origin at the main monitor's bottom-left corner, y up, so the result can be
    // compared with window and screen frames. CGEventGetLocation() reports the same
    // point in CoreGraphics' y-down space (see CGSConnectionX11).
    // -[X11Window mouseLocationOutsideOfEventStream] is window-local.
    CGFloat scale = [self backingScale];
    X11Point point = X11PointFromRoot([self primaryFrameInPoints],
                                      (X11Point){root_x / scale, root_y / scale});
    return NSMakePoint(point.x, point.y);
}

- (void) setWindow: (id) window forID: (XID) i {
    if (window)
        [_windowsByID
                setObject: window
                   forKey: [NSNumber
                                   numberWithUnsignedLong: (unsigned long) i]];
    else {
        // A window replaced by another X window ends its pinch here, while it is still known and
        // has its delegate; -[X11Window invalidate] ends it earlier.
        [self cancelPinchOnWindow: i];
        [_windowsByID removeObjectForKey: [NSNumber numberWithUnsignedLong:
                                                            (unsigned long) i]];

        [_appMenu windowDestroyed: i];

        // if "lastFocusedWindow" is dying, drop it
        //
        // this is an ugly hack because we miss FocusOut events sometimes and
        // retaining the window causes it to keep popping back up endlessly even after dismissing it
        if (lastFocusedWindow && [[lastFocusedWindow platformWindow] windowHandle] == i)
            lastFocusedWindow = nil;
        // The server released a grab on a window that became unviewable.
        if (_confinedWindow == i)
            _confinedWindow = None;
        // The server released a grab on a destroyed window.
        if (_relativeWindow == i)
            [self suspendRelativeMouse];
    }
}

// The menu bar window is a dock that the window manager has to place at the top of the screen. Under a manager
// that does not handle docks it would float over the windows of the application (see X11DockSupport.h), so
// there the menu is outside the windows only when the desktop has a global menu, as on Wayland, and the
// windows draw it themselves otherwise. -appMenu is not used: it asks +[NSWindow _usesInWindowMenuBar], which
// is what is being answered.
- (BOOL) _showsMainMenuOutsideWindows {
    if (X11WindowManagerPlacesDocks(_display))
        return YES;
    if (_appMenu == nil)
        _appMenu = [[X11AppMenu alloc] initWithDisplay: _display];
    if ([_appMenu globalMenuPresent])
        return YES;
    [_appMenu release];
    _appMenu = nil;
    return NO;
}

- (X11AppMenu *) appMenu {
    if (_appMenu == nil && ![NSWindow _usesInWindowMenuBar])
        _appMenu = [[X11AppMenu alloc] initWithDisplay: _display];
    return _appMenu;
}

- (void) _mainMenuDidChange: (NSMenu *) menu {
    [[self appMenu] setMainMenu: menu];
}

- (id) windowForID: (XID) i {
    return [_windowsByID objectForKey: [NSNumber numberWithUnsignedLong: i]];
}

// Xlib may have read events into its own queue, which leaves the connection's descriptor quiet
- (void) willWaitForEvents {
    [self processPendingEvents];
}

// With ControlKeyActsAsCommand set, Control+C, V and X (without Command or
// Option; Shift is kept) are the copy, paste and cut shortcuts of macOS; every
// other Control chord is left alone.
- (BOOL) controlStandsInForCommand: (NSEventModifierFlags) flags
                       keyEquivalent: (unichar) key
{
    return _controlActsAsCommand && (flags & NSControlKeyMask) &&
           !(flags & (NSCommandKeyMask | NSAlternateKeyMask)) &&
           (key == 'c' || key == 'v' || key == 'x');
}

- (NSEventModifierFlags) modifierFlagsForState: (unsigned int) state {
    NSEventModifierFlags ret = 0;
    if (state & ShiftMask)
        ret |= NSShiftKeyMask;
    if (state & ControlMask)
        ret |= NSControlKeyMask;
    // if (state & Mod2Mask) // Mod2Mask is numlock
    //   ret |= NSCommandKeyMask;
    if (state & LockMask)
        ret |= NSAlphaShiftKeyMask;
    if (state & Mod4Mask)
        ret |= NSCommandKeyMask;
    if (state & Mod1Mask)
        ret |= NSAlternateKeyMask;
    if (state & Mod5Mask) // AltGr
        ret |= NSFunctionKeyMask;

    return ret;
}

// Cocoa groups clicks only within its double-click interval and four logical
// points of the preceding press, and only for the same button in the same
// window. Without the button and the window, a left click followed by a right
// click inside the interval was reported as a double click; without the
// distance, a click on a far side of a window was too. The X server's own
// timestamp is used rather than the wall clock, which the client cannot
// compare against a server that may be a different machine, and its unsigned
// subtraction covers the 32-bit wrap.
- (NSInteger) countClickForButton: (unsigned int) button
                                  window: (XID) window
                                   point: (NSPoint) point
                                   time: (Time) time {
    CGFloat dx = point.x - _lastClickPoint.x;
    CGFloat dy = point.y - _lastClickPoint.y;
    if (_lastClickWindow == window && _lastClickButton == button &&
        (uint32_t) (time - _lastClickTime) < [self doubleClickInterval] * 1000 &&
        dx * dx + dy * dy <= 16 && _clickCount < NSIntegerMax)
        _clickCount++;
    else
        _clickCount = 1;
    _lastClickTime = time;
    _lastClickButton = button;
    _lastClickWindow = window;
    _lastClickPoint = point;
    [_buttonClickCounts setObject: @(_clickCount) forKey: @(button)];
    return _clickCount;
}

// Cocoa numbers the mouse buttons in press order from 0 (left), 1 (right) and
// 2 for everything else, so an app reading +[NSEvent buttonNumber] for the
// right button gets 3 and reads the middle button as the right one. X numbers
// them by position instead: 1 left, 3 right, 2 middle.
static NSInteger cocoaButtonNumber(unsigned int xButton) {
    switch (xButton) {
    case Button1: return 0;
    case Button3: return 1;
    case Button2: return 2;
    default:
        // X buttons 4 to 7 are the two wheels and never get here. The extra
        // buttons start at 8 (back) and 9 (forward), which Cocoa numbers 3
        // and 4, right after the middle button.
        return xButton >= 8 ? (NSInteger) xButton - 5 : (NSInteger) xButton;
    }
}

// Returns the window numbers of this app's windows, frontmost first, using the X server's stacking
// order: XQueryTree lists the root's children bottom to top. Under a reparenting window manager our
// top-level windows are children of frame windows, so each root child is matched against our windows
// and their ancestors.
static XErrorHandler previousOrderingErrorHandler;

// Windows (for example a window manager's frame, when a window closes) can be destroyed while
// -orderedWindowNumbers walks the tree. XQueryTree then fails with BadWindow, which isn't an error
// there; any other error goes to the handler that was installed before.
// The handler is swapped through the process-wide XSetErrorHandler and a file-scope variable, which
// is safe only because the X connection and this method are used from the main thread alone.
static int ignoreBadWindowWhileOrdering(Display *display, XErrorEvent *errorEvent) {
    if (errorEvent->error_code == BadWindow)
        return 0;
    return previousOrderingErrorHandler ? previousOrderingErrorHandler(display, errorEvent) : 0;
}

- (NSArray *) orderedWindowNumbers {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableDictionary *byTopLevel = [NSMutableDictionary dictionary];
    Window root = DefaultRootWindow(_display);

    XErrorHandler previousHandler = XSetErrorHandler(ignoreBadWindowWhileOrdering);
    previousOrderingErrorHandler = previousHandler;
    @try {
        for (NSNumber *xid in _windowsByID) {
            // X11Pasteboard registers its helper X window in the same map; it has no window number.
            if (![_windowsByID[xid] isKindOfClass: [X11Window class]])
                continue;
            Window w = (Window) [xid unsignedLongValue];
            Window rootRet, parent, *children = NULL;
            unsigned int count;

            // Walk up to the root's direct child that contains this window.
            while (XQueryTree(_display, w, &rootRet, &parent, &children, &count)) {
                if (children)
                    XFree(children);
                children = NULL;
                if (parent == root || parent == None)
                    break;
                w = parent;
            }
            byTopLevel[@((unsigned long) w)] = _windowsByID[xid];
        }

        Window rootRet, parent, *children = NULL;
        unsigned int count = 0;
        if (XQueryTree(_display, root, &rootRet, &parent, &children, &count)) {
            for (unsigned int i = count; i > 0; i--) {
                id window = byTopLevel[@((unsigned long) children[i - 1])];
                if (window != nil)
                    [result addObject: @([window windowNumber])];
            }
            if (children)
                XFree(children);
        }
    } @finally {
        XSetErrorHandler(previousHandler);
        previousOrderingErrorHandler = NULL;
    }

    return result;
}

// An unmanaged window is above the frames that the window manager restacks around it, so the order
// by window level (see X11LevelStacking.h) is made by moving the unmanaged windows, never the
// managed ones. Called from the window code after it made its own request, and again when the window
// manager has framed and mapped a window (ReparentNotify, MapNotify), because it stacks a new frame
// by itself.
- (void) restackWindowsForLevelsAround: (X11Window *) anchor {
    if (![anchor takesPartInLevelStacking])
        return;

    XErrorHandler previousHandler = XSetErrorHandler(ignoreBadWindowWhileOrdering);
    previousOrderingErrorHandler = previousHandler;
    @try {
        BOOL anchorUnmanaged = [anchor isUnmanaged];
        Window anchorTop = X11TopLevelAncestor(_display, [anchor windowHandle]);

        for (NSNumber *xid in [_windowsByID allKeys]) {
            id candidate = _windowsByID[xid];
            if (candidate == anchor || ![candidate isKindOfClass: [X11Window class]])
                continue;
            X11Window *other = candidate;
            if (![other takesPartInLevelStacking])
                continue;

            if (anchorUnmanaged && [other isUnmanaged]) {
                // Two override-redirect windows (the menu bar and a borderless window that cannot become
                // key): the server stacks them in the order they were raised, so the level is applied here.
                Window otherTop = X11TopLevelAncestor(_display, [other windowHandle]);
                if (anchorTop == None || otherTop == None)
                    continue;
                if (X11UnmanagedBelowUnmanaged([anchor stackingLevel], [other stackingLevel]))
                    X11StackBelowIfAbove(_display, anchorTop, otherTop);
                else if (X11UnmanagedBelowUnmanaged([other stackingLevel], [anchor stackingLevel]))
                    X11StackBelowIfAbove(_display, otherTop, anchorTop);
                continue;
            }
            if ([other isUnmanaged] == anchorUnmanaged)
                continue;

            X11Window *unmanaged = anchorUnmanaged ? anchor : other;
            X11Window *managed = anchorUnmanaged ? other : anchor;
            Window otherTop = X11TopLevelAncestor(_display, [other windowHandle]);
            Window unmanagedTop = anchorUnmanaged ? anchorTop : otherTop;
            Window managedTop = anchorUnmanaged ? otherTop : anchorTop;
            if (unmanagedTop == None || managedTop == None)
                continue;
            if (X11UnmanagedBelowManaged(anchorUnmanaged, [unmanaged stackingLevel], [managed stackingLevel]))
                X11StackBelowIfAbove(_display, unmanagedTop, managedTop);
            else if (!anchorUnmanaged && X11UnmanagedAboveManaged([unmanaged stackingLevel], [managed stackingLevel]))
                X11StackAboveIfBelow(_display, unmanagedTop, managedTop);
        }
    } @finally {
        XSetErrorHandler(previousHandler);
        previousOrderingErrorHandler = NULL;
    }
}

// Xlib names only the first five buttons. 6 and 7 are conventionally the
// horizontal wheel, to the left and to the right.
enum {
    HorizontalScrollLeftButton = 6,
    HorizontalScrollRightButton = 7,
};
// While relative mode is active the cursor is the virtual one, not wherever the
// pointer physically is (it is put back under the cursor after each motion, but a
// click can arrive in between). Returns NO when the server cannot translate.
static BOOL relativeEventPoint(Display *dpy, X11Window *window, const X11RelativeMouse *mouse, NSPoint *point) {
    Window child;
    int winX, winY;
    if (dpy == NULL || window == nil ||
        !XTranslateCoordinates(dpy, DefaultRootWindow(dpy), [window windowHandle], (int) mouse->virtualX,
                               (int) mouse->virtualY, &winX, &winY, &child))
        return NO;
    *point = [window logicalPoint: NSMakePoint(winX, winY)];
    return YES;
}

// The Cocoa screen point (points, origin at the main monitor's bottom-left,
// y up) of a root pixel position: where an event for a display overlay window
// is located, as the window of such an event is nil.
- (NSPoint) screenPointFromRootX: (double) x y: (double) y {
    CGFloat scale = [self backingScale];
    X11Point point = X11PointFromRoot([self primaryFrameInPoints],
                                      (X11Point){x / scale, y / scale});
    return NSMakePoint(point.x, point.y);
}

// The window has the input focus: tell the NSWindow it is active, which makes it the key window unless
// the rule in -[NSWindow platformWindowActivated:displayIfNeeded:] keeps the key status where it is.
// Reached by FocusIn, and by -[X11Window makeKey] when the window already held the focus.
- (void) windowHoldsFocus: (X11Window *) window {
    id delegate = [window delegate];

    if (lastFocusedWindow) {
        [lastFocusedWindow platformWindowDeactivated: window
                             checkForAppDeactivation: NO];
        lastFocusedWindow = nil;
    }
    if (window != nil)
        window->_receivingFocus = YES;
    [delegate platformWindowActivated: window displayIfNeeded: YES];
    if (window != nil)
        window->_receivingFocus = NO;
    lastFocusedWindow = delegate;
    if (window != nil && window->_xic != NULL) {
        XSetICFocus(window->_xic);
        [window updateInputMethodSpot];
    }
}

// Whether the window is one of this process's own: an application window, or an overlay of the display.
- (BOOL) isOwnWindowID: (Window) window {
    return window != None && ([self windowForID: window] != nil ||
                              [_overlayWindows containsObject: [NSNumber numberWithUnsignedLong: (unsigned long) window]]);
}

// The window manager made a window of another client the active one: the application is no longer
// active, even when none of its own windows ever held the focus and so no focus-out will tell it.
- (void) noteActiveWindowOfAnotherClient {
    Window active = X11OcclusionActiveWindow(_display);

    if (active != None && ![self isOwnWindowID: active])
        [NSApp _systemFocusMovedToAnotherClient];
}

// Marks the occlusion state for a new judgement when the event can change it. Returns YES for the
// root window's and the watched foreign window's events, which nothing else is interested in.
// A ConfigureNotify that repeats the geometry of the previous one for the same window changes
// nothing, so it does not ask for a new judgement: a window manager may send one for every
// request that leaves the geometry as it was.
- (BOOL) noteOcclusionEvent: (XEvent *) ev window: (X11Window *) window {
    Window target = ev->xany.window;
    if (target == DefaultRootWindow(_display)) {
        if (ev->type != PropertyNotify)
            return NO; // RandR notifications
        Atom atom = ev->xproperty.atom;
        if (atom == XInternAtom(_display, "_NET_ACTIVE_WINDOW", False)) {
            _occlusionActiveKnown = NO;
            _occlusionDirty = YES;
            [self noteActiveWindowOfAnotherClient];
        } else if (atom == XInternAtom(_display, "_NET_CLIENT_LIST_STACKING", False)) {
            _occlusionDirty = YES;
        }
        return YES;
    }
    if (window == nil) {
        if (target == None || target != _occlusionWatchWindow)
            return NO;
        if (ev->type == DestroyNotify) {
            _occlusionWatchWindow = None;
            _occlusionActiveKnown = NO;
        }
        if (ev->type == ConfigureNotify) {
            XConfigureEvent *c = &ev->xconfigure;
            if (_occlusionWatchGeometryKnown && c->x == _occlusionWatchX && c->y == _occlusionWatchY &&
                c->width == _occlusionWatchWidth && c->height == _occlusionWatchHeight)
                return YES;
            _occlusionWatchGeometryKnown = YES;
            _occlusionWatchX = c->x;
            _occlusionWatchY = c->y;
            _occlusionWatchWidth = c->width;
            _occlusionWatchHeight = c->height;
        }
        _occlusionCoverValid = NO;
        _occlusionDirty = YES;
        // A property deleted on that window may be the end of a transfer another part is waiting for.
        return !(ev->type == PropertyNotify && ev->xproperty.state == PropertyDelete);
    }
    switch (ev->type) {
    case MapNotify:
    case UnmapNotify:
        _occlusionDirty = YES;
        break;
    case ConfigureNotify:
        if ([window noteConfigureGeometryChanged: &ev->xconfigure])
            _occlusionDirty = YES;
        break;
    }
    return NO;
}

// Judges every window of ours against the focused foreign window and tells the ones whose state changed.
- (void) updateOcclusion {
    _occlusionDirty = NO;
    Window root = DefaultRootWindow(_display);

    // The focused window and its geometry are read again only after an event that can change them.
    if (!_occlusionActiveKnown) {
        Window focused = X11OcclusionActiveWindow(_display);
        // The application's own windows never cover each other here.
        if ([self isOwnWindowID: focused])
            focused = None;
        _occlusionActive = focused;
        _occlusionActiveKnown = YES;
        _occlusionCoverValid = NO;
        _occlusionWatchGeometryKnown = NO;
    }
    Window active = _occlusionActive;

    // Watch the focused foreign window for size, fullscreen and unmap changes. Selecting input replaces
    // this client's earlier selection on that window.
    if (active != _occlusionWatchWindow) {
        X11OcclusionStopWatching(_display, _occlusionWatchWindow, [self isOwnWindowID: _occlusionWatchWindow]);
        _occlusionWatchWindow = active;
        if (active != None)
            XSelectInput(_display, active, StructureNotifyMask | PropertyChangeMask);
    }

    NSSet *windows = [NSSet setWithArray: [_windowsByID allValues]];
    X11FullscreenRect cover = {0};
    bool coverFullscreen = false, coverOpaque = false;
    unsigned long *stack = NULL, stackCount = 0;
    if (active != None && [windows count] > 0) {
        if (!_occlusionCoverValid) {
            X11FullscreenRect info = {0};
            bool fullscreen = false, opaque = false;
            _occlusionCoverOK = X11OcclusionCoverInfo(_display, active, &info, &fullscreen, &opaque);
            _occlusionCoverX = info.x;
            _occlusionCoverY = info.y;
            _occlusionCoverWidth = info.width;
            _occlusionCoverHeight = info.height;
            _occlusionCoverFullscreen = fullscreen;
            _occlusionCoverOpaque = opaque;
            _occlusionCoverValid = YES;
        }
        cover = (X11FullscreenRect){_occlusionCoverX, _occlusionCoverY, _occlusionCoverWidth,
                                    _occlusionCoverHeight};
        coverFullscreen = _occlusionCoverFullscreen;
        coverOpaque = _occlusionCoverOpaque;
        if (_occlusionCoverOK && coverFullscreen && coverOpaque)
            stack = X11OcclusionStackingList(_display, &stackCount);
    }

    for (X11Window *platform in windows) {
        if (![platform isKindOfClass: [X11Window class]])
            continue;
        NSWindow *delegate = [platform delegate];
        Window handle = [platform windowHandle];
        BOOL occluded = NO;
        if (stack != NULL && delegate != nil && handle != None) {
            XWindowAttributes attributes;
            Window child;
            int x, y;
            if (XGetWindowAttributes(_display, handle, &attributes) && attributes.map_state == IsViewable &&
                XTranslateCoordinates(_display, handle, root, 0, 0, &x, &y, &child)) {
                X11FullscreenRect own = {x, y, (unsigned int) attributes.width, (unsigned int) attributes.height};
                occluded = X11OcclusionCovers(own, cover, coverFullscreen, coverOpaque,
                                              X11OcclusionStackIndex(stack, stackCount, handle),
                                              X11OcclusionStackIndex(stack, stackCount, active));
            }
        }
        if (occluded == [platform isOccluded])
            continue;
        [platform setOccluded: occluded];
        if ([delegate respondsToSelector: @selector(platformWindowOcclusionChanged:)])
            [delegate platformWindowOcclusionChanged: platform];
    }
    if (stack != NULL)
        XFree(stack);
}

- (void) postXEvent: (XEvent *) ev {
    id event = nil;
    NSEventType type;
    NSPoint pos;
    X11Window* window = (X11Window*) [self windowForID: ev->xany.window];

    if ([self noteOcclusionEvent: ev window: window])
        return;
    // Pointer events of a display overlay have no window; they are located in
    // screen coordinates.
    BOOL overlay = window == nil &&
            [_overlayWindows containsObject: @((unsigned long) ev->xany.window)];

    id delegate = [window delegate];

    [self trackPointerForEvent: ev];

    // Expected warp echoes are among the events queued when the warp was
    // synced; motion ages them itself.
    if (_relativeMouse.active && ev->type != MotionNotify)
        X11RelativeMouseTick(&_relativeMouse);

    switch (ev->type) {
    case KeyPress:
    case KeyRelease:
        // CoreGraphics decodes the keyboard and posts the keys as CGEvents (and the modifier state the
        // pointer events carry); the NSEvents are made from those (-windowNumber:location:forKeyEvent:).
        break;

    case ButtonPress:;
        pos = overlay ? [self screenPointFromRootX: ev->xbutton.x_root
                                                 y: ev->xbutton.y_root]
                      : [window logicalPoint: NSMakePoint(ev->xbutton.x, ev->xbutton.y)];
        if (_relativeMouse.active) {
            if (overlay)
                pos = [self screenPointFromRootX: _relativeMouse.virtualX
                                               y: _relativeMouse.virtualY];
            else
                relativeEventPoint(_display, window, &_relativeMouse, &pos);
        }

        // A wheel notch arrives as a press/release pair and belongs to exactly
        // one of them, or the notch scrolls twice. The press carries it: a
        // release the client never sees (a grab, an unmap, focus lost while
        // the button is held) then cannot swallow the scroll, and the press
        // has already been accepted by the server when we get it. A notch is
        // not a click, so it must not touch the click count either.
        if (ev->xbutton.button >= Button4 &&
            ev->xbutton.button <= HorizontalScrollRightButton) {
            // Buttons 4 and 5 are the vertical wheel, 6 and 7 the horizontal
            // one. -[NSView scrollWheel:] adds the delta to the document view's
            // bounds origin, so a positive delta scrolls towards the larger
            // coordinate on both axes: the up and right buttons are positive.
            CGFloat deltaX = 0.0, deltaY = 0.0;
            switch (ev->xbutton.button) {
            case Button4: deltaY = 1.0; break;
            case Button5: deltaY = -1.0; break;
            case HorizontalScrollLeftButton: deltaX = -1.0; break;
            case HorizontalScrollRightButton: deltaX = 1.0; break;
            }
            event = [NSEvent
                    mouseEventWithType: NSScrollWheel
                              location: pos
                         modifierFlags: [self modifierFlagsForState: ev->xbutton
                                                                             .state]
                               window: delegate
                           clickCount: 0
                               deltaX: deltaX
                               deltaY: deltaY];
            [self postEvent: event atStart: NO];
            break;
        }

        switch (ev->xbutton.button) {
        case Button1:
            type = NSLeftMouseDown;
            break;
        case Button3:
            type = NSRightMouseDown;
            break;
        default:
            type = NSOtherMouseDown;
        }

        event = [NSEvent
                mouseEventWithType: type
                          location: pos
                     modifierFlags: [self modifierFlagsForState: ev->xbutton
                                                                         .state]
                            window: delegate
                        clickCount: [self
                                    countClickForButton: ev->xbutton.button
                                                   window: ev->xany.window
                                                    point: pos
                                                    time: ev->xbutton.time]
                            deltaX: 0.0
                            deltaY: 0.0];
        [(NSEvent_mouse *) event
                _setButtonNumber: cocoaButtonNumber(ev->xbutton.button)];
        // The window manager may focus the window for this very click, before
        // or after the press reaches us; the press is judged by what we knew
        // when it arrived, not by what the queue shows when it is taken.
        [(NSEvent_mouse *) event _setWindowWasKeyOnArrival: [delegate isKeyWindow]];
        [self postEvent: event atStart: NO];
        break;

    case ButtonRelease:;
        // The wheel's other half of the pair; the press already scrolled.
        if (ev->xbutton.button >= Button4 &&
            ev->xbutton.button <= HorizontalScrollRightButton)
            break;

        pos = overlay ? [self screenPointFromRootX: ev->xbutton.x_root
                                                 y: ev->xbutton.y_root]
                      : [window logicalPoint: NSMakePoint(ev->xbutton.x, ev->xbutton.y)];
        if (_relativeMouse.active) {
            if (overlay)
                pos = [self screenPointFromRootX: _relativeMouse.virtualX
                                               y: _relativeMouse.virtualY];
            else
                relativeEventPoint(_display, window, &_relativeMouse, &pos);
        }

        // The up of a click reports the count its down was given, so that a
        // double click's two downs are matched by their own ups. A release
        // with no press behind it (the app attached mid-drag) is a single
        // click: Cocoa never reports an up with a count of zero.
        NSNumber *upCount = [_buttonClickCounts objectForKey: @(ev->xbutton.button)];
        [_buttonClickCounts removeObjectForKey: @(ev->xbutton.button)];

        switch (ev->xbutton.button) {
        case Button1:
            type = NSLeftMouseUp;
            break;
        case Button3:
            type = NSRightMouseUp;
            break;
        default:
            type = NSOtherMouseUp;
        }

        event = [NSEvent
                mouseEventWithType: type
                          location: pos
                     modifierFlags: [self modifierFlagsForState: ev->xbutton
                                                                         .state]
                            window: delegate
                        clickCount: upCount ? [upCount integerValue] : 1
                            deltaX: 0.0
                            deltaY: 0.0];
        [(NSEvent_mouse *) event
                _setButtonNumber: cocoaButtonNumber(ev->xbutton.button)];
        [self postEvent: event atStart: NO];
        break;

    case MotionNotify:; {
            // NSLog(@"MotionNotify, x=%d, y=%d, xroot=%d, yroot=%d\n",
            // ev->xmotion.x, ev->xmotion.y, ev->xmotion.x_root,
            // ev->xmotion.y_root);

            CGPoint lastMotionPos = [window mouseLocationOutsideOfEventStream];
            pos = overlay ? [self screenPointFromRootX: ev->xmotion.x_root
                                                     y: ev->xmotion.y_root]
                          : [window logicalPoint: NSMakePoint(ev->xmotion.x,
                                                              ev->xmotion.y)];

            CGFloat deltaX, deltaY;

            if (_relativeMouse.active) {
                // The cursor is disassociated: physical motion only produces
                // deltas, the event reports the frozen cursor, and the pointer is
                // put back under it where the server honours warps. A warp's own
                // echo is not motion.
                bool recorded;
                X11RelativeMouseMotion relative = X11RelativeMouseMotionEvent(
                        _display, &_relativeMouse, &ev->xmotion,
                        [self warpsHonoured], &recorded);
                // An echo that could not be recorded would be taken for input.
                if (!recorded)
                    [self suspendRelativeMouse];
                if (!relative.post)
                    break;
                // Deltas are in points, like the absolute ones.
                CGFloat deltaScale = overlay ? [self backingScale]
                                             : [window backingScaleFactor];
                deltaX = relative.deltaX / deltaScale;
                deltaY = relative.deltaY / deltaScale;
                // The window's origin in root coordinates is (x_root - x, y_root - y).
                if (overlay)
                    pos = [self screenPointFromRootX: _relativeMouse.virtualX
                                                   y: _relativeMouse.virtualY];
                else
                    pos = [window logicalPoint: NSMakePoint(
                            _relativeMouse.virtualX - (ev->xmotion.x_root - ev->xmotion.x),
                            _relativeMouse.virtualY - (ev->xmotion.y_root - ev->xmotion.y))];
            } else if (overlay) {
                // Root pixels moved since the previous motion; y grows downwards.
                CGFloat scale = [self backingScale];
                deltaX = _overlayPointerKnown
                        ? (ev->xmotion.x_root - _overlayPointerX) / scale : 0;
                deltaY = _overlayPointerKnown
                        ? (ev->xmotion.y_root - _overlayPointerY) / scale : 0;
            } else {
                // Mouse deltas are in screen orientation, y growing downwards
                // (as CGEvent's kCGMouseEventDeltaY), while pos is window-local
                // with y growing upwards; relative mode reports root deltas,
                // which already grow downwards.
                deltaX = pos.x - lastMotionPos.x;
                deltaY = lastMotionPos.y - pos.y;
            }
            [window setLastKnownCursorPosition: pos];
            if (overlay) {
                _overlayPointerKnown = YES;
                _overlayPointerX = ev->xmotion.x_root;
                _overlayPointerY = ev->xmotion.y_root;
            }
            [self accumulateMouseDeltaX: deltaX y: deltaY];

            // X11 numbers the right button 3 (Button3Mask); Button2Mask is
            // the middle button, whose drags are other-mouse drags.
            type = NSMouseMoved;

            if (ev->xmotion.state & Button1Mask) {
                type = NSLeftMouseDragged;
            } else if (ev->xmotion.state & Button3Mask) {
                type = NSRightMouseDragged;
            } else if (ev->xmotion.state & Button2Mask) {
                type = NSOtherMouseDragged;
            }

            // The pointer moved: a cursor hidden until then comes back, even
            // when the application does not want the mouse-moved event.
            [self pointerMoved];
            if (type == NSMouseMoved && !overlay && ![delegate acceptsMouseMovedEvents])
                break;

            // Coalescing in the event queue replaces a queued moved or dragged event of
            // the same type for the same window with this one, and adds its deltas to this
            // one's (which is all an application gets in relative mode).
            event = [NSEvent
                    mouseEventWithType: type
                              location: pos
                         modifierFlags:
                                 [self modifierFlagsForState: ev->xmotion.state]
                                window: delegate
                            clickCount: 1
                                deltaX: deltaX
                                deltaY: deltaY];
            [self postEvent: event atStart: NO];

            [delegate platformWindowSetCursorEvent: window];
            break;
        }

    case EnterNotify:
        if (!_relativeMouse.active)
            [window setLastKnownCursorPosition:
                            [window logicalPoint: NSMakePoint(
                                                          ev->xcrossing.x,
                                                          ev->xcrossing.y)]];
        break;

    case LeaveNotify:
        // The pointer left the window (X11Crossing.h says which crossings mean that), and the event carries where it
        // was. The window re-evaluates its tracking areas at that position, as it does for a motion, and sends the
        // exits for the areas the position is outside. A leave that comes with the pointer still inside the window's
        // rectangle (another window mapped over it) finds the areas still containing it and sends nothing. A pointer
        // on another screen has no usable position here.
        if (window == nil || _relativeMouse.active || !ev->xcrossing.same_screen ||
            !X11LeaveNotifyMeansPointerLeft(ev->xcrossing.mode, ev->xcrossing.detail))
            break;
        [window setLastKnownCursorPosition:
                        [window logicalPoint: NSMakePoint(ev->xcrossing.x,
                                                          ev->xcrossing.y)]];
        [delegate platformWindowSetCursorEvent: window];
        break;

    case FocusIn:
        // Focus changes caused by a grab, or by the pointer entering the
        // window or one of its children, do not move the keyboard focus.
        if (ev->xfocus.mode == NotifyGrab || ev->xfocus.mode == NotifyUngrab)
            break;
        if (ev->xfocus.detail == NotifyPointer ||
            ev->xfocus.detail == NotifyPointerRoot ||
            ev->xfocus.detail == NotifyInferior)
            break;

        // The server can still report FocusIn (detail NotifyPointer) for a
        // window we have unmapped; an ordered-out window must not become key.
        if (window != nil && ![window isMapped])
            break;
        if ([delegate attachedSheet]) {
            [[delegate attachedSheet] makeKeyAndOrderFront: delegate];
            break;
        }
        [self windowHoldsFocus: window];
        // Losing the focus released the pointer grab; the application still
        // wants relative mode.
        if (_relativeRequested && !_relativeMouse.active)
            [self beginRelativeMouse];
        [self updatePointerConfinement];
        break;

    case FocusOut:
        if (ev->xfocus.mode == NotifyGrab || ev->xfocus.mode == NotifyUngrab)
            break;
        if (ev->xfocus.detail == NotifyPointer ||
            ev->xfocus.detail == NotifyPointerRoot ||
            ev->xfocus.detail == NotifyInferior)
            break;

        [delegate platformWindowDeactivated: window
                    checkForAppDeactivation: NO];
        lastFocusedWindow = nil;
        // Give the pointer back to other clients; relative mode stays requested
        // and resumes on FocusIn.
        [self suspendRelativeMouse];
        [self updatePointerConfinement];
        // Unlike XSetICFocus(), XUnsetICFocus() doesn't accept a NULL XIC.
        if (window != nil && window->_xic != NULL)
            XUnsetICFocus(window->_xic);
        break;

    case KeymapNotify:
        break;

    case Expose:;
        // The exposed area is in device pixels from the top-left corner; the
        // delegate takes points with y up.
        CGFloat exposeScale = [window backingScaleFactor];
        O2Rect rect = NSMakeRect(ev->xexpose.x / exposeScale,
                                 ev->xexpose.y / exposeScale,
                                 ev->xexpose.width / exposeScale,
                                 ev->xexpose.height / exposeScale);

        rect.origin.y =
                [window frame].size.height - rect.origin.y - rect.size.height;
        // The server sends one event per rectangle of an exposed area; the window is flushed
        // and the delegate told once, for their union, after the last one.
        if (![window addExposedRect: rect isLast: ev->xexpose.count == 0 exposedUnion: &rect])
            break;
        [window flushBuffer];
        [delegate platformWindowExposed: window inRect: rect];
        break;

    case GraphicsExpose:
        break;

    case NoExpose:
        break;

    case VisibilityNotify:
        break;

    case CreateNotify:
        break;

    case DestroyNotify:;
        [self _overlayWindowDestroyed: ev->xany.window];
        // we should never get this message before the WM_DELETE_WINDOW
        // ClientNotify so normally, window should be nil here.
        [window invalidate];
        break;

    case UnmapNotify:
        // The server released a grab whose window became unviewable.
        if (ev->xany.window == _relativeWindow)
            [self suspendRelativeMouse];
        if (ev->xany.window == _confinedWindow)
            _confinedWindow = None;
        break;

    case MapNotify:
        [window mapNotified];
        [self updatePointerConfinement];
        break;

    case MapRequest:
        break;

    case ReparentNotify:
        // A window manager frame has to point back at our window through XdndProxy
        // before a drag source can find it under the pointer.
        if ([window isKindOfClass: [X11Window class]]) {
            [(X11DraggingManager *) [self draggingManager]
                    windowReparented: (X11Window *) window
                              intoParent: ev->xreparent.parent];
            // A new frame is stacked by the window manager as it sees fit: put the
            // unmanaged windows that are meant to be below it where they belong.
            [(X11Window *) window restackForLevels];
        }
        break;

    case ConfigureNotify:; {
            // The server also sends a ConfigureNotify for a pure move, and for
            // every pixel of a drag, so reporting a resize unconditionally
            // posted NSWindowDidResizeNotification for all of them. NSWindow
            // resizes its background view, resets the cursor rects and saves
            // the frame on each of those, once per pixel of a drag.
            if (_relativeMouse.active && ev->xconfigure.window == _relativeWindow)
                [self resnapshotRelativeMouse];
            O2Rect oldFrame = [window frame];
            [window frameChanged];
            O2Rect newFrame = [window frame];
            [delegate platformWindow: window
                        frameChanged: newFrame
                             didSize: !NSEqualSizes(oldFrame.size, newFrame.size)];
            [self updatePointerConfinement];
            break;
        }

    case ConfigureRequest:
        break;

    case GravityNotify:
        break;

    case ResizeRequest:
        break;

    case CirculateNotify:
        break;

    case CirculateRequest:
        break;

    case PropertyNotify:
        if ([window respondsToSelector: @selector(propertyNotify:)]) {
            [window propertyNotify: &ev->xproperty];
            // The window may have entered or left fullscreen.
            [self updatePointerConfinement];
        } else if (window == nil) {
            // An incremental transfer is paced by the receiver deleting the
            // property, and that property lives on the receiver's window, which
            // belongs to another client and so is not in the window map. The
            // pasteboard that wrote it is the one waiting for the deletion.
            [(X11DraggingManager *) [self draggingManager]
                    handlePropertyChange: &ev->xproperty];
        }
        // An INCR transfer a pasteboard serves is paced by the requestor
        // deleting a property on its own window, usually another client's,
        // which therefore is not in the window map.
        if (ev->xproperty.state == PropertyDelete &&
            (window == nil || [window isKindOfClass: [X11Pasteboard class]]))
            [X11Pasteboard dispatchPropertyNotify: &ev->xproperty];
        break;

    case SelectionClear:
        if ([window respondsToSelector: @selector(selectionClear:)]) {
            [window selectionClear: &ev->xselectionclear];
        }
        break;

    case SelectionRequest:
        if ([window respondsToSelector: @selector(selectionRequest:)]) {
            [window selectionRequest: &ev->xselectionrequest];
        }
        break;

    case SelectionNotify:
        if ([window respondsToSelector: @selector(selectionNotify:)]) {
            [window selectionNotify: &ev->xselection];
        }
        break;

    case ColormapNotify:
        break;

    case ClientMessage:
        // XDND is entirely ClientMessage traffic: XdndEnter, XdndPosition,
        // XdndStatus, XdndDrop, XdndFinished and XdndLeave.
        if (ev->xclient.format == 32) {
            if ([window isKindOfClass: [X11Window class]]) {
                [(X11DraggingManager *) [self draggingManager]
                        handleXdndMessage: &ev->xclient
                                     toWindow: (X11Window *) window];
            } else if ([window isKindOfClass: [X11Pasteboard class]]) {
                // A drag's source window is the helper window of the pasteboard
                // that owns its selection, so the replies a target sends to the
                // source arrive there rather than on one of our windows.
                [(X11DraggingManager *) [self draggingManager]
                        handleXdndSourceMessage: &ev->xclient];
            }
        }
        if (ev->xclient.format == 32 &&
            ev->xclient.data.l[0] ==
                    XInternAtom(_display, "WM_DELETE_WINDOW", False)) {
            [[NSRunLoop currentRunLoop] cancelPerformSelector: @selector(platformWindowWillClose:)
                                                       target: delegate
                                                     argument: window];
            [[NSRunLoop currentRunLoop] performSelector: @selector(platformWindowWillClose:)
                                                 target: delegate
                                               argument: window
                                                  order: 0
                                                  modes: @[
                                                        NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                                                        NSEventTrackingRunLoopMode
                                                    ]];
        }
        break;

    case MappingNotify:
        // Xlib caches the keyboard and modifier mappings, and the client has
        // to tell it when they change, or XLookupString() and
        // XKeycodeToKeysym() keep answering for the old layout.
        if (ev->xmapping.request == MappingKeyboard ||
            ev->xmapping.request == MappingModifier)
            XRefreshKeyboardMapping(&ev->xmapping);
        break;

    case GenericEvent:
        // events of other extensions are not used
        X11TouchHandleEvent(self, ev);
        break;

    default:
        NSLog(@"Unknown X11 event type %i", ev->type);
        break;
    }
}

// CoreGraphics reads the connection and gives this display each event it did not handle itself (see
// CGSNativeConnection.h); an event that was only read into Xlib's queue while a request waited for its
// reply is still delivered, since CoreGraphics also reads before the run loop sleeps.
- (void) nativeConnectionEvent: (void *) event {
    XEvent *e = event;

    // An input method's reply (Xlib: every event goes through XFilterEvent()); key events are filtered in
    // -postXEvent:, where the input method's decision is used.
    if (e->type != KeyPress && e->type != KeyRelease && XFilterEvent(e, None))
        return;
    [self postXEvent: e];
}

// The text of a key press as the input method of its window composes it (CoreGraphics decodes the key and
// asks, since the input contexts are this display's: the input method stays in the application). nil when
// the window has no input context (no input method could be opened, or XCreateIC() failed), which makes
// CoreGraphics look the key up in the keymap itself.
- (NSString *) nativeConnectionComposedTextForKeyEvent: (void *) event keySym: (unsigned long *) keySym {
    XKeyEvent *keyEvent = event;
    X11Window *window = (X11Window *) [self windowForID: keyEvent->window];

    if (![window isKindOfClass: [X11Window class]] || window->_xic == NULL)
        return nil;

    char buf[64];
    char *text = buf;
    KeySym symbol = NoSymbol;
    Status status;
    int length = Xutf8LookupString(window->_xic, (XKeyPressedEvent *) keyEvent, buf, sizeof(buf) - 1, &symbol, &status);
    if (status == XBufferOverflow) {
        // Composed and input method text can be longer than buf. Nothing was copied and length is the
        // size needed; Xlib says to repeat the lookup with a large enough buffer.
        char *larger = malloc(length + 1);
        if (larger != NULL) {
            text = larger;
            length = Xutf8LookupString(window->_xic, (XKeyPressedEvent *) keyEvent, text, length, &symbol, &status);
        }
    }
    // The text and the keysym are only valid for the statuses that report them.
    if ((status != XLookupChars && status != XLookupBoth) || length < 0)
        length = 0;
    if (status != XLookupKeySym && status != XLookupBoth)
        symbol = NoSymbol;
    NSString *result = [[[NSString alloc] initWithBytes: text length: length encoding: NSUTF8StringEncoding] autorelease];
    if (text != buf)
        free(text);
    *keySym = symbol;
    return result != nil ? result : @"";
}

// The window a key event is for, and where the pointer is in it (the NSEvent made from a CGEvent of the
// keyboard). Key events belong to the key window whichever window of the application holds the X focus.
// That matters when the key window is one with alpha 0, which does not get the focus once the window manager
// moves it to a window that was ordered in. Menus and pop-ups that hold the focus keep the keys.
- (BOOL) windowNumber: (NSInteger *) windowNumber location: (NSPoint *) location forKeyEvent: (CGEventRef) event {
    // An event the application or Carbon posted names no window: it is for the key window.
    Window native = (Window) CGEventGetIntegerValueField(event, kCGSEventNativeWindow);
    if (native == None)
        return [super windowNumber: windowNumber location: location forKeyEvent: event];

    // A window of a display overlay (or one that is gone) is no NSWindow: the event has no window.
    X11Window *window = (X11Window *) [self windowForID: native];
    if (![window isKindOfClass: [X11Window class]])
        window = nil;
    NSWindow *keyWindow = [NSApp keyWindow];
    id keyPlatformWindow = [keyWindow platformWindow];
    if (window != nil && ![window isMenuOrPopup] && keyPlatformWindow != window &&
        [keyPlatformWindow isKindOfClass: [X11Window class]] && [keyPlatformWindow isMapped])
        window = keyPlatformWindow;

    *windowNumber = [[window delegate] windowNumber];
    *location = window != nil ? [window mouseLocationOutsideOfEventStream] : NSZeroPoint;
    return YES;
}

// ControlKeyActsAsCommand: the copy, paste and cut shortcuts of other systems work as macOS's. Control+C, V and
// X, without Command or Option, arrive as Command+C, V and X, whose characters are the letters rather than
// control codes. Other Control combinations are left alone.
- (NSEvent *) keyEventCreated: (NSEvent *) event fromCGEvent: (CGEventRef) cgEvent {
    if (!_controlActsAsCommand || ([event type] != NSKeyDown && [event type] != NSKeyUp))
        return event;
    NSString *letters = [event charactersIgnoringModifiers];
    if ([letters length] != 1)
        return event;
    unichar key = [letters characterAtIndex: 0];
    unichar lower = (key >= 'A' && key <= 'Z') ? key + ('a' - 'A') : key;
    NSEventModifierFlags flags = [event modifierFlags];
    if (lower >= 0x100 || ![self controlStandsInForCommand: flags keyEquivalent: lower])
        return event;
    return [NSEvent keyEventWithType: [event type]
                            location: [event locationInWindow]
                       modifierFlags: (flags & ~NSControlKeyMask) | NSCommandKeyMask
                           timestamp: [event timestamp]
                        windowNumber: [event windowNumber]
                             context: nil
                          characters: letters
         charactersIgnoringModifiers: letters
                           isARepeat: [event isARepeat]
                             keyCode: [event keyCode]];
}

- (void) nativeConnectionDidProcessEvents {
    if (_occlusionDirty)
        [self updateOcclusion];
}

// Reads what the server has sent, now (CoreGraphics' pump; the events come back through the methods above).
- (void) processPendingEvents {
    _CGSProcessNativeConnectionEvents();
}

- (int) handleError: (XErrorEvent *) errorEvent {
    NSLog(@"************** X11 ERROR!");
    NSLog(@"Request code: %d:%d", errorEvent->request_code,
          errorEvent->minor_code);
    NSLog(@"Error code: %d", errorEvent->error_code);
    return 0;
}

void CGNativeBorderFrameWidthsForStyle(NSUInteger styleMask, CGFloat *top,
                                       CGFloat *left, CGFloat *bottom,
                                       CGFloat *right)
{
    *top = 0.0;
    *left = 0.0;
    *bottom = 0.0;
    *right = 0.0;
}

- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    CGFloat top, left, bottom, right;

    CGNativeBorderFrameWidthsForStyle(styleMask, &top, &left, &bottom, &right);

    frame.origin.x += left;
    frame.origin.y += bottom;
    frame.size.width -= left + right;
    frame.size.height -= top + bottom;

    return frame;
}

- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    CGFloat top, left, bottom, right;

    CGNativeBorderFrameWidthsForStyle(styleMask, &top, &left, &bottom, &right);

    frame.origin.x -= left;
    frame.origin.y -= bottom;
    frame.size.width += left + right;
    frame.size.height += top + bottom;

    return frame;
}

// Takes CoreGraphics global points (origin at the main monitor's top-left corner,
// y down): CGWarpMouseCursorPosition hands its argument straight through, and on
// macOS that API is documented in that space. Internal callers that hold a root
// point convert it with -cgPointFromRoot:.
//
// The relative-mode state and Xlib are only used from the main thread (the one that
// pumps X events), and CGWarpMouseCursorPosition may be called from any thread, so a
// call from another thread is handed over. The warp produces no delta, so the caller
// need not wait.
- (void) warpMouse: (NSPoint) position {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread: @selector(warpMouseOnMainThread:)
                               withObject: [NSValue valueWithPoint: position]
                            waitUntilDone: NO];
        return;
    }
    [self warpMouseOnMainThread: [NSValue valueWithPoint: position]];
}

- (void) warpMouseOnMainThread: (NSValue *) target {
    NSPoint position = [target pointValue];
    _pointerKnown = NO;
    // The position is in points; X takes device pixels.
    X11Point root = X11CGPointToRoot([self primaryFrameInPoints],
                                     (X11Point){position.x, position.y});
    CGFloat scale = [self backingScale];
    int root_x = (int) round(root.x * scale);
    int root_y = (int) round(root.y * scale);

    if (_relativeMouse.active) {
        // CGWarpMouseCursorPosition moves the disassociated cursor without
        // producing a delta; the warp's echo is dropped.
        if (!X11RelativeMouseApplicationWarp(_display, &_relativeMouse, root_x,
                                             root_y, [self warpsHonoured]))
            [self suspendRelativeMouse];
        return;
    }

    XWarpPointer(_display, None, DefaultRootWindow(_display), 0, 0, 0, 0,
                 root_x, root_y);
    XSync(_display, False);
    if (_relativeRequested) {
        // Suspended (focus lost, retry pending): the next grab must resume at
        // the application's target, not at the cursor frozen before.
        _relativeResumeValid = YES;
        _relativeResumeX = root_x;
        _relativeResumeY = root_y;
    }
}

- (BOOL) warpsHonoured {
    return !_isXwayland || _cursorHidden;
}

// Takes the relative-mode pointer grab on the key (else main, else first
// visible) window, starting the virtual cursor at the current pointer position.
// Without the keyboard focus nothing is grabbed (a grab would take the pointer
// from whichever client has it); FocusIn retries the preserved request.
- (void) beginRelativeMouse {
    // A display overlay covers the screen above every window, so it is the
    // window the pointer is grabbed for while there is one.
    X11Window *xwin = nil;
    Window win = _overlayWindow;
    if (win == None) {
        NSWindow *nswin = [NSApp keyWindow];
        if (!nswin)
            nswin = [NSApp mainWindow];
        if (!nswin) {
            NSArray *windows = [NSApp windows];
            for (NSWindow *w in windows) {
                if ([w isVisible]) {
                    nswin = w;
                    break;
                }
            }
            if (!nswin && [windows count] > 0)
                nswin = [windows objectAtIndex: 0];
        }

        xwin = (X11Window *) [nswin platformWindow];
        win = xwin ? [xwin windowHandle] : None;
    }
    if (win == None) {
        NSLog(@"Relative mouse mode: no window to grab the pointer for\n");
        return;
    }
    if (_relativeMouse.active && _relativeWindow == win)
        return;
    [self suspendRelativeMouse];
    _pointerKnown = NO;

    int result = X11RelativeMouseGrab(_display, &_relativeMouse, win,
                                      [self warpsHonoured]);
    if (result == X11_RELATIVE_MOUSE_NOT_FOCUSED)
        return;
    if (result != GrabSuccess) {
        NSLog(@"XGrabPointer() failed with error %d for window %lu\n", result, win);
        return;
    }
    NSLog(@"XGrabPointer() succeeded for window %lu\n", win);
    _relativeWindow = win;
    // The relative-mode grab replaced a confinement grab, if there was one.
    _confinedWindow = None;
    if (_relativeResumeValid) {
        // The cursor stays where it froze, not where the pointer is now.
        X11RelativeMouseRestoreCursor(&_relativeMouse, _relativeResumeX,
                                      _relativeResumeY);
        _relativeResumeValid = NO;
    }

    // Absolute motion after the release is measured from where the cursor froze.
    Window child;
    int windowX, windowY;
    if (XTranslateCoordinates(_display, DefaultRootWindow(_display), win,
                              (int) _relativeMouse.virtualX,
                              (int) _relativeMouse.virtualY, &windowX, &windowY,
                              &child))
        [xwin setLastKnownCursorPosition:
                        [xwin logicalPoint: NSMakePoint(windowX, windowY)]];
}

// A reconfiguration (the grab window moved or resized, the screen layout
// changed) can move a confined pointer by itself and changes where it can go:
// take a new snapshot and drop the old geometry's pending motion. The new grab
// can fail while the window manager is mid-operation (AlreadyGrabbed, or the
// focus check during a fullscreen transition) and FocusIn may never follow, so
// a failure is retried for a while.
- (void) resnapshotRelativeMouse {
    if (!_relativeMouse.active)
        return;
    // Most RandR events (a backlight change, an output property) change
    // nothing the grab depends on: skip the new grab unless the reachable
    // rectangle moved.
    X11RelativeMouseBounds bounds;
    if (X11RelativeMouseWindowBounds(_display, _relativeWindow, &bounds) &&
        bounds.minX == _relativeMouse.minX && bounds.minY == _relativeMouse.minY &&
        bounds.maxX == _relativeMouse.maxX && bounds.maxY == _relativeMouse.maxY)
        return;
    [self suspendRelativeMouse];
    [self beginRelativeMouse];
    if (_relativeRequested && !_relativeMouse.active)
        [self scheduleRelativeMouseRetry];
}

- (void) scheduleRelativeMouseRetry {
    _relativeRetriesLeft = 10;
    [NSObject cancelPreviousPerformRequestsWithTarget: self
                                             selector: @selector(retryRelativeMouse)
                                               object: nil];
    [self performSelector: @selector(retryRelativeMouse)
               withObject: nil
               afterDelay: 0.1];
}

- (void) retryRelativeMouse {
    if (!_relativeRequested || _relativeMouse.active)
        return;
    [self beginRelativeMouse];
    if (_relativeRequested && !_relativeMouse.active && --_relativeRetriesLeft > 0)
        [self performSelector: @selector(retryRelativeMouse)
                   withObject: nil
                   afterDelay: 0.1];
}

// Releases the grab without cancelling the request (focus loss, window gone).
- (void) suspendRelativeMouse {
    if (!_relativeMouse.active)
        return;
    _pointerKnown = NO;
    _relativeResumeValid = YES;
    _relativeResumeX = _relativeMouse.virtualX;
    _relativeResumeY = _relativeMouse.virtualY;
    X11RelativeMouseRelease(_display, &_relativeMouse);
    _relativeWindow = None;
}

// With ConfinePointerToFullscreenWindows set, the pointer cannot leave the
// window that has the keyboard focus while that window is fullscreen, so that
// on a setup with several monitors it stays on the fullscreen window's one, as
// applications that scroll when the pointer reaches a screen edge expect.
// macOS does not confine the pointer, so this is off by default. The grab is
// taken and released as the focus, the fullscreen state and the mapping
// change; relative mouse mode has its own grab, which takes precedence.
- (void) updatePointerConfinement {
    if (!_confinesPointer || _relativeMouse.active)
        return;

    Window target = None;
    if (!_relativeRequested && lastFocusedWindow != nil) {
        X11Window *window = (X11Window *) [lastFocusedWindow platformWindow];
        if ([window isKindOfClass: [X11Window class]] && [window isMapped] &&
            [window isFullscreen])
            target = [window windowHandle];
    }

    if (target == _confinedWindow)
        return;
    if (_confinedWindow != None) {
        XUngrabPointer(_display, CurrentTime);
        _confinedWindow = None;
    }
    if (target != None) {
        // owner_events keeps delivering events to the window they happen in,
        // including subwindows; confine_to keeps the pointer inside.
        int result = XGrabPointer(_display, target, True,
                                  ButtonPressMask | ButtonReleaseMask |
                                          PointerMotionMask,
                                  GrabModeAsync, GrabModeAsync, target, None,
                                  CurrentTime);
        // AlreadyGrabbed (the window manager is mid-operation) or
        // NotViewable: the next focus, configure or state change retries.
        if (result == GrabSuccess)
            _confinedWindow = target;
    }
}

// Holds the pointer for the application while a menu is open, on the newest
// menu window. Relative mouse mode holds the pointer already; it is not
// disturbed, an open menu then only sees the pointer inside its windows.
- (void) grabPointerForMenus {
    if ([_openMenuWindows count] == 0 || _relativeMouse.active)
        return;
    Window target = [(X11Window *) [_openMenuWindows lastObject] windowHandle];
    if (target == None)
        return;
    // The grab replaces the confinement grab, if there was one.
    _confinedWindow = None;
    XGrabPointer(_display, target, True,
                 ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
                 GrabModeAsync, GrabModeAsync, None, None, CurrentTime);
}

- (void) menuWindowMapped: (X11Window *) window {
    if (_openMenuWindows == nil)
        _openMenuWindows = [NSMutableArray new];
    [_openMenuWindows removeObjectIdenticalTo: window];
    [_openMenuWindows addObject: window];
    [self grabPointerForMenus];
}

- (void) menuWindowUnmapped: (X11Window *) window {
    if ([_openMenuWindows indexOfObjectIdenticalTo: window] == NSNotFound)
        return;
    [_openMenuWindows removeObjectIdenticalTo: window];
    _pointerKnown = NO;
    if ([_openMenuWindows count] > 0) {
        [self grabPointerForMenus];
        return;
    }
    if (!_relativeMouse.active)
        XUngrabPointer(_display, CurrentTime);
    [self updatePointerConfinement];
}

// CGAssociateMouseAndMouseCursorPosition(!doGrab).
- (void) grabMouse: (BOOL) doGrab {
    // Main thread only, like -warpMouse:.
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread: @selector(grabMouseOnMainThread:)
                               withObject: [NSNumber numberWithBool: doGrab]
                            waitUntilDone: NO];
        return;
    }
    [self grabMouseOnMainThread: [NSNumber numberWithBool: doGrab]];
}

- (void) grabMouseOnMainThread: (NSNumber *) wanted {
    BOOL doGrab = [wanted boolValue];
    if (doGrab) {
        _relativeRequested = YES;
        [self beginRelativeMouse];
        // A failed first grab (AlreadyGrabbed while a window manager holds the
        // pointer) is retried for a while, like one after a reconfiguration.
        if (!_relativeMouse.active)
            [self scheduleRelativeMouseRetry];
    } else {
        _relativeRequested = NO;
        [self suspendRelativeMouse];
        _relativeResumeValid = NO;
        [self updatePointerConfinement];
    }
    XSync(_display, False);
}

@end
