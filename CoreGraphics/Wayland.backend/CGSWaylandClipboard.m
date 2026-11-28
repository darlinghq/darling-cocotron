/*
This file is part of Darling.

Copyright (C) 2026 Lubos Dolezel

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import "CGSWaylandClipboard.h"
#import "CGSWaylandDrag.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

static const NSTimeInterval TransferTimeout = 5;

static void destroyProxy(struct wl_proxy *proxy, uint32_t opcode) {
    if (proxy != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(proxy, opcode, NULL, WL_MARSHAL_FLAG_DESTROY, args);
    }
}

@implementation CGSWaylandClipboard

- (id<CGSSelectionSource>) source {
    return _delegateSource;
}

- (void) setSource: (id<CGSSelectionSource>) source {
    _delegateSource = source;
}

- (id) initWithConnection: (CGSConnectionWayland *) connection manager: (struct wl_proxy *) manager seat: (struct wl_proxy *) seat {
    if ((self = [super init])) {
        _connection = connection;
        _manager = manager;
        _offers = [NSMutableDictionary new];
        _offerActions = [NSMutableDictionary new];
        _types = [NSMutableArray new];
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) seat}};
        _device = [connection createObject: manager
                                    opcode: WP_DATA_MANAGER_GET_DEVICE
                                 interface: &wl_data_device_interface
                                 arguments: args
                                      kind: CGSWaylandObjectDataDevice
                                    object: self];
        if (_device == NULL) {
            [self release];
            return nil;
        }
    }
    return self;
}

- (void) invalidate {
    destroyProxy(_source, WP_DATA_SOURCE_DESTROY);
    _source = NULL;
    for (NSValue *key in _offers)
        destroyProxy([key pointerValue], WP_DATA_OFFER_DESTROY);
    [_offers removeAllObjects];
    [_offerActions removeAllObjects];
    _selection = NULL;
    if (_device != NULL) {
        if (WL.wl_proxy_get_version(_device) >= 2)
            destroyProxy(_device, WP_DATA_DEVICE_RELEASE);
        else
            WL.wl_proxy_destroy(_device);
    }
    _device = _manager = NULL;
    _connection = nil;
}

- (void) dealloc {
    [self invalidate];
    [_hostChangeHandler release];
    [_offers release];
    [_offerActions release];
    [_types release];
    [_sourceData release];
    [super dealloc];
}

- (struct wl_proxy *) dataDevice {
    return _device;
}

- (void) setDrag: (id) drag {
    _drag = drag;
}

- (BOOL) ownsSelection {
    return _owned;
}

- (void) setHostChangeHandler: (void (^)(void)) handler {
    [_hostChangeHandler release];
    _hostChangeHandler = [handler copy];
}

- (NSInteger) changeCount {
    [_connection processPendingEvents];
    return _changeCount;
}

- (void) bumpChangeCount {
    _changeCount++;
}

- (void) inputAvailable {
    if (!_needsPublish || _publishQueued || _publishing || _device == NULL)
        return;
    _publishQueued = YES;
    [_connection performAfterDispatch: ^{
      self->_publishQueued = NO;
      [self publishSelection];
    }];
}

// The process holds the selection and what it holds is not yet with the compositor.
- (void) changed {
    _owned = YES;
    if (_publishing)
        return;
    // The serial is taken while the input that caused the change is handled: by the time the
    // selection is published the focus may have left, and a later input must not stand in for it.
    _changeSerial = [_connection clipboardSerial];
    _needsPublish = YES;
    [self inputAvailable];
}

- (void) acquire {
    [self changed];
}

- (void) setLocalTypes: (NSArray<NSString *> *) types {
    [_types setArray: types];
    [self changed];
}

- (void) relinquish {
    _owned = NO;
    _needsPublish = NO;
    [_types removeAllObjects];
}

- (NSArray<NSString *> *) remoteTypes {
    [_connection processPendingEvents];
    if (_owned || _device == NULL)
        return @[];
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *mime in [_offers objectForKey: [NSValue valueWithPointer: _selection]]) {
        for (NSString *type in _CGSSelectionTypesForMime(mime))
            if (![types containsObject: type])
                [types addObject: type];
    }
    return types;
}

// What the process publishes: for every type the source has, the data under each of the MIME types it is offered as.
- (void) publishSelection {
    uint32_t serial = _changeSerial ? _changeSerial : [_connection clipboardSerial];
    if (!_needsPublish || _device == NULL || !serial || !_owned)
        return;
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    _publishing = YES;
    @try {
        for (NSString *type in [[_types copy] autorelease]) {
            NSData *data = _CGSSelectionEncodeData([_delegateSource selectionDataForType: type], type);
            if (data != nil && [data length] <= CGSSelectionTransferLimit)
                for (NSString *mime in _CGSSelectionMimeTypesForType(type))
                    if ([type isEqual: mime] || ![snapshot objectForKey: mime])
                        [snapshot setObject: data forKey: mime];
        }
    } @finally {
        _publishing = NO;
    }
    union wl_argument args[2] = {{.o = NULL}};
    struct wl_proxy *source = NULL;
    if ([snapshot count]) {
        source = [_connection createObject: _manager
                                    opcode: WP_DATA_MANAGER_CREATE_SOURCE
                                 interface: &wl_data_source_interface
                                 arguments: args
                                      kind: CGSWaylandObjectDataSource
                                    object: self];
        for (NSString *mime in snapshot) {
            args[0].s = [mime UTF8String];
            WaylandMarshal(source, WP_DATA_SOURCE_OFFER, NULL, 0, args);
        }
    }
    args[0].o = (struct wl_object *) source;
    args[1].u = serial;
    WaylandMarshal(_device, WP_DATA_DEVICE_SET_SELECTION, NULL, 0, args);
    destroyProxy(_source, WP_DATA_SOURCE_DESTROY);
    _source = source;
    [_sourceData release];
    _sourceData = [snapshot copy];
    _needsPublish = NO;
    _changeSerial = 0;
    [_connection flush];
}

// The data an offer gives for a MIME type, read from a pipe the offer's owner writes to.
- (NSData *) readFromOffer: (struct wl_proxy *) offer mime: (NSString *) mime whileValid: (BOOL (^)(void)) valid {
    if (offer == NULL || mime == nil || _device == NULL)
        return nil;
    int fds[2];
    if (pipe(fds) != 0)
        return nil;
    fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    int flags = fcntl(fds[0], F_GETFL);
    if (flags < 0 || fcntl(fds[0], F_SETFL, flags | O_NONBLOCK) < 0) {
        close(fds[0]);
        close(fds[1]);
        return nil;
    }
    union wl_argument args[2] = {{.s = [mime UTF8String]}, {.h = fds[1]}};
    WaylandMarshal(offer, WP_DATA_OFFER_RECEIVE, NULL, 0, args);
    close(fds[1]);
    [_connection flush];
    NSMutableData *data = [NSMutableData data];
    BOOL complete = NO;
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + TransferTimeout;
    @try {
        while ([NSDate timeIntervalSinceReferenceDate] < deadline && valid()) {
            char bytes[16384];
            ssize_t count = read(fds[0], bytes, sizeof(bytes));
            if (count == 0) {
                complete = YES;
                break;
            }
            if (count > 0) {
                if ([data length] + count > CGSSelectionTransferLimit) {
                    NSLog(@"Wayland clipboard: incoming transfer exceeds 16 MiB");
                    break;
                }
                [data appendBytes: bytes length: count];
                continue;
            }
            if (errno == EINTR)
                continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK)
                break;
            // Service the compositor while the synchronous call waits.
            [_connection processPendingEvents];
            struct pollfd ready = {.fd = fds[0], .events = POLLIN};
            poll(&ready, 1, 20);
        }
    } @finally {
        close(fds[0]);
    }
    return complete && valid() ? data : nil;
}

// The data of a type the selection's owner offers.
- (NSData *) remoteDataForType: (NSString *) type {
    [_connection processPendingEvents];
    if (_owned || _device == NULL)
        return nil;
    NSString *mime = nil;
    NSArray *offered = [_offers objectForKey: [NSValue valueWithPointer: _selection]];
    for (NSString *candidate in _CGSSelectionMimeTypesForType(type))
        if ([offered containsObject: candidate]) {
            mime = candidate;
            break;
        }
    if (mime == nil || _selection == NULL)
        return nil;
    NSUInteger generation = _selectionGeneration;
    NSData *data = [self readFromOffer: _selection mime: mime whileValid: ^BOOL {
        return generation == self->_selectionGeneration;
    }];
    return data != nil ? _CGSSelectionDecodeData(data, type, mime) : nil;
}

- (void) removeOffer: (struct wl_proxy *) offer {
    if (offer == NULL)
        return;
    [_offers removeObjectForKey: [NSValue valueWithPointer: offer]];
    [_offerActions removeObjectForKey: [NSValue valueWithPointer: offer]];
    destroyProxy(offer, WP_DATA_OFFER_DESTROY);
}

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args {
    if (kind == CGSWaylandObjectDataDevice) {
        if (opcode == WP_DATA_DEVICE_EV_OFFER) {
            struct wl_proxy *offer = (struct wl_proxy *) args[0].o;
            [_offers setObject: [NSMutableArray array] forKey: [NSValue valueWithPointer: offer]];
            [_connection attachDispatcherTo: offer kind: CGSWaylandObjectDataOffer object: self];
        } else if (opcode == WP_DATA_DEVICE_EV_SELECTION) {
            struct wl_proxy *offer = (struct wl_proxy *) args[0].o;
            if (_selection != offer)
                [self removeOffer: _selection];
            _selection = offer;
            // Clearing publishes a NULL source, which can never be cancelled.
            // A later external offer must still replace that empty local state.
            if (offer != NULL && _source == NULL && !_needsPublish)
                _owned = NO;
            _selectionGeneration++;
            _changeCount++;
            if (offer != NULL && !_owned && _hostChangeHandler != nil) {
                void (^handler)(void) = [_hostChangeHandler retain];
                [_connection performAfterDispatch: ^{
                  handler();
                  [handler release];
                }];
            }
            // A local source may receive its own offer. Cancellation tells us
            // when ownership actually changes; NULL on focus loss is not loss.
        } else if (opcode == WP_DATA_DEVICE_EV_ENTER) {
            // The drag takes the offer, and destroys it when it is over with it: a compositor that tracks one offer
            // per drag source (wlroots does) cancels the drag when the offer goes before the drop is finished.
            struct wl_proxy *offer = (struct wl_proxy *) args[4].o;
            NSValue *key = [NSValue valueWithPointer: offer];
            NSArray *mimes = [[[_offers objectForKey: key] copy] autorelease];
            uint32_t actions = [[_offerActions objectForKey: key] unsignedIntValue];
            [_offers removeObjectForKey: key];
            [_offerActions removeObjectForKey: key];
            CGPoint point = CGPointMake(wl_fixed_to_double(args[2].f), wl_fixed_to_double(args[3].f));
            if (_drag != nil) {
                [(CGSWaylandDrag *) _drag deviceEnteredSurface: (struct wl_proxy *) args[1].o
                                                        serial: args[0].u
                                                         offer: offer
                                                         mimes: mimes
                                                 sourceActions: actions
                                                       atPoint: point];
            } else {
                destroyProxy(offer, WP_DATA_OFFER_DESTROY);
            }
        } else if (opcode == WP_DATA_DEVICE_EV_MOTION) {
            [(CGSWaylandDrag *) _drag deviceMovedToPoint: CGPointMake(wl_fixed_to_double(args[1].f),
                                                                       wl_fixed_to_double(args[2].f))];
        } else if (opcode == WP_DATA_DEVICE_EV_DROP) {
            [(CGSWaylandDrag *) _drag deviceDropped];
        } else if (opcode == WP_DATA_DEVICE_EV_LEAVE) {
            [(CGSWaylandDrag *) _drag deviceLeft];
        }
    } else if (kind == CGSWaylandObjectDataOffer && opcode == WP_DATA_OFFER_EV_SOURCE_ACTIONS) {
        if ([(CGSWaylandDrag *) _drag ownsOffer: proxy])
            [(CGSWaylandDrag *) _drag offer: proxy sourceActions: args[0].u];
        else
            [_offerActions setObject: [NSNumber numberWithUnsignedInt: args[0].u] forKey: [NSValue valueWithPointer: proxy]];
    } else if (kind == CGSWaylandObjectDataOffer && opcode == WP_DATA_OFFER_EV_ACTION) {
        [(CGSWaylandDrag *) _drag offer: proxy action: args[0].u];
    } else if (kind == CGSWaylandObjectDataOffer && opcode == WP_DATA_OFFER_EV_OFFER) {
        if (args[0].s) {
            NSString *mime = [NSString stringWithUTF8String: args[0].s];
            if (mime)
                [[_offers objectForKey: [NSValue valueWithPointer: proxy]] addObject: mime];
        }
    } else if (kind == CGSWaylandObjectDataSource) {
        if (opcode == WP_DATA_SOURCE_EV_SEND) {
            int fd = args[1].h;
            NSString *mime = args[0].s ? [NSString stringWithUTF8String: args[0].s] : nil;
            NSData *data = mime ? [_sourceData objectForKey: mime] : nil;
            if (!data || proxy != _source) {
                close(fd);
                return;
            }
            _CGSSelectionSendData(data, fd);
        } else if (opcode == WP_DATA_SOURCE_EV_CANCELLED && proxy == _source) {
            destroyProxy(_source, WP_DATA_SOURCE_DESTROY);
            _source = NULL;
            [_sourceData release];
            _sourceData = nil;
            _owned = NO;
            _needsPublish = NO;
            _changeCount++;
            [_types removeAllObjects];
            [_connection performAfterDispatch: ^{
              [_delegateSource selectionLost];
            }];
        }
    }
}

@end
