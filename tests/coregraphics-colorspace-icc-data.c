/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// CGColorSpaceCopyICCData: the named RGB and gray spaces return an ICC.1
// matrix/TRC profile; device spaces return NULL. The profile is parsed with the
// published ICC structure (header, tag table, XYZType, curveType,
// parametricCurveType) and checked for its colorimetry rather than its bytes:
// the D50-adapted colorants, the transfer curve evaluated at sample points, and
// the structural requirements of a display profile. Observed on macOS 26.7.3 and
// Mojave 10.14.4: the returned profile is version 2.x or 4.0, sRGB and the
// extended sRGB share a profile, device spaces give NULL. Colorant numbers are
// from that observation (tier 2) and the sRGB colorants also follow from the
// IEC 61966-2-1 primaries adapted to D50. Also passes on macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int g_fail;

static void expect(int ok, const char *what, const char *detail) {
	if (!ok) {
		printf("%s=FAIL (%s)\n", what, detail);
		g_fail++;
	} else {
		printf("%s=PASS\n", what);
	}
}

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static double s15(const uint8_t *p) { return (int32_t)be32(p) / 65536.0; }

typedef struct {
	const uint8_t *b;
	size_t n;
	uint32_t count;
} Profile;

static const uint8_t *findTag(const Profile *p, const char *sig, uint32_t *size) {
	for (uint32_t i = 0; i < p->count; i++) {
		const uint8_t *e = p->b + 132 + 12 * i;
		if (memcmp(e, sig, 4) == 0) {
			uint32_t off = be32(e + 4), sz = be32(e + 8);
			if (off % 4 != 0 || (size_t)off + sz > p->n || sz < 8)
				return NULL;
			*size = sz;
			return p->b + off;
		}
	}
	return NULL;
}

// Evaluates a curveType or parametricCurveType at x in 0...1.
static int evalCurve(const uint8_t *t, uint32_t size, double x, double *y) {
	if (memcmp(t, "curv", 4) == 0) {
		uint32_t c = be32(t + 8);
		if (c == 0) {
			*y = x;
		} else if (c == 1) {
			*y = pow(x, be16(t + 12) / 256.0);
		} else {
			if (size < 12 + 2 * c)
				return 0;
			double pos = x * (c - 1);
			uint32_t i = (uint32_t)pos;
			if (i >= c - 1)
				i = c - 2;
			double f = pos - i;
			*y = ((1 - f) * be16(t + 12 + 2 * i) + f * be16(t + 12 + 2 * (i + 1))) / 65535.0;
		}
		return 1;
	}
	if (memcmp(t, "para", 4) == 0) {
		int fn = be16(t + 8);
		static const int need[] = {1, 3, 4, 5, 7};
		if (fn > 4 || size < 12 + 4u * need[fn])
			return 0;
		double g = s15(t + 12), a = 0, b = 0, c = 0, d = 0, e = 0, f = 0;
		if (fn >= 1) { a = s15(t + 16); b = s15(t + 20); }
		if (fn >= 2) c = s15(t + 24);
		if (fn >= 3) d = s15(t + 28);
		if (fn >= 4) { e = s15(t + 32); f = s15(t + 36); }
		switch (fn) {
		case 0: *y = pow(x, g); break;
		case 1: *y = x >= -b / a ? pow(a * x + b, g) : 0; break;
		case 2: *y = x >= -b / a ? pow(a * x + b, g) + c : c; break;
		case 3: *y = x >= d ? pow(a * x + b, g) : c * x; break;
		default: *y = x >= d ? pow(a * x + b, g) + e : c * x + f; break;
		}
		return 1;
	}
	return 0;
}

typedef enum { TRC_SRGB, TRC_GAMMA } TRCKind;

typedef struct {
	const CFStringRef *name;
	const char *label;
	int gray;
	TRCKind trc;
	double gamma;
	double col[9]; // rX rY rZ gX gY gZ bX bY bZ (RGB only)
	double tol;
} Row;

#define SRGBCOL 0.43607, 0.22249, 0.01392, 0.38515, 0.71687, 0.09708, 0.14307, 0.06061, 0.71410

static const Row rows[] = {
	{ &kCGColorSpaceSRGB, "srgb", 0, TRC_SRGB, 0, { SRGBCOL }, 0.002 },
	{ &kCGColorSpaceExtendedSRGB, "extended_srgb", 0, TRC_SRGB, 0, { SRGBCOL }, 0.002 },
	{ &kCGColorSpaceLinearSRGB, "linear_srgb", 0, TRC_GAMMA, 1.0, { SRGBCOL }, 0.002 },
	{ &kCGColorSpaceDisplayP3, "display_p3", 0, TRC_SRGB, 0,
	  { 0.51512, 0.24120, -0.00105, 0.29198, 0.69225, 0.04189, 0.15710, 0.06657, 0.78407 }, 0.002 },
	{ &kCGColorSpaceAdobeRGB1998, "adobe_rgb", 0, TRC_GAMMA, 563.0 / 256.0,
	  { 0.60974, 0.31111, 0.01947, 0.20528, 0.62567, 0.06087, 0.14919, 0.06322, 0.74457 }, 0.002 },
	{ &kCGColorSpaceGenericRGB, "generic_rgb", 0, TRC_GAMMA, 1.8,
	  { 0.45430, 0.24191, 0.01489, 0.35335, 0.67363, 0.09064, 0.15665, 0.08446, 0.71957 }, 0.003 },
	{ &kCGColorSpaceGenericRGBLinear, "generic_rgb_linear", 0, TRC_GAMMA, 1.0,
	  { 0.45430, 0.24260, 0.01480, 0.35330, 0.67439, 0.09039, 0.15660, 0.08340, 0.71950 }, 0.003 },
	{ &kCGColorSpaceGenericGray, "generic_gray", 1, TRC_GAMMA, 1.8, { 0 }, 0.003 },
	{ &kCGColorSpaceLinearGray, "linear_gray", 1, TRC_GAMMA, 1.0, { 0 }, 0.003 },
};

static void checkColorant(const Profile *p, const char *sig, const double *want, double tol, const char *label) {
	char what[96];
	uint32_t size;
	const uint8_t *t = findTag(p, sig, &size);
	snprintf(what, sizeof what, "%s_%s_colorant", label, sig);
	if (t == NULL || size != 20 || memcmp(t, "XYZ ", 4) != 0) {
		expect(0, what, "missing or not XYZType");
		return;
	}
	double x = s15(t + 8), y = s15(t + 12), z = s15(t + 16);
	char d[96];
	snprintf(d, sizeof d, "%.5f %.5f %.5f", x, y, z);
	expect(fabs(x - want[0]) <= tol && fabs(y - want[1]) <= tol && fabs(z - want[2]) <= tol, what, d);
}

static void checkRow(const Row *r) {
	char what[96], d[160];
	CGColorSpaceRef cs = CGColorSpaceCreateWithName(*r->name);
	CFDataRef data = cs ? CGColorSpaceCopyICCData(cs) : NULL;
	snprintf(what, sizeof what, "%s_has_data", r->label);
	expect(data != NULL, what, "NULL");
	if (data == NULL)
		return;

	Profile p = { CFDataGetBytePtr(data), (size_t)CFDataGetLength(data), 0 };
	snprintf(what, sizeof what, "%s_header", r->label);
	int ok = p.n >= 132 && be32(p.b) == p.n && memcmp(p.b + 36, "acsp", 4) == 0 &&
	         memcmp(p.b + 12, "mntr", 4) == 0 && memcmp(p.b + 16, r->gray ? "GRAY" : "RGB ", 4) == 0 &&
	         memcmp(p.b + 20, "XYZ ", 4) == 0 && (p.b[8] == 2 || p.b[8] == 4) &&
	         fabs(s15(p.b + 68) - 0.9642) < 1e-3 && fabs(s15(p.b + 72) - 1.0) < 1e-3 &&
	         fabs(s15(p.b + 76) - 0.8249) < 1e-3;
	snprintf(d, sizeof d, "version %u.%u size %u of %zu", p.b[8], p.b[9] >> 4, p.n >= 4 ? be32(p.b) : 0, p.n);
	expect(ok, what, d);
	p.count = p.n >= 132 ? be32(p.b + 128) : 0;

	// All tag data must lie inside the profile.
	snprintf(what, sizeof what, "%s_tag_table_in_bounds", r->label);
	ok = 132 + 12 * (size_t)p.count <= p.n;
	for (uint32_t i = 0; ok && i < p.count; i++) {
		const uint8_t *e = p.b + 132 + 12 * i;
		ok = be32(e + 4) % 4 == 0 && (size_t)be32(e + 4) + be32(e + 8) <= p.n;
	}
	expect(ok, what, "tag out of bounds or unaligned");

	uint32_t size;
	snprintf(what, sizeof what, "%s_description_and_copyright", r->label);
	expect(findTag(&p, "desc", &size) != NULL && findTag(&p, "cprt", &size) != NULL, what, "missing desc or cprt");

	const uint8_t *wt = findTag(&p, "wtpt", &size);
	snprintf(what, sizeof what, "%s_white_point_luminance", r->label);
	expect(wt != NULL && size == 20 && fabs(s15(wt + 12) - 1.0) < 1e-3, what, "wtpt Y is not 1");

	const char *trcs[3] = { "rTRC", "gTRC", "bTRC" };
	int n = 3;
	if (r->gray) {
		trcs[0] = "kTRC";
		n = 1;
	} else {
		checkColorant(&p, "rXYZ", r->col, r->tol, r->label);
		checkColorant(&p, "gXYZ", r->col + 3, r->tol, r->label);
		checkColorant(&p, "bXYZ", r->col + 6, r->tol, r->label);
	}
	for (int k = 0; k < n; k++) {
		const uint8_t *t = findTag(&p, trcs[k], &size);
		snprintf(what, sizeof what, "%s_%s_curve", r->label, trcs[k]);
		int good = t != NULL;
		static const double xs[] = { 0, 0.02, 0.1, 0.25, 0.5, 0.75, 1 };
		for (int i = 0; good && i < 7; i++) {
			double want = r->trc == TRC_SRGB ? (xs[i] <= 0.04045 ? xs[i] / 12.92 : pow((xs[i] + 0.055) / 1.055, 2.4))
			                                 : pow(xs[i], r->gamma);
			double got;
			good = evalCurve(t, size, xs[i], &got) && fabs(got - want) <= 0.003;
			if (!good)
				snprintf(d, sizeof d, "x=%.2f got %.5f want %.5f", xs[i], got, want);
		}
		expect(good, what, t ? d : "missing");
	}
	CFRelease(data);
	CGColorSpaceRelease(cs);
}

int main(void) {
	for (size_t i = 0; i < sizeof rows / sizeof rows[0]; i++)
		checkRow(&rows[i]);

	// Device spaces carry no profile.
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
	CGColorSpaceRef cmyk = CGColorSpaceCreateDeviceCMYK();
	expect(CGColorSpaceCopyICCData(rgb) == NULL, "device_rgb_null", "not NULL");
	expect(CGColorSpaceCopyICCData(gray) == NULL, "device_gray_null", "not NULL");
	expect(CGColorSpaceCopyICCData(cmyk) == NULL, "device_cmyk_null", "not NULL");
	CGColorSpaceRelease(rgb);
	CGColorSpaceRelease(gray);
	CGColorSpaceRelease(cmyk);

	// The same space gives the same data every time.
	CGColorSpaceRef s = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CFDataRef a = CGColorSpaceCopyICCData(s), b = CGColorSpaceCopyICCData(s);
	expect(a && b && CFEqual(a, b), "repeatable", "differs");
	if (a) CFRelease(a);
	if (b) CFRelease(b);
	CGColorSpaceRelease(s);

	printf("%s\n", g_fail ? "FAIL" : "PASS");
	return g_fail != 0;
}
