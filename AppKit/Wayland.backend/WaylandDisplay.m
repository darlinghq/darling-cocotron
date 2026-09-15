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
#import "NSEvent_mouse.h"
#import "WaylandCursor.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "WaylandWindow.h"
#import "X11KeySymToUCS.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#import <objc/message.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <unistd.h>

// A wl_output and the modes it advertised.
@interface WaylandOutput : NSObject {
@public
    struct wl_proxy *_proxy;
    uint32_t _globalName;
    WaylandDisplay *_display;
    int32_t _width, _height, _refresh, _scale;
    NSMutableArray *_modes;
}
@end

@implementation WaylandOutput

- (void) dealloc {
    [_modes release];
    [super dealloc];
}

@end

@interface WaylandDisplay (Private)
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
            case WaylandObjectDecoration:
            case WaylandObjectFrameCallback:
            case WaylandObjectBuffer:
                [(WaylandWindow *) object handleEvent: opcode
                                                 kind: objectKind
                                                proxy: proxy
                                            arguments: args];
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
    const char *requested = getenv("DARLING_APPKIT_BACKEND");
    if (requested == NULL || strcasecmp(requested, "wayland") != 0) {
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

    _xkbContext = WL.xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (_xkbContext == NULL)
        NSLog(@"Wayland backend: cannot create an xkbcommon context, keyboard "
              @"input is disabled");

    if (WL.hasCursor) {
        const char *sizeString = getenv("XCURSOR_SIZE");
        int size = sizeString ? atoi(sizeString) : 0;
        _cursorTheme = WL.wl_cursor_theme_load(getenv("XCURSOR_THEME"),
                                               size > 0 ? size : 24,
                                               (struct wl_shm *) _shm);
        if (_cursorTheme == NULL) {
            NSLog(@"Wayland backend: no cursor theme, the compositor's cursor "
                  @"stays");
        }
    }
    // Image cursors only need wl_shm, even without libwayland-cursor or a theme.
    args[0].o = NULL;
    _cursorSurface = WaylandCreateObject(_compositor, WP_COMPOSITOR_CREATE_SURFACE,
                                        &wl_surface_interface, args, 0, nil);

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

    NSLog(@"Wayland backend: connected, %lu output(s), seat %s, decorations %s",
          (unsigned long) [_outputs count], _seat ? "present" : "missing",
          _decorationManager ? "server-side" : "unavailable");
    return self;
}

- (void) dealloc {
    [self stopKeyRepeat];

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
        struct wl_proxy *proxies[] = {_imageCursorBuffer, _cursorSurface, _pointer, _keyboard,
                                      _seat, _decorationManager, _wmBase,
                                      _shm, _compositor, _registry};
        for (size_t i = 0; i < sizeof(proxies) / sizeof(proxies[0]); i++)
            if (proxies[i] != NULL)
                WL.wl_proxy_destroy(proxies[i]);
        for (WaylandOutput *output in _outputs)
            WL.wl_proxy_destroy(output->_proxy);
        WL.wl_display_disconnect(_wlDisplay);
    }

    [_cursor release];
    [_screens release];
    [_outputs release];
    [_afterDispatch release];
    if (_windows != NULL)
        CFRelease(_windows);

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
    } else if (strcmp(interface, "wl_shm") == 0 && _shm == NULL) {
        _shm = [self bindGlobal: name
                      interface: &wl_shm_interface
                        version: 1
                           kind: 0
                         object: nil];
    } else if (strcmp(interface, "xdg_wm_base") == 0 && _wmBase == NULL) {
        _wmBase = [self bindGlobal: name
                         interface: &xdg_wm_base_interface
                           version: 1
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
    } else if (strcmp(interface, "wl_seat") == 0 && _seat == NULL) {
        // Version 4 adds wl_keyboard.repeat_info, 5 wl_pointer.frame.
        _seat = [self bindGlobal: name
                       interface: &wl_seat_interface
                         version: MIN(version, 5)
                            kind: WaylandObjectSeat
                          object: self];
    } else if (strcmp(interface, "wl_output") == 0) {
        WaylandOutput *output = [[WaylandOutput new] autorelease];
        output->_globalName = name;
        output->_display = self;
        output->_scale = 1;
        output->_modes = [NSMutableArray new];
        // Version 2 has scale and done.
        output->_proxy = [self bindGlobal: name
                                interface: &wl_output_interface
                                  version: MIN(version, 2)
                                     kind: WaylandObjectOutput
                                   object: output];
        if (output->_proxy != NULL)
            [_outputs addObject: output];
    }
}

- (void) registryGlobalRemoved: (uint32_t) name {
    for (WaylandOutput *output in _outputs) {
        if (output->_globalName == name) {
            WL.wl_proxy_destroy(output->_proxy);
            [_outputs removeObject: output];
            [self invalidateScreens];
            break;
        }
    }
}

- (void) invalidateScreens {
    [_screens release];
    _screens = nil;
}

- (void) outputEvent: (uint32_t) opcode
              output: (WaylandOutput *) output
           arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_OUTPUT_EV_MODE: {
        if (args[0].u & WP_OUTPUT_MODE_CURRENT) {
            output->_width = args[1].i;
            output->_height = args[2].i;
            output->_refresh = args[3].i;
        }
        NSDictionary *mode = @{
            @"Width" : @(args[1].i),
            @"Height" : @(args[2].i),
            @"Depth" : @(24),
            @"RefreshRate" : @(args[3].i / 1000.0)
        };
        if (![output->_modes containsObject: mode])
            [output->_modes addObject: mode];
        break;
    }
    case WP_OUTPUT_EV_SCALE:
        output->_scale = MAX(args[0].i, 1);
        break;
    case WP_OUTPUT_EV_DONE:
        [self invalidateScreens];
        break;
    }
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
    } else if (!(capabilities & WP_SEAT_CAPABILITY_POINTER) && _pointer != NULL) {
        [self releaseInputDevice: &_pointer opcode: WP_POINTER_RELEASE];
        _pointerWindow = nil;
        _pressedButtons = 0;
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
    switch (opcode) {
    case WP_POINTER_EV_ENTER:
        _pointerEnterSerial = args[0].u;
        _pointerWindow =
                [self windowForSurface: (struct wl_proxy *) args[1].o];
        _pointerSurfacePoint = CGPointMake(wl_fixed_to_double(args[2].f),
                                           wl_fixed_to_double(args[3].f));
        [_pointerWindow setLastKnownCursorPosition:
                                [_pointerWindow transformPoint: _pointerSurfacePoint]];
        [self applyCursor];
        break;

    case WP_POINTER_EV_LEAVE:
        _lastMouseLocation = [self mouseLocation];
        _pointerWindow = nil;
        break;

    case WP_POINTER_EV_MOTION:
        [self pointerMotionToX: wl_fixed_to_double(args[1].f)
                             y: wl_fixed_to_double(args[2].f)];
        break;

    case WP_POINTER_EV_BUTTON:
        [self pointerButton: args[2].u
                    pressed: args[3].u == WP_POINTER_BUTTON_STATE_PRESSED];
        break;

    case WP_POINTER_EV_AXIS:
        [self pointerAxis: args[1].u value: wl_fixed_to_double(args[2].f)];
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

- (void) pointerButton: (uint32_t) button pressed: (BOOL) pressed {
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

    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return;

    if (pressed) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - _lastClickTime < [self doubleClickInterval])
            _clickCount++;
        else
            _clickCount = 1;
        _lastClickTime = now;
    }

    NSEvent *event = [NSEvent
            mouseEventWithType: pressed ? downType : upType
                      location: [window transformPoint: _pointerSurfacePoint]
                 modifierFlags: [self currentModifierFlags]
                        window: [window delegate]
                    clickCount: _clickCount
                        deltaX: 0.0
                        deltaY: 0.0];
    [(NSEvent_mouse *) event _setButtonNumber: number];
    [self postEvent: event atStart: NO];
}

- (void) pointerAxis: (uint32_t) axis value: (CGFloat) value {
    WaylandWindow *window = _pointerWindow;
    if (window == nil)
        return;

    // One wheel notch is 10 units, scrolling down is positive; the X11 backend
    // reports a notch up as deltaY 1.
    CGFloat delta = -value / 10.0;
    NSEvent *event = [NSEvent
            mouseEventWithType: NSScrollWheel
                      location: [window transformPoint: _pointerSurfacePoint]
                 modifierFlags: [self currentModifierFlags]
                        window: [window delegate]
                    clickCount: 1
                        deltaX: axis == WP_POINTER_AXIS_HORIZONTAL_SCROLL ? delta : 0.0
                        deltaY: axis == WP_POINTER_AXIS_VERTICAL_SCROLL ? delta : 0.0];
    [self postEvent: event atStart: NO];
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

- (void) keyboardEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    switch (opcode) {
    case WP_KEYBOARD_EV_KEYMAP:
        [self keymapWithFormat: args[0].u fd: args[1].h size: args[2].u];
        break;

    case WP_KEYBOARD_EV_ENTER:
        _keyboardWindow = [self windowForSurface: (struct wl_proxy *) args[1].o];
        break;

    case WP_KEYBOARD_EV_LEAVE:
        _keyboardWindow = nil;
        [self stopKeyRepeat];
        break;

    case WP_KEYBOARD_EV_KEY: {
        if (_xkbState == NULL)
            break;
        // Wayland sends evdev codes; XKB keycodes are 8 higher.
        xkb_keycode_t keycode = args[2].u + 8;
        BOOL pressed = args[3].u == WP_KEYBOARD_KEY_STATE_PRESSED;

        [self postKeyEventForKeycode: keycode pressed: pressed repeat: NO];
        if (pressed && _repeatRate > 0 &&
            WL.xkb_keymap_key_repeats(_xkbKeymap, keycode))
            [self startKeyRepeat: keycode];
        else if (!pressed && keycode == _repeatKeycode)
            [self stopKeyRepeat];
        break;
    }

    case WP_KEYBOARD_EV_MODIFIERS:
        if (_xkbState != NULL)
            WL.xkb_state_update_mask(_xkbState, args[1].u, args[2].u, args[3].u,
                                     0, 0, args[4].u);
        break;

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
}

- (BOOL) isModifierActive: (const char *) name {
    return _xkbState != NULL &&
           WL.xkb_state_mod_name_is_active(_xkbState, name,
                                           XKB_STATE_MODS_EFFECTIVE) > 0;
}

// The same mapping as -[X11Display modifierFlagsForState:].
- (NSUInteger) currentModifierFlags {
    NSUInteger flags = 0;

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
        if (output->_width > 0 && output->_height > 0)
            [result addObject: output];
    return result;
}

// Outputs are laid out left to right in logical pixels: Wayland doesn't tell
// clients where outputs are.
- (NSArray *) screens {
    if (_screens != nil)
        return [[_screens retain] autorelease];

    NSMutableArray *screens = [NSMutableArray array];
    CGFloat x = 0;
    for (WaylandOutput *output in [self outputsWithModes]) {
        NSRect frame = NSMakeRect(x, 0, output->_width / output->_scale,
                                  output->_height / output->_scale);
        NSScreen *screen = [[[NSScreen alloc] initWithFrame: frame
                                               visibleFrame: frame] autorelease];
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
        @"Width" : @(output->_width),
        @"Height" : @(output->_height),
        @"Depth" : @(24),
        @"RefreshRate" : @(output->_refresh / 1000.0)
    };
}

- (BOOL) setMode: (NSDictionary *) mode forScreen: (int) screenIndex {
    return NO;
}

#pragma mark - Windows

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
    if (_pointerWindow == window)
        _pointerWindow = nil;
    if (_keyboardWindow == window) {
        _keyboardWindow = nil;
        [self stopKeyRepeat];
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

- (struct wl_proxy *) imageCursorBuffer {
    if (_imageCursorBuffer != NULL)
        return _imageCursorBuffer;
    NSData *pixels = [_cursor pixels];
    if (pixels == nil)
        return NULL;

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
    NSSize dimensions = [_cursor size];
    union wl_argument bufferArgs[6] = {{.o = NULL}, {.i = 0},
        {.i = (int32_t) dimensions.width}, {.i = (int32_t) dimensions.height},
        {.i = (int32_t) dimensions.width * 4}, {.u = WP_SHM_FORMAT_ARGB8888}};
    _imageCursorBuffer = WaylandCreateObject(pool, WP_SHM_POOL_CREATE_BUFFER,
            &wl_buffer_interface, bufferArgs, 0, nil);
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(pool, WP_SHM_POOL_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    return _imageCursorBuffer;
}

- (void) applyCursor {
    if (_pointer == NULL || _pointerEnterSerial == 0)
        return;

    union wl_argument args[4];
    args[0].u = _pointerEnterSerial;

    if ([_cursor isBlank]) {
        args[1].o = NULL;
        args[2].i = 0;
        args[3].i = 0;
        WaylandMarshal(_pointer, WP_POINTER_SET_CURSOR, NULL, 0, args);
        [self flush];
        return;
    }
    if (_cursorSurface == NULL)
        return;

    struct wl_proxy *buffer = [self imageCursorBuffer];
    NSSize size = [_cursor size];
    NSPoint hotSpot = [_cursor hotSpot];
    if (buffer == NULL) {
        if (_cursorTheme == NULL)
            return;
        static const char *const arrowNames[] = {"default", "left_ptr", NULL};
        const char *const *names = _cursor ? [_cursor names] : arrowNames;
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
        size = NSMakeSize(image->width, image->height);
        hotSpot = NSMakePoint(image->hotspot_x, image->hotspot_y);
    }

    union wl_argument attach[3] = {{.o = (struct wl_object *) buffer}, {.i = 0}, {.i = 0}};
    WaylandMarshal(_cursorSurface, WP_SURFACE_ATTACH, NULL, 0, attach);
    union wl_argument damage[4] = {{.i = 0}, {.i = 0},
                                   {.i = (int32_t) size.width},
                                   {.i = (int32_t) size.height}};
    WaylandMarshal(_cursorSurface, WP_SURFACE_DAMAGE, NULL, 0, damage);
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_cursorSurface, WP_SURFACE_COMMIT, NULL, 0, none);

    args[1].o = (struct wl_object *) _cursorSurface;
    args[2].i = (int32_t) hotSpot.x;
    args[3].i = (int32_t) hotSpot.y;
    WaylandMarshal(_pointer, WP_POINTER_SET_CURSOR, NULL, 0, args);
    [self flush];
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

- (NSPasteboard *) pasteboardWithName: (NSString *) name {
    // The clipboard isn't implemented yet.
    return nil;
}

- (void) beep {
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
