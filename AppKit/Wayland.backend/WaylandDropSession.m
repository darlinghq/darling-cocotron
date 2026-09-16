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

#import "WaylandDropSession.h"
#import "WaylandDragOperations.h"
#import "WaylandDraggingManager.h"
#import "WaylandWindow.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <AppKit/NSWindow-Drag.h>
#import <AppKit/NSWindow.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>

static NSString *typeForMime(NSString *mime) {
    if ([mime isEqual: @"text/plain;charset=utf-8"] || [mime isEqual: @"text/plain"] ||
        [mime isEqual: @"UTF8_STRING"]) return NSStringPboardType;
    return mime;
}

@implementation WaylandDropSession
- (id) initWithOffer: (struct wl_proxy *) offer types: (NSArray *) mimes
            display: (WaylandDisplay *) display window: (WaylandWindow *) window
             serial: (uint32_t) serial sourceActions: (uint32_t) actions {
    if ((self = [super init])) {
        _display = display; _offer = offer; _serial = serial;
        WaylandDraggingManager *manager = (WaylandDraggingManager *) [display draggingManager];
        _localSource = [[manager localDraggingSource] retain];
        _localOperations = [manager localOperations];
        _window = [window retain]; _destination = [[window delegate] retain];
        _mimes = [mimes copy]; _cache = [NSMutableDictionary new];
        NSMutableArray *types = [NSMutableArray array];
        for (NSString *mime in mimes) {
            if ([mime isEqual: @"DELETE"]) continue; // Control target, never pasteboard data.
            NSString *type = typeForMime(mime);
            if (![types containsObject: type]) [types addObject: type];
        }
        _types = [types copy];
        _sourceActions = actions;
        if (offer && WL.wl_proxy_get_version(offer) < 3) _sourceActions = _action = 1;
        static int nextSequence = 0;
        _sequence = ++nextSequence;
    }
    return self;
}
- (void) invalidate {
    if (_offer) {
        WaylandMarshal(_offer, WP_DATA_OFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _offer = NULL;
    }
    _accepted = NO;
}
- (void) dealloc {
    [self invalidate];
    [_window release]; [_destination release]; [_receiver release];
    [_mimes release]; [_types release]; [_cache release]; [_localSource release];
    [super dealloc];
}
- (void) sourceActions: (uint32_t) actions { if (!_dropAnnounced) _sourceActions = actions; }
- (void) selectedAction: (uint32_t) action { if (!_dropAnnounced) _action = action; }
- (NSArray *) types { return _types; }
- (NSString *) availableTypeFromArray: (NSArray *) types {
    for (NSString *type in types) if ([_types containsObject: type]) return type;
    return nil;
}
- (NSString *) mimeForType: (NSString *) type {
    if ([type isEqual: @"DELETE"]) return nil;
    if ([type isEqual: NSStringPboardType]) {
        for (NSString *mime in @[@"text/plain;charset=utf-8", @"text/plain", @"UTF8_STRING"])
            if ([_mimes containsObject: mime]) return mime;
    }
    return [_mimes containsObject: type] ? type : nil;
}
- (NSString *) name { return NSDragPboard; }
- (NSInteger) changeCount { return _sequence; }
- (NSData *) dataForType: (NSString *) type {
    if ([type isEqual: @"DELETE"]) return nil;
    NSData *cached = [_cache objectForKey: type];
    if (cached) return cached;
    NSString *mime = [self mimeForType: type];
    if (!_offer || !mime) return nil;
    int fds[2];
    if (pipe(fds) != 0) { _transferFailed = YES; return nil; }
    fcntl(fds[0], F_SETFD, FD_CLOEXEC); fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    int flags = fcntl(fds[0], F_GETFL);
    if (flags < 0 || fcntl(fds[0], F_SETFL, flags | O_NONBLOCK) < 0) {
        close(fds[0]); close(fds[1]); _transferFailed = YES; return nil;
    }
    union wl_argument args[2] = {{.s = [mime UTF8String]}, {.h = fds[1]}};
    WaylandMarshal(_offer, WP_DATA_OFFER_RECEIVE, NULL, 0, args);
    close(fds[1]); [_display flush];
    NSMutableData *data = [NSMutableData data];
    BOOL complete = NO;
    NSString *failure = @"timed out after five seconds";
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + 5;
    @try {
        while (_offer && [NSDate timeIntervalSinceReferenceDate] < deadline) {
            char bytes[16384];
            ssize_t count = read(fds[0], bytes, sizeof(bytes));
            if (!count) { complete = YES; break; }
            if (count > 0) {
                if ([data length] + count > 16 * 1024 * 1024) {
                    failure = @"exceeds 16 MiB"; break;
                }
                [data appendBytes: bytes length: count]; continue;
            }
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                failure = @"read failed"; break;
            }
            [_display processPendingEvents];
            struct pollfd ready = {.fd = fds[0], .events = POLLIN};
            poll(&ready, 1, 20);
        }
    } @finally { close(fds[0]); }
    if (!complete || !_offer) {
        _transferFailed = YES;
        NSLog(@"Wayland drop: transfer %@", _offer ? failure : @"cancelled");
        return nil;
    }
    [_cache setObject: data forKey: type];
    return data;
}
- (NSString *) stringForType: (NSString *) type {
    NSData *data = [self dataForType: type];
    return data ? [[[NSString alloc] initWithData: data encoding:
        [type isEqual: NSStringPboardType] ? NSUTF8StringEncoding : NSUnicodeStringEncoding] autorelease] : nil;
}
- (void) motion: (CGPoint) point {
    if (!_offer || _dropped) return;
    NSUInteger generation = ++_motionGeneration;
    _point = [_window transformPoint: point];
    // Motion queued before the native drop still supplies its final position,
    // but must not renegotiate the action already selected at drop time.
    if (_dropAnnounced) {
        if ([_window isDecorationPoint: point]) _accepted = NO;
        return;
    }
    NSDragOperation operation = NSDragOperationNone;
    _negotiationDepth++;
    @try {
        id receiver = [_window isMapped] && ![_window isDecorationPoint: point] ?
            [_destination _receiverForDragSession: self] : nil;
        if (generation != _motionGeneration) return;
        if (receiver != _receiver) {
            _accepted = NO; _acceptedActions = 0;
            id old = _receiver; _receiver = [receiver retain];
            @try { [old draggingExited: self]; } @finally { [old release]; }
            if (generation != _motionGeneration) return;
            operation = [_receiver draggingEntered: self];
        } else operation = [_receiver draggingUpdated: self];
    } @finally { _negotiationDepth--; }
    if (!_offer || generation != _motionGeneration) return; // Cancelled or superseded.
    uint32_t actions = WaylandActionsFromOperations(operation & [self draggingSourceOperationMask]);
    if (_dropAnnounced) {
        // A callback pumped the native drop: only narrow prior acceptance.
        _acceptedActions &= actions;
        _accepted = _accepted && _acceptedActions != 0;
        return;
    }
    _acceptedActions = actions;
    if (WL.wl_proxy_get_version(_offer) < 3) _acceptedActions &= 1;
    _accepted = _acceptedActions != 0;
    NSString *mime = nil;
    if (_accepted) {
        // Use a type registered by this receiver, not an unrelated first offer.
        for (NSString *type in [_receiver _draggedTypes]) {
            mime = [self mimeForType: type];
            if (mime) break;
        }
    }
    _accepted = _accepted && mime != nil;
    if (!_accepted) _acceptedActions = 0;
    union wl_argument args[2] = {{.u = _serial}, {.s = _accepted ? [mime UTF8String] : NULL}};
    WaylandMarshal(_offer, WP_DATA_OFFER_ACCEPT, NULL, 0, args);
    if (WL.wl_proxy_get_version(_offer) >= 3) {
        args[0].u = _acceptedActions;
        args[1].u = (_acceptedActions & 1) ? 1 : (_acceptedActions & 2);
        WaylandMarshal(_offer, WP_DATA_OFFER_SET_ACTIONS, NULL, 0, args);
    }
    [_display flush];
}
- (void) markDropped {
    _dropAnnounced = YES;
    // A receiver may pump a nested drop before returning its operation. Do not
    // perform using the previous motion's acceptance while that answer is pending.
    if (_negotiationDepth) { _accepted = NO; _acceptedActions = 0; }
}
- (BOOL) hasAcceptedAction {
    return _offer && _accepted && WaylandIsFinalDragAction(_action) &&
           (_action & _acceptedActions & _sourceActions) != 0;
}
- (void) drop {
    _dropped = YES;
    if (!_offer) return;
    @try {
        if ([self hasAcceptedAction] && [_window isMapped] &&
            [_destination _receiverForDragSession: self] == _receiver &&
            [_receiver prepareForDragOperation: self] && [_window isMapped] &&
            [_destination _receiverForDragSession: self] == _receiver && [self hasAcceptedAction] &&
            [_receiver performDragOperation: self] && !_transferFailed && [self hasAcceptedAction]) {
            if (WL.wl_proxy_get_version(_offer) >= 3)
                WaylandMarshal(_offer, WP_DATA_OFFER_FINISH, NULL, 0, NULL);
            [self invalidate];
            [_receiver concludeDragOperation: self];
        }
    } @finally { [self invalidate]; [_display flush]; }
}
- (void) leave {
    // Compositors may send leave immediately after drop; the queued transfer
    // still owns the offer until finish, including during nested event pumping.
    if (_dropAnnounced) return;
    [self invalidate];
    [_receiver draggingExited: self];
}
- (NSPasteboard *) draggingPasteboard { return self; }
- (NSDragOperation) draggingSourceOperationMask {
    // Once dropped, tell the receiver which operation the compositor chose.
    // NSDraggingInfo has no separate selected-operation accessor.
    uint32_t actions = _dropped ? ([self hasAcceptedAction] ? _action : 0) : _sourceActions;
    NSDragOperation operations = WaylandOperationsFromActions(actions);
    return _localSource ? (operations & _localOperations) : operations;
}
- (NSPoint) draggingLocation { return _point; }
- (NSWindow *) draggingDestinationWindow { return _destination; }
- (NSImage *) draggedImage { return nil; }
- (NSPoint) draggedImageLocation { return _point; }
- (id) draggingSource { return _localSource; }
- (int) draggingSequenceNumber { return _sequence; }
- (void) slideDraggedImageTo: (NSPoint) point {}
- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination { return nil; }
@end
