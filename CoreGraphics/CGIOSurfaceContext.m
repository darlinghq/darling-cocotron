/*
 This file is part of Darling.

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

// IOSurface contexts: bitmap contexts over the memory of an IOSurface. The
// surfaces of the contexts are kept in a table, so that the IOSurface context
// functions can tell such a context from another bitmap context; an entry is
// removed when its context goes away.

#import "CGContextInternal.h"
#import <CoreGraphics/CGIOSurfaceContext.h>
#import <IOSurface/IOSurfaceRef.h>
#include <pthread.h>
#include <stdlib.h>

typedef struct {
    IOSurfaceRef surface;
    CGContextRef context;
    uint32_t displayMask;
} IOSurfaceContextRecord;

static pthread_mutex_t recordsLock = PTHREAD_MUTEX_INITIALIZER;
// context -> IOSurfaceContextRecord *, neither retained
static CFMutableDictionaryRef records;

static IOSurfaceContextRecord *recordForContext(CGContextRef context) {
    IOSurfaceContextRecord *record = NULL;
    if (context == NULL)
        return NULL;
    pthread_mutex_lock(&recordsLock);
    if (records != NULL)
        record = (IOSurfaceContextRecord *) CFDictionaryGetValue(records, context);
    pthread_mutex_unlock(&recordsLock);
    return record;
}

// Called when the context is released, and also when it could not be
// created (see O2BitmapContext's QUIRK), before it was put in the table.
static void releaseSurface(void *info, void *data) {
    IOSurfaceContextRecord *record = info;
    (void) data;

    pthread_mutex_lock(&recordsLock);
    if (records != NULL && record->context != NULL &&
        CFDictionaryGetValue(records, record->context) == record)
        CFDictionaryRemoveValue(records, record->context);
    pthread_mutex_unlock(&recordsLock);
    CFRelease(record->surface);
    free(record);
}

bool _CGIOSurfaceContextIsIOSurfaceContext(CGContextRef context) {
    return recordForContext(context) != NULL;
}

CGContextRef CGIOSurfaceContextCreate(IOSurfaceRef surface, size_t width,
        size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
        CGColorSpaceRef colorSpace, CGBitmapInfo bitmapInfo)
{
    if (surface == NULL || colorSpace == NULL || width == 0 || height == 0 ||
        bitsPerComponent == 0 || bitsPerPixel == 0)
        return NULL;
    if (width > IOSurfaceGetWidth(surface) || height > IOSurfaceGetHeight(surface))
        return NULL;

    void *base = IOSurfaceGetBaseAddress(surface);
    size_t bytesPerRow = IOSurfaceGetBytesPerRow(surface);
    if (base == NULL || bytesPerRow == 0 || width > (bytesPerRow * 8) / bitsPerPixel)
        return NULL;

    IOSurfaceContextRecord *record = calloc(1, sizeof(IOSurfaceContextRecord));
    if (record == NULL)
        return NULL;
    record->surface = (IOSurfaceRef) CFRetain(surface);

    CGContextRef context = CGBitmapContextCreateWithData(base, width, height,
            bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo,
            releaseSurface, record);
    // A failed creation has called releaseSurface already.
    if (context == NULL)
        return NULL;
    if (CGBitmapContextGetBitsPerPixel(context) != bitsPerPixel) {
        CGContextRelease(context);
        return NULL;
    }

    pthread_mutex_lock(&recordsLock);
    if (records == NULL)
        records = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    record->context = context;
    if (records != NULL)
        CFDictionarySetValue(records, context, record);
    pthread_mutex_unlock(&recordsLock);
    if (records == NULL) {
        CGContextRelease(context);
        return NULL;
    }
    return context;
}

CGImageRef CGIOSurfaceContextCreateImage(CGContextRef context) {
    if (!_CGIOSurfaceContextIsIOSurfaceContext(context))
        return NULL;
    return CGBitmapContextCreateImage(context);
}

CGImageRef CGIOSurfaceContextCreateImageReference(CGContextRef context) {
    return CGIOSurfaceContextCreateImage(context);
}

CGColorSpaceRef CGIOSurfaceContextGetColorSpace(CGContextRef context) {
    if (!_CGIOSurfaceContextIsIOSurfaceContext(context))
        return NULL;
    return CGBitmapContextGetColorSpace(context);
}

size_t CGIOSurfaceContextGetBitmapInfo(CGContextRef context) {
    if (!_CGIOSurfaceContextIsIOSurfaceContext(context))
        return 0;
    return CGBitmapContextGetBitmapInfo(context);
}

IOSurfaceRef CGIOSurfaceContextGetSurface(CGContextRef context) {
    IOSurfaceContextRecord *record = recordForContext(context);
    return record != NULL ? record->surface : NULL;
}

void CGIOSurfaceContextSetDisplayMask(CGContextRef context, uint32_t mask) {
    IOSurfaceContextRecord *record = recordForContext(context);
    if (record != NULL)
        record->displayMask = mask;
}

void CGIOSurfaceContextInvalidateSurface(CGContextRef context) {
    (void) context;
}
