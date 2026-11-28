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
#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputBackend.h>
#import "../NSCGSInputMethod.h"
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
#import "../../CoreGraphics/X11.backend/CGSWindowX11.h"
#import <CoreGraphics/CGSServerSPI.h>
#import "X11FullscreenPolicy.h"
#import "X11PointerMotion.h"
#import "X11SubWindow.h"
#import "X11Window.h"
#import "X11AppMenu.h"
#import <X11/Xatom.h>
#import <X11/Xutil.h>
#include <math.h>

// Set once EGL could not create an alpha surface for the alpha visual; later
// windows are then created opaque straight away.
static BOOL alphaSurfaceFailed;

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

#pragma mark - Input method

// The window uses the window system's input method, which CoreGraphics runs; what it composes comes back as
// toplevel events (see -toplevelEvent:).
- (void) createXInputContext {
    if (_inputMethod == nil) {
        if (![NSCGSInputMethod available])
            return;
        _inputMethod = [[NSCGSInputMethod alloc] initWithPlatformWindow: self cgsWindow: _cgsWindow];
    }
    [_inputMethod setEnabled: YES];
}

// Gives the input method the spot where the client's composition is, so that it places its candidate window
// there.
- (void) updateInputMethodSpot {
    [_inputMethod candidateRectChanged];
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

// The application icon at each of the sizes the window manager is offered, as the display makes them (32-bit
// premultiplied ARGB pixels); nil when the application has no icon.
static NSArray<NSData *> *windowIconImages(X11Display *display) {
    NSMutableArray<NSData *> *images = nil;

    for (size_t i = 0; i < sizeof(WindowIconSides) / sizeof(WindowIconSides[0]); i++) {
        NSData *pixels = [display applicationIconPixelsOfSide: WindowIconSides[i]];
        if (pixels == nil)
            return nil;
        if (images == nil)
            images = [NSMutableArray array];
        [images addObject: pixels];
    }
    return images;
}

// The icon the window manager shows for the window is the application icon, or the manager's own choice when
// there is none.
- (void) setWindowIcon {
    [_cgsWindow setToplevelIcons: windowIconImages((X11Display *) [NSDisplay currentDisplay])];
}

- (instancetype) initWithDelegate: (NSWindow *) delegate {
    _delegate = delegate;
    _level = [delegate level];
    _styleMask = [delegate styleMask];
    _backingType = (CGSBackingStoreType)[delegate backingType];
    _deviceDictionary = [NSMutableDictionary new];

    X11Display* x11disp = (X11Display *) [NSDisplay currentDisplay];
    _display = [x11disp display];

    _frame = [delegate frame];
    _frame.size = NSMakeSize(fmax(_frame.size.width, 1.0), fmax(_frame.size.height, 1.0));
    BOOL isPanel = [delegate isKindOfClass: [NSPanel class]];
    BOOL isSheetPanel = isPanel && (_styleMask & NSDocModalWindowMask);
    if (isSheetPanel)
        _styleMask = NSBorderlessWindowMask;
    // Until NSWindow says what the window shows of a title bar, a titled window has a standard one.
    _titlebarKind = (_styleMask & NSWindowStyleMaskTitled) ? kCGSToplevelTitlebarStandard : kCGSToplevelTitlebarNone;
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
    BOOL unmanaged = borderless && !_dock &&
                     (isMenuWindow || (!isPanel && ![delegate canBecomeKeyWindow]));
    if (isSheetPanel)
        unmanaged = YES;
    _overrideRedirect = unmanaged;

    // The window system's window is CoreGraphics': made once, and made again (keeping its children) when
    // the visual has to change before the window is first shown. _frame is in root points, -frame in
    // Cocoa's global space, which is what CoreGraphics takes.
    CGSToplevelAttributes attributes = {
        .frame = _cgsWindow == nil ? NSRectToCGRect([delegate frame]) : NSRectToCGRect([self frame]),
        .unmanaged = unmanaged,
    };
    for (;;) {
        attributes.translucent = _hasAlpha;
        if (_cgsWindow == nil) {
            _cgsWindow = [_CGSNewToplevelWindow(&attributes) retain];
            if (_cgsWindow == nil)
                return NO;
            // What the window system says about the window: the user asks to close it, it is placed or
            // sized, painted again or moved to another scale.
            [_cgsWindow setToplevelEventProc: X11WindowToplevelEvent info: self];
        } else if ([_cgsWindow recreateToplevelWithAttributes: &attributes] != kCGSErrorSuccess) {
            return NO;
        }
        _window = (Window) [_cgsWindow nativeWindow];
        _visualInfo = [(CGSWindowX11 *) _cgsWindow visualInfo];
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
        _hasAlpha = NO;
        alphaSurfaceFailed = YES;
    }

    [self syncDelegateProperties];

    // A menu, pop-up and the menu bar are not stacked by level: they are above the windows they belong to by
    // their own means.
    [_cgsWindow setToplevelStacksByLevel: !_dock && !_menuWindow];
    // The level may have been set before the window system window was made.
    [_cgsWindow setToplevelLevel: _level];
    // The pointer and the keyboard are held for a menu while it is shown, so that a click outside it reaches the menu's
    // tracking and not another client, and its keys reach it.
    [_cgsWindow setToplevelHoldsInputForMenu: _menuWindow];

    [self updateWindowManagerHints];

    [self createXInputContext];

    [(X11Display *) [NSDisplay currentDisplay] setWindow: self forID: _window];

    // A window of the application's own, not a popup or its menu bar, shows
    // the application's menu in the desktop's global menu.
    if (!_dock && !_overrideRedirect && !isMenuWindow)
        [[x11disp appMenu] windowCreated: _window cgsWindow: _cgsWindow];

    [self setStyleMaskInternal: _styleMask force: YES];

    [self setWindowIcon];

    [self updateOpaqueRegion];

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

    CGSToplevelKind kind;
    BOOL isTransient = YES;
    if (_isModal) {
        kind = kCGSToplevelKindDialog;
    } else if (_dock) {
        kind = kCGSToplevelKindDock;
        isTransient = NO;
    } else if (isMenu) {
        // EWMH: _MENU is for torn-off managed windows; the menus of a menu bar
        // are dropdown menus, which are typically unmanaged.
        kind = kCGSToplevelKindDropdownMenu;
    } else if (isPopUp) {
        kind = kCGSToplevelKindPopupMenu;
    } else if (presentation == DarlingWindowPresentationPopup) {
        // A tool tip never takes the focus and does not react to the mouse; any other pop-up is a
        // pop-up menu to the window manager.
        kind = !canBecomeKey && [delegate ignoresMouseEvents] ? kCGSToplevelKindTooltip : kCGSToplevelKindPopupMenu;
    } else if (isPanel) {
        kind = kCGSToplevelKindUtility;
    } else if (presentation == DarlingWindowPresentationAuxiliary) {
        kind = kCGSToplevelKindNormal;
    } else {
        kind = kCGSToplevelKindNormal;
        isTransient = NO;
    }

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

    // Whether the window takes the input focus when the window manager maps it (ICCCM 4.1.7). A
    // window that is not an application window, or one of an application that is not active, is
    // not given the focus by being shown either. Making it the key window
    // asks for the focus explicitly (-[CGSWindow requestToplevelKeyboardFocus]).
    CGSToplevelHints hints = {
        .kind = kind,
        .acceptsKeyboardInput = canBecomeKey,
        .takesFocusWhenShown = _dock || (presentation == DarlingWindowPresentationApplication && [NSApp _mayTakeInputFocus]),
        .skipsTaskList = _skipTaskbar,
        .transientFor = parent != nil ? parent->_cgsWindow : nil,
    };
    [_cgsWindow setToplevelHints: &hints];
    [self updateSizeHints: _styleMask];
}

// The window's presentation can change while it is on screen (its collection behavior): the window manager
// is told whether the window is listed in the task bar and pager now.
- (void) presentationChanged {
    if (!_mapped || _window == 0 || _dock)
        return;
    // The window manager is told at once of a change in the task list entry of the shown window.
    [self updateWindowManagerHints];
}

- (void) dealloc {
    [self invalidate];
    [_deviceDictionary release];
    [super dealloc];
}

- (NSUInteger) styleMask {
    return _styleMask;
}

// NSWindow's size limits changed (see NSWindow_sizeLimits in NSWindow-Private.h).
- (void) sizeLimitsChanged {
    if (_window == 0)
        return;
    [self updateSizeHints: _styleMask];
    XFlush(_display);
}

// The mask is passed in rather than read from _styleMask because
// -setStyleMask: hands the new mask here before it stores it. The hinted size is
// _frame's, so a caller that just resized has to re-issue these.
- (void) updateSizeHints: (NSUInteger) mask {
    // The limits CoreGraphics hints to the window manager (ICCCM 4.1.2.3): for a resizable window those NSWindow
    // derives from minSize, maxSize, contentMinSize and contentMaxSize (a zero or unset extent is no limit), for
    // any other the window's size.
    NSSize minimum = NSZeroSize, maximum = NSZeroSize;

    if (mask & NSWindowStyleMaskResizable) {
        if (_delegate != nil) {
            minimum = [_delegate _minFrameSize];
            maximum = [_delegate _maxFrameSize];
        }
    } else {
        minimum = maximum = _frame.size;
    }
    [_cgsWindow setToplevelMinimumSize: NSSizeToCGSize(minimum) maximumSize: NSSizeToCGSize(maximum)];
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
        coversMonitor = [_cgsWindow toplevelFrameCoversDisplay: NSRectToCGRect(frame)];
    }
    return X11FullscreenWanted(_overrideRedirect, styleFullScreen, titled,
                               coversMonitor);
}

// The window system holds the window fullscreen on request (see -[CGSWindow setToplevelFullscreen:force:]). It
// changes the state on its own too (it leaves fullscreen on a keybinding), and says so with
// kCGSToplevelEventFullscreenChanged.
- (void) requestFullscreen: (BOOL) fullscreen force: (BOOL) force {
    [_cgsWindow setToplevelFullscreen: fullscreen force: force];
    [self updateLayerPresentationHints];
}

// Whether the window manager currently holds the window fullscreen.
- (BOOL) isFullScreen {
    return [_cgsWindow toplevelIsFullscreen];
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
                       on: presenting && [_cgsWindow toplevelFullscreenRequested]
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

// What the window shows of a title bar (see CGSToplevelTitlebarKind): a window gets the window manager's full frame when
// NSWindow says it has a standard title bar (a titled window, or a resizable one in a program built against an old SDK);
// other windows ask for no frame. A window that shows nothing of a title bar of its own has the content as all there is (the
// application draws its own header), so the window manager's frame would be a second title bar on top of it.
- (void) setTitlebarKind: (int) kind {
    _titlebarKind = kind;
    [self updateDecorationsForStyleMask: _styleMask];
}

- (void) updateDecorationsForStyleMask: (NSUInteger) mask {
    // The window system's window follows the kind, but a window that is invisible for want of a compositor has no frame.
    [_cgsWindow setToplevelTitlebarKind: _invisibleWithoutCompositor ? kCGSToplevelTitlebarNone : _titlebarKind];
    BOOL chromeless = _titlebarKind == kCGSToplevelTitlebarHidden;
    if (_window != 0 && chromeless != _chromeless) {
        _chromeless = chromeless;
        // Whether the window positions itself depends on it.
        [self updateSizeHints: mask];
    }
    _chromeless = chromeless;
}

// Corner radius, in points, of a window that has no frame of its own to be drawn by the window manager: the window
// system's window cuts the corners (see kCGSToplevelTitlebarHidden) and the outline is drawn into the window
// (-flushBuffer).
// QUIRK: macOS draws such a window (a titled window that shows no title bar of its own, see
// -[NSWindow _hasInvisibleTitlebarForStyleMask:]) with rounded corners of about 5 points, a thin outline and
// a shadow; the window manager draws none of them for a window it was asked not to decorate. The corners are
// cut with the SHAPE extension and the outline is drawn into the window (-flushBuffer), neither of which needs
// a compositor; the shadow can only come from a compositor and is not drawn. Evidence: black-box observation
// of such windows on macOS 10.14.4 (tier 2).
// Test: tests/x11-chromeless-corners.sh (shape of the window), tests/x11-rounded-shape.c (the shape).
static const int X11ChromelessCornerRadius = (int) kCGSToplevelHiddenTitlebarCornerRadius;

// Whether the window promises a compositing manager that all of it is opaque, an occlusion hint it may
// ignore; the window system's window follows its size.
- (void) updateOpaqueRegion {
    if (_window == 0 || _delegate == nil)
        return;
    [_cgsWindow setToplevelContentsOpaque: [_delegate isOpaque]];
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
    return !alphaSurfaceFailed && _CGSToplevelWindowsSupportTranslucency() &&
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
    [(X11Display *) [NSDisplay currentDisplay] setWindow: nil
                                                   forID: oldWindow];

    // The new window has no presentation hints yet.
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
        [(X11Display *) [NSDisplay currentDisplay] setWindow: self
                                                       forID: _window];
        return;
    }

    // CoreGraphics moved the children of the old window to the new one and destroyed it.

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
    if (_unmapPending) {
        // Ordered out and in again within one pass of the run loop: nothing changed for the window.
        _unmapPending = NO;
        return;
    }
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
        [_cgsWindow orderWindow: kCGSOrderIn relativeTo: nil];
        _mapped = YES;
        _wasMapped = YES;
    }
}

// What a dock window tells the window manager before it is mapped: it is on every desktop, outside the
// taskbar and pager, above other windows, and reserves the strip it covers along the top edge of the screen.
- (void) publishDockHints {
    [_cgsWindow reserveToplevelDockStrip];
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
    return [_cgsWindow toplevelFullscreenRequested];
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

    mask |= X11PointerMotionEventMask(
            [_delegate acceptsMouseMovedEvents],
            [(X11Display *) [NSDisplay currentDisplay] cursorAwaitsPointerMotion]);
    XSelectInput(_display, _window, mask);
    // Touch screens and pinch gestures are CoreGraphics': it selects them and posts them as CGEvents.
    _CGSNativeConnectionSelectTouchInput(_window);

    // Click-through windows (overlays, tooltips) must not take the pointer from
    // the window below. Only a change needs a request.
    if (_window != 0)
        [_cgsWindow setToplevelIgnoresMouseEvents: [_delegate ignoresMouseEvents] || _invisibleWithoutCompositor];

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

    [_cgsWindow setToplevelAlpha: value];
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
    if (_window == 0)
        return;
    BOOL invisible = _alphaIsZero && ![_cgsWindow toplevelWindowSystemComposites];

    if (invisible == _invisibleWithoutCompositor)
        return;
    if ([_cgsWindow setToplevelShapeEmpty: invisible] != kCGSErrorSuccess)
        return;
    _invisibleWithoutCompositor = invisible;
    // A frame follows the shape, but its decorations would come back with a window manager that draws them
    // outside the client, and the window must not take pointer events from what is below it either.
    [self updateDecorationsForStyleMask: _styleMask];
    [_cgsWindow setToplevelIgnoresMouseEvents: invisible || [_delegate ignoresMouseEvents]];
}

- (void) invalidate {
    // This is essentially dealloc; we release our contexts
    // and windows, but unlike dealloc, this method can be called
    // several times, so set everything to nil/NULL/0.
    [_context release];
    _context = nil;

    // The window system's window is not heard any more.
    [_cgsWindow setToplevelEventProc: NULL info: NULL];

    // An active pinch on this window ends while its delegate can still be told.
    if (_window != 0)
        _CGSNativeConnectionObjectDestroyed((void *) (uintptr_t) _window);

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
        [_inputMethod invalidate];
        [_inputMethod release];
        _inputMethod = nil;

        [(X11Display *) [NSDisplay currentDisplay] setWindow: nil
                                                       forID: _window];
        // CoreGraphics destroys the window system's window, with its children.
        CGSReleaseWindow(CGSMainConnectionID(), [_cgsWindow windowId]);
        _window = 0;
    }
    [_cgsWindow release];
    _cgsWindow = nil;
}

- (Window) windowHandle {
    return _window;
}

// The window's number is the id of its CoreGraphics window.
- (NSInteger) _assignedWindowNumber {
    return _cgsWindow != nil ? (NSInteger) [_cgsWindow windowId] : 0;
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
    // The title is the window's _NET_WM_NAME (UTF8_STRING, as EWMH has it) and WM_NAME for a window manager
    // predating EWMH; -setTitle: nil is undefined, but gives an empty title.
    [_cgsWindow setProperty: kCGSWindowTitle value: (CFTypeRef) title];
}

- (void) setFrame: (O2Rect) frame {
    O2Rect cocoaFrame = frame;
    NSSize previousSize = _frame.size;
    // Leave fullscreen before moving to a frame that does not cover a monitor,
    // or the manager keeps imposing its fullscreen size, and before moving a
    // fullscreen window elsewhere, which the manager would ignore; enter it after
    // moving onto a monitor.
    BOOL fullscreen = [self wantsFullscreenWithStyleMask: _styleMask
                                                   frame: frame];
    BOOL moved = _frame.origin.x != frame.origin.x || _frame.origin.y != frame.origin.y;
    if (X11FullscreenLeaveBeforeMove(fullscreen, [_cgsWindow toplevelFullscreenRequested], moved))
        [self requestFullscreen: NO force: NO];
    // The frame stays in points; only the window system's window and the surface are in device
    // pixels. The window system's window follows its size with its shape and opaque region.
    frame.size = NSMakeSize(fmax(frame.size.width, 1.0), fmax(frame.size.height, 1.0));
    [_cgsWindow setToplevelFrame: NSRectToCGRect(cocoaFrame)];
    [self invalidateContextWithNewSize: frame.size];
    _frame = frame;
    // A non-resizable window hints PMinSize == PMaxSize, and a window manager
    // refuses any resize that falls outside the pair, so the hints have to follow
    // the size. Only on a real change so a drag does not re-issue them per pixel.
    if (!NSEqualSizes(previousSize, frame.size))
        [self updateSizeHints: _styleMask];
    if (fullscreen && ![_cgsWindow toplevelFullscreenRequested])
        [self requestFullscreen: YES force: NO];
}

- (void) setHasShadow: (BOOL) value {
    _hasShadow = value;
    [_cgsWindow setToplevelHasShadow: value];
}

- (void) setLevel: (int) value {
    _level = value;
    [_cgsWindow setToplevelLevel: value];
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
    [self updateOpaqueRegion];
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

// Ordering a window out and in again within one pass of the run loop is invisible on macOS: the window
// stays where it is and keeps the focus. Toolkits do it for each pass of a frame loop. Unmapping and
// mapping a window makes the window manager withdraw it, place it again and give the focus away and
// back, so the unmap waits for the end of the pass and is dropped if the window is ordered in by then.
// Menus and the menu bar unmap at once.
- (void) hideWindow {
    if (!_mapped || _menuWindow || _dock) {
        [self unmapNow];
        return;
    }
    if (_unmapPending)
        return;
    _unmapPending = YES;
    // A focus request still waiting for MapNotify is void once the window is ordered out; otherwise a
    // later non-key orderFront would take focus.
    [_cgsWindow cancelToplevelKeyboardFocusRequest];
    _keyRequested = NO;
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        if (self->_unmapPending)
            [self unmapNow];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

- (void) unmapNow {
    _unmapPending = NO;
    if (_window == 0)
        return;
    [_cgsWindow orderWindow: kCGSOrderOut relativeTo: nil];
    _mapped = NO;
    // A key request still waiting for the focus is void once the window is ordered out; otherwise a later
    // non-key orderFront would take focus. (The window system's window forgets what it was waiting for, and the
    // fullscreen state, which the window manager drops for a withdrawn window.)
    _keyRequested = NO;
}

// Stacks this window directly above or below another top-level window, or in front of or behind all of them.
// Ordering in front also applies the order by level (see -[CGSWindow orderToplevelAbove:]).
- (void) placeAboveWindow: (NSInteger) otherNumber {
    X11Window *other = [X11Window windowWithWindowNumber: otherNumber];
    [self ensureMappedIfVisible];
    [_cgsWindow orderToplevelAbove: other != nil ? other->_cgsWindow : nil];
}

- (void) placeBelowWindow: (NSInteger) otherNumber {
    X11Window *other = [X11Window windowWithWindowNumber: otherNumber];
    [self ensureMappedIfVisible];
    [_cgsWindow orderToplevelBelow: other != nil ? other->_cgsWindow : nil];
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
    [_cgsWindow requestToplevelKeyboardFocus];
    // The window already holds the focus (the window manager gave it when the window was ordered in
    // and that did not make it key), so no FocusIn follows to report the request.
    if ([_cgsWindow toplevelHoldsKeyboardFocus] && ![_delegate isKeyWindow])
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

// -[NSWindow performWindowDragWithEvent:]: the window manager moves the window for as long as the left button stays
// down. NO when the window manager cannot do it, the window is not managed, or the button is already up.
- (BOOL) moveByWindowSystem {
    return [_cgsWindow beginToplevelMoveByWindowSystem] == kCGSErrorSuccess;
}

- (void) miniaturize {
    [_cgsWindow miniaturizeToplevel];
}

- (void) deminiaturize {
    [_cgsWindow deminiaturizeToplevel];
}

// NSWindow asks this of every window on each pass of the event loop; the window system's window keeps the answer
// until its state changes.
- (BOOL) isMiniaturized {
    return [_cgsWindow toplevelIsMiniaturized];
}

- (BOOL) isOccluded {
    return [_cgsWindow toplevelIsOccluded];
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

// The window's frame in Cocoa's global space, as the window system's window has it (it follows the layout of the
// monitors).
- (O2Rect) frame {
    CGRect frame = [_cgsWindow toplevelFrame];
    return CGRectIsNull(frame) ? _frame : NSRectFromCGRect(frame);
}

NSString *const X11WindowBackingDidFlushNotification = @"X11WindowBackingDidFlush";

static void X11WindowToplevelEvent(CGSWindow *window, const CGSToplevelEvent *event, void *info) {
    X11Window *platform = [(X11Window *) info retain];
    [platform toplevelEvent: event];
    [platform release];
}

// What the window system said about the window (see CGSToplevelEvent), told to the window's delegate.
- (void) toplevelEvent: (const CGSToplevelEvent *) event {
    switch (event->kind) {
    case kCGSToplevelEventCloseRequested:
        // The close request is acted on from the run loop, not from the middle of reading window system events.
        [[NSRunLoop currentRunLoop] cancelPerformSelector: @selector(platformWindowWillClose:)
                                                   target: _delegate
                                                 argument: self];
        [[NSRunLoop currentRunLoop] performSelector: @selector(platformWindowWillClose:)
                                             target: _delegate
                                           argument: self
                                              order: 0
                                              modes: @[
                                                    NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                                                    NSEventTrackingRunLoopMode
                                                ]];
        break;

    case kCGSToplevelEventFrameChanged: {
        // A pure move is reported too, and every pixel of a drag: the delegate is told whether the size changed
        // (resizing the background view, resetting the cursor rects and saving the frame is not for a move).
        O2Rect frame = NSRectFromCGRect(event->rect);
        [self invalidateContextWithNewSize: frame.size];
        _frame = frame;
        [_delegate platformWindow: self frameChanged: [self frame] didSize: event->resized];
        break;
    }

    case kCGSToplevelEventExposed: {
        // The exposed area is in points from the top-left corner; the delegate takes y up. The window is
        // flushed and the delegate told once, for the union of the areas the window system reported.
        O2Rect rect = NSRectFromCGRect(event->rect);
        rect.origin.y = _frame.size.height - rect.origin.y - rect.size.height;
        [self flushBuffer];
        [_delegate platformWindowExposed: self inRect: rect];
        break;
    }

    case kCGSToplevelEventBackingScaleChanged:
        // The window kept its size in points, and so its frame, at the new scale: the backing surface is rebuilt
        // at the new device size, and the window and its views are told before they redraw.
        [_context release];
        _context = nil;
        [_delegate platformWindowDidInvalidateCGContext: self];
        if ([_delegate respondsToSelector: @selector(platformWindow:didChangeBackingScaleFrom:)])
            [_delegate platformWindow: self didChangeBackingScaleFrom: event->oldScale];
        [_delegate platformWindowExposed: self
                                  inRect: NSMakeRect(0, 0, _frame.size.width, _frame.size.height)];
        break;

    case kCGSToplevelEventFocusGained:
        [(X11Display *) [NSDisplay currentDisplay] window: self focusChanged: YES];
        break;

    case kCGSToplevelEventFocusLost:
        [(X11Display *) [NSDisplay currentDisplay] window: self focusChanged: NO];
        break;

    case kCGSToplevelEventInputMethodPreedit:
    case kCGSToplevelEventInputMethodCommit:
        [_inputMethod handleToplevelEvent: event];
        break;

    case kCGSToplevelEventMiniaturized:
        if ([_delegate respondsToSelector: @selector(platformWindowMiniaturized:)])
            [_delegate performSelector: @selector(platformWindowMiniaturized:) withObject: self];
        break;

    case kCGSToplevelEventDeminiaturized:
        if ([_delegate respondsToSelector: @selector(platformWindowDeminiaturized:)])
            [_delegate performSelector: @selector(platformWindowDeminiaturized:) withObject: self];
        break;

    case kCGSToplevelEventOcclusionChanged:
        if ([_delegate respondsToSelector: @selector(platformWindowOcclusionChanged:)])
            [_delegate platformWindowOcclusionChanged: self];
        break;

    case kCGSToplevelEventStateChanged:
        // The window manager may have changed the fullscreen state: the compositor hints follow it.
        [self updateLayerPresentationHints];
        break;

    case kCGSToplevelEventFullscreenChanged:
        if ([_delegate respondsToSelector: @selector(platformWindow:didChangeFullScreen:)])
            [_delegate platformWindow: self didChangeFullScreen: event->state];
        break;

    default:
        break;
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

// Device pixels per point, as the window system's window has it.
- (CGFloat) backingScaleFactor {
    if (_cgsWindow != nil)
        return [_cgsWindow toplevelBackingScaleFactor];
    return [(X11Display *) [NSDisplay currentDisplay] backingScale];
}

// Points to the device pixels the window system takes, rounded as its window is: origins to the nearest
// pixel, extents to at least one pixel. One rounding serves the window and the backing surface.
- (NSSize) deviceSize: (NSSize) size {
    return NSSizeFromCGSize([_cgsWindow toplevelDeviceSizeForSize: NSSizeToCGSize(size)]);
}

- (O2Rect) deviceRect: (O2Rect) rect {
    return NSRectFromCGRect([_cgsWindow toplevelDeviceRectForRect: NSRectToCGRect(rect)]);
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
