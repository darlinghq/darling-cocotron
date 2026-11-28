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
#import "../NSCGSDraggingManager.h"
#import "X11Crossing.h"
#import "../private-include/AppKit/NSEventTime.h"
#import "X11Window.h"
#import "X11AppMenu.h"
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

#import <X11/XKBlib.h>
#import <X11/Xutil.h>
#import <X11/extensions/XKBrules.h>
#import "../../CoreGraphics/X11.backend/X11Xrandr.h"
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

        // RandR events are CoreGraphics', which reports the new layout (see -nativeConnectionDisplayLayoutChanged).
        // Which window covers one of ours is judged by CoreGraphics, which tells the windows (see
        // kCGSToplevelEventOcclusionChanged).

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

    // -init releases self when it cannot use the connection, so none of these may exist yet.
    // The connection itself is CoreGraphics'; it stays open.
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
    // The windows follow the new scale in CoreGraphics, which tells them (see CGSToplevelEvent).
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
// RandR, it is the root window. It is the display CoreGraphics lists first,
// which describes it in the window system's pixels.
- (NSRect) primaryRootFrame {
    if (!_primaryRootFrameValid) {
        CGRect frame;

        if (_CGSDisplayNativeFrame(CGMainDisplayID(), &frame))
            _primaryRootFrame = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        else
            _primaryRootFrame = NSMakeRect(0, 0, DisplayWidth(_display, DefaultScreen(_display)),
                                           DisplayHeight(_display, DefaultScreen(_display)));
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

// Drag and drop is CoreGraphics' (XDND on its connection); this is the manager on top of it.
- (NSDraggingManager *) draggingManager {
    return [NSCGSDraggingManager sharedManager];
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
// The pointer is held for the window of a menu that is being tracked (see -[CGSWindow setToplevelHoldsInputForMenu:]):
// the grab replaced the confinement of the pointer, which is taken again when the menus are gone.
- (void) nativeConnectionMenuGrabChanged: (BOOL) active {
    if (active) {
        _confinedWindow = None;
        return;
    }
    [self updatePointerConfinement];
}

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

// Whether a registrar owns its name on the session bus. Asked with a throw-away exporter. -appMenu is not used: it asks
// +[NSWindow _usesInWindowMenuBar], which is being answered.
- (BOOL) _probeGlobalMenuRegistrar {
    X11AppMenu *probe = [[X11AppMenu alloc] initWithDisplay: _display exporting: YES];
    BOOL present = [probe globalMenuPresent];

    [probe release];
    return present;
}

// The menu is exported for the desktop's global menu unless the windows carry it as strips. The menu bar is
// kept for the time no window carries a strip, where the window manager places it.
- (X11AppMenu *) appMenu {
    if (_appMenu == nil) {
        BOOL strips = [NSWindow _usesInWindowMenuBar];

        if (!strips || _CGSNativeConnectionPlacesMenuBar())
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

// The window numbers of this app's windows, frontmost first, in the window system's stacking order (the order
// CGWindowListCopyWindowInfo lists them in).
- (NSArray *) orderedWindowNumbers {
    // A window gets its number, and so its place in the registry that maps numbers back to windows, when it is
    // first asked for it; the numbers CoreGraphics lists have to be known by then.
    for (id window in [_windowsByID allValues]) {
        if ([window isKindOfClass: [X11Window class]])
            [window windowNumber];
    }
    return _CGSOrderedToplevelWindowIDs();
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
    // The input method took the focus with the window system's (CoreGraphics gives it); it needs to know where
    // the client's caret is.
    [window updateInputMethodSpot];
}

// The window system's keyboard focus came to a window or left it (see kCGSToplevelEventFocusGained). Focus
// changes caused by a grab, or by the pointer entering the window or one of its children, are not reported.
- (void) window: (X11Window *) window focusChanged: (BOOL) gained {
    id delegate = [window delegate];

    if (gained) {
        // The server can still report FocusIn (detail NotifyPointer) for a
        // window we have unmapped; an ordered-out window must not become key.
        if (window != nil && ![window isMapped])
            return;
        if ([delegate attachedSheet]) {
            [[delegate attachedSheet] makeKeyAndOrderFront: delegate];
            return;
        }
        [self windowHoldsFocus: window];
        [self updatePointerConfinement];
        return;
    }

    [delegate platformWindowDeactivated: window
                checkForAppDeactivation: NO];
    lastFocusedWindow = nil;
    [self updatePointerConfinement];
}

// The window system's input focus went to a window of another client: the application is no longer active, even
// when none of its own windows ever held the focus and so no focus-out will tell it.
- (void) nativeConnectionFocusMovedToAnotherClient {
    [NSApp _systemFocusMovedToAnotherClient];
}

- (void) postXEvent: (XEvent *) ev {
    id event = nil;
    NSEventType type;
    NSPoint pos;
    X11Window* window = (X11Window*) [self windowForID: ev->xany.window];

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
    case FocusOut:
        // Told by the window system's window (see kCGSToplevelEventFocusGained).
        break;

    case KeymapNotify:
        break;

    case Expose:
        // Painting the window again is the window system's window's to report (see CGSToplevelEvent).
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
        [self updatePointerConfinement];
        break;

    case MapRequest:
        break;

    case ConfigureNotify:
        // The new frame of the window is the window system's window's to report (see CGSToplevelEvent).
        [self updatePointerConfinement];
        break;

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
        // The window may have entered or left fullscreen (its _NET_WM_STATE is the window system's window's to
        // report, see kCGSToplevelEventFullscreenChanged).
        if ([window isKindOfClass: [X11Window class]])
            [self updatePointerConfinement];
        break;

    // The selections (the requests, replies and clears of the clipboard and of a drag's data, and the property
    // changes that pace their transfers) are handled by CoreGraphics, which owns the connection.

    case ReparentNotify:
        // A window manager reparenting a top-level window into its frame is tracked by CoreGraphics,
        // which owns the connection; AppKit has nothing to do.
        break;

    case ColormapNotify:
        break;

    case ClientMessage:
        // XDND (drag and drop) is CoreGraphics', which owns the connection. The close request is the window
        // system's window's to report (see CGSToplevelEvent).
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

    // The input method has seen it already: CoreGraphics runs it.
    [self postXEvent: e];
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

@end
