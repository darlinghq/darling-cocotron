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

// A remote CAContext renders its layer tree, off screen, into IOSurfaces and
// hands them to the CALayerHosts that show it:
//
// - The context's receive port is registered in the bootstrap namespace under
//   a name derived from a random contextId. Only a process that was told the
//   contextId can find it there, and the context serves only hosts of its own
//   user (or root).
// - A host subscribes with a send right to its own port. After each frame the
//   context sends every subscriber the Mach port of the surface it drew into
//   (two surfaces, used in turn), and the host draws that surface.
// - The port dies with the context's process or with -invalidate, so the
//   hosts get a dead-name notification and stop showing it, and the
//   bootstrap name goes away. A host that dies is dropped at the next send to
//   it.
//
// The protocol is in CARemoteContextProtocol.h. Contexts are used from the
// main thread, like the layer trees they draw.

#define GL_GLEXT_PROTOTYPES 1
#import <QuartzCore/CAContext.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CARenderer.h>
#import <IOSurface/IOSurface.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import "CALayerInternal.h"
#import "CARemoteContextProtocol.h"

#include <dispatch/dispatch.h>
#include <math.h>
#include <servers/bootstrap.h>
#include <stdlib.h>
#include <unistd.h>

NSString *const kCAContextCIFilterBehavior = @"CIFilterBehavior";
NSString *const kCAContextDisplayId = @"displayId";
NSString *const kCAContextDisplayName = @"displayName";
NSString *const kCAContextIgnoresHitTest = @"ignoresHitTest";
NSString *const kCAContextPortNumber = @"port_number";

// The most hosts one context serves at a time.
#define MAX_SUBSCRIBERS 32

@interface CAContext (Remote)
- (void) _publishFrame;
@end

// Draws a remote context's tree into an offscreen framebuffer and copies each
// frame into one of two IOSurfaces. It runs on CALayerContext's frame timer:
// the layers of the tree request frames from it as they change.
@interface CARemoteLayerContext : CALayerContext {
    CAContext *_owner;
    GLuint _framebuffer;
    GLuint _renderbuffer;
    GLint _framebufferWidth;
    GLint _framebufferHeight;
    IOSurfaceRef _surfaces[2];
    mach_port_t _surfacePorts[2];
    // The surface holding the last frame, or -1 when there is nothing to show.
    int _current;
}
- (instancetype) initWithOwner: (CAContext *) owner;
- (void) detach;
// A send right the caller does not own, or MACH_PORT_NULL.
- (mach_port_t) currentSurfacePort;
@end

@implementation CARemoteLayerContext

- (instancetype) initWithOwner: (CAContext *) owner {
    self = [super initWithFrame: CGRectZero];
    if (self == nil)
        return nil;
    _owner = owner;
    _current = -1;
    // Hosts composite the frames over their own layers.
    [_renderer _setClearsToTransparent: YES];
    return self;
}

- (void) releaseSurfaceAtIndex: (int) index {
    if (_surfaces[index] != NULL)
        CFRelease(_surfaces[index]);
    _surfaces[index] = NULL;
    if (_surfacePorts[index] != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), _surfacePorts[index]);
    _surfacePorts[index] = MACH_PORT_NULL;
    if (_current == index)
        _current = -1;
}

- (void) dealloc {
    CGLContextObj previous = CGLGetCurrentContext();
    if (_framebuffer != 0 && CGLSetCurrentContext(_glContext) == kCGLNoError) {
        glDeleteFramebuffers(1, &_framebuffer);
        glDeleteRenderbuffers(1, &_renderbuffer);
        CGLSetCurrentContext(previous != _glContext ? previous : NULL);
    }
    [self releaseSurfaceAtIndex: 0];
    [self releaseSurfaceAtIndex: 1];
    [super dealloc];
}

- (void) detach {
    _owner = nil;
    [self invalidate];
    [self setLayer: nil];
}

- (mach_port_t) currentSurfacePort {
    return _current >= 0 ? _surfacePorts[_current] : MACH_PORT_NULL;
}

// There is no window to show the tree in.
- (void) setSubwindow: (CGSubWindow *) subwindow {
}

- (BOOL) prepareFramebufferWidth: (GLint) width height: (GLint) height {
    if (_framebuffer == 0) {
        glGenFramebuffers(1, &_framebuffer);
        glGenRenderbuffers(1, &_renderbuffer);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    if (width != _framebufferWidth || height != _framebufferHeight) {
        glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                  GL_RENDERBUFFER, _renderbuffer);
        _framebufferWidth = width;
        _framebufferHeight = height;
    }
    return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

// A surface of the given size at index, with a Mach port to send.
- (IOSurfaceRef) surfaceAtIndex: (int) index
                          width: (GLint) width
                         height: (GLint) height
{
    IOSurfaceRef surface = _surfaces[index];
    if (surface != NULL && IOSurfaceGetWidth(surface) == (size_t) width &&
        IOSurfaceGetHeight(surface) == (size_t) height)
        return surface;

    [self releaseSurfaceAtIndex: index];

    NSDictionary *properties = @{
        (NSString *) kIOSurfaceWidth : @(width),
        (NSString *) kIOSurfaceHeight : @(height),
        (NSString *) kIOSurfaceBytesPerElement : @4,
        (NSString *) kIOSurfacePixelFormat : @((uint32_t) 'BGRA'),
    };
    surface = IOSurfaceCreate((CFDictionaryRef) properties);
    if (surface == NULL)
        return NULL;
    // A surface that cannot be shared is of no use to the hosts.
    mach_port_t port = IOSurfaceCreateMachPort(surface);
    if (port == MACH_PORT_NULL) {
        CFRelease(surface);
        return NULL;
    }
    _surfaces[index] = surface;
    _surfacePorts[index] = port;
    return surface;
}

- (void) render {
    CALayer *layer = _layer;
    CGSize size = layer != nil ? [layer bounds].size : CGSizeZero;
    GLint width = (GLint) ceil(size.width);
    GLint height = (GLint) ceil(size.height);

    if (layer == nil || width <= 0 || height <= 0 ||
        width > CA_REMOTE_MAX_FRAME_SIDE || height > CA_REMOTE_MAX_FRAME_SIDE) {
        _current = -1;
        return;
    }

    CGLContextObj previous = CGLGetCurrentContext();
    if (CGLSetCurrentContext(_glContext) != kCGLNoError)
        return;

    if ([self prepareFramebufferWidth: width height: height]) {
        [self _drawLayerTree: layer
                       width: width
                      height: height
                 topRowFirst: YES];

        // Hosts may still be reading the last frame: draw into the other
        // surface.
        int next = _current == 0 ? 1 : 0;
        IOSurfaceRef surface = [self surfaceAtIndex: next
                                              width: width
                                             height: height];
        if (surface != NULL &&
            IOSurfaceLock(surface, 0, NULL) == kIOReturnSuccess) {
            glPixelStorei(GL_PACK_ALIGNMENT, 4);
            glPixelStorei(GL_PACK_ROW_LENGTH,
                          (GLint) (IOSurfaceGetBytesPerRow(surface) / 4));
            glReadPixels(0, 0, width, height, GL_BGRA,
                         GL_UNSIGNED_INT_8_8_8_8_REV,
                         IOSurfaceGetBaseAddress(surface));
            glPixelStorei(GL_PACK_ROW_LENGTH, 0);
            // The unlock moves the seed on, so hosts upload the new pixels.
            IOSurfaceUnlock(surface, 0, NULL);
            _current = next;
        } else {
            _current = -1;
        }
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    CGLSetCurrentContext(previous != _glContext ? previous : NULL);
}

- (void) flush {
    [_owner _publishFrame];
}

@end

@implementation CAContext

static void handleContextMessages(void *context);

+ (instancetype) remoteContext {
    return [self remoteContextWithOptions: nil];
}

+ (instancetype) remoteContextWithOptions: (NSDictionary *) options {
    return [[[self alloc] _initRemoteWithOptions: options] autorelease];
}

+ (instancetype) contextWithCGSConnection: (CAContextID) connection
                                  options: (NSDictionary *) options
{
    return [self remoteContextWithOptions: options];
}

- (instancetype) _initRemoteWithOptions: (NSDictionary *) options {
    self = [super init];
    if (self == nil)
        return nil;

    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &_port) != KERN_SUCCESS) {
        _port = MACH_PORT_NULL;
        [self release];
        return nil;
    }
    mach_port_insert_right(mach_task_self(), _port, _port, MACH_MSG_TYPE_MAKE_SEND);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // The ID is the capability that lets a host find the context, so it is
    // random rather than a counter. Retry on the rare collision.
    // bootstrap_register, unlike bootstrap_check_in, leaves the receive right
    // with this process, so the name goes away when the port dies.
    for (int attempt = 0; attempt < 16 && !_registered; attempt++) {
        CAContextID contextId = arc4random();
        if (contextId == 0)
            continue;
        char name[128];
        CARemoteContextServiceName(contextId, name);
        if (bootstrap_register(bootstrap_port, name, _port) == BOOTSTRAP_SUCCESS) {
            _contextId = contextId;
            _registered = YES;
        }
    }
#pragma clang diagnostic pop
    // The registration holds its own send right.
    mach_port_deallocate(mach_task_self(), _port);

    if (!_registered) {
        NSLog(@"CAContext: cannot register a remote context");
        [self release];
        return nil;
    }

    _subscribers = calloc(MAX_SUBSCRIBERS, sizeof(mach_port_t));
    _renderContext = [[CARemoteLayerContext alloc] initWithOwner: self];
    if (_subscribers == NULL || _renderContext == nil) {
        [self release];
        return nil;
    }

    // Subscriptions are handled on the main queue, where the tree is drawn.
    dispatch_source_t source = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_MACH_RECV, _port, 0, dispatch_get_main_queue());
    if (source == NULL) {
        [self release];
        return nil;
    }
    dispatch_set_context(source, self);
    dispatch_source_set_event_handler_f(source, handleContextMessages);
    // The receive right goes away only once the source no longer uses it.
    mach_port_t port = _port;
    dispatch_source_set_cancel_handler(source, ^{
        mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
    });
    dispatch_resume(source);
    _source = source;

    return self;
}

- (void) _dropSubscribers {
    for (unsigned int i = 0; i < _subscriberCount; i++)
        mach_port_deallocate(mach_task_self(), _subscribers[i]);
    _subscriberCount = 0;
}

- (void) invalidate {
    // Destroying the port tells every host that the context is gone, and
    // removes the bootstrap name.
    if (_source != NULL) {
        dispatch_source_t source = _source;
        _source = NULL;
        dispatch_set_context(source, NULL);
        dispatch_source_cancel(source);
        dispatch_release(source);
    } else if (_port != MACH_PORT_NULL) {
        mach_port_mod_refs(mach_task_self(), _port, MACH_PORT_RIGHT_RECEIVE, -1);
    }
    _port = MACH_PORT_NULL;
    _registered = NO;

    [self _dropSubscribers];
    [_renderContext detach];
    [_renderContext release];
    _renderContext = nil;
    [_layer release];
    _layer = nil;
}

- (void) dealloc {
    [self invalidate];
    free(_subscribers);
    [super dealloc];
}

- (CAContextID) contextId {
    return _contextId;
}

- (CALayer *) layer {
    return _layer;
}

- (void) setLayer: (CALayer *) layer {
    layer = [layer retain];
    [_layer release];
    _layer = layer;
    [_renderContext setLayer: layer];
    // A new tree reaches the hosts with its first frame; no tree at once.
    if (layer == nil && _renderContext != nil) {
        [_renderContext render];
        [self _publishFrame];
    }
}

// Returns NO when the host has gone.
static BOOL sendFrame(mach_port_t destination, mach_port_t surfacePort) {
    CARemoteFrameMessage message = {0};
    message.header.msgh_bits =
            MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
    message.header.msgh_size = sizeof(message);
    message.header.msgh_remote_port = destination;
    message.header.msgh_id = kCARemoteFrameMessageID;
    message.body.msgh_descriptor_count = 1;
    message.surface.name = surfacePort;
    message.surface.disposition = MACH_MSG_TYPE_COPY_SEND;
    message.surface.type = MACH_MSG_PORT_DESCRIPTOR;
    message.version = CA_REMOTE_PROTOCOL_VERSION;

    // Never wait for a host: one whose queue is full has newer frames queued.
    mach_msg_return_t result = mach_msg(&message.header,
                                        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                                        sizeof(message), 0, MACH_PORT_NULL, 0,
                                        MACH_PORT_NULL);
    return result != MACH_SEND_INVALID_DEST;
}

- (void) _publishFrame {
    mach_port_t surfacePort = [_renderContext currentSurfacePort];
    unsigned int kept = 0;
    for (unsigned int i = 0; i < _subscriberCount; i++) {
        if (sendFrame(_subscribers[i], surfacePort))
            _subscribers[kept++] = _subscribers[i];
        else
            mach_port_deallocate(mach_task_self(), _subscribers[i]);
    }
    _subscriberCount = kept;
}

- (void) _addSubscriber: (mach_port_t) port {
    // Send rights to one port share a name in this task, so a repeated
    // subscription finds the earlier one.
    for (unsigned int i = 0; i < _subscriberCount; i++) {
        if (_subscribers[i] == port) {
            mach_port_deallocate(mach_task_self(), port);
            return;
        }
    }
    if (_subscriberCount == MAX_SUBSCRIBERS) {
        mach_port_deallocate(mach_task_self(), port);
        return;
    }

    mach_port_t surfacePort = [_renderContext currentSurfacePort];
    if (surfacePort == MACH_PORT_NULL) {
        // The first frame goes to every subscriber.
        _subscribers[_subscriberCount++] = port;
        if (_layer != nil)
            [_renderContext startTimerIfNeeded];
    } else if (sendFrame(port, surfacePort)) {
        _subscribers[_subscriberCount++] = port;
    } else {
        mach_port_deallocate(mach_task_self(), port);
    }
}

// Hosts of this user, and root, may subscribe. The second field of the
// sender's audit token is its effective user ID.
static BOOL senderMayHost(const mach_msg_header_t *header) {
    const mach_msg_audit_trailer_t *trailer =
            (const mach_msg_audit_trailer_t *) ((const uint8_t *) header +
                                                round_msg(header->msgh_size));
    if (trailer->msgh_trailer_size < sizeof(mach_msg_audit_trailer_t))
        return NO;
    uid_t uid = (uid_t) trailer->msgh_audit.val[1];
    return uid == geteuid() || uid == 0;
}

static void handleContextMessages(void *context) {
    CAContext *self = context;
    if (self == nil)
        return;

    for (;;) {
        CARemoteReceiveBuffer buffer;
        mach_msg_return_t result = mach_msg(&buffer.header, CA_REMOTE_RECEIVE_OPTIONS,
                                            0, sizeof(buffer), self->_port, 0,
                                            MACH_PORT_NULL);
        if (result != MACH_MSG_SUCCESS)
            return;

        mach_msg_header_t *header = &buffer.header;
        BOOL valid = header->msgh_id == kCARemoteSubscribeMessageID &&
                     !(header->msgh_bits & MACH_MSGH_BITS_COMPLEX) &&
                     header->msgh_size == sizeof(CARemoteSubscribeMessage) &&
                     buffer.subscribe.message.version == CA_REMOTE_PROTOCOL_VERSION &&
                     MACH_MSGH_BITS_REMOTE(header->msgh_bits) == MACH_MSG_TYPE_PORT_SEND &&
                     MACH_PORT_VALID(header->msgh_remote_port) &&
                     senderMayHost(header);
        if (!valid) {
            mach_msg_destroy(header);
            continue;
        }
        [self _addSubscriber: header->msgh_remote_port];
    }
}

@end
