#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFRuntime.h>
#include <CoreGraphics/CGColor.h>
#include <CoreGraphics/CGGradient.h>
#include <Foundation/NSString.h>
#include <Onyx2D/O2Color.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "CGGradientPrivate.h"

static CFTypeID gradientTypeID;
static CFRuntimeClass gradientClass;
static pthread_once_t registerGradientOnce = PTHREAD_ONCE_INIT;

static void CGGradientFinalize(CFTypeRef cf);

static void RegisterCGGradient(void) {
    memset(&gradientClass, 0, sizeof(gradientClass));
    gradientClass.version = 0;
    gradientClass.className = "CGGradient";
    gradientClass.finalize = CGGradientFinalize;
    gradientTypeID = _CFRuntimeRegisterClass(&gradientClass);
}

CFTypeID CGGradientGetTypeID(void) {
    pthread_once(&registerGradientOnce, RegisterCGGradient);
    return gradientTypeID;
}

static void CGGradientFinalize(CFTypeRef cf) {
    CGGradientRef gradient = (CGGradientRef)cf;

    CGColorSpaceRelease(gradient->colorSpace);
    free(gradient->locations);
    free(gradient->components);
}

/* Locations are clamped to 0...1 and never decrease, so the stops stay ordered. */
static CGFloat CGGradientClampLocation(CGFloat location, CGFloat previous) {
    if (!(location >= 0.0))
        location = 0.0;
    if (location > 1.0)
        location = 1.0;
    if (location < previous)
        location = previous;
    return location;
}

static CFTypeRef CGGradientCreate(CGColorSpaceRef colorSpace,
                                  const CGFloat *components,
                                  const CGFloat *locations, size_t count,
                                  size_t numberOfComponents) {
    CGGradientRef gradient;
    size_t i, j;
    CGFloat previousLocation = 0.0;
    CGColorSpaceModel model;

    if (count == 0)
        return NULL;
    if (numberOfComponents == 0 || numberOfComponents > CGGradientMaximumComponents)
        return NULL;
    if (count > SIZE_MAX / numberOfComponents)
        return NULL;

    /* O2Paint_ramp can only turn monochrome, RGB and CMYK output into colours. */
    model = CGColorSpaceGetModel(colorSpace);
    if (model != kCGColorSpaceModelMonochrome && model != kCGColorSpaceModelRGB &&
        model != kCGColorSpaceModelCMYK) {
        NSLog(@"CGGradientCreate, colour space model %d is not supported",
              (int)model);
        return NULL;
    }

    /* extraBytes excludes the CFRuntimeBase that _CFRuntimeCreateInstance lays down. */
    gradient = (CGGradientRef)_CFRuntimeCreateInstance(
            NULL, CGGradientGetTypeID(),
            sizeof(struct CGGradient) - sizeof(CFRuntimeBase), NULL);
    if (gradient == NULL)
        return NULL;

    gradient->colorSpace = (CGColorSpaceRef)CGColorSpaceRetain(colorSpace);
    gradient->count = count;
    gradient->numberOfComponents = numberOfComponents;
    gradient->locations = (CGFloat *)calloc(count, sizeof(CGFloat));
    gradient->components = (CGFloat *)calloc(count * numberOfComponents,
                                             sizeof(CGFloat));
    if (gradient->locations == NULL || gradient->components == NULL) {
        CGGradientRelease(gradient);
        return NULL;
    }

    for (i = 0; i < count; i++) {
        for (j = 0; j < numberOfComponents; j++) {
            gradient->components[i * numberOfComponents + j] =
                    components[i * numberOfComponents + j];
        }
    }

    if (locations != NULL) {
        for (i = 0; i < count; i++) {
            previousLocation = CGGradientClampLocation(locations[i],
                                                      previousLocation);
            gradient->locations[i] = previousLocation;
        }
    } else if (count == 1) {
        gradient->locations[0] = 0.0;
    } else {
        /* No locations given: divide the gradient evenly. */
        for (i = 0; i < count; i++) {
            gradient->locations[i] = (CGFloat)i / (CGFloat)(count - 1);
        }
    }

    return gradient;
}

CGGradientRef CGGradientCreateWithColorComponents(CGColorSpaceRef colorSpace,
                                                  const CGFloat components[],
                                                  const CGFloat locations[],
                                                  size_t count) {
    size_t numberOfComponents;

    if (colorSpace == NULL || components == NULL)
        return NULL;

    numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpace) + 1;

    return (CGGradientRef)CGGradientCreate(colorSpace, components, locations,
                                           count, numberOfComponents);
}

CGGradientRef CGGradientCreateWithColors(CGColorSpaceRef colorSpace,
                                         CFArrayRef colors,
                                         const CGFloat locations[]) {
    CFIndex i, count;
    size_t numberOfComponents;
    CGFloat *components;
    CGGradientRef gradient;

    if (colorSpace == NULL || colors == NULL)
        return NULL;

    count = CFArrayGetCount(colors);
    if (count == 0)
        return NULL;

    numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpace) + 1;
    if (numberOfComponents > CGGradientMaximumComponents)
        return NULL;
    if ((size_t)count > SIZE_MAX / numberOfComponents)
        return NULL;

    components = (CGFloat *)calloc((size_t)count * numberOfComponents,
                                   sizeof(CGFloat));
    if (components == NULL)
        return NULL;

    for (i = 0; i < count; i++) {
        CGColorRef color = (CGColorRef)CFArrayGetValueAtIndex(colors, i);
        size_t checkNumberOfComponents, j;

        /* Colours are O2Color NSObjects, not CF objects, so the class is the check. */
        if (color == NULL || ![(id) color isKindOfClass: [O2Color class]]) {
            NSLog(@"CGGradientCreateWithColors, colour %ld is not a CGColor",
                  (long)i);
            free(components);
            return NULL;
        }

        if (CGColorGetColorSpace(color) == NULL) {
            NSLog(@"CGGradientCreateWithColors, colour %ld has no colour space",
                  (long)i);
            free(components);
            return NULL;
        }

        checkNumberOfComponents = CGColorGetNumberOfComponents(color);
        if (checkNumberOfComponents != numberOfComponents) {
            /* Only the component count is compared; a different count is refused, as nothing converts colours. */
            NSLog(@"CGGradientCreateWithColors, colour %ld has %zu components "
                  @"but the gradient's space has %zu, and colour conversion is "
                  @"not implemented", (long)i, checkNumberOfComponents,
                  numberOfComponents);
            free(components);
            return NULL;
        }

        {
            const CGFloat *copy = CGColorGetComponents(color);
            for (j = 0; j < numberOfComponents; j++)
                components[(size_t)i * numberOfComponents + j] = copy[j];
        }
    }

    gradient = (CGGradientRef)CGGradientCreate(colorSpace, components, locations,
                                               (size_t)count,
                                               numberOfComponents);
    free(components);
    return gradient;
}

void CGGradientColorAtLocation(CGGradientRef gradient, CGFloat t,
                               CGFloat *components) {
    size_t i, j, n = gradient->numberOfComponents;
    size_t stop;
    CGFloat start, end, fraction;

    /* Last stop at or before t; coincident stops resolve to the later colour. */
    if (t < gradient->locations[0]) {
        memcpy(components, gradient->components, n * sizeof(CGFloat));
        return;
    }

    stop = 0;
    for (i = 1; i < gradient->count; i++) {
        if (gradient->locations[i] > t)
            break;
        stop = i;
    }

    if (stop + 1 >= gradient->count) {
        memcpy(components, gradient->components + stop * n, n * sizeof(CGFloat));
        return;
    }

    start = gradient->locations[stop];
    end = gradient->locations[stop + 1];

    /* t >= start and t < end here, so end > start; the clamp only guards rounding. */
    fraction = (t - start) / (end - start);
    if (fraction > 1.0)
        fraction = 1.0;

    for (j = 0; j < n; j++) {
        CGFloat from = gradient->components[stop * n + j];
        CGFloat to = gradient->components[(stop + 1) * n + j];
        components[j] = from + (to - from) * fraction;
    }
}

void CGGradientRelease(CGGradientRef self) {
    if (self == NULL)
        return;
    CFRelease((CFTypeRef)self);
}

CGGradientRef CGGradientRetain(CGGradientRef self) {
    if (self == NULL)
        return NULL;
    return (CGGradientRef)CFRetain((CFTypeRef)self);
}
