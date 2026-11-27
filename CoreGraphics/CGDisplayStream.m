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
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
#include <screen_capture_backend.h>
#endif

const CFStringRef kCGDisplayStreamShowCursor = CFSTR("kCGDisplayStreamShowCursor");
const CFStringRef kCGDisplayStreamSourceRect = CFSTR("kCGDisplayStreamSourceRect");
const CFStringRef kCGDisplayStreamDestinationRect = CFSTR("kCGDisplayStreamDestinationRect");
const CFStringRef kCGDisplayStreamPreserveAspectRatio = CFSTR("kCGDisplayStreamPreserveAspectRatio");
const CFStringRef kCGDisplayStreamColorSpace = CFSTR("kCGDisplayStreamColorSpace");
const CFStringRef kCGDisplayStreamMinimumFrameTime = CFSTR("kCGDisplayStreamMinimumFrameTime");
const CFStringRef kCGDisplayStreamQueueDepth = CFSTR("kCGDisplayStreamQueueDepth");
const CFStringRef kCGDisplayStreamYCbCrMatrix = CFSTR("kCGDisplayStreamYCbCrMatrix");
const CFStringRef kCGDisplayStreamYCbCrMatrix_ITU_R_601_4 = CFSTR("ITU_R_601_4");
const CFStringRef kCGDisplayStreamYCbCrMatrix_ITU_R_709_2 = CFSTR("ITU_R_709_2");

enum {
    kDarlingPixelFormatARGB = 0x00000020,
    kDarlingPixelFormatBGRA = 'BGRA',
    kDarlingPixelFormatABGR = 'ABGR',
    kDarlingPixelFormatRGBA = 'RGBA',
};

@interface CGDisplayStreamUpdate : NSObject {
@public
    CGRect _rect;
    size_t _count;
    size_t _dropCount;
}
- initWithRect: (CGRect) rect dropCount: (size_t) dropCount;
@end

@interface DarlingDisplayFrame : NSObject {
@public
    IOSurfaceRef surface;
    CGDisplayStreamUpdate *update;
    uint64_t displayTime;
}
@end

@interface CGDisplayStream : NSObject {
@public
    CGDisplayStreamFrameAvailableHandler _handler;
    dispatch_queue_t _queue;
    CFRunLoopSourceRef _runLoopSource;
    NSMutableArray *_pending;
    CGDirectDisplayID _display;
    size_t _outputWidth;
    size_t _outputHeight;
    int32_t _pixelFormat;
    CGRect _sourceRect;
    CGRect _destinationRect;
    BOOL _hasSourceRect;
    BOOL _hasDestinationRect;
    BOOL _preserveAspectRatio;
    BOOL _showCursor;
    BOOL _running;
    BOOL _stopPending;
    BOOL _stopDelivered;
    size_t _queueDepth;
    size_t _inFlight;
    size_t _pendingDrops;
    uint64_t _minimumFrameIntervalNs;
    uint64_t _lastFrameTimeNs;
    uint64_t _lastDisplayTime;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    struct darling_screen_capture_stream *_capture;
    IOSurfaceRef *_surfaces;
    uint8_t **_surfaceBases;
    uint32_t *_surfaceStrides;
    size_t _surfaceCount;
    size_t _nextSurface;
#endif
}
- initWithDisplay: (CGDirectDisplayID) display width: (size_t) width height: (size_t) height pixelFormat: (int32_t) pixelFormat properties: (CFDictionaryRef) properties handler: (CGDisplayStreamFrameAvailableHandler) handler queue: (dispatch_queue_t) queue;
- (CFRunLoopSourceRef) runLoopSource;
- (CGError) start;
- (void) stopFromBackend;
- (CGError) stop;
- (void) deliverStop;
- (void) deliverPendingFrame;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
- (void) receiveFrame: (const struct darling_screen_capture_frame *) frame;
#endif
@end

@implementation DarlingDisplayFrame
- (void) dealloc {
    if (surface != NULL) {
        IOSurfaceDecrementUseCount(surface);
        CFRelease(surface);
    }
    [update release];
    [super dealloc];
}
@end

static void performStreamSource(void *info) {
    CGDisplayStream *stream = (CGDisplayStream *) info;
    if (stream->_stopPending)
        [stream deliverStop];
    else
        [stream deliverPendingFrame];
}

static BOOL propertyBool(CFDictionaryRef properties, CFStringRef key, BOOL fallback) {
    CFBooleanRef value;
    if (properties == NULL)
        return fallback;
    value = (CFBooleanRef) CFDictionaryGetValue(properties, key);
    if (value == NULL || CFGetTypeID(value) != CFBooleanGetTypeID())
        return fallback;
    return CFBooleanGetValue(value) ? YES : NO;
}

static double propertyNumber(CFDictionaryRef properties, CFStringRef key, double fallback) {
    CFNumberRef value;
    double result = fallback;
    if (properties == NULL)
        return fallback;
    value = (CFNumberRef) CFDictionaryGetValue(properties, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID())
        return fallback;
    if (!CFNumberGetValue(value, kCFNumberDoubleType, &result))
        return fallback;
    return result;
}

static CGRect propertyRect(CFDictionaryRef properties, CFStringRef key, BOOL *hasValue) {
    CFTypeRef value;
    CGRect result = CGRectZero;
    *hasValue = NO;
    if (properties == NULL)
        return result;
    value = CFDictionaryGetValue(properties, key);
    if (value == NULL)
        return result;
    if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
        CFDictionaryRef dictionary = (CFDictionaryRef) value;
        CFNumberRef number;
        CGFloat x = 0, y = 0, width = 0, height = 0;
        CFDictionaryRef origin = (CFDictionaryRef) CFDictionaryGetValue(dictionary, CFSTR("origin"));
        CFDictionaryRef size = (CFDictionaryRef) CFDictionaryGetValue(dictionary, CFSTR("size"));
        number = (CFNumberRef) CFDictionaryGetValue(dictionary, CFSTR("X"));
        if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &x)) *hasValue = YES;
        number = (CFNumberRef) CFDictionaryGetValue(dictionary, CFSTR("Y"));
        if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &y)) *hasValue = YES;
        number = (CFNumberRef) CFDictionaryGetValue(dictionary, CFSTR("Width"));
        if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &width)) *hasValue = YES;
        number = (CFNumberRef) CFDictionaryGetValue(dictionary, CFSTR("Height"));
        if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &height)) *hasValue = YES;
        if (origin != NULL && CFGetTypeID(origin) == CFDictionaryGetTypeID()) {
            number = (CFNumberRef) CFDictionaryGetValue(origin, CFSTR("X"));
            if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &x)) *hasValue = YES;
            number = (CFNumberRef) CFDictionaryGetValue(origin, CFSTR("Y"));
            if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &y)) *hasValue = YES;
        }
        if (size != NULL && CFGetTypeID(size) == CFDictionaryGetTypeID()) {
            number = (CFNumberRef) CFDictionaryGetValue(size, CFSTR("Width"));
            if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &width)) *hasValue = YES;
            number = (CFNumberRef) CFDictionaryGetValue(size, CFSTR("Height"));
            if (number != NULL && CFNumberGetValue(number, kCFNumberCGFloatType, &height)) *hasValue = YES;
        }
        result = CGRectMake(x, y, width, height);
    } else if ([(id) value isKindOfClass: [NSValue class]]) {
        result = [(NSValue *) value rectValue];
        *hasValue = YES;
    }
    return result;
}

#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
static uint32_t ioSurfacePixelFormat(int32_t format) {
    switch (format) {
        case kDarlingPixelFormatBGRA:
        case kDarlingPixelFormatARGB:
        case kDarlingPixelFormatABGR:
        case kDarlingPixelFormatRGBA:
            return (uint32_t) format;
        default:
            return 0;
    }
}
static void swizzleBGRA(uint8_t *row, uint32_t width, uint32_t format) {
    uint32_t x;
    for (x = 0; x < width; x++) {
        uint8_t *p = row + x * 4;
        uint8_t blue = p[0], green = p[1], red = p[2], alpha = p[3];
        switch (format) {
            case kDarlingPixelFormatRGBA: p[0]=red; p[1]=green; p[2]=blue; p[3]=alpha; break;
            case kDarlingPixelFormatARGB: p[0]=alpha; p[1]=red; p[2]=green; p[3]=blue; break;
            case kDarlingPixelFormatABGR: p[0]=alpha; p[1]=blue; p[2]=green; p[3]=red; break;
            default: break;
        }
    }
}
static CGRect fittedRect(CGRect source, CGRect destination, BOOL preserveAspectRatio) {
    CGFloat scaleX, scaleY, scale, width, height;
    if (!preserveAspectRatio || CGRectIsEmpty(source) || CGRectIsEmpty(destination))
        return destination;
    scaleX = destination.size.width / source.size.width;
    scaleY = destination.size.height / source.size.height;
    scale = scaleX < scaleY ? scaleX : scaleY;
    width = source.size.width * scale;
    height = source.size.height * scale;
    return CGRectMake(destination.origin.x + (destination.size.width - width) / 2,
                      destination.origin.y + (destination.size.height - height) / 2,
                      width, height);
}
static void receivePipeWireFrame(const struct darling_screen_capture_frame *frame, void *userData) {
    [(CGDisplayStream *) userData receiveFrame: frame];
}
static void receivePipeWireError(int error, void *userData) {
    (void) error;
    /* The backend ended the stream: it is reported like a stop, with the Stopped status. */
    [(CGDisplayStream *) userData stopFromBackend];
}
static IOSurfaceRef createSurface(size_t width, size_t height, uint32_t pixelFormat, uint8_t **baseOut, uint32_t *strideOut) {
    CFMutableDictionaryRef properties;
    CFNumberRef number;
    IOSurfaceRef surface;
    int64_t dimension;
    int32_t format;
    size_t stride, size;
    properties = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (properties == NULL) return NULL;
    stride = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * 4);
    size = IOSurfaceAlignProperty(kIOSurfaceAllocSize, stride * height);
    dimension = (int64_t) width; number = CFNumberCreate(NULL, kCFNumberSInt64Type, &dimension); CFDictionarySetValue(properties, kIOSurfaceWidth, number); CFRelease(number);
    dimension = (int64_t) height; number = CFNumberCreate(NULL, kCFNumberSInt64Type, &dimension); CFDictionarySetValue(properties, kIOSurfaceHeight, number); CFRelease(number);
    dimension = (int64_t) stride; number = CFNumberCreate(NULL, kCFNumberSInt64Type, &dimension); CFDictionarySetValue(properties, kIOSurfaceBytesPerRow, number); CFRelease(number);
    dimension = (int64_t) size; number = CFNumberCreate(NULL, kCFNumberSInt64Type, &dimension); CFDictionarySetValue(properties, kIOSurfaceAllocSize, number); CFRelease(number);
    format = (int32_t) pixelFormat; number = CFNumberCreate(NULL, kCFNumberSInt32Type, &format); CFDictionarySetValue(properties, kIOSurfacePixelFormat, number); CFRelease(number);
    surface = IOSurfaceCreate(properties);
    CFRelease(properties);
    if (surface == NULL) return NULL;
    IOSurfaceLock(surface, 0, NULL);
    memset(IOSurfaceGetBaseAddress(surface), 0, IOSurfaceGetAllocSize(surface));
    IOSurfaceUnlock(surface, 0, NULL);
    *baseOut = (uint8_t *) IOSurfaceGetBaseAddress(surface);
    *strideOut = (uint32_t) IOSurfaceGetBytesPerRow(surface);
    return surface;
}
#endif

@implementation CGDisplayStreamUpdate
- initWithRect: (CGRect) rect dropCount: (size_t) dropCount {
    self = [super init];
    if (self != nil) { _rect = rect; _count = CGRectIsEmpty(rect) ? 0 : 1; _dropCount = dropCount; }
    return self;
}
- (CFTypeID) _cfTypeID { return CGDisplayStreamUpdateGetTypeID(); }
@end

@implementation CGDisplayStream
- initWithDisplay: (CGDirectDisplayID) display width: (size_t) width height: (size_t) height pixelFormat: (int32_t) pixelFormat properties: (CFDictionaryRef) properties handler: (CGDisplayStreamFrameAvailableHandler) handler queue: (dispatch_queue_t) queue
{
    self = [super init];
    if (self == nil) return nil;
    _handler = [handler copy];
    if (queue != NULL) { dispatch_retain(queue); _queue = queue; }
    _pending = [[NSMutableArray alloc] init];
    _display = display; _outputWidth = width; _outputHeight = height; _pixelFormat = pixelFormat;
    {
        double depth = propertyNumber(properties, kCGDisplayStreamQueueDepth, 3);
        double interval = propertyNumber(properties, kCGDisplayStreamMinimumFrameTime, 0);
        /* Apple WWDC 2012 session 506 documents a default depth of 3 and
         * recommends no more than 8 queued frames. */
        if (depth < 1)
            depth = 3;
        if (depth > 8)
            depth = 8;
        _queueDepth = (size_t) depth;
        _minimumFrameIntervalNs = (interval > 0 && interval < 3600) ? (uint64_t) (interval * 1000000000.0) : 0;
    }
    _showCursor = propertyBool(properties, kCGDisplayStreamShowCursor, NO);
    _preserveAspectRatio = propertyBool(properties, kCGDisplayStreamPreserveAspectRatio, NO);
    _sourceRect = propertyRect(properties, kCGDisplayStreamSourceRect, &_hasSourceRect);
    _destinationRect = propertyRect(properties, kCGDisplayStreamDestinationRect, &_hasDestinationRect);
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    {
        size_t i, count = _queueDepth;
        _surfaces = calloc(count, sizeof(IOSurfaceRef));
        _surfaceBases = calloc(count, sizeof(uint8_t *));
        _surfaceStrides = calloc(count, sizeof(uint32_t));
        if (_surfaces != NULL && _surfaceBases != NULL && _surfaceStrides != NULL) {
            for (i = 0; i < count; i++) {
                _surfaces[i] = createSurface(width, height, ioSurfacePixelFormat(pixelFormat),
                                             &_surfaceBases[i], &_surfaceStrides[i]);
                if (_surfaces[i] == NULL)
                    break;
            }
            _surfaceCount = i;
            if (i != count) {
                for (i = 0; i < _surfaceCount; i++)
                    CFRelease(_surfaces[i]);
                _surfaceCount = 0;
            }
        }
        if (_surfaceCount == 0) {
            free(_surfaces); free(_surfaceBases); free(_surfaceStrides);
            _surfaces = NULL; _surfaceBases = NULL; _surfaceStrides = NULL;
        }
    }
#endif
    return self;
}
- (void) dealloc {
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (_capture != NULL) darling_screen_capture_close(_capture);
    {
        size_t i;
        for (i = 0; i < _surfaceCount; i++)
            CFRelease(_surfaces[i]);
        free(_surfaces); free(_surfaceBases); free(_surfaceStrides);
    }
#endif
    if (_runLoopSource != NULL) { CFRunLoopSourceInvalidate(_runLoopSource); CFRelease(_runLoopSource); }
    if (_queue != NULL) dispatch_release(_queue);
    [_pending release];
    [_handler release];
    [super dealloc];
}
- (CFTypeID) _cfTypeID { return CGDisplayStreamGetTypeID(); }
- (CFRunLoopSourceRef) runLoopSource {
    if (_queue != NULL) return NULL;
    if (_runLoopSource == NULL) {
        CFRunLoopSourceContext context = { 0 };
        context.info = self;
        context.perform = performStreamSource;
        _runLoopSource = CFRunLoopSourceCreate(NULL, 0, &context);
    }
    return _runLoopSource;
}
- (CGError) start {
    if (_running) return kCGErrorSuccess;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (_surfaceCount == 0) return kCGErrorFailure;
    {
        CGRect bounds = CGDisplayBounds(_display);
        struct darling_screen_capture_callbacks callbacks;
        int result;
        if (CGRectIsEmpty(bounds)) return kCGErrorIllegalArgument;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.frame = receivePipeWireFrame;
        callbacks.error = receivePipeWireError;
        result = darling_screen_capture_open((int32_t) bounds.origin.x, (int32_t) bounds.origin.y, (uint32_t) bounds.size.width, (uint32_t) bounds.size.height, _showCursor, darling_screen_capture_supports_hdr() ? 1 : 0, &callbacks, self, &_capture);
        if (result != 0) return kCGErrorFailure;
        result = darling_screen_capture_start(_capture, 1);
        if (result != 0) { darling_screen_capture_close(_capture); _capture = NULL; return kCGErrorFailure; }
        result = darling_screen_capture_wait(_capture, 5000);
        if (result != 0) { darling_screen_capture_close(_capture); _capture = NULL; return kCGErrorFailure; }
    }
#else
    /* Without a capture backend no frame can ever be delivered. */
    return kCGErrorFailure;
#endif
    @synchronized (self) {
        _running = YES;
        _stopPending = NO;
        _stopDelivered = NO;
        _inFlight = 0;
        _pendingDrops = 0;
        _lastFrameTimeNs = 0;
        _lastDisplayTime = 0;
    }
    CFRetain(self);
    return kCGErrorSuccess;
}
- (CGError) stop {
    BOOL deliver = NO;
    @synchronized (self) {
        if (!_running) return kCGErrorSuccess;
        _running = NO;
        if (!_stopDelivered) {
            _stopDelivered = YES;
            _stopPending = YES;
            deliver = YES;
        }
    }
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (_capture != NULL) { darling_screen_capture_start(_capture, 0); darling_screen_capture_close(_capture); _capture = NULL; }
#endif
    @synchronized (_pending) { [_pending removeAllObjects]; }
    if (!deliver) return kCGErrorSuccess;
    if (_queue != NULL) {
        CGDisplayStreamFrameAvailableHandler handler = [_handler retain];
        dispatch_async(_queue, ^{
            handler(kCGDisplayStreamFrameStatusStopped, 0, NULL, NULL);
            [handler release];
            CFRelease(self);
        });
    } else if (_runLoopSource != NULL) {
        CFRunLoopSourceSignal(_runLoopSource);
        CFRunLoopWakeUp(CFRunLoopGetMain());
        CFRunLoopWakeUp(CFRunLoopGetCurrent());
    } else {
        _handler(kCGDisplayStreamFrameStatusStopped, 0, NULL, NULL);
        CFRelease(self);
    }
    return kCGErrorSuccess;
}
- (void) stopFromBackend {
    /* Called on the capture thread, which stop() would have to join. */
    [self retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self stop];
        [self release];
    });
}
- (void) deliverStop {
    BOOL deliver = NO;
    @synchronized (self) {
        if (_stopPending) { _stopPending = NO; deliver = YES; }
    }
    if (!deliver) return;
    _handler(kCGDisplayStreamFrameStatusStopped, 0, NULL, NULL);
    CFRelease(self);
}
- (void) deliverPendingFrame {
    DarlingDisplayFrame *frame = nil;
    @synchronized (_pending) {
        if (!_stopPending && [_pending count] > 0) {
            frame = [[_pending objectAtIndex: 0] retain];
            [_pending removeObjectAtIndex: 0];
        }
    }
    if (frame == nil) return;
    @synchronized (self) { if (_inFlight > 0) _inFlight--; }
    _handler(kCGDisplayStreamFrameStatusFrameComplete, frame->displayTime, frame->surface, (CGDisplayStreamUpdateRef) frame->update);
    [frame release];
}
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
- (void) receiveFrame: (const struct darling_screen_capture_frame *) frame {
    CGRect bounds = CGDisplayBounds(_display);
    CGRect source = _hasSourceRect ? CGRectIntersection(_sourceRect, bounds) : bounds;
    CGRect destination = _hasDestinationRect ? _destinationRect : CGRectMake(0, 0, _outputWidth, _outputHeight);
    CGRect fullSurface = CGRectMake(0, 0, _outputWidth, _outputHeight);
    CGDisplayStreamUpdate *update;
    IOSurfaceRef surface = NULL;
    uint8_t *base;
    uint32_t stride;
    struct timespec arrival;
    uint64_t pts, nowNs;
    clock_gettime(CLOCK_MONOTONIC, &arrival);
    nowNs = (uint64_t) arrival.tv_sec * 1000000000ull + (uint64_t) arrival.tv_nsec;
    /* The display time is the compositor's buffer timestamp when it advances, otherwise the
     * arrival time (a stream may repeat one timestamp for every buffer). */
    pts = frame->pts_ns > 0 ? (uint64_t) frame->pts_ns : nowNs;
    size_t slot = 0, i, drops = 0;
    uint32_t dx, dy, dw, dh;
    int32_t sx, sy;
    if (CGRectIsNull(source) || CGRectIsEmpty(source)) return;
    destination = CGRectIntersection(fittedRect(source, destination, _preserveAspectRatio), fullSurface);
    if (CGRectIsNull(destination) || CGRectIsEmpty(destination)) return;
    @synchronized (self) {
        if (!_running) return;
        if (pts <= _lastDisplayTime)
            pts = nowNs > _lastDisplayTime ? nowNs : _lastDisplayTime + 1;
        /* The minimum frame time is wall-clock time between deliveries. */
        if (_minimumFrameIntervalNs > 0 && _lastFrameTimeNs != 0 &&
            nowNs < _lastFrameTimeNs + _minimumFrameIntervalNs)
            return;
        _lastFrameTimeNs = nowNs;
        _lastDisplayTime = pts;
        if (_inFlight >= _queueDepth) { _pendingDrops++; return; }
        for (i = 0; i < _surfaceCount; i++) {
            size_t candidate = (_nextSurface + i) % _surfaceCount;
            if (IOSurfaceGetUseCount(_surfaces[candidate]) == 0) {
                surface = _surfaces[candidate];
                slot = candidate;
                _nextSurface = (candidate + 1) % _surfaceCount;
                break;
            }
        }
        if (surface == NULL) { _pendingDrops++; return; }
        /* Reserve the surface for this delivery. Clients that keep working
         * with it increment the count themselves, so a nonzero count tells
         * the pool not to overwrite it yet. */
        IOSurfaceIncrementUseCount(surface);
        _inFlight++;
        drops = _pendingDrops;
        _pendingDrops = 0;
    }
    base = _surfaceBases[slot];
    stride = _surfaceStrides[slot];
    sx = (int32_t) (source.origin.x - bounds.origin.x);
    sy = (int32_t) (source.origin.y - bounds.origin.y);
    dx = (uint32_t) destination.origin.x; dy = (uint32_t) destination.origin.y;
    dw = (uint32_t) destination.size.width; dh = (uint32_t) destination.size.height;
    IOSurfaceLock(surface, 0, NULL);
    if (darling_screen_capture_convert_bgra_rect(frame, base, stride, (uint32_t) _outputWidth, (uint32_t) _outputHeight, sx, sy, (uint32_t) source.size.width, (uint32_t) source.size.height, dx, dy, dw, dh) == 0) {
        uint32_t y;
        for (y = 0; y < dh; y++) swizzleBGRA(base + (dy + y) * stride + dx * 4, dw, _pixelFormat);
    }
    IOSurfaceUnlock(surface, 0, NULL);
    update = [[CGDisplayStreamUpdate alloc] initWithRect: destination dropCount: drops];
    if (_queue != NULL) {
        CGDisplayStreamFrameAvailableHandler handler = [_handler retain];
        CFRetain(surface); [update retain];
        dispatch_async(_queue, ^{
            @synchronized (self) { if (_inFlight > 0) _inFlight--; }
            handler(kCGDisplayStreamFrameStatusFrameComplete, pts, surface, (CGDisplayStreamUpdateRef) update);
            IOSurfaceDecrementUseCount(surface);
            CFRelease(surface); [update release]; [handler release];
        });
        [update release];
    } else {
        CFRunLoopSourceRef sourceRef = [self runLoopSource];
        DarlingDisplayFrame *item = [[DarlingDisplayFrame alloc] init];
        item->surface = (IOSurfaceRef) CFRetain(surface);
        item->update = update;
        item->displayTime = pts;
        @synchronized (_pending) { [_pending addObject: item]; }
        [item release];
        if (sourceRef != NULL) { CFRunLoopSourceSignal(sourceRef); CFRunLoopWakeUp(CFRunLoopGetMain()); CFRunLoopWakeUp(CFRunLoopGetCurrent()); }
    }
}
#endif
@end

CFTypeID CGDisplayStreamGetTypeID(void) { return (CFTypeID) [CGDisplayStream self]; }
CFTypeID CGDisplayStreamUpdateGetTypeID(void) { return (CFTypeID) [CGDisplayStreamUpdate self]; }

static CGDisplayStreamRef createStream(CGDirectDisplayID display, size_t outputWidth, size_t outputHeight, int32_t pixelFormat, CFDictionaryRef properties, CGDisplayStreamFrameAvailableHandler handler, dispatch_queue_t queue) {
    if (handler == NULL || outputWidth == 0 || outputHeight == 0) return NULL;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (ioSurfacePixelFormat(pixelFormat) == 0) return NULL;
#endif
    return (CGDisplayStreamRef) [[CGDisplayStream alloc] initWithDisplay: display width: outputWidth height: outputHeight pixelFormat: pixelFormat properties: properties handler: handler queue: queue];
}
CGDisplayStreamRef CGDisplayStreamCreate(CGDirectDisplayID display, size_t outputWidth, size_t outputHeight, int32_t pixelFormat, CFDictionaryRef properties, CGDisplayStreamFrameAvailableHandler handler) {
    return createStream(display, outputWidth, outputHeight, pixelFormat, properties, handler, NULL);
}
CGDisplayStreamRef CGDisplayStreamCreateWithDispatchQueue(CGDirectDisplayID display, size_t outputWidth, size_t outputHeight, int32_t pixelFormat, CFDictionaryRef properties, dispatch_queue_t queue, CGDisplayStreamFrameAvailableHandler handler) {
    if (queue == NULL) return NULL;
    return createStream(display, outputWidth, outputHeight, pixelFormat, properties, handler, queue);
}
CFRunLoopSourceRef CGDisplayStreamGetRunLoopSource(CGDisplayStreamRef displayStream) { return [(CGDisplayStream *) displayStream runLoopSource]; }
CGError CGDisplayStreamStart(CGDisplayStreamRef displayStream) { if (displayStream == NULL) return kCGErrorIllegalArgument; return [(CGDisplayStream *) displayStream start]; }
CGError CGDisplayStreamStop(CGDisplayStreamRef displayStream) { if (displayStream == NULL) return kCGErrorIllegalArgument; return [(CGDisplayStream *) displayStream stop]; }
const CGRect *CGDisplayStreamUpdateGetRects(CGDisplayStreamUpdateRef updateRef, CGDisplayStreamUpdateRectType rectType, size_t *rectCount) {
    CGDisplayStreamUpdate *update = (CGDisplayStreamUpdate *) updateRef;
    if (rectType < kCGDisplayStreamUpdateRefreshedRects ||
        rectType > kCGDisplayStreamUpdateReducedDirtyRects) {
        if (rectCount != NULL) *rectCount = 0; return NULL;
    }
    if (rectCount != NULL) *rectCount = update != nil ? update->_count : 0;
    return update != nil ? &update->_rect : NULL;
}
CGDisplayStreamUpdateRef CGDisplayStreamUpdateCreateMergedUpdate(CGDisplayStreamUpdateRef firstUpdate, CGDisplayStreamUpdateRef secondUpdate) {
    CGDisplayStreamUpdate *first = (CGDisplayStreamUpdate *) firstUpdate;
    CGDisplayStreamUpdate *second = (CGDisplayStreamUpdate *) secondUpdate;
    CGRect rect; size_t drops;
    if (first == nil && second == nil) return NULL;
    if (first == nil) return (CGDisplayStreamUpdateRef) [[CGDisplayStreamUpdate alloc] initWithRect: second->_rect dropCount: second->_dropCount];
    if (second == nil) return (CGDisplayStreamUpdateRef) [[CGDisplayStreamUpdate alloc] initWithRect: first->_rect dropCount: first->_dropCount];
    rect = CGRectUnion(first->_rect, second->_rect); drops = first->_dropCount + second->_dropCount;
    return (CGDisplayStreamUpdateRef) [[CGDisplayStreamUpdate alloc] initWithRect: rect dropCount: drops];
}
void CGDisplayStreamUpdateGetMovedRectsDelta(CGDisplayStreamUpdateRef updateRef, CGFloat *dx, CGFloat *dy) { (void) updateRef; if (dx) *dx = 0; if (dy) *dy = 0; }
size_t CGDisplayStreamUpdateGetDropCount(CGDisplayStreamUpdateRef updateRef) { CGDisplayStreamUpdate *update = (CGDisplayStreamUpdate *) updateRef; return update != nil ? update->_dropCount : 0; }
