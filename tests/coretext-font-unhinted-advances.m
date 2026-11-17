// Copyright (C) 2026 Lubos Dolezel
//
// Glyph advances and line widths are the unhinted design widths scaled to the
// exact (fractional) point size, not whole-pixel hinted advances. Expected
// numbers were measured on macOS 10.14.4 with the same font file (DejaVu Sans,
// loaded from data, so both systems use identical font data). Line widths are
// measured with pair kerning switched off, so they are sums of the advances.
// usage: coretext-font-unhinted-advances tests/fixtures/fonts/DejaVuSans.ttf
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>

static int failures;
static void report(int ok, const char *what, double got, double want) {
	if (ok) printf("PASS: %s\n", what);
	else { printf("FAIL: %s got %.4f want %.4f\n", what, got, want); failures++; }
}
#define NEAR(what, got, want, tol) report(fabs((got) - (want)) <= (tol), what, got, want)

static CTFontRef makeFont(const char *path, CGFloat size) {
	NSData *data = [NSData dataWithContentsOfFile: [NSString stringWithUTF8String: path]];
	CGDataProviderRef dp = data ? CGDataProviderCreateWithCFData((__bridge CFDataRef) data) : NULL;
	CGFontRef cg = dp ? CGFontCreateWithDataProvider(dp) : NULL;
	if (!cg) return NULL;
	CTFontRef f = CTFontCreateWithGraphicsFont(cg, size, NULL, NULL);
	CGFontRelease(cg);
	CGDataProviderRelease(dp);
	return f;
}

static double lineWidth(CTFontRef f, NSString *s) {
	// Kerning off (kCTKernAttributeName 0): the widths are sums of the advances.
	NSDictionary *a = @{ (__bridge id) kCTFontAttributeName: (__bridge id) f,
	                     (__bridge id) kCTKernAttributeName: @0 };
	NSAttributedString *as = [[NSAttributedString alloc] initWithString: s attributes: a];
	CTLineRef l = CTLineCreateWithAttributedString((CFAttributedStringRef) as);
	double w = CTLineGetTypographicBounds(l, NULL, NULL, NULL);
	CFRelease(l);
	return w;
}

static void advancesAt(const char *path, double size, double h, double w, double i,
                       double m, double line0, double line3)
{
	CTFontRef f = makeFont(path, size);
	if (!f) { printf("FAIL: font loads at %g\n", size); failures++; return; }
	UniChar ch[4] = { 'H', 'W', 'i', 'm' };
	CGGlyph gl[4];
	CGSize adv[4];
	CTFontGetGlyphsForCharacters(f, ch, gl, 4);
	CTFontGetAdvancesForGlyphs(f, kCTFontOrientationHorizontal, gl, adv, 4);
	char name[96];
	snprintf(name, sizeof name, "advance H at %g", size); NEAR(name, adv[0].width, h, 0.01);
	snprintf(name, sizeof name, "advance W at %g", size); NEAR(name, adv[1].width, w, 0.01);
	snprintf(name, sizeof name, "advance i at %g", size); NEAR(name, adv[2].width, i, 0.01);
	snprintf(name, sizeof name, "advance m at %g", size); NEAR(name, adv[3].width, m, 0.01);
	snprintf(name, sizeof name, "line width 0 at %g", size);
	NEAR(name, lineWidth(f, @"Hello, World! The quick brown fox"), line0, 0.05);
	snprintf(name, sizeof name, "line width 3 at %g", size);
	NEAR(name, lineWidth(f, @"Typography 0123456789"), line3, 0.05);
	if (size == 11.5) {
		// NSFont and CoreText agree on the advance.
		NSFont *nf = (__bridge NSFont *) f;
		NEAR("NSFont advancementForGlyph W at 11.5", [nf advancementForGlyph: gl[1]].width, w, 0.01);
	}
	CFRelease(f);
}

// -[NSString sizeWithAttributes:] at 24 pt equals the exact unkerned CTLine width on macOS 10.14.4.
// (Up to 16 pt macOS lays strings out with whole-pixel advances; that is not done here.)
static void stringWidthsAt24(void) {
	NSFont *f = [NSFont fontWithName: @"DejaVuSans" size: 24];
	if (f == nil) { printf("FAIL: NSFont DejaVuSans at 24\n"); failures++; return; }
	NEAR("NSString width iiiiiiiiii at 24",
	     [@"iiiiiiiiii" sizeWithAttributes: @{ NSFontAttributeName: f }].width, 66.6797, 0.01);
	NEAR("NSString width WWWWWWWWWW at 24",
	     [@"WWWWWWWWWW" sizeWithAttributes: @{ NSFontAttributeName: f }].width, 237.3047, 0.01);
}

int main(int argc, char **argv) {
	@autoreleasepool {
		if (argc < 2) { printf("usage: coretext-font-unhinted-advances DejaVuSans.ttf\n"); return 2; }
		const char *path = argv[1];
		// Registered for this process only, so NSFont can find it by name.
		NSURL *url = [NSURL fileURLWithPath: [NSString stringWithUTF8String: path]];
		CTFontManagerRegisterFontsForURL((__bridge CFURLRef) url, kCTFontManagerScopeProcess, NULL);
		advancesAt(path, 9, 6.7676, 8.8989, 2.5005, 8.7671, 152.7056, 113.8359);
		advancesAt(path, 11.5, 8.6475, 11.3708, 3.1951, 11.2024, 195.1238, 145.4570);
		advancesAt(path, 13.2, 9.9258, 13.0518, 3.6674, 12.8584, 223.9682, 166.9594);
		advancesAt(path, 24, 18.0469, 23.7305, 6.6680, 23.3789, 407.2148, 303.5625);

		stringWidthsAt24();

		CTFontRef f = makeFont(path, 11.5);
		NEAR("ascent at 11.5", CTFontGetAscent(f), 10.6746, 0.001);
		NEAR("descent at 11.5", CTFontGetDescent(f), 2.7122, 0.001);
		NEAR("leading at 11.5", CTFontGetLeading(f), 0, 0.001);
		NEAR("capHeight at 11.5", CTFontGetCapHeight(f), 8.4565, 0.15);
		NEAR("xHeight at 11.5", CTFontGetXHeight(f), 6.3621, 0.15);
		CFRelease(f);
		printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
	}
	return failures != 0;
}
