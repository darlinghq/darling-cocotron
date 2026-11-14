/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// Colour space conversion of CGColor and of drawing: CGColorCreateCopyByMatchingToColorSpace
// between named colour spaces, and a colour of one space filled into an sRGB bitmap context.
// Expected values were printed by mac-probes/v415-colorspace-matching.c on macOS 26.7.3
// (black-box, tier 2); the tolerance covers the quantisation of Apple's ICC profiles
// (0.015 for generic and Adobe spaces, 0.003 otherwise). Also passes on macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

static int g_fail;

typedef struct {
	const CFStringRef* from;
	double in[3];
	const CFStringRef* to;
	double out[3];
	int outCount;
	double tol;
} Row;

#define ROW(from, a, b, c, to, x, y, z, n, tol) { &kCGColorSpace##from, { a, b, c }, &kCGColorSpace##to, { x, y, z }, n, tol }

static const Row rows[] = {
	ROW(SRGB, 1, 0, 0, DisplayP3, 0.91747, 0.20037, 0.13852, 3, 0.003),
	ROW(SRGB, 0.2, 0.6, 0.9, DisplayP3, 0.32049, 0.59180, 0.87592, 3, 0.003),
	ROW(SRGB, 0.9, 0.3, 0.1, DisplayP3, 0.83262, 0.34403, 0.18236, 3, 0.003),
	ROW(SRGB, 0.2, 0.6, 0.9, LinearSRGB, 0.03310, 0.31855, 0.78741, 3, 0.003),
	ROW(LinearSRGB, 0.5, 0.5, 0.5, SRGB, 0.73536, 0.73536, 0.73536, 3, 0.003),
	// Display P3 colours outside sRGB are clamped for sRGB and kept for the extended space.
	ROW(DisplayP3, 0.2, 0.6, 0.9, SRGB, 0, 0.61019, 0.92562, 3, 0.003),
	ROW(DisplayP3, 0.2, 0.6, 0.9, ExtendedSRGB, -0.19356, 0.61019, 0.92562, 3, 0.003),
	ROW(DisplayP3, 0.9, 0.3, 0.1, LinearSRGB, 0.94810, 0.04318, 0, 3, 0.003),
	ROW(DisplayP3, 0.5, 0.5, 0.5, SRGB, 0.5, 0.5, 0.5, 3, 0.003),
	// Extended range keeps values outside 0...1.
	ROW(ExtendedSRGB, -0.2, 1.3, 0.5, ExtendedLinearSRGB, -0.03310, 1.82326, 0.21404, 3, 0.003),
	ROW(ExtendedSRGB, -0.2, 1.3, 0.5, ExtendedDisplayP3, 0.58072, 1.28072, 0.60659, 3, 0.003),
	ROW(ExtendedSRGB, -0.2, 1.3, 0.5, SRGB, 0, 1, 0.5, 3, 0.003),
	// Generic RGB (gamma 1.8) and the grays.
	ROW(SRGB, 1, 0, 0, GenericRGB, 0.98595, 0, 0.02694, 3, 0.015),
	ROW(SRGB, 0.2, 0.6, 0.9, GenericRGB, 0.16555, 0.52003, 0.87442, 3, 0.015),
	ROW(SRGB, 1, 0, 0, GenericGray, 0.43391, 0, 0, 1, 0.003),
	ROW(SRGB, 1, 0, 0, GenericGrayGamma2_2, 0.50903, 0, 0, 1, 0.003),
	ROW(GenericGray, 0.5, 0.5, 0.5, SRGB, 0.57231, 0.57231, 0.57231, 3, 0.003),
	ROW(GenericGrayGamma2_2, 0.5, 0.5, 0.5, DisplayP3, 0.5, 0.5, 0.5, 3, 0.003),
};

static void expect(const char* what, int ok)
{
	if (!ok) { printf("FAIL: %s\n", what); g_fail = 1; }
}

int main(void)
{
	for (unsigned i = 0; i < sizeof rows / sizeof *rows; i++)
	{
		const Row* r = &rows[i];
		CGColorSpaceRef from = CGColorSpaceCreateWithName(*r->from);
		CGColorSpaceRef to = CGColorSpaceCreateWithName(*r->to);
		char what[160];
		snprintf(what, sizeof what, "row %u: colour spaces exist", i);
		expect(what, from && to);
		if (!from || !to) continue;
		size_t nsrc = CGColorSpaceGetNumberOfComponents(from);
		CGFloat comps[4] = { r->in[0], nsrc == 1 ? 1 : r->in[1], nsrc == 1 ? 1 : r->in[2], 1 };
		CGColorRef color = CGColorCreate(from, comps);
		CGColorRef out = CGColorCreateCopyByMatchingToColorSpace(to, kCGRenderingIntentDefault, color, NULL);
		snprintf(what, sizeof what, "row %u: conversion result", i);
		expect(what, out != NULL);
		if (out)
		{
			const CGFloat* p = CGColorGetComponents(out);
			expect("component count", CGColorGetNumberOfComponents(out) == (size_t)r->outCount + 1);
			for (int k = 0; k < r->outCount; k++)
				if (fabs(p[k] - r->out[k]) > r->tol)
				{
					printf("FAIL: row %u component %d: %f, expected %f\n", i, k, p[k], r->out[k]);
					g_fail = 1;
				}
			expect("alpha kept", fabs(p[r->outCount] - 1) < 1e-6);
			CGColorRelease(out);
		}
		CGColorRelease(color);
		CGColorSpaceRelease(from);
		CGColorSpaceRelease(to);
	}

	// Alpha is not touched by the conversion.
	{
		CGColorSpaceRef p3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
		CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
		CGFloat c[4] = { 0.5, 0.5, 0.5, 0.25 };
		CGColorRef col = CGColorCreate(p3, c);
		CGColorRef out = CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, col, NULL);
		expect("alpha preserved", out && fabs(CGColorGetAlpha(out) - 0.25) < 1e-6);
		CGColorRelease(out); CGColorRelease(col);
		CGColorSpaceRelease(p3); CGColorSpaceRelease(srgb);
	}

	// Drawing: a colour of another space filled into an sRGB 8-bit context (premultiplied RGBA).
	{
		struct { const CFStringRef* space; double c[3]; int px[3]; } fills[] = {
			{ &kCGColorSpaceDisplayP3, { 0.2, 0.6, 0.9 }, { 0, 156, 236 } },
			{ &kCGColorSpaceDisplayP3, { 0.9, 0.3, 0.1 }, { 249, 59, 0 } },
			{ &kCGColorSpaceDisplayP3, { 0.5, 0.5, 0.5 }, { 128, 128, 128 } },
			{ &kCGColorSpaceLinearSRGB, { 0.5, 0.5, 0.5 }, { 188, 188, 188 } },
			{ &kCGColorSpaceGenericRGB, { 0.5, 0.5, 0.5 }, { 146, 146, 146 } },
			{ &kCGColorSpaceSRGB, { 0.2, 0.6, 0.9 }, { 51, 153, 230 } },
		};
		CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
		for (unsigned i = 0; i < sizeof fills / sizeof *fills; i++)
		{
			unsigned char px[4] = { 0, 0, 0, 0 };
			CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, srgb, kCGImageAlphaPremultipliedLast);
			CGColorSpaceRef src = CGColorSpaceCreateWithName(*fills[i].space);
			CGFloat comps[4] = { fills[i].c[0], fills[i].c[1], fills[i].c[2], 1 };
			CGColorRef col = CGColorCreate(src, comps);
			CGContextSetFillColorWithColor(ctx, col);
			CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
			for (int k = 0; k < 3; k++)
				if (abs(px[k] - fills[i].px[k]) > 2)
				{
					printf("FAIL: fill %u channel %d: %d, expected %d\n", i, k, px[k], fills[i].px[k]);
					g_fail = 1;
				}
			expect("fill alpha", px[3] == 255);
			CGColorRelease(col); CGColorSpaceRelease(src); CGContextRelease(ctx);
		}
		CGColorSpaceRelease(srgb);
	}

	// A NULL space or colour gives NULL.
	{
		CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
		expect("NULL colour", CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, NULL, NULL) == NULL);
		CGColorSpaceRelease(srgb);
	}

	printf(g_fail ? "FAIL\n" : "PASS\n");
	return g_fail;
}
