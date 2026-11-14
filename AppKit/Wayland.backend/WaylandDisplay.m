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

#import "WaylandDisplay.h"
#import "CarbonKeys.h"
#import "NSEvent_gesture.h"
#import "NSEvent_mouse.h"
#import "WaylandCursor.h"
#import "WaylandScale.h"
#import "WaylandPasteboard.h"
#import "WaylandDraggingManager.h"
#import <OpenGL/CGLInternal.h>
#include <dlfcn.h>
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "WaylandWindow.h"
#import "X11KeySymToUCS.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
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

@interface WaylandScreen : NSScreen {
@public
    CGFloat _waylandScale;
}
@end
@implementation WaylandScreen
- (CGFloat) backingScaleFactor { return _waylandScale; }
@end

// Mode pixels are untransformed. Publish v2 properties together at wl_output.done.
typedef struct { int32_t width, height, refresh, scale, transform; } WaylandOutputState;

typedef struct {
    int32_t x, y, width, height;
    BOOL hasPosition, hasSize;
} WaylandLogicalOutputState;

// A wl_output and the modes it advertised.
@interface WaylandOutput : NSObject {
@public
    struct wl_proxy *_proxy, *_logicalProxy;
    uint32_t _globalName, _version, _logicalVersion;
    WaylandDisplay *_display;
    WaylandOutputState _current, _pending;
    WaylandLogicalOutputState _logicalCurrent, _logicalPending;
    NSArray *_modes;
    NSMutableArray *_pendingModes;
}
@end

@implementation WaylandOutput

- (void) dealloc {
    [_modes release];
    [_pendingModes release];
    [super dealloc];
}

@end

@interface WaylandDisplay (Private)
- (void) logicalOutputEvent: (uint32_t) opcode output: (WaylandOutput *) output
                 arguments: (union wl_argument *) args;
- (void) attachLogicalOutput: (WaylandOutput *) output;
- (void) processPendingEvents;
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
            switch (objectKind) {
            case WaylandObjectSurface:
            case WaylandObjectXdgSurface:
            case WaylandObjectToplevel:
            case WaylandObjectPopup:
            case WaylandObjectDecoration:
            case WaylandObjectFrameCallback:
            case WaylandObjectBuffer:
                [(WaylandWindow *) object handleEvent: opcode
                                                 kind: objectKind
                                                proxy: proxy
                                            arguments: args];
                break;
            case WaylandObjectLogicalOutput:
                [((WaylandOutput *) object)->_display logicalOutputEvent: opcode
                                                                  output: object arguments: args];
                break;
            case WaylandObjectDataDevice:
            case WaylandObjectDataOffer:
            case WaylandObjectDataSource:
                [(WaylandPasteboard *) object handleEvent: opcode kind: objectKind
                                                     proxy: proxy arguments: args];
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

static void socketCallback(CFSocketRef socket, CFSocketCallBackType type,
                           CFDataRef address, const void *data, void *info)
{
    [(WaylandDisplay *) info processPendingEvents];
}

static void repeatTimerCallback(CFRunLoopTimerRef timer, void *info) {
    [(WaylandDisplay *) info performSelector: @selector(repeatKey)];
}

static NSString *stringWithCodepoint(uint32_t codepoint) {
    if (codepoint == 0 || codepoint > 0x10FFFF)
        return @"";
    if (codepoint < 0x10000) {
        unichar character = (unichar) codepoint;
        return [NSString stringWithCharacters: &character length: 1];
    }
    codepoint -= 0x10000;
    unichar pair[2] = {(unichar) (0xD800 + (codepoint >> 10)),
                       (unichar) (0xDC00 + (codepoint & 0x3FF))};
    return [NSString stringWithCharacters: pair length: 2];
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

    // Skip -[X11Display init], which connects to an X server.
    struct objc_super superInfo = {self, [NSDisplay class]};
    self = ((id (*)(struct objc_super *, SEL)) objc_msgSendSuper)(&superInfo,
                                                                 _cmd);
    if (self == nil)
        return nil;

    _outputs = [NSMutableArray new];
    _afterDispatch = [NSMutableArray new];
    _windows = CFArrayCreateMutable(NULL, 0, NULL);
    // Inherited from X11Display, whose -init was skipped above, so nothing else
    // allocates it. A nil dictionary would make every click the first click.
    _buttonClickCounts = [NSMutableDictionary new];
    _namedPasteboards = [NSMutableDictionary new];
    _repeatRate = 25;
    _repeatDelay = 600;

    _wlDisplay = WL.wl_display_connect(NULL);
    if (_wlDisplay == NULL) {
        const char *name = getenv("WAYLAND_DISPLAY");
        NSLog(@"Wayland backend: cannot connect to the compositor "
              @"(WAYLAND_DISPLAY=%s), trying the next backend",
              name ? name : "unset");
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

    _xkbContext = WL.xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (_xkbContext == NULL)
        NSLog(@"Wayland backend: cannot create an xkbcommon context, keyboard "
              @"input is disabled");

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
    if (_cursorFractionalScale) {
        union wl_argument viewport[] = {{.o = NULL}, {.o = (struct wl_object *)_cursorSurface}};
        _cursorViewport = WaylandCreateObject(_viewporter, WP_VIEWPORTER_GET_VIEWPORT,
            &wp_viewport_interface, viewport, 0, nil);
    }

    CFSocketContext context = {.version = 0, .info = self};
    _wlSocket = CFSocketCreateWithNative(NULL, WL.wl_display_get_fd(_wlDisplay),
                                         kCFSocketReadCallBack, socketCallback,
                                         &context);
    if (_wlSocket != NULL) {
        // The descriptor belongs to libwayland.
        CFSocketSetSocketFlags(_wlSocket, CFSocketGetSocketFlags(_wlSocket) &
                                                  ~kCFSocketCloseOnInvalidate);
        _wlSource = CFSocketCreateRunLoopSource(NULL, _wlSocket, 0);
    }
    if (_wlSource == NULL) {
        NSLog(@"Wayland backend: cannot watch the compositor connection, trying "
              @"the next backend");
        [self release];
        return nil;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), _wlSource, kCFRunLoopCommonModes);

    [self runAfterDispatchBlocks];
    [self flush];

    return self;
}

- (void) dealloc {
    [_draggingManager invalidate];
    [_draggingManager release];
    [self consumeDragPress];
    [_generalPasteboard invalidate];
    [_generalPasteboard release];
    for (WaylandPasteboard *pasteboard in [_namedPasteboards allValues])
        [pasteboard invalidate];
    [_namedPasteboards release];
    [self stopKeyRepeat];
    [self cancelPendingModifier];
    [_heldKeyIdentities release];

    if (_wlSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _wlSource,
                              kCFRunLoopCommonModes);
        CFRelease(_wlSource);
    }
    if (_wlSocket != NULL) {
        CFSocketInvalidate(_wlSocket);
        CFRelease(_wlSocket);
    }
    if (_xkbState != NULL)
        WL.xkb_state_unref(_xkbState);
    if (_xkbKeymap != NULL)
        WL.xkb_keymap_unref(_xkbKeymap);
    if (_xkbContext != NULL)
        WL.xkb_context_unref(_xkbContext);
    if (_cursorTheme != NULL)
        WL.wl_cursor_theme_destroy(_cursorTheme);
    if (_wlDisplay != NULL) {
        // wl_display_disconnect() doesn't free proxies.
        struct wl_proxy *proxies[] = {_imageCursorBuffer, _cursorFractionalScale, _cursorViewport, _cursorSurface, _pinchGesture, _pointerGestures, _pointer, _keyboard,
                                      _seat, _decorationManager, _dataDeviceManager, _wmBase,
                                      _shm, _viewporter, _fractionalScaleManager, _subcompositor, _logicalOutputManager,
                                      _legacyLogicalOutputManager, _compositor, _registry};
        for (size_t i = 0; i < sizeof(proxies) / sizeof(proxies[0]); i++)
            if (proxies[i] != NULL)
                WL.wl_proxy_destroy(proxies[i]);
        for (WaylandOutput *output in _outputs) {
            if (output->_logicalProxy) WL.wl_proxy_destroy(output->_logicalProxy);
            WL.wl_proxy_destroy(output->_proxy);
        }
        WL.wl_display_disconnect(_wlDisplay);
    }

    [_cursor release];
    [_inputEvent release];
    [_screens release];
    [_outputs release];
    [_afterDispatch release];
    if (_windows != NULL)
        CFRelease(_windows);

    // _buttonClickCounts is inherited, not owned separately: X11Display's -dealloc
    // releases it, so doing it here too would over-release.
    // X11Display's -dealloc only releases the X resources that exist.
    [super dealloc];
}

#pragma mark - Connection and event loop

- (void) flush {
    if (_wlDisplay != NULL)
        WL.wl_display_flush(_wlDisplay);
}

- (void) connectionFailed {
    NSLog(@"Wayland backend: lost the connection to the compositor (error %d)",
          WL.wl_display_get_error(_wlDisplay));
    exit(1);
}

- (void) performAfterDispatch: (void (^)(void)) block {
    [_afterDispatch addObject: [[block copy] autorelease]];
}

- (void) runAfterDispatchBlocks {
    while ([_afterDispatch count] > 0) {
        NSArray *blocks = [_afterDispatch copy];
        [_afterDispatch removeAllObjects];
        @try {
            for (void (^block)(void) in blocks)
                block();
        } @finally {
            [blocks release];
        }
    }
}

- (void) processPendingEvents {
    if (_wlDisplay == NULL)
        return;

    while (WL.wl_display_prepare_read(_wlDisplay) != 0) {
        if (WL.wl_display_dispatch_pending(_wlDisplay) < 0)
            [self connectionFailed];
    }
    WL.wl_display_flush(_wlDisplay);

    struct pollfd pfd = {.fd = WL.wl_display_get_fd(_wlDisplay),
                         .events = POLLIN};
    if (poll(&pfd, 1, 0) > 0) {
        if (WL.wl_display_read_events(_wlDisplay) < 0)
            [self connectionFailed];
    } else {
        WL.wl_display_cancel_read(_wlDisplay);
    }

    if (WL.wl_display_dispatch_pending(_wlDisplay) < 0)
        [self connectionFailed];

    [self runAfterDispatchBlocks];
    WL.wl_display_flush(_wlDisplay);
}

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue
{
    [self processPendingEvents];

    // NSDisplay's queue handling, without X11Display's X event processing.
    struct objc_super superInfo = {self, [NSDisplay class]};
    return ((NSEvent * (*) (struct objc_super *, SEL, NSEventMask, NSDate *,
                            NSRunLoopMode, BOOL)) objc_msgSendSuper)(
            &superInfo, _cmd, mask, untilDate, mode, dequeue);
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
    if (strcmp(interface, "wl_compositor") == 0 && _compositor == NULL) {
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
                           version: MIN(version, 3)
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
    } else if (strcmp(interface, "zwp_pointer_gestures_v1") == 0 && _pointerGestures == NULL) {
        // Version 2 adds the release request.
        _pointerGesturesName = name;
        _pointerGestures = [self bindGlobal: name interface: &zwp_pointer_gestures_v1_interface
                                    version: MIN(version, 2) kind: 0 object: nil];
        [self attachPinchGesture];
    } else if (strcmp(interface, "wl_seat") == 0 && _seat == NULL) {
        // Version 4 adds wl_keyboard.repeat_info, 5 wl_pointer.frame.
        _seat = [self bindGlobal: name
                       interface: &wl_seat_interface
                         version: MIN(version, 5)
                            kind: WaylandObjectSeat
                          object: self];
    } else if (strcmp(interface, "zxdg_output_manager_v1") == 0 && _logicalOutputManager == NULL) {
        _logicalOutputManagerName = name;
        _logicalOutputManager = [self bindGlobal: name interface: &zxdg_output_manager_v1_interface
                                        version: MIN(version, 3) kind: 0 object: nil];
        for (WaylandOutput *output in _outputs) [self attachLogicalOutput: output];
    } else if (strcmp(interface, "wl_output") == 0) {
        WaylandOutput *output = [[WaylandOutput new] autorelease];
        output->_globalName = name;
        output->_display = self;
        output->_current.scale = output->_pending.scale = 1;
        output->_version = MIN(version, 2);
        output->_pendingModes = [NSMutableArray new];
        output->_modes = [NSArray new];
        // Version 2 has scale and done.
        output->_proxy = [self bindGlobal: name
                                interface: &wl_output_interface
                                  version: output->_version
                                     kind: WaylandObjectOutput
                                   object: output];
        if (output->_proxy != NULL) {
            [_outputs addObject: output];
            [self attachLogicalOutput: output];
        }
    }
}

- (void) attachLogicalOutput: (WaylandOutput *) output {
    if (!_logicalOutputManager || output->_logicalProxy) return;
    struct wl_proxy *manager = _logicalOutputManager;
    // Typed new_id inherits the server-side manager version. A core v1 output
    // cannot receive wl_output.done, so it needs a genuinely v2 factory binding.
    if (output->_version < 2 && WL.wl_proxy_get_version(manager) >= 3) {
        if (!_legacyLogicalOutputManager)
            _legacyLogicalOutputManager = [self bindGlobal: _logicalOutputManagerName
                    interface: &zxdg_output_manager_v1_interface version: 2 kind: 0 object: nil];
        manager = _legacyLogicalOutputManager;
    }
    if (!manager) return;
    output->_logicalVersion = WL.wl_proxy_get_version(manager);
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *)output->_proxy}};
    output->_logicalProxy = WaylandCreateObject(manager, WP_LOGICAL_MANAGER_GET_OUTPUT,
            &zxdg_output_v1_interface, args, WaylandObjectLogicalOutput, output);
}

- (void) logicalOutputEvent: (uint32_t) opcode output: (WaylandOutput *) output
                 arguments: (union wl_argument *) args {
    switch (opcode) {
    case WP_LOGICAL_OUTPUT_EV_POSITION:
        output->_logicalPending.x = args[0].i;
        output->_logicalPending.y = args[1].i;
        output->_logicalPending.hasPosition = YES;
        break;
    case WP_LOGICAL_OUTPUT_EV_SIZE:
        if (args[0].i > 0 && args[1].i > 0) {
            output->_logicalPending.width = args[0].i;
            output->_logicalPending.height = args[1].i;
            output->_logicalPending.hasSize = YES;
        }
        break;
    case WP_LOGICAL_OUTPUT_EV_DONE:
        if (output->_logicalVersion < 3) {
            output->_logicalCurrent = output->_logicalPending;
            [self invalidateScreens];
        }
        break;
    }
}

- (struct wl_proxy *) newFractionalScaleForSurface: (struct wl_proxy *) surface owner: (id<WaylandFractionalScaleOwner>) owner {
    if (!_fractionalScaleManager || !_viewporter || !surface) return NULL;
    union wl_argument args[] = {{.o = NULL}, {.o = (struct wl_object *)surface}};
    return WaylandCreateObject(_fractionalScaleManager, WP_FRACTIONAL_MANAGER_GET_SCALE,
        &wp_fractional_scale_v1_interface, args, WaylandObjectFractionalScale, owner);
}

- (void) registryGlobalRemoved: (uint32_t) name {
    if (_pointerGestures && name == _pointerGesturesName) {
        [self detachPinchGesture];
        if (WL.wl_proxy_get_version(_pointerGestures) >= 2)
            WaylandMarshal(_pointerGestures, WP_GESTURES_RELEASE, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        else
            WL.wl_proxy_destroy(_pointerGestures);
        _pointerGestures = NULL; _pointerGesturesName = 0;
        return;
    }
    if (_fractionalScaleManager && name == _fractionalScaleManagerName) {
        WaylandMarshal(_fractionalScaleManager, WP_FRACTIONAL_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _fractionalScaleManager = NULL; _fractionalScaleManagerName = 0;
        return; // Existing surface preferences survive factory removal.
    }
    if (_viewporter && name == _viewporterName) {
        WaylandMarshal(_viewporter, WP_VIEWPORTER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _viewporter = NULL; _viewporterName = 0;
        return; // Existing viewport objects remain usable.
    }
    if (_logicalOutputManager && name == _logicalOutputManagerName) {
        if (_legacyLogicalOutputManager)
            WaylandMarshal(_legacyLogicalOutputManager, WP_LOGICAL_MANAGER_DESTROY, NULL,
                           WL_MARSHAL_FLAG_DESTROY, NULL);
        WaylandMarshal(_logicalOutputManager, WP_LOGICAL_MANAGER_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
        _logicalOutputManager = _legacyLogicalOutputManager = NULL;
        _logicalOutputManagerName = 0;
        // Existing logical-output children survive factory removal.
        return;
    }
    for (WaylandOutput *output in _outputs) {
        if (output->_globalName == name) {
            for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
                [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) outputRemoved: output->_proxy];
            if (output->_logicalProxy)
                WaylandMarshal(output->_logicalProxy, WP_LOGICAL_OUTPUT_DESTROY, NULL,
                               WL_MARSHAL_FLAG_DESTROY, NULL);
            [_draggingManager outputRemoved: output->_proxy];
            WL.wl_proxy_destroy(output->_proxy);
            [_outputs removeObject: output];
            [self invalidateScreens];
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

- (void) invalidateScreens {
    [_screens release];
    _screens = nil;
}

- (void) publishOutput: (WaylandOutput *) output {
    output->_current = output->_pending;
    if (output->_logicalVersion >= 3)
        output->_logicalCurrent = output->_logicalPending;
    [output->_modes release];
    output->_modes = [output->_pendingModes copy];
    [self invalidateScreens];
    [_draggingManager outputsChanged];
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) scheduleScaleUpdate];
}

- (void) outputEvent: (uint32_t) opcode
              output: (WaylandOutput *) output
           arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_OUTPUT_EV_GEOMETRY:
        // Geometry's transform is its eighth argument; dispatch avoids native
        // variadic/listener ABI differences. Ignore unknown enum values.
        if (args[7].i >= 0 && args[7].i <= 7)
            output->_pending.transform = args[7].i;
        break;
    case WP_OUTPUT_EV_MODE: {
        if (args[1].i <= 0 || args[2].i <= 0 || args[3].i < 0)
            return;
        if (args[0].u & WP_OUTPUT_MODE_CURRENT) {
            output->_pending.width = args[1].i;
            output->_pending.height = args[2].i;
            output->_pending.refresh = args[3].i;
        }
        NSDictionary *mode = @{
            @"Width" : @(args[1].i),
            @"Height" : @(args[2].i),
            @"Depth" : @(24),
            @"RefreshRate" : @(args[3].i / 1000.0)
        };
        if (![output->_pendingModes containsObject: mode])
            [output->_pendingModes addObject: mode];
        break;
    }
    case WP_OUTPUT_EV_SCALE:
        output->_pending.scale = MAX(args[0].i, 1);
        break;
    case WP_OUTPUT_EV_DONE:
        [self publishOutput: output];
        return;
    default:
        return;
    }
    // Version 1 has no done event. Do not leave the fallback screen cached.
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

    case WaylandObjectPointer:
        [self pointerEvent: opcode arguments: args];
        break;

    case WaylandObjectPinchGesture:
        [self pinchEvent: opcode arguments: args];
        break;

    case WaylandObjectKeyboardSync:
        if (proxy == _modifierSync && opcode == WP_CALLBACK_EV_DONE)
            [self flushPendingModifier];
        break;

    case WaylandObjectKeyboard:
        [self keyboardEvent: opcode arguments: args];
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

    if ((capabilities & WP_SEAT_CAPABILITY_POINTER) && _pointer == NULL) {
        _pointer = WaylandCreateObject(_seat, WP_SEAT_GET_POINTER,
                                       &wl_pointer_interface, args,
                                       WaylandObjectPointer, self);
        [self attachPinchGesture];
    } else if (!(capabilities & WP_SEAT_CAPABILITY_POINTER) && _pointer != NULL) {
        [self detachPinchGesture];
        [_draggingManager cancel];
        [self consumeDragPress];
        [self releaseInputDevice: &_pointer opcode: WP_POINTER_RELEASE];
        _pointerWindow = nil;
        _pointerEnterSerial = 0;
        _pressedButtons = 0;
        _pendingScrollX = _pendingScrollY = 0;
        _pendingScrollWindow = nil;
        _pendingScrollActive = NO;
        _wlLastClickWindow = nil;
        [_buttonClickCounts removeAllObjects];
    }

    if ((capabilities & WP_SEAT_CAPABILITY_KEYBOARD) && _keyboard == NULL) {
        args[0].o = NULL;
        _keyboard = WaylandCreateObject(_seat, WP_SEAT_GET_KEYBOARD,
                                        &wl_keyboard_interface, args,
                                        WaylandObjectKeyboard, self);
    } else if (!(capabilities & WP_SEAT_CAPABILITY_KEYBOARD) && _keyboard != NULL) {
        [self releaseInputDevice: &_keyboard opcode: WP_KEYBOARD_RELEASE];
        [self stopKeyRepeat];
        _keyboardWindow = nil;
        [self resetKeyboardModifiers];
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

#pragma mark - Pointer

- (void) pointerEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    if (opcode != WP_POINTER_EV_AXIS && opcode != WP_POINTER_EV_FRAME)
        [self postPendingScroll];
    [self flushPendingModifier];
    switch (opcode) {
    case WP_POINTER_EV_ENTER:
        _pointerEnterSerial = args[0].u;
        _pointerWindow =
                [self windowForSurface: (struct wl_proxy *) args[1].o];
        _pointerSurfacePoint = CGPointMake(wl_fixed_to_double(args[2].f),
                                           wl_fixed_to_double(args[3].f));
        [_pointerWindow setLastKnownCursorPosition:
                                [_pointerWindow transformPoint: _pointerSurfacePoint]];
        [self performAfterDispatch: ^{ [self applyCursor]; }];
        break;

    case WP_POINTER_EV_LEAVE:
        _pressedButtons = 0;
        [_buttonClickCounts removeAllObjects];
        [self consumeDragPress];
        _lastMouseLocation = [self mouseLocation];
        _pointerWindow = nil;
        _pointerEnterSerial = 0;
        _pendingScrollX = _pendingScrollY = 0;
        _pendingScrollWindow = nil;
        _pendingScrollActive = NO;
        break;

    case WP_POINTER_EV_MOTION:
        [self pointerMotionToX: wl_fixed_to_double(args[1].f)
                             y: wl_fixed_to_double(args[2].f)];
        break;

    case WP_POINTER_EV_BUTTON: {
        BOOL firstPress = _pressedButtons == 0;
        if (_pressedButtons == 0 && [_pointerWindow decorationButton: args[2].u
                pressed: args[3].u == WP_POINTER_BUTTON_STATE_PRESSED
                serial: args[0].u atPoint: _pointerSurfacePoint])
            break;
        if (args[3].u == WP_POINTER_BUTTON_STATE_PRESSED) {
            _inputSerial = args[0].u;
            [_generalPasteboard inputAvailable];
            [_inputEvent release];
            _inputEvent = nil;
            _inputWindow = nil;
        }
        [self pointerButton: args[2].u
                    pressed: args[3].u == WP_POINTER_BUTTON_STATE_PRESSED
                       time: args[1].u];
        if (firstPress && args[3].u == WP_POINTER_BUTTON_STATE_PRESSED && _inputEvent != nil) {
            [self consumeDragPress];
            _dragPressEvent = [_inputEvent retain];
            _dragPressWindow = _pointerWindow;
            _dragPressSerial = args[0].u;
            _dragPressButton = args[2].u;
        } else if (args[3].u != WP_POINTER_BUTTON_STATE_PRESSED &&
                   args[2].u == _dragPressButton) {
            [self consumeDragPress];
        }
        break;

    }
    case WP_POINTER_EV_AXIS:
        [self pointerAxis: args[1].u value: wl_fixed_to_double(args[2].f)];
        break;

    case WP_POINTER_EV_FRAME:
        [self postPendingScroll];
        break;
    }
}

- (void) pointerMotionToX: (CGFloat) x y: (CGFloat) y {
    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return;

    _pointerSurfacePoint = CGPointMake(x, y);
    NSPoint location = [window transformPoint: _pointerSurfacePoint];
    NSPoint last = [window mouseLocationOutsideOfEventStream];
    [window setLastKnownCursorPosition: location];

    if (_pressedButtons == 0 && [window isDecorationPoint: _pointerSurfacePoint]) {
        [self performAfterDispatch: ^{ [self applyCursor]; }];
        return;
    }

    NSWindow *delegate = [window delegate];
    NSEventType type = NSMouseMoved;
    // AppKit here has no NSOtherMouseDragged: other buttons move the mouse.
    if (_pressedButtons & 1)
        type = NSLeftMouseDragged;
    else if (_pressedButtons & 2)
        type = NSRightMouseDragged;

    if (type != NSMouseMoved || [delegate acceptsMouseMovedEvents]) {
        NSEvent *event = [NSEvent mouseEventWithType: type
                                            location: location
                                       modifierFlags: [self currentModifierFlags]
                                              window: delegate
                                          clickCount: 1
                                              deltaX: location.x - last.x
                                              deltaY: location.y - last.y];
        // Not coalesced with -discardEventsMatchingMask:beforeEvent:, which
        // currently removes every older queued event, mouse-downs included.
        [self postEvent: event atStart: NO];
    }

    [self performAfterDispatch: ^{
      if ([window delegate] != nil)
          [[window delegate] platformWindowSetCursorEvent: window];
    }];
}

- (void) pointerButton: (uint32_t) button pressed: (BOOL) pressed
                  time: (uint32_t) time {
    NSUInteger mask;
    NSInteger number;
    NSEventType downType, upType;

    switch (button) {
    case WP_BTN_LEFT:
        mask = 1, number = 0, downType = NSLeftMouseDown, upType = NSLeftMouseUp;
        break;
    case WP_BTN_RIGHT:
        mask = 2, number = 1, downType = NSRightMouseDown, upType = NSRightMouseUp;
        break;
    case WP_BTN_MIDDLE:
        mask = 4, number = 2, downType = NSOtherMouseDown, upType = NSOtherMouseUp;
        break;
    default:
        mask = 8, number = (NSInteger) button - WP_BTN_LEFT;
        downType = NSOtherMouseDown, upType = NSOtherMouseUp;
        break;
    }

    if (pressed)
        _pressedButtons |= mask;
    else
        _pressedButtons &= ~mask;

    NSInteger eventClickCount = [[_buttonClickCounts objectForKey: @(button)] integerValue];
    if (!pressed)
        [_buttonClickCounts removeObjectForKey: @(button)];
    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return;

    if (pressed) {
        // Group clicks only on the same button/window and within four logical
        // pixels of the preceding press. Unsigned subtraction handles timestamp
        // wrap without depending on the wall clock or dispatch latency.
        CGFloat dx = _pointerSurfacePoint.x - _wlLastClickPoint.x;
        CGFloat dy = _pointerSurfacePoint.y - _wlLastClickPoint.y;
        if (_wlLastClickWindow == window && _wlLastClickButton == button &&
            (uint32_t) (time - _wlLastClickTime) < [self doubleClickInterval] * 1000 &&
            dx * dx + dy * dy <= 16 && _clickCount < NSIntegerMax)
            _clickCount++;
        else
            _clickCount = 1;
        _wlLastClickTime = time;
        _wlLastClickButton = button;
        _wlLastClickWindow = window;
        _wlLastClickPoint = _pointerSurfacePoint;
        if (_buttonClickCounts == nil)
            _buttonClickCounts = [NSMutableDictionary new];
        [_buttonClickCounts setObject: @(_clickCount) forKey: @(button)];
        eventClickCount = _clickCount;
    }

    NSEvent *event = [NSEvent
            mouseEventWithType: pressed ? downType : upType
                      location: [window transformPoint: _pointerSurfacePoint]
                 modifierFlags: [self currentModifierFlags]
                        window: [window delegate]
                    clickCount: eventClickCount
                        deltaX: 0.0
                        deltaY: 0.0];
    [(NSEvent_mouse *) event _setButtonNumber: number];
    if (pressed) {
        _inputEvent = [event retain];
        _inputWindow = window;
    }
    [self postEvent: event atStart: NO];
}

- (void) pointerAxis: (uint32_t) axis value: (CGFloat) value {
    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return;

    // One wheel notch is 10 units, scrolling down is positive; the X11 backend
    // reports a notch up as deltaY 1.
    CGFloat delta = -value / 10.0;
    if (axis != WP_POINTER_AXIS_HORIZONTAL_SCROLL &&
        axis != WP_POINTER_AXIS_VERTICAL_SCROLL)
        return;
    if (!_pendingScrollActive) {
        _pendingScrollWindow = window;
        _pendingScrollSurfacePoint = _pointerSurfacePoint;
        _pendingScrollModifiers = [self currentModifierFlags];
        _pendingScrollActive = YES;
    }
    if (axis == WP_POINTER_AXIS_HORIZONTAL_SCROLL)
        _pendingScrollX += delta;
    else if (axis == WP_POINTER_AXIS_VERTICAL_SCROLL)
        _pendingScrollY += delta;

    // wl_pointer.frame was added in version 5. Older seats deliver each axis
    // event independently, so preserve their immediate behavior.
    if (WL.wl_proxy_get_version(_pointer) < 5)
        [self postPendingScroll];
}

- (void) postPendingScroll {
    CGFloat deltaX = _pendingScrollX;
    CGFloat deltaY = _pendingScrollY;
    WaylandWindow *window = _pendingScrollWindow;
    CGPoint surfacePoint = _pendingScrollSurfacePoint;
    NSUInteger modifiers = _pendingScrollModifiers;
    _pendingScrollX = _pendingScrollY = 0;
    _pendingScrollWindow = nil;
    _pendingScrollActive = NO;
    if (deltaX == 0 && deltaY == 0)
        return;

    if (window == nil)
        return;

    NSEvent *event = [NSEvent
            mouseEventWithType: NSScrollWheel
                      location: [window transformPoint: surfacePoint]
                 modifierFlags: modifiers
                        window: [window delegate]
                    clickCount: 1
                        deltaX: deltaX
                        deltaY: deltaY];
    [self postEvent: event atStart: NO];
}

#pragma mark - Pinch gestures

- (void) attachPinchGesture {
    if (_pointerGestures == NULL || _pointer == NULL || _pinchGesture != NULL)
        return;
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _pointer}};
    _pinchGesture = WaylandCreateObject(_pointerGestures, WP_GESTURES_GET_PINCH,
                                        &zwp_pointer_gesture_pinch_v1_interface, args,
                                        WaylandObjectPinchGesture, self);
}

- (void) detachPinchGesture {
    if (_pinchGesture == NULL)
        return;
    [self postPinchPhase: NSEventPhaseCancelled];
    WaylandMarshal(_pinchGesture, WP_PINCH_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _pinchGesture = NULL;
}

- (void) postGesture: (NSEventType) type
               phase: (NSEventPhase) phase
       magnification: (CGFloat) magnification
            rotation: (float) rotation
{
    WaylandWindow *window = _pinchWindow;
    NSEvent *event = [[[NSEvent_gesture alloc]
             initWithType: type
                 location: [window transformPoint: _pointerSurfacePoint]
            modifierFlags: [self currentModifierFlags]
                   window: [window delegate]
                    phase: phase
            magnification: magnification
                 rotation: rotation] autorelease];
    [self postEvent: event atStart: NO];
}

// Ends an active pinch; a no-op when none is in progress.
- (void) postPinchPhase: (NSEventPhase) phase {
    if (_pinchWindow == nil)
        return;
    [self postGesture: NSEventTypeMagnify phase: phase magnification: 0 rotation: 0];
    [self postGesture: NSEventTypeRotate phase: phase magnification: 0 rotation: 0];
    _pinchWindow = nil;
}

// A pinch reports its scale relative to where the fingers started and its
// rotation in degrees clockwise since the last update. AppKit events carry the
// change in magnification and counterclockwise degrees.
- (void) pinchEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    [self postPendingScroll];
    switch (opcode) {
    case WP_PINCH_EV_BEGIN:
        _pinchWindow = [self windowForSurface: (struct wl_proxy *) args[2].o];
        _pinchScale = 1;
        if (_pinchWindow == nil)
            break;
        [self postGesture: NSEventTypeMagnify phase: NSEventPhaseBegan magnification: 0 rotation: 0];
        [self postGesture: NSEventTypeRotate phase: NSEventPhaseBegan magnification: 0 rotation: 0];
        break;

    case WP_PINCH_EV_UPDATE: {
        if (_pinchWindow == nil)
            break;
        CGFloat scale = wl_fixed_to_double(args[3].f);
        float rotation = -wl_fixed_to_double(args[4].f);
        if (scale != _pinchScale)
            [self postGesture: NSEventTypeMagnify phase: NSEventPhaseChanged
                magnification: scale - _pinchScale rotation: 0];
        if (rotation != 0)
            [self postGesture: NSEventTypeRotate phase: NSEventPhaseChanged magnification: 0 rotation: rotation];
        _pinchScale = scale;
        break;
    }

    case WP_PINCH_EV_END:
        [self postPinchPhase: args[2].i ? NSEventPhaseCancelled : NSEventPhaseEnded];
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

- (void) warpMouse: (NSPoint) position {
    // Wayland clients can't move the pointer.
}

- (void) grabMouse: (BOOL) doGrab {
    // Needs the pointer-constraints protocol; not supported yet.
}

#pragma mark - Keyboard

// Physical identity is metadata only: the compositor's following modifiers
// event is authoritative for effective flags (including locks/layout changes).
static int modifierCarbonKeycode(xkb_keysym_t sym) {
    switch (sym) {
    case XKB_KEY_Shift_L: return kVK_Shift;
    case XKB_KEY_Shift_R: return kVK_RightShift;
    case XKB_KEY_Control_L: return kVK_Control;
    case XKB_KEY_Control_R: return kVK_RightControl;
    case XKB_KEY_Alt_L: return kVK_Option;
    case XKB_KEY_Alt_R: return kVK_RightOption;
    case XKB_KEY_Super_L: case XKB_KEY_Meta_L: return kVK_Command;
    case XKB_KEY_Super_R: case XKB_KEY_Meta_R: return 0x36; // Right Command.
    case XKB_KEY_Caps_Lock: return kVK_CapsLock;
    case XKB_KEY_ISO_Level3_Shift: case XKB_KEY_Mode_switch: return kVK_Function;
    default: return -1;
    }
}

// Device-dependent NSEvent bits, defined by IOKit's IOLLEvent.h. The aggregate
// high bits still come exclusively from the compositor's XKB modifier mask.
static NSUInteger modifierDeviceMask(int code) {
    switch (code) {
    case kVK_Control: return 0x0001;
    case kVK_Shift: return 0x0002;
    case kVK_RightShift: return 0x0004;
    case kVK_Command: return 0x0008;
    case 0x36: return 0x0010;
    case kVK_Option: return 0x0020;
    case kVK_RightOption: return 0x0040;
    case kVK_RightControl: return 0x2000;
    default: return 0;
    }
}

- (void) cancelPendingModifier {
    if (_modifierSync != NULL) {
        WL.wl_proxy_destroy(_modifierSync);
        _modifierSync = NULL;
    }
    _hasModifierKeycode = NO;
}

- (void) postModifierKeycode: (unsigned short) code {
    NSWindow *delegate = [_keyboardWindow delegate];
    if (delegate == nil)
        return;
    NSEvent *event = [NSEvent keyEventWithType: NSFlagsChanged
            location: [_keyboardWindow mouseLocationOutsideOfEventStream]
            modifierFlags: [self currentModifierFlags] timestamp: 0.0
            windowNumber: [delegate windowNumber] context: nil
            characters: @"" charactersIgnoringModifiers: @""
            isARepeat: NO keyCode: code];
    [self postEvent: event atStart: NO];
}

- (void) flushPendingModifier {
    if (_hasModifierKeycode)
        [self postModifierKeycode: _modifierKeycode];
    [self cancelPendingModifier];
}

- (void) classifyHeldKeys {
    for (NSNumber *key in [_heldKeyIdentities allKeys]) {
        int identity = modifierCarbonKeycode(WL.xkb_state_key_get_one_sym(
                _xkbState, [key unsignedIntValue]));
        [_heldKeyIdentities setObject: @(identity) forKey: key];
    }
    _classifyHeldKeys = NO;
}

- (void) resetKeyboardModifiers {
    [self cancelPendingModifier];
    [_heldKeyIdentities removeAllObjects];
    _syncModifierFlags = NO;
    _classifyHeldKeys = NO;
    if (_xkbState != NULL)
        WL.xkb_state_update_mask(_xkbState, 0, 0, 0, 0, 0, 0);
}

- (void) keyboardEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    [self postPendingScroll];
    switch (opcode) {
    case WP_KEYBOARD_EV_KEYMAP:
        [self keymapWithFormat: args[0].u fd: args[1].h size: args[2].u];
        break;

    case WP_KEYBOARD_EV_ENTER: {
        [self resetKeyboardModifiers];
        _keyboardWindow = [self windowForSurface: (struct wl_proxy *) args[1].o];
        if (_heldKeyIdentities == nil)
            _heldKeyIdentities = [NSMutableDictionary new];
        struct wl_array *keys = args[2].a;
        for (size_t i = 0; i < keys->size / sizeof(uint32_t); i++) {
            uint32_t raw = ((uint32_t *)keys->data)[i];
            [_heldKeyIdentities setObject: @(-1) forKey: @(raw + 8)];
        }
        // Enter is followed by modifiers: classify under that current group,
        // without inventing key presses for keys held before focus arrived.
        _classifyHeldKeys = YES;
        _syncModifierFlags = YES;
        break;
    }

    case WP_KEYBOARD_EV_LEAVE:
        _keyboardWindow = nil;
        [self stopKeyRepeat];
        [self resetKeyboardModifiers];
        break;

    case WP_KEYBOARD_EV_KEY: {
        if (_xkbState == NULL || _keyboardWindow == nil)
            break;
        [self flushPendingModifier];
        xkb_keycode_t keycode = args[2].u + 8;
        BOOL pressed = args[3].u == WP_KEYBOARD_KEY_STATE_PRESSED;
        if (pressed) {
            _inputSerial = args[0].u;
            [_generalPasteboard inputAvailable];
            [_inputEvent release];
            _inputEvent = nil;
            _inputWindow = nil;
        }

        NSNumber *held = [_heldKeyIdentities objectForKey: @(keycode)];
        int modifier = held != nil ? [held intValue] : modifierCarbonKeycode(
                WL.xkb_state_key_get_one_sym(_xkbState, keycode));
        if (pressed)
            [_heldKeyIdentities setObject: @(modifier) forKey: @(keycode)];
        else
            [_heldKeyIdentities removeObjectForKey: @(keycode)];
        if (modifier >= 0) {
            _modifierKeycode = modifier;
            _hasModifierKeycode = YES;
            // A mask-changing key is followed by modifiers; an overlapping
            // modifier need not be. A sync drains the compositor's already
            // queued events even across socket reads before the idle fallback.
            // It is not a keyboard frame or a fence for future input events.
            union wl_argument syncArgs[1] = {{.o = NULL}};
            _modifierSync = WaylandCreateObject((struct wl_proxy *)_wlDisplay,
                    WP_DISPLAY_SYNC, &wl_callback_interface, syncArgs,
                    WaylandObjectKeyboardSync, self);
            [self flush];
            break; // Modifiers are neither text nor repeatable keys.
        }
        [self postKeyEventForKeycode: keycode pressed: pressed repeat: NO];
        if (pressed && _repeatRate > 0 &&
            WL.xkb_keymap_key_repeats(_xkbKeymap, keycode))
            [self startKeyRepeat: keycode];
        else if (!pressed && keycode == _repeatKeycode)
            [self stopKeyRepeat];
        break;
    }

    case WP_KEYBOARD_EV_MODIFIERS: {
        NSUInteger oldFlags = [self currentModifierFlags];
        if (_xkbState != NULL) {
            WL.xkb_state_update_mask(_xkbState, args[1].u, args[2].u, args[3].u,
                                     0, 0, args[4].u);
            if (_classifyHeldKeys)
                [self classifyHeldKeys];
        }
        if (_hasModifierKeycode)
            [self flushPendingModifier];
        else if (_syncModifierFlags || [self currentModifierFlags] != oldFlags)
            [self postModifierKeycode: 0xFFFF];
        _syncModifierFlags = NO;
        break;
    }

    case WP_KEYBOARD_EV_REPEAT_INFO:
        _repeatRate = args[0].i;
        _repeatDelay = args[1].i;
        if (_repeatRate <= 0)
            [self stopKeyRepeat];
        break;
    }
}

- (void) keymapWithFormat: (uint32_t) format fd: (int) fd size: (uint32_t) size {
    char *map = MAP_FAILED;

    if (_xkbContext == NULL) {
        // Already logged at startup.
    } else if (format != WP_KEYBOARD_KEYMAP_FORMAT_XKB_V1 || size == 0) {
        NSLog(@"Wayland backend: unsupported keymap (format %u, %u bytes), "
              @"keyboard input is disabled",
              format, size);
    } else {
        map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (map == MAP_FAILED)
            NSLog(@"Wayland backend: cannot map the keymap: %s", strerror(errno));
    }
    close(fd);
    if (map == MAP_FAILED)
        return;

    struct xkb_keymap *keymap = WL.xkb_keymap_new_from_buffer(
            _xkbContext, map, strnlen(map, size), XKB_KEYMAP_FORMAT_TEXT_V1,
            XKB_KEYMAP_COMPILE_NO_FLAGS);
    munmap(map, size);

    struct xkb_state *state = keymap != NULL ? WL.xkb_state_new(keymap) : NULL;
    if (state == NULL) {
        NSLog(@"Wayland backend: cannot use the compositor's keymap");
        if (keymap != NULL)
            WL.xkb_keymap_unref(keymap);
        return;
    }

    [self stopKeyRepeat];
    if (_xkbState != NULL)
        WL.xkb_state_unref(_xkbState);
    if (_xkbKeymap != NULL)
        WL.xkb_keymap_unref(_xkbKeymap);
    _xkbKeymap = keymap;
    _xkbState = state;
    [self cancelPendingModifier];
    // Preserve press-time identities through keymap changes until release.
    // Only enter-seeded keys need classification under the current group.
    _syncModifierFlags = _keyboardWindow != nil;
}

- (BOOL) isModifierActive: (const char *) name {
    return _xkbState != NULL &&
           WL.xkb_state_mod_name_is_active(_xkbState, name,
                                           XKB_STATE_MODS_EFFECTIVE) > 0;
}

// The same mapping as -[X11Display modifierFlagsForState:].
- (NSUInteger) currentModifierFlags {
    NSUInteger flags = 0;
    for (NSNumber *identity in [_heldKeyIdentities allValues])
        flags |= modifierDeviceMask([identity intValue]);

    if ([self isModifierActive: XKB_MOD_NAME_SHIFT])
        flags |= NSShiftKeyMask;
    if ([self isModifierActive: XKB_MOD_NAME_CTRL])
        flags |= NSControlKeyMask;
    if ([self isModifierActive: XKB_MOD_NAME_CAPS])
        flags |= NSAlphaShiftKeyMask;
    if ([self isModifierActive: XKB_MOD_NAME_LOGO])
        flags |= NSCommandKeyMask;
    if ([self isModifierActive: XKB_MOD_NAME_ALT])
        flags |= NSAlternateKeyMask;
    if ([self isModifierActive: "Mod5"]) // AltGr
        flags |= NSFunctionKeyMask;

    return flags;
}

- (uint32_t) codepointForKeysym: (xkb_keysym_t) keysym {
    // X11KeySymToUCS knows AppKit's function key codes; XKB keysyms are X11's.
    uint32_t codepoint = X11KeySymToUCS(keysym);
    if (codepoint == 0)
        codepoint = WL.xkb_keysym_to_utf32(keysym);
    return codepoint;
}

- (xkb_keysym_t) keysymForKeycode: (xkb_keycode_t) keycode level: (xkb_level_index_t) level {
    xkb_layout_index_t layout = WL.xkb_state_key_get_layout(_xkbState, keycode);
    if (layout == XKB_LAYOUT_INVALID)
        return XKB_KEY_NoSymbol;

    const xkb_keysym_t *keysyms = NULL;
    int count = WL.xkb_keymap_key_get_syms_by_level(_xkbKeymap, keycode, layout,
                                                    level, &keysyms);
    if (count <= 0 && level > 0)
        count = WL.xkb_keymap_key_get_syms_by_level(_xkbKeymap, keycode, layout,
                                                    0, &keysyms);
    return count > 0 ? keysyms[0] : XKB_KEY_NoSymbol;
}

- (void) postKeyEventForKeycode: (xkb_keycode_t) keycode
                        pressed: (BOOL) pressed
                         repeat: (BOOL) repeat
{
    WaylandWindow *window = _keyboardWindow;
    if (window == nil) {
        id platformWindow = [[NSApp keyWindow] platformWindow];
        if ([platformWindow isKindOfClass: [WaylandWindow class]])
            window = platformWindow;
    }
    NSWindow *delegate = [window delegate];
    if (delegate == nil)
        return;

    xkb_keysym_t keysym = WL.xkb_state_key_get_one_sym(_xkbState, keycode);
    uint32_t special = X11KeySymToUCS(keysym);
    NSString *characters;

    if (special >= 0xF700 && special <= 0xF8FF) {
        characters = stringWithCodepoint(special);
    } else {
        char buffer[64];
        int length = WL.xkb_state_key_get_utf8(_xkbState, keycode, buffer,
                                               sizeof(buffer));
        if (length >= (int) sizeof(buffer)) {
            char *larger = malloc(length + 1);
            if (larger == NULL)
                return;
            WL.xkb_state_key_get_utf8(_xkbState, keycode, larger, length + 1);
            characters = [NSString stringWithUTF8String: larger];
            free(larger);
        } else {
            characters = length > 0 ? [NSString stringWithUTF8String: buffer]
                                    : @"";
        }
    }

    // AppKit ignores every modifier except Shift here.
    xkb_level_index_t level = [self isModifierActive: XKB_MOD_NAME_SHIFT] ? 1 : 0;
    NSString *charactersIgnoringModifiers = stringWithCodepoint(
            [self codepointForKeysym: [self keysymForKeycode: keycode
                                                       level: level]]);

    NSEvent *event = [NSEvent
                keyEventWithType: pressed ? NSKeyDown : NSKeyUp
                        location: [window mouseLocationOutsideOfEventStream]
                   modifierFlags: [self currentModifierFlags]
                       timestamp: 0.0
                    windowNumber: [delegate windowNumber]
                         context: nil
                      characters: characters ? characters : @""
     charactersIgnoringModifiers: charactersIgnoringModifiers
                       isARepeat: repeat
                         keyCode: keycode < 256 ? x11ToCarbon[keycode] : 0];
    if (pressed && !repeat) {
        _inputEvent = [event retain];
        _inputWindow = window;
    }
    [self postEvent: event atStart: NO];
}

- (void) startKeyRepeat: (xkb_keycode_t) keycode {
    [self stopKeyRepeat];
    _repeatKeycode = keycode;

    CFRunLoopTimerContext context = {.version = 0, .info = self};
    _repeatTimer = CFRunLoopTimerCreate(
            NULL, CFAbsoluteTimeGetCurrent() + _repeatDelay / 1000.0,
            1.0 / _repeatRate, 0, 0, repeatTimerCallback, &context);
    CFRunLoopAddTimer(CFRunLoopGetMain(), _repeatTimer, kCFRunLoopCommonModes);
}

- (void) stopKeyRepeat {
    if (_repeatTimer != NULL) {
        CFRunLoopTimerInvalidate(_repeatTimer);
        CFRelease(_repeatTimer);
        _repeatTimer = NULL;
    }
    _repeatKeycode = 0;
}

- (void) repeatKey {
    if (_xkbState == NULL || _repeatKeycode == 0)
        return;
    [self postKeyEventForKeycode: _repeatKeycode pressed: YES repeat: YES];
    // A timer doesn't end -[NSRunLoop runMode:beforeDate:], so wake the event loop.
    CFRunLoopStop(CFRunLoopGetMain());
}

- (int) keyboardLayoutId {
    if (_xkbState == NULL)
        return -1;
    return (int) WL.xkb_state_serialize_layout(_xkbState,
                                               XKB_STATE_LAYOUT_EFFECTIVE);
}

- (void) keyboardLayoutName: (NSString **) name fullName: (NSString **) fullName {
    NSString *layoutName = @"?";

    int layout = [self keyboardLayoutId];
    if (layout >= 0) {
        const char *xkbName = WL.xkb_keymap_layout_get_name(_xkbKeymap, layout);
        if (xkbName != NULL)
            layoutName = [NSString stringWithUTF8String: xkbName];
    }
    if (name != NULL)
        *name = layoutName;
    if (fullName != NULL)
        *fullName = layoutName;
}

// The same two-table layout (unshifted, shifted) as -[X11Display keyboardLayout:].
- (UCKeyboardLayout *) keyboardLayout: (uint32_t *) byteLength {
    struct Layout {
        UCKeyboardLayout layout;
        UCKeyModifiersToTableNum modifierVariants;
        UInt8 secondTableNum, thirdTableNum;
        UCKeyToCharTableIndex tableIndex;
        UInt32 secondTableOffset;
        UCKeyOutput table1[128];
        UCKeyOutput table2[128];
    };

    if (byteLength != NULL)
        *byteLength = 0;
    if (_xkbState == NULL)
        return NULL;

    struct Layout *layout = calloc(1, sizeof(struct Layout));
    if (layout == NULL)
        return NULL;

    layout->layout.keyLayoutHeaderFormat = kUCKeyLayoutHeaderFormat;
    layout->layout.keyboardTypeCount = 1;
    layout->layout.keyboardTypeList[0].keyModifiersToTableNumOffset =
            offsetof(struct Layout, modifierVariants);
    layout->layout.keyboardTypeList[0].keyToCharTableIndexOffset =
            offsetof(struct Layout, tableIndex);

    layout->modifierVariants.keyModifiersToTableNumFormat =
            kUCKeyModifiersToTableNumFormat;
    layout->modifierVariants.defaultTableNum = 0;
    layout->modifierVariants.modifiersCount = 3;
    layout->modifierVariants.tableNum[0] = 0;
    layout->modifierVariants.tableNum[1] = 0; // cmd key bit
    layout->modifierVariants.tableNum[2] = 1; // shift key bit

    layout->tableIndex.keyToCharTableIndexFormat = kUCKeyToCharTableIndexFormat;
    layout->tableIndex.keyToCharTableSize = 128;
    layout->tableIndex.keyToCharTableCount = 2;
    layout->tableIndex.keyToCharTableOffsets[0] = offsetof(struct Layout, table1);
    layout->tableIndex.keyToCharTableOffsets[1] = offsetof(struct Layout, table2);

    for (xkb_level_index_t level = 0; level <= 1; level++) {
        UCKeyOutput *table = level == 0 ? layout->table1 : layout->table2;
        for (int carbonCode = 0; carbonCode < 128; carbonCode++) {
            const int keycode = carbonToX11[carbonCode];
            if (keycode == 0)
                continue;
            uint32_t codepoint = [self
                    codepointForKeysym: [self keysymForKeycode: keycode
                                                         level: level]];
            table[carbonCode] = codepoint <= 0xFFFF ? codepoint : 0;
        }
    }

    if (byteLength != NULL)
        *byteLength = sizeof(struct Layout);
    return &layout->layout;
}

#pragma mark - Screens

- (NSArray *) outputsWithModes {
    NSMutableArray *result = [NSMutableArray array];
    for (WaylandOutput *output in _outputs)
        if (output->_current.width > 0 && output->_current.height > 0)
            [result addObject: output];
    return result;
}

// Prefer complete compositor logical topology. If any output is still missing
// metadata, keep the entire set in the core-protocol horizontal fallback.
- (NSArray *) screens {
    if (_screens != nil)
        return [[_screens retain] autorelease];

    NSMutableArray *screens = [NSMutableArray array];
    CGFloat x = 0;
    NSArray *outputs = [self outputsWithModes];
    BOOL logical = [outputs count] > 0;
    for (WaylandOutput *output in outputs)
        if (!output->_logicalCurrent.hasPosition || !output->_logicalCurrent.hasSize)
            logical = NO;
    CGFloat referenceX = 0, referenceTop = 0;
    if (logical) {
        WaylandOutput *first = [outputs objectAtIndex: 0];
        referenceX = first->_logicalCurrent.x;
        referenceTop = (CGFloat)first->_logicalCurrent.y + first->_logicalCurrent.height;
    }
    for (WaylandOutput *output in outputs) {
        BOOL rotated = (output->_current.transform & 1) != 0;
        CGFloat width = rotated ? output->_current.height : output->_current.width;
        CGFloat height = rotated ? output->_current.width : output->_current.height;
        NSRect frame = NSMakeRect(x, 0, width / output->_current.scale,
                                  height / output->_current.scale);
        if (logical) {
            WaylandLogicalOutputState state = output->_logicalCurrent;
            frame = NSMakeRect((CGFloat)state.x - referenceX,
                    referenceTop - (CGFloat)state.y - state.height, state.width, state.height);
        }
        WaylandScreen *screen = [[[WaylandScreen alloc] initWithFrame: frame
                                               visibleFrame: frame] autorelease];
        // Whole scale factors only: a compositor that scales an output by 1.5 reports 2, and the
        // logical size says so even when wl_output rounds down.
        CGFloat wholeScale = output->_current.scale;
        if (logical && output->_logicalCurrent.width > 0) {
            CGFloat ratio = width / output->_logicalCurrent.width;
            wholeScale = MAX(wholeScale, ceil(ratio - 0.01));
        }
        screen->_waylandScale = wholeScale;
        [screen setCgDirectDisplayID: [screens count] + 1];
        [screens addObject: screen];
        x += frame.size.width;
    }

    if ([screens count] == 0) {
        // No output has reported a mode yet.
        static const CGFloat fallbackWidth = 1920, fallbackHeight = 1080;
        static BOOL logged;
        if (!logged) {
            NSLog(@"Wayland backend: no output mode known, assuming a %.0fx%.0f "
                  @"screen",
                  fallbackWidth, fallbackHeight);
            logged = YES;
        }
        NSRect frame = NSMakeRect(0, 0, fallbackWidth, fallbackHeight);
        [screens addObject: [[[NSScreen alloc] initWithFrame: frame
                                                visibleFrame: frame] autorelease]];
    }

    _screens = [screens copy];
    return [[_screens retain] autorelease];
}

- (NSArray *) modesForScreen: (int) screenIndex {
    NSArray *outputs = [self outputsWithModes];
    if (screenIndex < 0 || screenIndex >= (int) [outputs count])
        return nil;
    return [NSArray arrayWithArray: ((WaylandOutput *) outputs[screenIndex])->_modes];
}

- (NSDictionary *) currentModeForScreen: (int) screenIndex {
    NSArray *outputs = [self outputsWithModes];
    if (screenIndex < 0 || screenIndex >= (int) [outputs count])
        return @{};
    WaylandOutput *output = outputs[screenIndex];
    return @{
        @"Width" : @(output->_current.width),
        @"Height" : @(output->_current.height),
        @"Depth" : @(24),
        @"RefreshRate" : @(output->_current.refresh / 1000.0)
    };
}

- (BOOL) setMode: (NSDictionary *) mode forScreen: (int) screenIndex {
    return NO;
}

#pragma mark - Windows

- (struct wl_proxy *) seat { return _seat; }

- (WaylandWindow *) popupParentForWindow: (WaylandWindow *) window {
    // Menu tracking can open nested menus with keyboard or timer events. The
    // newest mapped popup is the parent even if pointer focus has not moved.
    for (CFIndex i = CFArrayGetCount(_windows); i > 0; i--) {
        WaylandWindow *candidate = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i - 1);
        if (candidate != window && [candidate isMapped] && [candidate isPopup])
            return candidate;
    }
    if (_inputWindow != window && [_inputWindow isMapped])
        return _inputWindow;
    if (_pointerWindow != window && [_pointerWindow isMapped])
        return _pointerWindow;
    id key = [[NSApp keyWindow] platformWindow];
    if (key != window && [key isKindOfClass: [WaylandWindow class]] && [key isMapped])
        return key;
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
    for (CFIndex i = CFArrayGetCount(_windows); i > 0; i--) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i - 1);
        if ([window popupParent] == parent)
            [children addObject: window];
    }
    if ([children count] != 0 && ![parent isPopup]) {
        [self cancelPopupMenus];
        return;
    }
    for (WaylandWindow *window in children)
        [window unmap];
}

- (void) cancelPopupMenus {
    // Tracking loops own menu windows. Do not close/release them underneath
    // their stack frames. Clear selection and wake tracking with cancellation.
    NSMutableArray *popups = [NSMutableArray array];
    for (CFIndex i = CFArrayGetCount(_windows); i > 0; i--) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i - 1);
        if ([window isPopup])
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
                                   modifierFlags: 0 timestamp: 0 windowNumber: 0 context: nil
                                         subtype: NSApplicationDeactivated data1: 0 data2: 0];
    [self postEvent: cancel atStart: YES];
}

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    return [[WaylandWindow alloc] initWithDelegate: delegate];
}

- (void) windowCreated: (WaylandWindow *) window {
    CFArrayAppendValue(_windows, window);
}

- (void) windowActivated: (WaylandWindow *) window {
    CFIndex index = CFArrayGetFirstIndexOfValue(
            _windows, CFRangeMake(0, CFArrayGetCount(_windows)), window);
    if (index > 0) {
        CFArrayRemoveValueAtIndex(_windows, index);
        CFArrayInsertValueAtIndex(_windows, 0, window);
    }
}

- (void) windowUnmapped: (WaylandWindow *) window {
    if (_wlLastClickWindow == window)
        _wlLastClickWindow = nil;
    if (_pinchWindow == window)
        [self postPinchPhase: NSEventPhaseCancelled];
    [_draggingManager windowUnmapped: window];
    if (_dragPressWindow == window) [self consumeDragPress];
    if (_pointerWindow == window) {
        _pointerWindow = nil;
        _pointerEnterSerial = 0;
        _pressedButtons = 0;
        _pendingScrollX = _pendingScrollY = 0;
        _pendingScrollWindow = nil;
        _pendingScrollActive = NO;
        [_buttonClickCounts removeAllObjects];
    }
    if (_inputWindow == window) {
        _inputWindow = nil;
        [_inputEvent release];
        _inputEvent = nil;
    }
    if (_keyboardWindow == window) {
        _keyboardWindow = nil;
        [self stopKeyRepeat];
        [self resetKeyboardModifiers];
    }
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
        if ([window isMapped])
            [result addObject: @([window windowNumber])];
    }
    return result;
}

#pragma mark - Cursors

// The output scale must be applied exactly once. A cursor surface without a
// wp_viewport cannot express a logical size, so pre-scaling the raster and then
// setting wl_surface.set_buffer_scale to the same factor asks the compositor to
// scale it twice: a 24pt cursor then covers 96 physical px on a 2x output.
// With a viewporter the client owns the scaling and pins buffer_scale to 1;
// without one the compositor owns it, so hand over a 1x raster at buffer_scale 1.
- (uint32_t) cursorRenderScale120 {
    if (_cursorFractionalScale) return _cursorPreferredScale120 ?: (_pointerWindow ? [_pointerWindow renderScale120] : 120);
    return 120;
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
    if (!decoration && [cursor isBlank]) {
        args[1].o = NULL;
        args[2].i = 0;
        args[3].i = 0;
        WaylandMarshal(_pointer, WP_POINTER_SET_CURSOR, NULL, 0, args);
        [self flush];
        return;
    }
    if (_cursorSurface == NULL)
        return;

    uint32_t scale120 = [self cursorRenderScale120];
    BOOL fractional = _cursorFractionalScale != NULL;
    int32_t wireScale = fractional ? 1 : (int32_t)(scale120 / 120);
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
        if (fractional) {
            uint64_t width = ((uint64_t)image->width * 120 + _cursorThemeScale120 / 2) / _cursorThemeScale120;
            uint64_t height = ((uint64_t)image->height * 120 + _cursorThemeScale120 / 2) / _cursorThemeScale120;
            if (width > INT32_MAX || height > INT32_MAX) return;
            logical = NSMakeSize(MAX(1, width), MAX(1, height));
            hotSpot = NSMakePoint(MIN(logical.width - 1, floor(image->hotspot_x * logical.width / image->width)),
                MIN(logical.height - 1, floor(image->hotspot_y * logical.height / image->height)));
        } else {
            // No wp_viewport: the theme is loaded at the compositor's nominal
            // size (_cursorThemeScale120 is 120, since cursorRenderScale120
            // hands scaling to the compositor) and the surface stays at
            // buffer_scale 1, so the hotspot is used unscaled.
            wireScale = (int32_t)(_cursorThemeScale120 / 120);
            if (wireScale < 1 || image->width % wireScale || image->height % wireScale) wireScale = 1;
            logical = NSMakeSize(image->width / wireScale, image->height / wireScale);
            hotSpot = NSMakePoint(image->hotspot_x / wireScale, image->hotspot_y / wireScale);
        }
    }

    if (_compositorVersion >= 3) {
        union wl_argument scaleArgs[1] = {{.i = wireScale}};
        WaylandMarshal(_cursorSurface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scaleArgs);
    }

    if (_cursorViewport) {
        union wl_argument destination[] = {{.i = (int32_t)logical.width}, {.i = (int32_t)logical.height}};
        WaylandMarshal(_cursorViewport, WP_VIEWPORT_SET_DESTINATION, NULL, 0, destination);
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
            {@"openHandCursor", "grab", "fleur"},
            {@"pointingHandCursor", "pointer", "hand2"},
            {@"resizeDownCursor", "s-resize", "bottom_side"},
            {@"resizeLeftCursor", "w-resize", "left_side"},
            {@"resizeLeftRightCursor", "ew-resize", "h_double_arrow"},
            {@"resizeRightCursor", "e-resize", "right_side"},
            {@"resizeUpCursor", "n-resize", "top_side"},
            {@"resizeUpDownCursor", "ns-resize", "v_double_arrow"},
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

- (void) hideCursor {
    [self setCursor: [[[WaylandCursor alloc] initBlank] autorelease]];
}

- (void) unhideCursor {
    NSCursor *current = [NSCursor currentCursor];
    if (current != nil) {
        [current push];
        [current pop];
    } else {
        [self setCursor: [self cursorWithName: @"arrowCursor"]];
    }
}

#pragma mark - Unsupported or X11-only

- (uint32_t) clipboardSerial {
    return _keyboardWindow != nil ? _inputSerial : 0;
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

- (NSPasteboard *) pasteboardWithName: (NSString *) name {
    if ([name isEqual: NSGeneralPboard] || [name isEqual: NSPasteboardNameGeneral])
        return _generalPasteboard;
    if (name == nil) return nil;
    WaylandPasteboard *pasteboard = [_namedPasteboards objectForKey: name];
    if (!pasteboard) {
        pasteboard = [[[WaylandPasteboard alloc] initWithName: name display: self
                                                    manager: NULL seat: NULL] autorelease];
        [_namedPasteboards setObject: pasteboard forKey: name];
    }
    return pasteboard;
}

- (void) beep {
}

// X11Display answers these from the X server, and this display never connected to one, so
// the inherited versions would call Xlib with no connection.
- (NSUInteger) pressedMouseButtons {
    return _pressedButtons;
}

// Wayland has no protocol to activate another client's window.
- (BOOL) activateProcessIdentifier: (pid_t) processIdentifier {
    return NO;
}

- (Display *) display {
    return NULL;
}

- (void) setWindow: (id) window forID: (XID) i {
}

- (id) windowForID: (XID) i {
    return nil;
}

- (NSEventModifierFlags) modifierFlagsForState: (unsigned int) state {
    return 0;
}

- (void) postXEvent: (XEvent *) ev {
}

- (int) handleError: (XErrorEvent *) errorEvent {
    return 0;
}

@end
