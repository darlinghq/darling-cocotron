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

// Colour transforms: conversions to one destination colour space, done with
// the colour matching CGColorCreateCopyByMatchingToColorSpace does.

#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreFoundation/CFRuntime.h>
#include <pthread.h>
#include <string.h>

struct CGColorTransform {
    CFRuntimeBase base;
    CGColorSpaceRef destination;
};

static CFTypeID transformTypeID;
static CFRuntimeClass transformClass;
static pthread_once_t registerTransformOnce = PTHREAD_ONCE_INIT;

static void finalizeTransform(CFTypeRef cf) {
    CGColorSpaceRelease(((struct CGColorTransform *) cf)->destination);
}

static void registerTransform(void) {
    memset(&transformClass, 0, sizeof(transformClass));
    transformClass.version = 0;
    transformClass.className = "CGColorTransform";
    transformClass.finalize = finalizeTransform;
    transformTypeID = _CFRuntimeRegisterClass(&transformClass);
}

CFTypeID CGColorTransformGetTypeID(void) {
    pthread_once(&registerTransformOnce, registerTransform);
    return transformTypeID;
}

CGColorTransformRef CGColorTransformCreate(CGColorSpaceRef destination, CFDictionaryRef attributes) {
    (void) attributes;
    if (destination == NULL)
        return NULL;
    struct CGColorTransform *transform = (struct CGColorTransform *) _CFRuntimeCreateInstance(
            NULL, CGColorTransformGetTypeID(),
            sizeof(struct CGColorTransform) - sizeof(CFRuntimeBase), NULL);
    if (transform == NULL)
        return NULL;
    transform->destination = CGColorSpaceRetain(destination);
    return transform;
}

CGColorRef CGColorTransformConvertColor(CGColorTransformRef transform, CGColorRef color,
                                        CGColorRenderingIntent intent)
{
    if (transform == NULL || color == NULL)
        return NULL;
    return CGColorCreateCopyByMatchingToColorSpace(transform->destination, intent, color, NULL);
}

bool CGColorTransformConvertColorComponents(CGColorTransformRef transform, CGColorSpaceRef source,
                                            CGColorRenderingIntent intent,
                                            const CGFloat sourceComponents[],
                                            CGFloat destinationComponents[])
{
    if (transform == NULL || source == NULL || sourceComponents == NULL ||
        destinationComponents == NULL)
        return false;

    size_t count = CGColorSpaceGetNumberOfComponents(source);
    size_t destinationCount = CGColorSpaceGetNumberOfComponents(transform->destination);
    if (count == 0 || count > 15 || destinationCount == 0 || destinationCount > 15)
        return false;

    // The components carry no alpha; the colour is matched opaque.
    CGFloat components[16];
    memcpy(components, sourceComponents, count * sizeof(CGFloat));
    components[count] = 1;
    CGColorRef color = CGColorCreate(source, components);
    if (color == NULL)
        return false;
    CGColorRef converted = CGColorTransformConvertColor(transform, color, intent);
    CGColorRelease(color);
    if (converted == NULL)
        return false;

    bool converts = CGColorGetNumberOfComponents(converted) >= destinationCount;
    if (converts)
        memcpy(destinationComponents, CGColorGetComponents(converted),
               destinationCount * sizeof(CGFloat));
    CGColorRelease(converted);
    return converts;
}
