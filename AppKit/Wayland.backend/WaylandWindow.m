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

#import "WaylandWindow.h"
#import "WaylandSubWindow.h"
#import "WaylandToplevelIcon.h"
#import "WaylandColor.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "WaylandWindowLevel.h"
#import "../DarlingWindowPresentation.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#import "../NSWindow-Private.h"
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSRunLoop.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Surface.h>
#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <limits.h>
#import "WaylandScale.h"
#include <math.h>

// NSView replaces the user CTM whenever it locks focus. Keep scaling in the
// device transform, alongside Onyx2D's bottom-left to top-left conversion.
@interface WaylandDrawingContext : O2Context_builtin_FT
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize border: (CGFloat) border;
@end

@implementation WaylandDrawingContext
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize border: (CGFloat) border {
    if ((self = [super initWithSurface: surface flipped: NO]) != nil) {
        CGFloat sx = O2SurfaceGetWidth(surface) / logicalSize.width;
        CGFloat sy = O2SurfaceGetHeight(surface) / logicalSize.height;
        _userToDeviceTransform = O2AffineTransformMake(sx, 0, 0, -sy, border * sx,
                                                       O2SurfaceGetHeight(surface) - border * sy);
        O2ContextSetCTM(self, O2AffineTransformIdentity);
    }
    return self;
}
@end

@implementation WaylandWindow

static const CGFloat WaylandTitleHeight = 28;
static const CGFloat WaylandBorder = 6;

static void sendRequest(struct wl_proxy *proxy, uint32_t opcode, uint32_t flags) {
    union wl_argument args[1] = {{.o = NULL}};
    WaylandMarshal(proxy, opcode, NULL, flags, args);
}

- (instancetype) initWithDelegate: (NSWindow *) delegate {
    if ((self = [super init]) == nil)
        return nil;

    _delegate = delegate;
    _level = [delegate level];
    _styleMask = [delegate styleMask];
    _backingType = (CGSBackingStoreType) [delegate backingType];
    _isOpaque = [delegate isOpaque];
    _deviceDictionary = [NSMutableDictionary new];
    _surfaceOutputs = [NSMutableSet new];
    _bufferScale = 1; _renderScale120 = 120;
    _display = [(WaylandDisplay *) [NSDisplay currentDisplay] retain];
    _subwindows = [NSMutableArray new];

    _frame = [delegate frame];
    _frame.size.width = MAX(_frame.size.width, 1.0);
    _frame.size.height = MAX(_frame.size.height, 1.0);

    [_display windowCreated: self];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [self destroySurface];
    [_subwindows release];
    [_display release];
    [_deviceDictionary release];
    [_surfaceOutputs release];
    [_title release];
    [_sessionName release];
    [super dealloc];
}

- (void) invalidate {
    // Like X11Window, this can run several times.
    if (_invalidated) return;
    _invalidated = YES;
    [_context release];
    _context = nil;

    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;

    [self unmap];
    if (_display != nil) {
        [_display windowDestroyed: self];
        // Children retain this window until their EGL surfaces are released.
        // Keep the native parent surface/display alive for that whole lifetime.
    }
}

- (void) setDelegate: (id) delegate {
    _delegate = delegate;
}

- (id) delegate {
    return _delegate;
}

- (void) syncDelegateProperties {
    // An alpha value set before the platform window existed.
    if (_delegate != nil)
        [self setAlphaValue: [_delegate alphaValue]];
}

- (struct wl_proxy *) surface {
    return _surface;
}

- (struct wl_proxy *) toplevel {
    return _toplevel;
}

- (struct wl_proxy *) ensureSurface {
    if (!_surface && !_invalidated) {
        union wl_argument args[] = {{.o = NULL}};
        _surface = WaylandCreateObject(_display->_compositor, WP_COMPOSITOR_CREATE_SURFACE,
            &wl_surface_interface, args, WaylandObjectSurface, self);
        _fractionalScale = [_display newFractionalScaleForSurface: _surface owner: (id)self];
        if (_fractionalScale) {
            union wl_argument viewportArgs[] = {{.o = NULL}, {.o = (struct wl_object *)_surface}};
            _viewport = WaylandCreateObject(_display->_viewporter, WP_VIEWPORTER_GET_VIEWPORT,
                &wp_viewport_interface, viewportArgs, 0, nil);
        }
        [self updateSurfaceColorIfNeeded];
    }
    return _surface;
}

// The color space of the content the window draws, or sRGB when neither the window nor a screen
// reports one (a display the compositor has not described yet).
- (NSColorSpace *) contentColorSpace {
    NSColorSpace *space = [_delegate respondsToSelector: @selector(colorSpace)]
                          ? [_delegate colorSpace] : nil;
    if (space == nil)
        space = [[NSScreen screens] count] > 0 ? [[NSScreen mainScreen] colorSpace] : nil;
    return space != nil ? space : [NSColorSpace sRGBColorSpace];
}

- (void) updateSurfaceColor {
    if (_surface == NULL)
        return;
    WaylandColorManager *color = [_display colorManager];
    if (color == nil)
        return;
    if (_colorSurface == NULL)
        _colorSurface = [color newColorSurfaceForSurface: _surface];
    if (_representationSurface == NULL)
        _representationSurface = [color newRepresentationSurfaceForSurface: _surface];
    CGColorSpaceRef space = [[self contentColorSpace] CGColorSpace];
    if (space != NULL)
        [color setColorSpace: space onSurface: _colorSurface];
}

- (void) updateSurfaceColorIfNeeded {
    WaylandColorManager *color = [_display colorManager];
    if (_surface == NULL || color == nil)
        return;
    if ([color hasColorGlobals])
        [self updateSurfaceColor];
}

- (void) colorSpaceChanged {
    [self updateSurfaceColor];
    [_display flush];
}

- (void) colorManagerAvailable {
    [self updateSurfaceColorIfNeeded];
}

// alpha-modifier-v1 multiplies the surface's per-pixel alpha. The protocol's factor is 0 for fully
// transparent and UINT32_MAX for fully opaque, which is NSWindow.alphaValue mapped to that range.
- (void) updateAlphaModifier {
    if (_surface == NULL || _display->_alphaModifierManager == NULL)
        return;
    if (_alphaModifier == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _alphaModifier = WaylandCreateObject(_display->_alphaModifierManager,
                                             WP_ALPHA_MODIFIER_GET_SURFACE,
                                             &wp_alpha_modifier_surface_v1_interface, args, 0, nil);
        if (_alphaModifier == NULL)
            return;
    }
    double alpha = _delegate != nil ? (double) [_delegate alphaValue] : 1.0;
    if (!(alpha > 0)) alpha = 0;
    if (alpha > 1) alpha = 1;
    union wl_argument value[1] = {{.u = (uint32_t) (alpha * (double) UINT32_MAX)}};
    WaylandMarshal(_alphaModifier, WP_ALPHA_MODIFIER_SURFACE_SET_MULTIPLIER, NULL, 0, value);
    if (_mapped && _configured) {
        [self commitSurface];
        [_display flush];
    }
}

- (void) alphaModifierAvailable {
    [self updateAlphaModifier];
}

- (void) sessionManagerAvailable {
    if (_mapped && _toplevel != NULL && _toplevelSession == NULL)
        [self joinSessionBeforeCommit];
}

- (NSString *) ensureSessionToplevelName {
    if (_sessionName == nil)
        _sessionName = [[NSString stringWithFormat: @"darling-%@",
                         [[NSProcessInfo processInfo] globallyUniqueString]] copy];
    return _sessionName;
}

- (void) setSessionToplevelName: (NSString *) name restoring: (BOOL) restoring {
    if ([name length] == 0)
        return;
    if (_toplevelSession != NULL && ![name isEqualToString: _sessionName]) {
        union wl_argument args[1] = {{.s = [name UTF8String]}};
        WaylandMarshal(_toplevelSession, WP_TOPLEVEL_SESSION_RENAME, NULL, 0, args);
    }
    [name retain];
    [_sessionName release];
    _sessionName = name;
    _restoringSessionToplevel = restoring;
}

- (BOOL) isRestoringSessionToplevel {
    return _restoringSessionToplevel;
}

- (BOOL) hasCommittedSurface {
    return _surfaceCommitted;
}

- (void) commitSurface {
    if (_surface == NULL)
        return;
    sendRequest(_surface, WP_SURFACE_COMMIT, 0);
    _surfaceCommitted = YES;
}

- (struct wl_proxy *) toplevelSession {
    return _toplevelSession;
}

- (void) setToplevelSession: (struct wl_proxy *) proxy {
    _toplevelSession = proxy;
}

- (void) joinSessionBeforeCommit {
    [_display joinSessionForToplevel: self];
}

// The surface with the objects that are tied to it. The role objects must be gone first.
- (void) destroySurface {
    WaylandColorManager *color = [_display colorManager];
    [color destroyColorSurface: _colorSurface];
    [color destroyRepresentationSurface: _representationSurface];
    _colorSurface = _representationSurface = NULL;
    if (_alphaModifier != NULL)
        sendRequest(_alphaModifier, WP_ALPHA_MODIFIER_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _alphaModifier = NULL;
    if (_idleInhibitor != NULL)
        sendRequest(_idleInhibitor, ZWP_IDLE_INHIBITOR_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _idleInhibitor = NULL;
    if (_toplevelSession != NULL)
        sendRequest(_toplevelSession, WP_TOPLEVEL_SESSION_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _toplevelSession = NULL;
    if (_dialog != NULL)
        sendRequest(_dialog, XDG_DIALOG_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _dialog = NULL;
    _dialogModal = NO;
    if (_fractionalScale) sendRequest(_fractionalScale, WP_FRACTIONAL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_viewport) sendRequest(_viewport, WP_VIEWPORT_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_surface)
        sendRequest(_surface, WP_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _fractionalScale = _viewport = _surface = NULL;
    _surfaceCommitted = NO;
}

// The core protocol makes the role of a wl_surface permanent for its lifetime, and xdg_toplevel and
// xdg_popup are different roles, so a surface that was a toplevel cannot be given a popup role
// (or the other way round) once its role objects are gone: a strict compositor ends the connection
// with a protocol error. -unmap keeps the surface so that the subsurfaces of EGL and Metal children
// stay attached to it, which is right while the role stays the same. When the window is about to
// be shown with the other role, the surface is replaced instead, and the children move to the new
// one. Returns whether it was replaced.
- (BOOL) prepareSurfaceForRole: (WaylandSurfaceRole) role {
    if (_surface == NULL || _surfaceRole == WaylandSurfaceRoleNone || _surfaceRole == role)
        return NO;
    for (NSValue *value in _subwindows)
        [(WaylandSubWindow *) [value pointerValue] parentSurfaceWillBeReplaced];
    [self destroySurface];
    _surfaceRole = WaylandSurfaceRoleNone;
    return YES;
}

- (WaylandDisplay *) waylandDisplay { return _display; }
- (BOOL) isInvalidated { return _invalidated; }
- (void) addSubwindow: (WaylandSubWindow *) child {
    [_subwindows addObject: [NSValue valueWithPointer: child]];
}
- (void) removeSubwindow: (WaylandSubWindow *) child {
    [_subwindows removeObject: [NSValue valueWithPointer: child]];
}
- (void) stackSubwindows {
    struct wl_proxy *below = _surface;
    for (NSValue *value in _subwindows) {
        WaylandSubWindow *child = [value pointerValue];
        if ([child presentedSurface]) {
            [child placeAboveSurface: below];
            below = [child presentedSurface];
        }
        below = [child stackMetalSurfacesAbove: below];
    }
}
- (void) updateSubwindows {
    for (NSValue *value in _subwindows)
        [(WaylandSubWindow *) [value pointerValue] updateGeometry];
}

- (void) scheduleSubwindowRedraw {
    _subwindowRedrawNeeded = YES;
    if (_subwindowRedrawPending) return;
    _subwindowRedrawPending = YES;
    [_display performAfterDispatch: ^{
        self->_subwindowRedrawPending = NO;
        if (!self->_mapped || self->_invalidated || !self->_delegate) return;
        self->_subwindowRedrawNeeded = NO;
        [self->_delegate display];
    }];
}

- (BOOL) isMapped {
    return _mapped;
}

// A window with alphaValue 0 is ordered in and can be the key window, but nothing of it may be
// seen or hit. The protocol has no per-surface opacity, and a toplevel without a visible buffer
// would still get a tile, a tab or a title bar from the compositor, so such a window is not given
// a role at all: it stays a surface that is never shown, and the keyboard focus the compositor
// gives to the application's other windows reaches it through the key window (see
// -[WaylandDisplay postKeyEventForKeycode:pressed:repeat:]).
- (BOOL) isFullyTransparent {
    return _fullyTransparent;
}

// Whether the application asked for this window to become the key window and the activation now
// arriving is the answer to that; reading it clears the request.
- (BOOL) takeKeyRequest {
    BOOL requested = _keyRequested;
    _keyRequested = NO;
    return requested;
}

// Mapped, or ordered in but kept unmapped because it is fully transparent. Such a window counts as
// on screen for the window order (and so for the choice of the next key window), as on X11 where
// it is mapped with no opacity.
// The keyboard focus is in another client. A window the compositor does not hold active can still be
// active for AppKit, because a window that is never shown is reported active when it is made key.
- (BOOL) isActivatedByCompositor {
    return _activated;
}

- (void) keyboardFocusLeft {
    NSWindow *delegate = _delegate;
    if (delegate != nil && !_activated && [delegate _isActive])
        [delegate platformWindowDeactivated: self checkForAppDeactivation: NO];
}

- (BOOL) isOrderedIn {
    return _mapped || ((_fullyTransparent || _mapDeferred) && _shouldBeMapped && !_invalidated);
}

- (BOOL) isMapDeferred {
    return _mapDeferred && _shouldBeMapped && !_invalidated;
}

// Mapping a toplevel makes compositors give it the keyboard focus (nothing in xdg-shell lets a client
// say that a window is shown without taking it), but an application that is not active does not take
// the focus by ordering a window in. Such a window stays unmapped until the application is active
// (the display maps it then) or is asked to activate; modal windows and sheets are shown, as the
// application cannot continue without them.
- (BOOL) mapWouldTakeFocusFromOthers {
    // The menu bar is a layer surface without keyboard interactivity: it takes no focus.
    if ([self wantsLayerSurface])
        return NO;
    if ([NSApp _mayTakeInputFocus] || [_display mappingForActivation])
        return NO;
    NSWindow *window = _delegate;
    if ([window isSheet] || window == [NSApp modalWindow])
        return NO;
    return YES;
}

- (BOOL) isPopup { return _popup != NULL; }
- (BOOL) isTooltip {
    return [_delegate isKindOfClass: NSClassFromString(@"NSToolTipWindow")];
}
- (BOOL) isGenericPopup { return _genericPopup; }
- (WaylandWindow *) popupParent { return _popupParent; }
- (uint32_t) popupGrabSerial { return _popupGrabSerial; }
- (struct wl_proxy *) xdgSurface { return _xdgSurface; }
- (struct wl_proxy *) layerSurface { return _layerSurface; }

// The menu bar window is a layer surface along the top of the screen when the
// compositor offers wlr-layer-shell; otherwise it is an ordinary borderless
// toplevel, which the compositor places.
- (BOOL) wantsLayerSurface {
    return _display->_layerShell != NULL &&
           [_delegate isKindOfClass: NSClassFromString(@"NSMenuBarWindow")];
}

// The bar is anchored to the top, left and right edges, as tall as the window
// is, and keeps that strip free of other windows (the exclusive zone).
- (void) updateLayerSize {
    int32_t height = MAX(1, (int32_t) ceil(_frame.size.height));
    union wl_argument args[2] = {{.u = 0}, {.u = (uint32_t) height}};

    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_SIZE, NULL, 0, args);
    args[0].i = height;
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_EXCLUSIVE_ZONE, NULL, 0, args);
}

- (void) createLayerRole {
    union wl_argument args[5];

    args[0].o = NULL;
    args[1].o = (struct wl_object *) _surface;
    args[2].o = NULL; // the compositor picks the output
    args[3].u = WP_LAYER_TOP;
    args[4].s = "menubar";
    _layerSurface = WaylandCreateObject(_display->_layerShell, WP_LAYER_SHELL_GET_LAYER_SURFACE,
                                        &zwlr_layer_surface_v1_interface, args,
                                        WaylandObjectLayerSurface, self);
    args[0].u = WP_LAYER_ANCHOR_TOP | WP_LAYER_ANCHOR_LEFT | WP_LAYER_ANCHOR_RIGHT;
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_ANCHOR, NULL, 0, args);
    [self updateLayerSize];
    // The bar never takes the keyboard focus (the protocol default): a compositor that gives an
    // on-demand surface the focus when the pointer is over it (KWin does as soon as the bar is
    // mapped under the pointer) would take it from the application's window, which then looks to
    // AppKit like the application losing the focus, so the bar would hide, and show again once the
    // focus came back, in a loop. The menus the bar opens grab the keyboard themselves.
}

#pragma mark - Mapping

// Whether AppKit considers this window a pop-up (see -[NSWindow _windowPresentation]).
- (BOOL) wantsPopupRole {
    return [_delegate respondsToSelector: @selector(_windowPresentation)] &&
           [(NSWindow *) _delegate _windowPresentation] == DarlingWindowPresentationPopup;
}

- (void) ensureMapped {
    if (_unmapPending && !_invalidated) {
        // Ordered out and in again within one pass of the run loop: nothing changed for the window.
        _unmapPending = NO;
        _shouldBeMapped = YES;
        return;
    }
    if (_mapped || _invalidated)
        return;
    _shouldBeMapped = YES;
    // The window may have been given its alpha before it had a platform window.
    if (_delegate != nil)
        _fullyTransparent = [_delegate alphaValue] <= 0;
    if (_fullyTransparent)
        return;
    // A client cannot position a toplevel, so a tool tip without a mapped
    // parent stays unmapped rather than being centred by the compositor.
    BOOL tooltip = [self isTooltip];
    WaylandWindow *tooltipParent = tooltip ? [_display popupParentForWindow: self] : nil;
    if (tooltip && (tooltipParent == nil || !tooltipParent->_configured))
        return;
    BOOL menu = [_delegate isKindOfClass: NSClassFromString(@"NSMenuWindow")] ||
                [_delegate isKindOfClass: NSClassFromString(@"NSPopUpWindow")];
    // A pop-up window that is neither a menu nor a tool tip (see DarlingWindowPresentation.h) is a
    // popup of the window it belongs to, so that the compositor places it where AppKit put it,
    // keeps it out of the task bar and does not give it the keyboard focus. Without a window to
    // belong to it stays an ordinary window.
    BOOL genericPopup = !tooltip && !menu && [self wantsPopupRole];
    WaylandWindow *parent = tooltip ? tooltipParent : menu ? [_display popupParentForWindow: self]
                          : genericPopup ? [_display popupParentForGenericPopup: self] : nil;
    _genericPopup = genericPopup && parent != nil;
    // A menu opened before its parent's first configure is mapped when that configure arrives
    // (-[WaylandDisplay mapPopupsWaitingForParent]), as a popup of that parent.
    _popupWaitingForParent = parent != nil && !parent->_configured;
    if (_popupWaitingForParent)
        return;
    if (parent == nil && !tooltip && !menu && [self mapWouldTakeFocusFromOthers]) {
        _mapDeferred = YES;
        return;
    }
    _mapDeferred = NO;
    _surfaceGeneration++;
    _configureUpdatePending = NO;
    // WaylandDecorations (org.darlinghq.AppKit) or DARLING_WAYLAND_DECORATIONS set to
    // "client" draw the frame in the client even when the compositor offers to do it.
    char decorations[16] = "";
    const char *fromEnvironment = getenv("DARLING_WAYLAND_DECORATIONS");
    if (fromEnvironment != NULL)
        strlcpy(decorations, fromEnvironment, sizeof(decorations));
    else
        WaylandCopyPreference("WaylandDecorations", decorations, sizeof(decorations));
    BOOL forceClient = strcmp(decorations, "client") == 0;
    _pendingClientDecorated = _display->_decorationManager == NULL || forceClient;

    union wl_argument args[4];

    BOOL layerRole = [self wantsLayerSurface];
    BOOL surfaceRenewed = [self prepareSurfaceForRole: layerRole ? WaylandSurfaceRoleLayer
                                                       : parent != nil ? WaylandSurfaceRolePopup
                                                                       : WaylandSurfaceRoleToplevel];
    [self ensureSurface];

    if (layerRole) {
        [self createLayerRole];
        _surfaceRole = WaylandSurfaceRoleLayer;
    } else {
        args[0].o = NULL;
        args[1].o = (struct wl_object *) _surface;
        _xdgSurface = WaylandCreateObject(_display->_wmBase,
                                          WP_WM_BASE_GET_XDG_SURFACE,
                                          &xdg_surface_interface, args,
                                          WaylandObjectXdgSurface, self);

        if (parent != nil) {
            _popupParent = [parent retain];
            [self createPopupRole];
            _surfaceRole = WaylandSurfaceRolePopup;
        } else {
            args[0].o = NULL;
            _toplevel = WaylandCreateObject(_xdgSurface, WP_XDG_SURFACE_GET_TOPLEVEL,
                                        &xdg_toplevel_interface, args,
                                        WaylandObjectToplevel, self);
            _surfaceRole = WaylandSurfaceRoleToplevel;
            _minimizeAdvertised = _pendingMinimizeAdvertised = NO;

            [self updateTitle];
            args[0].s = [[[NSProcessInfo processInfo] processName] UTF8String];
            if (args[0].s != NULL)
                WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_APP_ID, NULL, 0, args);
            _fullscreenRequested = NO;
            [self updateFullscreen];
            [self updateSizeLimits];
            _levelParent = nil;
            [self updateLevelParent];
            [self updateDialogForToplevel];

            _decorationForcedClient = forceClient;
            [self updateDecorationMode];
            [self updateApplicationMenu];
            [self updateTaskbarPresence];
            _toplevelIconSet = NO;
            [self updateToplevelIcon];
            // The session request has to precede the initial commit on the surface.
            [self joinSessionBeforeCommit];
        }

    }

    // The multiplier is double-buffered, so it has to be set before the surface's first commit.
    [self updateAlphaModifier];
    _pendingWidth = _pendingHeight = 0;
    _pendingActivated = NO;
    _pendingSuspended = NO;
    _pendingFullscreen = NO;
    // The initial commit has no buffer; content follows the first configure.
    [self commitSurface];
    _mapped = YES;
    [self updateIdleInhibitor];
    [self scheduleScaleUpdate];
    if (_subwindowRedrawNeeded) [self scheduleSubwindowRedraw];
    _configured = NO;
    _needsPresent = _context != nil;
    if (surfaceRenewed) {
        for (NSValue *value in _subwindows)
            [(WaylandSubWindow *) [value pointerValue] parentSurfaceReplaced];
        if ([_subwindows count] > 0) [self scheduleSubwindowRedraw];
    }
    [_display flush];
}

// A toplevel that is not an application window (see DarlingWindowPresentation.h) is left out of the
// application's window list on macOS. xdg-shell cannot say that, and a client cannot relate a window
// to another client's window, so a window with nothing of its own application to belong to would be
// listed. KDE's plasma-shell protocol, which KDE's client libraries use for this, can. Without it
// (other compositors) the window is only related to its parent, as before.
- (void) updateTaskbarPresence {
    if (_toplevel == NULL || _display->_plasmaShell == NULL)
        return;
    BOOL skip = [_delegate respondsToSelector: @selector(_windowPresentation)] &&
                [(NSWindow *) _delegate _windowPresentation] != DarlingWindowPresentationApplication;
    // The compositor keeps what a plasma surface set after the surface is gone, so a window that
    // stops being skipped says so before it lets go of the surface.
    if (_plasmaSurface == NULL && skip) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _plasmaSurface = WaylandCreateObject(_display->_plasmaShell, WP_PLASMA_SHELL_GET_SURFACE,
                                             &org_kde_plasma_surface_interface, args, 0, nil);
    }
    if (_plasmaSurface == NULL)
        return;
    union wl_argument value[1] = {{.u = skip ? 1 : 0}};
    if (_display->_plasmaShellVersion >= 2)
        WaylandMarshal(_plasmaSurface, WP_PLASMA_SURFACE_SET_SKIP_TASKBAR, NULL, 0, value);
    if (_display->_plasmaShellVersion >= 5)
        WaylandMarshal(_plasmaSurface, WP_PLASMA_SURFACE_SET_SKIP_SWITCHER, NULL, 0, value);
}

// Gives the toplevel the application icon the compositor shows for it (xdg-toplevel-icon); the request is
// double-buffered, so a window that is already showing content commits for it to take effect.
- (void) updateToplevelIcon {
    if (_toplevel == NULL || _display->_toplevelIcons == nil)
        return;
    if ([_display->_toplevelIcons applyToToplevel: _toplevel hadIcon: &_toplevelIconSet] && _mapped && _configured) {
        [self commitSurface];
        [_display flush];
    }
}

// The window's presentation can change while it is mapped (its collection behavior).
- (void) presentationChanged {
    if (!_mapped || _toplevel == NULL)
        return;
    [self updateTaskbarPresence];
    [self updateDialogForToplevel];
    [_display flush];
}

- (void) updateApplicationMenu {
    NSString *service = [_display applicationMenuServiceName];
    NSString *path = [_display applicationMenuObjectPath];

    if (_toplevel == NULL || _display->_appMenuManager == NULL || service == nil || path == nil) {
        if (_appMenu != NULL) {
            sendRequest(_appMenu, WP_APPMENU_RELEASE, WL_MARSHAL_FLAG_DESTROY);
            _appMenu = NULL;
        }
        return;
    }

    if (_appMenu == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _appMenu = WaylandCreateObject(_display->_appMenuManager, WP_APPMENU_MANAGER_CREATE,
                                       &org_kde_kwin_appmenu_interface, args, 0, nil);
    }
    // Both are ASCII: a unique bus name and an object path.
    union wl_argument address[2] = {{.s = [service UTF8String]}, {.s = [path UTF8String]}};
    WaylandMarshal(_appMenu, WP_APPMENU_SET_ADDRESS, NULL, 0, address);
}

- (struct wl_proxy *) newPopupPositioner {
    union wl_argument args[4] = {{.o = NULL}};
    struct wl_proxy *positioner = WaylandCreateObject(_display->_wmBase,
            WP_WM_BASE_CREATE_POSITIONER, &xdg_positioner_interface, args, 0, nil);
    args[0].i = MAX(1, (int32_t) ceil(_frame.size.width));
    args[1].i = MAX(1, (int32_t) ceil(_frame.size.height));
    WaylandMarshal(positioner, WP_POSITIONER_SET_SIZE, NULL, 0, args);
    NSRect parent = [_popupParent frame];
    NSPoint offset = [_popupParent contentOffset];
    int32_t x = (int32_t) floor(_frame.origin.x - parent.origin.x + offset.x);
    int32_t y = (int32_t) floor(NSMaxY(parent) - NSMaxY(_frame) + offset.y);
    // A submenu can start beyond its parent edge. Keep the anchor inside the
    // parent geometry, expressing the remaining displacement as an offset.
    int32_t anchorX = MAX(0, MIN(x, (int32_t) ceil(parent.size.width + 2 * offset.x) - 1));
    int32_t anchorY = MAX(0, MIN(y, (int32_t) ceil(parent.size.height + offset.x + offset.y) - 1));
    args[0].i = anchorX;
    args[1].i = anchorY;
    args[2].i = args[3].i = 1;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR_RECT, NULL, 0, args);
    args[0].i = x - anchorX;
    args[1].i = y - anchorY;
    WaylandMarshal(positioner, WP_POSITIONER_SET_OFFSET, NULL, 0, args);
    args[0].u = WP_POSITIONER_ANCHOR_TOP_LEFT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR, NULL, 0, args);
    args[0].u = WP_POSITIONER_GRAVITY_BOTTOM_RIGHT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_GRAVITY, NULL, 0, args);
    args[0].u = WP_POSITIONER_SLIDE_X | WP_POSITIONER_SLIDE_Y |
                WP_POSITIONER_FLIP_X | WP_POSITIONER_FLIP_Y;
    WaylandMarshal(positioner, WP_POSITIONER_SET_CONSTRAINT_ADJUSTMENT, NULL, 0, args);
    return positioner;
}

- (void) createPopupRole {
    struct wl_proxy *positioner = [self newPopupPositioner];
    union wl_argument args[3];
    args[0].o = NULL;
    // A popup of a layer surface has no xdg parent; the layer surface adopts it.
    BOOL layerParent = [_popupParent layerSurface] != NULL;
    args[1].o = layerParent ? NULL : (struct wl_object *) [_popupParent xdgSurface];
    args[2].o = (struct wl_object *) positioner;
    _popup = WaylandCreateObject(_xdgSurface, WP_XDG_SURFACE_GET_POPUP,
            &xdg_popup_interface, args, WaylandObjectPopup, self);
    if (layerParent) {
        args[0].o = (struct wl_object *) _popup;
        WaylandMarshal([_popupParent layerSurface], WP_LAYER_SURFACE_GET_POPUP, NULL, 0, args);
    }
    sendRequest(positioner, WP_POSITIONER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if ([self isTooltip] || (_genericPopup && [_delegate ignoresMouseEvents])) {
        // No grab, and an empty input region: the pointer keeps its focus on the
        // parent while a tool tip is shown beside it.
        args[0].o = NULL;
        struct wl_proxy *region = WaylandCreateObject(_display->_compositor,
                WP_COMPOSITOR_CREATE_REGION, &wl_region_interface, args, 0, nil);
        args[0].o = (struct wl_object *) region;
        WaylandMarshal(_surface, WP_SURFACE_SET_INPUT_REGION, NULL, 0, args);
        sendRequest(region, WP_REGION_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        return;
    }
    // A pop-up window of the application ends when the application orders it out; the compositor
    // dismissing it with a click elsewhere would leave the application showing it.
    if (_genericPopup)
        return;
    _popupGrabSerial = [_display popupGrabSerialForParent: _popupParent];
    if (_popupGrabSerial != 0 && [_display seat] != NULL) {
        args[0].o = (struct wl_object *) [_display seat];
        args[1].u = _popupGrabSerial;
        WaylandMarshal(_popup, WP_POPUP_GRAB, NULL, 0, args);
    }
}

- (void) destroyBuffers {
    for (int i = 0; i < 2; i++) {
        struct WaylandBuffer *buffer = &_buffers[i];
        if (buffer->buffer != NULL)
            sendRequest(buffer->buffer, WP_BUFFER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        if (buffer->data != NULL)
            munmap(buffer->data, buffer->size);
        memset(buffer, 0, sizeof(*buffer));
    }
}

// Unmapping an xdg surface requires a new configure sequence before it can be
// shown again, so the role objects are destroyed and created again on show.
- (BOOL) isPopupWaitingForParent { return _popupWaitingForParent; }

- (void) unmap {
    _unmapPending = NO;
    _shouldBeMapped = NO;
    _mapDeferred = NO;
    _popupWaitingForParent = NO;
    _keyRequested = NO;
    if (!_mapped)
        return;

    [_display unmapPopupsForParent: self];

    if (_frameCallback != NULL) {
        WL.wl_proxy_destroy(_frameCallback);
        _frameCallback = NULL;
    }
    if (_decoration != NULL) {
        sendRequest(_decoration, WP_TOPLEVEL_DECORATION_DESTROY,
                    WL_MARSHAL_FLAG_DESTROY);
        _decoration = NULL;
    }
    if (_popup != NULL) {
        sendRequest(_popup, WP_POPUP_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _popup = NULL;
        [_popupParent release];
        _popupParent = nil;
        _popupGrabSerial = 0;
        _genericPopup = NO;
    }
    if (_appMenu != NULL) {
        sendRequest(_appMenu, WP_APPMENU_RELEASE, WL_MARSHAL_FLAG_DESTROY);
        _appMenu = NULL;
    }
    if (_plasmaSurface != NULL) {
        sendRequest(_plasmaSurface, WP_PLASMA_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _plasmaSurface = NULL;
    }
    if (_toplevel != NULL)
        sendRequest(_toplevel, WP_TOPLEVEL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_layerSurface != NULL) {
        sendRequest(_layerSurface, WP_LAYER_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _layerSurface = NULL;
    }
    if (_xdgSurface != NULL)
        sendRequest(_xdgSurface, WP_XDG_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    // Retain the parent wl_surface across hide/show: EGL child surfaces keep
    // their native-window identity. A NULL buffer unmaps the entire subtree.
    union wl_argument detach[] = {{.o = NULL}, {.i = 0}, {.i = 0}};
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, detach);
    [self commitSurface];
    _toplevel = _xdgSurface = NULL;
    [_surfaceOutputs removeAllObjects];
    [self destroyBuffers];

    _mapped = NO;
    [self updateIdleInhibitor];
    // The toplevel is gone, and so is what the compositor did to it.
    [self endMinimized];
    _levelParent = nil;
    _configureUpdatePending = NO;
    _configured = NO;
    // The compositor moves the focus away from a window that is unmapped without telling the client,
    // so the window tells its application, which stops being active when another window of it is
    // still shown and none has the focus (as the X11 backend learns from the focus-out event). That
    // the focus went elsewhere is not known: the application whose last window is unmapped stays
    // active, as on macOS, until a window system event shows another client has the focus.
    BOOL wasActivated = _activated;
    _activated = NO;
    if (wasActivated) {
        [_display performAfterDispatch: ^{
            NSWindow *delegate = self->_delegate;
            if (self->_invalidated || self->_activated || delegate == nil || ![delegate _isActive])
                return;
            [delegate platformWindowDeactivated: self checkForAppDeactivation: NO];
        }];
    }
    _pendingSuspended = _suspended = NO;
    // The tracker survives hiding: _frame keeps the fullscreen size, so the size
    // from before fullscreen would be lost if the next map saved it again.
    _fullscreenRequested = _pendingFullscreen = _fullscreenRecheckPending = NO;
    _fullscreenReported = NO;
    _fullscreenSettling = NO;
    [_display windowUnmapped: self];
    [_display flush];
}

- (void) showWindowWithoutActivation {
    [self ensureMapped];
}

- (void) showWindowForAppActivation: (NSRect) frame {
    [self ensureMapped];
}

- (void) hideWindowForAppDeactivation: (NSRect) frame {
}

// Ordering a window out and in again within one pass of the run loop is invisible on macOS: the window
// stays where it is and keeps the focus. Toolkits do it for each pass of a frame loop. Here unmapping a
// toplevel destroys its role, and mapping it creates a new one that the compositor places and focuses
// anew, so the unmap waits for the end of the pass and is dropped if the window is ordered in by then.
// Windows that are not application toplevels (pop-ups, the menu bar, windows never shown) unmap at once.
- (void) hideWindow {
    if (!_mapped || _toplevel == NULL || _popup != NULL) {
        [self unmap];
        return;
    }
    if (_unmapPending)
        return;
    _unmapPending = YES;
    _shouldBeMapped = NO;
    _keyRequested = NO;
    [_display performAfterRunLoopPass: ^{
        if (self->_unmapPending)
            [self unmap];
    }];
}

- (void) sheetOrderFrontFromFrame: (NSRect) frame
                      aboveWindow: (CGWindow *) aboveWindow
{
    [self setFrame: frame];
    [self ensureMapped];
}

- (void) sheetOrderOutToFrame: (NSRect) frame {
    [self unmap];
}

// Clients can't restack or focus toplevels; the compositor decides.
- (void) placeAboveWindow: (NSInteger) otherNumber {
    [self ensureMapped];
}

- (void) placeBelowWindow: (NSInteger) otherNumber {
    [self ensureMapped];
}

// Reports to the NSWindow that this window is the compositor's focus (or the key window of a window
// that is never shown). The NSWindow decides whether that makes it key.
- (void) reportActivationDisplayingIfNeeded: (BOOL) displayIfNeeded {
    _reportingActivation = YES;
    [_delegate platformWindowActivated: self displayIfNeeded: displayIfNeeded];
    _reportingActivation = NO;
}

- (void) makeKey {
    // -[NSWindow becomeKeyWindow] asks for this while it answers an activation.
    if (_reportingActivation)
        return;
    _keyRequested = YES;
    [self ensureMapped];
    // Without the compositor's focus a window that is shown waits for it. A window that already has
    // it (it was ordered in and focused without becoming key) or that is never shown, so never gets
    // it, is reported as activated now.
    if (!_fullyTransparent && !_activated)
        return;
    [_display performAfterDispatch: ^{
        NSWindow *delegate = self->_delegate;
        if (self->_invalidated || delegate == nil || [delegate isKeyWindow])
            return;
        if (!self->_fullyTransparent && !self->_activated)
            return;
        [self->_display windowActivated: self];
        [self reportActivationDisplayingIfNeeded: NO];
    }];
}

- (void) makeMain {
}

- (void) captureEvents {
}

// xdg-shell has no request to undo set_minimized and no event that says a toplevel is minimized,
// so the window keeps the state itself. GUESS: the compositor minimizes the window when asked (it
// may ignore the request, and then the window is reported miniaturized until it is shown again).
// The state is kept only when something can bring the window back (xdg-activation) and the
// compositor advertised that it minimizes (a compositor that did not ignores the request, so the
// window would be reported miniaturized while it stays on screen). Otherwise the request is sent as
// before and the window keeps being reported as not miniaturized. GUESS: a compositor that
// predates the capabilities event (xdg_toplevel before version 5) minimizes.
- (BOOL) compositorMinimizes {
    return WL.wl_proxy_get_version(_toplevel) < 5 || _minimizeAdvertised;
}

- (void) miniaturize {
    if (_toplevel == NULL || _minimized)
        return;
    sendRequest(_toplevel, WP_TOPLEVEL_SET_MINIMIZED, 0);
    [_display flush];
    if (_display->_activation == NULL || ![self compositorMinimizes])
        return;
    _minimized = YES;
    [_display performAfterDispatch: ^{
        if (self->_minimized && !self->_invalidated)
            [self->_delegate platformWindowMiniaturized: self];
    }];
}

// The only client-side way to bring a minimized toplevel back is to ask for its activation
// (xdg-activation-v1); the compositor decides, and may only mark the window as wanting attention.
// The window counts as shown again from the request on. If no request could be made (one is waiting
// for its token) the state stays, and asking again later works. A restore the compositor does itself
// (its task bar) ends the state when a configure changes the window to activated (see
// -applyConfigure); a compositor that never reports the window deactivated cannot be told.
- (void) deminiaturize {
    if (_minimized && [_display requestActivationOfWindow: self])
        [self endMinimized];
    [self ensureMapped];
}

- (BOOL) isMiniaturized {
    return _minimized;
}

// The window is shown again (activated by the compositor, or mapped anew): tell the NSWindow.
- (void) endMinimized {
    if (!_minimized)
        return;
    _minimized = NO;
    // A window being invalidated (-dealloc does it) has no NSWindow to tell, and must not be retained.
    if (_invalidated)
        return;
    [_display performAfterDispatch: ^{
        if (!self->_minimized && !self->_invalidated)
            [self->_delegate platformWindowDeminiaturized: self];
    }];
}

// What xdg-shell offers of occlusion is the suspended state, sent by compositors that stop repainting a
// toplevel they do not show (version 6 of xdg_wm_base). A compositor that never sends it leaves the
// window seen whenever it is mapped.
- (BOOL) isOccluded {
    return _mapped && _suspended;
}

- (void) flashWindow {
}

#pragma mark - Properties

- (NSUInteger) styleMask {
    return _styleMask;
}

// Whether the window has a title bar for the platform to draw (see -[NSWindow
// _hasTitlebarForStyleMask:]).
- (BOOL) hasTitlebar {
    // A sheet is drawn over its window on macOS, but xdg-shell lets the compositor place every toplevel and
    // gives a client no way to put one at a position over its parent. A sheet left without a frame then
    // appears as a bare rectangle at a place of the compositor's choosing, which looks like a glitch. It is
    // presented as what the compositor can show well: a dialog related to its window (see
    // -updateLevelParent) with the compositor's frame.
    if ([_delegate respondsToSelector: @selector(isSheet)] && [(NSWindow *) _delegate isSheet])
        return YES;
    if ([_delegate respondsToSelector: @selector(_hasTitlebarForStyleMask:)])
        return [(NSWindow *) _delegate _hasTitlebarForStyleMask: _styleMask];
    return (_styleMask & NSWindowStyleMaskTitled) != 0;
}

// A window that shows nothing of a title bar of its own (see NSWindow) leaves nothing for the
// platform to draw as a title bar: the application draws its own header. Such a window gets no
// frame, neither from the compositor nor from the client-side fallback.
- (BOOL) wantsChromeless {
    return [_delegate respondsToSelector: @selector(_hasInvisibleTitlebarForStyleMask:)] &&
           [(NSWindow *) _delegate _hasInvisibleTitlebarForStyleMask: _styleMask];
}

// Whether this window should draw the client-side frame, given what the compositor asked for.
- (BOOL) wantsClientDecoration {
    return _toplevel != NULL && [self hasTitlebar] && ![self wantsChromeless] &&
            _pendingClientDecorated && !_pendingFullscreen;
}

// Tells the compositor which side draws the frame. A chromeless window declares client-side
// decorations explicitly because compositors differ on the default for a window that says nothing.
- (void) updateDecorationMode {
    if (_toplevel == NULL || _display->_decorationManager == NULL)
        return;
    union wl_argument args[2];
    if (![self hasTitlebar]) {
        if (_decoration != NULL)
            sendRequest(_decoration, WP_TOPLEVEL_DECORATION_UNSET_MODE, 0);
        return;
    }
    if (_decoration == NULL) {
        args[0].o = NULL;
        args[1].o = (struct wl_object *) _toplevel;
        _decoration = WaylandCreateObject(
                _display->_decorationManager,
                WP_DECORATION_MANAGER_GET_TOPLEVEL_DECORATION,
                &zxdg_toplevel_decoration_v1_interface, args,
                WaylandObjectDecoration, self);
    }
    args[0].u = (_decorationForcedClient || [self wantsChromeless])
            ? WP_TOPLEVEL_DECORATION_MODE_CLIENT_SIDE
            : WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE;
    WaylandMarshal(_decoration, WP_TOPLEVEL_DECORATION_SET_MODE, NULL, 0, args);
}

// Called when the style mask, the title bar transparency or the title visibility of a window
// change, and when it is shown (its standard buttons may have been hidden). On a mapped window
// the mode is updated and the client-side frame switched on or off right away, keeping the
// content size.
- (void) updateDecorationsForStyleMask: (NSUInteger) mask {
    _styleMask = mask;
    if (_toplevel == NULL)
        return;
    [self updateDecorationMode];
    if (!_configured || [self wantsClientDecoration] == _clientDecorated) {
        [_display flush];
        return;
    }
    if (!_pendingMaximized && !_pendingFullscreen) {
        BOOL framed = [self wantsClientDecoration];
        _pendingWidth = (int32_t) ceil(_frame.size.width) + (framed ? 2 * WaylandBorder : 0);
        _pendingHeight = (int32_t) ceil(_frame.size.height) + (framed ? 2 * WaylandBorder + WaylandTitleHeight : 0);
    }
    [self applyConfigure];
    [_display flush];
}

- (void) setStyleMask: (NSUInteger) mask {
    [self updateDecorationsForStyleMask: mask];
    [self updateSizeLimits];
    [self updateFullscreen];
}

#pragma mark - Fullscreen

// Whether the window should be fullscreen, and on which output (NULL: the
// compositor chooses; always NULL for a window that asked through the style mask).
- (BOOL) wantsFullscreenOn: (struct wl_proxy **) output {
    *output = NULL;
    if (_popup != NULL || _popupParent != nil)
        return NO;
    WaylandFullscreenOutput outputs[32];
    struct wl_proxy *proxies[32];
    size_t count = [_display fullscreenOutputs: outputs proxies: proxies max: 32
                                       entered: _surfaceOutputs];
    WaylandFullscreenWindow window = {
        .fullScreenStyle = (_styleMask & NSWindowStyleMaskFullScreen) != 0,
        .titled = (_styleMask & NSWindowStyleMaskTitled) != 0,
        .canBecomeKey = [_delegate canBecomeKeyWindow],
        .popupOrMenu = [_delegate isKindOfClass: NSClassFromString(@"NSMenuWindow")] ||
                       [_delegate isKindOfClass: NSClassFromString(@"NSPopUpWindow")],
        .width = WaylandFullscreenRound(_frame.size.width),
        .height = WaylandFullscreenRound(_frame.size.height),
    };
    int target;
    BOOL wanted = WaylandFullscreenDecide(&window, outputs, count, &target);
    if (target >= 0)
        *output = proxies[target];
    return wanted;
}

// Asks the compositor to enter or leave fullscreen when the answer changed.
- (void) updateFullscreen {
    if (_toplevel == NULL)
        return;
    struct wl_proxy *output;
    BOOL wanted = [self wantsFullscreenOn: &output];
    if (wanted == _fullscreenRequested)
        return;
    _fullscreenRequested = wanted;
    if (wanted)
        WaylandToplevelSetFullscreen(_toplevel, output);
    else
        WaylandToplevelUnsetFullscreen(_toplevel);
    if (_configured)
        [self beginFullscreenSettle];
    [_display flush];
}

// After set_fullscreen or unset_fullscreen the client waits for the configure that
// answers it before it commits again: the compositor decides the size. A commit
// sent before the answer arrives has the size the window gets from the
// application's own side of the change (the title bar goes away, for instance),
// and a compositor that lets a client's size count for a floating window (sway)
// then sends one more configure with that size and the fullscreen state, which
// wins over the real fullscreen size. Drawing resumes when a configure brings the
// requested state, or after a second when the compositor answers nothing.
- (void) beginFullscreenSettle {
    _fullscreenSettling = YES;
    NSUInteger token = ++_fullscreenSettleToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self->_fullscreenSettleToken != token || !self->_fullscreenSettling)
            return;
        self->_fullscreenSettling = NO;
        [self presentIfPossible];
    });
}

- (void) outputsChanged {
    if (_toplevel == NULL)
        return;
    _fullscreenRecheckPending = YES;
    NSUInteger generation = _surfaceGeneration;
    [_display performAfterDispatch: ^{
        if (self->_surfaceGeneration == generation)
            [self recheckFullscreen];
    }];
}

// A configure that is still queued carries the size the compositor chose for
// the new output layout; applyConfigure runs this once it has applied it.
- (void) recheckFullscreen {
    if (!_fullscreenRecheckPending || _configureUpdatePending)
        return;
    _fullscreenRecheckPending = NO;
    [self updateFullscreen];
}

- (void) setLevel: (int) value {
    _level = value;
    [self updateLevelParent];
    [self updateDialogForToplevel];
}

// xdg-shell cannot stack a window above arbitrary windows, but it can keep a
// window in front of another toplevel of the application: a window whose level is
// above the normal one but below the main menu's (floating panels, modal panels,
// utility windows) is made transient for the key window, so it stays in front of
// the window the user works in. Higher levels need a layering protocol that
// xdg-shell does not have and stay ordinary windows (see DarlingWindowLevelPolicy.h).
- (void) updateLevelParent {
    if (_toplevel == NULL)
        return;

    WaylandWindow *parent = nil;
    // A window of a raised level, and any window that is not an application window (a panel, a
    // child window, a window that cannot become main: see DarlingWindowPresentation.h), is related
    // to the window it belongs to, which keeps it in front of that window and out of the task bar.
    BOOL auxiliary = [_delegate respondsToSelector: @selector(_windowPresentation)] &&
                     [(NSWindow *) _delegate _windowPresentation] != DarlingWindowPresentationApplication;
    if (DarlingWindowRoleForLevel(_level) == DarlingWindowRoleTransient || auxiliary)
        parent = [_display levelParentForWindow: self];
    if (parent == _levelParent || (parent != nil && parent->_toplevel == NULL))
        return;
    _levelParent = parent;
    WaylandToplevelSetParent(_toplevel, parent != nil ? parent->_toplevel : NULL);
    [_display flush];
}

- (WaylandWindow *) levelParent {
    return _levelParent;
}

// Sheets and windows in an application modal session are the dialogs AppKit has. xdg-shell can relate
// a toplevel to its parent but cannot say that it is a dialog, so xdg-dialog-v1 tells the compositor.
- (BOOL) isDialogToplevel {
    NSWindow *window = _delegate;
    if (window == nil)
        return NO;
    return ([window respondsToSelector: @selector(isSheet)] && [window isSheet]) ||
           window == [NSApp modalWindow];
}

- (void) updateDialogForToplevel {
    BOOL dialog = _toplevel != NULL && [self isDialogToplevel] &&
                  _display->_dialogManager != NULL && _levelParent != nil &&
                  _levelParent->_toplevel != NULL;
    if (!dialog) {
        if (_dialog != NULL) {
            sendRequest(_dialog, XDG_DIALOG_DESTROY, WL_MARSHAL_FLAG_DESTROY);
            _dialog = NULL;
            _dialogModal = NO;
        }
        return;
    }
    if (_dialog == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _toplevel}};
        _dialog = WaylandCreateObject(_display->_dialogManager, XDG_WM_DIALOG_GET_XDG_DIALOG,
                                      &xdg_dialog_v1_interface, args, 0, nil);
        if (_dialog == NULL)
            return;
        _dialogModal = NO;
    }
    // A sheet is modal to its parent; the same is true of a window in an application modal session.
    // The client still filters events for the parent (AppKit does that), so this is only a hint.
    if (!_dialogModal) {
        sendRequest(_dialog, XDG_DIALOG_SET_MODAL, 0);
        _dialogModal = YES;
    }
}

- (void) dialogManagerAvailable {
    [self updateDialogForToplevel];
}

// The compositor drops the relation when the parent unmaps.
- (void) levelParentUnmapped {
    _levelParent = nil;
    [self updateDialogForToplevel];
}

// The tag is configuration data, so it uses the untranslated process name. The description is what a
// user sees, so it uses the localized window title. Both are sent before the first surface commit when
// the manager is available; a title change updates the description in place.
- (void) updateToplevelTags {
    if (_toplevel == NULL || _display->_toplevelTagManager == NULL)
        return;
    NSString *process = [[NSProcessInfo processInfo] processName];
    const char *tag = [process UTF8String];
    if (tag == NULL)
        tag = "window";
    union wl_argument args[2] = {{.o = (struct wl_object *) _toplevel}, {.s = tag}};
    WaylandMarshal(_display->_toplevelTagManager,
                   XDG_TOPLEVEL_TAG_MANAGER_SET_TOPLEVEL_TAG, NULL, 0, args);
    const char *description = [_title UTF8String];
    if (description == NULL || *description == '\0')
        description = tag;
    args[1].s = description;
    WaylandMarshal(_display->_toplevelTagManager,
                   XDG_TOPLEVEL_TAG_MANAGER_SET_TOPLEVEL_DESCRIPTION, NULL, 0, args);
}

// The display stays awake for a window only while the process holds a power assertion that prevents display
// sleep (kIOPMAssertPreventUserIdleDisplaySleep), which is what macOS does; the compositor only takes
// an inhibitor made for a surface. The inhibitor is only useful while the surface is mapped and visible:
// a compositor ignores it when the surface is unmapped or occluded, so it is dropped as soon as either
// happens.
- (void) updateIdleInhibitor {
    BOOL inhibit = !_invalidated && _mapped && !_suspended && !_fullyTransparent &&
                   _surface != NULL && _display->_idleInhibitManager != NULL &&
                   _CGSNativeConnectionDisplaySleepPrevented();
    if (inhibit && _idleInhibitor == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _idleInhibitor = WaylandCreateObject(_display->_idleInhibitManager,
                                             ZWP_IDLE_INHIBIT_MANAGER_CREATE_INHIBITOR,
                                             &zwp_idle_inhibitor_v1_interface, args, 0, nil);
    } else if (!inhibit && _idleInhibitor != NULL) {
        sendRequest(_idleInhibitor, ZWP_IDLE_INHIBITOR_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _idleInhibitor = NULL;
    }
}

- (void) updateTitle {
    if (_toplevel == NULL)
        return;
    const char *title = [_title UTF8String];
    union wl_argument args[1] = {{.s = title ? title : ""}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, args);
    [self updateToplevelTags];
}

- (void) setTitle: (NSString *) title {
    [_title release];
    _title = [title copy];
    [self updateTitle];
    if (_clientDecorated)
        [self flushBuffer];
    [_display flush];
}

// A size limit of the NSWindow as a xdg_toplevel size: in window geometry coordinates, where 0
// means no limit. A value that is 0 or less, or too large to represent (the FLT_MAX of an unset
// maximum), is no limit.
static int32_t WaylandToplevelLimit(CGFloat limit, CGFloat decoration) {
    if (!(limit > 0) || limit >= (CGFloat) INT32_MAX - decoration)
        return 0;
    return (int32_t) ceil(limit + decoration);
}

- (void) updateSizeLimits {
    if (_layerSurface != NULL) {
        [self updateLayerSize];
        return;
    }
    if (_toplevel == NULL)
        return;

    CGFloat decorationWidth = _clientDecorated ? 2 * WaylandBorder : 0;
    CGFloat decorationHeight = _clientDecorated ? 2 * WaylandBorder + WaylandTitleHeight : 0;
    union wl_argument min[2] = {{.i = 0}, {.i = 0}};
    union wl_argument max[2] = {{.i = 0}, {.i = 0}};
    if (!(_styleMask & NSWindowStyleMaskResizable)) {
        min[0].i = max[0].i = (int32_t) _frame.size.width + (int32_t) decorationWidth;
        min[1].i = max[1].i = (int32_t) _frame.size.height + (int32_t) decorationHeight;
    } else if ([_delegate respondsToSelector: @selector(_minFrameSize)]) {
        NSSize minSize = [(NSWindow *) _delegate _minFrameSize];
        NSSize maxSize = [(NSWindow *) _delegate _maxFrameSize];
        min[0].i = WaylandToplevelLimit(minSize.width, decorationWidth);
        min[1].i = WaylandToplevelLimit(minSize.height, decorationHeight);
        max[0].i = WaylandToplevelLimit(maxSize.width, decorationWidth);
        max[1].i = WaylandToplevelLimit(maxSize.height, decorationHeight);
        // A maximum below the minimum is a protocol error, so the minimum wins.
        for (int i = 0; i < 2; i++)
            if (max[i].i != 0 && max[i].i < min[i].i)
                max[i].i = min[i].i;
    }
    // Double buffered: the compositor sees them with the surface's next commit.
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MIN_SIZE, NULL, 0, min);
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MAX_SIZE, NULL, 0, max);
}

// The NSWindow's minSize, maxSize, contentMinSize or contentMaxSize changed.
- (void) sizeLimitsChanged {
    if (_toplevel == NULL)
        return;
    [self updateSizeLimits];
    [_display flush];
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
}

- (void) setAlphaValue: (CGFloat) value {
    BOOL transparent = value <= 0;
    if (transparent != _fullyTransparent) {
        // Without alpha-modifier a fully transparent window is simply not shown (see
        // -isFullyTransparent); with it any value can be sent to the compositor.
        _fullyTransparent = transparent;
        if (transparent) {
            BOOL ordered = _shouldBeMapped;
            [self unmap];
            _shouldBeMapped = ordered;
        } else if (_shouldBeMapped)
            [self ensureMapped];
    }
    if (_mapped) {
        [self updateAlphaModifier];
        [self updateIdleInhibitor];
    }
}

- (void) setHasShadow: (BOOL) value {
    _hasShadow = value;
}

- (CGLContextObj) cglContext {
    return NULL;
}

- (void) addEntriesToDeviceDictionary: (NSDictionary *) entries {
    [_deviceDictionary addEntriesFromDictionary: entries];
}

- (CGSubWindow *) createSubWindowWithFrame: (CGRect) frame {
    if (!_display->_eglAvailable || _invalidated) return nil;
    return [[[WaylandSubWindow alloc] initWithParentWindow: self frame: frame] autorelease];
}

#pragma mark - Geometry

- (O2Rect) frame {
    return _frame;
}

- (void) setFrame: (O2Rect) frame {
    frame.size.width = MAX(frame.size.width, 1.0);
    frame.size.height = MAX(frame.size.height, 1.0);

    BOOL moved = !NSEqualPoints(frame.origin, _frame.origin);
    BOOL sized = !NSEqualSizes(frame.size, _frame.size);
    [self invalidateContextWithNewSize: frame.size];
    _frame = frame;
    // The application chose a new size: leaving fullscreen returns to it, even
    // when the compositor answers unset_fullscreen with the size it remembered.
    if (sized)
        WaylandFullscreenApplicationResized(&_fullscreenTracker,
                                            WaylandFullscreenRound(frame.size.width),
                                            WaylandFullscreenRound(frame.size.height));
    if (_popup != NULL && (moved || sized) && WL.wl_proxy_get_version(_popup) >= 3) {
        struct wl_proxy *positioner = [self newPopupPositioner];
        union wl_argument args[2] = {{.o = (struct wl_object *) positioner},
                                     {.u = ++_repositionToken}};
        WaylandMarshal(_popup, WP_POPUP_REPOSITION, NULL, 0, args);
        sendRequest(positioner, WP_POSITIONER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        [_display flush];
    }
    [self updateSubwindows];
    if (sized) {
        [self updateSizeLimits];
        [self updateFullscreen];
        [_display flush];
    }
}

- (NSPoint) transformPoint: (CGPoint) surfacePoint {
    NSPoint offset = [self contentOffset];
    return NSMakePoint(surfacePoint.x - offset.x, _frame.size.height - surfacePoint.y + offset.y);
}

- (NSPoint) contentOffset {
    return _clientDecorated ? NSMakePoint(WaylandBorder, WaylandBorder + WaylandTitleHeight) : NSZeroPoint;
}

- (BOOL) isDecorationPoint: (CGPoint) point {
    if (!_clientDecorated)
        return NO;
    NSPoint offset = [self contentOffset];
    return point.x < offset.x || point.y < offset.y ||
           point.x >= offset.x + _frame.size.width || point.y >= offset.y + _frame.size.height;
}

- (BOOL) decorationButton: (uint32_t) button pressed: (BOOL) pressed
                   serial: (uint32_t) serial atPoint: (CGPoint) point
{
    if (![self isDecorationPoint: point])
        return NO;
    if (!pressed || button != WP_BTN_LEFT || _toplevel == NULL || [_display seat] == NULL)
        return YES;
    CGFloat width = _frame.size.width + 2 * WaylandBorder;
    CGFloat height = _frame.size.height + 2 * WaylandBorder + WaylandTitleHeight;
    uint32_t edge = 0;
    if (point.y < WaylandBorder) edge |= 1;
    if (point.y >= height - WaylandBorder) edge |= 2;
    if (point.x < WaylandBorder) edge |= 4;
    if (point.x >= width - WaylandBorder) edge |= 8;
    union wl_argument args[3] = {{.o = (struct wl_object *) [_display seat]},
                                 {.u = serial}, {.u = edge}};
    if (edge != 0) {
        if (_styleMask & NSWindowStyleMaskResizable)
            WaylandMarshal(_toplevel, WP_TOPLEVEL_RESIZE, NULL, 0, args);
    } else if (point.y < WaylandBorder + WaylandTitleHeight) {
        CGFloat x = point.x - WaylandBorder;
        if (x >= 4 && x < 22 && (_styleMask & NSWindowStyleMaskClosable))
            [self closeRequested];
        else if (x >= 24 && x < 42 && (_styleMask & NSWindowStyleMaskMiniaturizable))
            [self miniaturize];
        else if (x >= 44 && x < 62 && (_styleMask & NSWindowStyleMaskResizable))
            sendRequest(_toplevel, _maximized ? WP_TOPLEVEL_UNSET_MAXIMIZED : WP_TOPLEVEL_SET_MAXIMIZED, 0);
        else
            WaylandMarshal(_toplevel, WP_TOPLEVEL_MOVE, NULL, 0, args);
    }
    [_display flush];
    return YES;
}

// -[NSWindow performWindowDragWithEvent:]: a client cannot place a toplevel, so
// the compositor moves it, for the press the event stands for (xdg_toplevel.move
// with that press's serial). NO for a popup, or when the event is not the
// press being dispatched.
- (BOOL) moveByWindowManagerForEvent: (NSEvent *) event {
    if (_toplevel == NULL || [_display seat] == NULL)
        return NO;
    uint32_t serial = [_display dragSerialForEvent: event];
    if (serial == 0)
        return NO;
    union wl_argument args[2] = {{.o = (struct wl_object *) [_display seat]}, {.u = serial}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_MOVE, NULL, 0, args);
    [_display flush];
    return YES;
}

- (void) setLastKnownCursorPosition: (CGPoint) point {
    _lastMotionPos = point;
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return _lastMotionPos;
}

#pragma mark - Drawing

- (int32_t) bufferScale { return _bufferScale; }
- (CGFloat) backingScaleFactor { return _renderScale120 / 120.0; }
- (uint32_t) renderScale120 { return _renderScale120; }
// The fastest output the surface is on, 0 before it has entered one.
- (uint32_t) refreshMillihertz {
    uint32_t refresh = 0;
    for (NSValue *output in _surfaceOutputs)
        refresh = MAX(refresh, [_display refreshForOutput: [output pointerValue]]);
    return refresh;
}
- (void) preferredScaleChanged: (uint32_t) scale120 {
    if (!_fractionalScale || scale120 == 0 || scale120 == _preferredScale120) return;
    _preferredScale120 = scale120;
    [self scheduleScaleUpdate];
}
- (NSSize) logicalSurfaceSize {
    return NSMakeSize(ceil(_frame.size.width) + (_clientDecorated ? 2 * WaylandBorder : 0),
        ceil(_frame.size.height) + (_clientDecorated ? 2 * WaylandBorder + WaylandTitleHeight : 0));
}

- (void) outputRemoved: (struct wl_proxy *) output {
    [_surfaceOutputs removeObject: [NSValue valueWithPointer: output]];
    [self scheduleScaleUpdate];
}

- (void) scheduleScaleUpdate {
    if (_scaleUpdatePending)
        return;
    _scaleUpdatePending = YES;
    [_display performAfterDispatch: ^{
        self->_scaleUpdatePending = NO;
        if (!self->_mapped || self->_delegate == nil)
            return;
        int32_t scale = 1;
        if (self->_display->_compositorVersion >= 3)
            for (NSValue *output in self->_surfaceOutputs)
                scale = MAX(scale, [self->_display scaleForOutput: [output pointerValue]]);
        uint32_t render = self->_fractionalScale && self->_preferredScale120
            ? WaylandIntegralScale120(self->_preferredScale120) : (uint32_t)MIN((uint64_t)scale * 120, UINT32_MAX);
        if (scale == self->_bufferScale && render == self->_renderScale120) return;
        CGFloat oldScale = self->_renderScale120 / 120.0;
        self->_bufferScale = scale;
        self->_renderScale120 = render;
        [self updateSubwindows];
        [self->_context release];
        self->_context = nil;
        self->_needsPresent = NO;
        [self->_delegate platformWindowDidInvalidateCGContext: self];
        // The window and its views learn of the new scale before they redraw.
        if ([self->_delegate respondsToSelector: @selector(platformWindow:didChangeBackingScaleFrom:)])
            [self->_delegate platformWindow: self didChangeBackingScaleFrom: oldScale];
        [self->_delegate platformWindowExposed: self
                                      inRect: NSMakeRect(0, 0, self->_frame.size.width,
                                                         self->_frame.size.height)];
        // Expose only posts a notification in Cocotron. A new backing surface
        // needs a full redraw, even when no view has invalidated its contents.
        [self->_delegate display];
        [self->_display windowScaleChanged: self];
    }];
}

- (O2Context *) createCGContextIfNeeded {
    if (_context == nil) {
        NSSize logical = [self logicalSurfaceSize];
        int32_t width, height;
        if (!isfinite(logical.width) || !isfinite(logical.height) || logical.width < 1 || logical.height < 1 ||
            logical.width > INT32_MAX || logical.height > INT32_MAX ||
            !WaylandScaleExtent((int32_t)logical.width, _renderScale120, INT32_MAX / 4, &width) ||
            !WaylandScaleExtent((int32_t)logical.height, _renderScale120, INT32_MAX / (width * 4), &height)) {
            NSLog(@"Wayland backend: window buffer dimensions exceed wl_shm limits");
            return nil;
        }
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc]
                   initWithBytes: NULL
                           width: width
                          height: height
                bitsPerComponent: 8
                     bytesPerRow: 0
                      colorSpace: colorSpace
                      bitmapInfo: kO2ImageAlphaPremultipliedFirst |
                                  kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        _context = [[WaylandDrawingContext alloc] initWithSurface: surface logicalSize: logical
                                                          border: _clientDecorated ? WaylandBorder : 0];
        [surface release];
    }
    return _context;
}

- (O2Context *) cgContext {
    return [self createCGContextIfNeeded];
}

- (void) invalidateContextWithNewSize: (NSSize) size {
    if (!NSEqualSizes(_frame.size, size)) {
        _frame.size = size;
        [_context release];
        _context = nil;
        [_delegate platformWindowDidInvalidateCGContext: self];
    }
}

- (void) drawDecorations {
    if (!_clientDecorated || _context == nil)
        return;
    [NSGraphicsContext saveGraphicsState];
    O2ContextSaveGState(_context);
    @try {
        [NSGraphicsContext setCurrentContext:
            [NSGraphicsContext graphicsContextWithGraphicsPort: (CGContextRef) _context flipped: NO]];
        O2ContextResetClip(_context);
        O2ContextSetCTM(_context, O2AffineTransformIdentity);
        CGFloat w = _frame.size.width, h = _frame.size.height;
        [[NSColor colorWithCalibratedWhite: _activated ? 0.82 : 0.92 alpha: 1] set];
        NSRectFill(NSMakeRect(-WaylandBorder, h, w + 2 * WaylandBorder,
                              WaylandTitleHeight + WaylandBorder));
        NSRectFill(NSMakeRect(-WaylandBorder, -WaylandBorder, w + 2 * WaylandBorder, WaylandBorder));
        NSRectFill(NSMakeRect(-WaylandBorder, 0, WaylandBorder, h));
        NSRectFill(NSMakeRect(w, 0, WaylandBorder, h));
        NSUInteger masks[] = {NSWindowStyleMaskClosable, NSWindowStyleMaskMiniaturizable,
                               NSWindowStyleMaskResizable};
        NSColor *colors[] = {[NSColor redColor], [NSColor yellowColor], [NSColor greenColor]};
        for (int i = 0; i < 3; ++i) {
            [(_styleMask & masks[i] ? colors[i] : [NSColor grayColor]) set];
            [[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(7 + i * 20, h + 8, 12, 12)] fill];
        }
        [_title drawInRect: NSMakeRect(76, h + 6, MAX(0, w - 90), 18)
           withAttributes: @{NSFontAttributeName: [NSFont systemFontOfSize: 12],
                             NSForegroundColorAttributeName: [NSColor blackColor]}];
    } @finally {
        O2ContextRestoreGState(_context);
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (void) flushBuffer {
    if (_context == nil)
        return;
    [self drawDecorations];
    O2ContextFlush(_context);
    _needsPresent = YES;
    [self presentIfPossible];
}

- (struct WaylandBuffer *) bufferWithWidth: (int32_t) width
                                    height: (int32_t) height
                                    format: (uint32_t) format
{
    struct WaylandBuffer *reusable = NULL;

    for (int i = 0; i < 2; i++) {
        struct WaylandBuffer *buffer = &_buffers[i];
        if (buffer->busy)
            continue;
        if (buffer->buffer != NULL && buffer->width == width &&
            buffer->height == height && buffer->format == format)
            return buffer;
        if (reusable == NULL)
            reusable = buffer;
    }
    // Both buffers are still in use: present again when one is released.
    if (reusable == NULL)
        return NULL;

    if (width < 1 || height < 1 || width > INT32_MAX / 4 ||
        height > INT32_MAX / (width * 4))
        return NULL;

    if (reusable->buffer != NULL)
        sendRequest(reusable->buffer, WP_BUFFER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (reusable->data != NULL)
        munmap(reusable->data, reusable->size);
    memset(reusable, 0, sizeof(*reusable));

    int32_t stride = width * 4;
    size_t size = (size_t) stride * (size_t) height;
    int fd = WaylandCreateAnonymousFile(size);
    if (fd < 0) {
        NSLog(@"Wayland backend: cannot allocate a %dx%d window buffer", width,
              height);
        return NULL;
    }

    void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        NSLog(@"Wayland backend: cannot map a %dx%d window buffer: %s", width,
              height, strerror(errno));
        close(fd);
        return NULL;
    }

    // libwayland duplicates the descriptor when it marshals the request.
    union wl_argument poolArgs[3] = {{.o = NULL}, {.h = fd}, {.i = (int32_t) size}};
    struct wl_proxy *pool = WaylandCreateObject(_display->_shm, WP_SHM_CREATE_POOL,
                                                &wl_shm_pool_interface, poolArgs,
                                                0, nil);
    close(fd);

    union wl_argument bufferArgs[6] = {{.o = NULL},    {.i = 0},
                                       {.i = width},   {.i = height},
                                       {.i = stride},  {.u = format}};
    struct wl_proxy *proxy = WaylandCreateObject(pool, WP_SHM_POOL_CREATE_BUFFER,
                                                 &wl_buffer_interface, bufferArgs,
                                                 WaylandObjectBuffer, self);
    sendRequest(pool, WP_SHM_POOL_DESTROY, WL_MARSHAL_FLAG_DESTROY);

    reusable->buffer = proxy;
    reusable->data = data;
    reusable->size = size;
    reusable->width = width;
    reusable->height = height;
    reusable->format = format;
    return reusable;
}

// Copies the current content into a shm buffer and commits it, at most once
// per frame callback.
- (void) presentIfPossible {
    if (!_needsPresent || !_mapped || !_configured || _configureUpdatePending || _frameCallback != NULL ||
        _fullscreenSettling || _context == nil)
        return;

    O2Surface *surface = [_context surface];
    size_t width = O2SurfaceGetWidth(surface);
    size_t height = O2SurfaceGetHeight(surface);
    size_t sourceStride = O2SurfaceGetBytesPerRow(surface);
    const uint8_t *pixels = O2SurfaceGetPixelBytes(surface);
    if (pixels == NULL || width == 0 || height == 0 || sourceStride < width * 4)
        return;

    // Onyx2D's premultiplied, little-endian ARGB is wl_shm's ARGB8888.
    uint32_t format = _isOpaque ? WP_SHM_FORMAT_XRGB8888 : WP_SHM_FORMAT_ARGB8888;
    struct WaylandBuffer *buffer = [self bufferWithWidth: (int32_t) width
                                                  height: (int32_t) height
                                                  format: format];
    if (buffer == NULL)
        return;

    // Both start with the top row.
    for (size_t row = 0; row < height; row++)
        memcpy((uint8_t *) buffer->data + row * width * 4,
               pixels + row * sourceStride, width * 4);

    union wl_argument args[4] = {{.o = (struct wl_object *) buffer->buffer},
                                 {.i = 0},
                                 {.i = 0}};
    if (_display->_compositorVersion >= 3) {
        union wl_argument scale[1] = {{.i = _fractionalScale ? 1 : _bufferScale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scale);
    }
    NSSize logical = [self logicalSurfaceSize];
    if (_viewport) {
        union wl_argument destination[] = {{.i = (int32_t)logical.width}, {.i = (int32_t)logical.height}};
        WaylandMarshal(_viewport, WP_VIEWPORT_SET_DESTINATION, NULL, 0, destination);
    }
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, args);

    args[0].i = 0;
    args[1].i = 0;
    args[2].i = _display->_compositorVersion >= 4 ? (int32_t)width : (int32_t)logical.width;
    args[3].i = _display->_compositorVersion >= 4 ? (int32_t)height : (int32_t)logical.height;
    WaylandMarshal(_surface,
                   _display->_compositorVersion >= 4 ? WP_SURFACE_DAMAGE_BUFFER
                                                     : WP_SURFACE_DAMAGE,
                   NULL, 0, args);

    args[0].o = NULL;
    _frameCallback = WaylandCreateObject(_surface, WP_SURFACE_FRAME,
                                         &wl_callback_interface, args,
                                         WaylandObjectFrameCallback, self);

    [self commitSurface];
    buffer->busy = YES;
    _needsPresent = NO;
    [_display flush];
}

#pragma mark - Events

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args
{
    switch (kind) {
    case WaylandObjectSurface:
        if (opcode == WP_SURFACE_EV_ENTER) {
            [_surfaceOutputs addObject: [NSValue valueWithPointer: args[0].o]];
            [self scheduleScaleUpdate];
        } else if (opcode == WP_SURFACE_EV_LEAVE) {
            [self outputRemoved: (struct wl_proxy *) args[0].o];
        }
        break;
    case WaylandObjectXdgSurface:
        if (opcode == WP_XDG_SURFACE_EV_CONFIGURE)
            [self configure: args[0].u];
        break;

    case WaylandObjectLayerSurface:
        if (opcode == WP_LAYER_SURFACE_EV_CONFIGURE) {
            union wl_argument ack[1] = {{.u = args[0].u}};
            WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_ACK_CONFIGURE, NULL, 0, ack);
            // A zero size leaves the choice to the client.
            _pendingWidth = args[1].u != 0 ? (int32_t) args[1].u : (int32_t) ceil(_frame.size.width);
            _pendingHeight = args[2].u != 0 ? (int32_t) args[2].u : (int32_t) ceil(_frame.size.height);
            _pendingActivated = NO;
            _pendingMaximized = _pendingFullscreen = NO;
            [self scheduleConfigureApply];
        } else if (opcode == WP_LAYER_SURFACE_EV_CLOSED) {
            // The compositor took the bar away (its output is gone): it is not a window the
            // user closed, so the bar is only hidden.
            NSUInteger generation = _surfaceGeneration;
            [_display performAfterDispatch: ^{
                if (!self->_mapped || self->_surfaceGeneration != generation)
                    return;
                [self unmap];
                [self->_delegate orderOut: nil];
            }];
        }
        break;

    case WaylandObjectToplevel:
        if (opcode == WP_TOPLEVEL_EV_CONFIGURE) {
            _pendingWidth = args[0].i;
            _pendingHeight = args[1].i;
            struct wl_array *states = args[2].a;
            _pendingActivated = WaylandStatesContain(states, WP_TOPLEVEL_STATE_ACTIVATED);
            _pendingMaximized = WaylandStatesContain(states, WP_TOPLEVEL_STATE_MAXIMIZED);
            _pendingFullscreen = WaylandStatesContain(states, WP_TOPLEVEL_STATE_FULLSCREEN);
            _pendingSuspended = WaylandStatesContain(states, WP_TOPLEVEL_STATE_SUSPENDED);
        } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
            [self closeRequested];
        } else if (opcode == WP_TOPLEVEL_EV_WM_CAPABILITIES) {
            _pendingMinimizeAdvertised = WaylandStatesContain(args[0].a, WP_TOPLEVEL_CAPABILITY_MINIMIZE);
        }
        break;

    case WaylandObjectToplevelSession:
        // The event only says the compositor used the state saved under this name; the state itself
        // arrives with the following configure, which is handled as an ordinary toplevel configure.
        break;

    case WaylandObjectDecoration:
        if (opcode == WP_TOPLEVEL_DECORATION_EV_CONFIGURE)
            _pendingClientDecorated = args[0].u != WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE;
        break;

    case WaylandObjectPopup:
        if (opcode == WP_POPUP_EV_CONFIGURE) {
            _pendingPopupX = args[0].i;
            _pendingPopupY = args[1].i;
            _pendingWidth = args[2].i;
            _pendingHeight = args[3].i;
        } else if (opcode == WP_POPUP_EV_DONE) {
            NSUInteger generation = _surfaceGeneration;
            BOOL tooltip = [self isTooltip];
            [_display performAfterDispatch: ^{
                if (!self->_mapped || self->_surfaceGeneration != generation)
                    return;
                // Dismissing a tool tip must not cancel menu tracking.
                if (tooltip || self->_genericPopup)
                    [self unmap];
                else
                    [self->_display cancelPopupMenus];
            }];
        }
        break;

    case WaylandObjectFrameCallback:
        if (proxy == _frameCallback) {
            WL.wl_proxy_destroy(_frameCallback);
            _frameCallback = NULL;
            [self presentIfPossible];
        }
        break;

    case WaylandObjectBuffer:
        for (int i = 0; i < 2; i++)
            if (_buffers[i].buffer == proxy)
                _buffers[i].busy = NO;
        [self presentIfPossible];
        break;

    default:
        break;
    }
}

// xdg_surface.configure ends a configure sequence: apply the toplevel state.
- (void) configure: (uint32_t) serial {
    union wl_argument args[1] = {{.u = serial}};
    WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_ACK_CONFIGURE, NULL, 0, args);
    [self scheduleConfigureApply];
}

- (void) scheduleConfigureApply {
    if (_configureUpdatePending)
        return;
    _configureUpdatePending = YES;
    NSUInteger generation = _surfaceGeneration;
    [_display performAfterDispatch: ^{
        if (!self->_mapped || self->_surfaceGeneration != generation)
            return;
        self->_configureUpdatePending = NO;
        [self applyConfigure];
    }];
}

- (void) applyConfigure {
    // A fullscreen window has no frame of its own to draw.
    BOOL clientDecorated = [self wantsClientDecoration];
    BOOL decorationChanged = clientDecorated != _clientDecorated;
    _clientDecorated = clientDecorated;
    _maximized = _pendingMaximized;
    if (decorationChanged) {
        [_context release];
        _context = nil;
        _needsPresent = NO;
        [_delegate platformWindowDidInvalidateCGContext: self];
        [self updateSizeLimits];
    }
    int32_t width, height;
    WaylandFullscreenConfigure(&_fullscreenTracker, _pendingFullscreen,
            WaylandFullscreenRound(_frame.size.width), WaylandFullscreenRound(_frame.size.height),
            _pendingWidth - (_clientDecorated ? 2 * WaylandBorder : 0),
            _pendingHeight - (_clientDecorated ? 2 * WaylandBorder + WaylandTitleHeight : 0),
            &width, &height);
    BOOL firstConfigure = !_configured;
    _configured = YES;
    if (firstConfigure) {
        [_display performAfterDispatch: ^{
          [self->_display mapPopupsWaitingForParent];
        }];
    }

    // Tell the delegate when the compositor's fullscreen state changes.
    BOOL fullscreenChanged = _pendingFullscreen != _fullscreenReported;
    _fullscreenReported = _pendingFullscreen;
    if (_fullscreenSettling && _fullscreenReported == _fullscreenRequested)
        _fullscreenSettling = NO;

    BOOL sized = NO;
    BOOL moved = NO;
    if (_popupParent != nil) {
        NSRect parent = [_popupParent frame];
        NSPoint offset = [_popupParent contentOffset];
        NSPoint origin = NSMakePoint(parent.origin.x + _pendingPopupX - offset.x,
                NSMaxY(parent) - _pendingPopupY + offset.y - _pendingHeight);
        moved = !NSEqualPoints(_frame.origin, origin);
        _frame.origin = origin;
    }
    if (width > 0 && height > 0 &&
        (width != WaylandFullscreenRound(_frame.size.width) ||
         height != WaylandFullscreenRound(_frame.size.height)))
    {
        // Keep the top edge where it was, as the compositor does on screen.
        O2Rect frame = _frame;
        if (_popupParent == nil)
            frame.origin.y += frame.size.height - height;
        frame.size = NSMakeSize(width, height);
        [self invalidateContextWithNewSize: frame.size];
        _frame = frame;
        sized = YES;
    }

    [self updateSubwindows];
    [self recheckFullscreen];

    if (fullscreenChanged) {
        BOOL fullscreen = _fullscreenReported;
        [_display performAfterDispatch: ^{
          if ([self->_delegate respondsToSelector: @selector(platformWindow:didChangeFullScreen:)])
              [self->_delegate platformWindow: self didChangeFullScreen: fullscreen];
        }];
    }

    BOOL activationChanged = _pendingActivated != _activated;
    BOOL activated = _pendingActivated;
    _activated = activated;
    _minimizeAdvertised = _pendingMinimizeAdvertised;
    // Only the change to activated shows a restore: a configure that repeats the state of a window
    // that was active when it was minimized may already be on its way.
    if (activationChanged && activated)
        [self endMinimized];

    BOOL suspendedChanged = _pendingSuspended != _suspended;
    _suspended = _pendingSuspended;
    if (suspendedChanged) {
        [self updateIdleInhibitor];
        [_display performAfterDispatch: ^{
          if ([self->_delegate respondsToSelector: @selector(platformWindowOcclusionChanged:)])
              [self->_delegate platformWindowOcclusionChanged: self];
        }];
    }

    if (firstConfigure || sized || moved || activationChanged || decorationChanged) {
        [_display performAfterDispatch: ^{
          NSWindow *delegate = self->_delegate;
          if (delegate == nil)
              return;
          if (sized || moved)
              [delegate platformWindow: self
                          frameChanged: self->_frame
                               didSize: sized];
          if (firstConfigure || sized)
              [delegate platformWindowExposed: self
                                       inRect: NSMakeRect(0, 0,
                                                          self->_frame.size.width,
                                                          self->_frame.size.height)];
          if (firstConfigure || sized || decorationChanged)
              [delegate display];
          else if (activationChanged)
              [self flushBuffer];
          if (activationChanged && activated) {
              [self->_display windowActivated: self];
              if ([delegate attachedSheet] != nil)
                  [[delegate attachedSheet] makeKeyAndOrderFront: delegate];
              else
                  [self reportActivationDisplayingIfNeeded: YES];
          } else if (activationChanged) {
              [delegate platformWindowDeactivated: self
                          checkForAppDeactivation: NO];
              [self->_display applicationFocusMayHaveLeft];
          }
        }];
    }

    [self presentIfPossible];
}

// Whether the compositor currently holds the window fullscreen.
- (BOOL) isFullScreen {
    return _mapped && _fullscreenReported;
}

- (void) closeRequested {
    [[NSRunLoop currentRunLoop]
            cancelPerformSelector: @selector(platformWindowWillClose:)
                           target: _delegate
                         argument: self];
    [[NSRunLoop currentRunLoop]
            performSelector: @selector(platformWindowWillClose:)
                     target: _delegate
                   argument: self
                      order: 0
                      modes: @[
                          NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                          NSEventTrackingRunLoopMode
                      ]];
}

@end
