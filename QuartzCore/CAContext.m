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

// Draws a remote context's tree into a framebuffer whose texture is bound to
// one of two IOSurfaces, which the hosts then show. It runs on CALayerContext's frame timer:
// the layers of the tree request frames from it as they change.
@interface CARemoteLayerContext : CALayerContext {
    CAContext *_owner;
    GLuint _framebuffer;
    // The texture bound to each surface, and the surface it is bound to.
    GLuint _textures[2];
    IOSurfaceRef _textureSurfaces[2];
    IOSurfaceRef _surfaces[2];
    mach_port_t _surfacePorts[2];
    // Where the frame in each surface lies.
    CARemoteFrameGeometry _geometries[2];
    // The surface holding the last frame, or -1 when there is nothing to show.
    int _current;
}
- (instancetype) initWithOwner: (CAContext *) owner;
- (void) detach;
// A send right the caller does not own, or MACH_PORT_NULL.
- (mach_port_t) currentSurfacePort;
// Where the frame in the current surface lies.
- (CARemoteFrameGeometry) currentGeometry;
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
    _textureSurfaces[index] = NULL;
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
        glDeleteTextures(2, _textures);
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

- (CARemoteFrameGeometry) currentGeometry {
    CARemoteFrameGeometry none = {0};
    return _current >= 0 ? _geometries[_current] : none;
}

// There is no window to show the tree in.
- (void) setSubwindow: (CGSubWindow *) subwindow {
}

// Makes the framebuffer draw into the texture that uses the surface's memory
// (the surface is the texture's storage, so nothing is read back or copied
// afterwards; where the driver cannot import the surface, OpenGL.c copies the
// texture into it when it is locked). Leaves the framebuffer bound.
- (BOOL) prepareFramebufferForSurface: (IOSurfaceRef) surface index: (int) index {
    if (_framebuffer == 0)
        glGenFramebuffers(1, &_framebuffer);
    if (_textures[index] == 0)
        glGenTextures(1, &_textures[index]);

    glBindTexture(GL_TEXTURE_2D, _textures[index]);
    if (_textureSurfaces[index] != surface) {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        if (CGLTexImageIOSurface2D(_glContext, GL_TEXTURE_2D, GL_RGBA8,
                                   (GLsizei) IOSurfaceGetWidth(surface),
                                   (GLsizei) IOSurfaceGetHeight(surface), GL_BGRA,
                                   GL_UNSIGNED_INT_8_8_8_8_REV, surface, 0) != kCGLNoError) {
            glBindTexture(GL_TEXTURE_2D, 0);
            return NO;
        }
        _textureSurfaces[index] = surface;
    }
    glBindTexture(GL_TEXTURE_2D, 0);

    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           _textures[index], 0);
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

// The pixels a frame covers: the tree's drawn extent, out to whole points,
// cut down to the largest frame a host accepts. A cut keeps the top-left,
// where the content starts in a tree laid out from the top.
static BOOL frameRectForExtent(CGRect extent, CGRect *frame) {
    if (CGRectIsNull(extent) || CGRectIsEmpty(extent))
        return NO;
    double minX = floor(CGRectGetMinX(extent));
    double minY = floor(CGRectGetMinY(extent));
    double maxX = ceil(CGRectGetMaxX(extent));
    double maxY = ceil(CGRectGetMaxY(extent));
    if (!isfinite(minX) || !isfinite(minY) || !isfinite(maxX) ||
        !isfinite(maxY))
        return NO;
    maxX = fmin(maxX, minX + CA_REMOTE_MAX_FRAME_SIDE);
    minY = fmax(minY, maxY - CA_REMOTE_MAX_FRAME_SIDE);
    // The origin goes into the frame message as 32-bit integers.
    if (minX < INT32_MIN || minY < INT32_MIN || minX > INT32_MAX ||
        minY > INT32_MAX)
        return NO;
    *frame = CGRectMake(minX, minY, maxX - minX, maxY - minY);
    return YES;
}

- (void) render {
    CALayer *layer = _layer;
    CGRect extent = CGRectNull, rootFrame = CGRectNull, frame;

    // The tree is not clipped to the root layer's bounds: Core Animation
    // clips only at layers that mask to their bounds, and a host shows all
    // of a tree, so the frame covers whatever the tree draws.
    if (layer != nil) {
        [layer layoutIfNeeded];
        extent = [_renderer _drawnExtentOfLayerTree: layer
                                          rootFrame: &rootFrame
                                             atTime: CACurrentMediaTime()];
    }

    if (!frameRectForExtent(extent, &frame)) {
        _current = -1;
        return;
    }
    GLint width = (GLint) frame.size.width;
    GLint height = (GLint) frame.size.height;

    CGLContextObj previous = CGLGetCurrentContext();
    if (CGLSetCurrentContext(_glContext) != kCGLNoError)
        return;

    // Hosts may still be reading the last frame: draw into the other surface.
    int next = _current == 0 ? 1 : 0;
    IOSurfaceRef surface = [self surfaceAtIndex: next
                                          width: width
                                         height: height];
    if (surface != NULL && [self prepareFramebufferForSurface: surface index: next]) {
        [self _drawLayerTree: layer
                      inRect: frame
                 topRowFirst: YES];

        // The lock waits for the drawing to finish (and has OpenGL.c copy
        // the texture into the surface where it only holds a copy of it);
        // the unlock moves the seed on, so hosts bind the new pixels.
        if (IOSurfaceLock(surface, 0, NULL) == kIOReturnSuccess) {
            IOSurfaceUnlock(surface, 0, NULL);
            _geometries[next] = (CARemoteFrameGeometry) {
                .originX = (int32_t) frame.origin.x,
                .originY = (int32_t) frame.origin.y,
                .rootMinY = (float) CGRectGetMinY(rootFrame),
                .rootMaxY = (float) CGRectGetMaxY(rootFrame),
            };
            _current = next;
        } else {
            _current = -1;
        }
    } else {
        _current = -1;
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

// SPI. Whether contexts may use the window server (CGS) connection; YES until set. Processes
// without window server access (WebKit's web content process) turn it off before creating remote
// contexts. Observed on macOS 26.7.3: the value reads back as set, and
// +remoteContextWithOptions: still makes a context after it is set to NO. Darling's remote
// contexts never use a CGS connection, so nothing else depends on it.
// Test: tests/quartzcore-cacontext-allows-cgs-connections.m.
static BOOL allowsCGSConnections = YES;

+ (BOOL) allowsCGSConnections {
    return allowsCGSConnections;
}

+ (void) setAllowsCGSConnections: (BOOL) allows {
    allowsCGSConnections = allows;
}

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

    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &NS_EXTRA(CAContext, self)->_port) != KERN_SUCCESS) {
        NS_EXTRA(CAContext, self)->_port = MACH_PORT_NULL;
        [self release];
        return nil;
    }
    mach_port_insert_right(mach_task_self(), NS_EXTRA(CAContext, self)->_port, NS_EXTRA(CAContext, self)->_port, MACH_MSG_TYPE_MAKE_SEND);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // The ID is the capability that lets a host find the context, so it is
    // random rather than a counter. Retry on the rare collision.
    // bootstrap_register, unlike bootstrap_check_in, leaves the receive right
    // with this process, so the name goes away when the port dies.
    for (int attempt = 0; attempt < 16 && !NS_EXTRA(CAContext, self)->_registered; attempt++) {
        CAContextID contextId = arc4random();
        if (contextId == 0)
            continue;
        char name[128];
        CARemoteContextServiceName(contextId, name);
        if (bootstrap_register(bootstrap_port, name, NS_EXTRA(CAContext, self)->_port) == BOOTSTRAP_SUCCESS) {
            NS_EXTRA(CAContext, self)->_contextId = contextId;
            NS_EXTRA(CAContext, self)->_registered = YES;
        }
    }
#pragma clang diagnostic pop
    // The registration holds its own send right.
    mach_port_deallocate(mach_task_self(), NS_EXTRA(CAContext, self)->_port);

    if (!NS_EXTRA(CAContext, self)->_registered) {
        NSLog(@"CAContext: cannot register a remote context");
        [self release];
        return nil;
    }

    NS_EXTRA(CAContext, self)->_subscribers = calloc(MAX_SUBSCRIBERS, sizeof(mach_port_t));
    NS_EXTRA(CAContext, self)->_renderContext = [[CARemoteLayerContext alloc] initWithOwner: self];
    if (NS_EXTRA(CAContext, self)->_subscribers == NULL || NS_EXTRA(CAContext, self)->_renderContext == nil) {
        [self release];
        return nil;
    }

    // Subscriptions are handled on the main queue, where the tree is drawn.
    dispatch_source_t source = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_MACH_RECV, NS_EXTRA(CAContext, self)->_port, 0, dispatch_get_main_queue());
    if (source == NULL) {
        [self release];
        return nil;
    }
    dispatch_set_context(source, self);
    dispatch_source_set_event_handler_f(source, handleContextMessages);
    // The receive right goes away only once the source no longer uses it.
    mach_port_t port = NS_EXTRA(CAContext, self)->_port;
    dispatch_source_set_cancel_handler(source, ^{
        mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
    });
    dispatch_resume(source);
    NS_EXTRA(CAContext, self)->_source = source;

    return self;
}

- (void) _dropSubscribers {
    for (unsigned int i = 0; i < NS_EXTRA(CAContext, self)->_subscriberCount; i++)
        mach_port_deallocate(mach_task_self(), NS_EXTRA(CAContext, self)->_subscribers[i]);
    NS_EXTRA(CAContext, self)->_subscriberCount = 0;
}

- (void) invalidate {
    // Destroying the port tells every host that the context is gone, and
    // removes the bootstrap name.
    if (NS_EXTRA(CAContext, self)->_source != NULL) {
        dispatch_source_t source = NS_EXTRA(CAContext, self)->_source;
        NS_EXTRA(CAContext, self)->_source = NULL;
        dispatch_set_context(source, NULL);
        dispatch_source_cancel(source);
        dispatch_release(source);
    } else if (NS_EXTRA(CAContext, self)->_port != MACH_PORT_NULL) {
        mach_port_mod_refs(mach_task_self(), NS_EXTRA(CAContext, self)->_port, MACH_PORT_RIGHT_RECEIVE, -1);
    }
    NS_EXTRA(CAContext, self)->_port = MACH_PORT_NULL;
    NS_EXTRA(CAContext, self)->_registered = NO;

    [self _dropSubscribers];
    [NS_EXTRA(CAContext, self)->_renderContext detach];
    [NS_EXTRA(CAContext, self)->_renderContext release];
    NS_EXTRA(CAContext, self)->_renderContext = nil;
    [NS_EXTRA(CAContext, self)->_layer release];
    NS_EXTRA(CAContext, self)->_layer = nil;
}

- (void) dealloc {
    [self invalidate];
    free(NS_EXTRA(CAContext, self)->_subscribers);
    [super dealloc];
}

- (CAContextID) contextId {
    return NS_EXTRA(CAContext, self)->_contextId;
}

- (CALayer *) layer {
    return NS_EXTRA(CAContext, self)->_layer;
}

- (void) setLayer: (CALayer *) layer {
    layer = [layer retain];
    [NS_EXTRA(CAContext, self)->_layer release];
    NS_EXTRA(CAContext, self)->_layer = layer;
    [NS_EXTRA(CAContext, self)->_renderContext setLayer: layer];
    // A new tree reaches the hosts with its first frame; no tree at once.
    if (layer == nil && NS_EXTRA(CAContext, self)->_renderContext != nil) {
        [NS_EXTRA(CAContext, self)->_renderContext render];
        [self _publishFrame];
    }
}

// Returns NO when the host has gone.
static BOOL sendFrame(mach_port_t destination, mach_port_t surfacePort,
                      CARemoteFrameGeometry geometry) {
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
    message.geometry = geometry;

    // Never wait for a host: one whose queue is full has newer frames queued.
    mach_msg_return_t result = mach_msg(&message.header,
                                        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                                        sizeof(message), 0, MACH_PORT_NULL, 0,
                                        MACH_PORT_NULL);
    return result != MACH_SEND_INVALID_DEST;
}

- (void) _publishFrame {
    mach_port_t surfacePort = [NS_EXTRA(CAContext, self)->_renderContext currentSurfacePort];
    CARemoteFrameGeometry geometry = [NS_EXTRA(CAContext, self)->_renderContext currentGeometry];
    unsigned int kept = 0;
    for (unsigned int i = 0; i < NS_EXTRA(CAContext, self)->_subscriberCount; i++) {
        if (sendFrame(NS_EXTRA(CAContext, self)->_subscribers[i], surfacePort, geometry))
            NS_EXTRA(CAContext, self)->_subscribers[kept++] = NS_EXTRA(CAContext, self)->_subscribers[i];
        else
            mach_port_deallocate(mach_task_self(), NS_EXTRA(CAContext, self)->_subscribers[i]);
    }
    NS_EXTRA(CAContext, self)->_subscriberCount = kept;
}

- (void) _addSubscriber: (mach_port_t) port {
    // Send rights to one port share a name in this task, so a repeated
    // subscription finds the earlier one.
    for (unsigned int i = 0; i < NS_EXTRA(CAContext, self)->_subscriberCount; i++) {
        if (NS_EXTRA(CAContext, self)->_subscribers[i] == port) {
            mach_port_deallocate(mach_task_self(), port);
            return;
        }
    }
    if (NS_EXTRA(CAContext, self)->_subscriberCount == MAX_SUBSCRIBERS) {
        mach_port_deallocate(mach_task_self(), port);
        return;
    }

    mach_port_t surfacePort = [NS_EXTRA(CAContext, self)->_renderContext currentSurfacePort];
    if (surfacePort == MACH_PORT_NULL) {
        // The first frame goes to every subscriber.
        NS_EXTRA(CAContext, self)->_subscribers[NS_EXTRA(CAContext, self)->_subscriberCount++] = port;
        if (NS_EXTRA(CAContext, self)->_layer != nil)
            [NS_EXTRA(CAContext, self)->_renderContext startTimerIfNeeded];
    } else if (sendFrame(port, surfacePort,
                         [NS_EXTRA(CAContext, self)->_renderContext currentGeometry])) {
        NS_EXTRA(CAContext, self)->_subscribers[NS_EXTRA(CAContext, self)->_subscriberCount++] = port;
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
                                            0, sizeof(buffer), NS_EXTRA(CAContext, self)->_port, 0,
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
