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

#import "WaylandCursor.h"
#import "WaylandScale.h"
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <Foundation/NSData.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

@implementation WaylandCursor

- (instancetype) initWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot {
    if ((self = [super init]) == nil)
        return nil;

    NSSize size = [image size];
    // The shm pool size and stride are signed 32-bit protocol arguments.
    double width = ceil(size.width), height = ceil(size.height);
    if (!isfinite(width) || !isfinite(height) || width < 1 || height < 1 ||
        width > INT32_MAX / 4 || height > INT32_MAX / (width * 4) ||
        !isfinite(hotSpot.x) || !isfinite(hotSpot.y)) {
        [self release];
        return nil;
    }
    _size = NSMakeSize(width, height);
    _hotSpot = NSMakePoint(MAX(0, MIN(floor(hotSpot.x), width - 1)),
                          MAX(0, MIN(floor(hotSpot.y), height - 1)));

    _image = [image retain];
    @try {
        if ([self pixelsForScale: 1] == nil) {
            [self release];
            return nil;
        }
    } @catch (id exception) {
        [self release];
        @throw;
    }
    return self;
}

- (NSData *) pixelsForScale: (int32_t) scale {
    if (scale < 1 || (uint64_t)scale * 120 > UINT32_MAX) return nil;
    return [self pixelsForScale120: (uint32_t)scale * 120];
}

- (NSSize) pixelSizeForScale120: (uint32_t) scale120 {
    int32_t width, height;
    if (!WaylandScaleExtent((int32_t)_size.width, scale120, INT32_MAX / 4, &width) ||
        !WaylandScaleExtent((int32_t)_size.height, scale120, INT32_MAX / (width * 4), &height)) return NSZeroSize;
    return NSMakeSize(width, height);
}

- (NSData *) pixelsForScale120: (uint32_t) scale120 {
    if (_image == nil)
        return nil;
    if (_pixels != nil && _pixelScale120 == scale120)
        return _pixels;
    NSSize dimensions = [self pixelSizeForScale120: scale120];
    double width = dimensions.width, height = dimensions.height;
    if (width < 1 || height < 1) return nil;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0,
            colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL)
        return nil;
    @try {
        [NSGraphicsContext saveGraphicsState];
        @try {
            [NSGraphicsContext setCurrentContext:
                    [NSGraphicsContext graphicsContextWithGraphicsPort: context flipped: NO]];
            CGContextScaleCTM(context, width / _size.width, height / _size.height);
            [_image drawInRect: NSMakeRect(0, 0, _size.width, _size.height)
                     fromRect: NSZeroRect operation: NSCompositeCopy fraction: 1.0];
        } @finally {
            [NSGraphicsContext restoreGraphicsState];
        }
        size_t stride = (size_t) width * 4;
        NSMutableData *pixels = [NSMutableData dataWithLength: stride * (size_t) height];
        const uint8_t *source = CGBitmapContextGetData(context);
        size_t sourceStride = CGBitmapContextGetBytesPerRow(context);
        for (size_t row = 0; row < (size_t) height; row++)
            memcpy((uint8_t *) [pixels mutableBytes] + row * stride,
                   source + row * sourceStride, stride);
        NSData *snapshot = [pixels copy];
        [_pixels release];
        _pixels = snapshot;
        _pixelScale120 = scale120;
    } @finally {
        CGContextRelease(context);
    }
    return _pixels;
}

- (void) dealloc {
    [_pixels release];
    [_image release];
    [super dealloc];
}

- (NSData *) pixels { return _pixels; }
- (NSSize) size { return _size; }
- (NSPoint) hotSpot { return _hotSpot; }

- (instancetype) initWithName: (const char *) name fallback: (const char *) fallback {
    if ((self = [super init]) != nil) {
        _names[0] = name;
        _names[1] = fallback;
        _names[2] = NULL;
    }
    return self;
}

- (instancetype) initBlank {
    if ((self = [super init]) != nil)
        _blank = YES;
    return self;
}

- (const char *const *) names {
    return _names;
}

- (BOOL) isBlank {
    return _blank;
}

@end
