/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

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

#import <CoreGraphics/CGDisplayStream.h>
#import <Foundation/NSObject.h>

const CFStringRef kCGDisplayStreamShowCursor = CFSTR("kCGDisplayStreamShowCursor");
const CFStringRef kCGDisplayStreamSourceRect = CFSTR("kCGDisplayStreamSourceRect");
const CFStringRef kCGDisplayStreamDestinationRect = CFSTR("kCGDisplayStreamDestinationRect");
const CFStringRef kCGDisplayStreamPreserveAspectRatio = CFSTR("kCGDisplayStreamPreserveAspectRatio");
const CFStringRef kCGDisplayStreamColorSpace = CFSTR("kCGDisplayStreamColorSpace");
const CFStringRef kCGDisplayStreamMinimumFrameTime = CFSTR("kCGDisplayStreamMinimumFrameTime");
const CFStringRef kCGDisplayStreamQueueDepth = CFSTR("kCGDisplayStreamQueueDepth");

// There is no screen capture backend, so a stream never delivers a frame.
// It can be started and stopped, and stopping it reports
// kCGDisplayStreamFrameStatusStopped to the handler on the stream's queue
// or run loop source, as a capturing stream would.
@interface CGDisplayStream : NSObject {
    CGDisplayStreamFrameAvailableHandler _handler;
    dispatch_queue_t _queue;
    CFRunLoopSourceRef _runLoopSource;
    BOOL _running;
    BOOL _stopPending;
}
- initWithHandler: (CGDisplayStreamFrameAvailableHandler) handler
            queue: (dispatch_queue_t) queue;
- (CFRunLoopSourceRef) runLoopSource;
- (CGError) start;
- (CGError) stop;
- (void) deliverStop;
@end

@interface CGDisplayStreamUpdate : NSObject
@end

static void performStreamSource(void *info) {
    [(CGDisplayStream *) info deliverStop];
}

@implementation CGDisplayStream

- initWithHandler: (CGDisplayStreamFrameAvailableHandler) handler
            queue: (dispatch_queue_t) queue
{
    self = [super init];
    if (self == nil)
        return nil;
    _handler = [handler copy];
    if (queue != NULL) {
        dispatch_retain(queue);
        _queue = queue;
    }
    return self;
}

- (void) dealloc {
    if (_runLoopSource != NULL) {
        CFRunLoopSourceInvalidate(_runLoopSource);
        CFRelease(_runLoopSource);
    }
    if (_queue != NULL)
        dispatch_release(_queue);
    [_handler release];
    [super dealloc];
}

- (CFTypeID) _cfTypeID {
    return CGDisplayStreamGetTypeID();
}

- (CFRunLoopSourceRef) runLoopSource {
    if (_queue != NULL)
        return NULL;
    if (_runLoopSource == NULL) {
        // The source does not retain the stream; the stream owns the source.
        CFRunLoopSourceContext context = { 0 };
        context.info = self;
        context.perform = performStreamSource;
        _runLoopSource = CFRunLoopSourceCreate(NULL, 0, &context);
    }
    return _runLoopSource;
}

- (CGError) start {
    _running = YES;
    return kCGErrorSuccess;
}

- (CGError) stop {
    if (!_running)
        return kCGErrorSuccess;
    _running = NO;

    if (_queue != NULL) {
        CGDisplayStreamFrameAvailableHandler handler = [_handler retain];
        dispatch_async(_queue, ^{
            handler(kCGDisplayStreamFrameStatusStopped, 0, NULL, NULL);
            [handler release];
        });
    } else if (_runLoopSource != NULL) {
        _stopPending = YES;
        CFRunLoopSourceSignal(_runLoopSource);
        // The source is usually scheduled on the main or the calling
        // thread's run loop.
        CFRunLoopWakeUp(CFRunLoopGetMain());
        CFRunLoopWakeUp(CFRunLoopGetCurrent());
    }
    return kCGErrorSuccess;
}

- (void) deliverStop {
    if (!_stopPending)
        return;
    _stopPending = NO;
    _handler(kCGDisplayStreamFrameStatusStopped, 0, NULL, NULL);
}

@end

@implementation CGDisplayStreamUpdate

- (CFTypeID) _cfTypeID {
    return CGDisplayStreamUpdateGetTypeID();
}

@end

CFTypeID CGDisplayStreamGetTypeID(void) {
    return (CFTypeID) [CGDisplayStream self];
}

CFTypeID CGDisplayStreamUpdateGetTypeID(void) {
    return (CFTypeID) [CGDisplayStreamUpdate self];
}

static CGDisplayStreamRef createStream(size_t outputWidth, size_t outputHeight,
                                       dispatch_queue_t queue,
                                       CGDisplayStreamFrameAvailableHandler handler)
{
    if (handler == NULL || outputWidth == 0 || outputHeight == 0)
        return NULL;
    return (CGDisplayStreamRef) [[CGDisplayStream alloc] initWithHandler: handler
                                                                   queue: queue];
}

CGDisplayStreamRef CGDisplayStreamCreate(CGDirectDisplayID display, size_t outputWidth,
                                         size_t outputHeight, int32_t pixelFormat,
                                         CFDictionaryRef properties,
                                         CGDisplayStreamFrameAvailableHandler handler)
{
    return createStream(outputWidth, outputHeight, NULL, handler);
}

CGDisplayStreamRef CGDisplayStreamCreateWithDispatchQueue(
    CGDirectDisplayID display, size_t outputWidth, size_t outputHeight,
    int32_t pixelFormat, CFDictionaryRef properties, dispatch_queue_t queue,
    CGDisplayStreamFrameAvailableHandler handler)
{
    if (queue == NULL)
        return NULL;
    return createStream(outputWidth, outputHeight, queue, handler);
}

CFRunLoopSourceRef CGDisplayStreamGetRunLoopSource(CGDisplayStreamRef displayStream) {
    return [(CGDisplayStream *) displayStream runLoopSource];
}

CGError CGDisplayStreamStart(CGDisplayStreamRef displayStream) {
    if (displayStream == NULL)
        return kCGErrorIllegalArgument;
    return [(CGDisplayStream *) displayStream start];
}

CGError CGDisplayStreamStop(CGDisplayStreamRef displayStream) {
    if (displayStream == NULL)
        return kCGErrorIllegalArgument;
    return [(CGDisplayStream *) displayStream stop];
}

// No updates are ever delivered; these accept the updates a caller could
// still have (NULL) and report them as empty.
const CGRect *CGDisplayStreamUpdateGetRects(CGDisplayStreamUpdateRef updateRef,
                                            CGDisplayStreamUpdateRectType rectType,
                                            size_t *rectCount)
{
    if (rectCount != NULL)
        *rectCount = 0;
    return NULL;
}

CGDisplayStreamUpdateRef CGDisplayStreamUpdateCreateMergedUpdate(
    CGDisplayStreamUpdateRef firstUpdate, CGDisplayStreamUpdateRef secondUpdate)
{
    if (firstUpdate == NULL && secondUpdate == NULL)
        return NULL;
    return (CGDisplayStreamUpdateRef) [[CGDisplayStreamUpdate alloc] init];
}

void CGDisplayStreamUpdateGetMovedRectsDelta(CGDisplayStreamUpdateRef updateRef,
                                             CGFloat *dx, CGFloat *dy)
{
    if (dx != NULL)
        *dx = 0;
    if (dy != NULL)
        *dy = 0;
}

size_t CGDisplayStreamUpdateGetDropCount(CGDisplayStreamUpdateRef updateRef) {
    return 0;
}
