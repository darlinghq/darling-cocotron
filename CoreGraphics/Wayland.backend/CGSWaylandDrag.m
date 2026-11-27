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

#import "CGSWaylandDrag.h"
#import "CGSWaylandClipboard.h"
#import "CGSWaylandPointer.h"
#import "CGSWindowWayland.h"
#import <CoreGraphics/CGSSelection.h>
#import <CoreGraphics/CoreGraphics.h>
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

// The actions of wl_data_device_manager, which can say two of the operations (a copy and a move).
enum { CGSWaylandActionCopy = 1, CGSWaylandActionMove = 2 };

// The name of the type the drag of a source that only this process may read offers instead of the data: the
// compositor needs something to match, and this offers nothing to read.
static NSString *const LocalMarkerPrefix = @"application/x-darling-local-drag";

// How long the destination has to finish with the data after the compositor says the source dropped.
static const NSTimeInterval DropFinishGrace = 10.0;
// How long a drag whose release the UI layer has seen waits for the compositor to say how it ended.
static const NSTimeInterval EndGrace = 0.5;
// The most pixels of the drag image.
static const uint64_t DragImageLimit = 4 * 1024 * 1024;

static uint32_t actionsFromOperations(CGSDragOperation operations) {
    return ((operations & kCGSDragOperationCopy) ? CGSWaylandActionCopy : 0u) |
           ((operations & kCGSDragOperationMove) ? CGSWaylandActionMove : 0u);
}

static CGSDragOperation operationsFromActions(uint32_t actions) {
    return ((actions & CGSWaylandActionCopy) ? kCGSDragOperationCopy : kCGSDragOperationNone) |
           ((actions & CGSWaylandActionMove) ? kCGSDragOperationMove : kCGSDragOperationNone);
}

// The one action the compositor settled on, which is what a drop does.
static BOOL isFinalAction(uint32_t action) {
    return action == CGSWaylandActionCopy || action == CGSWaylandActionMove;
}

static BOOL monotonicSeconds(double *seconds) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return NO;
    *seconds = now.tv_sec + now.tv_nsec / 1e9;
    return YES;
}

static void destroyProxy(struct wl_proxy *proxy, uint32_t opcode) {
    if (proxy != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(proxy, opcode, NULL, WL_MARSHAL_FLAG_DESTROY, args);
    }
}

#pragma mark - The icon

// The image dragged along with the pointer: a surface the compositor moves with the drag.
@interface CGSWaylandDragIcon : NSObject {
    CGSConnectionWayland *_connection; // not retained: the connection outlives the drag
    struct wl_proxy *_surface, *_buffer;
    CGPoint _offset;
    int32_t _scale;
}
- (instancetype) initWithImage: (CGImageRef) image
                    imageScale: (CGFloat) imageScale
                        offset: (CGPoint) offset
                    connection: (CGSConnectionWayland *) connection;
- (struct wl_proxy *) surface;
- (void) show;
- (void) invalidate;
@end

@implementation CGSWaylandDragIcon

- (instancetype) initWithImage: (CGImageRef) image
                    imageScale: (CGFloat) imageScale
                        offset: (CGPoint) offset
                    connection: (CGSConnectionWayland *) connection {
    if ((self = [super init]) == nil)
        return nil;
    _connection = connection;
    if (image == NULL || connection->_compositor == NULL || connection->_shm == NULL || !isfinite(offset.x) ||
        !isfinite(offset.y) || fabs(offset.x) > INT32_MAX || fabs(offset.y) > INT32_MAX) {
        [self release];
        return nil;
    }
    if (!(imageScale >= 1))
        imageScale = 1;
    // The image is as many points as it has pixels for the scale it was made at; it is drawn for the scale of the
    // outputs, whole because set_buffer_scale takes no other (the compositor scales it down for a fractional one).
    double pointsWide = ceil(CGImageGetWidth(image) / imageScale), pointsHigh = ceil(CGImageGetHeight(image) / imageScale);
    _scale = WL.wl_proxy_get_version(connection->_compositor) >= 3
                 ? (int32_t) (([connection maximumOutputScale120] + 119) / 120)
                 : 1;
    if (_scale < 1)
        _scale = 1;
    // The raster is bounded before anything is made for it.
    if (pointsWide < 1 || pointsHigh < 1 || pointsWide * _scale * pointsHigh * _scale > DragImageLimit) {
        [self release];
        return nil;
    }
    size_t width = (size_t) pointsWide * _scale, height = (size_t) pointsHigh * _scale;
    NSMutableData *pixels = [NSMutableData dataWithLength: width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate([pixels mutableBytes], width, height, 8, width * 4, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (context == NULL) {
        [self release];
        return nil;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);

    _offset = CGPointMake(floor(offset.x), floor(offset.y));
    union wl_argument args[1] = {{.o = NULL}};
    _surface = [connection createObject: connection->_compositor
                                 opcode: WP_COMPOSITOR_CREATE_SURFACE
                              interface: &wl_surface_interface
                              arguments: args
                                   kind: CGSWaylandObjectNone
                                 object: nil];
    _buffer = WaylandCreateARGBBuffer(connection->_shm, [pixels bytes], [pixels length], (int32_t) width, (int32_t) height);
    if (_surface == NULL || _buffer == NULL) {
        [self release];
        return nil;
    }
    return self;
}

- (struct wl_proxy *) surface {
    return _surface;
}

// The surface is attached with the offset that puts its top left corner where the drag says (the compositor binds
// at most version 4 of wl_compositor here, where attach carries the offset).
- (void) show {
    if (_surface == NULL || _buffer == NULL)
        return;
    if (WL.wl_proxy_get_version(_connection->_compositor) >= 3) {
        union wl_argument scale[1] = {{.i = _scale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scale);
    }
    union wl_argument attach[3] = {{.o = (struct wl_object *) _buffer}, {.i = (int32_t) _offset.x}, {.i = (int32_t) _offset.y}};
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
    union wl_argument damage[4] = {{.i = 0}, {.i = 0}, {.i = INT32_MAX}, {.i = INT32_MAX}};
    WaylandMarshal(_surface, WP_SURFACE_DAMAGE, NULL, 0, damage);
    WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, NULL);
}

- (void) invalidate {
    if (_surface != NULL)
        WaylandMarshal(_surface, WP_SURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    if (_buffer != NULL)
        WaylandMarshal(_buffer, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _surface = _buffer = NULL;
}

- (void) dealloc {
    [self invalidate];
    [super dealloc];
}

@end

#pragma mark - A drag over a window

// One drag that is over a window of the process, from the compositor's enter to the end of the drop or the leave.
@interface CGSWaylandDropSession : NSObject <CGSDropSession> {
    CGSWaylandDrag *_drag; // not retained: the drag owns the session
    struct wl_proxy *_offer;
    uint32_t _windowID;
    NSArray *_mimes, *_types;
    NSMutableDictionary *_cache, *_wireCache;
    uint32_t _serial, _sourceActions, _action, _acceptedActions;
    // What the drag of this process offers when this session is of it (see -fromThisProcess), where the data is
    // read, and the drag's local operations.
    BOOL _fromThisProcess;
    NSDictionary *_localSnapshot;
    CGSDragOperation _localOperations, _sourceOperationsMask;
    id<CGSDragDestination> _destination; // retained, while the destination knows of the session
    CGPoint _point;
    BOOL _entered, _dropAnnounced, _dropped, _accepted, _invalidated;
    NSUInteger _motionGeneration, _negotiationDepth;
}
- (instancetype) initWithDrag: (CGSWaylandDrag *) drag
                        offer: (struct wl_proxy *) offer
                        mimes: (NSArray *) mimes
                     windowID: (uint32_t) windowID
                       serial: (uint32_t) serial
                sourceActions: (uint32_t) actions;
- (struct wl_proxy *) offer;
- (BOOL) isDropAnnounced;
- (void) sourceActions: (uint32_t) actions;
- (void) selectedAction: (uint32_t) action;
- (void) motion: (CGPoint) surfacePoint;
- (void) markDropped;
- (void) drop;
- (void) willLeave;
- (void) leave;
- (void) invalidate;
@end

#pragma mark - A drag of this process

@interface CGSWaylandDragSession : NSObject <CGSDragSession> {
    CGSWaylandDrag *_drag; // not retained: the UI layer owns the session
    id<CGSDragSource> _source;
    CGSDragOperation _localOperations;
    uint32_t _originWindow;
    struct wl_proxy *_wlSource;
    CGSWaylandDragIcon *_icon;
    // What is offered, by MIME type (by type for a drag of this process only, which offers a marker instead).
    NSDictionary *_snapshot, *_localSnapshot;
    NSString *_localMime;
    id _localSession; // the session that reads the local snapshot, not retained
    uint32_t _offeredActions, _action, _completedLocalAction;
    BOOL _localOnly, _finished, _dropped, _closed;
    double _dropDeadline;
}
- (instancetype) initWithDrag: (CGSWaylandDrag *) drag description: (const CGSDragDescription *) description;
- (uint32_t) originWindow;
- (NSDictionary *) snapshotOfTypes: (NSArray *) types localOnly: (BOOL) localOnly encodable: (BOOL *) encodable;
- (void) cancel;
- (BOOL) active;
- (NSDictionary *) localSnapshotForSession: (id) session mimes: (NSArray *) mimes;
- (BOOL) permitsLocalSession: (id) session;
- (void) revokeLocalSession: (id) session;
- (BOOL) completeLocalSession: (id) session action: (uint32_t) action;
- (CGSDragOperation) localOperations;
- (void) sourceEvent: (uint32_t) opcode proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;
@end

@implementation CGSWaylandDropSession

- (instancetype) initWithDrag: (CGSWaylandDrag *) drag
                        offer: (struct wl_proxy *) offer
                        mimes: (NSArray *) mimes
                     windowID: (uint32_t) windowID
                       serial: (uint32_t) serial
                sourceActions: (uint32_t) actions {
    if ((self = [super init]) == nil)
        return nil;
    _drag = drag;
    _offer = offer;
    _windowID = windowID;
    _serial = serial;
    _mimes = [mimes copy];
    _cache = [NSMutableDictionary new];
    _wireCache = [NSMutableDictionary new];
    // A compositor older than the actions has the drag copy.
    _sourceActions = actions;
    if (offer != NULL && WL.wl_proxy_get_version(offer) < 3)
        _sourceActions = _action = CGSWaylandActionCopy;

    CGSWaylandDragSession *outgoing = drag->_outgoing;
    if (outgoing != nil && [outgoing active]) {
        _fromThisProcess = YES;
        _localOperations = [outgoing localOperations];
        _localSnapshot = [[outgoing localSnapshotForSession: self mimes: mimes] retain];
    }
    if (_localSnapshot != nil) {
        _types = [[_localSnapshot allKeys] copy];
    } else {
        NSMutableArray *types = [NSMutableArray array];
        for (NSString *mime in mimes) {
            // A control target of the protocol, never data.
            if ([mime isEqual: @"DELETE"])
                continue;
            for (NSString *type in _CGSSelectionTypesForMime(mime))
                if (![types containsObject: type])
                    [types addObject: type];
        }
        _types = [types copy];
    }
    [self updateSourceOperations];
    return self;
}

- (void) updateSourceOperations {
    uint32_t actions = _sourceActions;
    if (_fromThisProcess)
        actions &= actionsFromOperations(_localOperations);
    _sourceOperationsMask = operationsFromActions(actions);
}

- (void) dealloc {
    [self invalidate];
    [_destination release];
    [_mimes release];
    [_types release];
    [_cache release];
    [_wireCache release];
    [_localSnapshot release];
    [super dealloc];
}

- (struct wl_proxy *) offer {
    return _offer;
}

- (NSArray<NSString *> *) types {
    return _types;
}

- (CGSDragOperation) sourceOperations {
    return _sourceOperationsMask;
}

- (BOOL) isDropAnnounced {
    return _dropAnnounced;
}

- (BOOL) fromThisProcess {
    return _fromThisProcess;
}

- (CGSWindowWayland *) window {
    CGSWindow *window = _windowID != 0 ? [_drag->_connection windowForId: (CGSWindowID) _windowID] : nil;
    return [window isKindOfClass: [CGSWindowWayland class]] ? (CGSWindowWayland *) window : nil;
}

- (void) sourceActions: (uint32_t) actions {
    if (!_dropAnnounced && (_offer == NULL || WL.wl_proxy_get_version(_offer) >= 3)) {
        _sourceActions = actions;
        [self updateSourceOperations];
    }
}

- (void) selectedAction: (uint32_t) action {
    if (!_dropAnnounced)
        _action = action;
}

// Whether this session may read what the drag of this process holds: only while the drag runs, and only for the
// session it handed the marker to.
- (BOOL) hasLocalAccess {
    CGSWaylandDragSession *outgoing = _drag->_outgoing;
    return _localSnapshot != nil && _offer != NULL && outgoing != nil && [outgoing permitsLocalSession: self];
}

- (NSString *) mimeForType: (NSString *) type {
    if (type == nil || [type isEqual: @"DELETE"])
        return nil;
    if (_localSnapshot != nil)
        return [self hasLocalAccess] && [_localSnapshot objectForKey: type] ? [_mimes objectAtIndex: 0] : nil;
    for (NSString *mime in _CGSSelectionMimeTypesForType(type))
        if ([_mimes containsObject: mime])
            return mime;
    return nil;
}

- (NSData *) dataForType: (NSString *) type {
    if ([type isEqual: @"DELETE"] || ![_types containsObject: type])
        return nil;
    if (_localSnapshot != nil)
        return [self hasLocalAccess] ? [_localSnapshot objectForKey: type] : nil;
    NSData *cached = [_cache objectForKey: type];
    if (cached != nil)
        return cached;
    NSString *mime = [self mimeForType: type];
    if (_offer == NULL || mime == nil)
        return nil;
    NSData *wire = [_wireCache objectForKey: mime];
    if (wire == nil) {
        struct wl_proxy *offer = _offer;
        wire = [_drag->_clipboard readFromOffer: offer mime: mime whileValid: ^BOOL {
            return self->_offer == offer;
        }];
        if (wire == nil)
            return nil;
        [_wireCache setObject: wire forKey: mime];
    }
    NSData *data = _CGSSelectionDecodeData(wire, type, mime);
    if (data != nil)
        [_cache setObject: data forKey: type];
    return data;
}

// The first MIME type of the offer that the position can be accepted with.
- (NSString *) acceptedMime {
    for (NSString *type in _types) {
        NSString *mime = [self mimeForType: type];
        if (mime != nil)
            return mime;
    }
    return nil;
}

- (uint32_t) effectiveActions {
    uint32_t actions = _sourceActions;
    if (_fromThisProcess)
        actions &= actionsFromOperations(_localOperations);
    return actions;
}

- (void) motion: (CGPoint) surfacePoint {
    if (_offer == NULL || _dropped)
        return;
    NSUInteger generation = ++_motionGeneration;
    CGSWindowWayland *window = [self window];
    CGPoint content = window != nil ? [window toplevelContentOffset] : CGPointZero;
    BOOL inContent = window != nil && [window toplevelContentContainsSurfacePoint: surfacePoint];
    _point = CGPointMake(surfacePoint.x - content.x, surfacePoint.y - content.y);

    // Motion queued before the compositor's drop still supplies the final position, but the action chosen at the
    // drop is not renegotiated.
    if (_dropAnnounced) {
        if (!inContent)
            _accepted = NO;
        return;
    }

    CGSDragOperation operation = kCGSDragOperationNone;
    _negotiationDepth++;
    @try {
        id<CGSDragDestination> destination = inContent ? [window dragDestination] : nil;
        if (destination != nil) {
            if (!_entered) {
                _entered = YES;
                _destination = [destination retain];
                operation = [destination dropSession: self enteredAtPoint: _point];
            } else {
                operation = [_destination dropSession: self updatedAtPoint: _point];
            }
        } else if (_entered) {
            // The pointer went over the frame of the window, or the window lost its destination.
            _entered = NO;
            _accepted = NO;
            _acceptedActions = 0;
            id<CGSDragDestination> old = _destination;
            _destination = nil;
            @try {
                [old dropSessionExited: self];
            } @finally {
                [old release];
            }
        }
    } @finally {
        _negotiationDepth--;
    }
    // Cancelled or superseded while the destination answered.
    if (_offer == NULL || generation != _motionGeneration)
        return;
    if (_dropAnnounced) {
        // A callback pumped the compositor's drop: acceptance is only narrowed.
        _acceptedActions &= actionsFromOperations(operation) & [self effectiveActions];
        _accepted = _accepted && _acceptedActions != 0;
        return;
    }

    _acceptedActions = actionsFromOperations(operation) & [self effectiveActions];
    if (WL.wl_proxy_get_version(_offer) < 3)
        _acceptedActions &= CGSWaylandActionCopy;
    NSString *mime = _acceptedActions != 0 ? [self acceptedMime] : nil;
    _accepted = mime != nil;
    if (!_accepted)
        _acceptedActions = 0;
    union wl_argument args[2] = {{.u = _serial}, {.s = _accepted ? [mime UTF8String] : NULL}};
    WaylandMarshal(_offer, WP_DATA_OFFER_ACCEPT, NULL, 0, args);
    if (WL.wl_proxy_get_version(_offer) >= 3) {
        args[0].u = _acceptedActions;
        args[1].u = (_acceptedActions & CGSWaylandActionCopy) ? CGSWaylandActionCopy : (_acceptedActions & CGSWaylandActionMove);
        WaylandMarshal(_offer, WP_DATA_OFFER_SET_ACTIONS, NULL, 0, args);
    }
    [_drag->_connection flush];
}

- (void) markDropped {
    _dropAnnounced = YES;
    // A destination may pump a nested drop before it returns its operation: what the previous position accepted
    // does not stand for the drop while that answer is pending.
    if (_negotiationDepth > 0) {
        _accepted = NO;
        _acceptedActions = 0;
    }
}

- (BOOL) hasAcceptedAction {
    return _offer != NULL && _accepted && (_localSnapshot == nil || [self hasLocalAccess]) && isFinalAction(_action) &&
           (_action & _acceptedActions & [self effectiveActions]) != 0;
}

- (void) drop {
    _dropped = YES;
    if (_offer == NULL)
        return;
    id<CGSDragDestination> destination = _entered ? _destination : nil;
    @try {
        if (destination != nil) {
            CGSDragOperation operation = [self hasAcceptedAction] ? operationsFromActions(_action) : kCGSDragOperationNone;
            CGSDragOperation performed = [destination dropSession: self performWithOperation: operation];
            if (performed != kCGSDragOperationNone && operation != kCGSDragOperationNone && [self hasAcceptedAction]) {
                CGSWaylandDragSession *outgoing = _drag->_outgoing;
                // A drag only this process may read is complete when its destination says so.
                if (_localSnapshot == nil || (outgoing != nil && [outgoing completeLocalSession: self action: _action])) {
                    if (WL.wl_proxy_get_version(_offer) >= 3)
                        WaylandMarshal(_offer, WP_DATA_OFFER_FINISH, NULL, 0, NULL);
                }
            }
        }
    } @finally {
        [self invalidate];
        [_drag->_connection flush];
        if (_drag->_incoming == self) {
            [_drag->_incoming release];
            _drag->_incoming = nil;
        }
    }
}

- (void) willLeave {
    if (!_dropAnnounced)
        [(CGSWaylandDragSession *) _drag->_outgoing revokeLocalSession: self];
}

- (void) leave {
    // The compositor may send the leave right after the drop; the queued drop still owns the offer until it
    // finishes.
    if (_dropAnnounced)
        return;
    [self invalidate];
    if (_entered) {
        _entered = NO;
        id<CGSDragDestination> old = _destination;
        _destination = nil;
        @try {
            [old dropSessionExited: self];
        } @finally {
            [old release];
        }
    }
}

- (void) invalidate {
    if (_invalidated)
        return;
    _invalidated = YES;
    [(CGSWaylandDragSession *) _drag->_outgoing revokeLocalSession: self];
    if (_offer != NULL) {
        destroyProxy(_offer, WP_DATA_OFFER_DESTROY);
        _offer = NULL;
    }
    _accepted = NO;
}

@end

#pragma mark - The session of a drag of this process

@implementation CGSWaylandDragSession

- (instancetype) initWithDrag: (CGSWaylandDrag *) drag description: (const CGSDragDescription *) description {
    if ((self = [super init]) == nil)
        return nil;
    CGSConnectionWayland *connection = drag->_connection;
    struct wl_proxy *manager = [connection dataDeviceManager];
    struct wl_proxy *device = [drag->_clipboard dataDevice];
    uint32_t serial = [connection dragSerial];
    CGSWindow *origin = [connection windowForId: description->window];
    // The drag is tied to the press that started it, and to the surface the press was on. Older protocol versions
    // cannot say how a drag ended.
    if (manager == NULL || device == NULL || WL.wl_proxy_get_version(manager) < 3 || serial == 0 ||
        ![origin isKindOfClass: [CGSWindowWayland class]] || ((CGSWindowWayland *) origin)->_surface == NULL) {
        [self release];
        return nil;
    }
    _drag = drag;
    _originWindow = description->window;
    _localOperations = description->localOperations;

    // A source that allows nothing outside this application can still be dragged within it: the drag then offers
    // what it allows within it, to this application's windows only.
    _offeredActions = actionsFromOperations(description->operations);
    _localOnly = _offeredActions == 0 && actionsFromOperations(_localOperations) != 0;
    if (_localOnly)
        _offeredActions = actionsFromOperations(_localOperations);
    if (_offeredActions == 0) {
        [self release];
        return nil;
    }
    _source = [description->source retain];

    BOOL encodable = YES;
    NSDictionary *snapshot = [self snapshotOfTypes: description->types localOnly: _localOnly encodable: &encodable];
    // Data other clients cannot be given (files only this application can see) still goes to this application.
    if (!encodable && !_localOnly && actionsFromOperations(_localOperations) != 0) {
        _localOnly = YES;
        _offeredActions = actionsFromOperations(_localOperations);
        snapshot = [self snapshotOfTypes: description->types localOnly: YES encodable: &encodable];
    }
    if ([snapshot count] == 0) {
        [self release];
        return nil;
    }

    if (description->image != NULL)
        _icon = [[CGSWaylandDragIcon alloc] initWithImage: description->image
                                               imageScale: description->imageScale
                                                   offset: description->imageOffset
                                               connection: connection];

    // Producing the data and the image can run the application's code, which may release the button or unmap
    // the window: the press has to still be the one the drag started from.
    CGSWindow *current = [connection windowForId: description->window];
    if ([connection dragSerial] != serial || current != origin) {
        [self release];
        return nil;
    }

    if (_localOnly) {
        _localSnapshot = [snapshot copy];
        // A marker nobody can reuse stands for the data: it names the drag, and carries nothing.
        _localMime = [[NSString alloc] initWithFormat: @"%@-%08x%08x%08x%08x", LocalMarkerPrefix, arc4random(),
                                                       arc4random(), arc4random(), arc4random()];
        _snapshot = [@{_localMime : [NSData data]} copy];
    } else {
        _snapshot = [snapshot copy];
    }

    union wl_argument args[4] = {{.o = NULL}};
    _wlSource = [connection createObject: manager
                                  opcode: WP_DATA_MANAGER_CREATE_SOURCE
                               interface: &wl_data_source_interface
                               arguments: args
                                    kind: CGSWaylandObjectDragSource
                                  object: drag];
    if (_wlSource == NULL) {
        [self release];
        return nil;
    }
    for (NSString *mime in _snapshot) {
        args[0].s = [mime UTF8String];
        WaylandMarshal(_wlSource, WP_DATA_SOURCE_OFFER, NULL, 0, args);
    }
    args[0].u = _offeredActions;
    WaylandMarshal(_wlSource, WP_DATA_SOURCE_SET_ACTIONS, NULL, 0, args);
    args[0].o = (struct wl_object *) _wlSource;
    args[1].o = (struct wl_object *) ((CGSWindowWayland *) origin)->_surface;
    args[2].o = (struct wl_object *) [_icon surface];
    args[3].u = serial;
    [connection consumeDragSerial];
    WaylandMarshal(device, WP_DATA_DEVICE_START_DRAG, NULL, 0, args);
    [_icon show];
    [connection flush];
    drag->_outgoing = self;
    return self;
}

// The data of the types as the drag offers it: by type for this application's destinations, by MIME type for
// other clients. Empty when the drag cannot be offered whole; *encodable is NO when that is because some data has
// no form other clients can be given.
- (NSDictionary *) snapshotOfTypes: (NSArray *) types localOnly: (BOOL) localOnly encodable: (BOOL *) encodable {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    NSUInteger bytes = 0;
    *encodable = YES;
    for (NSString *type in types) {
        if ([type isEqual: @"DELETE"])
            continue;
        NSData *data = [_source selectionDataForType: type];
        if (data == nil) {
            // A partial list of files could make a move source remove files that were never delivered.
            if ([type isEqual: @"NSFilenamesPboardType"]) {
                [snapshot removeAllObjects];
                break;
            }
            continue;
        }
        if (!localOnly)
            data = _CGSSelectionEncodeData(data, type);
        if (data == nil) {
            *encodable = NO;
            [snapshot removeAllObjects];
            break;
        }
        if ([data length] > CGSSelectionTransferLimit - bytes) {
            [snapshot removeAllObjects];
            break;
        }
        bytes += [data length];
        NSData *copy = [[data copy] autorelease];
        if (localOnly) {
            [snapshot setObject: copy forKey: type];
            continue;
        }
        for (NSString *mime in _CGSSelectionMimeTypesForType(type))
            if ([type isEqual: mime] || [snapshot objectForKey: mime] == nil)
                [snapshot setObject: copy forKey: mime];
    }
    return snapshot;
}

- (void) dealloc {
    [self close];
    [_source release];
    [_localSnapshot release];
    [_localMime release];
    [_snapshot release];
    [super dealloc];
}

- (uint32_t) originWindow {
    return _originWindow;
}

- (BOOL) active {
    return !_closed && !_finished;
}

- (CGSDragOperation) localOperations {
    return [self active] ? _localOperations : kCGSDragOperationNone;
}

// The marker names the one drag that is running and the one session of this process it was handed to.
- (NSDictionary *) localSnapshotForSession: (id) session mimes: (NSArray *) mimes {
    if (![self active] || !_localOnly || [mimes count] != 1 || ![[mimes objectAtIndex: 0] isEqual: _localMime])
        return nil;
    _localSession = session;
    _completedLocalAction = 0;
    return _localSnapshot;
}

- (BOOL) permitsLocalSession: (id) session {
    return [self active] && _localOnly && session == _localSession;
}

- (void) revokeLocalSession: (id) session {
    if (session == _localSession)
        _localSession = nil;
}

- (BOOL) completeLocalSession: (id) session action: (uint32_t) action {
    if (![self permitsLocalSession: session] || !isFinalAction(action) || !(action & _offeredActions))
        return NO;
    _completedLocalAction = action;
    return YES;
}

- (void) cancel {
    if (_finished)
        return;
    _finished = YES;
    _action = 0;
    _localSession = nil;
}

- (BOOL) finished {
    return _finished;
}

// The compositor moves the drag, and tells the source nothing of where it is.
- (BOOL) update {
    return NO;
}

- (void) sourceEvent: (uint32_t) opcode proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args {
    if (opcode == WP_DATA_SOURCE_EV_SEND) {
        if (proxy != _wlSource || _finished || _localOnly || args[0].s == NULL) {
            close(args[1].h);
            return;
        }
        NSString *mime = [NSString stringWithUTF8String: args[0].s];
        _CGSSelectionSendData(mime != nil ? [_snapshot objectForKey: mime] : nil, args[1].h);
        return;
    }
    if (proxy != _wlSource || _finished)
        return;
    if (opcode == WP_DATA_SOURCE_EV_ACTION) {
        _action = args[0].u;
    } else if (opcode == WP_DATA_SOURCE_EV_DROP_PERFORMED) {
        _dropped = YES;
        if (!monotonicSeconds(&_dropDeadline))
            [self cancel];
        else
            _dropDeadline += DropFinishGrace;
    } else if (opcode == WP_DATA_SOURCE_EV_CANCELLED) {
        [self cancel];
    } else if (opcode == WP_DATA_SOURCE_EV_FINISHED) {
        if (!_dropped || !isFinalAction(_action) || !(_action & _offeredActions))
            _action = 0;
        _finished = YES;
    }
}

- (CGSDragOperation) concludePumping: (void (^)(NSDate *until)) pump {
    // The compositor says how the drag ended: the UI layer calls this once it has seen the end, or the release.
    double started;
    if (!monotonicSeconds(&started))
        started = 0;
    while (!_finished && !_closed) {
        double now;
        if (!monotonicSeconds(&now))
            break;
        // Before the drop the compositor is only given a moment; once it dropped, the destination has until the
        // deadline to finish with the data.
        if (now >= (_dropped ? _dropDeadline : started + EndGrace)) {
            [self cancel];
            break;
        }
        pump([NSDate dateWithTimeIntervalSinceNow: 0.02]);
    }
    if (_finished && isFinalAction(_action) && (_action & _offeredActions) &&
        (!_localOnly || _completedLocalAction == _action))
        return operationsFromActions(_action);
    return kCGSDragOperationNone;
}

- (void) close {
    if (_closed)
        return;
    _closed = YES;
    [self cancel];
    if (_drag != nil && _drag->_outgoing == self)
        _drag->_outgoing = nil;
    [_icon invalidate];
    [_icon release];
    _icon = nil;
    if (_wlSource != NULL) {
        destroyProxy(_wlSource, WP_DATA_SOURCE_DESTROY);
        _wlSource = NULL;
        [_drag->_connection flush];
    }
    _localSession = nil;
}

@end

#pragma mark - The drag of the connection

@implementation CGSWaylandDrag

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection clipboard: (CGSWaylandClipboard *) clipboard {
    if ((self = [super init]) != nil) {
        _connection = connection;
        _clipboard = clipboard;
    }
    return self;
}

- (void) invalidate {
    [_outgoing close];
    [_incoming invalidate];
    [_incoming release];
    _incoming = nil;
    _clipboard = nil;
}

- (void) dealloc {
    [self invalidate];
    [super dealloc];
}

- (BOOL) available {
    return _clipboard != nil && [_clipboard dataDevice] != NULL;
}

- (id<CGSDragSession>) beginDragWithDescription: (const CGSDragDescription *) description {
    if (![self available] || _outgoing != nil || ![NSThread isMainThread])
        return nil;
    // The caller owns the session (see _CGSDragBegin()).
    return [[CGSWaylandDragSession alloc] initWithDrag: self description: description];
}

- (void) windowUnmapped: (uint32_t) windowID {
    if (_outgoing != nil && [_outgoing originWindow] == windowID)
        [_outgoing cancel];
}

- (void) deviceEnteredSurface: (struct wl_proxy *) surface
                       serial: (uint32_t) serial
                        offer: (struct wl_proxy *) offer
                        mimes: (NSArray *) mimes
                sourceActions: (uint32_t) actions
                      atPoint: (CGPoint) point {
    CGSWaylandDropSession *old = _incoming;
    [old willLeave];
    if (old != nil)
        [_connection performAfterDispatch: ^{
            [old leave];
        }];
    CGSWaylandDropSession *session = [[CGSWaylandDropSession alloc] initWithDrag: self
                                                                           offer: offer
                                                                           mimes: mimes
                                                                        windowID: [_connection windowIDForSurface: surface]
                                                                          serial: serial
                                                                   sourceActions: actions];
    _incoming = session;
    [old release];
    [_connection performAfterDispatch: ^{
        [session motion: point];
    }];
}

- (void) deviceMovedToPoint: (CGPoint) point {
    CGSWaylandDropSession *session = _incoming;
    // The session is kept for the callback, which can end the drag.
    [session retain];
    [_connection performAfterDispatch: ^{
        [session motion: point];
        [session release];
    }];
}

- (void) deviceDropped {
    CGSWaylandDropSession *session = _incoming;
    [session markDropped];
    [session retain];
    [_connection performAfterDispatch: ^{
        [session drop];
        [session release];
    }];
}

- (void) deviceLeft {
    CGSWaylandDropSession *session = _incoming;
    [session willLeave];
    [session retain];
    [_connection performAfterDispatch: ^{
        [session leave];
        [session release];
    }];
    // A drop's session stays until the drop is performed (it ends the session itself).
    if (session != nil && ![session isDropAnnounced]) {
        [_incoming release];
        _incoming = nil;
    }
}

- (BOOL) ownsOffer: (struct wl_proxy *) offer {
    return offer != NULL && [_incoming offer] == offer;
}

- (void) offer: (struct wl_proxy *) offer sourceActions: (uint32_t) actions {
    if ([self ownsOffer: offer])
        [_incoming sourceActions: actions];
}

- (void) offer: (struct wl_proxy *) offer action: (uint32_t) action {
    if ([self ownsOffer: offer])
        [_incoming selectedAction: action];
}

- (void) sourceEvent: (uint32_t) opcode proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args {
    if (_outgoing != nil)
        [_outgoing sourceEvent: opcode proxy: proxy arguments: args];
    else if (opcode == WP_DATA_SOURCE_EV_SEND)
        close(args[1].h);
}

@end

#pragma mark - What the connection offers the UI layer

@interface CGSConnection (CGSDragBackend)
- (BOOL) _dragAvailable;
- (BOOL) _dragUsesImage;
- (id<CGSDragSession>) _beginDrag: (const CGSDragDescription *) description;
@end

@implementation CGSConnectionWayland (CGSWaylandDrag)

- (BOOL) _dragAvailable {
    return [(CGSWaylandDrag *) _drag available];
}

- (BOOL) _dragUsesImage {
    return YES;
}

- (id<CGSDragSession>) _beginDrag: (const CGSDragDescription *) description {
    return [(CGSWaylandDrag *) _drag beginDragWithDescription: description];
}

- (struct wl_proxy *) dataDeviceManager {
    return _dataDeviceManager;
}

- (uint32_t) dragSerial {
    return [(CGSWaylandPointer *) _pointerDecoder dragSerial];
}

- (void) consumeDragSerial {
    [(CGSWaylandPointer *) _pointerDecoder consumeDragSerial];
}

@end
