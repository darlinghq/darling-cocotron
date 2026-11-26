/* CoreGraphics Wayland backend: the window-server connection.

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

#import "CGSConnectionWayland.h"
#import "CGSWaylandKeyboard.h"
#import "CGSWaylandPointer.h"
#import "CGSWaylandTouch.h"
#import "CGSWaylandKeymap.h"
#import "CGSWaylandClipboard.h"
#import "CGSWaylandOutputManager.h"
#import "CGSWindowWayland.h"
#import "WaylandColor.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/pwr_mgt/IOPMLibPrivate.h>
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>

#import <CoreGraphics/CGSKeyboardLayout.h>
#import <CoreGraphics/CGSScreen.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <dispatch/dispatch.h>
#include <math.h>
#include <notify.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Mode pixels are untransformed. The properties of a wl_output (version 2 and later) take effect
// together at wl_output.done.
// x, y: the output's position in the compositor's layout (wl_output.geometry).
typedef struct { int32_t width, height, refresh, scale, transform, x, y; } CGSWaylandOutputState;

typedef struct {
    int32_t x, y, width, height;
    BOOL hasPosition, hasSize;
} CGSWaylandLogicalOutputState;

// One wl_output and the state its events accumulate until wl_output.done.
@interface CGSWaylandOutput : NSObject {
@public
    CGSConnectionWayland *_connection; // Not retained; it outlives its outputs.
    struct wl_proxy *_proxy, *_logicalProxy;
    uint32_t _name, _version, _logicalVersion;
    CGSWaylandOutputState _current, _pending;
    CGSWaylandLogicalOutputState _logicalCurrent, _logicalPending;
    NSArray *_modes;
    NSMutableArray *_pendingModes;
    // wl_output version 4: the connector name and the human readable description, published at done.
    NSString *_outputName, *_pendingName, *_outputDescription, *_pendingDescription;
}
@end

@implementation CGSWaylandOutput
- (void) dealloc {
    [_outputName release];
    [_pendingName release];
    [_outputDescription release];
    [_pendingDescription release];
    [_modes release];
    [_pendingModes release];
    [super dealloc];
}
@end

static int CGSWaylandDispatch(const void *kind, void *proxy, uint32_t opcode,
                              const struct wl_message *message,
                              union wl_argument *args)
{
    id object = (id) WL.wl_proxy_get_user_data(proxy);
    CGSWaylandObjectKind objectKind = (CGSWaylandObjectKind) (uintptr_t) kind;

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
            case CGSWaylandObjectXdgSurface:
            case CGSWaylandObjectToplevel:
            case CGSWaylandObjectLayerSurface:
            case CGSWaylandObjectPopup:
                [(CGSWindowWayland *) object handleEvent: opcode
                                                    kind: objectKind
                                               arguments: args];
                break;
            case CGSWaylandObjectBuffer:
                [(CGSWindowWayland *) object bufferReleased: (struct wl_proxy *) proxy opcode: opcode];
                break;
            case CGSWaylandObjectOutput:
            case CGSWaylandObjectLogicalOutput:
                [((CGSWaylandOutput *) object)->_connection handleEvent: opcode
                                                                   kind: objectKind
                                                                 object: object
                                                              arguments: args];
                break;
            case CGSWaylandObjectOutputManager:
            case CGSWaylandObjectOutputHead:
            case CGSWaylandObjectOutputHeadMode:
            case CGSWaylandObjectOutputConfiguration:
                [(id<CGSWaylandOutputManagementEvents>) object handleEvent: opcode
                                                                      kind: objectKind
                                                                     proxy: proxy
                                                                 arguments: args];
                break;
            case CGSWaylandObjectPointer:
                [(CGSWaylandPointer *) object pointerEvent: opcode arguments: args];
                break;
            case CGSWaylandObjectPinchGesture:
                [(CGSWaylandPointer *) object pinchEvent: opcode arguments: args];
                break;
            case CGSWaylandObjectTouch:
                [(CGSWaylandTouch *) object touchEvent: opcode arguments: args];
                break;
            case CGSWaylandObjectLockedPointer:
            case CGSWaylandObjectRelativePointer:
            case CGSWaylandObjectWarpLock:
                [(CGSWaylandPointer *) object lockEvent: opcode kind: objectKind proxy: (struct wl_proxy *) proxy arguments: args];
                break;
            case CGSWaylandObjectDataDevice:
            case CGSWaylandObjectDataOffer:
            case CGSWaylandObjectDataSource:
                [(CGSWaylandClipboard *) object handleEvent: opcode
                                                       kind: objectKind
                                                      proxy: (struct wl_proxy *) proxy
                                                  arguments: args];
                break;
            case CGSWaylandObjectKeyboardSync:
                if (opcode == WP_CALLBACK_EV_DONE)
                    [(CGSWaylandKeyboard *) object modifierSyncDone: (struct wl_proxy *) proxy];
                break;
            case CGSWaylandObjectSeat:
            case CGSWaylandObjectKeyboard:
            default:
                [(CGSConnectionWayland *) object handleEvent: opcode
                                                        kind: objectKind
                                                      object: object
                                                   arguments: args];
                break;
            }
        } @catch (NSException *exception) {
            NSLog(@"CoreGraphics Wayland backend: exception while handling an "
                  @"event: %@", exception);
        }
    }
    return 0;
}

@interface CGSConnectionWayland ()
- (void) processPendingEvents;
- (void) scheduleAfterDispatchRun;
- (void) runAfterDispatchBlocks;
- (void) seatCapabilities: (uint32_t) capabilities;
- (void) keyboardEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
- (void) releaseKeyboard;
@end

static void socketCallback(CFSocketRef socket, CFSocketCallBackType type,
                           CFDataRef address, const void *data, void *info)
{
    [(CGSConnectionWayland *) info processPendingEvents];
}

// One registered global hot key
@interface CGSWaylandHotKeyEntry : NSObject {
@public
    int uid;
    CGKeyCode virtualKey;
    CGEventFlags flags;
    BOOL enabled;
}
@end

@implementation CGSWaylandHotKeyEntry
@end

// The modifier flags a hot key is matched on.
static const CGEventFlags kHotKeyModifierMask =
    kCGEventFlagMaskShift | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand;

@implementation CGSConnectionWayland

+ (BOOL) isAvailable {
    // WaylandBackendSelected() is the decision AppKit's Wayland backend makes too (see
    // WaylandLibrary.h); CGS.m selects by NSPriority alone, so asking the same question keeps
    // both frameworks on the same display server.
    if (!WaylandBackendSelected())
        return NO;
    if (getenv("WAYLAND_DISPLAY") == NULL) {
        NSLog(@"CoreGraphics Wayland backend: the Wayland backend was selected "
              @"but WAYLAND_DISPLAY is unset");
        return NO;
    }
    return YES;
}

- (instancetype) initWithConnectionID: (CGSConnectionID) connId {
    if (!WaylandLibraryLoad() || !WaylandCheckOpcodes()) {
        NSLog(@"CoreGraphics Wayland backend: unavailable, trying the next "
              @"backend");
        [self release];
        return nil;
    }

    self = [super initWithConnectionID: connId];
    if (self == nil)
        return nil;

    _outputs = [NSMutableArray new];
    _color = [[WaylandColorManager alloc] initWithDispatcher: CGSWaylandDispatch owner: self];
    // The keyboard layout is described from the system default until the compositor's keymap arrives.
    _keymap = [[CGSWaylandKeymap alloc] init];
    if (_keymap != nil)
        _keyboardDecoder = [[CGSWaylandKeyboard alloc] initWithConnection: self keymap: _keymap];
    _pointerDecoder = [[CGSWaylandPointer alloc] initWithConnection: self];
    _touchDecoder = [[CGSWaylandTouch alloc] initWithConnection: self];

    _wlDisplay = WL.wl_display_connect(NULL);
    if (_wlDisplay == NULL) {
        const char *name = getenv("WAYLAND_DISPLAY");
        NSLog(@"CoreGraphics Wayland backend: cannot connect to the compositor "
              @"(WAYLAND_DISPLAY=%s)", name ? name : "unset");
        [self release];
        return nil;
    }

    union wl_argument args[1] = {{.o = NULL}};
    _registry = [self createObject: (struct wl_proxy *) _wlDisplay
                            opcode: WP_DISPLAY_GET_REGISTRY
                         interface: &wl_registry_interface
                         arguments: args
                              kind: CGSWaylandObjectRegistry
                            object: self];
    if (_registry == NULL) {
        [self release];
        return nil;
    }

    // The first roundtrip delivers the globals, the second the initial events
    // of the objects bound meanwhile (output geometry and modes).
    if (WL.wl_display_roundtrip(_wlDisplay) < 0 ||
        WL.wl_display_roundtrip(_wlDisplay) < 0)
    {
        NSLog(@"CoreGraphics Wayland backend: the compositor connection failed "
              @"during setup (error %d)", WL.wl_display_get_error(_wlDisplay));
        [self release];
        return nil;
    }

    if (_compositor == NULL || _wmBase == NULL) {
        NSLog(@"CoreGraphics Wayland backend: the compositor lacks%s%s",
              _compositor ? "" : " wl_compositor", _wmBase ? "" : " xdg_wm_base");
        [self release];
        return nil;
    }

    CFSocketContext context = {.version = 0, .info = self};
    _cfSocket = CFSocketCreateWithNative(kCFAllocatorDefault,
                                         WL.wl_display_get_fd(_wlDisplay),
                                         kCFSocketReadCallBack, socketCallback,
                                         &context);
    if (_cfSocket != NULL) {
        // The descriptor belongs to libwayland.
        CFSocketSetSocketFlags(_cfSocket, CFSocketGetSocketFlags(_cfSocket) &
                                                  ~kCFSocketCloseOnInvalidate);
        _source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _cfSocket, 0);
    }
    if (_source == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot watch the compositor "
              @"connection");
        [self release];
        return nil;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

    // Another process asks for the activation of this one's windows with a libnotify notification named
    // after this process (see _CGSActivateProcess). Only the process can ask the compositor for it, with
    // a token its windows' input gives it, so the observer that owns the windows is told, on the main
    // queue, which the run loop serves.
    char notificationName[64];
    snprintf(notificationName, sizeof(notificationName),
             kCGSProcessActivationNotificationPrefix "%d", (int) getpid());
    // The block does not keep the connection alive (a __block variable is not retained); the token is
    // cancelled before the connection goes.
    __block CGSConnectionWayland *connection = self;
    _activationRegistered = notify_register_dispatch(notificationName, &_activationNotifyToken,
                                                     dispatch_get_main_queue(),
                                                     ^(int ignored) { [connection activationRequested]; }) ==
                            NOTIFY_STATUS_OK;

    _afterDispatch = [NSMutableArray new];

    // The clipboard: the general pasteboard shows the compositor's selection. This goes before the process makes its
    // first pasteboard, which is why the connection does it, not the framework with the windows.
    if (_dataDeviceManager != NULL && _seat != NULL) {
        _clipboard = [[CGSWaylandClipboard alloc] initWithConnection: self manager: _dataDeviceManager seat: _seat];
        if (_clipboard != nil)
            _CGSHostClipboardStart(_clipboard);
    }
    [self observeDisplaySleepAssertions];

    _setupDone = YES;
    [self flush];
    return self;
}

- (void) dealloc {
    // Windows destroy wl_proxies and flush, so they have to go while the
    // display is still connected; -[CGSConnection dealloc] releases _windows
    // only after this body runs.
    @synchronized (_windows) {
        [_windows removeAllObjects];
    }

    [_clipboard invalidate];
    [_clipboard release];
    if (_dataDeviceManager != NULL)
        WL.wl_proxy_destroy(_dataDeviceManager);
    [_afterDispatch release];

    if (_activationRegistered)
        notify_cancel(_activationNotifyToken);
    if (_assertionsNotifyRegistered)
        notify_cancel(_assertionsNotifyToken);
    if (_source != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
    }
    if (_cfSocket != NULL) {
        CFSocketInvalidate(_cfSocket);
        CFRelease(_cfSocket);
    }

    [_outputManager release];
    [(WaylandColorManager *) _color shutdown];
    [_color release];
    [self releaseKeyboard];
    [_keyboardDecoder release];
    [(CGSWaylandPointer *) _pointerDecoder stop];
    [_pointerDecoder release];
    [(CGSWaylandTouch *) _touchDecoder stop];
    [_touchDecoder release];
    if (_pointerGestures != NULL)
        WL.wl_proxy_destroy(_pointerGestures);
    [_hotKeys release];
    if (_seat != NULL)
        WL.wl_proxy_destroy(_seat);
    [_keymap release];
    if (_legacyLogicalOutputManager != NULL)
        WL.wl_proxy_destroy(_legacyLogicalOutputManager);
    if (_logicalOutputManager != NULL)
        WL.wl_proxy_destroy(_logicalOutputManager);
    for (CGSWaylandOutput *output in _outputs) {
        if (output->_logicalProxy != NULL)
            WaylandMarshal(output->_logicalProxy, WP_LOGICAL_OUTPUT_DESTROY, NULL,
                           WL_MARSHAL_FLAG_DESTROY, NULL);
        WL.wl_proxy_destroy(output->_proxy);
    }
    [_outputs release];

    if (_wlDisplay != NULL) {
        WL.wl_display_disconnect(_wlDisplay);
        _wlDisplay = NULL;
    }

    [super dealloc];
}

#pragma mark - Wayland plumbing

- (struct wl_proxy *) createObject: (struct wl_proxy *) proxy
                            opcode: (uint32_t) opcode
                         interface: (const struct wl_interface *) interface
                         arguments: (union wl_argument *) args
                              kind: (CGSWaylandObjectKind) kind
                            object: (id) object
{
    struct wl_proxy *created = WaylandMarshal(proxy, opcode, interface, 0, args);
    if (created == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot create a %s",
              interface->name);
        return NULL;
    }
    if (kind != 0)
        WL.wl_proxy_add_dispatcher(created, CGSWaylandDispatch,
                                   (void *) (uintptr_t) kind, object);
    return created;
}

- (struct wl_proxy *) bindGlobal: (uint32_t) name
                       interface: (const struct wl_interface *) interface
                         version: (uint32_t) version
                            kind: (CGSWaylandObjectKind) kind
                          object: (id) object
{
    union wl_argument args[4] = {
            {.u = name}, {.s = interface->name}, {.u = version}, {.o = NULL}};
    struct wl_proxy *proxy = WL.wl_proxy_marshal_array_flags(
            _registry, WP_REGISTRY_BIND, interface, version, 0, args);
    if (proxy == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot bind %s", interface->name);
        return NULL;
    }
    if (kind != 0)
        WL.wl_proxy_add_dispatcher(proxy, CGSWaylandDispatch,
                                   (void *) (uintptr_t) kind, object);
    return proxy;
}

- (void) attachDispatcherTo: (struct wl_proxy *) proxy
                       kind: (CGSWaylandObjectKind) kind
                     object: (id) object
{
    WL.wl_proxy_add_dispatcher(proxy, CGSWaylandDispatch, (void *) (uintptr_t) kind, object);
}

- (void) flush {
    if (_wlDisplay != NULL)
        WL.wl_display_flush(_wlDisplay);
}

- (WaylandColorManager *) colorManager {
    return _color;
}

- (id) waylandColorManager {
    return _color;
}

- (void) notifyWindowsColorManagerAvailable {
    // The windows of the framework above share this manager (see -waylandColorManager).
    id observer = [CGSConnection nativeObserver];
    if ([observer respondsToSelector: @selector(nativeConnectionColorManagerAvailable)])
        [observer nativeConnectionColorManagerAvailable];
    @synchronized (_windows) {
        for (NSNumber *key in _windows) {
            CGSWindow *window = [_windows objectForKey: key];
            if ([window isKindOfClass: [CGSWindowWayland class]])
                [(CGSWindowWayland *) window colorManagerAvailable];
        }
    }
}

- (void) connectionFailed {
    // Matches AppKit's backend: a lost compositor connection leaves every proxy
    // unusable, and there is nothing to fall back to at this point.
    NSLog(@"CoreGraphics Wayland backend: lost the connection to the compositor "
          @"(error %d)", WL.wl_display_get_error(_wlDisplay));
    exit(1);
}

- (void) processPendingEvents {
    if (_wlDisplay == NULL)
        return;

    _dispatching = YES;
    while (WL.wl_display_prepare_read(_wlDisplay) != 0) {
        if (WL.wl_display_dispatch_pending(_wlDisplay) < 0)
            [self connectionFailed];
    }
    WL.wl_display_flush(_wlDisplay);

    struct pollfd pfd = {.fd = WL.wl_display_get_fd(_wlDisplay), .events = POLLIN};
    if (poll(&pfd, 1, 0) > 0) {
        if (WL.wl_display_read_events(_wlDisplay) < 0)
            [self connectionFailed];
    } else {
        WL.wl_display_cancel_read(_wlDisplay);
    }

    if (WL.wl_display_dispatch_pending(_wlDisplay) < 0)
        [self connectionFailed];
    _dispatching = NO;
    [self runAfterDispatchBlocks];

    // What the framework with the windows lives on the same connection: every listener of every
    // object on it has run, so the observer sends what it queued meanwhile. A change of the displays
    // is reported once the objects of both have seen it (a client's wl_output objects all get their
    // events from the same read).
    id observer = [CGSConnection nativeObserver];
    if (_layoutChangedForObserver) {
        _layoutChangedForObserver = NO;
        if ([observer respondsToSelector: @selector(nativeConnectionDisplayLayoutChanged)])
            [observer nativeConnectionDisplayLayoutChanged];
    }
    if ([observer respondsToSelector: @selector(nativeConnectionDidProcessEvents)])
        [observer nativeConnectionDidProcessEvents];

    WL.wl_display_flush(_wlDisplay);
}

+ (int) nativeConnectionKind {
    return CGSNativeConnectionKindWayland;
}

#pragma mark - After the dispatch

- (void) performAfterDispatch: (void (^)(void)) block {
    [_afterDispatch addObject: [[block copy] autorelease]];
    // Outside a dispatch nothing would run the block before the compositor sends something.
    if (!_dispatching)
        [self scheduleAfterDispatchRun];
}

- (void) scheduleAfterDispatchRun {
    if (_afterDispatchRunQueued)
        return;
    _afterDispatchRunQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_afterDispatchRunQueued = NO;
      [self runAfterDispatchBlocks];
    });
}

// Runs the blocks that were queued before this pass. Blocks queued by those blocks wait for the next run loop
// iteration, so that work which keeps queueing more work cannot keep the main thread here and starve the run loop.
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

#pragma mark - Clipboard

// How long the serial of a press stays good for the clipboard after the keyboard focus left.
static const CFTimeInterval kInputSerialGrace = 1.0;

- (void) inputPressedWithSerial: (uint32_t) serial {
    _inputSerial = serial;
    _inputSerialTime = CFAbsoluteTimeGetCurrent();
    [(CGSWaylandClipboard *) _clipboard inputAvailable];
}

- (uint32_t) clipboardSerial {
    if (_inputSerial == 0)
        return 0;
    if ([self keyboardFocus] != NULL)
        return _inputSerial;
    // A key or click still being handled entitles its writes to the selection even when the focus left right
    // after it, as when a virtual keyboard is removed a few milliseconds after its key.
    return CFAbsoluteTimeGetCurrent() - _inputSerialTime < kInputSerialGrace ? _inputSerial : 0;
}

#pragma mark - Events

- (void) registryGlobal: (uint32_t) name
              interface: (const char *) interface
                version: (uint32_t) version
{
    if (strcmp(interface, "wl_compositor") == 0 && _compositor == NULL) {
        _compositor = [self bindGlobal: name interface: &wl_compositor_interface
                               version: MIN(version, 4u)
                                   kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "wl_shm") == 0 && _shm == NULL) {
        _shm = [self bindGlobal: name interface: &wl_shm_interface
                        version: 1
                           kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "xdg_wm_base") == 0 && _wmBase == NULL) {
        _wmBase = [self bindGlobal: name interface: &xdg_wm_base_interface
                           version: MIN(version, 2u)
                              kind: CGSWaylandObjectWmBase object: self];
    } else if (strcmp(interface, "zwlr_layer_shell_v1") == 0 && _layerShell == NULL) {
        _layerShell = [self bindGlobal: name interface: &zwlr_layer_shell_v1_interface
                               version: MIN(version, 4u)
                                  kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "org_kde_plasma_shell") == 0 && _plasmaShell == NULL) {
        // Version 2 adds set_skip_taskbar, version 5 set_skip_switcher.
        _plasmaShellVersion = MIN(version, 5u);
        _plasmaShell = [self bindGlobal: name interface: &org_kde_plasma_shell_interface
                                version: _plasmaShellVersion
                                   kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "zxdg_decoration_manager_v1") == 0 && _decorationManager == NULL) {
        _decorationManager = [self bindGlobal: name interface: &zxdg_decoration_manager_v1_interface
                                      version: 1
                                         kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "wp_color_manager_v1") == 0 &&
               ((WaylandColorManager *) _color)->_colorManager == NULL) {
        uint32_t managerVersion = MIN(version, (uint32_t) wp_color_manager_v1_interface.version);
        struct wl_proxy *proxy = [self bindGlobal: name interface: &wp_color_manager_v1_interface
                                          version: managerVersion
                                             kind: (CGSWaylandObjectKind) WaylandColorObjectManager
                                           object: _color];
        [(WaylandColorManager *) _color bindColorManager: proxy
                                                 version: managerVersion name: name];
        [self notifyWindowsColorManagerAvailable];
    } else if (strcmp(interface, "wp_color_representation_manager_v1") == 0 &&
               ((WaylandColorManager *) _color)->_representationManager == NULL) {
        struct wl_proxy *proxy = [self bindGlobal: name
                                         interface: &wp_color_representation_manager_v1_interface
                                          version: 1
                                             kind: (CGSWaylandObjectKind) WaylandColorObjectRepresentationManager
                                           object: _color];
        [(WaylandColorManager *) _color bindRepresentationManager: proxy version: 1 name: name];
        [self notifyWindowsColorManagerAvailable];
    } else if (strcmp(interface, "wl_seat") == 0 && _seat == NULL) {
        // Version 4 adds wl_keyboard.repeat_info, 5 wl_pointer.frame and 8 wl_pointer.axis_value120. A
        // protocol table older than that offers less.
        _seat = [self bindGlobal: name interface: &wl_seat_interface
                         version: MIN(MIN(version, 8u), (uint32_t) wl_seat_interface.version)
                            kind: CGSWaylandObjectSeat object: self];
    } else if (strcmp(interface, "wl_data_device_manager") == 0 && _dataDeviceManager == NULL) {
        _dataDeviceManager = [self bindGlobal: name interface: &wl_data_device_manager_interface
                                      version: MIN(version, 3u)
                                         kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "zwp_pointer_constraints_v1") == 0 && _pointerConstraints == NULL) {
        _pointerConstraintsName = name;
        _pointerConstraints = [self bindGlobal: name interface: &zwp_pointer_constraints_v1_interface
                                       version: 1 kind: CGSWaylandObjectNone object: nil];
        [(CGSWaylandPointer *) _pointerDecoder pointerLockGlobalsChanged];
    } else if (strcmp(interface, "zwp_relative_pointer_manager_v1") == 0 && _relativePointerManager == NULL) {
        _relativePointerManagerName = name;
        _relativePointerManager = [self bindGlobal: name interface: &zwp_relative_pointer_manager_v1_interface
                                           version: 1 kind: CGSWaylandObjectNone object: nil];
        [(CGSWaylandPointer *) _pointerDecoder pointerLockGlobalsChanged];
    } else if (strcmp(interface, "wp_pointer_warp_v1") == 0 && _pointerWarp == NULL) {
        _pointerWarpName = name;
        _pointerWarp = [self bindGlobal: name interface: &wp_pointer_warp_v1_interface
                                version: 1 kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "zwp_pointer_gestures_v1") == 0 && _pointerGestures == NULL) {
        // Version 2 adds the release request.
        _pointerGesturesName = name;
        _pointerGestures = [self bindGlobal: name interface: &zwp_pointer_gestures_v1_interface
                                    version: MIN(version, 2u) kind: CGSWaylandObjectNone object: nil];
        [(CGSWaylandPointer *) _pointerDecoder pointerGesturesChanged];
    } else if (strcmp(interface, "zxdg_output_manager_v1") == 0 && _logicalOutputManager == NULL) {
        _logicalOutputManagerName = name;
        _logicalOutputManager = [self bindGlobal: name interface: &zxdg_output_manager_v1_interface
                                         version: MIN(version, 3u)
                                            kind: CGSWaylandObjectNone object: nil];
        @synchronized (self) {
            for (CGSWaylandOutput *output in _outputs)
                [self attachLogicalOutput: output];
        }
    } else if (strcmp(interface, "zwlr_output_manager_v1") == 0 && _outputManager == nil) {
        _outputManagerName = name;
        _outputManager = [CGSWaylandOutputManager alloc];
        struct wl_proxy *proxy = [self bindGlobal: name interface: &zwlr_output_manager_v1_interface
                                          version: 1 kind: CGSWaylandObjectOutputManager
                                           object: _outputManager];
        _outputManager = [_outputManager initWithConnection: self manager: proxy];
    } else if (strcmp(interface, "wl_output") == 0) {
        CGSWaylandOutput *output = [CGSWaylandOutput new];
        output->_connection = self;
        output->_name = name;
        output->_current.scale = output->_pending.scale = 1;
        // Version 2 has scale and done, version 4 the name and the description.
        output->_version = MIN(version, MIN(4u, wl_output_interface.version));
        output->_pendingModes = [NSMutableArray new];
        output->_modes = [NSArray new];
        output->_proxy = [self bindGlobal: name interface: &wl_output_interface
                                  version: output->_version
                                     kind: CGSWaylandObjectOutput object: output];
        if (output->_proxy == NULL) {
            [output release];
            return;
        }
        @synchronized (self) {
            [_outputs addObject: output];
            [self attachLogicalOutput: output];
            [(WaylandColorManager *) _color observeOutput: output->_proxy];
        }
        [output release];
    }
}

// The compositor's logical description of an output (its place in the layout and its size in
// logical units), where it offers xdg-output.
- (void) attachLogicalOutput: (CGSWaylandOutput *) output {
    if (_logicalOutputManager == NULL || output->_logicalProxy != NULL)
        return;
    struct wl_proxy *manager = _logicalOutputManager;
    // A typed new_id inherits the server-side manager version. A core v1 output cannot receive
    // wl_output.done, so it needs a genuinely v2 factory binding.
    if (output->_version < 2 && WL.wl_proxy_get_version(manager) >= 3) {
        if (_legacyLogicalOutputManager == NULL)
            _legacyLogicalOutputManager = [self bindGlobal: _logicalOutputManagerName
                    interface: &zxdg_output_manager_v1_interface version: 2
                         kind: CGSWaylandObjectNone object: nil];
        manager = _legacyLogicalOutputManager;
    }
    if (manager == NULL)
        return;
    output->_logicalVersion = WL.wl_proxy_get_version(manager);
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) output->_proxy}};
    output->_logicalProxy = [self createObject: manager
                                        opcode: WP_LOGICAL_MANAGER_GET_OUTPUT
                                     interface: &zxdg_output_v1_interface
                                     arguments: args
                                          kind: CGSWaylandObjectLogicalOutput
                                        object: output];
}

- (void) registryGlobalRemove: (uint32_t) name {
    [(WaylandColorManager *) _color globalRemoved: name];
    if ((_pointerConstraints != NULL && name == _pointerConstraintsName) ||
        (_relativePointerManager != NULL && name == _relativePointerManagerName)) {
        // The lock objects go before the global that made them.
        [(CGSWaylandPointer *) _pointerDecoder releasePointerLockObjects];
        struct wl_proxy **global = name == _pointerConstraintsName ? &_pointerConstraints : &_relativePointerManager;
        WL.wl_proxy_destroy(*global);
        *global = NULL;
        if (name == _pointerConstraintsName)
            _pointerConstraintsName = 0;
        else
            _relativePointerManagerName = 0;
        [(CGSWaylandPointer *) _pointerDecoder pointerLockGlobalsChanged];
        return;
    }
    if (_pointerWarp != NULL && name == _pointerWarpName) {
        WaylandMarshal(_pointerWarp, WP_POINTER_WARP_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _pointerWarp = NULL;
        _pointerWarpName = 0;
        return;
    }
    if (_pointerGestures != NULL && name == _pointerGesturesName) {
        struct wl_proxy *gestures = _pointerGestures;
        _pointerGestures = NULL;
        _pointerGesturesName = 0;
        [(CGSWaylandPointer *) _pointerDecoder pointerGesturesChanged];
        // wl_pointer_gestures.release exists from version 2.
        if (WL.wl_proxy_get_version(gestures) >= 2)
            WaylandMarshal(gestures, WP_GESTURES_RELEASE, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        else
            WL.wl_proxy_destroy(gestures);
        return;
    }
    if (_outputManager != nil && name == _outputManagerName) {
        [_outputManager release];
        _outputManager = nil;
        _outputManagerName = 0;
        return;
    }
    if (_logicalOutputManager != NULL && name == _logicalOutputManagerName) {
        if (_legacyLogicalOutputManager != NULL)
            WaylandMarshal(_legacyLogicalOutputManager, WP_LOGICAL_MANAGER_DESTROY, NULL,
                           WL_MARSHAL_FLAG_DESTROY, NULL);
        WaylandMarshal(_logicalOutputManager, WP_LOGICAL_MANAGER_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
        _logicalOutputManager = _legacyLogicalOutputManager = NULL;
        _logicalOutputManagerName = 0;
        // Existing logical-output children survive the removal of their factory.
        return;
    }

    BOOL removed = NO;
    @synchronized (self) {
        for (NSUInteger i = 0; i < [_outputs count]; i++) {
            CGSWaylandOutput *output = [_outputs objectAtIndex: i];
            if (output->_name != name)
                continue;
            if (output->_logicalProxy != NULL)
                WaylandMarshal(output->_logicalProxy, WP_LOGICAL_OUTPUT_DESTROY, NULL,
                               WL_MARSHAL_FLAG_DESTROY, NULL);
            WL.wl_proxy_destroy(output->_proxy);
            [_outputs removeObjectAtIndex: i];
            removed = YES;
            break;
        }
    }
    if (removed)
        [self outputsChanged];
}

// An output's image description (primaries, transfer function, luminances) changed. The screens are
// rebuilt with the new values; the observer is told separately so it can post
// NSScreenColorSpaceDidChangeNotification.
- (void) waylandColorManagerOutputInfoChanged: (WaylandColorManager *) manager {
    (void) manager;
    [self invalidateScreens];
    [self displayLayoutChanged];
    id observer = [CGSConnection nativeObserver];
    if ([observer respondsToSelector: @selector(nativeConnectionDisplayColorSpaceChanged)])
        [observer nativeConnectionDisplayColorSpaceChanged];
}

// A color manager global went away: the cached descriptions are gone, so rebuild the screens
// the same way as when an output's description changes.
- (void) waylandColorManagerDidLoseGlobal: (WaylandColorManager *) manager {
    [self waylandColorManagerOutputInfoChanged: manager];
}

// What changed in the outputs is a change of the displays, for the callbacks once the setup is over.
- (void) outputsChanged {
    if (_setupDone) {
        [self displayLayoutChanged];
        _layoutChangedForObserver = YES;
    } else
        [self invalidateScreens];
}

- (void) publishOutput: (CGSWaylandOutput *) output {
    @synchronized (self) {
        output->_current = output->_pending;
        [output->_outputName release];
        output->_outputName = [output->_pendingName copy];
        [output->_outputDescription release];
        output->_outputDescription = [output->_pendingDescription copy];
        if (output->_logicalVersion >= 3)
            output->_logicalCurrent = output->_logicalPending;
        [output->_modes release];
        output->_modes = [output->_pendingModes copy];
    }
    [self outputsChanged];
}

- (void) outputEvent: (uint32_t) opcode
              output: (CGSWaylandOutput *) output
           arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_OUTPUT_EV_GEOMETRY:
        // The transform is the eighth argument. Ignore unknown enum values.
        if (args[7].i >= 0 && args[7].i <= 7)
            output->_pending.transform = args[7].i;
        output->_pending.x = args[0].i;
        output->_pending.y = args[1].i;
        break;
    case WP_OUTPUT_EV_MODE: {
        if (args[1].i <= 0 || args[2].i <= 0 || args[3].i < 0)
            return;
        if (args[0].u & WP_OUTPUT_MODE_CURRENT) {
            output->_pending.width = args[1].i;
            output->_pending.height = args[2].i;
            output->_pending.refresh = args[3].i;
        }
        // Kept in device pixels; the scale of the output turns them into points when the
        // displays are described.
        NSDictionary *mode = @{
            @"Width": @(args[1].i),
            @"Height": @(args[2].i),
            @"Depth": @(24),
            @"RefreshRate": @(args[3].i / 1000.0),
        };
        if (![output->_pendingModes containsObject: mode])
            [output->_pendingModes addObject: mode];
        break;
    }
    case WP_OUTPUT_EV_SCALE:
        output->_pending.scale = MAX(args[0].i, 1);
        break;
    case WP_OUTPUT_EV_NAME:
    case WP_OUTPUT_EV_DESCRIPTION: {
        NSString *text = args[0].s != NULL ? [NSString stringWithUTF8String: args[0].s] : nil;
        if (opcode == WP_OUTPUT_EV_NAME) {
            [output->_pendingName release];
            output->_pendingName = [text copy];
        } else {
            [output->_pendingDescription release];
            output->_pendingDescription = [text copy];
        }
        return; // Published with the next done event.
    }
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

- (void) logicalOutputEvent: (uint32_t) opcode
                     output: (CGSWaylandOutput *) output
                  arguments: (union wl_argument *) args
{
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
        // From version 3 the logical state is published with wl_output.done.
        if (output->_logicalVersion < 3) {
            @synchronized (self) {
                output->_logicalCurrent = output->_logicalPending;
            }
            [self outputsChanged];
        }
        break;
    }
}

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
              object: (id) object
           arguments: (union wl_argument *) args
{
    switch (kind) {
    case CGSWaylandObjectRegistry:
        if (opcode == WP_REGISTRY_EV_GLOBAL)
            [self registryGlobal: args[0].u interface: args[1].s version: args[2].u];
        else if (opcode == WP_REGISTRY_EV_GLOBAL_REMOVE)
            [self registryGlobalRemove: args[0].u];
        break;

    case CGSWaylandObjectWmBase:
        if (opcode == WP_WM_BASE_EV_PING) {
            union wl_argument pong[1] = {{.u = args[0].u}};
            WaylandMarshal(_wmBase, WP_WM_BASE_PONG, NULL, 0, pong);
            [self flush];
        }
        break;

    case CGSWaylandObjectOutput:
        [self outputEvent: opcode output: (CGSWaylandOutput *) object arguments: args];
        break;

    case CGSWaylandObjectSeat:
        if (opcode == WP_SEAT_EV_CAPABILITIES)
            [self seatCapabilities: args[0].u];
        break;

    case CGSWaylandObjectKeyboard:
        [self keyboardEvent: opcode arguments: args];
        break;

    case CGSWaylandObjectLogicalOutput:
        [self logicalOutputEvent: opcode output: (CGSWaylandOutput *) object arguments: args];
        break;

    default:
        break;
    }
}

#pragma mark - Keyboard

- (void) seatCapabilities: (uint32_t) capabilities {
    [(CGSWaylandPointer *) _pointerDecoder seatCapabilities: capabilities seat: _seat];
    [(CGSWaylandTouch *) _touchDecoder seatCapabilities: capabilities seat: _seat];
    if ((capabilities & WP_SEAT_CAPABILITY_KEYBOARD) && _keyboard == NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        _keyboard = [self createObject: _seat
                                opcode: WP_SEAT_GET_KEYBOARD
                             interface: &wl_keyboard_interface
                             arguments: args
                                  kind: CGSWaylandObjectKeyboard
                                object: self];
    } else if (!(capabilities & WP_SEAT_CAPABILITY_KEYBOARD)) {
        // Also with no wl_keyboard object: the decoder may still hold state (a pending modifier key).
        [self releaseKeyboard];
    }
}

- (void) releaseKeyboard {
    [(CGSWaylandKeyboard *) _keyboardDecoder stop];
    if (_keyboard == NULL)
        return;
    // wl_keyboard.release exists from version 3.
    if (WL.wl_proxy_get_version(_keyboard) >= 3) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(_keyboard, WP_KEYBOARD_RELEASE, NULL, WL_MARSHAL_FLAG_DESTROY, args);
    } else {
        WL.wl_proxy_destroy(_keyboard);
    }
    _keyboard = NULL;
}

// The events of the wl_keyboard: the keymap and the modifier state are the keymap's, the keys become
// CGEvents (CGSWaylandKeyboard).
- (void) keyboardEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    if (_keyboardDecoder != nil) {
        [(CGSWaylandKeyboard *) _keyboardDecoder keyboardEvent: opcode arguments: args];
        return;
    }
    // Without xkbcommon there is no keymap object. The descriptor is the connection's to close.
    if (opcode == WP_KEYBOARD_EV_KEYMAP)
        close(args[1].h);
}

- (void *) keyboardFocus {
    return [(CGSWaylandKeyboard *) _keyboardDecoder focusSurface];
}

- (uint64_t) modifierFlags {
    return [(CGSWaylandKeyboard *) _keyboardDecoder modifierFlags];
}

- (void) nativeObjectDestroyed: (void *) object {
    [(CGSWaylandPointer *) _pointerDecoder surfaceDestroyed: (struct wl_proxy *) object];
    [(CGSWaylandTouch *) _touchDecoder surfaceDestroyed: (struct wl_proxy *) object];
    [(CGSWaylandKeyboard *) _keyboardDecoder surfaceDestroyed: (struct wl_proxy *) object];
}

- (void *) nativePointer {
    return [(CGSWaylandPointer *) _pointerDecoder pointerProxy];
}

- (void) setPointerSurfacePointX: (double) x y: (double) y {
    [(CGSWaylandPointer *) _pointerDecoder setSurfacePointX: x y: y];
}

- (void) flushPendingPointerEvents {
    [(CGSWaylandPointer *) _pointerDecoder flushPending];
}

- (struct wl_proxy *) pointerGestures {
    return _pointerGestures;
}

- (struct wl_proxy *) pointerConstraints {
    return _pointerConstraints;
}

- (struct wl_proxy *) relativePointerManager {
    return _relativePointerManager;
}

- (struct wl_proxy *) pointerWarp {
    return _pointerWarp;
}

#pragma mark - Power assertions

// Whether this process holds an assertion that keeps the display from sleeping on idle: the current
// kIOPMAssertPreventUserIdleDisplaySleep, or the older kIOPMAssertionTypeNoDisplaySleep which names the
// same thing. The assertions are listed by power management (iokitd), which keeps them for every process.
static BOOL ProcessHoldsDisplaySleepAssertion(void) {
    CFDictionaryRef byProcess = NULL;
    BOOL held = NO;

    if (IOPMCopyAssertionsByProcess(&byProcess) != kIOReturnSuccess || byProcess == NULL)
        return NO;

    int pid = (int) getpid();
    CFNumberRef key = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    CFArrayRef assertions = key != NULL ? CFDictionaryGetValue(byProcess, key) : NULL;
    if (key != NULL)
        CFRelease(key);

    if (assertions != NULL && CFGetTypeID(assertions) == CFArrayGetTypeID()) {
        for (CFIndex i = 0; i < CFArrayGetCount(assertions) && !held; i++) {
            CFDictionaryRef assertion = CFArrayGetValueAtIndex(assertions, i);
            if (CFGetTypeID(assertion) != CFDictionaryGetTypeID())
                continue;
            CFTypeRef type = CFDictionaryGetValue(assertion, kIOPMAssertionTypeKey);
            CFTypeRef level = CFDictionaryGetValue(assertion, kIOPMAssertionLevelKey);
            int levelValue = 0;
            if (type == NULL || CFGetTypeID(type) != CFStringGetTypeID() || level == NULL ||
                CFGetTypeID(level) != CFNumberGetTypeID() ||
                !CFNumberGetValue(level, kCFNumberIntType, &levelValue) || levelValue == kIOPMAssertionLevelOff)
                continue;
            held = CFEqual(type, kIOPMAssertPreventUserIdleDisplaySleep) ||
                   CFEqual(type, kIOPMAssertionTypeNoDisplaySleep);
        }
    }
    CFRelease(byProcess);
    return held;
}

// The window system has to be told that the display should stay awake, and power management does not
// reach the compositor, so the connection watches this process' assertions. Power management is asked
// on a queue of its own (it may be slow to answer), and the answer is applied on the main queue,
// where the observer that owns the windows runs.
- (void) observeDisplaySleepAssertions {
    _assertionsQueue = dispatch_queue_create("CoreGraphics.Wayland.assertions", DISPATCH_QUEUE_SERIAL);
    // The blocks do not keep the connection alive; the token is cancelled before it goes.
    __block CGSConnectionWayland *connection = self;
    dispatch_async(_assertionsQueue, ^{
        // Power management posts the change notification to clients that registered for it, so register
        // before the first listing: a change in between is then seen by the notification.
        if (IOPMAssertionNotify((char *) kIOPMAssertionsAnyChangedNotifyString, kIOPMNotifyRegister) ==
                    kIOReturnSuccess &&
            notify_register_dispatch(kIOPMAssertionsAnyChangedNotifyString, &connection->_assertionsNotifyToken,
                                     connection->_assertionsQueue,
                                     ^(int ignored) { [connection refreshDisplaySleepPrevented]; }) ==
                    NOTIFY_STATUS_OK)
            connection->_assertionsNotifyRegistered = YES;
        [connection refreshDisplaySleepPrevented];
    });
}

- (void) refreshDisplaySleepPrevented {
    BOOL held = ProcessHoldsDisplaySleepAssertion();
    __block CGSConnectionWayland *connection = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [connection setDisplaySleepPrevented: held];
    });
}

- (void) setDisplaySleepPrevented: (BOOL) prevented {
    if (_displaySleepPrevented == prevented)
        return;
    _displaySleepPrevented = prevented;
    id observer = [CGSConnection nativeObserver];
    if ([observer respondsToSelector: @selector(nativeConnectionDisplaySleepPreventionChanged)])
        [observer nativeConnectionDisplaySleepPreventionChanged];
}

- (BOOL) displaySleepPrevented {
    return _displaySleepPrevented;
}

#pragma mark - Pointer state

- (BOOL) managesPointer {
    return YES;
}

- (BOOL) cancelsHiddenUntilMouseMoves {
    return YES;
}

// Wayland requests are made on the main thread, where the connection is read.
- (void) cursorHiddenStateChanged: (BOOL) hidden {
    if ([NSThread isMainThread])
        [(CGSWaylandPointer *) _pointerDecoder cursorHiddenChanged];
    else
        [_pointerDecoder performSelectorOnMainThread: @selector(cursorHiddenChanged) withObject: nil waitUntilDone: NO];
}

- (void) mouseAssociationChanged: (BOOL) associated {
    if ([NSThread isMainThread])
        [(CGSWaylandPointer *) _pointerDecoder updatePointerLock];
    else
        [_pointerDecoder performSelectorOnMainThread: @selector(updatePointerLock) withObject: nil waitUntilDone: NO];
}

- (CGError) warpPointerToPoint: (CGPoint) point {
    if ([NSThread isMainThread])
        return [(CGSWaylandPointer *) _pointerDecoder warpToGlobalPoint: point];
    // A warp of another thread is carried out by the main one; whether it could be is not reported back.
    [self performSelectorOnMainThread: @selector(warpOnMainThread:)
                           withObject: [NSValue valueWithBytes: &point objCType: @encode(CGPoint)]
                        waitUntilDone: YES];
    return kCGErrorSuccess;
}

- (void) warpOnMainThread: (NSValue *) value {
    CGPoint point;
    [value getValue: &point];
    [(CGSWaylandPointer *) _pointerDecoder warpToGlobalPoint: point];
}

// The windows are ordered from any thread; the lock is made on the one that reads the connection.
- (void) pointerLockTargetMayHaveChanged {
    if ([NSThread isMainThread])
        [(CGSWaylandPointer *) _pointerDecoder updatePointerLock];
    else
        [_pointerDecoder performSelectorOnMainThread: @selector(updatePointerLock) withObject: nil waitUntilDone: NO];
}

- (BOOL) pointerLocked {
    return [(CGSWaylandPointer *) _pointerDecoder pointerLocked];
}

// The point of a window of this connection that is at a global location, when that is one of its own.
- (BOOL) surfacePoint: (CGPoint *) point forGlobalLocation: (CGPoint) location ofSurface: (struct wl_proxy *) surface {
    uint32_t windowID = [self windowIDForSurface: surface];
    CGSWindowWayland *window = windowID != 0 ? (CGSWindowWayland *) [self windowForId: (CGSWindowID) windowID] : nil;

    if (window == nil)
        return NO;
    *point = CGPointMake(location.x - [window frameOrigin].x, location.y - [window frameOrigin].y);
    return YES;
}

- (uint32_t) windowIDForSurface: (struct wl_proxy *) surface {
    if (surface == NULL)
        return 0;
    @synchronized (_windows) {
        for (NSNumber *key in _windows) {
            CGSWindow *window = [_windows objectForKey: key];

            if ([window isKindOfClass: [CGSWindowWayland class]] && ((CGSWindowWayland *) window)->_surface == surface)
                return (uint32_t) [key intValue];
        }
    }
    return 0;
}

- (BOOL) isDisplayOverlaySurface: (struct wl_proxy *) surface {
    uint32_t windowID = [self windowIDForSurface: surface];
    CGSWindow *window = windowID != 0 ? [self windowForId: (CGSWindowID) windowID] : nil;

    return [window isKindOfClass: [CGSWindowWayland class]] && [(CGSWindowWayland *) window isDisplayOverlay];
}

// Window ids grow with creation: the overlay made last is the one on top.
- (struct wl_proxy *) displayOverlaySurface {
    struct wl_proxy *found = NULL;
    int foundID = 0;

    @synchronized (_windows) {
        for (NSNumber *key in _windows) {
            CGSWindow *window = [_windows objectForKey: key];

            if ([window isKindOfClass: [CGSWindowWayland class]] && [(CGSWindowWayland *) window isDisplayOverlay] &&
                [(CGSWindowWayland *) window isShown] && [key intValue] > foundID) {
                found = ((CGSWindowWayland *) window)->_surface;
                foundID = [key intValue];
            }
        }
    }
    return found;
}

- (BOOL) isDisplayOverlayNativeWindow: (void *) nativeWindow {
    return [self isDisplayOverlaySurface: (struct wl_proxy *) nativeWindow];
}

- (BOOL) globalLocation: (CGPoint *) location ofSurface: (struct wl_proxy *) surface point: (CGPoint) point {
    uint32_t windowID = [self windowIDForSurface: surface];
    CGSWindowWayland *window = windowID != 0 ? (CGSWindowWayland *) [self windowForId: (CGSWindowID) windowID] : nil;

    if (window == nil)
        return NO;
    *location = CGPointMake([window frameOrigin].x + point.x, [window frameOrigin].y + point.y);
    return YES;
}

- (void) flushPendingKeyboardEvents {
    [(CGSWaylandKeyboard *) _keyboardDecoder flushPendingModifier];
}

- (int) keyboardLayoutGroup {
    return [(CGSWaylandKeymap *) _keymap layoutGroup];
}

- (NSString *) keyboardLayoutName {
    return [(CGSWaylandKeymap *) _keymap layoutName];
}

// The layout of the keymap in force, which this connection's keyboard received from the compositor.
// Nil without xkbcommon.
- (CGSKeyboardLayout *) createKeyboardLayout {
    return [(CGSWaylandKeymap *) _keymap copyLayout];
}

#pragma mark - CGSConnection

- (void *) nativeDisplay {
    // EGLNativeDisplayType on Wayland is the wl_display.
    return _wlDisplay;
}

- (CGPoint) mouseLocation {
    // Wayland reports the pointer only through wl_pointer events over a client's
    // own surfaces: where it was last over one is all there is to report (its
    // position outside them is not known).
    CGPoint last;
    if ([(CGSWaylandPointer *) _pointerDecoder getLastGlobalLocation: &last])
        return last;
    // A made-up origin would be indistinguishable from a real one, so this is
    // CGEventObjC.m's sentinel.
    static BOOL warned;
    if (!warned) {
        warned = YES;
        NSLog(@"CoreGraphics Wayland backend: the pointer position is not "
              @"available to Wayland clients; CGEventGetLocation() has no value "
              @"to report");
    }
    return CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX);
}

- (BOOL) isMouseButtonDown: (CGMouseButton) button {
    return [(CGSWaylandPointer *) _pointerDecoder isButtonDown: button];
}

#pragma mark - Hot keys

// Wayland has no request to grab a key for the whole session, so the hot keys of this connection are
// matched against the keys the compositor sends to the process' own wl_keyboard (CGSWaylandKeyboard asks
// -activeHotKeyUIDsForKeyCode:flags:), which is while one of the process' surfaces has the keyboard focus.
// Registration always succeeds, since no other client can hold a key combination here.
// Limitation: while none of the process' surfaces has the keyboard focus the hot keys do not report. Wayland
// itself has no global key request; the compositor-specific ways (the xdg-desktop-portal GlobalShortcuts
// interface, KDE's KGlobalAccel) are not used, since they ask the user to confirm and assign each shortcut.
- (CGSWaylandHotKeyEntry *) _hotKeyWithUID: (int) uid {
    for (CGSWaylandHotKeyEntry *entry in _hotKeys) {
        if (entry->uid == uid)
            return entry;
    }
    return nil;
}

- (void) setHotKeyWithUID: (int) uid keyCode: (CGKeyCode) keyCode flags: (CGEventFlags) flags exclusion: (int) exclusion {
    [self removeHotKeyWithUID: uid];
    CGSWaylandHotKeyEntry *entry = [[CGSWaylandHotKeyEntry alloc] init];
    entry->uid = uid;
    entry->virtualKey = keyCode;
    entry->flags = flags & kHotKeyModifierMask;
    entry->enabled = YES;
    @synchronized(self) {
        if (_hotKeys == nil)
            _hotKeys = [[NSMutableArray alloc] init];
        [_hotKeys addObject: entry];
    }
    [entry release];
}

- (BOOL) getHotKeyWithUID: (int) uid keyCode: (CGKeyCode *) outKeyCode flags: (CGEventFlags *) outFlags {
    @synchronized(self) {
        CGSWaylandHotKeyEntry *entry = [self _hotKeyWithUID: uid];
        if (entry == nil)
            return NO;
        if (outKeyCode)
            *outKeyCode = entry->virtualKey;
        if (outFlags)
            *outFlags = entry->flags;
        return YES;
    }
}

- (void) removeHotKeyWithUID: (int) uid {
    @synchronized(self) {
        CGSWaylandHotKeyEntry *entry = [self _hotKeyWithUID: uid];
        if (entry != nil)
            [_hotKeys removeObject: entry];
    }
}

- (BOOL) isHotKeyEnabledWithUID: (int) uid {
    @synchronized(self) {
        CGSWaylandHotKeyEntry *entry = [self _hotKeyWithUID: uid];
        return entry != nil && entry->enabled;
    }
}

- (void) setHotKeyWithUID: (int) uid enabled: (BOOL) enabled {
    @synchronized(self) {
        CGSWaylandHotKeyEntry *entry = [self _hotKeyWithUID: uid];
        if (entry != nil)
            entry->enabled = enabled;
    }
}

- (NSArray *) activeHotKeyUIDsForKeyCode: (CGKeyCode) keyCode flags: (uint64_t) flags {
    NSMutableArray *uids = nil;
    if (_hotKeyOperatingMode != 0)
        return nil;
    @synchronized(self) {
        for (CGSWaylandHotKeyEntry *entry in _hotKeys) {
            if (entry->enabled && entry->virtualKey == keyCode && entry->flags == (flags & kHotKeyModifierMask)) {
                if (uids == nil)
                    uids = [NSMutableArray array];
                [uids addObject: @(entry->uid)];
            }
        }
    }
    return uids;
}

// The outputs that have reported a mode, in the order the compositor announced them. The first is
// the main display, and a display's ID is its place in this list plus one.
- (NSArray *) _outputsWithModes {
    NSMutableArray *result = [NSMutableArray array];
    for (CGSWaylandOutput *output in _outputs) {
        if (output->_current.width > 0 && output->_current.height > 0)
            [result addObject: output];
    }
    return result;
}

static NSDictionary *modeDictionary(int32_t width, int32_t height, double refresh, CGFloat scale) {
    return @{
        @"Width": @((unsigned) lround(width / scale)),
        @"Height": @((unsigned) lround(height / scale)),
        @"Depth": @(24),
        @"RefreshRate": @(refresh),
        @"PixelWidth": @(width),
        @"PixelHeight": @(height),
    };
}

// The compositor's logical layout when every output has described itself (xdg-output); otherwise,
// with the core protocol alone, the outputs side by side in announcement order.
- (NSArray<CGSScreen *> *) buildScreens {
    NSArray *outputs = [self _outputsWithModes];
    if ([outputs count] == 0)
        return nil;

    BOOL logical = YES;
    for (CGSWaylandOutput *output in outputs) {
        if (!output->_logicalCurrent.hasPosition || !output->_logicalCurrent.hasSize)
            logical = NO;
    }
    CGSWaylandOutput *first = [outputs objectAtIndex: 0];
    CGFloat mainHeight = 0;
    if (!logical) {
        BOOL rotated = (first->_current.transform & 1) != 0;
        mainHeight = (rotated ? first->_current.width : first->_current.height) / (CGFloat) first->_current.scale;
    }

    NSMutableArray<CGSScreen *> *screens = [NSMutableArray array];
    CGFloat x = 0;
    for (CGSWaylandOutput *output in outputs) {
        BOOL rotated = (output->_current.transform & 1) != 0;
        CGFloat width = rotated ? output->_current.height : output->_current.width;
        CGFloat height = rotated ? output->_current.width : output->_current.height;
        CGRect bounds;
        if (logical) {
            // The origin is the main display's top-left corner.
            bounds = CGRectMake((CGFloat) output->_logicalCurrent.x - first->_logicalCurrent.x,
                                (CGFloat) output->_logicalCurrent.y - first->_logicalCurrent.y,
                                output->_logicalCurrent.width, output->_logicalCurrent.height);
        } else {
            CGFloat w = width / output->_current.scale, h = height / output->_current.scale;
            // Side by side, bottom edges aligned with the main display's.
            bounds = CGRectMake(x, mainHeight - h, w, h);
        }

        // Whole scale factors only: a compositor that scales an output by 1.5 reports 2, and the
        // logical size says so even when wl_output rounds down.
        CGFloat scale = output->_current.scale;
        if (logical && output->_logicalCurrent.width > 0)
            scale = MAX(scale, ceil(width / output->_logicalCurrent.width - 0.01));

        CGSScreen *screen = [[CGSScreen new] autorelease];
        screen.displayID = (CGDirectDisplayID) ([screens count] + 1);
        screen.bounds = bounds;
        screen.backingScale = scale;
        NSString *outputName = [output->_outputDescription length] > 0 ? output->_outputDescription : output->_outputName;
        screen.name = [outputName length] > 0 ? outputName : nil;
        screen.colorInfo = [(WaylandColorManager *) _color infoForOutput: output->_proxy];

        // The output-management heads list every mode the output can be set to; wl_output lists only what the
        // compositor chooses to announce.
        NSMutableArray *modes = [NSMutableArray array];
        NSArray *listed = [_outputManager modesForOutputAtX: output->_current.x y: output->_current.y
                                                      width: output->_current.width
                                                     height: output->_current.height];
        if ([listed count] == 0)
            listed = output->_modes;
        for (NSDictionary *mode in listed) {
            [modes addObject: modeDictionary([[mode objectForKey: @"Width"] intValue],
                                             [[mode objectForKey: @"Height"] intValue],
                                             [[mode objectForKey: @"RefreshRate"] doubleValue], scale)];
        }
        NSDictionary *current = modeDictionary(output->_current.width, output->_current.height,
                                               output->_current.refresh / 1000.0, scale);
        CFIndex currentIndex = -1;
        for (NSUInteger i = 0; i < [modes count]; i++) {
            NSDictionary *mode = [modes objectAtIndex: i];
            if ([[mode objectForKey: @"PixelWidth"] isEqual: [current objectForKey: @"PixelWidth"]] &&
                [[mode objectForKey: @"PixelHeight"] isEqual: [current objectForKey: @"PixelHeight"]] &&
                fabs([[mode objectForKey: @"RefreshRate"] doubleValue] -
                     [[current objectForKey: @"RefreshRate"] doubleValue]) < 0.01) {
                currentIndex = (CFIndex) i;
                break;
            }
        }
        if (currentIndex < 0) {
            [modes addObject: current];
            currentIndex = (CFIndex) [modes count] - 1;
        }
        screen.modes = modes;
        screen.currentMode = currentIndex;

        [screens addObject: screen];
        x += bounds.size.width;
    }
    return [[screens copy] autorelease];
}

// Modes can be changed only through wlr-output-management; a compositor without it keeps its
// output modes (NO).
- (BOOL) setMode: (NSDictionary *) mode forScreen: (int) screenIndex {
    NSArray *outputs;
    @synchronized (self) {
        outputs = [[self _outputsWithModes] retain];
    }
    [outputs autorelease];
    if (_outputManager == nil || mode == nil || screenIndex < 0 || screenIndex >= (int) [outputs count])
        return NO;

    CGSWaylandOutput *output = outputs[screenIndex];
    int width = [[mode objectForKey: @"PixelWidth"] intValue];
    int height = [[mode objectForKey: @"PixelHeight"] intValue];
    BOOL changed = [_outputManager
            setModeWidth: width
                  height: height
                 refresh: (int) lround([[mode objectForKey: @"RefreshRate"] doubleValue] * 1000.0)
            forOutputAtX: output->_current.x y: output->_current.y
            currentWidth: output->_current.width currentHeight: output->_current.height];
    if (changed) {
        // wl_output.done for the new mode normally came with the round trips; if it is still on its way, wait
        // for it so that the displays are up to date.
        for (int i = 0; i < 200 && (output->_current.width != width || output->_current.height != height); i++) {
            if (WL.wl_display_roundtrip(_wlDisplay) < 0)
                break;
            usleep(5000);
        }
        [self invalidateScreens];
    }
    return changed;
}

- (CGSWindow *) newWindow: (CGSRegionRef) region {
    CGSWindowID windowID = _nextWindowId++;
    CGSWindowWayland *window =
            [[CGSWindowWayland alloc] initWithRegion: region
                                          connection: self
                                            windowID: windowID];
    if (window == nil)
        return nil;

    @synchronized (_windows) {
        [_windows setObject: window forKey: [NSNumber numberWithInt: windowID]];
    }
    [window release];
    return window;
}

@end
