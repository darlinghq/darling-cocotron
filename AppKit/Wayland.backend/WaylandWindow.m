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
#import "WaylandRender.h"
#import "../DarlingWindowLevelPolicy.h"
#import "../../CoreGraphics/Wayland.backend/CGSWindowWayland.h"
#import <CoreGraphics/CGSServerSPI.h>
#import <IOSurface/IOSurface.h>
#import "../DarlingWindowPresentation.h"
#import "../NSCGSInputMethod.h"
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

// Implemented by NSScreen for both screen outputs and compositor-preferred descriptions. Declared
// here rather than in AppKit's public header because only this backend needs it.
@interface NSScreen (WaylandColorDescription)
+ (NSColorSpace *) _colorSpaceFromDisplayColorInfo: (NSDictionary *) info;
@end

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

static void WaylandWindowToplevelEvent(CGSWindow *window, const CGSToplevelEvent *event, void *info);

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
    // Until NSWindow says what the window shows of a title bar, a titled window has a standard one.
    _titlebarKind = (_styleMask & NSWindowStyleMaskTitled) ? kCGSToplevelTitlebarStandard : kCGSToplevelTitlebarNone;
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

    // The window system's window: its id is this window's number.
    CGSToplevelAttributes attributes = {
        .frame = NSRectToCGRect(_frame),
        .unmanaged = NO,
        .translucent = YES,
    };
    _cgsWindow = [_CGSNewToplevelWindow(&attributes) retain];
    if (_cgsWindow == nil) {
        NSLog(@"Wayland backend: CoreGraphics has no window to make for this window");
        [self release];
        return nil;
    }
    [_cgsWindow setToplevelEventProc: WaylandWindowToplevelEvent info: self];

    [_display windowCreated: self];
    return self;
}

// The window's number is the id of its CoreGraphics window.
- (NSInteger) _assignedWindowNumber {
    return _cgsWindow != nil ? (NSInteger) [_cgsWindow windowId] : 0;
}

- (void) dealloc {
    [self invalidate];
    [self destroySurface];
    // CoreGraphics destroys the window system's window, with the surface.
    [_cgsWindow setToplevelEventProc: NULL info: NULL];
    [_inputMethod invalidate];
    [_inputMethod release];
    _inputMethod = nil;
    if (_cgsWindow != nil)
        CGSReleaseWindow(CGSMainConnectionID(), [_cgsWindow windowId]);
    [_cgsWindow release];
    [_subwindows release];
    [_display release];
    [_deviceDictionary release];
    [_surfaceOutputs release];
    [_title release];
    [_sessionName release];
    [_preferredColorSpace release];
    [super dealloc];
}

- (void) invalidate {
    // Like X11Window, this can run several times.
    if (_invalidated) return;
    _invalidated = YES;
    [_cgsWindow setToplevelHeldBack: NO];
    [_context release];
    _context = nil;

    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;

    [self unmap];
    [_inputMethod invalidate];
    [_inputMethod release];
    _inputMethod = nil;
    if (_display != nil) {
        [_display windowDestroyed: self];
        // Children retain this window until their EGL surfaces are released.
        // Keep the native parent surface/display alive for that whole lifetime.
    }
}

// The window uses the window system's input method, which CoreGraphics runs, for the text of its first responder; what
// it composes comes back as toplevel events (see -toplevelEvent:).
- (void) updateInputMethodSpot {
    if (_inputMethod == nil) {
        if (_cgsWindow == nil || _invalidated || ![NSCGSInputMethod available])
            return;
        _inputMethod = [[NSCGSInputMethod alloc] initWithPlatformWindow: self cgsWindow: _cgsWindow];
    }
    [_inputMethod firstResponderChanged];
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
        // The wl_surface is the window system window's; this window listens to what it says of the outputs.
        _surface = (struct wl_proxy *) [_cgsWindow nativeWindow];
        if (_surface != NULL)
            WL.wl_proxy_add_dispatcher(_surface, WaylandDispatch, (void *) (uintptr_t) WaylandObjectSurface, self);
        _fractionalScale = [_display newFractionalScaleForSurface: _surface owner: (id)self];
        if (_fractionalScale) {
            union wl_argument viewportArgs[] = {{.o = NULL}, {.o = (struct wl_object *)_surface}};
            _viewport = WaylandCreateObject(_display->_viewporter, WP_VIEWPORTER_GET_VIEWPORT,
                &wp_viewport_interface, viewportArgs, 0, nil);
        }
        WaylandColorManager *color = [_display colorManager];
        if (color != nil && _surfaceFeedback == NULL)
            _surfaceFeedback = [color newSurfaceFeedbackForSurface: _surface];
        [[_display renderManager] observeSurface: _surface];
        [self updateSurfaceColorIfNeeded];
        [self updateContentType];
        [self updateShortcutsInhibitor];
    }
    return _surface;
}

// The color space of the content the window draws, or sRGB when neither the window nor a screen
// reports one (a display the compositor has not described yet).
- (NSColorSpace *) contentColorSpace {
    NSColorSpace *space = [_delegate respondsToSelector: @selector(colorSpace)]
                          ? [_delegate colorSpace] : nil;
    if (space == nil)
        space = _preferredColorSpace;
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
    if (space == NULL)
        return;
    NSDictionary *preferred = _surfaceFeedback != NULL
                              ? [color preferredInfoForFeedback: _surfaceFeedback] : nil;
    WaylandColorHDRMetadata metadata = [color hdrMetadataForColorInfo: preferred space: space];
    [color setColorSpace: space
         renderingIntent: WP_COLOR_RENDER_INTENT_PERCEPTUAL
              hdrMetadata: &metadata
                onSurface: _colorSurface];
}

// The compositor's preferred image description for this surface changed. Use it for content whose
// color space the application has not chosen, and pass its HDR metadata with the next description.
- (void) preferredColorInfoChanged {
    if (_invalidated)
        return;
    WaylandColorManager *color = [_display colorManager];
    NSDictionary *info = _surfaceFeedback != NULL
                         ? [color preferredInfoForFeedback: _surfaceFeedback] : nil;
    NSColorSpace *preferred = [NSScreen _colorSpaceFromDisplayColorInfo: info];
    [_preferredColorSpace release];
    _preferredColorSpace = [preferred retain];
    [self updateSurfaceColor];
    // The subwindows use the parent's preference when their own feedback has none.
    for (NSValue *value in _subwindows)
        [(WaylandSubWindow *) [value pointerValue] colorManagerAvailable];
    [_display flush];
}

- (BOOL) preferredSubwindowColorInfoChangedForFeedback: (struct wl_proxy *) feedback {
    for (NSValue *value in _subwindows) {
        WaylandSubWindow *child = (WaylandSubWindow *) [value pointerValue];
        if ([child preferredColorInfoChangedForFeedback: feedback])
            return YES;
    }
    return NO;
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
    if (_surface != NULL && _surfaceFeedback == NULL) {
        WaylandColorManager *color = [_display colorManager];
        _surfaceFeedback = [color newSurfaceFeedbackForSurface: _surface];
    }
    [self updateSurfaceColorIfNeeded];
    for (NSValue *value in _subwindows)
        [(WaylandSubWindow *) [value pointerValue] colorManagerAvailable];
}

- (void) renderGlobalsAvailable {
    if (_surface != NULL)
        [[_display renderManager] observeSurface: _surface];
}

// The window's opacity is the window system window's (alpha-modifier-v1 where the compositor has it).
- (void) updateAlphaModifier {
    double alpha = _delegate != nil ? (double) [_delegate alphaValue] : 1.0;
    [_cgsWindow setToplevelAlpha: alpha];
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

- (struct wl_proxy *) surfaceFeedback {
    return _surfaceFeedback;
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
    [color destroySurfaceFeedback: _surfaceFeedback];
    _colorSurface = _representationSurface = _surfaceFeedback = NULL;
    if (_idleInhibitor != NULL)
        sendRequest(_idleInhibitor, ZWP_IDLE_INHIBITOR_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _idleInhibitor = NULL;
    if (_shortcutsInhibitor != NULL)
        sendRequest(_shortcutsInhibitor, ZWP_KEYBOARD_SHORTCUTS_INHIBITOR_DESTROY,
                    WL_MARSHAL_FLAG_DESTROY);
    _shortcutsInhibitor = NULL;
    if (_contentType != NULL)
        sendRequest(_contentType, WP_CONTENT_TYPE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _contentType = NULL;
    _contentTypeValue = WP_CONTENT_TYPE_NONE;
    if (_toplevelSession != NULL)
        sendRequest(_toplevelSession, WP_TOPLEVEL_SESSION_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _toplevelSession = NULL;
    if (_dialog != NULL)
        sendRequest(_dialog, XDG_DIALOG_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _dialog = NULL;
    _dialogModal = NO;
    if (_fractionalScale) sendRequest(_fractionalScale, WP_FRACTIONAL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_viewport) sendRequest(_viewport, WP_VIEWPORT_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    // The surface is the window system window's: it is destroyed with that window, or when it makes another.
    [[_display renderManager] destroySurface: _surface];
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
    CGSToplevelAttributes attributes = {.frame = NSRectToCGRect(_frame), .unmanaged = NO, .translucent = YES};
    if ([_cgsWindow recreateToplevelWithAttributes: &attributes] != kCGSErrorSuccess)
        NSLog(@"Wayland backend: CoreGraphics cannot make a new surface for a window");
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

// The compositor activated the window, or it is the key window of a window that is never shown: it comes first in the
// order of the windows.
- (void) activatedInWindowSystem {
    [_cgsWindow orderToplevelAbove: nil];
}

- (BOOL) isOrderedIn {
    return _mapped || ((_fullyTransparent || _mapDeferred) && _shouldBeMapped && !_invalidated);
}

// A window that is ordered in but not mapped (fully transparent, or held back while the application cannot take the
// focus) is not given to the compositor, but counts as ordered in for the window order, which the window system window
// keeps (see -[CGSWindow setToplevelHeldBack:]).
- (void) syncHeldBack {
    [_cgsWindow setToplevelHeldBack: !_mapped && [self isOrderedIn]];
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

#pragma mark - Mapping

// Whether AppKit considers this window a pop-up (see -[NSWindow _windowPresentation]).
- (BOOL) wantsPopupRole {
    return [_delegate respondsToSelector: @selector(_windowPresentation)] &&
           [(NSWindow *) _delegate _windowPresentation] == DarlingWindowPresentationPopup;
}

- (void) ensureMapped {
    [self ensureMappedUnsynced];
    [self syncHeldBack];
}

- (void) ensureMappedUnsynced {
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

    BOOL layerRole = [self wantsLayerSurface];
    BOOL surfaceRenewed = [self prepareSurfaceForRole: layerRole ? WaylandSurfaceRoleLayer
                                                       : parent != nil ? WaylandSurfaceRolePopup
                                                                       : WaylandSurfaceRoleToplevel];
    [self ensureSurface];

    // What the window is, for the window system window that makes the role.
    CGSToplevelHints hints = {
        .kind = layerRole ? kCGSToplevelKindDock
                          : parent == nil ? kCGSToplevelKindNormal
                          : tooltip ? kCGSToplevelKindTooltip
                          : menu ? kCGSToplevelKindDropdownMenu : kCGSToplevelKindPopupMenu,
        .transientFor = parent != nil ? parent->_cgsWindow : nil,
    };
    [_cgsWindow setToplevelHints: &hints];
    [self syncCGFrame];
    _surfaceRole = layerRole ? WaylandSurfaceRoleLayer
                 : parent != nil ? WaylandSurfaceRolePopup : WaylandSurfaceRoleToplevel;
    _decorationForcedClient = forceClient;
    if (parent != nil) {
        _popupParent = [parent retain];
        // A pop-up window of the application ends when the application orders it out; the compositor dismissing it
        // with a click elsewhere would leave the application showing it, as it would for a tool tip.
        _popupGrabSerial = (tooltip || _genericPopup) ? 0 : [_display popupGrabSerialForParent: _popupParent];
        [(CGSWindowWayland *) _cgsWindow setToplevelPopupGrabSerial: _popupGrabSerial];
    }
    // The window system window makes the role and the window system's objects of it, then tells -toplevelEvent:
    // (kCGSToplevelEventWillShow) before it commits the surface for the first time.
    [_cgsWindow orderWindow: kCGSOrderIn relativeTo: nil];
    _surfaceCommitted = YES;
    _pendingWidth = _pendingHeight = 0;
    _pendingActivated = NO;
    _pendingFullscreen = NO;
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
    // The window system's window tells the compositor (KDE's appmenu protocol) while it is a toplevel and the compositor
    // has the protocol; both are ASCII: a unique bus name and an object path.
    [_cgsWindow setToplevelApplicationMenuServiceName: [_display applicationMenuServiceName]
                                           objectPath: [_display applicationMenuObjectPath]];
}

- (void) discardBuffer: (struct WaylandBuffer *) buffer {
    if (buffer->buffer != NULL) {
        [[_display renderManager] bufferDestroyed: buffer->buffer];
        sendRequest(buffer->buffer, WP_BUFFER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    }
    if (buffer->data != NULL)
        munmap(buffer->data, buffer->size);
    if (buffer->surface != NULL)
        CFRelease(buffer->surface);
    memset(buffer, 0, sizeof(*buffer));
}

- (void) destroyBuffers {
    for (int i = 0; i < 2; i++)
        [self discardBuffer: &_buffers[i]];
}

// Unmapping an xdg surface requires a new configure sequence before it can be
// shown again, so the role objects are destroyed and created again on show.
- (BOOL) isPopupWaitingForParent { return _popupWaitingForParent; }

- (void) unmap {
    [self unmapUnsynced];
    [self syncHeldBack];
}

- (void) unmapUnsynced {
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
    if (_popup != NULL) {
        _popup = NULL;
        [_popupParent release];
        _popupParent = nil;
        _popupGrabSerial = 0;
        _genericPopup = NO;
    }
    if (_plasmaSurface != NULL) {
        sendRequest(_plasmaSurface, WP_PLASMA_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _plasmaSurface = NULL;
    }
    // The window system window destroys the role and hides the surface's content. It keeps the wl_surface across
    // hide/show: EGL child surfaces keep their native-window identity, and the NULL buffer unmaps the entire subtree.
    [_cgsWindow orderWindow: kCGSOrderOut relativeTo: nil];
    _surfaceCommitted = YES;
    _toplevel = _xdgSurface = _layerSurface = NULL;
    [_surfaceOutputs removeAllObjects];
    [self destroyBuffers];

    _mapped = NO;
    [self updateIdleInhibitor];
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
    // The tracker survives hiding: _frame keeps the fullscreen size, so the size
    // from before fullscreen would be lost if the next map saved it again.
    _pendingFullscreen = _fullscreenRecheckPending = NO;
    _fullscreenReported = NO;
    [self updateShortcutsInhibitor];
    [self updateContentType];
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
    [self syncHeldBack];
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
    // The text input focus follows the keyboard focus: what the first responder takes is told before it arrives.
    [self updateInputMethodSpot];
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

// The window system window asks the compositor to minimize the window, and keeps the state xdg-shell does not tell, and
// asks for the activation that shows the window again (see -[CGSWindow miniaturizeToplevel]).
- (void) miniaturize {
    [_cgsWindow miniaturizeToplevel];
}

- (void) deminiaturize {
    [_cgsWindow deminiaturizeToplevel];
    [self ensureMapped];
}

// Whether the compositor advertised that it minimizes windows.
- (BOOL) compositorMinimizes {
    return [(CGSWindowWayland *) _cgsWindow compositorMinimizes];
}

- (BOOL) isMiniaturized {
    return [_cgsWindow toplevelIsMiniaturized];
}

// What xdg-shell offers of occlusion is the suspended state, sent by compositors that stop repainting a
// toplevel they do not show (version 6 of xdg_wm_base). A compositor that never sends it leaves the
// window seen whenever it is mapped.
- (BOOL) isOccluded {
    return _mapped && [_cgsWindow toplevelIsOccluded];
}

- (void) flashWindow {
}

#pragma mark - Properties

- (NSUInteger) styleMask {
    return _styleMask;
}

// Whether the window has a title bar (see -setTitlebarKind:).
- (BOOL) hasTitlebar {
    // A sheet is drawn over its window on macOS, but xdg-shell lets the compositor place every toplevel and
    // gives a client no way to put one at a position over its parent. A sheet left without a frame then
    // appears as a bare rectangle at a place of the compositor's choosing, which looks like a glitch. It is
    // presented as what the compositor can show well: a dialog related to its window (see
    // -updateLevelParent) with the compositor's frame.
    if ([_delegate respondsToSelector: @selector(isSheet)] && [(NSWindow *) _delegate isSheet])
        return YES;
    return _titlebarKind != kCGSToplevelTitlebarNone;
}

// A window that shows nothing of a title bar of its own (see NSWindow) leaves nothing for the
// platform to draw as a title bar: the application draws its own header. Such a window gets no
// frame, neither from the compositor nor from the client-side fallback.
- (BOOL) wantsChromeless {
    return _titlebarKind == kCGSToplevelTitlebarHidden;
}

// Whether this window should draw the client-side frame, given what the compositor asked for.
- (BOOL) wantsClientDecoration {
    return _toplevel != NULL && [self hasTitlebar] && ![self wantsChromeless] &&
            _pendingClientDecorated && !_pendingFullscreen;
}

// What the window shows of a title bar is the window system's window's to carry out: the compositor draws the frame, unless
// the frame is the client's own choice (a chromeless window declares client-side decorations explicitly because
// compositors differ on the default for a window that says nothing).
- (void) updateDecorationMode {
    if (_toplevel == NULL)
        return;
    int kind = [self hasTitlebar] ? (_titlebarKind == kCGSToplevelTitlebarHidden ? kCGSToplevelTitlebarHidden
                                                                                 : kCGSToplevelTitlebarStandard)
                                  : kCGSToplevelTitlebarNone;
    [_cgsWindow setToplevelPrefersClientDecoration: _decorationForcedClient];
    [_cgsWindow setToplevelTitlebarKind: kind];
}

- (void) setTitlebarKind: (int) kind {
    _titlebarKind = kind;
    [self updateDecorationsForStyleMask: _styleMask];
}

// Called when the style mask or the title bar kind of a window change, and when it is shown. On a mapped window
// the mode is updated and the client-side frame switched on or off right away, keeping the content size.
- (void) updateDecorationsForStyleMask: (NSUInteger) mask {
    _styleMask = mask;
    if (_toplevel == NULL)
        return;
    [self updateDecorationMode];
    [self updateClientDecorationLayout];
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
    if (wanted == [_cgsWindow toplevelFullscreenRequested])
        return;
    // The window system window asks the compositor, and holds the drawing back until the compositor has answered (see
    // -toplevelFullscreenSettling).
    [(CGSWindowWayland *) _cgsWindow setToplevelFullscreen: wanted onOutput: output force: NO];
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

    // A window of a raised level, and any window that is not an application window (a panel, a child window, a window that
    // cannot become main: see DarlingWindowPresentation.h), is related to the window it belongs to, which keeps it in front
    // of that window and out of the task bar. The window system window refuses a parent that would make the window its own
    // ancestor, and then the next candidate is tried.
    BOOL auxiliary = [_delegate respondsToSelector: @selector(_windowPresentation)] &&
                     [(NSWindow *) _delegate _windowPresentation] != DarlingWindowPresentationApplication;
    if (DarlingWindowRoleForLevel(_level) == DarlingWindowRoleTransient || auxiliary) {
        CGSWindow *current = [_cgsWindow toplevelParent];
        for (WaylandWindow *candidate in [_display levelParentCandidatesForWindow: self]) {
            if (candidate->_cgsWindow == current)
                return;
            if ([_cgsWindow setToplevelParent: candidate->_cgsWindow] == kCGSErrorSuccess)
                return;
        }
    }
    [_cgsWindow setToplevelParent: nil];
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
                  _display->_dialogManager != NULL && [_cgsWindow toplevelParent] != nil;
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
    BOOL inhibit = !_invalidated && _mapped && ![_cgsWindow toplevelIsOccluded] && !_fullyTransparent &&
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

// wp_content_type_v1 lets the compositor optimize for the kind of content a surface shows. The
// frameworks have no macOS API for this, so the backend derives it from the state it already knows:
// a fullscreen window is a game, a window visible while the process holds a display sleep assertion
// is showing video, and everything else says none.
- (void) updateContentType {
    if (_surface == NULL || _display->_contentTypeManager == NULL)
        return;
    uint32_t type = WP_CONTENT_TYPE_NONE;
    if (_fullscreenReported)
        type = WP_CONTENT_TYPE_GAME;
    else if (_mapped && ![_cgsWindow toplevelIsOccluded] && !_fullyTransparent && _CGSNativeConnectionDisplaySleepPrevented())
        type = WP_CONTENT_TYPE_VIDEO;
    if (_contentType == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _contentType = WaylandCreateObject(_display->_contentTypeManager,
                                           WP_CONTENT_TYPE_MANAGER_GET_SURFACE_CONTENT_TYPE,
                                           &wp_content_type_v1_interface, args, 0, nil);
        if (_contentType == NULL)
            return;
    }
    if (type == _contentTypeValue)
        return;
    union wl_argument value[1] = {{.u = type}};
    WaylandMarshal(_contentType, WP_CONTENT_TYPE_SET_CONTENT_TYPE, NULL, 0, value);
    _contentTypeValue = type;
    if (_mapped && _configured) {
        [self commitSurface];
        [_display flush];
    }
}

// The compositor's own shortcuts (switching workspaces, for instance) must not take keys away from a
// fullscreen game; the protocol needs both the surface and the seat.
- (void) updateShortcutsInhibitor {
    BOOL inhibit = !_invalidated && _mapped && _fullscreenReported && _surface != NULL &&
                   _display->_shortcutsInhibitManager != NULL && [_display seat] != NULL;
    if (inhibit && _shortcutsInhibitor == NULL) {
        union wl_argument args[3] = {{.o = NULL}, {.o = (struct wl_object *) _surface},
                                     {.o = (struct wl_object *) [_display seat]}};
        _shortcutsInhibitor = WaylandCreateObject(_display->_shortcutsInhibitManager,
                                                  ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_INHIBIT_SHORTCUTS,
                                                  &zwp_keyboard_shortcuts_inhibitor_v1_interface,
                                                  args, 0, nil);
    } else if (!inhibit && _shortcutsInhibitor != NULL) {
        sendRequest(_shortcutsInhibitor, ZWP_KEYBOARD_SHORTCUTS_INHIBITOR_DESTROY,
                    WL_MARSHAL_FLAG_DESTROY);
        _shortcutsInhibitor = NULL;
    }
}

- (void) updateTitle {
    [_cgsWindow setProperty: kCGSWindowTitle value: (CFTypeRef) _title];
    if (_toplevel == NULL)
        return;
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
    // A layer surface is as tall as its frame, which the window system window follows.
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
    [_cgsWindow setToplevelMinimumSize: CGSizeMake(min[0].i, min[1].i) maximumSize: CGSizeMake(max[0].i, max[1].i)];
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
            [self syncHeldBack];
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
    // A pop-up is placed again, a menu bar surface sized again.
    [_cgsWindow setToplevelFrame: NSRectToCGRect(_frame)];
    if (_popup != NULL && (moved || sized))
        [_display flush];
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

// Whether a point of the surface is on the client-side frame: the window system's window answers (see
// -updateClientDecorationLayout).
- (BOOL) isDecorationPoint: (CGPoint) point {
    return _clientDecorated && [_cgsWindow toplevelClientDecorationContainsPoint: point];
}

// The client-side frame AppKit draws (-drawDecorations) is hit-tested by the window system's window: the edges that
// resize, the title bar that moves, and the buttons. It is told where they are.
- (void) updateClientDecorationLayout {
    if (!_clientDecorated || _toplevel == NULL) {
        [_cgsWindow setToplevelClientDecorationLayout: NULL];
        return;
    }
    NSSize size = [self logicalSurfaceSize];
    CGRect none = CGRectNull;
    CGSToplevelDecorationLayout layout = {
        .border = WaylandBorder,
        .titleHeight = WaylandTitleHeight,
        .size = NSSizeToCGSize(size),
        .resizable = (_styleMask & NSWindowStyleMaskResizable) != 0,
        .closeButton = none,
        .miniaturizeButton = none,
        .zoomButton = none,
    };
    CGRect *buttons[] = {&layout.closeButton, &layout.miniaturizeButton, &layout.zoomButton};
    NSUInteger masks[] = {NSWindowStyleMaskClosable, NSWindowStyleMaskMiniaturizable, NSWindowStyleMaskResizable};
    for (int i = 0; i < 3; ++i)
        if (_styleMask & masks[i])
            *buttons[i] = CGRectMake(WaylandBorder + 4 + i * 20, WaylandBorder, 18, WaylandTitleHeight);
    [_cgsWindow setToplevelClientDecorationLayout: &layout];
}

// -[NSWindow performWindowDragWithEvent:]: a client cannot place a toplevel, so the compositor moves it, for the
// press that is held (xdg_toplevel.move with that press's serial). NO for a popup, or when no button is down.
- (BOOL) moveByWindowSystem {
    if (_toplevel == NULL)
        return NO;
    return [_cgsWindow beginToplevelMoveByWindowSystem] == kCGSErrorSuccess;
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
        [self updateClientDecorationLayout];
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

    WaylandRenderManager *render = [_display renderManager];
    for (int i = 0; i < 2; i++) {
        struct WaylandBuffer *buffer = &_buffers[i];
        // A dma-buf the compositor rejected cannot be attached again; rebuild it as shm.
        if (buffer->buffer != NULL && [render bufferCreationFailed: buffer->buffer])
            [self discardBuffer: buffer];
        if (buffer->busy) {
            // With explicit synchronization there is no wl_buffer.release event.
            if ([render releasePointSignalledForBuffer: buffer->buffer])
                buffer->busy = NO;
            else
                continue;
        }
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

    [self discardBuffer: reusable];

    int32_t stride = width * 4;
    size_t size = (size_t) stride * (size_t) height;

    // When the compositor advertised a format/modifier we can import, keep the pixels in an
    // IOSurface and let the host export its memory as a dma-buf. The same IOSurface backs every
    // frame in this slot, so GPU contents survive between commits and the CPU view below stays
    // coherent. Fall back to wl_shm whenever any step is unavailable.
    uint32_t drmFormat = 0;
    uint64_t modifier = 0;
    BOOL needsAlpha = format == WP_SHM_FORMAT_ARGB8888;
    // Onyx2D produces premultiplied 8-bit ARGB pixels. Request a wide format only when the
    // producer supplies half-float pixels; a plain window buffer must stay 8-bit.
    if ([render preferredFormat: &drmFormat modifier: &modifier forSurface: _surface
                      needsAlpha: needsAlpha
                     pixelFormat: WaylandRenderPixelFormat8Bit]) {
        // GPU drivers that import a linear dma-buf need its rows to start at a multiple of the
        // hardware pitch alignment (up to 256 bytes); a compositor that samples the buffer with
        // a GPU shows a window sheared when its row length is not so aligned. Pad the rows of
        // the surface: the compositor is given the real stride of the surface, and the pixel
        // copy below already honours it.
        size_t pitch = ((size_t) stride + 255) & ~(size_t) 255;
        size_t surfaceSize = pitch * (size_t) height;
        size_t pageSize = (size_t) getpagesize();
        size_t allocSize = (size_t) ((surfaceSize + pageSize - 1) / pageSize) * pageSize;
        if (allocSize >= surfaceSize) {
            NSMutableDictionary *properties = [NSMutableDictionary dictionary];
            [properties setObject: [NSNumber numberWithInt: width] forKey: (id) kIOSurfaceWidth];
            [properties setObject: [NSNumber numberWithInt: height] forKey: (id) kIOSurfaceHeight];
            [properties setObject: [NSNumber numberWithUnsignedInt: 4]
                           forKey: (id) kIOSurfaceBytesPerElement];
            [properties setObject: [NSNumber numberWithUnsignedLong: pitch]
                           forKey: (id) kIOSurfaceBytesPerRow];
            [properties setObject: [NSNumber numberWithUnsignedLongLong: allocSize]
                           forKey: (id) kIOSurfaceAllocSize];
            [properties setObject: [NSNumber numberWithUnsignedInt: 'BGRA']
                           forKey: (id) kIOSurfacePixelFormat];

            IOSurfaceRef surface = IOSurfaceCreate((CFDictionaryRef) properties);
            if (surface != NULL) {
                struct wl_proxy *proxy =
                        [render newBufferForIOSurface: surface
                                               format: drmFormat
                                             modifier: modifier
                                            forSurface: _surface
                                                width: width
                                               height: height
                                               offset: 0
                                               stride: (uint32_t) pitch];
                if (proxy != NULL) {
                    // create_immed has no dispatcher of its own. Without explicit synchronization
                    // the compositor still sends wl_buffer.release, which frees this slot.
                    WL.wl_proxy_add_dispatcher(proxy, WaylandDispatch,
                                               (void *) (uintptr_t) WaylandObjectBuffer, self);
                    reusable->buffer = proxy;
                    reusable->surface = surface;
                    reusable->width = width;
                    reusable->height = height;
                    reusable->format = format;
                    reusable->drmFormat = drmFormat;
                    reusable->modifier = modifier;
                    return reusable;
                }
                CFRelease(surface);
            }
        }
    }

    if (_display->_shm == NULL)
        return NULL;
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
        [_cgsWindow toplevelFullscreenSettling] || _context == nil)
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
    if (buffer == NULL) {
        // An explicitly synchronized buffer has no wl_buffer.release event. When its timeline has
        // not been signalled yet, ask for another frame callback instead of waiting forever for an
        // event the compositor will not send.
        BOOL waitingForExplicitRelease = NO;
        for (int i = 0; i < 2; i++)
            if (_buffers[i].busy && _buffers[i].surface != NULL)
                waitingForExplicitRelease = YES;
        if (waitingForExplicitRelease && _frameCallback == NULL) {
            union wl_argument args[1] = {{.o = NULL}};
            _frameCallback = WaylandCreateObject(_surface, WP_SURFACE_FRAME,
                                                 &wl_callback_interface, args,
                                                 WaylandObjectFrameCallback, self);
            [_display flush];
        }
        return;
    }

    // Both start with the top row. An IOSurface's stride can differ from the tight shm stride.
    if (buffer->surface != NULL) {
        if (IOSurfaceLock(buffer->surface, 0, NULL) != kIOSurfaceSuccess)
            return;
        uint8_t *destination = (uint8_t *) IOSurfaceGetBaseAddressOfPlane(buffer->surface, 0);
        size_t destinationStride = IOSurfaceGetBytesPerRowOfPlane(buffer->surface, 0);
        if (destination != NULL && destinationStride >= width * 4) {
            for (size_t row = 0; row < height; row++)
                memcpy(destination + row * destinationStride,
                       pixels + row * sourceStride, width * 4);
        }
        IOSurfaceUnlock(buffer->surface, 0, NULL);
    } else {
        for (size_t row = 0; row < height; row++)
            memcpy((uint8_t *) buffer->data + row * width * 4,
                   pixels + row * sourceStride, width * 4);
    }

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

    // fifo (and explicit sync for a dma-buf buffer, if one was attached) must be set before commit.
    [[_display renderManager] beginFrameForSurface: _surface buffer: buffer->buffer];
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
    case WaylandObjectToplevelSession:
        // The event only says the compositor used the state saved under this name; the state itself
        // arrives with the following configure, which is handled as an ordinary toplevel configure.
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

#pragma mark - Window system events

static void WaylandWindowToplevelEvent(CGSWindow *window, const CGSToplevelEvent *event, void *info) {
    [(WaylandWindow *) info toplevelEvent: event];
}

// What the window system window says of the window.
- (void) toplevelEvent: (const CGSToplevelEvent *) event {
    switch (event->kind) {
    case kCGSToplevelEventWillShow:
        [self roleCreated];
        break;
    case kCGSToplevelEventCloseRequested:
        [self closeRequested];
        break;
    case kCGSToplevelEventConfigured:
        [self configured: &event->configure];
        break;
    case kCGSToplevelEventDismissed:
        [self dismissed];
        break;
    case kCGSToplevelEventInputMethodPreedit:
    case kCGSToplevelEventInputMethodCommit:
    case kCGSToplevelEventInputMethodDeleteSurrounding:
        [_inputMethod handleToplevelEvent: event];
        break;
    case kCGSToplevelEventOcclusionChanged:
        // Whether the compositor still repaints the window: what depends on it follows.
        [_display performAfterDispatch: ^{
          if (self->_invalidated)
              return;
          [self updateIdleInhibitor];
          if ([self->_delegate respondsToSelector: @selector(platformWindowOcclusionChanged:)])
              [self->_delegate platformWindowOcclusionChanged: self];
        }];
        break;
    case kCGSToplevelEventMiniaturized:
        if (!_invalidated)
            [_delegate platformWindowMiniaturized: self];
        break;
    case kCGSToplevelEventDeminiaturized:
        // A window being invalidated (-dealloc does it) has no NSWindow to tell.
        if (!_invalidated)
            [_delegate platformWindowDeminiaturized: self];
        break;
    case kCGSToplevelEventParentLost:
        // The compositor dropped the relation with the parent: a dialog needs one.
        [self updateDialogForToplevel];
        break;
    case kCGSToplevelEventFullscreenSettled:
        // The compositor answered a request for fullscreen: the content can be drawn at the size it chose.
        [_display performAfterDispatch: ^{
          if (!self->_invalidated)
              [self presentIfPossible];
        }];
        break;
    default:
        break;
    }
}

// The window system window made the role, and is about to commit the surface for the first time: what goes to the
// compositor before that is told now.
- (void) roleCreated {
    CGSWindowWayland *window = (CGSWindowWayland *) _cgsWindow;
    _xdgSurface = [window xdgSurfaceProxy];
    _toplevel = [window toplevelProxy];
    _popup = [window popupProxy];
    _layerSurface = [window layerSurfaceProxy];

    if (_toplevel != NULL) {
        [self updateTitle];
        [self updateFullscreen];
        [self updateSizeLimits];
        [self updateLevelParent];
        [self updateDialogForToplevel];
        [self updateDecorationMode];
        [self updateApplicationMenu];
        [self updateTaskbarPresence];
        _toplevelIconSet = NO;
        [self updateToplevelIcon];
        // The session request has to precede the initial commit on the surface.
        [self joinSessionBeforeCommit];
    } else if (_popup != NULL && ([self isTooltip] || (_genericPopup && [_delegate ignoresMouseEvents]))) {
        // No grab, and an empty input region: the pointer keeps its focus on the parent while a tool tip is shown beside it.
        [_cgsWindow setToplevelIgnoresMouseEvents: YES];
    }
    // The multiplier is double-buffered, so it has to be set before the surface's first commit.
    [self updateAlphaModifier];
}

// The end of a configure sequence of the compositor: apply the toplevel state.
- (void) configured: (const CGSToplevelConfigure *) configure {
    if (_layerSurface != NULL) {
        // A zero size leaves the choice to the client.
        _pendingWidth = configure->width != 0 ? configure->width : (int32_t) ceil(_frame.size.width);
        _pendingHeight = configure->height != 0 ? configure->height : (int32_t) ceil(_frame.size.height);
        _pendingActivated = NO;
        _pendingMaximized = _pendingFullscreen = NO;
        [self scheduleConfigureApply];
        return;
    }
    _pendingWidth = configure->width;
    _pendingHeight = configure->height;
    _pendingActivated = configure->activated;
    _pendingMaximized = configure->maximized;
    _pendingFullscreen = configure->fullscreen;
    if (_popup != NULL) {
        _pendingPopupX = configure->popupX;
        _pendingPopupY = configure->popupY;
    }
    if (configure->decorationReported)
        _pendingClientDecorated = configure->clientDecorated;
    [self scheduleConfigureApply];
}

// The compositor took the window away: a pop-up it dismissed, or the menu bar whose output is gone.
- (void) dismissed {
    NSUInteger generation = _surfaceGeneration;
    if (_layerSurface != NULL) {
        // The bar is not a window the user closed, so it is only hidden.
        [_display performAfterDispatch: ^{
            if (!self->_mapped || self->_surfaceGeneration != generation)
                return;
            [self unmap];
            [self->_delegate orderOut: nil];
        }];
    } else if (_popup != NULL) {
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
}

// The window system window follows the frame of this one (a pop-up is placed relative to its parent's, a menu bar sized
// like its frame); this tells it of a frame the compositor changed.
- (void) syncCGFrame {
    [(CGSWindowWayland *) _cgsWindow noteToplevelFrame: NSRectToCGRect(_frame)];
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
    [self updateShortcutsInhibitor];
    [self updateContentType];

    BOOL sized = NO;
    BOOL moved = NO;
    if (_popupParent != nil) {
        NSRect parent = [_popupParent frame];
        NSPoint offset = [_popupParent contentOffset];
        NSPoint origin = NSMakePoint(parent.origin.x + _pendingPopupX - offset.x,
                NSMaxY(parent) - _pendingPopupY + offset.y - _pendingHeight);
        moved = !NSEqualPoints(_frame.origin, origin);
        _frame.origin = origin;
        [self syncCGFrame];
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
        [self syncCGFrame];
        sized = YES;
    }

    // A fullscreen window is the screen's frame; the compositor places it, a client has no position of its own.
    NSRect screenFrame;
    if (_pendingFullscreen && _popupParent == nil &&
        [_display fullscreenScreenFrameForSize: _frame.size entered: _surfaceOutputs frame: &screenFrame] &&
        !NSEqualPoints(_frame.origin, screenFrame.origin))
    {
        _frame.origin = screenFrame.origin;
        [self syncCGFrame];
        moved = YES;
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

    [(CGSWindowWayland *) _cgsWindow setToplevelContentOffset: NSPointToCGPoint([self contentOffset])];
    [self updateClientDecorationLayout];

    BOOL activationChanged = _pendingActivated != _activated;
    BOOL activated = _pendingActivated;
    _activated = activated;

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
    return _mapped && [_cgsWindow toplevelIsFullscreen];
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
