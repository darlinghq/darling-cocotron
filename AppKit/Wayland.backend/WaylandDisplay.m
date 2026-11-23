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
#import "../private-include/AppKit/CarbonKeys.h"
#import "../private-include/AppKit/NSEventTime.h"
#import "NSEvent_gesture.h"
#import "NSEvent_mouse.h"
#import "WaylandCursor.h"
#import "WaylandScale.h"
#import "WaylandOutputManager.h"
#import "WaylandPasteboard.h"
#import "WaylandDraggingManager.h"
#import "WaylandAppMenu.h"
#import "../private-include/AppKit/NSGlobalMenu+Private.h"
#import <OpenGL/CGLInternal.h>
#include <dlfcn.h>
#import "WaylandLibrary.h"
#import "WaylandPointerLock.h"
#import "WaylandProtocol.h"
#import "WaylandWindow.h"
#import "WaylandAppMenu.h"
#import "WaylandToplevelIcon.h"
#import "../private-include/AppKit/NSGlobalMenu+Private.h"
#import "../DarlingWindowLevelPolicy.h"
#import "../../CoreGraphics/DarlingUnicodeKeyLayout.h"
#import "../../CoreGraphics/DarlingUnicodeKeyLayoutCompose.h"
#import <CoreGraphics/CGSKeySymToUnicodePrivate.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreFoundation/CFNotificationCenter.h>
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
    NSString *_outputName;
}
@end
@implementation WaylandScreen
- (CGFloat) backingScaleFactor { return _waylandScale; }
// The output's description or name as the compositor reports it, else the name from an EDID set on the screen, else the
// generic name.
- (NSString *) localizedName {
    return _outputName != nil && [self edid] == nil ? _outputName : [super localizedName];
}
- (void) dealloc {
    [_outputName release];
    [super dealloc];
}
@end

// Mode pixels are untransformed. Publish v2 properties together at wl_output.done.
// x, y: the output's position in the compositor's layout (wl_output.geometry).
typedef struct { int32_t width, height, refresh, scale, transform, x, y; } WaylandOutputState;

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
    // wl_output version 4: the connector name and the human readable description, published at done.
    NSString *_name, *_pendingName, *_description, *_pendingDescription;
}
@end

@implementation WaylandOutput

- (void) dealloc {
    [_name release];
    [_pendingName release];
    [_description release];
    [_pendingDescription release];
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
            case WaylandObjectLayerSurface:
                [(WaylandWindow *) object handleEvent: opcode
                                                 kind: objectKind
                                                proxy: proxy
                                            arguments: args];
                break;
            case WaylandObjectLogicalOutput:
                [((WaylandOutput *) object)->_display logicalOutputEvent: opcode
                                                                  output: object arguments: args];
                break;
            case WaylandObjectOutputManager:
            case WaylandObjectOutputHead:
            case WaylandObjectOutputHeadMode:
            case WaylandObjectOutputConfiguration:
                [(id<WaylandOutputManagementEvents>) object handleEvent: opcode kind: objectKind
                                                                  proxy: proxy arguments: args];
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

static void socketCallback(CFSocketRef socket, CFSocketCallBackType type,
                           CFDataRef address, const void *data, void *info)
{
    [(WaylandDisplay *) info processPendingEvents];
}

// A process asked (CGS, _CGSActivateProcess) that this one activate its windows.
static void activationRequestedCallback(CFNotificationCenterRef center, void *observer,
                                        CFNotificationName name, const void *object,
                                        CFDictionaryRef userInfo)
{
    [(WaylandDisplay *) observer performSelectorOnMainThread: @selector(requestActivation)
                                                  withObject: nil
                                               waitUntilDone: NO];
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

    self = [super init];
    if (self == nil)
        return nil;

    _outputs = [NSMutableArray new];
    _afterDispatch = [NSMutableArray new];
    _windows = CFArrayCreateMutable(NULL, 0, NULL);
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
    else
        // The Text Input Sources API describes a keyboard layout whether or not the
        // seat has a keyboard (a compositor with no input devices never sends a
        // keymap), so start with the system default layout; the compositor's keymap
        // replaces it when one arrives.
        [self installKeymap: WL.xkb_keymap_new_from_names(_xkbContext, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS)];

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

    // Another process asks for the activation of this one's windows with a Darwin
    // notification named after this process (see _CGSActivateProcess).
    char notificationName[64];
    snprintf(notificationName, sizeof(notificationName),
             kCGSProcessActivationNotificationPrefix "%d", (int) getpid());
    CFStringRef notification = CFStringCreateWithCString(NULL, notificationName,
                                                         kCFStringEncodingUTF8);
    if (notification != NULL) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), self,
                                        activationRequestedCallback, notification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFRelease(notification);
    }

    // Windows ordered in while the application was not active are mapped once it is.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationBecameActive:)
                                                 name: NSApplicationDidBecomeActiveNotification
                                               object: nil];

    [self runAfterDispatchBlocks];
    [self flush];

    // The general pasteboard and the compositor's clipboard show the same contents.
    NSPasteboardRegisterHostClipboard(_generalPasteboard);

    return self;
}

- (void) dealloc {
    [_appMenu release];
    [_draggingManager invalidate];
    [_draggingManager release];
    [self consumeDragPress];
    [_generalPasteboard invalidate];
    [_generalPasteboard release];
    [self stopKeyRepeat];
    [self cancelPendingModifier];
    [_heldKeyIdentities release];

    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), self);
    [self cancelActivationRequest];

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
    [_outputManager release];
    _outputManager = nil;
    [_appMenu release];
    _appMenu = nil;
    [_toplevelIcons release];
    _toplevelIcons = nil;
    if (_wlDisplay != NULL) {
        // wl_display_disconnect() doesn't free proxies.
        struct wl_proxy *proxies[] = {_imageCursorBuffer, _cursorFractionalScale, _cursorSurface,
                                      _lockedPointer, _relativePointer, _pointerConstraints, _relativePointerManager,
                                      _textInput, _textInputManager, _pinchGesture, _pointerGestures, _pointer, _keyboard,
                                      _seat, _decorationManager, _dataDeviceManager, _wmBase,
                                      _shm, _viewporter, _fractionalScaleManager, _activationToken, _activation, _appMenuManager, _subcompositor, _logicalOutputManager,
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

    [super dealloc];
}

#pragma mark - Connection and event loop

- (void) flush {
    if (_wlDisplay != NULL)
        WL.wl_display_flush(_wlDisplay);
}

// The windows carry the application icon (see WaylandToplevelIcon.h): when the application sets another
// one, the windows already shown are given it too.
- (void) updateWindowIcons {
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) updateToplevelIcon];
}

- (void) applicationIconImageChanged {
    [super applicationIconImageChanged];
    [_toplevelIcons applicationIconChanged];
}

- (void) connectionFailed {
    NSLog(@"Wayland backend: lost the connection to the compositor (error %d)",
          WL.wl_display_get_error(_wlDisplay));
    exit(1);
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

- (NSEvent *) nextEventMatchingMask: (NSUInteger) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue
{
    [self processPendingEvents];

    return [super nextEventMatchingMask: mask untilDate: untilDate inMode: mode dequeue: dequeue];
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
    } else if (strcmp(interface, "zwp_pointer_gestures_v1") == 0 && _pointerGestures == NULL) {
        // Version 2 adds the release request.
        _pointerGesturesName = name;
        _pointerGestures = [self bindGlobal: name interface: &zwp_pointer_gestures_v1_interface
                                    version: MIN(version, 2) kind: 0 object: nil];
        [self attachPinchGesture];
    } else if (strcmp(interface, "zwp_text_input_manager_v3") == 0 && _textInputManager == NULL) {
        _textInputManagerName = name;
        _textInputManager = [self bindGlobal: name interface: &zwp_text_input_manager_v3_interface
                                     version: 1 kind: 0 object: nil];
        [self attachTextInput];
    } else if (strcmp(interface, "zwp_pointer_constraints_v1") == 0 && _pointerConstraints == NULL) {
        _pointerConstraintsName = name;
        _pointerConstraints = [self bindGlobal: name interface: &zwp_pointer_constraints_v1_interface
                                       version: 1 kind: 0 object: nil];
        [self updatePointerLock];
    } else if (strcmp(interface, "zwp_relative_pointer_manager_v1") == 0 && _relativePointerManager == NULL) {
        _relativePointerManagerName = name;
        _relativePointerManager = [self bindGlobal: name interface: &zwp_relative_pointer_manager_v1_interface
                                           version: 1 kind: 0 object: nil];
        [self updatePointerLock];
    } else if (strcmp(interface, "wl_seat") == 0 && _seat == NULL) {
        // Version 4 adds wl_keyboard.repeat_info, 5 wl_pointer.frame.
        _seat = [self bindGlobal: name
                       interface: &wl_seat_interface
                         version: MIN(version, 5)
                            kind: WaylandObjectSeat
                          object: self];
        [self attachTextInput];
    } else if (strcmp(interface, "zxdg_output_manager_v1") == 0 && _logicalOutputManager == NULL) {
        _logicalOutputManagerName = name;
        _logicalOutputManager = [self bindGlobal: name interface: &zxdg_output_manager_v1_interface
                                        version: MIN(version, 3) kind: 0 object: nil];
        for (WaylandOutput *output in _outputs) [self attachLogicalOutput: output];
    } else if (strcmp(interface, "zwlr_output_manager_v1") == 0 && _outputManager == nil) {
        _outputManagerName = name;
        _outputManager = [WaylandOutputManager alloc];
        struct wl_proxy *proxy = [self bindGlobal: name interface: &zwlr_output_manager_v1_interface
                                          version: 1 kind: WaylandObjectOutputManager
                                           object: _outputManager];
        _outputManager = [_outputManager initWithDisplay: _wlDisplay manager: proxy];
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
    if (_textInputManager && name == _textInputManagerName) {
        [self detachTextInput];
        WaylandMarshal(_textInputManager, WP_TEXT_INPUT_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _textInputManager = NULL; _textInputManagerName = 0;
        return;
    }
    if (_pointerGestures && name == _pointerGesturesName) {
        [self detachPinchGesture];
        if (WL.wl_proxy_get_version(_pointerGestures) >= 2)
            WaylandMarshal(_pointerGestures, WP_GESTURES_RELEASE, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        else
            WL.wl_proxy_destroy(_pointerGestures);
        _pointerGestures = NULL; _pointerGesturesName = 0;
        return;
    }
    if ((_pointerConstraints && name == _pointerConstraintsName) ||
        (_relativePointerManager && name == _relativePointerManagerName))
    {
        [self releasePointerLock];
        if (name == _pointerConstraintsName) {
            WaylandMarshal(_pointerConstraints, WP_POINTER_CONSTRAINTS_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            _pointerConstraints = NULL; _pointerConstraintsName = 0;
        } else {
            WaylandMarshal(_relativePointerManager, WP_RELATIVE_POINTER_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            _relativePointerManager = NULL; _relativePointerManagerName = 0;
        }
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
    if (_outputManager && name == _outputManagerName) {
        [_outputManager release];
        _outputManager = nil;
        _outputManagerName = 0;
        return;
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
            for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
                [(WaylandWindow *) CFArrayGetValueAtIndex(_windows, i) outputsChanged];
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
    // Not for the output's first description: the screens are being set up then.
    BOOL changed = output->_current.width > 0 && output->_current.height > 0 &&
                   memcmp(&output->_current, &output->_pending, sizeof output->_current) != 0;
    output->_current = output->_pending;
    [output->_name release];
    output->_name = [output->_pendingName copy];
    [output->_description release];
    output->_description = [output->_pendingDescription copy];
    if (output->_logicalVersion >= 3)
        output->_logicalCurrent = output->_logicalPending;
    [output->_modes release];
    output->_modes = [output->_pendingModes copy];
    [self invalidateScreens];
    [_draggingManager outputsChanged];
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *window = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        [window scheduleScaleUpdate];
        [window outputsChanged];
    }
    if (changed) {
        // One change comes as several events; merge them into one notification for the next run loop pass.
        NSNotification *note = [NSNotification
                notificationWithName: NSApplicationDidChangeScreenParametersNotification
                              object: NSApp];
        [[NSNotificationQueue defaultQueue] enqueueNotification: note
                                                   postingStyle: NSPostASAP
                                                   coalesceMask: NSNotificationCoalescingOnName |
                                                                 NSNotificationCoalescingOnSender
                                                       forModes: nil];
    }
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

    case WaylandObjectTextInput:
        [self textInputEvent: opcode arguments: args];
        break;

    case WaylandObjectActivationToken:
        if (proxy == _activationToken && opcode == WP_ACTIVATION_TOKEN_EV_DONE)
            [self activationTokenDone: args[0].s];
        break;

    case WaylandObjectLockedPointer:
        if (proxy == _lockedPointer) {
            _pointerLocked = opcode == WP_LOCKED_POINTER_EV_LOCKED;
        }
        break;

    case WaylandObjectRelativePointer: {
        double dx, dy;
        if (proxy == _relativePointer && WaylandRelativeMotionDelta(opcode, args, &dx, &dy))
            [self pointerRelativeMotionByX: dx y: dy];
        break;
    }

    case WaylandObjectKeyboardSync:
        if (proxy == _modifierSync && opcode == WP_CALLBACK_EV_DONE)
            [self flushPendingModifier];
        break;

    case WaylandObjectKeyboard:
        [self keyboardEvent: opcode arguments: args];
        break;

    case WaylandObjectTouch:
        [self touchEvent: opcode arguments: args];
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
        [self updatePointerLock];
    } else if (!(capabilities & WP_SEAT_CAPABILITY_POINTER) && _pointer != NULL) {
        [self detachPinchGesture];
        [self releasePointerLock];
        [_draggingManager cancel];
        [self consumeDragPress];
        [self cancelFingerScroll];
        [self releaseInputDevice: &_pointer opcode: WP_POINTER_RELEASE];
        _pointerWindow = nil;
        _pointerEnterSerial = 0;
        _pressedButtons = 0;
        [self discardPendingScroll];
        _wlLastClickWindow = nil;
        [_buttonClickCounts removeAllObjects];
    }

    if ((capabilities & WP_SEAT_CAPABILITY_TOUCH) && _touch == NULL) {
        args[0].o = NULL;
        _touch = WaylandCreateObject(_seat, WP_SEAT_GET_TOUCH, &wl_touch_interface, args,
                                     WaylandObjectTouch, self);
    } else if (!(capabilities & WP_SEAT_CAPABILITY_TOUCH) && _touch != NULL) {
        [self releaseInputDevice: &_touch opcode: WP_TOUCH_RELEASE];
        [self touchCancel];
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

- (void) pointerEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    if (opcode != WP_POINTER_EV_AXIS && opcode != WP_POINTER_EV_FRAME &&
        opcode != WP_POINTER_EV_AXIS_SOURCE && opcode != WP_POINTER_EV_AXIS_STOP)
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

    case WP_POINTER_EV_LEAVE: {
        WaylandWindow *left = _pointerWindow;

        [self cancelFingerScroll];
        _pressedButtons = 0;
        [_buttonClickCounts removeAllObjects];
        [self consumeDragPress];
        _lastMouseLocation = [self mouseLocation];
        if (left != nil && !_pointerLocked)
            [self performAfterDispatch: ^{ [self pointerLeftWindow: left]; }];
        _pointerWindow = nil;
        _pointerEnterSerial = 0;
        [self discardPendingScroll];
        break;
    }

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

    case WP_POINTER_EV_AXIS_SOURCE:
        _pendingScrollSourceNamed = YES;
        _pendingScrollFinger = args[0].u == WP_POINTER_AXIS_SOURCE_FINGER;
        break;

    case WP_POINTER_EV_AXIS_STOP:
        [self startPendingScrollFrame];
        if (args[1].u <= WP_POINTER_AXIS_HORIZONTAL_SCROLL)
            _pendingScrollStoppedAxes |= 1u << args[1].u;
        break;

    case WP_POINTER_EV_FRAME:
        [self postPendingScroll];
        break;
    }
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

- (void) pointerMotionToX: (CGFloat) x y: (CGFloat) y {
    // Track the position even when no surface is under the pointer. Opening a
    // menu maps a new surface under a stationary cursor, so the compositor
    // sends leave and then motion with no window; dropping that motion left
    // _pointerSurfacePoint stale and the following button landed wherever the
    // pointer last was over a known surface.
    CGPoint previousPoint = _pointerSurfacePoint;
    _pointerSurfacePoint = CGPointMake(x, y);

    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return;

    NSPoint location = [window transformPoint: _pointerSurfacePoint];
    NSPoint last = [window mouseLocationOutsideOfEventStream];
    [window setLastKnownCursorPosition: location];
    [self accumulateMouseDeltaX: location.x - last.x y: last.y - location.y];

    // The pointer moved: a cursor hidden until then comes back, even when the
    // application does not want the mouse-moved event. A compositor repeats the
    // position when a surface changes under a still pointer, and a locked pointer
    // moves nothing on screen: neither is a move. The AppKit work runs outside
    // libwayland's listener, as for the cursor below.
    if (!_pointerLocked && (x != previousPoint.x || y != previousPoint.y))
        [self performAfterDispatch: ^{ [self pointerMoved]; }];

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
        // deltaY is positive downward, as AppKit and the X11 backend report it;
        // locations are bottom-left, hence last - location.
        NSEvent *event = [NSEvent mouseEventWithType: type
                                            location: location
                                       modifierFlags: [self currentModifierFlags]
                                              window: delegate
                                          clickCount: 1
                                              deltaX: location.x - last.x
                                              deltaY: last.y - location.y];
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
        // The compositor may activate the window for this very click, before
        // or after the press reaches us; the press is judged by what we knew
        // when it arrived, not by what the queue shows when it is taken.
        [(NSEvent_mouse *) event _setWindowWasKeyOnArrival: [[window delegate] isKeyWindow]];
        _inputEvent = [event retain];
        _inputWindow = window;
    }
    [self postEvent: event atStart: NO];
}

// wl_pointer.axis values are lengths in surface-local coordinates, the space pointer motion uses
// (https://gitlab.freedesktop.org/wayland/wayland/-/blob/main/protocol/wayland.xml). One wheel
// notch is this many of them; precise scrolling reports them as they are.
static const CGFloat WaylandAxisUnitsPerNotch = 10.0;

- (void) startPendingScrollFrame {
    if (_pendingScrollActive)
        return;
    _pendingScrollWindow = _pointerWindow;
    _pendingScrollSurfacePoint = _pointerSurfacePoint;
    _pendingScrollModifiers = [self currentModifierFlags];
    _pendingScrollActive = YES;
}

- (void) discardPendingScroll {
    _pendingScrollX = _pendingScrollY = 0;
    _pendingScrollWindow = nil;
    _pendingScrollActive = NO;
    _pendingScrollFinger = _pendingScrollSourceNamed = NO;
    _pendingScrollStoppedAxes = 0;
    _fingerScrollActive = NO;
    _fingerScrollWindow = nil;
}

- (void) pointerAxis: (uint32_t) axis value: (CGFloat) value {
    if (_pointerWindow == nil)
        return;

    // Scrolling down is positive; the X11 backend reports a notch up as deltaY 1, so the sum keeps
    // the opposite sign.
    if (axis != WP_POINTER_AXIS_HORIZONTAL_SCROLL &&
        axis != WP_POINTER_AXIS_VERTICAL_SCROLL)
        return;
    [self startPendingScrollFrame];
    if (axis == WP_POINTER_AXIS_HORIZONTAL_SCROLL)
        _pendingScrollX -= value;
    else if (axis == WP_POINTER_AXIS_VERTICAL_SCROLL)
        _pendingScrollY -= value;

    // wl_pointer.frame was added in version 5. Older seats deliver each axis
    // event independently, so preserve their immediate behavior.
    if (WL.wl_proxy_get_version(_pointer) < 5)
        [self postPendingScroll];
}

- (void) postPendingScroll {
    CGFloat unitsX = _pendingScrollX;
    CGFloat unitsY = _pendingScrollY;
    WaylandWindow *window = _pendingScrollWindow;
    CGPoint surfacePoint = _pendingScrollSurfacePoint;
    NSUInteger modifiers = _pendingScrollModifiers;
    BOOL finger = _pendingScrollFinger;
    BOOL sourceNamed = _pendingScrollSourceNamed;
    uint32_t stoppedAxes = _pendingScrollStoppedAxes;
    _pendingScrollX = _pendingScrollY = 0;
    _pendingScrollWindow = nil;
    _pendingScrollActive = NO;
    _pendingScrollFinger = _pendingScrollSourceNamed = NO;
    _pendingScrollStoppedAxes = 0;

    BOOL moved = unitsX != 0 || unitsY != 0;
    if (window == nil)
        return;

    NSEventPhase phase = NSEventPhaseNone;
    // GUESS: the source is optional in a frame, so a finger sequence in progress also continues in
    // a frame that names no source, and a frame without motion (an axis_stop alone) can end it
    // whatever source it names. A frame that moves and names another source is not part of it.
    if (finger || (_fingerScrollActive && (!sourceNamed || !moved))) {
        // GUESS: the protocol only says a finger source sends axis_stop when the finger lifts.
        // The first frame with motion is taken as the began phase and later ones as changed. A
        // sequence ends in a frame whose axis_stop covers every axis that moved in it (so also in
        // one with no motion); an axis_stop beside motion on the other axis is a change, since the
        // protocol says that axis is still moving then.
        // A first frame that has motion and an axis_stop for it gives began only, since one event cannot
        // be both began and ended; the sequence then ends at the next axis_stop.
        uint32_t movedAxes = (unitsX != 0 ? 1u << WP_POINTER_AXIS_HORIZONTAL_SCROLL : 0) |
                             (unitsY != 0 ? 1u << WP_POINTER_AXIS_VERTICAL_SCROLL : 0);
        BOOL ends = _fingerScrollActive && stoppedAxes != 0 && (movedAxes & ~stoppedAxes) == 0;
        if (ends)
            phase = NSEventPhaseEnded;
        else if (moved)
            phase = _fingerScrollActive ? NSEventPhaseChanged : NSEventPhaseBegan;
        if (phase == NSEventPhaseNone)
            return;
        _fingerScrollActive = phase != NSEventPhaseEnded;
        _fingerScrollWindow = _fingerScrollActive ? window : nil;
        _fingerScrollSurfacePoint = surfacePoint;
    } else if (!moved) {
        return;
    }
    BOOL precise = phase != NSEventPhaseNone;

    NSEvent *event = [NSEvent
            mouseEventWithType: NSScrollWheel
                      location: [window transformPoint: surfacePoint]
                 modifierFlags: modifiers
                        window: [window delegate]
                    clickCount: 1
                        deltaX: unitsX / WaylandAxisUnitsPerNotch
                        deltaY: unitsY / WaylandAxisUnitsPerNotch];
    if (precise)
        // GUESS: the line deltas stay set to the wheel-notch equivalent of the axis values, so code
        // that reads deltaX and deltaY keeps scrolling by a proportional amount.
        [(NSEvent_mouse *) event _setPreciseScrollingDeltaX: unitsX
                                                     deltaY: unitsY
                                                      phase: phase];
    [self postEvent: event atStart: NO];
}

// A pointer that leaves, a seat that loses its pointer or a window that goes away in the middle of
// a finger scroll ends it with the cancelled phase, as a pinch does. GUESS: the documentation of
// NSEvent.phase lists cancelled as an ending phase of a gesture but not when it is used.
- (void) cancelFingerScroll {
    WaylandWindow *window = _fingerScrollWindow;
    CGPoint surfacePoint = _fingerScrollSurfacePoint;
    BOOL known = _fingerScrollActive && window != nil && [self windowIsKnown: window];
    _fingerScrollActive = NO;
    _fingerScrollWindow = nil;
    if (!known)
        return;

    NSEvent *event = [NSEvent
            mouseEventWithType: NSScrollWheel
                      location: [window transformPoint: surfacePoint]
                 modifierFlags: [self currentModifierFlags]
                        window: [window delegate]
                    clickCount: 1
                        deltaX: 0
                        deltaY: 0];
    [(NSEvent_mouse *) event _setPreciseScrollingDeltaX: 0 deltaY: 0 phase: NSEventPhaseCancelled];
    [self postEvent: event atStart: NO];
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

// Wayland clients can't move the pointer, but while it is locked the cursor is
// the application's own and a warp only moves where it is. That position is
// where mouseLocation reports it and where the pointer reappears on unlock.
// Without a lock the call does nothing, and nothing pretends otherwise.
// position is in CoreGraphics' global space, as -[NSDisplay warpMouse:] documents.
- (void) warpMouse: (NSPoint) position {
    WaylandWindow *window = _lockWindow;
    if (!_pointerLocked || window == nil)
        return;
    NSArray *screens = [self screens];
    double primaryHeight = [screens count] > 0 ? NSHeight([[screens objectAtIndex: 0] frame]) : 0;
    double screenX, screenY;
    WaylandScreenPointFromCG(position.x, position.y, primaryHeight, &screenX, &screenY);
    NSRect frame = [window frame];
    NSPoint offset = [window contentOffset];
    WaylandWarp warp = WaylandWarpTarget(screenX, screenY, frame.origin.x, frame.origin.y,
                                         frame.size.width, frame.size.height, offset.x, offset.y);
    _pointerSurfacePoint = CGPointMake(warp.surfaceX, warp.surfaceY);
    // Window coordinates, like every other writer of the last known position.
    [window setLastKnownCursorPosition: NSMakePoint(warp.windowX, warp.windowY)];
}

- (void) grabMouse: (BOOL) doGrab {
    _pointerLockRequested = doGrab;
    [self updatePointerLock];
}

#pragma mark - Pointer lock

// The window to lock: the one activated last. The lock activates once it also
// has pointer focus.
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
- (void) updatePointerLock {
    WaylandWindow *target = _pointerLockRequested ? [self pointerLockTarget] : nil;
    BOOL possible = _pointer != NULL && _pointerConstraints != NULL && _relativePointerManager != NULL;
    static BOOL loggedMissing;
    if (_pointerLockRequested && !loggedMissing &&
        (_pointerConstraints == NULL || _relativePointerManager == NULL)) {
        loggedMissing = YES;
        NSLog(@"Wayland backend: relative mouse mode was requested, but the compositor offers no %s: "
              @"the cursor stays free and no deltas are delivered",
              _pointerConstraints == NULL ? "zwp_pointer_constraints_v1"
                                          : "zwp_relative_pointer_manager_v1");
    }
    if (!possible || target == nil || (_lockWindow != nil && _lockWindow != target)) {
        [self releasePointerLock];
        if (!possible || target == nil)
            return;
    }
    if (_lockedPointer != NULL)
        return;
    _lockWindow = target;
    _lockedPointer = WaylandLockPointer(_pointerConstraints, [target surface], _pointer);
    _relativePointer = WaylandGetRelativePointer(_relativePointerManager, _pointer);
    WL.wl_proxy_add_dispatcher(_lockedPointer, WaylandDispatch,
                               (void *) (uintptr_t) WaylandObjectLockedPointer, self);
    WL.wl_proxy_add_dispatcher(_relativePointer, WaylandDispatch,
                               (void *) (uintptr_t) WaylandObjectRelativePointer, self);
    [self flush];
}

- (void) releasePointerLock {
    if (_lockedPointer == NULL)
        return;
    WaylandWindow *window = _lockWindow;
    _lockWindow = nil;
    _pointerLocked = NO;
    // The pointer comes back where the application left its cursor.
    WaylandUnlockPointer(_lockedPointer, _relativePointer, [window surface],
                         _pointerSurfacePoint.x, _pointerSurfacePoint.y);
    _lockedPointer = _relativePointer = NULL;
    [self flush];
}

// A locked pointer moves nothing on screen: the event carries the delta at the
// frozen cursor position, as macOS reports it while the cursor is disassociated.
- (void) pointerRelativeMotionByX: (CGFloat) dx y: (CGFloat) dy {
    WaylandWindow *window = _lockWindow;
    if (!_pointerLocked || window == nil)
        return;
    NSEventType type = NSMouseMoved;
    if (_pressedButtons & 1)
        type = NSLeftMouseDragged;
    else if (_pressedButtons & 2)
        type = NSRightMouseDragged;
    [self accumulateMouseDeltaX: dx y: dy];
    NSWindow *delegate = [window delegate];
    if (delegate == nil || (type == NSMouseMoved && ![delegate acceptsMouseMovedEvents]))
        return;
    [self postEvent: [NSEvent mouseEventWithType: type
                                        location: [window transformPoint: _pointerSurfacePoint]
                                   modifierFlags: [self currentModifierFlags]
                                          window: delegate
                                      clickCount: 1
                                          deltaX: dx
                                          deltaY: dy]
            atStart: NO];
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
            modifierFlags: [self currentModifierFlags] timestamp: NSEventCurrentTime()
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
        [self applicationFocusMayHaveLeft];
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
            [self publishKeyboardLayout];
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

// A keymap the client cannot use (format no_keymap, an empty or unreadable xkb_v1 map) leaves the
// keymap in force as it was. The wl_keyboard protocol sends no_keymap when the client has to
// interpret raw key codes itself, and a compositor may replace the keymap at any time, so input
// must survive both. With no keymap yet, the system default layout (the evdev rules, honouring
// the XKB_DEFAULT_* variables) interprets the raw codes.
- (struct xkb_keymap *) keymapFromFormat: (uint32_t) format fd: (int) fd size: (uint32_t) size {
    struct xkb_keymap *keymap = NULL;

    if (format == WP_KEYBOARD_KEYMAP_FORMAT_XKB_V1 && size == 0) {
        NSLog(@"Wayland backend: the compositor sent an empty keymap");
    } else if (format == WP_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        char *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (map == MAP_FAILED) {
            NSLog(@"Wayland backend: cannot map the keymap: %s", strerror(errno));
        } else {
            keymap = WL.xkb_keymap_new_from_buffer(
                    _xkbContext, map, strnlen(map, size), XKB_KEYMAP_FORMAT_TEXT_V1,
                    XKB_KEYMAP_COMPILE_NO_FLAGS);
            munmap(map, size);
            if (keymap == NULL)
                NSLog(@"Wayland backend: cannot compile the compositor's keymap");
        }
    } else if (format != WP_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP) {
        NSLog(@"Wayland backend: unsupported keymap format %u", format);
    }
    return keymap;
}

- (void) keymapWithFormat: (uint32_t) format fd: (int) fd size: (uint32_t) size {
    struct xkb_keymap *keymap = NULL;

    if (_xkbContext != NULL) {
        keymap = [self keymapFromFormat: format fd: fd size: size];
        if (keymap == NULL && _xkbKeymap == NULL)
            keymap = WL.xkb_keymap_new_from_names(_xkbContext, NULL,
                                                  XKB_KEYMAP_COMPILE_NO_FLAGS);
    }
    close(fd);

    [self installKeymap: keymap];
}

// Makes keymap (nil: none usable; the reference is taken over) the one that interprets key codes
// and that the Text Input Sources API describes.
- (void) installKeymap: (struct xkb_keymap *) keymap {
    struct xkb_state *state = keymap != NULL ? WL.xkb_state_new(keymap) : NULL;
    if (state == NULL) {
        if (keymap != NULL)
            WL.xkb_keymap_unref(keymap);
        if (_xkbContext != NULL && _xkbKeymap == NULL)
            NSLog(@"Wayland backend: no usable keymap, keyboard input is disabled");
        return;
    }

    [self stopKeyRepeat];
    if (_xkbState != NULL)
        WL.xkb_state_unref(_xkbState);
    if (_xkbKeymap != NULL)
        WL.xkb_keymap_unref(_xkbKeymap);
    _xkbKeymap = keymap;
    _xkbState = state;
    _publishedKeymap = NULL;
    [self publishKeyboardLayout];
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

// The same mapping as the X11 backend's modifier flags for a key state.
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
    // CGSKeySymToUnicode knows AppKit's function key codes; XKB keysyms
    // have the same values as X11 keysyms.
    uint32_t codepoint = CGSKeySymToUnicode(keysym);
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
    // Key events belong to the key window whichever surface of the application the compositor
    // gave the focus to. That matters when the key window is a window with alpha 0, which is
    // never shown and so never gets the focus. Menus and pop-ups that hold the focus keep it.
    WaylandWindow *window = _keyboardWindow;
    id keyPlatformWindow = [[NSApp keyWindow] platformWindow];
    if ([keyPlatformWindow isKindOfClass: [WaylandWindow class]] &&
        (window == nil || ![window isPopup]))
        window = keyPlatformWindow;
    NSWindow *delegate = [window delegate];
    if (delegate == nil)
        return;

    xkb_keysym_t keysym = WL.xkb_state_key_get_one_sym(_xkbState, keycode);
    uint32_t special = CGSKeySymToUnicode(keysym);
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
                       timestamp: NSEventCurrentTime()
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

// What the keyboard layout builder needs of the compositor's keymap: a scratch XKB state that
// is put into each modifier layer in turn, so XKB itself decides the level of a key.
typedef struct {
    struct xkb_state *state;
    xkb_layout_index_t group;
    xkb_mod_mask_t shift, caps, option;
} WaylandKeyLayoutContext;

static uint32_t WaylandKeyLayoutKeysym(void *context, int carbonKey, unsigned layer) {
    WaylandKeyLayoutContext *keymap = context;
    const int keycode = carbonToX11[carbonKey];
    if (keycode == 0)
        return 0;

    xkb_mod_mask_t depressed = 0, locked = 0;
    if (layer & DarlingKeyLayerShift)
        depressed |= keymap->shift;
    if (layer & DarlingKeyLayerOption)
        depressed |= keymap->option;
    if (layer & DarlingKeyLayerCaps)
        locked |= keymap->caps;
    WL.xkb_state_update_mask(keymap->state, depressed, 0, locked, 0, 0, keymap->group);
    xkb_keysym_t keysym = WL.xkb_state_key_get_one_sym(keymap->state, keycode);
    return keysym == XKB_KEY_NoSymbol ? 0 : keysym;
}

static uint32_t WaylandKeyLayoutCodepoint(void *context, uint32_t keysym) {
    uint32_t codepoint = CGSKeySymToUnicode(keysym);
    return codepoint != 0 ? codepoint : WL.xkb_keysym_to_utf32(keysym);
}

// Builds the 'uchr' layout of the compositor's keymap in its current group and registers it with
// CoreGraphics, where the Text Input Sources API reads it: Wayland gives the keymap to the client
// that owns the keyboard, so CoreGraphics' own Wayland connection cannot read it. Called when a
// keymap arrives and when the group changes.
- (void) publishKeyboardLayout {
    if (_xkbState == NULL || _xkbKeymap == NULL)
        return;
    xkb_layout_index_t group = WL.xkb_state_serialize_layout(_xkbState, XKB_STATE_LAYOUT_EFFECTIVE);
    if (_publishedKeymap == _xkbKeymap && _publishedGroup == group)
        return;

    WaylandKeyLayoutContext keymap;
    keymap.state = WL.xkb_state_new(_xkbKeymap);
    if (keymap.state == NULL)
        return;
    keymap.group = group;
    xkb_mod_index_t shift = WL.xkb_keymap_mod_get_index(_xkbKeymap, XKB_MOD_NAME_SHIFT);
    xkb_mod_index_t caps = WL.xkb_keymap_mod_get_index(_xkbKeymap, XKB_MOD_NAME_CAPS);
    xkb_mod_index_t option = WL.xkb_keymap_mod_get_index(_xkbKeymap, "Mod5"); // AltGr
    keymap.shift = shift != XKB_MOD_INVALID ? 1u << shift : 0;
    keymap.caps = caps != XKB_MOD_INVALID ? 1u << caps : 0;
    keymap.option = option != XKB_MOD_INVALID ? 1u << option : 0;

    DarlingKeyLayoutSource source = {
        .context = &keymap,
        .keysym = WaylandKeyLayoutKeysym,
        .codepoint = WaylandKeyLayoutCodepoint,
        .compose = DarlingComposeCharacters,
    };
    uint32_t length = 0;
    UCKeyboardLayout *layout = DarlingCreateUnicodeKeyLayout(&source, &length);
    WL.xkb_state_unref(keymap.state);
    if (layout == NULL)
        return;

    NSString *name = nil, *fullName = nil;
    [self keyboardLayoutName: &name fullName: &fullName];
    _CGSSetProvidedKeyboardLayout(layout, length, (CFStringRef) name, (CFStringRef) fullName);
    free(layout);
    _publishedKeymap = _xkbKeymap;
    _publishedGroup = group;
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
        NSString *outputName = [output->_description length] > 0 ? output->_description : output->_name;
        screen->_outputName = [outputName length] > 0 ? [outputName copy] : nil;
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

// -screens is built from -outputsWithModes in order, so the indexes agree.
- (size_t) fullscreenOutputs: (WaylandFullscreenOutput *) result
                     proxies: (struct wl_proxy **) proxies
                         max: (size_t) max
                     entered: (NSSet *) entered
{
    NSArray *outputs = [self outputsWithModes];
    // -screens invents a screen when no output has reported a mode yet.
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

- (NSArray *) modesForScreen: (int) screenIndex {
    NSArray *outputs = [self outputsWithModes];
    if (screenIndex < 0 || screenIndex >= (int) [outputs count])
        return nil;
    WaylandOutput *output = outputs[screenIndex];
    // The output-management heads list every mode the output can be set to; wl_output
    // lists only what the compositor chooses to announce.
    NSArray *managed = [_outputManager modesForOutputAtX: output->_current.x y: output->_current.y
                                                   width: output->_current.width
                                                  height: output->_current.height];
    if ([managed count] > 0)
        return managed;
    return [NSArray arrayWithArray: output->_modes];
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

// Modes can be changed only through wlr-output-management; a compositor
// without it keeps its output modes (NO).
- (BOOL) setMode: (NSDictionary *) mode forScreen: (int) screenIndex {
    NSArray *outputs = [self outputsWithModes];
    if (_outputManager == nil || mode == nil || screenIndex < 0 || screenIndex >= (int) [outputs count])
        return NO;
    WaylandOutput *output = outputs[screenIndex];
    BOOL changed = [_outputManager
            setModeWidth: [[mode objectForKey: @"Width"] intValue]
                  height: [[mode objectForKey: @"Height"] intValue]
                 refresh: (int) lround([[mode objectForKey: @"RefreshRate"] doubleValue] * 1000.0)
            forOutputAtX: output->_current.x y: output->_current.y
            currentWidth: output->_current.width currentHeight: output->_current.height];
    if (changed) {
        // wl_output.done for the new mode normally came with the round trips; if it
        // is still on its way, wait for it so that the screens are up to date.
        for (int i = 0; i < 200 && output->_current.width != [[mode objectForKey: @"Width"] intValue]; i++) {
            if (WL.wl_display_roundtrip(_wlDisplay) < 0)
                break;
            usleep(5000);
        }
    }
    return changed;
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
    if (_layerShell != NULL)
        return YES;
    if (_appMenuManager == NULL)
        return NO;
    if (_appMenu == nil)
        _appMenu = [[WaylandAppMenu alloc] initWithDisplay: self];
    if ([_appMenu globalMenuPresent])
        return YES;
    [_appMenu release];
    _appMenu = nil;
    return NO;
}

- (void) _mainMenuDidChange: (NSMenu *) menu {
    if ([NSWindow _usesInWindowMenuBar])
        return;
    if (_appMenu == nil)
        _appMenu = [[WaylandAppMenu alloc] initWithDisplay: self];
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
        if (self->_keyboardWindow != nil)
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
    [self updatePointerLock];
}

- (void) windowUnmapped: (WaylandWindow *) window {
    // The compositor reparents the window's transient children itself.
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        WaylandWindow *other = (WaylandWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([other levelParent] == window)
            [other levelParentUnmapped];
    }
    if (_lockWindow == window) {
        [self releasePointerLock];
        [self performAfterDispatch: ^{ [self updatePointerLock]; }];
    }
    if (_wlLastClickWindow == window)
        _wlLastClickWindow = nil;
    if (_textInputWindow == window)
        [self textInputLeft];
    if (_pinchWindow == window)
        [self postPinchPhase: NSEventPhaseCancelled];
    [_draggingManager windowUnmapped: window];
    if (_dragPressWindow == window) [self consumeDragPress];
    if (_fingerScrollWindow == window)
        [self cancelFingerScroll];
    if (_pointerWindow == window) {
        _pointerWindow = nil;
        _pointerEnterSerial = 0;
        _pressedButtons = 0;
        [self discardPendingScroll];
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

#pragma mark - Clipboard, drag and drop, input state and unsupported calls

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
