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

// Colorimetric conversion between the named colour spaces (sRGB, Display P3,
// linear and generic variants, grays). Plain C with no Onyx2D dependency, so it
// can be unit-tested natively.
//
// A space is described by its primaries and white point, which give the matrix
// between its linear components and CIE XYZ, and by its transfer function.
// Converting goes source encoding -> linear -> XYZ -> destination linear ->
// destination encoding. Spaces whose name says "Extended" keep values outside
// 0...1 (the transfer function is mirrored around zero); all others clamp.

#ifndef O2_COLOR_CONVERSION_H
#define O2_COLOR_CONVERSION_H

#include <stdbool.h>

typedef enum {
    O2ColorTransferLinear,
    O2ColorTransferSRGB,
    O2ColorTransferGamma,
    O2ColorTransferITU709,
} O2ColorTransfer;

typedef struct {
    bool isGray;
    bool isExtended;
    O2ColorTransfer transfer;
    double gamma;      // O2ColorTransferGamma only
    double toXYZ[9];   // row-major, linear RGB -> XYZ (RGB spaces)
    double fromXYZ[9]; // inverse of toXYZ
} O2ColorProfile;

// Fills the profile of a space known by its kCGColorSpace... name; false for a
// name without a profile.
bool O2ColorProfileForName(const char *name, O2ColorProfile *profile);

// Converts one color. Gray profiles take and give one component, others three;
// alpha is the caller's business.
void O2ColorProfileConvert(const O2ColorProfile *source,
                           const O2ColorProfile *destination,
                           const double *in, double *out);

#endif
