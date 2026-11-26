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

#import <AppKit/NSTextInputBackend.h>
#import <AppKit/NSTouch.h>
#import "../private-include/AppKit/NSTouchBackend.h"
#import "WaylandDisplay.h"
#import "../private-include/AppKit/NSEventTime.h"
#import "NSEvent_gesture.h"
#import "NSEvent_mouse.h"
#import "WaylandCursor.h"
#import "WaylandScale.h"
#import "WaylandPasteboard.h"
#import "WaylandDraggingManager.h"
#import "WaylandAppMenu.h"
#import "../private-include/AppKit/NSGlobalMenu+Private.h"
#import <OpenGL/CGLInternal.h>
#include <dlfcn.h>
#import "WaylandColor.h"
#import "WaylandLibrary.h"
#import "WaylandPointerLock.h"
#import "WaylandProtocol.h"
#import "WaylandWindow.h"
#import "WaylandAppMenu.h"
#import "WaylandToplevelIcon.h"
#import "../private-include/AppKit/NSGlobalMenu+Private.h"
#import "../DarlingWindowLevelPolicy.h"
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreFoundation/CFNotificationCenter.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#import "../NSWindow-Private.h"
#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSPopUpWindow.h>
#import <objc/message.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <unistd.h>
#include <limits.h>

// What a window needs of a wl_output: its scale and refresh rate, and the properties that
// take effect together at wl_output.done (version 2 and later). The displays an application sees
// (CoreGraphics' CGSConnectionWayland) describe the outputs themselves, from a connection of
// their own.
typedef struct { int32_t width, height, refresh, scale; } WaylandOutputState;

// A wl_output.
@interface WaylandOutput : NSObject {
@public
    struct wl_proxy *_proxy;
    uint32_t _globalName, _version;
    WaylandDisplay *_display;
    WaylandOutputState _current, _pending;
}
@end

@implementation WaylandOutput
@end

@interface WaylandDisplay (Private)
- (void) processPendingEvents;
- (void) scheduleOutputsDidChange;
- (void) outputsDidChange;
- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
              object: (id) object
           arguments: (union wl_argument *) args;
@end

int WaylandDispatch(const void *kind, void *proxy, uint32_t opcode,
                    const struct wl_message *message, union wl_argument *args)
{
    id object = (id) WL.wl_proxy_get_user_data(proxy);
    WaylandObjectKind objectKind = (WaylandObjectKind) (uintptr_t) kind;

    // An exception can't unwind through libwayland's native frames.
    @autoreleasepool {
        @try {
            if (objectKind >= WaylandColorObjectManager &&
                objectKind <= WaylandColorObjectLast) {
                [(WaylandColorManager *) object handleEvent: opcode
                                                       kind: (WaylandColorObjectKind) objectKind
                                                      proxy: (struct wl_proxy *) proxy
                                                  arguments: args];
                return 0;
            }
            switch (objectKind) {
            case WaylandObjectSurface:
            case WaylandObjectXdgSurface:
            case WaylandObjectToplevel:
            case WaylandObjectPopup:
            case WaylandObjectDecoration:
            case WaylandObjectFrameCallback:
            case WaylandObjectBuffer:
            case WaylandObjectLayerSurface:
            case WaylandObjectToplevelSession:
                [(WaylandWindow *) object handleEvent: opcode
                                                 kind: objectKind
                                                proxy: proxy
                                            arguments: args];
                break;
            case WaylandObjectDataDevice:
            case WaylandObjectDataOffer:
            case WaylandObjectDataSource:
                [(WaylandPasteboard *) object handleEvent: opcode kind: objectKind
                                                     proxy: proxy arguments: args];
                break;
            case WaylandObjectIconManager:
                [(WaylandToplevelIcons *) object handleEvent: opcode arguments: args];
                break;
            case WaylandObjectFractionalScale:
                if (opcode == WP_FRACTIONAL_EV_PREFERRED && args[0].u != 0)
                    [(id<WaylandFractionalScaleOwner>)object preferredScaleChanged: args[0].u];
                break;
            case WaylandObjectOutput:
                [((WaylandOutput *) object)->_display handleEvent: opcode
                                                             kind: objectKind
                                                            proxy: proxy
                                                           object: object
                                                        arguments: args];
                break;
            default:
                [(WaylandDisplay *) object handleEvent: opcode
                                                  kind: objectKind
                                                 proxy: proxy
                                                object: object
                                             arguments: args];
                break;
            }
        } @catch (id exception) {
            NSLog(@"Wayland backend: exception while handling %s (object kind %d)",
                  message->name, (int) objectKind);
            NSLog(@"%@", exception);
            if (NSApp != nil && [exception isKindOfClass: [NSException class]])
                // -reportException: can be app code: run it outside libwayland.
                [(WaylandDisplay *) [NSDisplay currentDisplay]
                        performAfterDispatch: ^{
                          [NSApp reportException: exception];
                        }];
        } @catch (...) {
            NSLog(@"Wayland backend: non-Objective-C exception while handling %s",
                  message->name);
        }
    }
    return 0;
}

struct wl_proxy *WaylandCreateObject(struct wl_proxy *proxy, uint32_t opcode,
                                     const struct wl_interface *interface,
                                     union wl_argument *args,
                                     WaylandObjectKind kind, id object)
{
    struct wl_proxy *created = WaylandMarshal(proxy, opcode, interface, 0, args);
    if (created == NULL) {
        NSLog(@"Wayland backend: cannot create a %s", interface->name);
        exit(1);
    }
    if (kind != 0)
        WL.wl_proxy_add_dispatcher(created, WaylandDispatch,
                                   (void *) (uintptr_t) kind, object);
    return created;
}

@implementation WaylandDisplay

- (instancetype) init {
    // WaylandBackendSelected() is shared with CoreGraphics' Wayland backend (see
    // WaylandLibrary.h): the two frameworks pick a display server independently, and
    // they must not disagree.
    if (!WaylandBackendSelected()) {
        [self release];
        return nil;
    }

    if (!WaylandLibraryLoad() || !WaylandCheckOpcodes()) {
        NSLog(@"Wayland backend: unavailable, trying the next backend");
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;

    _outputs = [NSMutableArray new];
    _color = [[WaylandColorManager alloc] initWithDispatcher: WaylandDispatch owner: self];
    _afterDispatch = [NSMutableArray new];
    _windows = CFArrayCreateMutable(NULL, 0, NULL);

    // The process has one connection to the compositor and CoreGraphics owns it: it reads its socket and
    // dispatches the events of every object on it, this display's included, then tells the observer
    // registered at the end of this method.
    if (_CGSNativeConnectionKind() != CGSNativeConnectionKindWayland) {
        [self release];
        return nil;
    }
    _wlDisplay = (struct wl_display *) _CGSNativeConnectionDisplay();
    if (_wlDisplay == NULL) {
        NSLog(@"Wayland backend: no connection to the compositor, trying the next backend");
        [self release];
        return nil;
    }

    union wl_argument args[1] = {{.o = NULL}};
    _registry = WaylandCreateObject((struct wl_proxy *) _wlDisplay,
                                    WP_DISPLAY_GET_REGISTRY,
                                    &wl_registry_interface, args,
                                    WaylandObjectRegistry, self);

    // The first roundtrip delivers the globals; the second one the initial
    // events of the objects bound meanwhile (output modes, seat capabilities).
    if (WL.wl_display_roundtrip(_wlDisplay) < 0 ||
        WL.wl_display_roundtrip(_wlDisplay) < 0)
    {
        NSLog(@"Wayland backend: the compositor connection failed during setup "
              @"(error %d), trying the next backend",
              WL.wl_display_get_error(_wlDisplay));
        [self release];
        return nil;
    }
    if (_compositor == NULL || _shm == NULL || _wmBase == NULL) {
        NSLog(@"Wayland backend: the compositor lacks%s%s%s, trying the next "
              @"backend",
              _compositor ? "" : " wl_compositor", _shm ? "" : " wl_shm",
              _wmBase ? "" : " xdg_wm_base");
        [self release];
        return nil;
    }

    // An additive CGL entry point selects Wayland explicitly, without changing
    // EGL_PLATFORM process-wide or relying on Mesa's default platform (X11).
    // Older runtimes keep their CPU backend and report the missing capability.
    CGLError (*registerPlatform)(void *, unsigned int) =
        dlsym(RTLD_DEFAULT, "CGLRegisterNativeDisplayForPlatform");
    _eglAvailable = WL.hasEGL && _subcompositor && registerPlatform &&
        registerPlatform(_wlDisplay, 0x31D8 /* EGL_PLATFORM_WAYLAND_KHR */) == kCGLNoError;
    if (!_eglAvailable)
        NSLog(@"Wayland backend: EGL subwindows unavailable; CPU drawing remains enabled");

    _generalPasteboard = [[WaylandPasteboard alloc] initWithName: NSGeneralPboard display: self
                                                      manager: _dataDeviceManager seat: _seat];

    if (WL.hasCursor) {
        const char *sizeString = getenv("XCURSOR_SIZE");
        long parsed = sizeString ? strtol(sizeString, NULL, 10) : 24;
        int size = parsed > 0 && parsed <= INT_MAX ? (int)parsed : 24;
        _cursorTheme = WL.wl_cursor_theme_load(getenv("XCURSOR_THEME"),
                                               size > 0 ? size : 24,
                                               (struct wl_shm *) _shm);
        _cursorThemeScale120 = 120;
        if (_cursorTheme == NULL) {
            NSLog(@"Wayland backend: no cursor theme, the compositor's cursor "
                  @"stays");
        }
    }
    // Image cursors only need wl_shm, even without libwayland-cursor or a theme.
    args[0].o = NULL;
    _cursorSurface = WaylandCreateObject(_compositor, WP_COMPOSITOR_CREATE_SURFACE,
                                        &wl_surface_interface, args, 0, nil);

    _cursorFractionalScale = [self newFractionalScaleForSurface: _cursorSurface owner: (id)self];

    // Windows ordered in while the application was not active are mapped once it is.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationBecameActive:)
                                                 name: NSApplicationDidBecomeActiveNotification
                                               object: nil];

    [self runAfterDispatchBlocks];
    [self flush];

    // The general pasteboard and the compositor's clipboard show the same contents.
    NSPasteboardRegisterHostClipboard(_generalPasteboard);

    _setupDone = YES;
    _CGSSetNativeConnectionObserver(self);
    return self;
}

- (void) dealloc {
    [_appMenu release];
    [_draggingManager invalidate];
    [_draggingManager release];
    [self consumeDragPress];
    [_generalPasteboard invalidate];
    [_generalPasteboard release];

    _CGSSetNativeConnectionObserver(nil);
    [self cancelActivationRequest];

    if (_cursorTheme != NULL)
        WL.wl_cursor_theme_destroy(_cursorTheme);
    [_appMenu release];
    _appMenu = nil;
    [_toplevelIcons release];
    _toplevelIcons = nil;
    if (_wlDisplay != NULL) {
        // wl_display_disconnect() doesn't free proxies.
        [(WaylandColorManager *) _color shutdown];
        // Destroying the session preserves the compositor's state for the next launch. The windows
        // have already released their toplevel session objects before this display is deallocated.
        if (_session != NULL)
            WaylandMarshal(_session, WP_SESSION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        if (_sessionManager != NULL)
            WaylandMarshal(_sessionManager, WP_SESSION_MANAGER_DESTROY,
                           NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        struct wl_proxy *proxies[] = {_imageCursorBuffer, _cursorFractionalScale, _cursorSurface,
                                      _cursorShapeDevice, _cursorShapeManager, _dialogManager,
                                      _textInput, _textInputManager,
                                      _seat, _decorationManager, _dataDeviceManager, _wmBase,
                                      _shm, _viewporter, _fractionalScaleManager, _activationToken, _activation, _appMenuManager, _subcompositor, _compositor, _registry};
        for (size_t i = 0; i < sizeof(proxies) / sizeof(proxies[0]); i++)
            if (proxies[i] != NULL)
                WL.wl_proxy_destroy(proxies[i]);
        for (WaylandOutput *output in _outputs)
            WL.wl_proxy_destroy(output->_proxy);
        // The connection is CoreGraphics'; it stays open.
    }

    [_cursor release];
    [_inputEvent release];
    [_color release];
    [_sessionIdentifier release];
    [_outputs release];
    [_afterDispatch release];
    if (_windows != NULL)
        CFRelease(_windows);

    [super dealloc];
}

#pragma mark - Connection and event loop

- (void) flush {
    if (_wlDisplay != NULL)
        WL.wl_display_flush(_wlDisplay);
}

- (WaylandColorManager *) colorManager {
    return _color;
}

#pragma mark - Window-system session

- (void) beginWindowSessionWithReason: (NSUInteger) reason identifier: (NSString *) identifier {
    if (_sessionRequested)
        return;
    _sessionRequested = YES;
    _sessionReason = reason;
    [_sessionIdentifier release];
    _sessionIdentifier = [identifier copy];
    [self startSessionIfPossible];
}

- (NSString *) windowSessionIdentifier {
    return _sessionIdentifier;
}

// The manager and AppKit's reason can arrive in either order: the registry is read during -init,
// while the reason comes from the saved state later in launching.
- (void) startSessionIfPossible {
    if (!_sessionRequested || _sessionManager == NULL || _session != NULL)
        return;
    uint32_t reason = (uint32_t) _sessionReason;
    if (reason < WP_SESSION_REASON_LAUNCH || reason > WP_SESSION_REASON_SESSION_RESTORE)
        reason = WP_SESSION_REASON_LAUNCH;
    union wl_argument args[3] = {
        {.o = NULL}, {.u = reason}, {.s = [_sessionIdentifier length] > 0 ? [_sessionIdentifier UTF8String] : NULL},
    };
    _session = WaylandCreateObject(_sessionManager, WP_SESSION_MANAGER_GET_SESSION,
                                   &xdg_session_v1_interface, args,
                                   WaylandObjectSession, self);
    if (_session == NULL)
        return;
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) sessionManagerAvailable];
}

- (void) joinSessionForToplevel: (WaylandWindow *) window {
    if (_session == NULL || window == nil || [window toplevelSession] != NULL)
        return;
    NSString *name = [window ensureSessionToplevelName];
    const char *utf8 = [name UTF8String];
    if (utf8 == NULL)
        return;
    // A session state can only be restored before the first commit. If AppKit set the name
    // after the window was already mapped, the same name is still used to store new state.
    BOOL restoring = [window isRestoringSessionToplevel] && ![window hasCommittedSurface];
    union wl_argument args[3] = {
        {.o = NULL}, {.o = (struct wl_object *) [window toplevel]}, {.s = utf8},
    };
    struct wl_proxy *proxy =
            WaylandCreateObject(_session,
                                restoring ? WP_SESSION_RESTORE_TOPLEVEL : WP_SESSION_ADD_TOPLEVEL,
                                &xdg_toplevel_session_v1_interface, args,
                                WaylandObjectToplevelSession, window);
    if (proxy != NULL)
        [window setToplevelSession: proxy];
}

- (void) sessionEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    if (opcode == WP_SESSION_EV_CREATED) {
        NSString *identifier = args[0].s != NULL ? [NSString stringWithUTF8String: args[0].s] : nil;
        [identifier retain];
        [_sessionIdentifier release];
        _sessionIdentifier = identifier;
        if (NSApp != nil)
            [NSApp _writeWindowSessionMarkerWithIdentifier: identifier];
    } else if (opcode == WP_SESSION_EV_REPLACED) {
        // Another client took the session over: all its objects are inert now.
        for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
            WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
            struct wl_proxy *proxy = [window toplevelSession];
            if (proxy != NULL) {
                WaylandMarshal(proxy, WP_TOPLEVEL_SESSION_DESTROY, NULL,
                               WL_MARSHAL_FLAG_DESTROY, NULL);
                [window setToplevelSession: NULL];
            }
        }
        if (_session != NULL)
            WaylandMarshal(_session, WP_SESSION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _session = NULL;
        [_sessionIdentifier release];
        _sessionIdentifier = nil;
        if (NSApp != nil)
            [NSApp _removeWindowSessionMarker];
    }
}

// The windows carry the application icon (see WaylandToplevelIcon.h): when the application sets another
// one, the windows already shown are given it too.
- (void) updateWindowIcons {
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) updateToplevelIcon];
}

- (void) dialogManagerAvailable {
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) dialogManagerAvailable];
}

- (void) applicationIconImageChanged {
    [super applicationIconImageChanged];
    [_toplevelIcons applicationIconChanged];
}

- (void) performAfterDispatch: (void (^)(void)) block {
    [_afterDispatch addObject: [[block copy] autorelease]];
}

- (void) performAfterRunLoopPass: (void (^)(void)) block {
    [self performAfterDispatch: block];
    [self scheduleAfterDispatchRun];
}

// Runs the blocks that were queued before this pass. Blocks queued by those
// blocks wait for the next run loop iteration, so that work which keeps
// queueing more work (a view whose frame alternates, say) cannot keep the main
// thread here and starve the run loop, as events and timers are only serviced
// between iterations.
- (void) runAfterDispatchBlocks {
    if ([_afterDispatch count] == 0)
        return;
    NSArray *blocks = [_afterDispatch copy];
    [_afterDispatch removeAllObjects];
    @try {
        for (void (^block)(void) in blocks)
            block();
    } @finally {
        [blocks release];
        if ([_afterDispatch count] > 0)
            [self scheduleAfterDispatchRun];
    }
}

// Wakes the main run loop to run the blocks that were queued during a pass.
- (void) scheduleAfterDispatchRun {
    if (_afterDispatchRunQueued)
        return;
    _afterDispatchRunQueued = YES;
    [self retain];
    CFRunLoopRef loop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(loop, kCFRunLoopCommonModes, ^{
        _afterDispatchRunQueued = NO;
        [self runAfterDispatchBlocks];
        if (_wlDisplay != NULL)
            WL.wl_display_flush(_wlDisplay);
        [self release];
    });
    CFRunLoopWakeUp(loop);
}

// Reads and dispatches what the compositor has sent, now. CoreGraphics does it for the whole connection
// and calls back -nativeConnectionDidProcessEvents.
- (void) processPendingEvents {
    _CGSProcessNativeConnectionEvents();
}

// Every listener on the connection has run: this display's queued work follows.
- (void) nativeConnectionDidProcessEvents {
    [self runAfterDispatchBlocks];
    [self flush];
}

// CoreGraphics read the new layout of the outputs and reported it. The windows learn of it once, with the
// outputs of this display as they are after the same pass (see -publishOutput:).
- (void) nativeConnectionDisplayLayoutChanged {
    [self outputsDidChange];
}

// CoreGraphics has rebuilt the screens with an output's new color description.
- (void) nativeConnectionDisplayColorSpaceChanged {
    // Windows without an explicit color space follow the screen, so their surface descriptions
    // have to be sent again.
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) colorManagerAvailable];
    [self flush];
    [[NSNotificationQueue defaultQueue]
            enqueueNotification: [NSNotification notificationWithName: NSScreenColorSpaceDidChangeNotification
                                                               object: NSApp]
                   postingStyle: NSPostASAP
                   coalesceMask: NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender
                       forModes: nil];
}

// A color manager global went away: its surface descriptions are inert, so let the windows
// refresh theirs and let the screens drop the compositor's color space.
- (void) waylandColorManagerDidLoseGlobal: (WaylandColorManager *) manager {
    (void) manager;
    [self nativeConnectionDisplayColorSpaceChanged];
}

// Another process asked for the activation of this one's windows (see _CGSActivateProcess).
- (void) nativeConnectionActivationRequested {
    [self requestActivation];
}

// Sends the requests made since the last wait, and handles the events libwayland has already
// read (which leave the connection's descriptor quiet)
- (void) willWaitForEvents {
    [self processPendingEvents];
}

#pragma mark - Globals

- (struct wl_proxy *) bindGlobal: (uint32_t) name
                       interface: (const struct wl_interface *) interface
                         version: (uint32_t) version
                            kind: (WaylandObjectKind) kind
                          object: (id) object
{
    union wl_argument args[4];
    args[0].u = name;
    args[1].s = interface->name;
    args[2].u = version;
    args[3].o = NULL;

    struct wl_proxy *proxy = WL.wl_proxy_marshal_array_flags(
            _registry, WP_REGISTRY_BIND, interface, version, 0, args);
    if (proxy == NULL) {
        NSLog(@"Wayland backend: cannot bind %s", interface->name);
        exit(1);
    }
    if (kind != 0)
        WL.wl_proxy_add_dispatcher(proxy, WaylandDispatch,
                                   (void *) (uintptr_t) kind, object);
    return proxy;
}

- (void) registryGlobal: (uint32_t) name
              interface: (const char *) interface
                version: (uint32_t) version
{
    if (strcmp(interface, "xdg_session_manager_v1") == 0 && _sessionManager == NULL) {
        _sessionManagerName = name;
        _sessionManager = [self bindGlobal: name
                                 interface: &xdg_session_manager_v1_interface
                                   version: 1
                                      kind: WaylandObjectSessionManager
                                    object: self];
        [self startSessionIfPossible];
    } else if (strcmp(interface, "xdg_wm_dialog_v1") == 0 && _dialogManager == NULL) {
        _dialogManagerName = name;
        _dialogManager = [self bindGlobal: name
                                interface: &xdg_wm_dialog_v1_interface
                                  version: 1
                                     kind: 0
                                   object: nil];
        [self dialogManagerAvailable];
    } else if (strcmp(interface, "wp_color_manager_v1") == 0 &&
        ((WaylandColorManager *) _color)->_colorManager == NULL) {
        uint32_t managerVersion = MIN(version, (uint32_t) wp_color_manager_v1_interface.version);
        struct wl_proxy *proxy = [self bindGlobal: name
                                         interface: &wp_color_manager_v1_interface
                                          version: managerVersion
                                             kind: (WaylandObjectKind) WaylandColorObjectManager
                                           object: _color];
        [(WaylandColorManager *) _color bindColorManager: proxy
                                                 version: managerVersion name: name];
        for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
            [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) colorManagerAvailable];
    } else if (strcmp(interface, "wp_color_representation_manager_v1") == 0 &&
               ((WaylandColorManager *) _color)->_representationManager == NULL) {
        struct wl_proxy *proxy = [self bindGlobal: name
                                         interface: &wp_color_representation_manager_v1_interface
                                          version: 1
                                             kind: (WaylandObjectKind) WaylandColorObjectRepresentationManager
                                           object: _color];
        [(WaylandColorManager *) _color bindRepresentationManager: proxy version: 1 name: name];
        for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
            [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) colorManagerAvailable];
    } else if (strcmp(interface, "wl_compositor") == 0 && _compositor == NULL) {
        // Version 4 has wl_surface.damage_buffer.
        _compositorVersion = MIN(version, 4);
        _compositor = [self bindGlobal: name
                             interface: &wl_compositor_interface
                               version: _compositorVersion
                                  kind: 0
                                object: nil];
    } else if (strcmp(interface, "wp_viewporter") == 0 && _viewporter == NULL) {
        _viewporterName = name;
        _viewporter = [self bindGlobal: name interface: &wp_viewporter_interface
                               version: 1 kind: 0 object: nil];
    } else if (strcmp(interface, "wp_fractional_scale_manager_v1") == 0 && _fractionalScaleManager == NULL) {
        _fractionalScaleManagerName = name;
        _fractionalScaleManager = [self bindGlobal: name interface: &wp_fractional_scale_manager_v1_interface
                                          version: 1 kind: 0 object: nil];
    } else if (strcmp(interface, "xdg_activation_v1") == 0 && _activation == NULL) {
        _activationName = name;
        _activation = [self bindGlobal: name interface: &xdg_activation_v1_interface
                               version: 1 kind: 0 object: nil];
    } else if (strcmp(interface, "org_kde_kwin_appmenu_manager") == 0 && _appMenuManager == NULL) {
        // Version 2 adds the manager's release request.
        _appMenuManagerName = name;
        _appMenuManagerVersion = MIN(version, 2);
        _appMenuManager = [self bindGlobal: name interface: &org_kde_kwin_appmenu_manager_interface
                                   version: _appMenuManagerVersion kind: 0 object: nil];
    } else if (strcmp(interface, "xdg_toplevel_icon_manager_v1") == 0 && _toplevelIcons == nil) {
        _toplevelIcons = [[WaylandToplevelIcons alloc] initWithDisplay: self];
        [_toplevelIcons setManager: [self bindGlobal: name interface: &xdg_toplevel_icon_manager_v1_interface
                                             version: 1 kind: WaylandObjectIconManager object: _toplevelIcons]
                              name: name];
    } else if (strcmp(interface, "org_kde_plasma_shell") == 0 && _plasmaShell == NULL) {
        // Version 2 adds set_skip_taskbar, version 5 set_skip_switcher.
        _plasmaShellName = name;
        _plasmaShellVersion = MIN(version, 5);
        _plasmaShell = [self bindGlobal: name interface: &org_kde_plasma_shell_interface
                                version: _plasmaShellVersion kind: 0 object: nil];
    } else if (strcmp(interface, "wl_subcompositor") == 0 && _subcompositor == NULL) {
        _subcompositor = [self bindGlobal: name interface: &wl_subcompositor_interface
                                  version: 1 kind: 0 object: nil];
    } else if (strcmp(interface, "wl_data_device_manager") == 0 && _dataDeviceManager == NULL) {
        _dataDeviceManager = [self bindGlobal: name interface: &wl_data_device_manager_interface
                                    version: MIN(version, 3) kind: 0 object: nil];
    } else if (strcmp(interface, "wl_shm") == 0 && _shm == NULL) {
        _shm = [self bindGlobal: name
                      interface: &wl_shm_interface
                        version: 1
                           kind: 0
                         object: nil];
    } else if (strcmp(interface, "xdg_wm_base") == 0 && _wmBase == NULL) {
        _wmBase = [self bindGlobal: name
                         interface: &xdg_wm_base_interface
                           version: MIN(version, 6)
                              kind: WaylandObjectWmBase
                            object: self];
    } else if (strcmp(interface, "zxdg_decoration_manager_v1") == 0 &&
               _decorationManager == NULL)
    {
        _decorationManager =
                [self bindGlobal: name
                       interface: &zxdg_decoration_manager_v1_interface
                         version: 1
                            kind: 0
                          object: nil];
    } else if (strcmp(interface, "zwp_text_input_manager_v3") == 0 && _textInputManager == NULL) {
        _textInputManagerName = name;
        _textInputManager = [self bindGlobal: name interface: &zwp_text_input_manager_v3_interface
                                     version: 1 kind: 0 object: nil];
        [self attachTextInput];
    } else if (strcmp(interface, "wp_cursor_shape_manager_v1") == 0 && _cursorShapeManager == NULL) {
        _cursorShapeManagerName = name;
        _cursorShapeManager = [self bindGlobal: name
                                     interface: &wp_cursor_shape_manager_v1_interface
                                      version: MIN(version, (uint32_t) wp_cursor_shape_manager_v1_interface.version)
                                         kind: 0
                                       object: nil];
        [self updateCursorShapeDevice];
    } else if (strcmp(interface, "wl_seat") == 0 && _seat == NULL) {
        // Version 4 adds wl_keyboard.repeat_info, 5 wl_pointer.frame.
        _seat = [self bindGlobal: name
                       interface: &wl_seat_interface
                         version: MIN(version, 5)
                            kind: WaylandObjectSeat
                          object: self];
        [self attachTextInput];
    } else if (strcmp(interface, "zwlr_layer_shell_v1") == 0 && _layerShell == NULL) {
        _layerShellName = name;
        // Version 4 adds the on-demand keyboard interactivity the bar asks for.
        _layerShell = [self bindGlobal: name interface: &zwlr_layer_shell_v1_interface
                               version: MIN(version, 4) kind: 0 object: nil];
    } else if (strcmp(interface, "wl_output") == 0) {
        WaylandOutput *output = [[WaylandOutput new] autorelease];
        output->_globalName = name;
        output->_display = self;
        output->_current.scale = output->_pending.scale = 1;
        // Version 2 has scale and done, version 4 the name and the description.
        output->_version = MIN(version, MIN(4u, wl_output_interface.version));
        // Version 2 has scale and done.
        output->_proxy = [self bindGlobal: name
                                interface: &wl_output_interface
                                  version: output->_version
                                     kind: WaylandObjectOutput
                                   object: output];
        if (output->_proxy != NULL) {
            [_outputs addObject: output];
            [(WaylandColorManager *) _color observeOutput: output->_proxy];
        }
    }
}

- (struct wl_proxy *) newFractionalScaleForSurface: (struct wl_proxy *) surface owner: (id<WaylandFractionalScaleOwner>) owner {
    if (!_fractionalScaleManager || !_viewporter || !surface) return NULL;
    union wl_argument args[] = {{.o = NULL}, {.o = (struct wl_object *)surface}};
    return WaylandCreateObject(_fractionalScaleManager, WP_FRACTIONAL_MANAGER_GET_SCALE,
        &wp_fractional_scale_v1_interface, args, WaylandObjectFractionalScale, owner);
}

- (void) registryGlobalRemoved: (uint32_t) name {
    [(WaylandColorManager *) _color globalRemoved: name];
    if (_sessionManager != NULL && name == _sessionManagerName) {
        // The manager global is gone; an existing session keeps working (see the protocol's
        // manager destructor), so only the factory is dropped here.
        WaylandMarshal(_sessionManager, WP_SESSION_MANAGER_DESTROY,
                       NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _sessionManager = NULL;
        _sessionManagerName = 0;
        return;
    }
    if (_dialogManager != NULL && name == _dialogManagerName) {
        // xdg_dialog_v1 objects created from this factory survive its removal.
        WaylandMarshal(_dialogManager, XDG_WM_DIALOG_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
        _dialogManager = NULL;
        _dialogManagerName = 0;
        return;
    }
    if (_cursorShapeManager != NULL && name == _cursorShapeManagerName) {
        // The device becomes inert with the manager; the compositor keeps the last shape that was set.
        [self updateCursorShapeDevice];
        WaylandMarshal(_cursorShapeManager, WP_CURSOR_SHAPE_MANAGER_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
        _cursorShapeManager = NULL;
        _cursorShapeManagerName = 0;
        return;
    }
    if (_textInputManager && name == _textInputManagerName) {
        [self detachTextInput];
        WaylandMarshal(_textInputManager, WP_TEXT_INPUT_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _textInputManager = NULL; _textInputManagerName = 0;
        return;
    }
    if (_fractionalScaleManager && name == _fractionalScaleManagerName) {
        WaylandMarshal(_fractionalScaleManager, WP_FRACTIONAL_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _fractionalScaleManager = NULL; _fractionalScaleManagerName = 0;
        return; // Existing surface preferences survive factory removal.
    }
    if (_appMenuManager && name == _appMenuManagerName) {
        struct wl_proxy *manager = _appMenuManager;
        _appMenuManager = NULL; _appMenuManagerName = 0;
        // The windows release their appmenu objects while the manager is gone.
        for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
            [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) updateApplicationMenu];
        if (_appMenuManagerVersion >= 2)
            WaylandMarshal(manager, WP_APPMENU_MANAGER_RELEASE, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        else
            WL.wl_proxy_destroy(manager);
        return;
    }
    if (_toplevelIcons && name == [_toplevelIcons name]) {
        // The windows keep the icons they were given.
        [_toplevelIcons managerRemoved];
        [_toplevelIcons release];
        _toplevelIcons = nil;
        return;
    }
    if (_plasmaShell && name == _plasmaShellName) {
        // The windows' plasma surfaces stay valid on the compositor's side; they are destroyed when
        // their windows unmap.
        WL.wl_proxy_destroy(_plasmaShell);
        _plasmaShell = NULL; _plasmaShellName = 0;
        return;
    }
    if (_activation && name == _activationName) {
        [self cancelActivationRequest];
        WaylandMarshal(_activation, WP_ACTIVATION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _activation = NULL; _activationName = 0;
        return;
    }
    if (_viewporter && name == _viewporterName) {
        WaylandMarshal(_viewporter, WP_VIEWPORTER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _viewporter = NULL; _viewporterName = 0;
        return; // Existing viewport objects remain usable.
    }
    if (_layerShell && name == _layerShellName) {
        // Existing layer surfaces stay usable until the compositor closes them.
        _layerShell = NULL;
        _layerShellName = 0;
        return;
    }
    for (WaylandOutput *output in _outputs) {
        if (output->_globalName == name) {
            for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
                [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) outputRemoved: output->_proxy];
            [_draggingManager outputRemoved: output->_proxy];
            WL.wl_proxy_destroy(output->_proxy);
            [_outputs removeObject: output];
            [self scheduleOutputsDidChange];
            break;
        }
    }
}

- (int32_t) scaleForOutput: (struct wl_proxy *) proxy {
    for (WaylandOutput *output in _outputs)
        if (output->_proxy == proxy)
            return output->_current.scale;
    return 1;
}

- (uint32_t) refreshForOutput: (struct wl_proxy *) proxy {
    for (WaylandOutput *output in _outputs)
        if (output->_proxy == proxy)
            return output->_current.refresh > 0 ? (uint32_t)output->_current.refresh : 0;
    return 0;
}

- (void) windowScaleChanged: (WaylandWindow *) window {
    if (window == _pointerWindow)
        [self applyCursor];
}

// An output changed. The displays are CoreGraphics', which learns of it on the same connection: its
// objects and these ones get the events of one change in the same pass, so the windows are told when the
// pass is over and both agree on the outputs (-outputsDidChange).
- (void) publishOutput: (WaylandOutput *) output {
    output->_current = output->_pending;
    // Not while the connection is being set up: the displays are read when they are first needed.
    if (_setupDone)
        [self scheduleOutputsDidChange];
}

- (void) scheduleOutputsDidChange {
    if (_outputsChangePending)
        return;
    _outputsChangePending = YES;
    [self performAfterDispatch: ^{
        // CoreGraphics' report of the same change may have been handled meanwhile.
        if (self->_outputsChangePending)
            [self outputsDidChange];
    }];
}

// The outputs changed: what depends on them is brought up to date once per pass.
- (void) outputsDidChange {
    _outputsChangePending = NO;
    [self _invalidateScreens];
    [_draggingManager outputsChanged];
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        [window scheduleScaleUpdate];
        [window outputsChanged];
    }
}

- (void) outputEvent: (uint32_t) opcode
              output: (WaylandOutput *) output
           arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_OUTPUT_EV_MODE:
        if (args[1].i <= 0 || args[2].i <= 0 || args[3].i < 0)
            return;
        if (args[0].u & WP_OUTPUT_MODE_CURRENT) {
            output->_pending.width = args[1].i;
            output->_pending.height = args[2].i;
            output->_pending.refresh = args[3].i;
        }
        break;
    case WP_OUTPUT_EV_SCALE:
        output->_pending.scale = MAX(args[0].i, 1);
        break;
    case WP_OUTPUT_EV_DONE:
        [self publishOutput: output];
        return;
    default:
        return;
    }
    // Version 1 has no done event.
    if (output->_version < 2)
        [self publishOutput: output];
}

#pragma mark - Event routing

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
              object: (id) object
           arguments: (union wl_argument *) args
{
    switch (kind) {
    case WaylandObjectRegistry:
        if (opcode == WP_REGISTRY_EV_GLOBAL)
            [self registryGlobal: args[0].u
                       interface: args[1].s
                         version: args[2].u];
        else if (opcode == WP_REGISTRY_EV_GLOBAL_REMOVE)
            [self registryGlobalRemoved: args[0].u];
        break;

    case WaylandObjectWmBase:
        if (opcode == WP_WM_BASE_EV_PING) {
            union wl_argument pong[1] = {{.u = args[0].u}};
            WaylandMarshal(_wmBase, WP_WM_BASE_PONG, NULL, 0, pong);
        }
        break;

    case WaylandObjectOutput:
        [self outputEvent: opcode output: object arguments: args];
        break;

    case WaylandObjectSeat:
        if (opcode == WP_SEAT_EV_CAPABILITIES)
            [self seatCapabilities: args[0].u];
        break;

    case WaylandObjectTextInput:
        [self textInputEvent: opcode arguments: args];
        break;

    case WaylandObjectActivationToken:
        if (proxy == _activationToken && opcode == WP_ACTIVATION_TOKEN_EV_DONE)
            [self activationTokenDone: args[0].s];
        break;

    case WaylandObjectTouch:
        [self touchEvent: opcode arguments: args];
        break;

    case WaylandObjectSession:
        [self sessionEvent: opcode arguments: args];
        break;

    default:
        break;
    }
}

#pragma mark - Seat

- (void) releaseInputDevice: (struct wl_proxy **) device opcode: (uint32_t) opcode {
    if (*device == NULL)
        return;
    // wl_pointer.release and wl_keyboard.release exist from version 3.
    if (WL.wl_proxy_get_version(*device) >= 3) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(*device, opcode, NULL, WL_MARSHAL_FLAG_DESTROY, args);
    } else {
        WL.wl_proxy_destroy(*device);
    }
    *device = NULL;
}

- (void) seatCapabilities: (uint32_t) capabilities {
    union wl_argument args[1] = {{.o = NULL}};

    // The pointer is CoreGraphics': it binds the process' wl_pointer from its own seat object, decodes it
    // into CGEvents and tells this display about it (see the pointer methods below).
    if ((capabilities & WP_SEAT_CAPABILITY_TOUCH) && _touch == NULL) {
        args[0].o = NULL;
        _touch = WaylandCreateObject(_seat, WP_SEAT_GET_TOUCH, &wl_touch_interface, args,
                                     WaylandObjectTouch, self);
    } else if (!(capabilities & WP_SEAT_CAPABILITY_TOUCH) && _touch != NULL) {
        [self releaseInputDevice: &_touch opcode: WP_TOUCH_RELEASE];
        [self touchCancel];
    }
}

- (WaylandWindow *) windowForSurface: (struct wl_proxy *) surface {
    if (surface == NULL)
        return nil;
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window =
                (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window surface] == surface)
            return window;
    }
    return nil;
}

#pragma mark - Touch

// Fingers go to AppKit's touch router, which moves the mouse for views that
// take no touches: compositors emulate no pointer from a touch screen.
- (void) touchEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    if (_touchWindows == nil)
        _touchWindows = [NSMutableDictionary new];
    switch (opcode) {
    case WP_TOUCH_EV_DOWN: {
        WaylandWindow *window = [self windowForSurface: (struct wl_proxy *) args[2].o];
        if (window == nil)
            break;
        _inputSerial = args[0].u;
        [_touchWindows setObject: [NSValue valueWithNonretainedObject: window] forKey: @(args[3].i)];
        CGPoint point = CGPointMake(wl_fixed_to_double(args[4].f), wl_fixed_to_double(args[5].f));
        NSTouchPost([window delegate], args[3].i, NSTouchPhaseBegan, [window transformPoint: point], 0);
        break;
    }
    case WP_TOUCH_EV_MOTION: {
        WaylandWindow *window = [[_touchWindows objectForKey: @(args[1].i)] nonretainedObjectValue];
        if (window == nil || ![self windowIsKnown: window])
            break;
        CGPoint point = CGPointMake(wl_fixed_to_double(args[2].f), wl_fixed_to_double(args[3].f));
        NSTouchPost([window delegate], args[1].i, NSTouchPhaseMoved, [window transformPoint: point], 0);
        break;
    }
    case WP_TOUCH_EV_UP: {
        WaylandWindow *window = [[_touchWindows objectForKey: @(args[2].i)] nonretainedObjectValue];
        [_touchWindows removeObjectForKey: @(args[2].i)];
        if (window == nil || ![self windowIsKnown: window])
            break;
        // Up carries no position: the finger leaves where it last was.
        NSTouchPost([window delegate], args[2].i, NSTouchPhaseEnded, NSMakePoint(NAN, NAN), 0);
        break;
    }
    case WP_TOUCH_EV_CANCEL:
        [self touchCancel];
        break;
    }
}

- (void) touchCancel {
    [_touchWindows removeAllObjects];
    NSTouchCancelAll(nil);
}

- (BOOL) windowIsKnown: (WaylandWindow *) window {
    return CFArrayContainsValue(_windows, CFRangeMake(0, CFArrayGetCount(_windows)), window);
}

#pragma mark - Pointer

// The pointer is CoreGraphics': it reads the process' wl_pointer, decodes it into mouse, scroll and gesture
// CGEvents (see CGSWaylandPointer) and tells this display what only it can use through the connection observer:
// where the pointer is (surface, serial, position) for the cursor, the tracking areas and popup grabs, the
// window decorations, the key state of a window at a press, and the window of each event. The NSEvents are
// made from the CGEvents when the application takes them (see -windowNumber:location:hasLocation:forPointerEvent:
// and -pointerEventCreated:fromCGEvent:).

- (void) nativeConnectionPointerAvailabilityChanged: (BOOL) available {
    if (available) {
        _pointer = (struct wl_proxy *) _CGSNativeConnectionPointer();
        [self updateCursorShapeDevice];
        return;
    }
    [_draggingManager cancel];
    [self consumeDragPress];
    _pointer = NULL;
    [self updateCursorShapeDevice];
    _pointerWindow = nil;
    _pointerEnterSerial = 0;
    _pressedButtons = 0;
}

- (void) nativeConnectionPointerEntered: (void *) surface serial: (uint32_t) serial x: (double) x y: (double) y {
    // The seat may have given CoreGraphics the pointer before this display was an observer: an enter says it exists.
    if (_pointer == NULL)
        _pointer = (struct wl_proxy *) _CGSNativeConnectionPointer();
    _pointerEnterSerial = serial;
    _pointerWindow = [self windowForSurface: (struct wl_proxy *) surface];
    _pointerSurfacePoint = CGPointMake(x, y);
    [_pointerWindow setLastKnownCursorPosition: [_pointerWindow transformPoint: _pointerSurfacePoint]];
    [self performAfterDispatch: ^{ [self applyCursor]; }];
}

- (void) nativeConnectionPointerLeft {
    WaylandWindow *left = _pointerWindow;

    _pressedButtons = 0;
    [self consumeDragPress];
    _lastMouseLocation = [self mouseLocation];
    if (left != nil && !_CGSNativeConnectionPointerLocked())
        [self performAfterDispatch: ^{ [self pointerLeftWindow: left]; }];
    _pointerWindow = nil;
    _pointerEnterSerial = 0;
}

// The pointer left the window's surface. The compositor does not say where it went, so it is taken to be just
// outside the edge of the window nearest to where it last was (the X11 backend gets the real position in its
// crossing event). The window re-evaluates its tracking areas there, as it does for a motion, and sends the exits
// for the areas the pointer was in. The AppKit work runs outside libwayland's listener.
- (void) pointerLeftWindow: (WaylandWindow *) window {
    if (![self windowIsKnown: window] || [window delegate] == nil)
        return;

    NSSize size = [[window delegate] frame].size;
    NSPoint point = [window mouseLocationOutsideOfEventStream];
    CGFloat toLeft = point.x, toRight = size.width - point.x, toBottom = point.y, toTop = size.height - point.y;
    CGFloat nearest = MIN(MIN(toLeft, toRight), MIN(toBottom, toTop));

    if (nearest == toLeft)
        point.x = -1;
    else if (nearest == toRight)
        point.x = size.width + 1;
    else if (nearest == toBottom)
        point.y = -1;
    else
        point.y = size.height + 1;
    [window setLastKnownCursorPosition: point];
    [[window delegate] platformWindowSetCursorEvent: window];
}

- (BOOL) nativeConnectionPointerMovedToX: (double) x y: (double) y {
    // Track the position even when no surface is under the pointer. Opening a menu maps a new surface under a
    // stationary cursor, so the compositor sends leave and then motion with no window; dropping that motion left
    // _pointerSurfacePoint stale and the following button landed wherever the pointer last was over a known surface.
    CGPoint previousPoint = _pointerSurfacePoint;
    _pointerSurfacePoint = CGPointMake(x, y);

    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return NO;

    [window setLastKnownCursorPosition: [window transformPoint: _pointerSurfacePoint]];

    if (_pressedButtons == 0 && [window isDecorationPoint: _pointerSurfacePoint]) {
        [self performAfterDispatch: ^{ [self applyCursor]; }];
        return YES;
    }

    [self performAfterDispatch: ^{
      if ([window delegate] != nil)
          [[window delegate] platformWindowSetCursorEvent: window];
    }];
    return NO;
}

// A window decoration (the buttons of a title bar, the edges that resize) takes the first button for itself.
- (BOOL) nativeConnectionPointerButton: (uint32_t) button pressed: (BOOL) pressed serial: (uint32_t) serial {
    return _pressedButtons == 0 && [_pointerWindow decorationButton: button
                                                            pressed: pressed
                                                             serial: serial
                                                            atPoint: _pointerSurfacePoint];
}

// A Linux button code of the Cocoa button number of a mouse event, and the mask of it in _pressedButtons.
static uint32_t buttonCodeForNumber(int64_t number) {
    return number == 0 ? WP_BTN_LEFT : number == 1 ? WP_BTN_RIGHT : number == 2 ? WP_BTN_MIDDLE
                                                                                 : (uint32_t) (WP_BTN_LEFT + number);
}

static NSUInteger buttonMaskForNumber(int64_t number) {
    return number == 0 ? 1 : number == 1 ? 2 : number == 2 ? 4 : 8;
}

// CoreGraphics has decoded an event of the pointer and is about to post it. What AppKit knows when the event
// arrives is added: the serial and the window's key state at a press (the compositor may activate the window for
// this very click before or after the press reaches us, so the press is judged by what we knew when it arrived),
// the motion for CGGetLastMouseDelta. An event for a surface that is not a window of ours, and a mouse moved event
// of a window that did not ask for them, go to the event taps only.
- (BOOL) nativeConnectionWillPostWaylandPointerEvent: (CGEventRef) event {
    struct wl_proxy *surface =
            (struct wl_proxy *) (intptr_t) CGEventGetIntegerValueField(event, kCGSEventNativeWindow);
    WaylandWindow *window = [self windowForSurface: surface];
    id delegate = [window delegate];
    int64_t number = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);

    switch (CGEventGetType(event)) {
    case kCGEventLeftMouseDown:
    case kCGEventRightMouseDown:
    case kCGEventOtherMouseDown: {
        BOOL firstPress = _pressedButtons == 0;
        uint32_t serial = (uint32_t) CGEventGetIntegerValueField(event, kCGSEventInputSerial);
        _pressedButtons |= buttonMaskForNumber(number);
        _inputSerial = serial;
        [_generalPasteboard inputAvailable];
        [_inputEvent release];
        _inputEvent = nil;
        _inputWindow = nil;
        _firstPressSerial = firstPress ? serial : 0;
        if (delegate != nil)
            CGEventSetIntegerValueField(event, kCGSMouseEventWindowKeyState, [delegate isKeyWindow] ? 1 : 2);
        return delegate != nil;
    }
    case kCGEventLeftMouseUp:
    case kCGEventRightMouseUp:
    case kCGEventOtherMouseUp:
        _pressedButtons &= ~buttonMaskForNumber(number);
        if (buttonCodeForNumber(number) == _dragPressButton)
            [self consumeDragPress];
        return delegate != nil;
    case kCGEventMouseMoved:
    case kCGEventLeftMouseDragged:
    case kCGEventRightMouseDragged:
    case kCGEventOtherMouseDragged:
        return delegate != nil && (CGEventGetType(event) != kCGEventMouseMoved || [delegate acceptsMouseMovedEvents]);
    default:
        return delegate != nil;
    }
}

// The NSEvent of a press is what popup grabs and drags are tied to (see -popupGrabSerialForParent: and
// -dragOriginForEvent:).
- (void) pointerEventCreated: (NSEvent *) event fromCGEvent: (CGEventRef) cgEvent {
    CGEventType type = CGEventGetType(cgEvent);
    uint32_t serial = (uint32_t) CGEventGetIntegerValueField(cgEvent, kCGSEventInputSerial);

    if ((type != kCGEventLeftMouseDown && type != kCGEventRightMouseDown && type != kCGEventOtherMouseDown) ||
        serial == 0 || CGEventGetIntegerValueField(cgEvent, kCGSEventNativeWindow) == 0)
        return;
    WaylandWindow *window = [self windowForSurface: (struct wl_proxy *) (intptr_t) CGEventGetIntegerValueField(
                                                            cgEvent, kCGSEventNativeWindow)];
    int64_t number = CGEventGetIntegerValueField(cgEvent, kCGMouseEventButtonNumber);

    // Only the press that is the latest one still counts.
    if (serial != _inputSerial)
        return;
    [_inputEvent release];
    _inputEvent = [event retain];
    _inputWindow = window;
    if (serial == _firstPressSerial && (_pressedButtons & buttonMaskForNumber(number)) != 0) {
        [self consumeDragPress];
        _dragPressEvent = [event retain];
        _dragPressWindow = window;
        _dragPressSerial = serial;
        _dragPressButton = buttonCodeForNumber(number);
        _firstPressSerial = 0;
    }
}

// Where a point of one of our windows' surfaces is in global coordinates: the window's origin and the point
// (Wayland says nothing about where a window is, so the origin is the one the application asked for).
- (BOOL) nativeConnectionGlobalLocation: (CGPoint *) location ofSurface: (void *) surface point: (CGPoint) point {
    WaylandWindow *window = [self windowForSurface: (struct wl_proxy *) surface];
    if (window == nil)
        return NO;
    NSPoint local = [window transformPoint: point];
    O2Rect frame = [window frame];
    NSArray *screens = [self screens];
    double primaryHeight = [screens count] > 0 ? NSHeight([[screens objectAtIndex: 0] frame]) : 0;
    *location = CGPointMake(frame.origin.x + local.x, primaryHeight - (frame.origin.y + local.y));
    return YES;
}

// The window an event of the pointer is for and where the pointer was in it, from the surface and the
// position CoreGraphics read from the compositor. They apply only while no event tap has moved the event.
- (BOOL) windowNumber: (NSInteger *) windowNumber
             location: (NSPoint *) location
          hasLocation: (BOOL *) hasLocation
      forPointerEvent: (CGEventRef) event {
    WaylandWindow *window = [self windowForSurface: (struct wl_proxy *) (intptr_t) CGEventGetIntegerValueField(
                                                            event, kCGSEventNativeWindow)];
    if ([window delegate] == nil)
        return NO;
    *windowNumber = [[window delegate] windowNumber];
    CGPoint global = CGEventGetLocation(event);
    if (llround(global.x * 1024) == CGEventGetIntegerValueField(event, kCGSEventPostedLocationX) &&
        llround(global.y * 1024) == CGEventGetIntegerValueField(event, kCGSEventPostedLocationY)) {
        *location = [window transformPoint: CGPointMake(CGEventGetIntegerValueField(event, kCGSEventNativeLocationX) / 1024.0,
                                                        CGEventGetIntegerValueField(event, kCGSEventNativeLocationY) / 1024.0)];
        *hasLocation = YES;
    }
    return YES;
}

#pragma mark - Text input (text-input-v3)

// The compositor's input method sends the composition (preedit_string) and the final text
// (commit_string) between enter and leave, as one state applied at done. They go to the
// text input client of the window's first responder through its NSTextInputContext.

- (void) attachTextInput {
    if (_textInputManager == NULL || _seat == NULL || _textInput != NULL)
        return;
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _seat}};
    _textInput = WaylandCreateObject(_textInputManager, WP_TEXT_INPUT_MANAGER_GET_TEXT_INPUT,
                                     &zwp_text_input_v3_interface, args,
                                     WaylandObjectTextInput, self);
}

- (void) detachTextInput {
    if (_textInput == NULL)
        return;
    [self textInputLeft];
    WaylandMarshal(_textInput, WP_TEXT_INPUT_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _textInput = NULL;
}

- (NSTextInputContext *) textInputContext {
    return _textInputWindow != nil
            ? [NSTextInputContext inputContextForWindow: [_textInputWindow delegate]] : nil;
}

// Sends the text input state to the compositor: whether the first responder takes text and where
// its caret is. Only a change is sent, because the compositor answers every commit.
- (void) syncTextInput {
    if (_textInput == NULL || _textInputWindow == nil)
        return;

    NSTextInputContext *context = [self textInputContext];
    BOOL wanted = context != nil;
    BOOL changed = NO;

    if (wanted != _textInputEnabled) {
        WaylandMarshal(_textInput, wanted ? WP_TEXT_INPUT_ENABLE : WP_TEXT_INPUT_DISABLE,
                       NULL, 0, NULL);
        _textInputEnabled = wanted;
        changed = YES;
        if (!wanted) {
            [_textInputPreedit release];
            _textInputPreedit = nil;
        }
    }
    if (wanted) {
        // The caret rectangle in the surface's logical coordinates, y down.
        NSRect screenRect = [context candidateRectOnScreen];
        NSRect rect = NSZeroRect;
        if (!NSEqualRects(screenRect, NSZeroRect)) {
            NSRect windowRect = [[_textInputWindow delegate] convertRectFromScreen: screenRect];
            NSPoint offset = [_textInputWindow contentOffset];
            rect = NSMakeRect(NSMinX(windowRect) + offset.x,
                              [_textInputWindow frame].size.height - NSMaxY(windowRect) + offset.y,
                              NSWidth(windowRect), NSHeight(windowRect));
        }
        if (!NSEqualRects(rect, _textInputRect) || changed) {
            union wl_argument args[4] = {{.i = (int32_t) floor(rect.origin.x)},
                                         {.i = (int32_t) floor(rect.origin.y)},
                                         {.i = (int32_t) ceil(rect.size.width)},
                                         {.i = (int32_t) ceil(rect.size.height)}};
            WaylandMarshal(_textInput, WP_TEXT_INPUT_SET_CURSOR_RECTANGLE, NULL, 0, args);
            _textInputRect = rect;
            changed = YES;
        }
    }
    if (changed) {
        WaylandMarshal(_textInput, WP_TEXT_INPUT_COMMIT, NULL, 0, NULL);
        [self flush];
    }
}

- (void) textInputCandidateRectChangedInWindow: (NSWindow *) window {
    if (_textInputWindow != nil && [_textInputWindow delegate] == window)
        [self syncTextInput];
}

// The compositor took the text input away from the window: a composition that was showing is
// removed, as no commit can follow it.
- (void) textInputLeft {
    NSTextInputContext *context = [self textInputContext];

    if (_textInputPreedit != nil)
        [context cancelComposition];
    [_textInputPreedit release];
    _textInputPreedit = nil;
    [_textInputPendingPreedit release];
    _textInputPendingPreedit = nil;
    [_textInputPendingCommit release];
    _textInputPendingCommit = nil;
    _textInputWindow = nil;
    _textInputEnabled = NO;
    _textInputRect = NSZeroRect;
}

// Converts a byte offset in the UTF-8 string to a UTF-16 offset in `text`.
static NSUInteger utf16OffsetOfUTF8Offset(NSString *text, int byteOffset) {
    if (byteOffset < 0)
        return [text length];

    NSUInteger length = [text length];
    NSUInteger offset = 0;
    int bytes = 0;

    while (offset < length && bytes < byteOffset) {
        unichar c = [text characterAtIndex: offset];
        if (c >= 0xD800 && c < 0xDC00 && offset + 1 < length) {
            bytes += 4;
            offset += 2;
        } else {
            bytes += c < 0x80 ? 1 : (c < 0x800 ? 2 : 3);
            offset++;
        }
    }
    return offset;
}

// Applies one done batch in the order the protocol gives: the old composition goes, the
// committed text is inserted, the new composition is shown with its caret.
- (void) textInputDone {
    NSTextInputContext *context = [self textInputContext];
    NSString *commit = [_textInputPendingCommit autorelease];
    NSString *preedit = [_textInputPendingPreedit autorelease];
    int cursorBegin = _textInputPendingCursorBegin;
    int cursorEnd = _textInputPendingCursorEnd;

    _textInputPendingCommit = nil;
    _textInputPendingPreedit = nil;
    _textInputPendingCursorBegin = _textInputPendingCursorEnd = -1;

    if (context == nil)
        return;
    if ([preedit length] == 0)
        preedit = nil;
    // Nothing the client has not already got: the compositor answers each commit with a done.
    BOOL samePreedit = preedit == nil ? _textInputPreedit == nil : [preedit isEqualToString: _textInputPreedit];
    if ([commit length] == 0 && samePreedit)
        return;

    if ([commit length] > 0) {
        [context cancelComposition];
        [_textInputPreedit release];
        _textInputPreedit = nil;
        [context commitComposition: commit];
    }
    if (preedit == nil) {
        if (_textInputPreedit != nil)
            [context cancelComposition];
        [_textInputPreedit release];
        _textInputPreedit = nil;
        return;
    }
    NSUInteger begin = utf16OffsetOfUTF8Offset(preedit, cursorBegin);
    NSUInteger end = cursorEnd < 0 ? begin : utf16OffsetOfUTF8Offset(preedit, cursorEnd);
    if (end < begin)
        end = begin;
    [_textInputPreedit release];
    _textInputPreedit = [preedit copy];
    [context updateComposition: preedit selection: NSMakeRange(begin, end - begin)];
}

- (void) textInputEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    switch (opcode) {
    case WP_TEXT_INPUT_EV_ENTER:
        [self textInputLeft];
        _textInputWindow = [self windowForSurface: (struct wl_proxy *) args[0].o];
        [self syncTextInput];
        break;

    case WP_TEXT_INPUT_EV_LEAVE:
        [self textInputLeft];
        break;

    case WP_TEXT_INPUT_EV_PREEDIT_STRING:
        [_textInputPendingPreedit release];
        _textInputPendingPreedit = args[0].s != NULL ? [[NSString alloc] initWithUTF8String: args[0].s] : nil;
        _textInputPendingCursorBegin = args[1].i;
        _textInputPendingCursorEnd = args[2].i;
        break;

    case WP_TEXT_INPUT_EV_COMMIT_STRING:
        [_textInputPendingCommit release];
        _textInputPendingCommit = args[0].s != NULL ? [[NSString alloc] initWithUTF8String: args[0].s] : nil;
        break;

    case WP_TEXT_INPUT_EV_DELETE_SURROUNDING_TEXT:
        // No surrounding text is reported to the input method, so it has nothing to delete.
        break;

    case WP_TEXT_INPUT_EV_DONE:
        [self textInputDone];
        break;
    }
}

- (NSPoint) mouseLocation {
    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return _lastMouseLocation;

    // Global coordinates aren't available on Wayland: use the window's origin.
    NSPoint location = [window transformPoint: _pointerSurfacePoint];
    O2Rect frame = [window frame];
    return NSMakePoint(frame.origin.x + location.x, frame.origin.y + location.y);
}

// Wayland clients can't move the pointer, but while it is locked the cursor is
// the application's own and a warp only moves where it is. That position is
// where mouseLocation reports it and where the pointer reappears on unlock.
// Without a lock the call does nothing, and nothing pretends otherwise.
// position is in CoreGraphics' global space, as -[NSDisplay warpMouse:] documents.
#pragma mark - Pointer lock

// The window to lock: the one activated last. The lock activates once it also
// has pointer focus.
// The relative mouse mode, the warps and the hidden cursor belong to CoreGraphics' connection (the process' one
// wl_pointer); it asks AppKit for what only the windows know.
- (void *) nativeConnectionSurfaceForPointerLock {
    return [[self pointerLockTarget] surface];
}

// Where a point in CoreGraphics' global space is in a window's surface (the window's frame origin as the
// application set it, clamped to its content). Wayland has no global coordinates of its own.
- (BOOL) nativeConnectionPoint: (CGPoint *) point ofSurface: (void *) surface forGlobalLocation: (CGPoint) location {
    WaylandWindow *window = [self windowForSurface: (struct wl_proxy *) surface];
    if (window == nil)
        return NO;
    NSArray *screens = [self screens];
    double primaryHeight = [screens count] > 0 ? NSHeight([[screens objectAtIndex: 0] frame]) : 0;
    double screenX, screenY;
    WaylandScreenPointFromCG(location.x, location.y, primaryHeight, &screenX, &screenY);
    NSRect frame = [window frame];
    NSPoint offset = [window contentOffset];
    WaylandWarp warp = WaylandWarpTarget(screenX, screenY, frame.origin.x, frame.origin.y,
                                         frame.size.width, frame.size.height, offset.x, offset.y);
    *point = CGPointMake(warp.surfaceX, warp.surfaceY);
    return YES;
}

// The cursor of the application was moved within the surface: that is where mouseLocation reports it.
- (void) nativeConnectionPointerWarpedToX: (double) x y: (double) y {
    WaylandWindow *window = _pointerWindow != nil ? _pointerWindow : [self pointerLockTarget];

    _pointerSurfacePoint = CGPointMake(x, y);
    [window setLastKnownCursorPosition: [window transformPoint: _pointerSurfacePoint]];
}

// The cursor was hidden or is visible again: the image (or none) is applied after the dispatch, like every
// cursor change.
- (void) nativeConnectionCursorHiddenChanged: (BOOL) hidden {
    // Not necessarily in the middle of a dispatch: the run is scheduled for the next run loop pass.
    [self performAfterDispatch: ^{ [self applyCursor]; }];
    [self scheduleAfterDispatchRun];
}

- (WaylandWindow *) pointerLockTarget {
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window isMapped] && ![window isPopup])
            return window;
    }
    return nil;
}

// Makes the lock objects match what was asked for. The compositor activates
// the lock when the window has pointer focus, which can be later.
// A locked pointer moves nothing on screen: the event carries the delta at the
// frozen cursor position, as macOS reports it while the cursor is disassociated.
#pragma mark - Keyboard

// The keyboard is CoreGraphics': it reads the process' wl_keyboard, builds the key events from the
// compositor's keymap and posts them as CGEvents (see CGSWaylandKeyboard). What it tells this display
// about arrives through the connection observer.

// The window that has the keyboard focus, from the surface CoreGraphics reports.
- (WaylandWindow *) keyboardWindow {
    return [self windowForSurface: (struct wl_proxy *) _CGSNativeConnectionKeyboardFocus()];
}

- (void) nativeConnectionKeyboardFocusChanged: (void *) surface {
    if (surface != NULL) {
        _keyboardWindowUnmapped = NO;
        _keyboardFocusWindow = [self windowForSurface: (struct wl_proxy *) surface];
        return;
    }
    // The keyboard focus leaves a window that the application itself unmapped (the last window closed,
    // a menu popup destroyed): that is not the focus moving to another client. The application stays
    // active, as on macOS, where an application whose last window closes keeps the activation and
    // the menu bar; a window that is still shown when its focus goes does resign.
    // An application that only owns the menu bar, with a menu popup that the keyboard followed, is
    // the same case.
    BOOL ownUnmapping = _keyboardWindowUnmapped ||
            ([_keyboardFocusWindow isPopup] && ![_keyboardFocusWindow isTooltip] && ![_keyboardFocusWindow isGenericPopup]);
    _keyboardWindowUnmapped = NO;
    _keyboardFocusWindow = nil;
    if (!ownUnmapping)
        [self applicationFocusMayHaveLeft];
}

- (void) nativeConnectionKeyPressedWithSerial: (uint32_t) serial {
    _inputSerial = serial;
    [_generalPasteboard inputAvailable];
    [_inputEvent release];
    _inputEvent = nil;
    _inputWindow = nil;
}

// The window a key event is for, and where the pointer is in it (the NSEvent made from a CGEvent of the
// keyboard). Key events belong to the key window whichever surface of the application the compositor gave
// the focus to. That matters when the key window is a window with alpha 0, which is never shown and so
// never gets the focus. Menus and pop-ups that hold the focus keep the keys.
- (BOOL) windowNumber: (NSInteger *) windowNumber location: (NSPoint *) location forKeyEvent: (CGEventRef) event {
    // An event the application or Carbon posted names no surface: it is for the key window.
    if (CGEventGetIntegerValueField(event, kCGSEventNativeWindow) == 0)
        return [super windowNumber: windowNumber location: location forKeyEvent: event];
    WaylandWindow *window = [self windowForSurface: (struct wl_proxy *) (intptr_t) CGEventGetIntegerValueField(
                                                            event, kCGSEventNativeWindow)];
    id keyPlatformWindow = [[NSApp keyWindow] platformWindow];
    if ([keyPlatformWindow isKindOfClass: [WaylandWindow class]] && (window == nil || ![window isPopup]))
        window = keyPlatformWindow;
    NSWindow *delegate = [window delegate];
    if (delegate == nil)
        return NO;
    *windowNumber = [delegate windowNumber];
    *location = [window mouseLocationOutsideOfEventStream];
    return YES;
}

// The press of a key starts the input event popup grabs are tied to (see -popupGrabSerialForParent:).
- (NSEvent *) keyEventCreated: (NSEvent *) event fromCGEvent: (CGEventRef) cgEvent {
    if ([event type] != NSKeyDown || [event isARepeat] ||
        CGEventGetIntegerValueField(cgEvent, kCGSEventNativeWindow) == 0)
        return event;
    WaylandWindow *window = [self windowForSurface: (struct wl_proxy *) (intptr_t) CGEventGetIntegerValueField(
                                                            cgEvent, kCGSEventNativeWindow)];
    id keyPlatformWindow = [[NSApp keyWindow] platformWindow];
    if ([keyPlatformWindow isKindOfClass: [WaylandWindow class]] && (window == nil || ![window isPopup]))
        window = keyPlatformWindow;
    _inputSerial = (uint32_t) CGEventGetIntegerValueField(cgEvent, kCGSEventInputSerial);
    [_inputEvent release];
    _inputEvent = [event retain];
    _inputWindow = window;
    return event;
}

- (NSUInteger) currentModifierFlags {
    return (NSUInteger) _CGSNativeConnectionModifierFlags();
}

- (int) keyboardLayoutId {
    return _CGSNativeConnectionKeyboardLayoutGroup(NULL);
}

- (void) keyboardLayoutName: (NSString **) name fullName: (NSString **) fullName {
    CFStringRef layout = NULL;
    NSString *layoutName = @"?";

    if (_CGSNativeConnectionKeyboardLayoutGroup(&layout) >= 0 && layout != NULL)
        layoutName = [(NSString *) layout autorelease];
    if (name != NULL)
        *name = layoutName;
    if (fullName != NULL)
        *fullName = layoutName;
}

#pragma mark - Screens

- (NSArray *) outputsWithModes {
    NSMutableArray *result = [NSMutableArray array];
    for (WaylandOutput *output in _outputs)
        if (output->_current.width > 0 && output->_current.height > 0)
            [result addObject: output];
    return result;
}

// The outputs that have reported a mode are CoreGraphics' displays (its connection to the compositor
// lists the same outputs in the same order), so the indexes agree.
- (size_t) fullscreenOutputs: (WaylandFullscreenOutput *) result
                     proxies: (struct wl_proxy **) proxies
                         max: (size_t) max
                     entered: (NSSet *) entered
{
    NSArray *outputs = [self outputsWithModes];
    // -screens invents a screen when no display is known yet.
    if ([outputs count] == 0)
        return 0;
    NSArray *screens = [self screens];
    size_t count = 0;
    for (NSUInteger i = 0; i < [outputs count] && i < [screens count] && count < max; i++) {
        struct wl_proxy *proxy = ((WaylandOutput *) outputs[i])->_proxy;
        NSSize size = [(NSScreen *) screens[i] frame].size;
        result[count] = (WaylandFullscreenOutput) {
            .width = WaylandFullscreenRound(size.width),
            .height = WaylandFullscreenRound(size.height),
            .entered = [entered containsObject: [NSValue valueWithPointer: proxy]],
        };
        proxies[count++] = proxy;
    }
    return count;
}

- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    return frame;
}

- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    return frame;
}

#pragma mark - Windows

- (struct wl_proxy *) seat { return _seat; }

- (WaylandWindow *) popupParentForWindow: (WaylandWindow *) window {
    // A tool tip belongs to the window the pointer is over, whatever was clicked last. Its
    // position comes from the pointer in that window: without one it is not shown.
    if ([window isTooltip])
        return _pointerWindow != window && [_pointerWindow isMapped] ? _pointerWindow : nil;
    // Menu tracking can open nested menus with keyboard or timer events. The
    // newest mapped popup is the parent even if pointer focus has not moved.
    for (CFIndex i = CFArrayGetCount(_windows); i > 0; i--) {
        WaylandWindow *candidate = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i - 1);
        if (candidate != window && [candidate isMapped] && [candidate isPopup] &&
            ![candidate isTooltip] && ![candidate isGenericPopup])
            return candidate;
    }
    if (_inputWindow != window && [_inputWindow isMapped])
        return _inputWindow;
    if (_pointerWindow != window && [_pointerWindow isMapped])
        return _pointerWindow;
    id key = [[NSApp keyWindow] platformWindow];
    if (key != window && [key isKindOfClass: [WaylandWindow class]] && [key isMapped])
        return key;
    // No pointer, input or key window yet (the compositor has not configured and activated the
    // application's first window): the newest mapped window of the application. A toplevel would
    // be placed and sized by the compositor.
    for (CFIndex i = CFArrayGetCount(_windows); i > 0; i--) {
        WaylandWindow *candidate = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i - 1);
        if (candidate != window && [candidate isMapped] && ![candidate isPopup] &&
            ![candidate isTooltip])
            return candidate;
    }
    return nil;
}

// The window a pop-up window of the application (see DarlingWindowPresentation.h) is shown as a
// popup of: the window it is attached to as a child window, else the application's main window,
// else its key window. It must be mapped (a popup of a window that is not shown is a protocol
// error); the caller waits for its first configure.
- (WaylandWindow *) popupParentForGenericPopup: (WaylandWindow *) window {
    NSWindow *candidates[3] = {[[window delegate] parentWindow], [NSApp mainWindow], [NSApp keyWindow]};
    for (int i = 0; i < 3; i++) {
        id platform = [candidates[i] platformWindow];
        if ([platform isKindOfClass: [WaylandWindow class]] && platform != window && [platform isMapped])
            return platform;
    }
    return nil;
}

// The window a window of a raised level, or any window that is not an application window, is made
// transient for: the window it is attached to as a child window, else the application's key
// window, else its main window, provided it is a mapped toplevel and naming it would
// not make a window its own ancestor.
- (WaylandWindow *) levelParentForWindow: (WaylandWindow *) window {
    NSWindow *candidates[4] = {[[window delegate] parentWindow], [[window delegate] sheetParent], [NSApp keyWindow],
                                [NSApp mainWindow]};

    for (int i = 0; i < 4; i++) {
        id platform = [candidates[i] platformWindow];
        if (![platform isKindOfClass: [WaylandWindow class]] || ![platform isMapped] || [platform isPopup])
            continue;
        const void *ancestors[16];
        int count = 0;
        for (WaylandWindow *up = [platform levelParent]; up != nil && count < 16; up = [up levelParent])
            ancestors[count++] = up;
        if (DarlingWindowParentAllowed(window, platform, ancestors, count))
            return platform;
    }
    return nil;
}

- (uint32_t) popupGrabSerialForParent: (WaylandWindow *) parent {
    if ([parent isPopup])
        return [parent popupGrabSerial];
    // Never use a stale serial for a programmatically opened popup.
    return _inputWindow == parent && _inputEvent != nil && [NSApp currentEvent] == _inputEvent
            ? _inputSerial : 0;
}

- (void) unmapPopupsForParent: (WaylandWindow *) parent {
    // Retain a snapshot: unmapping releases each child's parent reference.
    NSMutableArray *children = [NSMutableArray array];
    NSMutableArray *tooltips = [NSMutableArray array];
    for (CFIndex i = CFArrayGetCount(_windows); i > 0; i--) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i - 1);
        if ([window popupParent] == parent)
            [([window isTooltip] || [window isGenericPopup] ? tooltips : children) addObject: window];
    }
    for (WaylandWindow *window in tooltips)
        [window unmap];
    if ([children count] != 0 && ![parent isPopup]) {
        [self cancelPopupMenus];
        return;
    }
    for (WaylandWindow *window in children)
        [window unmap];
}

// Menus that were ordered in before their parent's first configure are mapped now that a window
// has been configured (each decides again which window it belongs to).
- (void) mapPopupsWaitingForParent {
    NSMutableArray *waiting = [NSMutableArray array];
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window isPopupWaitingForParent])
            [waiting addObject: window];
    }
    for (WaylandWindow *window in waiting)
        [window ensureMapped];
}

- (void) cancelPopupMenus {
    // Tracking loops own menu windows. Do not close/release them underneath
    // their stack frames. Clear selection and wake tracking with cancellation.
    NSMutableArray *popups = [NSMutableArray array];
    for (CFIndex i = CFArrayGetCount(_windows); i > 0; i--) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i - 1);
        if ([window isPopup] && ![window isTooltip] && ![window isGenericPopup])
            [popups addObject: window];
    }
    if ([popups count] == 0)
        return;
    for (WaylandWindow *window in popups) {
        id delegate = [window delegate];
        if ([delegate isKindOfClass: [NSMenuWindow class]])
            [[delegate menuView] setSelectedItemIndex: NSNotFound];
        else if ([delegate isKindOfClass: [NSPopUpWindow class]])
            [delegate selectItemAtIndex: -1];
        [window unmap];
    }
    _pressedButtons = 0;
    NSEvent *cancel = [NSEvent otherEventWithType: NSAppKitDefined location: NSZeroPoint
                                   modifierFlags: 0 timestamp: NSEventCurrentTime() windowNumber: 0 context: nil
                                         subtype: NSApplicationDeactivated data1: 0 data2: 0];
    [self postEvent: cancel atStart: YES];
}

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    return [[WaylandWindow alloc] initWithDelegate: delegate];
}

#pragma mark - Main menu

// The main menu goes to the desktop's global menu when the compositor takes the
// address of a window's menu (KDE's appmenu protocol) and something on the
// session bus shows application menus (the com.canonical.AppMenu.Registrar
// name has an owner). Plasma's appmenu service owns that name only while a
// global menu view, the Global Menu applet or the application menu button of
// the window title bars, is in use. Otherwise nothing outside the application
// would show the menu, and a client cannot put a bar of its own along the top
// of the screen with xdg-shell, so the windows draw it themselves.
- (BOOL) _showsMainMenuOutsideWindows {
    // With a layer shell the menu bar window shows the menu when the desktop does not.
    return _layerShell != NULL || [self _desktopShowsMainMenu];
}

// Asked once, with a throw-away exporter, because the answer decides whether the application exports its
// menu at all.
- (BOOL) _desktopShowsMainMenu {
    if (!_desktopMenuProbed) {
        _desktopMenuProbed = YES;
        if (_appMenuManager != NULL) {
            WaylandAppMenu *probe = [[WaylandAppMenu alloc] initWithDisplay: self exporting: YES];

            _desktopMenuPresent = [probe globalMenuPresent];
            [probe release];
        }
    }
    return _desktopMenuPresent;
}

// The menu is exported for the desktop's global menu unless the windows carry it as strips. The menu bar
// window, which a layer shell makes possible, is kept for the time no window carries a strip.
- (void) _mainMenuDidChange: (NSMenu *) menu {
    if (_appMenu == nil) {
        BOOL strips = [NSWindow _usesInWindowMenuBar];

        if (strips && _layerShell == NULL)
            return;
        _appMenu = [[WaylandAppMenu alloc] initWithDisplay: self exporting: !strips];
    }
    [_appMenu setMainMenu: menu];
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) updateApplicationMenu];
    [self flush];
}

- (NSString *) applicationMenuServiceName {
    return [_appMenu serviceName];
}

- (NSString *) applicationMenuObjectPath {
    return [_appMenu objectPath];
}

- (void) windowCreated: (WaylandWindow *) window {
    CFArrayAppendValue(_windows, window);
}

// A window lost the keyboard focus or the compositor's activation. The focus moving from one of our
// surfaces to another arrives as a loss and a gain in the same dispatch; a loss that no gain follows
// means another client has it.
- (void) applicationFocusMayHaveLeft {
    [self performAfterDispatch: ^{
        if (_CGSNativeConnectionKeyboardFocus() != NULL)
            return;
        for (CFIndex i = 0; i < CFArrayGetCount(self->_windows); i++) {
            if ([(WaylandWindow *) CFArrayGetValueAtIndex(self->_windows, i) isActivatedByCompositor])
                return;
        }
        [self keyboardFocusLeftApplication];
    }];
}

// Another client has the keyboard focus: no window of the application is active any more, including
// one that was only reported active because it is never shown (see -[WaylandWindow makeKey]), which no
// configure event would ever take the activation from. The application resigns once none is.
- (void) keyboardFocusLeftApplication {
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        [window keyboardFocusLeft];
    }
    [NSApp _systemFocusMovedToAnotherClient];
}

- (void) windowActivated: (WaylandWindow *) window {
    CFIndex index = CFArrayGetFirstIndexOfValue(
            _windows, CFRangeMake(0, CFArrayGetCount(_windows)), window);
    if (index > 0) {
        CFArrayRemoveValueAtIndex(_windows, index);
        CFArrayInsertValueAtIndex(_windows, 0, window);
    }
    _CGSNativeConnectionPointerLockTargetChanged();
}

- (void) windowUnmapped: (WaylandWindow *) window {
    // The compositor reparents the window's transient children itself.
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *other = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([other levelParent] == window)
            [other levelParentUnmapped];
    }
    // The window to lock the pointer to may be another one now (after the window is gone from the list).
    [self performAfterDispatch: ^{ _CGSNativeConnectionPointerLockTargetChanged(); }];
    if (_textInputWindow == window)
        [self textInputLeft];
    [_draggingManager windowUnmapped: window];
    if (_dragPressWindow == window) [self consumeDragPress];
    if (_pointerWindow == window) {
        _pointerWindow = nil;
        _pointerEnterSerial = 0;
        _pressedButtons = 0;
    }
    if (_inputWindow == window) {
        _inputWindow = nil;
        [_inputEvent release];
        _inputEvent = nil;
    }
    if (_keyboardFocusWindow == window) {
        // The leave event that may still follow is the application unmapping its own window, not another
        // client taking the focus.
        _keyboardWindowUnmapped = YES;
        _keyboardFocusWindow = nil;
    }
    // The keyboard focus, the pointer focus and a pinch on the window's surface end with it.
    _CGSNativeConnectionObjectDestroyed([window surface]);
}

- (void) windowDestroyed: (WaylandWindow *) window {
    [self windowUnmapped: window];
    CFIndex index = CFArrayGetFirstIndexOfValue(
            _windows, CFRangeMake(0, CFArrayGetCount(_windows)), window);
    if (index >= 0)
        CFArrayRemoveValueAtIndex(_windows, index);
}

// Most recently activated first; Wayland doesn't expose the stacking order.
- (NSArray *) orderedWindowNumbers {
    NSMutableArray *result = [NSMutableArray array];
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window =
                (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window isOrderedIn])
            [result addObject: @([window windowNumber])];
    }
    return result;
}

#pragma mark - Cursors

// The output scale must be applied exactly once. wl_surface.set_buffer_scale is the
// one mechanism every compositor applies to a cursor surface; a wp_viewport
// destination is not (Hyprland derives the logical size from buffer size / buffer
// scale and ignores it, wlroots honours it). A raster pinned to buffer_scale 1 and
// cropped by a viewport therefore shows 2x too large on a 2x Hyprland. So the raster is
// made at the next whole scale and tagged with it; the compositor scales it down
// to a fractional output. Without a fractional-scale manager, or without
// set_buffer_scale, the compositor owns the scaling: hand over a 1x raster.
- (uint32_t) cursorRenderScale120 {
    // set_buffer_scale needs wl_surface v3.
    if (!_cursorFractionalScale || _compositorVersion < 3) return 120;
    return WaylandCursorBufferScale120(
            _cursorPreferredScale120 ?: (_pointerWindow ? [_pointerWindow renderScale120] : 120));
}
- (void) preferredScaleChanged: (uint32_t) scale120 {
    if (!_cursorFractionalScale || !scale120 || scale120 == _cursorPreferredScale120) return;
    _cursorPreferredScale120 = scale120;
    if (_applyingCursor) { _cursorApplyPending = YES; return; }
    if (_cursorApplyQueued) return;
    _cursorApplyQueued = YES;
    [self performAfterDispatch: ^{ self->_cursorApplyQueued = NO; [self applyCursor]; }];
}

- (struct wl_proxy *) imageCursorBufferForScale120: (uint32_t) scale120 cursor: (WaylandCursor *) cursor {
    if (_imageCursorBuffer != NULL && _imageCursorBufferScale120 != scale120) {
        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_imageCursorBuffer, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
        _imageCursorBuffer = NULL;
    }
    if (_imageCursorBuffer != NULL)
        return _imageCursorBuffer;
    NSData *pixels = [cursor pixelsForScale120: scale120];
    // Rendering an NSImage can select a different cursor or dispatch input.
    // Never install that obsolete result as the active cursor buffer.
    if (_cursorApplyPending || cursor != _cursor || pixels == nil)
        return NULL;

    NSSize dimensions = [cursor pixelSizeForScale120: scale120];
    _imageCursorBuffer = [self newARGBBuffer: pixels pixelSize: dimensions];
    _imageCursorBufferScale120 = scale120;
    return _imageCursorBuffer;
}

- (struct wl_proxy *) newARGBBuffer: (NSData *) pixels pixelSize: (NSSize) dimensions {
    double width = dimensions.width, height = dimensions.height;
    if (!isfinite(width) || !isfinite(height) || width < 1 || height < 1 ||
        width != floor(width) || height != floor(height) ||
        width > INT32_MAX / 4 || height > INT32_MAX / (width * 4) ||
        [pixels length] != (NSUInteger) (width * height * 4)) return NULL;
    size_t size = [pixels length];
    int fd = WaylandCreateAnonymousFile(size);
    if (fd < 0)
        return NULL;
    void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        close(fd);
        return NULL;
    }
    memcpy(data, [pixels bytes], size);
    // Immutable storage: the queued request owns a duplicate of fd and the
    // compositor keeps its mapping. We never rewrite pixels still in use.
    munmap(data, size);
    union wl_argument poolArgs[3] = {{.o = NULL}, {.h = fd}, {.i = (int32_t) size}};
    struct wl_proxy *pool = WaylandCreateObject(_shm, WP_SHM_CREATE_POOL,
                                                &wl_shm_pool_interface, poolArgs, 0, nil);
    close(fd);
    union wl_argument bufferArgs[6] = {{.o = NULL}, {.i = 0},
        {.i = (int32_t) width}, {.i = (int32_t) height},
        {.i = (int32_t) width * 4}, {.u = WP_SHM_FORMAT_ARGB8888}};
    struct wl_proxy *buffer = WaylandCreateObject(pool, WP_SHM_POOL_CREATE_BUFFER,
            &wl_buffer_interface, bufferArgs, 0, nil);
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(pool, WP_SHM_POOL_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    return buffer;
}

// The freedesktop names WaylandCursor looks up, and the matching wp_cursor_shape_device_v1.shape.
// Names that are not in this table (a custom NSImage, for example) use the default shape.
static uint32_t CursorShapeForCursor(WaylandCursor *cursor) {
    static const struct { const char *name; uint32_t shape; } shapes[] = {
            {"default", WP_CURSOR_SHAPE_DEFAULT},
            {"grabbing", WP_CURSOR_SHAPE_GRABBING},
            {"crosshair", WP_CURSOR_SHAPE_CROSSHAIR},
            {"text", WP_CURSOR_SHAPE_TEXT},
            {"vertical-text", WP_CURSOR_SHAPE_VERTICAL_TEXT},
            {"zoom-in", WP_CURSOR_SHAPE_ZOOM_IN},
            {"zoom-out", WP_CURSOR_SHAPE_ZOOM_OUT},
            {"grab", WP_CURSOR_SHAPE_GRAB},
            {"pointer", WP_CURSOR_SHAPE_POINTER},
            {"s-resize", WP_CURSOR_SHAPE_S_RESIZE},
            {"w-resize", WP_CURSOR_SHAPE_W_RESIZE},
            {"ew-resize", WP_CURSOR_SHAPE_EW_RESIZE},
            {"e-resize", WP_CURSOR_SHAPE_E_RESIZE},
            {"n-resize", WP_CURSOR_SHAPE_N_RESIZE},
            {"ns-resize", WP_CURSOR_SHAPE_NS_RESIZE},
            {"nw-resize", WP_CURSOR_SHAPE_NW_RESIZE},
            {"ne-resize", WP_CURSOR_SHAPE_NE_RESIZE},
            {"se-resize", WP_CURSOR_SHAPE_SE_RESIZE},
            {"sw-resize", WP_CURSOR_SHAPE_SW_RESIZE},
            {"nwse-resize", WP_CURSOR_SHAPE_NWSE_RESIZE},
            {"nesw-resize", WP_CURSOR_SHAPE_NESW_RESIZE},
    };
    const char *const *names = cursor != nil ? [cursor names] : NULL;
    for (int i = 0; names != NULL && names[i] != NULL; i++)
        for (size_t j = 0; j < sizeof(shapes) / sizeof(shapes[0]); j++)
            if (strcmp(names[i], shapes[j].name) == 0)
                return shapes[j].shape;
    return WP_CURSOR_SHAPE_DEFAULT;
}

- (void) updateCursorShapeDevice {
    if (_cursorShapeManager != NULL && _pointer != NULL && _cursorShapeDevice == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _pointer}};
        _cursorShapeDevice = WaylandCreateObject(_cursorShapeManager,
                                                 WP_CURSOR_SHAPE_MANAGER_GET_POINTER,
                                                 &wp_cursor_shape_device_v1_interface,
                                                 args, 0, nil);
        // The current cursor was set with wl_pointer.set_cursor before the manager existed.
        if (_cursorShapeDevice != NULL)
            [self performAfterDispatch: ^{ [self applyCursor]; }];
    } else if ((_cursorShapeManager == NULL || _pointer == NULL) && _cursorShapeDevice != NULL) {
        // A device whose pointer went away is inert; there is nothing to send it.
        WaylandMarshal(_cursorShapeDevice, WP_CURSOR_SHAPE_DEVICE_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
        _cursorShapeDevice = NULL;
    }
}

- (void) applyCursorSnapshot: (WaylandCursor *) cursor {
    if (_pointer == NULL || _pointerEnterSerial == 0)
        return;

    struct wl_proxy *pointer = _pointer, *surface = _cursorSurface;
    uint32_t serial = _pointerEnterSerial;
    WaylandWindow *window = _pointerWindow;
    CGPoint point = _pointerSurfacePoint;
    union wl_argument args[4];
    args[0].u = serial;

    BOOL decoration = [_pointerWindow isDecorationPoint: _pointerSurfacePoint];
    if (!decoration && ([cursor isBlank] || _CGSNativeConnectionCursorHidden())) {
        args[1].o = NULL;
        args[2].i = 0;
        args[3].i = 0;
        WaylandMarshal(_pointer, WP_POINTER_SET_CURSOR, NULL, 0, args);
        [self flush];
        return;
    }
    // A named cursor needs neither a cursor surface nor a theme: the compositor draws the shape.
    // The protocol requires the latest wl_pointer.enter serial, which is the one kept for the
    // surface cursor too.
    if (_cursorShapeDevice != NULL) {
        union wl_argument shapeArgs[2] = {{.u = serial}, {.u = CursorShapeForCursor(cursor)}};
        WaylandMarshal(_cursorShapeDevice, WP_CURSOR_SHAPE_DEVICE_SET_SHAPE, NULL, 0, shapeArgs);
        [self flush];
        return;
    }
    if (_cursorSurface == NULL)
        return;

    uint32_t scale120 = [self cursorRenderScale120];
    int32_t wireScale = (int32_t)(scale120 / 120);
    struct wl_proxy *buffer = decoration ? NULL : [self imageCursorBufferForScale120: scale120 cursor: cursor];
    if (_cursorApplyPending || cursor != _cursor || pointer != _pointer ||
        surface != _cursorSurface || serial != _pointerEnterSerial ||
        window != _pointerWindow || !CGPointEqualToPoint(point, _pointerSurfacePoint) ||
        decoration != [_pointerWindow isDecorationPoint: _pointerSurfacePoint] ||
        scale120 != [self cursorRenderScale120]) {
        _cursorApplyPending = YES;
        return;
    }
    NSSize logical = [cursor size];
    NSPoint hotSpot = [cursor hotSpot];
    if (buffer == NULL) {
        if (WL.hasCursor && _cursorThemeScale120 != scale120) {
            const char *sizeString = getenv("XCURSOR_SIZE");
            long nominal = sizeString ? strtol(sizeString, NULL, 10) : 24;
            if (nominal <= 0 || nominal > INT32_MAX) nominal = 24;
            int32_t requested;
            struct wl_cursor_theme *theme = WaylandScaleExtent((int32_t)nominal, scale120, INT32_MAX, &requested)
                ? WL.wl_cursor_theme_load(getenv("XCURSOR_THEME"), requested, (struct wl_shm *)_shm) : NULL;
            if (theme != NULL) {
                if (_cursorTheme != NULL) WL.wl_cursor_theme_destroy(_cursorTheme);
                _cursorTheme = theme; _cursorThemeScale120 = scale120;
            }
        }
        if (_cursorTheme == NULL)
            return;
        static const char *const arrowNames[] = {"default", "left_ptr", NULL};
        const char *const *names = !decoration && cursor ? [cursor names] : arrowNames;
        struct wl_cursor *cursor = NULL;
        for (int i = 0; cursor == NULL && names[i] != NULL; i++)
            cursor = WL.wl_cursor_theme_get_cursor(_cursorTheme, names[i]);
        for (int i = 0; cursor == NULL && arrowNames[i] != NULL; i++)
            cursor = WL.wl_cursor_theme_get_cursor(_cursorTheme, arrowNames[i]);
        if (cursor == NULL || cursor->image_count == 0)
            return;

        struct wl_cursor_image *image = cursor->images[0];
        buffer = (struct wl_proxy *) WL.wl_cursor_image_get_buffer(image);
        if (buffer == NULL)
            return;
        if (!image->width || !image->height || image->width > INT32_MAX || image->height > INT32_MAX) return;
        // The theme was loaded at the nominal size times the whole scale: the
        // surface is tagged with that scale, so the logical size and the hotspot
        // are the image's divided by it. A theme without that exact size hands
        // back its nearest one, which the scale may not divide.
        wireScale = WaylandCursorWireScale((int32_t)image->width, (int32_t)image->height,
                                           (int32_t)(_cursorThemeScale120 / 120));
        logical = NSMakeSize(image->width / wireScale, image->height / wireScale);
        hotSpot = NSMakePoint(image->hotspot_x / wireScale, image->hotspot_y / wireScale);
    }

    if (_compositorVersion >= 3) {
        union wl_argument scaleArgs[1] = {{.i = wireScale}};
        WaylandMarshal(_cursorSurface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scaleArgs);
    }

    union wl_argument attach[3] = {{.o = (struct wl_object *) buffer}, {.i = 0}, {.i = 0}};
    WaylandMarshal(_cursorSurface, WP_SURFACE_ATTACH, NULL, 0, attach);
    union wl_argument damage[4] = {{.i = 0}, {.i = 0},
                                   {.i = (int32_t)logical.width},
                                   {.i = (int32_t)logical.height}};
    WaylandMarshal(_cursorSurface, WP_SURFACE_DAMAGE, NULL, 0, damage);
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_cursorSurface, WP_SURFACE_COMMIT, NULL, 0, none);

    args[1].o = (struct wl_object *) _cursorSurface;
    args[2].i = (int32_t) hotSpot.x;
    args[3].i = (int32_t) hotSpot.y;
    WaylandMarshal(_pointer, WP_POINTER_SET_CURSOR, NULL, 0, args);
    [self flush];
}

- (void) applyCursor {
    if (_applyingCursor) { _cursorApplyPending = YES; return; }
    _applyingCursor = YES;
    // Keep the image receiver alive even if drawing changes the display cursor.
    WaylandCursor *cursor = [_cursor retain];
    WaylandWindow *window = [_pointerWindow retain];
    @try { [self applyCursorSnapshot: cursor]; }
    @finally {
        [window release];
        [cursor release];
        _applyingCursor = NO;
        if (_cursorApplyPending) {
            _cursorApplyPending = NO;
            if (!_cursorApplyQueued) {
                _cursorApplyQueued = YES;
                [self performAfterDispatch: ^{
                    self->_cursorApplyQueued = NO;
                    [self applyCursor];
                }];
            }
        }
    }
}

// Names from the freedesktop cursor specification, then the older X11 names.
- (id) cursorWithName: (NSString *) name {
    static const struct {
        NSString *name;
        const char *cursor, *fallback;
    } names[] = {
            {@"arrowCursor", "default", "left_ptr"},
            {@"closedHandCursor", "grabbing", "hand3"},
            {@"crosshairCursor", "crosshair", "cross"},
            {@"IBeamCursor", "text", "xterm"},
            {@"IBeamCursorForVerticalLayout", "vertical-text", "xterm"},
            {@"zoomInCursor", "zoom-in", "left_ptr"},
            {@"zoomOutCursor", "zoom-out", "left_ptr"},
            {@"openHandCursor", "grab", "fleur"},
            {@"pointingHandCursor", "pointer", "hand2"},
            {@"resizeDownCursor", "s-resize", "bottom_side"},
            {@"resizeLeftCursor", "w-resize", "left_side"},
            {@"resizeLeftRightCursor", "ew-resize", "h_double_arrow"},
            {@"resizeRightCursor", "e-resize", "right_side"},
            {@"resizeUpCursor", "n-resize", "top_side"},
            {@"resizeUpDownCursor", "ns-resize", "v_double_arrow"},
            {@"frameResizeNorthWestCursor", "nw-resize", "top_left_corner"},
            {@"frameResizeNorthEastCursor", "ne-resize", "top_right_corner"},
            {@"frameResizeSouthEastCursor", "se-resize", "bottom_right_corner"},
            {@"frameResizeSouthWestCursor", "sw-resize", "bottom_left_corner"},
            {@"frameResizeNorthWestSouthEastCursor", "nwse-resize", "fd_double_arrow"},
            {@"frameResizeNorthEastSouthWestCursor", "nesw-resize", "bd_double_arrow"},
    };

    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if ([name isEqualToString: names[i].name])
            return [[[WaylandCursor alloc] initWithName: names[i].cursor
                                               fallback: names[i].fallback]
                    autorelease];
    return [[[WaylandCursor alloc] initWithName: "default" fallback: "left_ptr"]
            autorelease];
}

- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot {
    WaylandCursor *cursor = [[[WaylandCursor alloc] initWithImage: image hotSpot: hotSpot] autorelease];
    return cursor != nil ? cursor : [self cursorWithName: @"arrowCursor"];
}

- (void) setCursor: (id) cursor {
    if (![cursor isKindOfClass: [WaylandCursor class]])
        return;
    // Retain first: AppKit can select the currently active cursor again.
    [cursor retain];
    if (cursor != _cursor && _imageCursorBuffer != NULL) {
        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_imageCursorBuffer, WP_BUFFER_DESTROY, NULL,
                        WL_MARSHAL_FLAG_DESTROY, none);
        _imageCursorBuffer = NULL;
    }
    [_cursor release];
    _cursor = cursor;
    [self applyCursor];
}

#pragma mark - Clipboard, drag and drop, input state and unsupported calls

- (uint32_t) clipboardSerial {
    if (_CGSNativeConnectionKeyboardFocus() != NULL)
        return _inputSerial;
    // A key or click still being handled entitles its writes to the selection even when the focus
    // left right after it, as when a virtual keyboard is removed a few milliseconds after its key.
    return _inputEvent != nil && [NSApp currentEvent] == _inputEvent ? _inputSerial : 0;
}

- (NSDraggingManager *) draggingManager {
    if (_draggingManager == nil)
        _draggingManager = [[WaylandDraggingManager alloc] initWithDisplay: self];
    return _draggingManager;
}
- (struct wl_proxy *) dragDataDevice { return [_generalPasteboard dataDevice]; }
- (void) consumeDragPress {
    [_dragPressEvent release]; _dragPressEvent = nil;
    _dragPressWindow = nil; _dragPressSerial = 0;
}
- (WaylandWindow *) dragOriginForEvent: (NSEvent *) event {
    if (_dragPressEvent == nil || _dragPressSerial == 0 ||
        _dragPressWindow == nil || ![_dragPressWindow isMapped]) return nil;
    if (event == _dragPressEvent) return _dragPressWindow;
    // A drag may start from the down event or the currently dispatched motion.
    if (_dragPressButton != WP_BTN_LEFT && _dragPressButton != WP_BTN_RIGHT) return nil;
    NSEventType expected = _dragPressButton == WP_BTN_LEFT ? NSLeftMouseDragged : NSRightMouseDragged;
    if ([NSApp currentEvent] == event && [event type] == expected &&
        [event window] == [_dragPressWindow delegate]) return _dragPressWindow;
    return nil;
}
- (uint32_t) dragSerialForEvent: (NSEvent *) event {
    return [self dragOriginForEvent: event] ? _dragPressSerial : 0;
}

- (void) beep {
}

- (NSUInteger) pressedMouseButtons {
    return _pressedButtons;
}

#pragma mark - Activation

// Wayland has no protocol to activate another client's window: the request goes
// to the process, as a Darwin notification that its own backend answers with
// -requestActivation (see _CGSActivateProcess).
- (BOOL) activateProcessIdentifier: (pid_t) processIdentifier {
    if (processIdentifier <= 0 || processIdentifier == getpid())
        return NO;
    return _CGSActivateProcess(processIdentifier, kCGSActivateProcessFrontWindowOnly) ==
           kCGErrorSuccess;
}

// The window an activation request is for: the key window, else the main window,
// else the window that was active most recently.
- (WaylandWindow *) windowForActivation {
    NSWindow *candidates[] = {[NSApp keyWindow], [NSApp mainWindow]};
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        id platform = [candidates[i] platformWindow];
        if ([platform isKindOfClass: [WaylandWindow class]] && [platform isMapped] &&
            ![platform isPopup])
            return platform;
    }
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window isMapped] && ![window isPopup])
            return window;
    }
    return nil;
}

// Asks the compositor, through xdg-activation, to focus one of our windows. The
// compositor decides: it may only mark the window as wanting attention. The token
// carries the serial of the last input event when there is one, because
// compositors refuse requests that cannot be tied to user input.
- (BOOL) mappingForActivation {
    return _mappingForActivation;
}

// Maps the windows that were ordered in while the application could not take the input focus.
- (void) mapDeferredWindows {
    BOOL previous = _mappingForActivation;
    _mappingForActivation = YES;
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window isMapDeferred])
            [window ensureMapped];
    }
    _mappingForActivation = previous;
    [self flush];
}

- (void) applicationBecameActive: (NSNotification *) notification {
    [self mapDeferredWindows];
}

- (void) requestActivation {
    if (_activation == NULL || _activationToken != NULL)
        return;
    // An application that is asked to activate shows the windows it was holding back.
    [self mapDeferredWindows];
    WaylandWindow *window = [self windowForActivation];
    [self requestActivationOf: window from: window];
}

// The same request for a given window, for instance one the compositor was asked to minimize. The
// requesting surface the token names (xdg-activation set_surface) is not the surface to activate:
// it is the key or main window, when there is another one that is shown. GUESS: with none the token
// names no surface, which the protocol allows and some compositors refuse. Returns whether a
// request was made; one is not while another waits for its token, and then nothing was asked.
- (BOOL) requestActivationOfWindow: (WaylandWindow *) window {
    NSWindow *candidates[] = {[NSApp keyWindow], [NSApp mainWindow]};
    WaylandWindow *requester = nil;
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]) && requester == nil; i++) {
        id platform = [candidates[i] platformWindow];
        if ([platform isKindOfClass: [WaylandWindow class]] && platform != window &&
            [platform isMapped] && ![platform isPopup] && ![platform isMiniaturized])
            requester = platform;
    }
    return [self requestActivationOf: window from: requester];
}

- (BOOL) requestActivationOf: (WaylandWindow *) window from: (WaylandWindow *) requester {
    if (_activation == NULL || _activationToken != NULL)
        return NO;
    struct wl_proxy *surface = [window surface];
    if (surface == NULL)
        return NO;

    union wl_argument none[1] = {{.o = NULL}};
    _activationToken = WaylandCreateObject(_activation, WP_ACTIVATION_GET_TOKEN,
                                           &xdg_activation_token_v1_interface, none,
                                           WaylandObjectActivationToken, self);
    if (_inputSerial != 0 && _seat != NULL) {
        union wl_argument serial[2] = {{.u = _inputSerial}, {.o = (struct wl_object *) _seat}};
        WaylandMarshal(_activationToken, WP_ACTIVATION_TOKEN_SET_SERIAL, NULL, 0, serial);
    }
    struct wl_proxy *requesting = [requester surface];
    if (requesting != NULL) {
        union wl_argument forSurface[1] = {{.o = (struct wl_object *) requesting}};
        WaylandMarshal(_activationToken, WP_ACTIVATION_TOKEN_SET_SURFACE, NULL, 0, forSurface);
    }
    WaylandMarshal(_activationToken, WP_ACTIVATION_TOKEN_COMMIT, NULL, 0, NULL);
    _activationWindow = [window retain];
    [self flush];
    return YES;
}

- (void) cancelActivationRequest {
    if (_activationToken != NULL) {
        WaylandMarshal(_activationToken, WP_ACTIVATION_TOKEN_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
        _activationToken = NULL;
    }
    [_activationWindow release];
    _activationWindow = nil;
}

- (void) activationTokenDone: (const char *) token {
    WaylandWindow *window = _activationWindow;
    struct wl_proxy *surface = [window isInvalidated] ? NULL : [window surface];

    if (_activation != NULL && surface != NULL) {
        union wl_argument args[2] = {{.s = token}, {.o = (struct wl_object *) surface}};
        WaylandMarshal(_activation, WP_ACTIVATION_ACTIVATE, NULL, 0, args);
    }
    [self cancelActivationRequest];
    [self flush];
}

@end
