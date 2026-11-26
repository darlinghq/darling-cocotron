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
#include <string.h>
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

// Whether the locale modifiers (XMODIFIERS, as XSetLocaleModifiers("") returns them) name an input method other
// than Xlib's own: "@im=none" and "@im=local" are the built-in one, and so is no @im at all.
static BOOL modifiersNameInputMethod(const char *modifiers) {
    const char *name = modifiers != NULL ? strstr(modifiers, "@im=") : NULL;
    if (name == NULL)
        return NO;
    name += 4;
    size_t length = strcspn(name, "@");
    if (length == 0)
        return NO;
    return !(length == 4 && strncmp(name, "none", 4) == 0) && !(length == 5 && strncmp(name, "local", 5) == 0);
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

        const char *modifiers = XSetLocaleModifiers("");
        _xim = XOpenIM(_display, NULL, NULL, NULL);
        _inputMethodComposes = _xim != NULL && modifiersNameInputMethod(modifiers);

        if (!_xim) {
            NSLog(@"Failed to open XIM, falling back to im=none\n");

            XSetLocaleModifiers("@im=none");
            _xim = XOpenIM(_display, NULL, NULL, NULL);
        }

        // RandR events are CoreGraphics', which reports the new layout (see -nativeConnectionDisplayLayoutChanged).
        // The window manager publishes the focused window and the stacking order on the root window,
        // whose property changes CoreGraphics' connection selects.
        _occlusionDirty = YES;

        int xwaylandOpcode, xwaylandEvent, xwaylandError;
        _isXwayland = XQueryExtension(_display, "XWAYLAND", &xwaylandOpcode,
                                      &xwaylandEvent, &xwaylandError);

        lastFocusedWindow = nil;
        _confinesPointer = appKitPreference(CFSTR("ConfinePointerToFullscreenWindows"));
        _controlActsAsCommand = appKitPreference(CFSTR("ControlKeyActsAsCommand"));

        // From here on CoreGraphics hands this display the events of the connection.
        _CGSSetNativeConnectionObserver(self);
    }
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    _CGSSetNativeConnectionObserver(nil);
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

// The process' cursor is hidden or shown by CoreGraphics (CGDisplayHideCursor() and the calls that undo it, which
// the counted hide of NSCursor uses): the windows show a blank cursor while it is hidden.
- (void) nativeConnectionCursorHiddenChanged: (BOOL) hidden {
    if (hidden)
        [self hideCursor];
    else
        [self unhideCursor];
}

- (BOOL) usesPointerController {
    return NO;
}

- (void) hideCursorCounted {
    CGDisplayHideCursor(kCGNullDirectDisplay);
}

- (void) unhideCursorCounted {
    CGDisplayShowCursor(kCGNullDirectDisplay);
}

- (void) forceShowCursor {
    _cursorHiddenUntilMouseMoves = NO;
    CGSForceShowCursor(CGSMainConnectionID());
}

// The window CoreGraphics grabs the pointer for while the mouse is disassociated from the cursor, unless a display
// overlay is up: the key window, else the main, else the first visible, else the first window.
- (unsigned long) nativeConnectionRelativeMouseWindow {
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
    X11Window *xwin = (X11Window *) [nswin platformWindow];
    return xwin ? (unsigned long) [xwin windowHandle] : 0;
}

// The grab was taken or released: a confinement grab was replaced, and the window's cursor position is where the
// cursor froze (absolute motion after the release starts from there).
- (void) nativeConnectionRelativeMouseGrabChanged: (BOOL) active window: (unsigned long) window rootX: (int) x rootY: (int) y {
    if (!active)
        return;
    _confinedWindow = None;
    X11Window *xwin = (X11Window *) [self windowForID: (XID) window];
    Window child;
    int windowX, windowY;
    if ([xwin isKindOfClass: [X11Window class]] &&
        XTranslateCoordinates(_display, DefaultRootWindow(_display), (Window) window, x, y, &windowX, &windowY, &child))
        [xwin setLastKnownCursorPosition: [xwin logicalPoint: NSMakePoint(windowX, windowY)]];
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



- (void) setWindow: (id) window forID: (XID) i {
    if (window)
        [_windowsByID
                setObject: window
                   forKey: [NSNumber
                                   numberWithUnsignedLong: (unsigned long) i]];
    else {
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
        // The pointer grab of the relative mouse (CoreGraphics') is released with the window.
        _CGSNativeConnectionObjectDestroyed((void *) (uintptr_t) i);
    }
}

// Whether the session has a desktop that shows application menus: a registrar owns its name on the session
// bus. Asked once, with a throw-away exporter, because the answer decides whether the application exports its
// menu at all. -appMenu is not used: it asks +[NSWindow _usesInWindowMenuBar], which is being answered.
- (BOOL) _desktopShowsMainMenu {
    if (!_desktopMenuProbed) {
        X11AppMenu *probe = [[X11AppMenu alloc] initWithDisplay: _display exporting: YES];

        _desktopMenuPresent = [probe globalMenuPresent];
        _desktopMenuProbed = YES;
        [probe release];
    }
    return _desktopMenuPresent;
}

// The menu bar window is a dock that the window manager has to place at the top of the screen. Under a manager
// that does not handle docks it would float over the windows of the application (see X11DockSupport.h), so
// there the menu is outside the windows only when the desktop has a global menu, as on Wayland, and the
// windows draw it themselves otherwise.
- (BOOL) _showsMainMenuOutsideWindows {
    return X11WindowManagerPlacesDocks(_display) || [self _desktopShowsMainMenu];
}

// The menu is exported for the desktop's global menu unless the windows carry it as strips. The menu bar is
// kept for the time no window carries a strip, where the window manager places it.
- (X11AppMenu *) appMenu {
    if (_appMenu == nil) {
        BOOL strips = [NSWindow _usesInWindowMenuBar];

        if (!strips || X11WindowManagerPlacesDocks(_display))
            _appMenu = [[X11AppMenu alloc] initWithDisplay: _display exporting: !strips];
    }
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

// Whether the window is one of this process's own application windows.
- (BOOL) isOwnWindowID: (Window) window {
    return window != None && [self windowForID: window] != nil;
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
    id delegate = [window delegate];

    switch (ev->type) {
    case KeyPress:
    case KeyRelease:
        // CoreGraphics decodes the keyboard and posts the keys as CGEvents (and the modifier state the
        // pointer events carry); the NSEvents are made from those (-windowNumber:location:forKeyEvent:).
        break;

    case ButtonPress:
    case ButtonRelease:
        // CoreGraphics decodes the buttons and the wheel into CGEvents (click state, button number, flags,
        // window), whichever window they are for; the NSEvents are made from those.
        break;

    case MotionNotify: {
        // CoreGraphics decoded the motion into a CGEvent (the deltas are added to the pointer's total when it is
        // about to be posted, see -nativeConnectionWillPostPointerEvent:forXEvent:). What stays here is what
        // depends on the windows: where the pointer is in the window, the cursor and the tracking areas.
        [window setLastKnownCursorPosition:
                        [window logicalPoint: NSMakePoint(ev->xmotion.x, ev->xmotion.y)]];
        [self pointerMoved];
        BOOL moved = !(ev->xmotion.state & (Button1Mask | Button2Mask | Button3Mask));
        if (moved && ![delegate acceptsMouseMovedEvents])
            break;
        [delegate platformWindowSetCursorEvent: window];
        break;
    }

    case EnterNotify:
        if (!_CGSNativeConnectionRelativeMouseState(NULL, NULL))
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
        if (window == nil || _CGSNativeConnectionRelativeMouseState(NULL, NULL) || !ev->xcrossing.same_screen ||
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
        // we should never get this message before the WM_DELETE_WINDOW
        // ClientNotify so normally, window should be nil here.
        [window invalidate];
        break;

    case UnmapNotify:
        // The server released a grab whose window became unviewable.
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
        }
        break;

    // The selections (the requests, replies and clears of the clipboard and of a drag's data, and the property
    // changes that pace their transfers) are handled by CoreGraphics, which owns the connection.

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
        // The events of XInput2 (touch screens, pinch gestures, smooth scrolling) are CoreGraphics', which
        // decodes them into CGEvents; the events of other extensions are not used.
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

- (BOOL) nativeConnectionInputMethodComposes {
    return _inputMethodComposes;
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

// CoreGraphics decoded a pointer event and is about to post it. What AppKit knows when the event arrives is
// added: whether a pressed button's window was the key window (the window manager may focus it for this very
// click before or after the press reaches us, so the press is judged by what we knew at its arrival). A mouse
// moved event for a window that did not ask for them goes to the event taps only (a display overlay has no window
// and takes them all).
- (BOOL) nativeConnectionWillPostPointerEvent: (CGEventRef) event forXEvent: (void *) xEvent {
    XEvent *ev = (XEvent *) xEvent;
    X11Window *window = (X11Window *) [self windowForID: ev->xany.window];
    id delegate = [window delegate];

    switch (CGEventGetType(event)) {
    case kCGEventLeftMouseDown:
    case kCGEventRightMouseDown:
    case kCGEventOtherMouseDown:
        CGEventSetIntegerValueField(event, kCGSMouseEventWindowKeyState, [delegate isKeyWindow] ? 1 : 2);
        return YES;
    case kCGEventMouseMoved:
    case kCGEventLeftMouseDragged:
    case kCGEventRightMouseDragged:
    case kCGEventOtherMouseDragged:
        return CGEventGetType(event) != kCGEventMouseMoved || window == nil || [delegate acceptsMouseMovedEvents];
    default:
        return YES;
    }
}

// The window a pointer event is for and where the pointer was in it, from the X window and the position
// CoreGraphics read from the server. They apply only while no event tap has moved the event.
- (BOOL) windowNumber: (NSInteger *) windowNumber
             location: (NSPoint *) location
          hasLocation: (BOOL *) hasLocation
      forPointerEvent: (CGEventRef) event {
    Window native = (Window) CGEventGetIntegerValueField(event, kCGSEventNativeWindow);
    X11Window *window = (X11Window *) [self windowForID: native];

    if (![window isKindOfClass: [X11Window class]])
        return NO;
    *windowNumber = [[window delegate] windowNumber];
    CGPoint global = CGEventGetLocation(event);
    if (llround(global.x * 1024) == CGEventGetIntegerValueField(event, kCGSEventPostedLocationX) &&
        llround(global.y * 1024) == CGEventGetIntegerValueField(event, kCGSEventPostedLocationY)) {
        *location = [window logicalPoint: NSMakePoint(CGEventGetIntegerValueField(event, kCGSEventNativeLocationX),
                                                      CGEventGetIntegerValueField(event, kCGSEventNativeLocationY))];
        *hasLocation = YES;
    }
    return YES;
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

// With ConfinePointerToFullscreenWindows set, the pointer cannot leave the
// window that has the keyboard focus while that window is fullscreen, so that
// on a setup with several monitors it stays on the fullscreen window's one, as
// applications that scroll when the pointer reaches a screen edge expect.
// macOS does not confine the pointer, so this is off by default. The grab is
// taken and released as the focus, the fullscreen state and the mapping
// change; relative mouse mode has its own grab, which takes precedence.
- (void) updatePointerConfinement {
    if (!_confinesPointer || _CGSNativeConnectionRelativeMouseState(NULL, NULL))
        return;

    Window target = None;
    BOOL relativeRequested = NO;
    _CGSNativeConnectionRelativeMouseState(&relativeRequested, NULL);
    if (!relativeRequested && lastFocusedWindow != nil) {
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
    if ([_openMenuWindows count] == 0 || _CGSNativeConnectionRelativeMouseState(NULL, NULL))
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

// Holds the keyboard for the application while a menu is open, so that its keys reach the menu
// whichever client has the input focus (an application that only owns the menu bar has none). The
// keys still go to the application's own windows while one has the focus (owner_events), and the
// focus events the grab causes are not taken for the focus moving (see the FocusIn and FocusOut cases).
- (void) grabKeyboardForMenus {
    if ([_openMenuWindows count] == 0)
        return;
    Window target = [(X11Window *) [_openMenuWindows lastObject] windowHandle];
    if (target == None)
        return;
    XGrabKeyboard(_display, target, True, GrabModeAsync, GrabModeAsync, CurrentTime);
}

- (void) menuWindowMapped: (X11Window *) window {
    if (_openMenuWindows == nil)
        _openMenuWindows = [NSMutableArray new];
    [_openMenuWindows removeObjectIdenticalTo: window];
    [_openMenuWindows addObject: window];
    [self grabPointerForMenus];
    [self grabKeyboardForMenus];
}

- (void) menuWindowUnmapped: (X11Window *) window {
    if ([_openMenuWindows indexOfObjectIdenticalTo: window] == NSNotFound)
        return;
    [_openMenuWindows removeObjectIdenticalTo: window];
    if ([_openMenuWindows count] > 0) {
        [self grabPointerForMenus];
        [self grabKeyboardForMenus];
        return;
    }
    XUngrabKeyboard(_display, CurrentTime);
    if (!_CGSNativeConnectionRelativeMouseState(NULL, NULL))
        XUngrabPointer(_display, CurrentTime);
    [self updatePointerConfinement];
}

@end
