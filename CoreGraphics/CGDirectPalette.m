/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// The legacy CGDirectPalette API (CGDirectPalette.h). A palette is a table of
// device colors (floating point red, green, blue triples); as on macOS it is a
// CoreFoundation object (a CFData), so CFRetain/CFRelease and CGPaletteRelease
// agree.
#import <CoreGraphics/CGDirectPalette.h>
#include <string.h>

typedef struct {
    float c[3];
} PaletteEntry;

static CFMutableDataRef paletteData(CGDirectPaletteRef palette) {
    return (CFMutableDataRef) palette;
}

static CFMutableDataRef createTable(CFIndex count) {
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    if (data == NULL)
        return NULL;
    CFDataSetLength(data, count * (CFIndex) sizeof(PaletteEntry));
    if (CFDataGetLength(data) != count * (CFIndex) sizeof(PaletteEntry)) {
        CFRelease(data);
        return NULL;
    }
    return data;
}

static PaletteEntry *entries(CGDirectPaletteRef palette) {
    return (PaletteEntry *) CFDataGetMutableBytePtr(paletteData(palette));
}

// The standard 256-entry color table of the classic Mac OS 8-bit display: a
// 6x6x6 color cube (red slowest, blue fastest, levels 0xFF, 0xCC, ... 0x00),
// then ten-step ramps of red, green, blue and gray (0xEE, 0xDD, 0xBB, 0xAA,
// 0x88, 0x77, 0x55, 0x44, 0x22, 0x11) and black. The default palette has the
// first entry (white in the standard table) and the last (black) exchanged.
static void fillDefault(PaletteEntry *table, CGTableCount count) {
    static const unsigned cube[6] = {0xFF, 0xCC, 0x99, 0x66, 0x33, 0x00};
    static const unsigned ramp[10] = {0xEE, 0xDD, 0xBB, 0xAA, 0x88, 0x77, 0x55, 0x44, 0x22, 0x11};
    for (CGTableCount i = 0; i < count && i < 256; i++) {
        unsigned r, g, b;
        if (i == 0) {
            r = g = b = 0x00;
        } else if (i < 215) {
            r = cube[i / 36];
            g = cube[(i / 6) % 6];
            b = cube[i % 6];
        } else if (i < 225) {
            r = ramp[i - 215]; g = 0; b = 0;
        } else if (i < 235) {
            r = 0; g = ramp[i - 225]; b = 0;
        } else if (i < 245) {
            r = 0; g = 0; b = ramp[i - 235];
        } else if (i < 255) {
            r = g = b = ramp[i - 245];
        } else {
            r = g = b = 0xFF;
        }
        table[i].c[0] = r / 255.0f;
        table[i].c[1] = g / 255.0f;
        table[i].c[2] = b / 255.0f;
    }
}

CGDirectPaletteRef CGPaletteCreateDefaultColorPalette(void) {
    CFMutableDataRef data = createTable(256);
    if (data != NULL)
        fillDefault((PaletteEntry *) CFDataGetMutableBytePtr(data), 256);
    return (CGDirectPaletteRef) data;
}

// A palette for a display's own color table exists only for displays whose
// pixel format is indexed, which no display here has.
CGDirectPaletteRef CGPaletteCreateWithDisplay(CGDirectDisplayID display) {
    return NULL;
}

// The first 256 entries start as the default palette, the rest as black.
CGDirectPaletteRef CGPaletteCreateWithCapacity(CGTableCount capacity) {
    CFMutableDataRef data = createTable(capacity);
    if (data != NULL && capacity > 0)
        fillDefault((PaletteEntry *) CFDataGetMutableBytePtr(data), capacity);
    return (CGDirectPaletteRef) data;
}

CGDirectPaletteRef CGPaletteCreateWithSamples(CGDeviceColor *sampleTable, CGTableCount sampleCount) {
    if (sampleCount > 0 && sampleTable == NULL)
        return NULL;
    CFMutableDataRef data = createTable(sampleCount);
    if (data != NULL && sampleCount > 0)
        memcpy(CFDataGetMutableBytePtr(data), sampleTable, sampleCount * sizeof(PaletteEntry));
    return (CGDirectPaletteRef) data;
}

CGDirectPaletteRef CGPaletteCreateWithByteSamples(CGDeviceByteColor *sampleTable, CGTableCount sampleCount) {
    if (sampleCount > 0 && sampleTable == NULL)
        return NULL;
    CFMutableDataRef data = createTable(sampleCount);
    if (data == NULL)
        return NULL;
    PaletteEntry *out = (PaletteEntry *) CFDataGetMutableBytePtr(data);
    for (CGTableCount i = 0; i < sampleCount; i++) {
        out[i].c[0] = sampleTable[i].red / 255.0f;
        out[i].c[1] = sampleTable[i].green / 255.0f;
        out[i].c[2] = sampleTable[i].blue / 255.0f;
    }
    return (CGDirectPaletteRef) data;
}

CGDirectPaletteRef CGPaletteCreateCopy(CGDirectPaletteRef palette) {
    if (palette == NULL)
        return NULL;
    return (CGDirectPaletteRef) CFDataCreateMutableCopy(kCFAllocatorDefault, 0, paletteData(palette));
}

// The fraction is limited to 0...1; each entry moves that far towards the color.
CGDirectPaletteRef CGPaletteCreateFromPaletteBlendedWithColor(CGDirectPaletteRef palette,
                                                              CGPaletteBlendFraction fraction,
                                                              CGDeviceColor color) {
    CGDirectPaletteRef copy = CGPaletteCreateCopy(palette);
    if (copy == NULL)
        return NULL;
    if (!(fraction > 0.0f))
        fraction = 0.0f;
    if (fraction > 1.0f)
        fraction = 1.0f;
    PaletteEntry *table = entries(copy);
    CGTableCount count = CGPaletteGetNumberOfSamples(copy);
    const float target[3] = {color.red, color.green, color.blue};
    for (CGTableCount i = 0; i < count; i++) {
        for (int k = 0; k < 3; k++)
            table[i].c[k] += (target[k] - table[i].c[k]) * fraction;
    }
    return copy;
}

void CGPaletteRelease(CGDirectPaletteRef palette) {
    if (palette != NULL)
        CFRelease(palette);
}

CGTableCount CGPaletteGetNumberOfSamples(CGDirectPaletteRef palette) {
    if (palette == NULL)
        return 0;
    return (CGTableCount) (CFDataGetLength(paletteData(palette)) / (CFIndex) sizeof(PaletteEntry));
}

// An index outside the table reads as black.
CGDeviceColor CGPaletteGetColorAtIndex(CGDirectPaletteRef palette, CGTableCount index) {
    CGDeviceColor color = {0, 0, 0};
    if (index < CGPaletteGetNumberOfSamples(palette)) {
        const PaletteEntry *entry = &entries(palette)[index];
        color.red = entry->c[0];
        color.green = entry->c[1];
        color.blue = entry->c[2];
    }
    return color;
}

// Components are stored as given, without clamping to 0...1. An index outside
// the table changes nothing.
void CGPaletteSetColorAtIndex(CGDirectPaletteRef palette, CGDeviceColor color, CGTableCount index) {
    if (index >= CGPaletteGetNumberOfSamples(palette))
        return;
    PaletteEntry *entry = &entries(palette)[index];
    entry->c[0] = color.red;
    entry->c[1] = color.green;
    entry->c[2] = color.blue;
}

// The entry nearest to the color by squared distance in RGB, computed in
// double precision, the first of equally near entries winning (so exact ties
// such as (1.5,0.5,0.5) between (1,0.6,0.6) and (1,0.4,0.4) are decided by the
// rounding of the 8-bit levels).
//
// QUIRK: a color whose nearest entry is farther than a squared distance of 1
// gives kCGPaletteNoIndex, and so does an empty palette. Colors outside 0...1
// still get their nearest entry while within that distance, e.g.
// (1.5,0.5,0.5) -> 21 and (-0.3,-0.3,-0.3) -> 0, but (1.6,1.7,1.5),
// (1.7,1.7,-0.3), (-1,-1,-1) and (5,5,5) give none. The cut-off is not
// documented; it was fitted to 1617 colors on a grid, where the largest
// distance that still found an entry was 0.99 and the smallest that did not
// was 1.02 (black-box, Mac OS X 10.14.4, i386 and x86_64, tier 2).
// Test: coregraphics-direct-palette.c (quirk_index_for_distant_color).
CGTableCount CGPaletteGetIndexForColor(CGDirectPaletteRef palette, CGDeviceColor color) {
    const CGTableCount count = CGPaletteGetNumberOfSamples(palette);
    const PaletteEntry *table = count > 0 ? entries(palette) : NULL;
    CGTableCount best = kCGPaletteNoIndex;
    double bestDistance = 0;

    for (CGTableCount i = 0; i < count; i++) {
        double dr = (double) color.red - table[i].c[0];
        double dg = (double) color.green - table[i].c[1];
        double db = (double) color.blue - table[i].c[2];
        double distance = dr * dr + dg * dg + db * db;
        if (best == kCGPaletteNoIndex || distance < bestDistance) {
            best = i;
            bestDistance = distance;
        }
    }
    if (best != kCGPaletteNoIndex && bestDistance > 1.0)
        return kCGPaletteNoIndex;
    return best;
}

bool CGPaletteIsEqualToPalette(CGDirectPaletteRef palette1, CGDirectPaletteRef palette2) {
    if (palette1 == NULL || palette2 == NULL)
        return palette1 == palette2;
    return CFEqual(paletteData(palette1), paletteData(palette2));
}
