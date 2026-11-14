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

// Definitions used:
//  - sRGB: IEC 61966-2-1 (Rec. 709 primaries, D65, the piecewise transfer
//    function with the linear segment below 0.04045).
//  - Display P3: the DCI-P3 primaries with the D65 white point and the sRGB
//    transfer function (as published for Display P3).
//  - Rec. ITU-R BT.2020 primaries (D65) and Adobe RGB (1998) primaries with
//    gamma 563/256.
// QUIRK: the following follow what macOS does, not the names or the standards.
// Not documented. Evidence: black-box observation of
// CGColorCreateCopyByMatchingToColorSpace on macOS 26.7.3 (tier 2, probe
// mac-probes/v415-colorspace-matching.c, test impl/V415-tests/
// coregraphics-colorspace-conversion.c): (1) the generic RGB space has gamma 1.8
// and primaries (0.630,0.340), (0.295,0.605), (0.155,0.077) with D65, fitted from
// its conversion to extended linear sRGB; generic RGB linear has the same primaries
// within 1e-3 (fitted separately); (2) ITUR_709 and ITUR_2020 use a pure power
// 2.4 transfer, not the piecewise BT.709 curve; (3) the "gamma 2.2" generic gray
// and extended gray spaces use the sRGB transfer function (generic gray is a
// gamma 1.8 power function, the linear gray spaces are linear); (4) gray conversions take the
// luminance in the D50 profile connection space, after a Bradford adaptation from
// D65 (the Y of the sRGB red primary is 0.2225). Deviations from the observed
// values stay below 0.015 (ICC profile quantisation). Spaces not listed in
// O2ColorProfileForName (DCI-P3, ROMM, ITU-R 2100) have no profile.
// All primaries are given as chromaticities with the D65 white point; between two
// of these spaces the adaptation to D50 cancels.

#include <Onyx2D/O2ColorConversion.h>
#include <math.h>
#include <string.h>

typedef struct {
    double x, y;
} Chromaticity;

static const Chromaticity kD65 = {0.3127, 0.3290};

static void invert3(const double *m, double *r) {
    double a = m[0], b = m[1], c = m[2];
    double d = m[3], e = m[4], f = m[5];
    double g = m[6], h = m[7], i = m[8];
    double det = a * (e * i - f * h) - b * (d * i - f * g) +
                 c * (d * h - e * g);
    r[0] = (e * i - f * h) / det;
    r[1] = (c * h - b * i) / det;
    r[2] = (b * f - c * e) / det;
    r[3] = (f * g - d * i) / det;
    r[4] = (a * i - c * g) / det;
    r[5] = (c * d - a * f) / det;
    r[6] = (d * h - e * g) / det;
    r[7] = (b * g - a * h) / det;
    r[8] = (a * e - b * d) / det;
}

static void setPrimaries(O2ColorProfile *p, Chromaticity r, Chromaticity g,
                         Chromaticity b, Chromaticity white) {
    // Columns: XYZ of each primary at unit luminance, then scaled so that
    // the three sum to the white point.
    double prim[9] = {r.x / r.y, g.x / g.y, b.x / b.y,
                      1,         1,         1,
                      (1 - r.x - r.y) / r.y, (1 - g.x - g.y) / g.y,
                      (1 - b.x - b.y) / b.y};
    double w[3] = {white.x / white.y, 1, (1 - white.x - white.y) / white.y};
    double inv[9];
    invert3(prim, inv);
    double s[3];
    for (int i = 0; i < 3; i++)
        s[i] = inv[i * 3] * w[0] + inv[i * 3 + 1] * w[1] + inv[i * 3 + 2] * w[2];
    double d65[9];
    for (int row = 0; row < 3; row++)
        for (int col = 0; col < 3; col++)
            d65[row * 3 + col] = prim[row * 3 + col] * s[col];
    // Convert to the D50 profile connection space (Bradford adaptation, with
    // the D65 and D50 white points), where the luminance of a gray conversion is
    // taken: this is why the Y of the red primary of sRGB is 0.2225 here and
    // not the 0.2126 of Rec. 709.
    static const double bradford[9] = {1.0478112,  0.0228866, -0.0501270,
                                       0.0295424,  0.9904844, -0.0170491,
                                       -0.0092345, 0.0150436, 0.7521316};
    for (int row = 0; row < 3; row++)
        for (int col = 0; col < 3; col++)
            p->toXYZ[row * 3 + col] = bradford[row * 3] * d65[col] +
                                      bradford[row * 3 + 1] * d65[3 + col] +
                                      bradford[row * 3 + 2] * d65[6 + col];
    invert3(p->toXYZ, p->fromXYZ);
}

static void initProfile(O2ColorProfile *p, bool gray, bool extended,
                        O2ColorTransfer transfer, double gamma) {
    memset(p, 0, sizeof(*p));
    p->isGray = gray;
    p->isExtended = extended;
    p->transfer = transfer;
    p->gamma = gamma;
}

static void setSRGBPrimaries(O2ColorProfile *p) {
    setPrimaries(p, (Chromaticity){0.640, 0.330}, (Chromaticity){0.300, 0.600},
                 (Chromaticity){0.150, 0.060}, kD65);
}

static void setP3Primaries(O2ColorProfile *p) {
    setPrimaries(p, (Chromaticity){0.680, 0.320}, (Chromaticity){0.265, 0.690},
                 (Chromaticity){0.150, 0.060}, kD65);
}

static void setBT2020Primaries(O2ColorProfile *p) {
    setPrimaries(p, (Chromaticity){0.708, 0.292}, (Chromaticity){0.170, 0.797},
                 (Chromaticity){0.131, 0.046}, kD65);
}

static void setAdobePrimaries(O2ColorProfile *p) {
    setPrimaries(p, (Chromaticity){0.640, 0.330}, (Chromaticity){0.210, 0.710},
                 (Chromaticity){0.150, 0.060}, kD65);
}

static void setGenericRGBLinearPrimaries(O2ColorProfile *p) {
    setPrimaries(p, (Chromaticity){0.6296, 0.3406}, (Chromaticity){0.2949, 0.6054},
                 (Chromaticity){0.1551, 0.0762}, kD65);
}

static void setGenericRGBPrimaries(O2ColorProfile *p) {
    setPrimaries(p, (Chromaticity){0.630, 0.340}, (Chromaticity){0.295, 0.605},
                 (Chromaticity){0.155, 0.077}, kD65);
}

bool O2ColorProfileForName(const char *name, O2ColorProfile *p) {
    if (name == NULL)
        return false;
    // Names are kCGColorSpace<Suffix>.
    static const char prefix[] = "kCGColorSpace";
    if (strncmp(name, prefix, sizeof(prefix) - 1) != 0)
        return false;
    const char *n = name + sizeof(prefix) - 1;
    bool extended = strncmp(n, "Extended", 8) == 0;
    if (extended)
        n += 8;
    // "ExtendedLinear..." leaves "Linear..." here.

    if (strcmp(n, "SRGB") == 0) {
        initProfile(p, false, extended, O2ColorTransferSRGB, 0);
        setSRGBPrimaries(p);
    } else if (strcmp(n, "LinearSRGB") == 0) {
        initProfile(p, false, extended, O2ColorTransferLinear, 0);
        setSRGBPrimaries(p);
    } else if (strcmp(n, "DisplayP3") == 0) {
        initProfile(p, false, extended, O2ColorTransferSRGB, 0);
        setP3Primaries(p);
    } else if (strcmp(n, "LinearDisplayP3") == 0) {
        initProfile(p, false, extended, O2ColorTransferLinear, 0);
        setP3Primaries(p);
    } else if (strcmp(n, "GenericRGB") == 0) {
        initProfile(p, false, extended, O2ColorTransferGamma, 1.8);
        setGenericRGBPrimaries(p);
    } else if (strcmp(n, "GenericRGBLinear") == 0) {
        initProfile(p, false, extended, O2ColorTransferLinear, 0);
        setGenericRGBLinearPrimaries(p);
    } else if (strcmp(n, "AdobeRGB1998") == 0) {
        initProfile(p, false, extended, O2ColorTransferGamma, 563.0 / 256.0);
        setAdobePrimaries(p);
    } else if (strcmp(n, "ITUR_709") == 0) {
        initProfile(p, false, extended, O2ColorTransferGamma, 2.4);
        setSRGBPrimaries(p);
    } else if (strcmp(n, "ITUR_2020") == 0) {
        initProfile(p, false, extended, O2ColorTransferGamma, 2.4);
        setBT2020Primaries(p);
    } else if (strcmp(n, "LinearITUR_2020") == 0) {
        initProfile(p, false, extended, O2ColorTransferLinear, 0);
        setBT2020Primaries(p);
    } else if (strcmp(n, "GenericGray") == 0) {
        initProfile(p, true, extended, O2ColorTransferGamma, 1.8);
        setSRGBPrimaries(p);
    } else if (strcmp(n, "GenericGrayGamma2_2") == 0) {
        initProfile(p, true, extended, O2ColorTransferSRGB, 0);
        setSRGBPrimaries(p);
    } else if (strcmp(n, "Gray") == 0 || strcmp(n, "LinearGray") == 0) {
        // "ExtendedGray" is gamma 2.2 as well; the linear variants are linear.
        bool linear = n[0] == 'L';
        initProfile(p, true, extended, linear ? O2ColorTransferLinear
                                              : O2ColorTransferSRGB,
                    0);
        setSRGBPrimaries(p);
    } else {
        return false;
    }
    return true;
}

static double decode(const O2ColorProfile *p, double c) {
    double a = fabs(c);
    double lin;
    switch (p->transfer) {
    case O2ColorTransferSRGB:
        lin = (a <= 0.04045) ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4);
        break;
    case O2ColorTransferGamma:
        lin = pow(a, p->gamma);
        break;
    case O2ColorTransferITU709:
        lin = (a < 0.081) ? a / 4.5 : pow((a + 0.099) / 1.099, 1 / 0.45);
        break;
    default:
        lin = a;
        break;
    }
    return (c < 0) ? -lin : lin;
}

static double encode(const O2ColorProfile *p, double l) {
    double a = fabs(l);
    double c;
    switch (p->transfer) {
    case O2ColorTransferSRGB:
        c = (a <= 0.0031308) ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055;
        break;
    case O2ColorTransferGamma:
        c = pow(a, 1 / p->gamma);
        break;
    case O2ColorTransferITU709:
        c = (a < 0.018) ? a * 4.5 : 1.099 * pow(a, 0.45) - 0.099;
        break;
    default:
        c = a;
        break;
    }
    return (l < 0) ? -c : c;
}

static double clamp01(double v) {
    return v < 0 ? 0 : (v > 1 ? 1 : v);
}

void O2ColorProfileConvert(const O2ColorProfile *source,
                           const O2ColorProfile *destination, const double *in,
                           double *out) {
    // The input of a space without extended range is limited to 0...1.
    double xyz[3];
    if (source->isGray) {
        double y = decode(source, source->isExtended ? in[0] : clamp01(in[0]));
        // The neutral axis: the white point scaled by the luminance.
        double w[3] = {source->toXYZ[0] + source->toXYZ[1] + source->toXYZ[2],
                       source->toXYZ[3] + source->toXYZ[4] + source->toXYZ[5],
                       source->toXYZ[6] + source->toXYZ[7] + source->toXYZ[8]};
        for (int i = 0; i < 3; i++)
            xyz[i] = y * w[i];
    } else {
        double lin[3];
        for (int i = 0; i < 3; i++) {
            double c = source->isExtended ? in[i] : clamp01(in[i]);
            lin[i] = decode(source, c);
        }
        for (int row = 0; row < 3; row++)
            xyz[row] = source->toXYZ[row * 3] * lin[0] +
                       source->toXYZ[row * 3 + 1] * lin[1] +
                       source->toXYZ[row * 3 + 2] * lin[2];
    }

    if (destination->isGray) {
        double v = encode(destination, xyz[1]);
        out[0] = destination->isExtended ? v : clamp01(v);
    } else {
        for (int row = 0; row < 3; row++) {
            double l = destination->fromXYZ[row * 3] * xyz[0] +
                       destination->fromXYZ[row * 3 + 1] * xyz[1] +
                       destination->fromXYZ[row * 3 + 2] * xyz[2];
            double v = encode(destination, l);
            out[row] = destination->isExtended ? v : clamp01(v);
        }
    }
}
