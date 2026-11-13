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

typedef struct {
    CGFloat location;
    size_t index;
} CGGradientStopOrder;

/* Orders stops by location; stops with equal locations keep their given order. */
static int CGGradientCompareStops(const void *left, const void *right) {
    const CGGradientStopOrder *l = (const CGGradientStopOrder *)left;
    const CGGradientStopOrder *r = (const CGGradientStopOrder *)right;

    if (l->location < r->location)
        return -1;
    if (l->location > r->location)
        return 1;
    if (l->index < r->index)
        return -1;
    return l->index > r->index;
}

static CFTypeRef CGGradientCreate(CGColorSpaceRef colorSpace,
                                  const CGFloat *components,
                                  const CGFloat *locations, size_t count,
                                  size_t numberOfComponents) {
    CGGradientRef gradient;
    size_t i, j;
    CGGradientStopOrder *order = NULL;
    CGColorSpaceModel model;

    if (count == 0)
        return NULL;
    if (numberOfComponents == 0 || numberOfComponents > CGGradientMaximumComponents)
        return NULL;
    if (count > SIZE_MAX / numberOfComponents)
        return NULL;

    /* Locations outside 0...1 (and NaN) make the gradient invalid. */
    if (locations != NULL) {
        for (i = 0; i < count; i++) {
            if (!(locations[i] >= 0.0 && locations[i] <= 1.0))
                return NULL;
        }
    }

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

    if (locations != NULL) {
        /* The stops are stored sorted by location, each colour moving with its
         * location. */
        order = (CGGradientStopOrder *)calloc(count, sizeof(CGGradientStopOrder));
        if (order == NULL) {
            CGGradientRelease(gradient);
            return NULL;
        }
        for (i = 0; i < count; i++) {
            order[i].location = locations[i];
            order[i].index = i;
        }
        qsort(order, count, sizeof(CGGradientStopOrder), CGGradientCompareStops);
    }

    for (i = 0; i < count; i++) {
        size_t source = order != NULL ? order[i].index : i;

        for (j = 0; j < numberOfComponents; j++) {
            gradient->components[i * numberOfComponents + j] =
                    components[source * numberOfComponents + j];
        }
    }

    if (order != NULL) {
        for (i = 0; i < count; i++)
            gradient->locations[i] = order[i].location;
        free(order);
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
    size_t j, n = gradient->numberOfComponents;
    size_t segment;
    CGFloat start, end, fraction;

    /* The first colour fills everything before the first location and the last
     * colour everything after the last one. */
    if (t <= gradient->locations[0] || gradient->count == 1) {
        memcpy(components, gradient->components, n * sizeof(CGFloat));
        return;
    }
    if (t > gradient->locations[gradient->count - 1]) {
        memcpy(components, gradient->components + (gradient->count - 1) * n,
               n * sizeof(CGFloat));
        return;
    }

    /* The first segment that reaches t: at a location shared by several stops
     * the segment that ends there is used, so the colour at the tie is the
     * earlier stop's colour. */
    segment = 0;
    while (gradient->locations[segment + 1] < t)
        segment++;

    start = gradient->locations[segment];
    end = gradient->locations[segment + 1];

    /* start < t <= end here: t is above the first location and every earlier
     * segment ended below t. */
    fraction = (t - start) / (end - start);
    if (fraction > 1.0)
        fraction = 1.0;

    for (j = 0; j < n; j++) {
        CGFloat from = gradient->components[segment * n + j];
        CGFloat to = gradient->components[(segment + 1) * n + j];
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
