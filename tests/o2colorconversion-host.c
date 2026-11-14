/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// Native host unit test of Onyx2D/O2ColorConversion.m (plain C): sRGB IEC 61966-2-1 and Display P3
// definitions plus basic properties. Build and run on the host:
//   gcc -I<tree>/Onyx2D/include -x c <tree>/Onyx2D/O2ColorConversion.m o2colorconversion-host.c -lm
// (put -x none before this file). Reference values: the sRGB transfer function of the standard,
// and the Display P3 matrix as published (linear Display P3 -> linear sRGB, D65).
#include <Onyx2D/O2ColorConversion.h>
#include <math.h>
#include <stdio.h>

static int fail;
static void near(const char* what, double a, double b, double tol)
{
	if (fabs(a - b) > tol) { printf("FAIL %s: %.6f vs %.6f\n", what, a, b); fail = 1; }
}

int main(void)
{
	O2ColorProfile srgb, p3, lin, ext, gray;
	if (!O2ColorProfileForName("kCGColorSpaceSRGB", &srgb) || !O2ColorProfileForName("kCGColorSpaceDisplayP3", &p3)
		|| !O2ColorProfileForName("kCGColorSpaceLinearSRGB", &lin) || !O2ColorProfileForName("kCGColorSpaceExtendedSRGB", &ext)
		|| !O2ColorProfileForName("kCGColorSpaceGenericGray", &gray)) { printf("FAIL profiles\n"); return 1; }
	if (O2ColorProfileForName("kCGColorSpaceITUR_2100_PQ", &srgb) || O2ColorProfileForName(NULL, &srgb)
		|| O2ColorProfileForName("unknown", &srgb)) { printf("FAIL unknown names accepted\n"); return 1; }
	O2ColorProfileForName("kCGColorSpaceSRGB", &srgb);

	double out[3];
	// sRGB 0.5 -> linear: ((0.5 + 0.055) / 1.055)^2.4 = 0.21404
	double half[3] = { 0.5, 0.5, 0.5 };
	O2ColorProfileConvert(&srgb, &lin, half, out);
	near("sRGB 0.5 to linear", out[0], 0.214041, 1e-5);
	// the linear segment: 0.04 / 12.92 = 0.003096
	double dark[3] = { 0.04, 0.04, 0.04 };
	O2ColorProfileConvert(&srgb, &lin, dark, out);
	near("sRGB linear segment", out[0], 0.04 / 12.92, 1e-7);
	// white and black stay put in every direction
	double white[3] = { 1, 1, 1 }, black[3] = { 0, 0, 0 };
	O2ColorProfileConvert(&p3, &srgb, white, out);
	near("white P3 to sRGB", out[1], 1, 1e-6);
	O2ColorProfileConvert(&p3, &srgb, black, out);
	near("black P3 to sRGB", out[2], 0, 1e-9);
	// round trip sRGB -> P3 -> sRGB for an in-gamut colour
	double c[3] = { 0.3, 0.5, 0.7 }, mid[3];
	O2ColorProfileConvert(&srgb, &p3, c, mid);
	O2ColorProfileConvert(&p3, &srgb, mid, out);
	for (int i = 0; i < 3; i++) near("round trip", out[i], c[i], 1e-9);
	// Display P3 red is outside sRGB: clamped for sRGB, > 1 / < 0 for the extended space
	double red[3] = { 1, 0, 0 };
	O2ColorProfileConvert(&p3, &srgb, red, out);
	near("P3 red clamped", out[1], 0, 1e-12);
	O2ColorProfileConvert(&p3, &ext, red, out);
	if (!(out[0] > 1.09 && out[1] < -0.2)) { printf("FAIL extended range lost\n"); fail = 1; }
	// published: linear Display P3 (1,0,0) in linear sRGB is (1.2249, -0.0420, -0.0197)
	O2ColorProfile p3lin;
	O2ColorProfileForName("kCGColorSpaceExtendedLinearDisplayP3", &p3lin);
	O2ColorProfile extlin;
	O2ColorProfileForName("kCGColorSpaceExtendedLinearSRGB", &extlin);
	O2ColorProfileConvert(&p3lin, &extlin, red, out);
	near("linear P3 red in sRGB, R", out[0], 1.2249, 1e-3);
	near("linear P3 red in sRGB, G", out[1], -0.0420, 1e-3);
	near("linear P3 red in sRGB, B", out[2], -0.0197, 1e-3);
	// gray to RGB is neutral
	double g[3] = { 0.5, 0, 0 };
	O2ColorProfileConvert(&gray, &srgb, g, out);
	near("gray neutral", out[0] - out[2], 0, 1e-6);

	printf(fail ? "FAIL\n" : "PASS\n");
	return fail;
}
