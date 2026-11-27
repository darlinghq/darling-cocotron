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
    double _minimumFrameTime;
    NSUInteger _queueDepth;
    NSUInteger _queuedFrames;
    uint64_t _lastFrameTimeNs;
    size_t _pendingDrops;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    struct darling_screen_capture_stream *_capture;
    IOSurfaceRef _surface;
    uint8_t *_surfaceBase;
    uint32_t _surfaceStride;
#endif
}
- initWithDisplay: (CGDirectDisplayID) display width: (size_t) width height: (size_t) height pixelFormat: (int32_t) pixelFormat properties: (CFDictionaryRef) properties handler: (CGDisplayStreamFrameAvailableHandler) handler queue: (dispatch_queue_t) queue;
- (CFRunLoopSourceRef) runLoopSource;
- (CGError) start;
- (CGError) stop;
- (void) deliverStop;
- (void) deliverPendingFrame;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
- (void) receiveFrame: (const struct darling_screen_capture_frame *) frame;
#endif
@end

@implementation DarlingDisplayFrame
- (void) dealloc {
    if (surface != NULL)
        CFRelease(surface);
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

static double propertyDouble(CFDictionaryRef properties, CFStringRef key) {
    CFNumberRef value;
    double result = 0;
    if (properties == NULL)
        return 0;
    value = (CFNumberRef) CFDictionaryGetValue(properties, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID())
        return 0;
    if (!CFNumberGetValue(value, kCFNumberDoubleType, &result))
        return 0;
    return result > 0 ? result : 0;
}

static NSInteger propertyInteger(CFDictionaryRef properties, CFStringRef key) {
    CFNumberRef value;
    int64_t result = 0;
    if (properties == NULL)
        return 0;
    value = (CFNumberRef) CFDictionaryGetValue(properties, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID())
        return 0;
    if (!CFNumberGetValue(value, kCFNumberSInt64Type, &result))
        return 0;
    return (NSInteger) result;
}

static uint64_t monotonicTimeNs(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0;
    return (uint64_t) ts.tv_sec * 1000000000ULL + (uint64_t) ts.tv_nsec;
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
    _showCursor = propertyBool(properties, kCGDisplayStreamShowCursor, NO);
    _preserveAspectRatio = propertyBool(properties, kCGDisplayStreamPreserveAspectRatio, NO);
    _sourceRect = propertyRect(properties, kCGDisplayStreamSourceRect, &_hasSourceRect);
    _destinationRect = propertyRect(properties, kCGDisplayStreamDestinationRect, &_hasDestinationRect);
    _minimumFrameTime = propertyDouble(properties, kCGDisplayStreamMinimumFrameTime);
    {
        NSInteger depth = propertyInteger(properties, kCGDisplayStreamQueueDepth);
        _queueDepth = depth > 0 ? (NSUInteger) depth : 0;
    }
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    _surface = createSurface(width, height, ioSurfacePixelFormat(pixelFormat), &_surfaceBase, &_surfaceStride);
#endif
    return self;
}
- (void) dealloc {
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (_capture != NULL) darling_screen_capture_close(_capture);
    if (_surface != NULL) CFRelease(_surface);
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
    _lastFrameTimeNs = 0;
    _pendingDrops = 0;
    _queuedFrames = 0;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (_surface == NULL) return kCGErrorFailure;
    {
        CGRect bounds = CGDisplayBounds(_display);
        struct darling_screen_capture_callbacks callbacks;
        int result;
        if (CGRectIsEmpty(bounds)) return kCGErrorIllegalArgument;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.frame = receivePipeWireFrame;
        result = darling_screen_capture_open((int32_t) bounds.origin.x, (int32_t) bounds.origin.y, (uint32_t) bounds.size.width, (uint32_t) bounds.size.height, _showCursor, darling_screen_capture_supports_hdr() ? 1 : 0, &callbacks, self, &_capture);
        if (result != 0) return kCGErrorFailure;
        result = darling_screen_capture_start(_capture, 1);
        if (result != 0) { darling_screen_capture_close(_capture); _capture = NULL; return kCGErrorFailure; }
        result = darling_screen_capture_wait(_capture, 5000);
        if (result != 0) { darling_screen_capture_close(_capture); _capture = NULL; return kCGErrorFailure; }
    }
#endif
    _running = YES;
    CFRetain(self);
    return kCGErrorSuccess;
}
- (CGError) stop {
    if (!_running) return kCGErrorSuccess;
    _running = NO;
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (_capture != NULL) { darling_screen_capture_start(_capture, 0); darling_screen_capture_close(_capture); _capture = NULL; }
#endif
    if (_queue != NULL) {
        CGDisplayStreamFrameAvailableHandler handler = [_handler retain];
        dispatch_async(_queue, ^{ handler(kCGDisplayStreamFrameStatusStopped, 0, NULL, NULL); [handler release]; });
    } else if (_runLoopSource != NULL) {
        _stopPending = YES;
        CFRunLoopSourceSignal(_runLoopSource);
        CFRunLoopWakeUp(CFRunLoopGetMain());
        CFRunLoopWakeUp(CFRunLoopGetCurrent());
    }
    CFRelease(self);
    return kCGErrorSuccess;
}
- (void) deliverStop { if (!_stopPending) return; _stopPending = NO; _handler(kCGDisplayStreamFrameStatusStopped, 0, NULL, NULL); }
- (void) deliverPendingFrame {
    DarlingDisplayFrame *frame = nil;
    @synchronized (_pending) {
        if ([_pending count] > 0) { frame = [[_pending objectAtIndex: 0] retain]; [_pending removeObjectAtIndex: 0]; }
    }
    if (frame == nil) return;
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
    uint32_t dx, dy, dw, dh;
    int32_t sx, sy;
    if (_minimumFrameTime > 0) {
        uint64_t now = monotonicTimeNs();
        uint64_t minimumNs = (uint64_t) (_minimumFrameTime * 1000000000.0);
        if (minimumNs > 0 && _lastFrameTimeNs != 0 && now >= _lastFrameTimeNs
                && now - _lastFrameTimeNs < minimumNs)
            return;
        _lastFrameTimeNs = now;
    }
    if (CGRectIsNull(source) || CGRectIsEmpty(source)) return;
    destination = CGRectIntersection(fittedRect(source, destination, _preserveAspectRatio), fullSurface);
    if (CGRectIsNull(destination) || CGRectIsEmpty(destination)) return;
    {
        BOOL full = NO;
        @synchronized (self) {
            if (_queueDepth > 0) {
                NSUInteger queued = _queue != NULL ? _queuedFrames : [_pending count];
                if (queued >= _queueDepth - 1)
                    full = YES;
                else if (_queue != NULL)
                    _queuedFrames++;
            }
        }
        if (full) {
            _pendingDrops++;
            return;
        }
    }
    sx = (int32_t) (source.origin.x - bounds.origin.x);
    sy = (int32_t) (source.origin.y - bounds.origin.y);
    dx = (uint32_t) destination.origin.x; dy = (uint32_t) destination.origin.y;
    dw = (uint32_t) destination.size.width; dh = (uint32_t) destination.size.height;
    IOSurfaceLock(_surface, 0, NULL);
    if (darling_screen_capture_convert_bgra_rect(frame, _surfaceBase, _surfaceStride, (uint32_t) _outputWidth, (uint32_t) _outputHeight, sx, sy, (uint32_t) source.size.width, (uint32_t) source.size.height, dx, dy, dw, dh) == 0) {
        uint32_t y;
        for (y = 0; y < dh; y++) swizzleBGRA(_surfaceBase + (dy + y) * _surfaceStride + dx * 4, dw, _pixelFormat);
    }
    IOSurfaceUnlock(_surface, 0, NULL);
    update = [[CGDisplayStreamUpdate alloc] initWithRect: destination dropCount: _pendingDrops];
    _pendingDrops = 0;
    if (_queue != NULL) {
        CGDisplayStreamFrameAvailableHandler handler = [_handler retain];
        CFRetain(_surface); [update retain];
        dispatch_async(_queue, ^{
            handler(kCGDisplayStreamFrameStatusFrameComplete, (uint64_t) frame->pts_ns, _surface, (CGDisplayStreamUpdateRef) update);
            @synchronized (self) {
                if (_queuedFrames > 0) _queuedFrames--;
            }
            CFRelease(_surface); [update release]; [handler release];
        });
        [update release];
    } else {
        CFRunLoopSourceRef source = [self runLoopSource];
        DarlingDisplayFrame *item = [[DarlingDisplayFrame alloc] init];
        item->surface = (IOSurfaceRef) CFRetain(_surface);
        item->update = update;
        item->displayTime = (uint64_t) frame->pts_ns;
        @synchronized (_pending) { [_pending addObject: item]; }
        [item release];
        if (source != NULL) { CFRunLoopSourceSignal(source); CFRunLoopWakeUp(CFRunLoopGetMain()); CFRunLoopWakeUp(CFRunLoopGetCurrent()); }
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
    if (rectType != kCGDisplayStreamUpdateRefreshedRects && rectType != kCGDisplayStreamUpdateReducedDirtyRects) {
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
