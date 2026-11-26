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

#ifndef CGSTYLEPRIVATE_H
#define CGSTYLEPRIVATE_H

// Private CoreGraphics interfaces: styles, effects a context applies to what
// it draws (a shadow, a focus ring, a blur, a colour matrix). Apple does not
// document them. The names, signatures and structure layouts follow the
// declarations WebKit (BSD licensed) makes for them in
// Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h; the numeric values are
// inferred from those declarations.

#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGContextDelegatePrivate.h>

__BEGIN_DECLS

// Inferred values.
typedef CF_ENUM(int32_t, CGStyleType) {
    kCGStyleUnknown = 0,
    kCGStyleShadow = 1,
    kCGStyleFocusRing = 2,
    kCGStyleGaussianBlur = 3,
    kCGStyleColorMatrix = 4,
};

// Inferred values.
typedef CF_ENUM(int32_t, CGStyleDrawOrdering) {
    kCGStyleDrawOrderingStyleOnly = 0,
    kCGStyleDrawOrderingBelow = 1,
    kCGStyleDrawOrderingAbove = 2,
};

typedef CF_ENUM(int32_t, CGFocusRingOrdering) {
    kCGFocusRingOrderingNone = kCGStyleDrawOrderingStyleOnly,
    kCGFocusRingOrderingBelow = kCGStyleDrawOrderingBelow,
    kCGFocusRingOrderingAbove = kCGStyleDrawOrderingAbove,
};

typedef CF_ENUM(int32_t, CGFocusRingTint) {
    kCGFocusRingTintBlue = 0,
    kCGFocusRingTintGraphite = 1,
};

// A focus ring: drawn around the outline of what is filled or stroked, radius
// wide, in the style's colour with alpha applied. ordering says whether the
// shape is drawn as well (below or above the ring) or only the ring.
struct CGFocusRingStyle {
    unsigned int version;
    CGFocusRingTint tint;
    CGFocusRingOrdering ordering;
    CGFloat alpha;
    CGFloat radius;
    CGFloat threshold;
    CGRect bounds;
    int accumulate;
};
typedef struct CGFocusRingStyle CGFocusRingStyle;

// A shadow, as CGStyleGetData returns it for a shadow style. The offset is
// height long, in the direction azimuth - 180 degrees from the positive x
// axis; radius is the blur radius. The unnamed fields are 0.
struct CGShadowStyle {
    unsigned a;
    CGFloat b;
    CGFloat azimuth;
    CGFloat c;
    CGFloat height;
    CGFloat radius;
    CGFloat d;
};
typedef struct CGShadowStyle CGShadowStyle;

struct CGGaussianBlurStyle {
    unsigned version;
    CGFloat radius;
};
typedef struct CGGaussianBlurStyle CGGaussianBlurStyle;

// A 4x5 colour matrix, row by row (red, green, blue, alpha outputs), each row
// the factors of red, green, blue and alpha and a constant.
struct CGColorMatrixStyle {
    unsigned version;
    CGFloat matrix[20];
};
typedef struct CGColorMatrixStyle CGColorMatrixStyle;

// The styles are CF objects; release them with CFRelease or CGStyleRelease.
extern CFTypeID CGStyleGetTypeID(void);
extern CGStyleRef CGStyleRetain(CGStyleRef style);
extern void CGStyleRelease(CGStyleRef style);
// A shadow offset by offset (in base space) and blurred by radius; a NULL
// colour gives the default shadow colour, black at a third opacity.
extern CGStyleRef CGStyleCreateShadow2(CGSize offset, CGFloat radius, CGColorRef color);
// NULL for a NULL style or colour.
extern CGStyleRef CGStyleCreateFocusRingWithColor(const CGFocusRingStyle *style, CGColorRef color);
// NULL for a NULL style.
extern CGStyleRef CGStyleCreateGaussianBlur(const CGGaussianBlurStyle *style);
extern CGStyleRef CGStyleCreateColorMatrix(const CGColorMatrixStyle *style);
// kCGStyleUnknown, NULL and NULL for a NULL style.
extern CGStyleType CGStyleGetType(CGStyleRef style);
// The style's parameters: a CGShadowStyle, CGFocusRingStyle,
// CGGaussianBlurStyle or CGColorMatrixStyle, owned by the style.
extern const void *CGStyleGetData(CGStyleRef style);
// The colour of a shadow or focus ring style, owned by the style; NULL for the
// other kinds.
extern CGColorRef CGStyleGetColor(CGStyleRef style);

// Sets the style in the context's graphics state (NULL removes it). A shadow
// style sets the state's shadow and a focus ring style draws focus rings
// around filled and stroked paths; the blur and colour matrix styles are kept
// but not applied, what is drawn is drawn without the effect.
extern void CGContextSetStyle(CGContextRef context, CGStyleRef style);

__END_DECLS

#endif
