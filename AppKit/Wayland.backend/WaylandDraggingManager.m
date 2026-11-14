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

#import "WaylandDraggingManager.h"
#import "WaylandDragOperations.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "WaylandPasteboard.h"
#import "WaylandWindow.h"
#import "WaylandDragIcon.h"
#include <math.h>
#import <AppKit/AppKit.h>
#include <unistd.h>
#include <time.h>
#include <poll.h>
#include <stdlib.h>

NSString * const WaylandLocalDragMime = @"application/x-darling-local-drag";

static BOOL monotonicSeconds(double *seconds) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return NO;
    *seconds = now.tv_sec + now.tv_nsec / 1e9;
    return YES;
}

@implementation WaylandDraggingManager
- (id) initWithDisplay: (WaylandDisplay *) display {
    if ((self = [super init])) _display = display;
    return self;
}
// Incoming drops already inspect registered view types while hit testing.
- (void) registerWindow: (NSWindow *) window dragTypes: (NSArray *) types {}
- (void) unregisterWindow: (NSWindow *) window {}
- (id) localDraggingSource { return _nativeStarted && !_finished ? _localSource : nil; }
- (NSDragOperation) localOperations { return _nativeStarted && !_finished ? _localOperations : NSDragOperationNone; }
// The marker carries no payload or capability. Only our currently active drag
// and exact destination session may access the in-process typed snapshot.
- (NSDictionary *) localSnapshotForSession: (id) session mimes: (NSArray *) mimes
                               generation: (NSUInteger *) generation {
    if (!_nativeStarted || _finished || !_localOnly ||
        [mimes count] != 1 || ![[mimes objectAtIndex:0] isEqual:_localMime]) return nil;
    _localSession = session;
    _completedLocalAction = 0;
    *generation = _localGeneration;
    return _localSnapshot;
}
- (BOOL) permitsLocalSession: (id) session generation: (NSUInteger) generation {
    return _nativeStarted && !_finished && _localOnly &&
           session == _localSession && generation == _localGeneration;
}
- (void) revokeLocalSession: (id) session generation: (NSUInteger) generation {
    if (session == _localSession && generation == _localGeneration) _localSession = nil;
}
- (BOOL) completeLocalSession: (id) session generation: (NSUInteger) generation
                       action: (uint32_t) action {
    if (![self permitsLocalSession:session generation:generation] ||
        !WaylandIsFinalDragAction(action) || !(action & _offeredActions)) return NO;
    _completedLocalAction = action;
    return YES;
}
- (void) cancel {
    if (_finished) return;
    _finished = YES;
    _action = 0;
    _localSession = nil;
}
- (void) invalidate {
    [self cancel]; [_icon invalidate]; [self destroySource]; [_display flush]; _display = nil;
}
- (void) outputRemoved: (struct wl_proxy *) output { [_icon outputRemoved: output]; }
- (void) outputsChanged { [_icon scheduleScaleUpdate]; }
- (void) windowUnmapped: (WaylandWindow *) window {
    if (_origin == window) [self cancel];
}
- (void) destroySource {
    if (_source != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(_source, WP_DATA_SOURCE_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, args);
        _source = NULL;
    }
}
- (void) dealloc {
    [self destroySource];
    [_icon invalidate]; [_icon release];
    [_localSnapshot release]; [_localMime release];
    [_snapshot release]; [_origin release]; [_localSource release];
    [super dealloc];
}
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args {
    if (opcode == WP_DATA_SOURCE_EV_SEND) {
        if (proxy != _source || _finished || _localOnly) { close(args[1].h); return; }
        NSString *mime = args[0].s ? [NSString stringWithUTF8String: args[0].s] : nil;
        WaylandSendData(_display, mime ? [_snapshot objectForKey: mime] : nil, args[1].h);
        return;
    }
    if (proxy != _source || _finished) return;
    if (opcode == WP_DATA_SOURCE_EV_ACTION) _action = args[0].u;
    else if (opcode == WP_DATA_SOURCE_EV_DROP_PERFORMED) {
        _dropped = YES;
        if (!monotonicSeconds(&_dropDeadline)) [self cancel];
        else _dropDeadline += 10;
    }
    else if (opcode == WP_DATA_SOURCE_EV_CANCELLED) [self cancel];
    else if (opcode == WP_DATA_SOURCE_EV_FINISHED) {
        if (!_dropped || !WaylandIsFinalDragAction(_action) || !(_action & _offeredActions)) _action = 0;
        _finished = YES;
    }
}
- (void) dragImage: (NSImage *) image at: (NSPoint) location
            offset: (NSSize) offset event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard source: (id) source
         slideBack: (BOOL) slideBack {
    if (_busy || ![NSThread isMainThread] || _display == nil) return;
    struct wl_proxy *manager = _display->_dataDeviceManager;
    struct wl_proxy *device = [_display dragDataDevice];
    // Older protocol versions cannot reliably report outgoing completion.
    if (!manager || !device || WL.wl_proxy_get_version(manager) < 3) return;
    WaylandWindow *origin = [_display dragOriginForEvent: event];
    uint32_t serial = [_display dragSerialForEvent: event];
    if (!origin || !serial) return;
    [self retain]; // Display invalidation may release its ownership while pumping.
    _busy = YES; _finished = NO; _dropped = NO; _action = 0;
    _nativeStarted = NO; _localOnly = NO; _localSession = nil;
    ++_localGeneration; _completedLocalAction = 0;
    _origin = [origin retain]; _localSource = [source retain];
    NSImage *heldImage = [image retain];
    BOOL began = NO;
    NSDragOperation result = NSDragOperationNone;
    @try {
        NSDragOperation allowed = NSDragOperationCopy;
        _localOperations = NSDragOperationCopy;
        if ([source respondsToSelector: @selector(draggingSourceOperationMaskForLocal:)]) {
            allowed = [source draggingSourceOperationMaskForLocal: NO];
            _localOperations = [source draggingSourceOperationMaskForLocal: YES];
        }
        NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
        NSUInteger bytes = 0;
        _offeredActions = WaylandActionsFromOperations(allowed);
        _localOnly = !_offeredActions && WaylandActionsFromOperations(_localOperations);
        if (_localOnly) _offeredActions = WaylandActionsFromOperations(_localOperations);
        if (_offeredActions) {
            for (NSString *type in [[[pasteboard types] copy] autorelease]) {
                if ([type isEqual:@"DELETE"]) continue;
                NSData *data = [pasteboard dataForType: type];
                if (!data) {
                    if ([type isEqual:NSFilenamesPboardType]) { [snapshot removeAllObjects]; break; }
                    continue;
                }
                if (!_localOnly) data = [WaylandPasteboard encodeData:data forType:type];
                // A partial filename selection could make a MOVE source remove
                // files that were never delivered. Reject that drag atomically.
                if (!data) { [snapshot removeAllObjects]; break; }
                if ([data length] > 16 * 1024 * 1024 - bytes) {
                    [snapshot removeAllObjects]; break;
                }
                bytes += [data length];
                NSData *copy = [[data copy] autorelease];
                if (_localOnly) {
                    [snapshot setObject:copy forKey:type];
                    continue;
                }
                for (NSString *mime in [WaylandPasteboard mimeTypesForType: type])
                    if ([type isEqual:mime] || ![snapshot objectForKey:mime])
                        [snapshot setObject:copy forKey:mime];
            }
        }
        if (image != nil && [snapshot count] && !_finished && _display) {
            NSPoint pointer = [event locationInWindow];
            NSPoint iconOffset = NSMakePoint(location.x - pointer.x,
                    pointer.y - location.y - ceil([image size].height));
            _icon = [[WaylandDragIcon alloc] initWithImage: image display: _display
                    scale120: [origin renderScale120] fallbackScale: [origin bufferScale] offset: iconOffset];
        }
        // Lazy providers/image drawing may run the event loop, release the button or unmap.
        if ([snapshot count] && !_finished && _display &&
            [_display dragOriginForEvent: event] == origin &&
            [_display dragSerialForEvent: event] == serial) {
            if (_localOnly) {
                _localSnapshot = [snapshot copy];
                // Unique correlation marker rejects stale offers. It contains
                // no user payload/type names and is never a data capability.
                _localMime = [[NSString alloc] initWithFormat:@"%@-%08x%08x%08x%08x",
                        WaylandLocalDragMime, arc4random(), arc4random(), arc4random(), arc4random()];
                _snapshot = [@{_localMime:[NSData data]} copy];
            } else _snapshot = [snapshot copy];
            union wl_argument args[4] = {{.o = NULL}};
            _source = WaylandCreateObject(manager, WP_DATA_MANAGER_CREATE_SOURCE,
                    &wl_data_source_interface, args, WaylandObjectDataSource, self);
            for (NSString *mime in _snapshot) {
                args[0].s = [mime UTF8String];
                WaylandMarshal(_source, WP_DATA_SOURCE_OFFER, NULL, 0, args);
            }
            args[0].u = _offeredActions;
            WaylandMarshal(_source, WP_DATA_SOURCE_SET_ACTIONS, NULL, 0, args);
            args[0].o = (struct wl_object *) _source;
            args[1].o = (struct wl_object *) [origin surface];
            args[2].o = (struct wl_object *) [_icon surface];
            args[3].u = serial;
            [_display consumeDragPress];
            WaylandMarshal(device, WP_DATA_DEVICE_START_DRAG, NULL, 0, args);
            _nativeStarted = YES;
            [_icon show];
            [_display flush]; began = YES;
            if ([source respondsToSelector: @selector(draggedImage:beganAt:)])
                [source draggedImage: heldImage beganAt: location];
            while (!_finished && _display != nil) {
                @autoreleasepool {
                    [_display processPendingEvents];
                    if (_dropped) {
                        double now;
                        if (!monotonicSeconds(&now) || now >= _dropDeadline) [self cancel];
                    }
                    if (!_finished) {
                        // Pump timers/sources without a nested timed Mach wait.
                        // The native display fd bounds the sleep even when a
                        // drop destination never sends its completion event.
                        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
                        if (!_finished && _display != nil) {
                            struct pollfd ready = {.fd = WL.wl_display_get_fd(_display->_wlDisplay),
                                                   .events = POLLIN};
                            poll(&ready, 1, 10);
                        }
                    }
                }
            }
            if (_finished && WaylandIsFinalDragAction(_action) && (_action & _offeredActions) &&
                (!_localOnly || _completedLocalAction == _action))
                result = WaylandOperationsFromActions(_action);
        }
    } @finally {
        _nativeStarted = NO; _localSession = nil;
        [_localSnapshot release]; _localSnapshot = nil;
        [_localMime release]; _localMime = nil;
        [_icon invalidate]; [_icon release]; _icon = nil;
        [self destroySource];
        [_display flush];
        [_snapshot release]; _snapshot = nil;
        [_origin release]; _origin = nil;
        id finishedSource = _localSource;
        _localSource = nil;
        _busy = NO;
        @try {
            // Core Wayland supplies no global drop coordinates; retain the
            // documented virtual starting location rather than invent one.
            if (began && [finishedSource respondsToSelector: @selector(draggedImage:endedAt:operation:)])
                [finishedSource draggedImage: heldImage endedAt: location operation: result];
        } @finally { [finishedSource release]; [heldImage release]; [self release]; }
    }
}
@end
