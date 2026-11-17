/* Copyright (C) 2026 Lubos Dolezel

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSQuickDrawView.h>

#ifndef __LP64__

#import <AppKit/NSGraphicsContext.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>

// QuickDraw announces the flushed part of a port (QDFlushPortBuffer) to the
// local notification center under this name, with the port as the object and
// the flushed rectangle, when there is one, as CFNumber values in the user info.
static NSString *const QDPortFlushedNotificationName = @"com.darlinghq.QD.PortFlushed";

static void portFlushed(CFNotificationCenterRef center, void *observer,
                        CFNotificationName name, const void *object,
                        CFDictionaryRef userInfo);

@interface NSQuickDrawView ()
- (void) _portFlushed: (NSValue *) dirtyRect;
@end

@implementation NSQuickDrawView

// QuickDraw coordinates have their origin at the top left.
- (BOOL) isFlipped {
    return YES;
}

- (void *) qdPort {
    if (_qdPort == NULL) {
        NSSize size = [self bounds].size;
        if (size.width < 1 || size.height < 1 || size.width > 32767 || size.height > 32767)
            return NULL;
        Rect rect;
        SetRect(&rect, 0, 0, (short) size.width, (short) size.height);

        GWorldPtr port = NULL;
        if (NewGWorld(&port, 32, &rect, NULL, NULL, 0) != noErr)
            return NULL;
        _qdPort = port;
        CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), self,
                                        portFlushed, (CFStringRef) QDPortFlushedNotificationName,
                                        port,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return _qdPort;
}

- (void) dealloc {
    if (_qdPort != NULL) {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetLocalCenter(), self);
        DisposeGWorld((GWorldPtr) _qdPort);
        _qdPort = NULL;
    }
    [super dealloc];
}

// The pixels of the port are drawn at the top left of the view, as 32-bit
// ARGB with the alpha byte ignored.
- (void) drawRect: (NSRect) dirtyRect {
    if (_qdPort == NULL)
        return;

    PixMapHandle pixMap = GetPortPixMap((CGrafPtr) _qdPort);
    Rect bounds;
    GetPortBounds((CGrafPtr) _qdPort, &bounds);
    size_t width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
    if (pixMap == NULL || width == 0 || height == 0)
        return;

    LockPixels(pixMap);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(
            NULL, GetPixBaseAddr(pixMap), (size_t) GetPixRowBytes(pixMap) * height, NULL);
    CGImageRef image = CGImageCreate(width, height, 8, 32, (size_t) GetPixRowBytes(pixMap),
                                     colorSpace,
                                     kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Big,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    if (image != NULL && context != NULL) {
        NSPoint origin = [self bounds].origin;
        CGContextSaveGState(context);
        CGContextClipToRect(context, NSRectToCGRect(dirtyRect));
        // The view is flipped, the image is not.
        CGContextTranslateCTM(context, origin.x, origin.y + height);
        CGContextScaleCTM(context, 1, -1);
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGContextRestoreGState(context);
    }
    CGImageRelease(image);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    UnlockPixels(pixMap);
}

// Redraws the flushed part on the main thread, at once: QuickDraw callers
// expect the flush to put the pixels on screen.
- (void) _portFlushed: (NSValue *) dirtyRect {
    NSRect rect = [self bounds];
    if (dirtyRect != nil) {
        NSRect flushed = [dirtyRect rectValue];
        flushed.origin.x += rect.origin.x;
        flushed.origin.y += rect.origin.y;
        rect = NSIntersectionRect(rect, flushed);
    }
    if (NSIsEmptyRect(rect))
        return;
    [self setNeedsDisplayInRect: rect];
    [self displayRect: rect];
}

static void portFlushed(CFNotificationCenterRef center, void *observer,
                        CFNotificationName name, const void *object,
                        CFDictionaryRef userInfo)
{
    NSQuickDrawView *view = (NSQuickDrawView *) observer;
    NSValue *dirty = nil;
    if (userInfo != NULL) {
        short values[4] = {0, 0, 0, 0};
        CFStringRef keys[4] = {CFSTR("top"), CFSTR("left"), CFSTR("bottom"), CFSTR("right")};
        for (int i = 0; i < 4; i++) {
            CFNumberRef number = CFDictionaryGetValue(userInfo, keys[i]);
            if (number != NULL)
                CFNumberGetValue(number, kCFNumberShortType, &values[i]);
        }
        dirty = [NSValue valueWithRect: NSMakeRect(values[1], values[0], values[3] - values[1], values[2] - values[0])];
    }
    if ([NSThread isMainThread]) {
        [view _portFlushed: dirty];
    } else {
        [view retain];
        [dirty retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            [view _portFlushed: dirty];
            [dirty release];
            [view release];
        });
    }
}

@end

#endif
