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
#import "PocketWindow.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSScreen.h>
#import <CoreFoundation/CFSocket.h>
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
- (void) processPendingEvents;
- (BOOL) readMessages;
- (void) handleMessage: (uint32_t) type bytes: (const uint8_t *) bytes length: (size_t) length;
- (void) screenChanged: (struct pocket_screen) screen;
@end

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
    [super dealloc];
}

#pragma mark - The connection

- (void) hostGone {
    NSLog(@"Pocket backend: lost the connection to the host");
    exit(1);
}

- (void) send: (uint32_t) type bytes: (const void *) bytes length: (size_t) length {
    if (_socket < 0)
        return;
    uint8_t message[sizeof(struct pocket_header) + POCKET_MAX_MESSAGE];
    size_t total = pocket_pack(message, type, bytes, length);
    if (total == 0) {
        NSLog(@"Pocket backend: not sending a message of %zu bytes", length);
        return;
    }
    for (size_t sent = 0; sent < total;) {
        ssize_t written = send(_socket, message + sent, total - sent, 0);
        if (written < 0 && (errno == EAGAIN || errno == EINTR)) {
            struct pollfd pfd = {.fd = _socket, .events = POLLOUT};
            poll(&pfd, 1, 1000);
            continue;
        }
        if (written <= 0)
            [self hostGone];
        sent += written;
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

- (NSPoint) mouseLocation {
    return NSZeroPoint;
}

- (NSUInteger) currentModifierFlags {
    return 0;
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
