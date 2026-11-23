/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers
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

// A CALayerHost subscribes to the remote CAContext named by its contextId
// and draws the frames the context sends, at their size, where the hosted
// tree would be as a sublayer of the host. When the context goes away, it
// draws nothing again. See CAContext.m
// for the other end and CARemoteContextProtocol.h for the messages.

#import <QuartzCore/CALayerHost.h>
#import <QuartzCore/CALayerContext.h>
#import <IOSurface/IOSurface.h>
#import <OpenGL/gl.h>
#import "CALayerInternal.h"
#import "CARemoteContextProtocol.h"

#include <dispatch/dispatch.h>
#include <stddef.h>
#include <mach/notify.h>
#include <servers/bootstrap.h>

// How long a host waits to queue its subscription with a context.
#define SUBSCRIBE_TIMEOUT_MS 1000

@interface CALayerHost (Connection)
- (void) _frameDidChange;
@end

// One subscription to one context. It lives as long as its dispatch source.
@interface CALayerHostConnection : NSObject {
    CALayerHost *_host;
    mach_port_t _contextPort;
    mach_port_t _port;
    dispatch_source_t _source;
    // The surfaces the context draws into in turn, as received.
    IOSurfaceRef _surfaces[2];
    mach_port_t _surfacePorts[2];
    IOSurfaceRef _frame;
    CARemoteFrameGeometry _geometry;
}
- (instancetype) initWithHost: (CALayerHost *) host contextId: (CAContextID) contextId;
- (void) cancel;
// NO once the context has gone away.
- (BOOL) isConnected;
// The last frame, or NULL.
- (IOSurfaceRef) frame;
// Which of the two surfaces the frame is in.
- (int) frameSlot;
// Where the last frame lies in the context's coordinate space.
- (CARemoteFrameGeometry) geometry;
@end

@implementation CALayerHostConnection

static void handleHostMessages(void *context);

- (instancetype) initWithHost: (CALayerHost *) host contextId: (CAContextID) contextId {
    self = [super init];
    if (self == nil)
        return nil;
    _host = host;

    char name[128];
    CARemoteContextServiceName(contextId, name);
    if (bootstrap_look_up(bootstrap_port, name, &_contextPort) != BOOTSTRAP_SUCCESS) {
        _contextPort = MACH_PORT_NULL;
        [self release];
        return nil;
    }

    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &_port) != KERN_SUCCESS) {
        _port = MACH_PORT_NULL;
        [self release];
        return nil;
    }
    // Frames arrive as fast as the context draws; all but the last are
    // skipped when the host is behind.
    mach_port_limits_t limits = {.mpl_qlimit = MACH_PORT_QLIMIT_LARGE};
    mach_port_set_attributes(mach_task_self(), _port, MACH_PORT_LIMITS_INFO,
                             (mach_port_info_t) &limits, MACH_PORT_LIMITS_INFO_COUNT);

    // Learn when the context goes away.
    mach_port_t previous = MACH_PORT_NULL;
    if (mach_port_request_notification(mach_task_self(), _contextPort,
                                       MACH_NOTIFY_DEAD_NAME, 0, _port,
                                       MACH_MSG_TYPE_MAKE_SEND_ONCE,
                                       &previous) != KERN_SUCCESS) {
        [self release];
        return nil;
    }
    if (previous != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), previous);

    CARemoteSubscribeMessage message = {0};
    message.header.msgh_bits =
            MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND);
    message.header.msgh_size = sizeof(message);
    message.header.msgh_remote_port = _contextPort;
    message.header.msgh_local_port = _port;
    message.header.msgh_id = kCARemoteSubscribeMessageID;
    message.version = CA_REMOTE_PROTOCOL_VERSION;
    if (mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                 sizeof(message), 0, MACH_PORT_NULL, SUBSCRIBE_TIMEOUT_MS,
                 MACH_PORT_NULL) != MACH_MSG_SUCCESS) {
        [self release];
        return nil;
    }

    // Frames are handled on the main queue, where the host's tree is drawn.
    _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, _port, 0,
                                     dispatch_get_main_queue());
    if (_source == NULL) {
        [self release];
        return nil;
    }
    dispatch_set_context(_source, self);
    dispatch_source_set_event_handler_f(_source, handleHostMessages);
    // The block keeps the connection, and with it the receive right, alive
    // until the source is done with them.
    dispatch_source_set_cancel_handler(_source, ^{
        [self releaseResources];
    });
    dispatch_resume(_source);
    return self;
}

- (void) releaseSurfaces {
    for (int i = 0; i < 2; i++) {
        if (_surfaces[i] != NULL)
            CFRelease(_surfaces[i]);
        _surfaces[i] = NULL;
        if (_surfacePorts[i] != MACH_PORT_NULL)
            mach_port_deallocate(mach_task_self(), _surfacePorts[i]);
        _surfacePorts[i] = MACH_PORT_NULL;
    }
    _frame = NULL;
}

- (void) releaseResources {
    [self releaseSurfaces];
    if (_contextPort != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), _contextPort);
    _contextPort = MACH_PORT_NULL;
    if (_port != MACH_PORT_NULL)
        mach_port_mod_refs(mach_task_self(), _port, MACH_PORT_RIGHT_RECEIVE, -1);
    _port = MACH_PORT_NULL;
}

- (void) dealloc {
    // Without a source (initialization failed), nothing else releases them.
    if (_source == NULL)
        [self releaseResources];
    else
        dispatch_release(_source);
    [super dealloc];
}

- (void) cancel {
    _host = nil;
    if (_source != NULL)
        dispatch_source_cancel(_source);
}

- (BOOL) isConnected {
    return _contextPort != MACH_PORT_NULL;
}

- (IOSurfaceRef) frame {
    return _frame;
}

- (CARemoteFrameGeometry) geometry {
    return _geometry;
}

- (int) frameSlot {
    return _frame != NULL && _frame == _surfaces[1] ? 1 : 0;
}

// Takes the send right in the message.
- (void) receiveSurfacePort: (mach_port_t) port
                   geometry: (CARemoteFrameGeometry) geometry
{
    if (!MACH_PORT_VALID(port)) {
        _frame = NULL;
        return;
    }
    // A right to a port this task already holds has the same name, so the
    // surfaces in turn are each looked up once.
    for (int i = 0; i < 2; i++) {
        if (_surfacePorts[i] == port) {
            mach_port_deallocate(mach_task_self(), port);
            _frame = _surfaces[i];
            _geometry = geometry;
            return;
        }
    }

    IOSurfaceRef surface = IOSurfaceLookupFromMachPort(port);
    if (surface == NULL || IOSurfaceGetPixelFormat(surface) != 'BGRA' ||
        IOSurfaceGetWidth(surface) > CA_REMOTE_MAX_FRAME_SIDE ||
        IOSurfaceGetHeight(surface) > CA_REMOTE_MAX_FRAME_SIDE) {
        if (surface != NULL)
            CFRelease(surface);
        mach_port_deallocate(mach_task_self(), port);
        return;
    }

    // Replace the surface that is not on screen.
    int slot = _surfaces[0] == _frame ? 1 : 0;
    if (_surfaces[slot] != NULL)
        CFRelease(_surfaces[slot]);
    if (_surfacePorts[slot] != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), _surfacePorts[slot]);
    _surfaces[slot] = surface;
    _surfacePorts[slot] = port;
    _frame = surface;
    _geometry = geometry;
}

- (void) contextDidGoAway {
    [self releaseSurfaces];
    if (_contextPort != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), _contextPort);
    _contextPort = MACH_PORT_NULL;
}

static void handleHostMessages(void *context) {
    CALayerHostConnection *self = context;
    BOOL changed = NO;

    for (;;) {
        CARemoteReceiveBuffer buffer;
        mach_msg_return_t result = mach_msg(&buffer.header, CA_REMOTE_RECEIVE_OPTIONS,
                                            0, sizeof(buffer), self->_port, 0,
                                            MACH_PORT_NULL);
        if (result != MACH_MSG_SUCCESS)
            break;

        mach_msg_header_t *header = &buffer.header;
        if (header->msgh_id == MACH_NOTIFY_DEAD_NAME &&
            // The SDK's notification struct includes the receive trailer.
            header->msgh_size >= offsetof(mach_dead_name_notification_t, trailer) &&
            !(header->msgh_bits & MACH_MSGH_BITS_COMPLEX)) {
            mach_port_t name = buffer.deadName.not_port;
            if (name != MACH_PORT_NULL && name == self->_contextPort) {
                // The notification carries a reference of its own.
                mach_port_deallocate(mach_task_self(), name);
                [self contextDidGoAway];
                changed = YES;
            }
            continue;
        }

        const CARemoteFrameMessage *frame = &buffer.frame.message;
        BOOL valid = header->msgh_id == kCARemoteFrameMessageID &&
                     (header->msgh_bits & MACH_MSGH_BITS_COMPLEX) &&
                     header->msgh_size == sizeof(CARemoteFrameMessage) &&
                     frame->body.msgh_descriptor_count == 1 &&
                     frame->surface.type == MACH_MSG_PORT_DESCRIPTOR &&
                     (frame->surface.name == MACH_PORT_NULL ||
                      frame->surface.disposition == MACH_MSG_TYPE_PORT_SEND) &&
                     frame->version == CA_REMOTE_PROTOCOL_VERSION &&
                     self->_contextPort != MACH_PORT_NULL;
        if (!valid) {
            mach_msg_destroy(header);
            continue;
        }
        [self receiveSurfacePort: frame->surface.name
                        geometry: frame->geometry];
        changed = YES;
    }

    if (changed)
        [self->_host _frameDidChange];
}

@end

@implementation CALayerHost

- (void) dealloc {
    [[self _context] deleteTextureId: NS_EXTRA(CALayerHost, self)->_otherTextureId];
    [NS_EXTRA(CALayerHost, self)->_otherTextureId release];
    [NS_EXTRA(CALayerHost, self)->_otherTextureContents release];
    [NS_EXTRA(CALayerHost, self)->_connection cancel];
    [NS_EXTRA(CALayerHost, self)->_connection release];
    [super dealloc];
}

- (CAContextID) contextId {
    return NS_EXTRA(CALayerHost, self)->_contextId;
}

- (void) setContextId: (CAContextID) contextId {
    // Setting the ID again connects again only if the context has gone.
    if (contextId == NS_EXTRA(CALayerHost, self)->_contextId && (contextId == 0 || [NS_EXTRA(CALayerHost, self)->_connection isConnected]))
        return;
    NS_EXTRA(CALayerHost, self)->_contextId = contextId;

    [NS_EXTRA(CALayerHost, self)->_connection cancel];
    [NS_EXTRA(CALayerHost, self)->_connection release];
    NS_EXTRA(CALayerHost, self)->_connection = nil;

    // An ID that names no context (any more) is kept, and shows nothing.
    if (contextId != 0)
        NS_EXTRA(CALayerHost, self)->_connection = [[CALayerHostConnection alloc] initWithHost: self
                                                        contextId: contextId];
    [self _frameDidChange];
}

// Whether the layer, or one above it, is hidden or fully transparent, so
// that a new frame changes nothing that is drawn.
- (BOOL) _isInvisible {
    for (CALayer *layer = self; layer != nil; layer = [layer superlayer])
        if ([layer isHidden] || [layer opacity] <= 0)
            return YES;
    return NO;
}

// Showing the layer again (hidden, opacity) asks for a frame, which then
// draws the latest one.
- (void) _frameDidChange {
    if ([self _isInvisible])
        return;
    [[self _context] startTimerIfNeeded];
}

// The renderer keeps one texture per layer and binds a new surface to it when
// the contents change. The frames alternate between two surfaces, so the
// texture would be bound to the other surface at every frame; instead each
// surface keeps a texture, and the layer's texture state is swapped to the
// surface's when the frame moves to the other one. Called while the layer is
// being drawn, with the rendering context current.
- (void) _selectTextureForSlot: (int) slot {
    if (slot == NS_EXTRA(CALayerHost, self)->_activeSlot)
        return;
    NS_EXTRA(CALayerHost, self)->_activeSlot = slot;

    NSNumber *textureId = [[self _textureId] retain];
    id contents = [[self _textureContents] retain];
    uint32_t seed = [self _textureSeed];

    [self _setTextureId: NS_EXTRA(CALayerHost, self)->_otherTextureId];
    [self _setTextureContents: NS_EXTRA(CALayerHost, self)->_otherTextureContents];
    [self _setTextureSeed: NS_EXTRA(CALayerHost, self)->_otherTextureSeed];

    [NS_EXTRA(CALayerHost, self)->_otherTextureId release];
    [NS_EXTRA(CALayerHost, self)->_otherTextureContents release];
    NS_EXTRA(CALayerHost, self)->_otherTextureId = textureId;
    NS_EXTRA(CALayerHost, self)->_otherTextureContents = contents;
    NS_EXTRA(CALayerHost, self)->_otherTextureSeed = seed;

    if ([self _textureId] == nil) {
        GLuint texture;
        glGenTextures(1, &texture);
        [self _setTextureId: [NSNumber numberWithUnsignedInt: texture]];
    }
}

- (void) _setContext: (CALayerContext *) context {
    if ([self _context] != context) {
        [[self _context] deleteTextureId: NS_EXTRA(CALayerHost, self)->_otherTextureId];
        [NS_EXTRA(CALayerHost, self)->_otherTextureId release];
        NS_EXTRA(CALayerHost, self)->_otherTextureId = nil;
    }
    [super _setContext: context];
}

- (id) _contentsForRendering: (CGRect *) rect {
    IOSurfaceRef frame = [NS_EXTRA(CALayerHost, self)->_connection frame];
    if (frame == NULL)
        return [super _contentsForRendering: rect];
    [self _selectTextureForSlot: [NS_EXTRA(CALayerHost, self)->_connection frameSlot]];
    CARemoteFrameGeometry geometry = [NS_EXTRA(CALayerHost, self)->_connection geometry];
    CGFloat width = IOSurfaceGetWidth(frame);
    CGFloat height = IOSurfaceGetHeight(frame);
    CGFloat y = geometry.originY;
    // The hosted root layer is placed in this layer's coordinates as a
    // sublayer would be, but the hosted tree keeps the orientation it has in
    // its own context: the host's flipped state does not reach into it. In
    // flipped coordinates, the root's frame is mirrored into place and the
    // picture around it stays upright.
    if ([self contentsAreFlipped])
        y = (CGFloat) geometry.rootMinY + (CGFloat) geometry.rootMaxY -
            (geometry.originY + height);
    // Sublayers are positioned relative to the bounds origin; *rect is
    // relative to the bounds' corner.
    CGRect bounds = [self bounds];
    *rect = CGRectMake(geometry.originX - bounds.origin.x, y - bounds.origin.y,
                       width, height);
    return (id) frame;
}

@end
