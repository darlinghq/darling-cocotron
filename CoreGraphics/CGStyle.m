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

// Styles: CF objects holding the parameters of an effect, which
// CGContextSetStyle puts in the graphics state.

#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreFoundation/CFRuntime.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2GraphicsState.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <pthread.h>
#include <string.h>

struct CGStyle {
    CFRuntimeBase base;
    CGStyleType type;
    CGColorRef color;
    union {
        CGShadowStyle shadow;
        CGFocusRingStyle focusRing;
        CGGaussianBlurStyle blur;
        CGColorMatrixStyle colorMatrix;
    } data;
    // for a shadow: the offset and blur it was made with
    CGSize offset;
};

static CFTypeID styleTypeID;
static CFRuntimeClass styleClass;
static pthread_once_t registerStyleOnce = PTHREAD_ONCE_INIT;

static void finalizeStyle(CFTypeRef cf) {
    CGColorRelease(((CGStyleRef) cf)->color);
}

static void registerStyle(void) {
    memset(&styleClass, 0, sizeof(styleClass));
    styleClass.version = 0;
    styleClass.className = "CGStyle";
    styleClass.finalize = finalizeStyle;
    styleTypeID = _CFRuntimeRegisterClass(&styleClass);
}

CFTypeID CGStyleGetTypeID(void) {
    pthread_once(&registerStyleOnce, registerStyle);
    return styleTypeID;
}

static CGStyleRef createStyle(CGStyleType type, CGColorRef color) {
    CGStyleRef style = (CGStyleRef) _CFRuntimeCreateInstance(NULL, CGStyleGetTypeID(),
            sizeof(struct CGStyle) - sizeof(CFRuntimeBase), NULL);
    if (style == NULL)
        return NULL;
    style->type = type;
    style->color = CGColorRetain(color);
    memset(&style->data, 0, sizeof(style->data));
    style->offset = CGSizeZero;
    return style;
}

CGStyleRef CGStyleRetain(CGStyleRef style) {
    return style != NULL ? (CGStyleRef) CFRetain(style) : NULL;
}

void CGStyleRelease(CGStyleRef style) {
    if (style != NULL)
        CFRelease(style);
}

// QUIRK: a shadow style describes its offset as a direction and a length: the
// offset is height long and points azimuth - 180 degrees from the positive x
// axis (so azimuth = atan2(dy, dx) in degrees + 180; 180 for no offset). The
// other fields of the CGShadowStyle are 0, 45, 0 and 1 (WebKit's a, b, c and d)
// whatever the arguments, and a NULL colour stays NULL. Not documented.
// Evidence: black-box observation of CGStyleCreateShadow2 and CGStyleGetData /
// CGStyleGetColor on macOS 26.7.3 (tier 2), for the offsets (3,4), (0,5),
// (-5,0), (0,-2) and (0,0); WebKit's DrawGlyphsRecorder (BSD) decodes it the
// same way. OS versions: observed on 26.7.3 only.
// Test: coregraphics-styles.c (test_quirk_shadow_azimuth_and_height)
static void describeShadowOffset(CGShadowStyle *shadow, CGSize offset) {
    shadow->height = hypot(offset.width, offset.height);
    shadow->azimuth = shadow->height > 0
            ? atan2(offset.height, offset.width) * 180 / M_PI + 180
            : 180;
    shadow->a = 0;
    shadow->b = 45;
    shadow->c = 0;
    shadow->d = 1;
}

CGStyleRef CGStyleCreateShadow2(CGSize offset, CGFloat radius, CGColorRef color) {
    CGStyleRef style = createStyle(kCGStyleShadow, color);
    if (style == NULL)
        return NULL;
    style->offset = offset;
    describeShadowOffset(&style->data.shadow, offset);
    style->data.shadow.radius = radius;
    return style;
}

CGStyleRef CGStyleCreateFocusRingWithColor(const CGFocusRingStyle *focusRing, CGColorRef color) {
    if (focusRing == NULL || color == NULL)
        return NULL;
    CGStyleRef style = createStyle(kCGStyleFocusRing, color);
    if (style != NULL)
        style->data.focusRing = *focusRing;
    return style;
}

CGStyleRef CGStyleCreateGaussianBlur(const CGGaussianBlurStyle *blur) {
    if (blur == NULL)
        return NULL;
    CGStyleRef style = createStyle(kCGStyleGaussianBlur, NULL);
    if (style != NULL)
        style->data.blur = *blur;
    return style;
}

CGStyleRef CGStyleCreateColorMatrix(const CGColorMatrixStyle *colorMatrix) {
    if (colorMatrix == NULL)
        return NULL;
    CGStyleRef style = createStyle(kCGStyleColorMatrix, NULL);
    if (style != NULL)
        style->data.colorMatrix = *colorMatrix;
    return style;
}

CGStyleType CGStyleGetType(CGStyleRef style) {
    return style != NULL ? style->type : kCGStyleUnknown;
}

const void *CGStyleGetData(CGStyleRef style) {
    return style != NULL ? (const void *) &style->data : NULL;
}

CGColorRef CGStyleGetColor(CGStyleRef style) {
    return style != NULL ? style->color : NULL;
}

// The colour of a shadow style that has none: that of CGContextSetShadow,
// black at one third alpha (documented).
static CGColorRef defaultShadowColor(void) {
    static CGColorRef color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[4] = {0, 0, 0, 1.0 / 3.0};
        color = CGColorCreate(space, components);
        CGColorSpaceRelease(space);
    });
    return color;
}

void CGContextSetStyle(CGContextRef context, CGStyleRef style) {
    if (context == NULL)
        return;
    O2GState *gState = O2ContextCurrentGState((O2ContextRef) context);

    // The style takes the place of the state's shadow and focus ring.
    if (style != NULL && style->type == kCGStyleShadow)
        [gState setShadowOffset: style->offset
                           blur: style->data.shadow.radius
                          color: (O2ColorRef) (style->color != NULL ? style->color : defaultShadowColor())];
    else
        [gState setShadowOffset: O2SizeMake(0, 0) blur: 0 color: nil];

    if (style != NULL && style->type == kCGStyleFocusRing) {
        const CGFocusRingStyle *ring = &style->data.focusRing;
        CGFloat alpha = CGColorGetAlpha(style->color) * ring->alpha;
        CGColorRef color = CGColorCreateCopyWithAlpha(style->color, alpha);
        int ordering = ring->ordering == kCGFocusRingOrderingBelow ? 1
                : ring->ordering == kCGFocusRingOrderingAbove ? 2 : 0;
        O2GStateSetFocusRing(gState, (O2ColorRef) color, ring->radius, ordering);
        CGColorRelease(color);
    } else {
        O2GStateSetFocusRing(gState, nil, 0, 0);
    }

    O2GStateSetStyle(gState, style);
}

// A state whose shadow was set with CGContextSetShadow* has no style object;
// one describing that shadow is made, and kept in the state, when it is asked
// for.
CGStyleRef CGGStateGetStyle(CGGStateRef gstate) {
    if (gstate == NULL)
        return NULL;
    O2GState *gState = (O2GState *) gstate;
    CFTypeRef style = O2GStateGetStyle(gState);

    if (style == NULL && gState->_shadowColor != nil &&
        (gState->_shadowBlur > 0 || gState->_shadowOffset.width != 0 ||
         gState->_shadowOffset.height != 0)) {
        CGStyleRef shadow = CGStyleCreateShadow2(gState->_shadowOffset,
                gState->_shadowBlur, (CGColorRef) gState->_shadowColor);
        O2GStateSetStyle(gState, shadow);
        CGStyleRelease(shadow);
        style = shadow;
    }
    return (CGStyleRef) style;
}
