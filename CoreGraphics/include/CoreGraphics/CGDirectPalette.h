/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef CGDIRECTPALETTE_H
#define CGDIRECTPALETTE_H

#include <stdbool.h>
#include <stdint.h>
#include <CoreGraphics/CoreGraphicsExport.h>

typedef uint32_t CGTableCount;
typedef uint8_t CGByteValue;
typedef float CGPaletteBlendFraction;

typedef struct {
    float red;
    float green;
    float blue;
} CGDeviceColor;

typedef struct {
    CGByteValue red;
    CGByteValue green;
    CGByteValue blue;
} CGDeviceByteColor;

typedef struct _CGDirectPaletteRef *CGDirectPaletteRef;
typedef CGDirectPaletteRef CGPaletteRef;

#include <CoreGraphics/CGDirectDisplay.h>

/* Returned by CGPaletteGetIndexForColor when no palette entry is close to the color. */
#define kCGPaletteNoIndex ((CGTableCount) 0xFFFFFFFFu)

COREGRAPHICS_EXPORT CGDirectPaletteRef CGPaletteCreateDefaultColorPalette(void);
COREGRAPHICS_EXPORT CGDirectPaletteRef CGPaletteCreateWithDisplay(CGDirectDisplayID display);
COREGRAPHICS_EXPORT CGDirectPaletteRef CGPaletteCreateWithCapacity(CGTableCount capacity);
COREGRAPHICS_EXPORT CGDirectPaletteRef CGPaletteCreateWithSamples(CGDeviceColor *sampleTable, CGTableCount sampleCount);
COREGRAPHICS_EXPORT CGDirectPaletteRef CGPaletteCreateWithByteSamples(CGDeviceByteColor *sampleTable, CGTableCount sampleCount);
COREGRAPHICS_EXPORT CGDirectPaletteRef CGPaletteCreateCopy(CGDirectPaletteRef palette);
COREGRAPHICS_EXPORT CGDirectPaletteRef CGPaletteCreateFromPaletteBlendedWithColor(CGDirectPaletteRef palette, CGPaletteBlendFraction fraction, CGDeviceColor color);
COREGRAPHICS_EXPORT void CGPaletteRelease(CGDirectPaletteRef palette);
COREGRAPHICS_EXPORT CGDeviceColor CGPaletteGetColorAtIndex(CGDirectPaletteRef palette, CGTableCount index);
COREGRAPHICS_EXPORT CGTableCount CGPaletteGetIndexForColor(CGDirectPaletteRef palette, CGDeviceColor color);
COREGRAPHICS_EXPORT CGTableCount CGPaletteGetNumberOfSamples(CGDirectPaletteRef palette);
COREGRAPHICS_EXPORT void CGPaletteSetColorAtIndex(CGDirectPaletteRef palette, CGDeviceColor color, CGTableCount index);
COREGRAPHICS_EXPORT bool CGPaletteIsEqualToPalette(CGDirectPaletteRef palette1, CGDirectPaletteRef palette2);

#endif /* CGDIRECTPALETTE_H */
