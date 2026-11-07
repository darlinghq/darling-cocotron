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

#import <CoreGraphics/CoreGraphicsExport.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CGError.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOSurface/IOSurfaceRef.h>
#include <dispatch/dispatch.h>

COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamSourceRect;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamDestinationRect;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamPreserveAspectRatio;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamColorSpace;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamMinimumFrameTime;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamShowCursor;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamQueueDepth;

typedef struct CGDisplayStream *CGDisplayStreamRef;
typedef const struct CGDisplayStreamUpdate *CGDisplayStreamUpdateRef;

typedef CF_ENUM(int32_t, CGDisplayStreamFrameStatus) {
    kCGDisplayStreamFrameStatusFrameComplete = 0,
    kCGDisplayStreamFrameStatusFrameIdle = 1,
    kCGDisplayStreamFrameStatusFrameBlank = 2,
    kCGDisplayStreamFrameStatusStopped = 3,
};

typedef CF_ENUM(int32_t, CGDisplayStreamUpdateRectType) {
    kCGDisplayStreamUpdateRefreshedRects = 0,
    kCGDisplayStreamUpdateMovedRects = 1,
    kCGDisplayStreamUpdateDirtyRects = 2,
    kCGDisplayStreamUpdateReducedDirtyRects = 3,
};

COREGRAPHICS_EXPORT CFTypeID CGDisplayStreamGetTypeID(void);
COREGRAPHICS_EXPORT CFTypeID CGDisplayStreamUpdateGetTypeID(void);

#ifdef __BLOCKS__
typedef void (^CGDisplayStreamFrameAvailableHandler)(
    CGDisplayStreamFrameStatus status, uint64_t displayTime,
    IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef);

COREGRAPHICS_EXPORT CGDisplayStreamRef CGDisplayStreamCreate(
    CGDirectDisplayID display, size_t outputWidth, size_t outputHeight,
    int32_t pixelFormat, CFDictionaryRef properties,
    CGDisplayStreamFrameAvailableHandler handler);
COREGRAPHICS_EXPORT CGDisplayStreamRef CGDisplayStreamCreateWithDispatchQueue(
    CGDirectDisplayID display, size_t outputWidth, size_t outputHeight,
    int32_t pixelFormat, CFDictionaryRef properties, dispatch_queue_t queue,
    CGDisplayStreamFrameAvailableHandler handler);
#endif

COREGRAPHICS_EXPORT CFRunLoopSourceRef CGDisplayStreamGetRunLoopSource(CGDisplayStreamRef displayStream);
COREGRAPHICS_EXPORT CGError CGDisplayStreamStart(CGDisplayStreamRef displayStream);
COREGRAPHICS_EXPORT CGError CGDisplayStreamStop(CGDisplayStreamRef displayStream);

COREGRAPHICS_EXPORT const CGRect *CGDisplayStreamUpdateGetRects(
    CGDisplayStreamUpdateRef updateRef, CGDisplayStreamUpdateRectType rectType,
    size_t *rectCount);
COREGRAPHICS_EXPORT CGDisplayStreamUpdateRef CGDisplayStreamUpdateCreateMergedUpdate(
    CGDisplayStreamUpdateRef firstUpdate, CGDisplayStreamUpdateRef secondUpdate);
COREGRAPHICS_EXPORT void CGDisplayStreamUpdateGetMovedRectsDelta(
    CGDisplayStreamUpdateRef updateRef, CGFloat *dx, CGFloat *dy);
COREGRAPHICS_EXPORT size_t CGDisplayStreamUpdateGetDropCount(CGDisplayStreamUpdateRef updateRef);
