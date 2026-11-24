/* AppKit's Pocket backend: the display of a phone host.

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

#import "PocketDisplay.h"
#import "PocketSocket.h"
#import "PocketWindow.h"
#import "../private-include/AppKit/NSTouchBackend.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSTouch.h>
#import <AppKit/NSWindow.h>
#import <CoreFoundation/CFSocket.h>
#import <HIToolbox/Events.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

// The host's screen: the notch, status bar and navigation bar it covers.
@interface PocketScreen : NSScreen {
    NSEdgeInsets _safeArea;
}
- (void) _setSafeAreaInsets: (NSEdgeInsets) insets;
@end

@implementation PocketScreen
- (NSEdgeInsets) safeAreaInsets {
    return _safeArea;
}

- (void) _setSafeAreaInsets: (NSEdgeInsets) insets {
    _safeArea = insets;
}
@end

@interface PocketDisplay ()
- (PocketWindow *) windowWithNumber: (uint32_t) number;
- (void) touch: (struct pocket_touch) touch;
- (void) key: (struct pocket_key) key characters: (NSString *) characters;
- (void) commitText: (NSString *) text;
- (void) processPendingEvents;
- (BOOL) readMessages;
- (void) handleMessage: (uint32_t) type bytes: (const uint8_t *) bytes length: (size_t) length;
- (void) screenChanged: (struct pocket_screen) screen;
@end

static NSString *stringFromBytes(const uint8_t *bytes, size_t length) {
    NSString *string = [[NSString alloc] initWithBytes: bytes length: length encoding: NSUTF8StringEncoding];
    return [string autorelease];
}

static void socketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    [(PocketDisplay *) info processPendingEvents];
}

@implementation PocketDisplay

- (instancetype) init {
    // -dealloc closes the socket: descriptor 0 is not ours.
    _socket = -1;
    const char *path = getenv("DARLING_POCKET_DISPLAY");
    if (path == NULL || *path == '\0') {
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;
    _windows = CFArrayCreateMutable(NULL, 0, NULL);
    _windowsByFinger = [NSMutableDictionary new];

    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof(address.sun_path)) {
        NSLog(@"Pocket backend: the socket path %s is too long, trying the next backend", path);
        [self release];
        return nil;
    }
    strcpy(address.sun_path, path);
    _socket = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_socket < 0 || connect(_socket, (struct sockaddr *) &address, sizeof(address)) != 0) {
        NSLog(@"Pocket backend: cannot connect to the host at %s: %s, trying the next backend", path,
              strerror(errno));
        [self release];
        return nil;
    }
    fcntl(_socket, F_SETFD, FD_CLOEXEC);
    fcntl(_socket, F_SETFL, fcntl(_socket, F_GETFL) | O_NONBLOCK);

    struct pocket_hello hello = {POCKET_PROTOCOL_VERSION, (uint32_t) getpid()};
    [self send: POCKET_HELLO bytes: &hello length: sizeof(hello)];

    // Windows are placed on the screen, so it must be known first.
    for (int waited = 0; !_haveScreen && waited < 100; waited++) {
        struct pollfd pfd = {.fd = _socket, .events = POLLIN};
        if (poll(&pfd, 1, 100) > 0 && ![self readMessages])
            break;
    }
    if (!_haveScreen) {
        NSLog(@"Pocket backend: the host at %s did not describe its screen, trying the next backend", path);
        [self release];
        return nil;
    }

    CFSocketContext context = {.version = 0, .info = self};
    _pocketSocket = CFSocketCreateWithNative(NULL, _socket, kCFSocketReadCallBack, socketCallback, &context);
    CFSocketSetSocketFlags(_pocketSocket, CFSocketGetSocketFlags(_pocketSocket) & ~kCFSocketCloseOnInvalidate);
    _pocketSource = CFSocketCreateRunLoopSource(NULL, _pocketSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _pocketSource, kCFRunLoopCommonModes);

    NSLog(@"Pocket backend: connected to %s, screen %ux%u at %.2fx", path, _screen.width, _screen.height,
          [self scale]);
    return self;
}

- (void) dealloc {
    if (_pocketSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _pocketSource, kCFRunLoopCommonModes);
        CFRelease(_pocketSource);
    }
    if (_pocketSocket != NULL) {
        CFSocketInvalidate(_pocketSocket);
        CFRelease(_pocketSocket);
    }
    if (_socket >= 0)
        close(_socket);
    if (_windows != NULL)
        CFRelease(_windows);
    [_windowsByFinger release];
    [super dealloc];
}

#pragma mark - The connection

- (void) hostGone {
    NSLog(@"Pocket backend: lost the connection to the host");
    exit(1);
}

- (void) send: (uint32_t) type bytes: (const void *) bytes length: (size_t) length {
    [self send: type bytes: bytes length: length fd: -1];
}

// With a descriptor, it goes with the first byte of the message.
- (void) send: (uint32_t) type bytes: (const void *) bytes length: (size_t) length fd: (int) fd {
    if (_socket < 0)
        return;
    if (pocket_send(_socket, type, bytes, length, fd) != 0) {
        if (errno == EMSGSIZE)
            NSLog(@"Pocket backend: not sending a message of %zu bytes", length);
        else
            [self hostGone];
    }
}

// Reads what has arrived and handles each whole message. NO when the host
// closed the connection or is broken.
- (BOOL) readMessages {
    for (;;) {
        ssize_t got = recv(_socket, _input + _inputLength, sizeof(_input) - _inputLength, 0);
        if (got < 0 && errno == EINTR)
            continue;
        if (got < 0 && errno == EAGAIN)
            return YES;
        if (got <= 0)
            return NO;
        _inputLength += got;

        size_t offset = 0;
        struct pocket_header header;
        int status;
        while ((status = pocket_unpack(_input + offset, _inputLength - offset, &header)) == 1) {
            [self handleMessage: header.type
                          bytes: _input + offset + sizeof(header)
                         length: header.size];
            offset += sizeof(header) + header.size;
        }
        if (status < 0)
            return NO;
        memmove(_input, _input + offset, _inputLength - offset);
        _inputLength -= offset;
    }
}

- (void) processPendingEvents {
    if (_socket >= 0 && ![self readMessages])
        [self hostGone];
}

// What the host has sent is handled before the application waits for an event.
- (void) willWaitForEvents {
    [self processPendingEvents];
}

#pragma mark - Messages from the host

- (void) handleMessage: (uint32_t) type bytes: (const uint8_t *) bytes length: (size_t) length {
    switch (type) {
    case POCKET_RELEASE:
        if (length >= sizeof(struct pocket_window_id)) {
            struct pocket_window_id message;
            memcpy(&message, bytes, sizeof(message));
            [[self windowWithNumber: message.window] bufferReleased];
        }
        break;
    case POCKET_TOUCH:
        if (length >= sizeof(struct pocket_touch)) {
            struct pocket_touch touch;
            memcpy(&touch, bytes, sizeof(touch));
            [self touch: touch];
        }
        break;
    case POCKET_KEY:
        if (length >= sizeof(struct pocket_key)) {
            struct pocket_key key;
            memcpy(&key, bytes, sizeof(key));
            if (key.length <= length - sizeof(key))
                [self key: key characters: stringFromBytes(bytes + sizeof(key), key.length)];
        }
        break;
    case POCKET_TEXT:
        [self commitText: stringFromBytes(bytes, length)];
        break;
    case POCKET_SCREEN:
        if (length >= sizeof(struct pocket_screen)) {
            struct pocket_screen screen;
            memcpy(&screen, bytes, sizeof(screen));
            [self screenChanged: screen];
        }
        break;
    default:
        break;
    }
}

- (PocketWindow *) windowWithNumber: (uint32_t) number {
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        PocketWindow *window = (PocketWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window number] == number)
            return window;
    }
    return nil;
}

#pragma mark - Input

// The topmost visible window under a point of the screen, in points.
- (PocketWindow *) windowAtPoint: (NSPoint) point {
    PocketWindow *found = nil;
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++) {
        PocketWindow *window = (PocketWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window isVisible] && NSPointInRect(point, [window frame]) &&
            (found == nil || [window level] >= [found level]))
            found = window;
    }
    return found;
}

// A finger goes to the window it began in, wherever it moves.
- (void) touch: (struct pocket_touch) touch {
    NSTouchPhase phase;
    switch (touch.phase) {
    case POCKET_TOUCH_BEGAN: phase = NSTouchPhaseBegan; break;
    case POCKET_TOUCH_MOVED: phase = NSTouchPhaseMoved; break;
    case POCKET_TOUCH_ENDED: phase = NSTouchPhaseEnded; break;
    case POCKET_TOUCH_CANCELLED: phase = NSTouchPhaseCancelled; break;
    default: return;
    }
    CGFloat scale = [self scale];
    NSPoint point = NSMakePoint(touch.x / scale, NSMaxY([self screenFrame]) - touch.y / scale);
    NSNumber *finger = [NSNumber numberWithUnsignedInt: touch.finger];
    PocketWindow *window;
    if (phase == NSTouchPhaseBegan) {
        window = [self windowAtPoint: point];
        if (window != nil)
            [_windowsByFinger setObject: [NSNumber numberWithUnsignedInt: [window number]] forKey: finger];
    } else {
        window = [self windowWithNumber: [[_windowsByFinger objectForKey: finger] unsignedIntValue]];
        if (phase == NSTouchPhaseEnded || phase == NSTouchPhaseCancelled)
            [_windowsByFinger removeObjectForKey: finger];
    }
    _lastTouch = point;
    if (window == nil || [window delegate] == nil)
        return;
    NSRect frame = [window frame];
    NSTouchPost([window delegate], touch.finger, phase,
                NSMakePoint(point.x - frame.origin.x, point.y - frame.origin.y), touch.time);
}

// Keys go to the key window, or the topmost one while none is key.
- (NSWindow *) keyWindow {
    NSWindow *window = [NSApp keyWindow];
    if (window == nil) {
        for (CFIndex i = CFArrayGetCount(_windows) - 1; i >= 0 && window == nil; i--) {
            PocketWindow *platform = (PocketWindow *) CFArrayGetValueAtIndex(_windows, i);
            if ([platform isVisible])
                window = [platform delegate];
        }
    }
    return window;
}

- (void) postKey: (BOOL) down
         keyCode: (unsigned short) keyCode
       modifiers: (NSEventModifierFlags) modifiers
      characters: (NSString *) characters
{
    NSWindow *window = [self keyWindow];
    if (window == nil)
        return;
    NSEvent *event = [NSEvent keyEventWithType: down ? NSKeyDown : NSKeyUp
                                      location: NSZeroPoint
                                 modifierFlags: modifiers
                                     timestamp: [NSDate timeIntervalSinceReferenceDate]
                                  windowNumber: [window windowNumber]
                                       context: nil
                                    characters: characters
                   charactersIgnoringModifiers: characters
                                     isARepeat: NO
                                       keyCode: keyCode];
    [self postEvent: event atStart: NO];
}

// The characters AppKit's key bindings expect from the keys that type none. The Mac virtual key
// codes are HIToolbox's (Events.h). Delete is a backspace here (0x08), as the standard key bindings
// of this AppKit expect, not the 0x7f of macOS.
static NSString *charactersForSpecialKey(uint32_t keycode) {
    unichar character;
    switch (keycode) {
    case kVK_Return: character = '\r'; break;
    case kVK_ANSI_KeypadEnter: character = 0x03; break;
    case kVK_Tab: character = '\t'; break;
    case kVK_Delete: character = 0x08; break;
    case kVK_Escape: character = 0x1B; break;
    case kVK_ForwardDelete: character = NSDeleteFunctionKey; break;
    case kVK_Home: character = NSHomeFunctionKey; break;
    case kVK_End: character = NSEndFunctionKey; break;
    case kVK_PageUp: character = NSPageUpFunctionKey; break;
    case kVK_PageDown: character = NSPageDownFunctionKey; break;
    case kVK_LeftArrow: character = NSLeftArrowFunctionKey; break;
    case kVK_RightArrow: character = NSRightArrowFunctionKey; break;
    case kVK_DownArrow: character = NSDownArrowFunctionKey; break;
    case kVK_UpArrow: character = NSUpArrowFunctionKey; break;
    default: return nil;
    }
    return [NSString stringWithCharacters: &character length: 1];
}

- (void) key: (struct pocket_key) key characters: (NSString *) characters {
    _modifierFlags = key.modifiers;
    NSString *special = charactersForSpecialKey(key.keycode);
    if (special != nil)
        characters = special;
    [self postKey: key.down != 0
          keyCode: key.keycode == 0xFFFF ? 0 : (unsigned short) key.keycode
        modifiers: key.modifiers
       characters: characters ? characters : @""];
}

// An input method's text, as a key typing it.
- (void) commitText: (NSString *) text {
    if ([text length] == 0)
        return;
    [self postKey: YES keyCode: 0 modifiers: 0 characters: text];
    [self postKey: NO keyCode: 0 modifiers: 0 characters: text];
}

#pragma mark - Screen changes

- (void) screenChanged: (struct pocket_screen) screen {
    if (screen.width == 0 || screen.height == 0)
        return;
    if (screen.scale_milli == 0)
        screen.scale_milli = 1000;
    BOOL changed = _haveScreen && memcmp(&screen, &_screen, sizeof(screen)) != 0;
    _screen = screen;
    _haveScreen = YES;
    if (!changed)
        return;
    [self _invalidateScreens];
    for (CFIndex i = 0; i < CFArrayGetCount(_windows); i++)
        [(PocketWindow *) CFArrayGetValueAtIndex(_windows, i) screenChanged];
    [self _postScreenParametersChanged];
}

#pragma mark - The screen

- (CGFloat) scale {
    return _screen.scale_milli / 1000.0;
}

- (NSRect) screenFrame {
    CGFloat scale = [self scale];
    return NSMakeRect(0, 0, _screen.width / scale, _screen.height / scale);
}

// The screens of -[NSDisplay screens] come from CoreGraphics' displays, which have no Pocket backend.
- (NSArray<NSScreen *> *) _screensFromDisplays {
    CGFloat scale = [self scale];
    NSRect frame = [self screenFrame];
    PocketScreen *screen = [[[PocketScreen alloc] initWithFrame: frame visibleFrame: frame] autorelease];
    [screen _setBackingScaleFactor: scale];
    [screen _setSafeAreaInsets: NSEdgeInsetsMake(_screen.inset_top / scale, _screen.inset_left / scale,
                                                _screen.inset_bottom / scale, _screen.inset_right / scale)];
    return [NSArray arrayWithObject: screen];
}

// Event locations are made global with the screen's height, which the missing CoreGraphics display
// would otherwise give as 0.
- (CGFloat) _mainScreenMaxY {
    return NSMaxY([self screenFrame]);
}

#pragma mark - The rest of AppKit's display interface

#pragma mark - Windows

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    return [[PocketWindow alloc] initWithDelegate: delegate];
}

// The host is told the windows from the bottom up: by level, then in the order they were raised.
- (void) sendOrder {
    CFIndex count = CFArrayGetCount(_windows);
    uint32_t numbers[POCKET_MAX_MESSAGE / sizeof(uint32_t)];
    CFIndex sent = 0;
    NSMutableArray *sorted = [NSMutableArray arrayWithCapacity: count];
    for (CFIndex i = 0; i < count; i++)
        [sorted addObject: (id) CFArrayGetValueAtIndex(_windows, i)];
    [sorted sortWithOptions: NSSortStable
            usingComparator: ^NSComparisonResult(PocketWindow *a, PocketWindow *b) {
                return [a level] < [b level] ? NSOrderedAscending
                                             : [a level] > [b level] ? NSOrderedDescending : NSOrderedSame;
            }];
    for (PocketWindow *window in sorted)
        if (sent < (CFIndex) (sizeof(numbers) / sizeof(numbers[0])))
            numbers[sent++] = [window number];
    [self send: POCKET_ORDER bytes: numbers length: sent * sizeof(uint32_t)];
}

- (void) windowCreated: (PocketWindow *) window {
    CFArrayAppendValue(_windows, window);
}

- (void) windowDestroyed: (PocketWindow *) window {
    CFIndex index = CFArrayGetFirstIndexOfValue(_windows, CFRangeMake(0, CFArrayGetCount(_windows)), window);
    if (index != kCFNotFound)
        CFArrayRemoveValueAtIndex(_windows, index);
}

- (void) windowRaised: (PocketWindow *) window {
    CFIndex count = CFArrayGetCount(_windows);
    CFIndex index = CFArrayGetFirstIndexOfValue(_windows, CFRangeMake(0, count), window);
    if (index == count - 1)
        return;
    if (index != kCFNotFound)
        CFArrayRemoveValueAtIndex(_windows, index);
    CFArrayAppendValue(_windows, window);
    [self sendOrder];
}

- (void) windowLowered: (PocketWindow *) window {
    CFIndex index = CFArrayGetFirstIndexOfValue(_windows, CFRangeMake(0, CFArrayGetCount(_windows)), window);
    if (index == 0)
        return;
    if (index != kCFNotFound)
        CFArrayRemoveValueAtIndex(_windows, index);
    CFArrayInsertValueAtIndex(_windows, 0, window);
    [self sendOrder];
}

- (NSDraggingManager *) draggingManager {
    return nil;
}

// Front to back.
- (NSArray *) orderedWindowNumbers {
    NSMutableArray *numbers = [NSMutableArray array];
    for (CFIndex i = CFArrayGetCount(_windows) - 1; i >= 0; i--) {
        PocketWindow *window = (PocketWindow *) CFArrayGetValueAtIndex(_windows, i);
        if ([window isVisible])
            [numbers addObject: [NSNumber numberWithInteger: [window windowNumber]]];
    }
    return numbers;
}

// Windows have no frames on a phone.
- (CGRect) insetRect: (CGRect) frame forNativeWindowBorderWithStyle: (NSUInteger) styleMask {
    return frame;
}

- (CGRect) outsetRect: (CGRect) frame forNativeWindowBorderWithStyle: (NSUInteger) styleMask {
    return frame;
}

// Where the last finger was.
- (NSPoint) mouseLocation {
    return _lastTouch;
}

- (NSUInteger) currentModifierFlags {
    return _modifierFlags;
}

// There is no pointer.
- (void) warpMouse: (NSPoint) position {}
- (void) grabMouse: (BOOL) doGrab {}
- (void) hideCursor {}
- (void) unhideCursor {}
- (id) cursorWithName: (NSString *) name { return nil; }
- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot { return nil; }
- (void) setCursor: (id) cursor {}
- (void) beep {}

@end
