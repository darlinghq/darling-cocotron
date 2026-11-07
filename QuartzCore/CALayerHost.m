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
// and draws the frames the context sends, at their size, from its own
// origin. When the context goes away, it draws nothing again. See CAContext.m
// for the other end and CARemoteContextProtocol.h for the messages.

#import <QuartzCore/CALayerHost.h>
#import <QuartzCore/CALayerContext.h>
#import <IOSurface/IOSurface.h>
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
}
- (instancetype) initWithHost: (CALayerHost *) host contextId: (CAContextID) contextId;
- (void) cancel;
// NO once the context has gone away.
- (BOOL) isConnected;
// The last frame, or NULL.
- (IOSurfaceRef) frame;
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

// Takes the send right in the message.
- (void) receiveSurfacePort: (mach_port_t) port {
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
        [self receiveSurfacePort: frame->surface.name];
        changed = YES;
    }

    if (changed)
        [self->_host _frameDidChange];
}

@end

@implementation CALayerHost

- (void) dealloc {
    [_connection cancel];
    [_connection release];
    [super dealloc];
}

- (CAContextID) contextId {
    return _contextId;
}

- (void) setContextId: (CAContextID) contextId {
    // Setting the ID again connects again only if the context has gone.
    if (contextId == _contextId && (contextId == 0 || [_connection isConnected]))
        return;
    _contextId = contextId;

    [_connection cancel];
    [_connection release];
    _connection = nil;

    // An ID that names no context (any more) is kept, and shows nothing.
    if (contextId != 0)
        _connection = [[CALayerHostConnection alloc] initWithHost: self
                                                        contextId: contextId];
    [self _frameDidChange];
}

- (void) _frameDidChange {
    [[self _context] startTimerIfNeeded];
}

- (id) _contentsForRendering: (CGRect *) rect {
    IOSurfaceRef frame = [_connection frame];
    if (frame == NULL)
        return [super _contentsForRendering: rect];
    // The hosted tree is drawn at its own size, from the host's origin.
    *rect = CGRectMake(0, 0, IOSurfaceGetWidth(frame), IOSurfaceGetHeight(frame));
    return (id) frame;
}

@end
