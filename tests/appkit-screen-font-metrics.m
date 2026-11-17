// Copyright (C) 2026 Lubos Dolezel
//
// Screen fonts, whole-pixel layout and pair kerning. On macOS NSLayoutManager lays text out
// with the screen variant of each font by default: glyph advances rounded to whole pixels up
// to 16 pt, exact advances above, and no kerning in the rounded layout; without screen fonts
// the exact advances are used and pair kerning is applied. CoreText lines are always exact and
// kerned. NSString sizing goes through the layout manager. The numbers were measured on
// macOS 10.14.4 with the same font file (DejaVu Sans 2.37, loaded from data, so both systems
// use identical font data); the checks marked quirk_ cover undocumented behaviour (see the
// QUIRK comments in NSFont.m). NSString heights are not checked: macOS returns taller ones
// than the layout manager's line height for this font and the rule is not known.
// usage: appkit-screen-font-metrics tests/fixtures/fonts/DejaVuSans.ttf
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
#define EQUAL(what, got, want) report((got) == (want), what, got, want)

static NSString *strings[] = { @"iiiiiiiiii", @"Hello, World! The quick brown fox", @"AVAVAV To Wa Ty" };

// Rendering modes and advances of the screen variants: size, rendering mode of the font, of
// -screenFont, of the default and of the antialiased integer screen font, advance of "i" for
// the font, the screen font, the default screen font and the antialiased integer one, default
// line height. The antialiased screen font has the font's advance.
static const struct { double size; int fontMode, screenMode, defaultMode, integerMode;
                      double fontAdv, screenAdv, defaultAdv, integerAdv, lineHeight; } api[] = {
	{ 9, 1, 3, 3, 3, 2.5005, 3.0000, 3.0000, 3.0000, 10.0000 },
	{ 10.5, 1, 3, 3, 3, 2.9172, 3.0000, 3.0000, 3.0000, 12.0000 },
	{ 12, 1, 3, 3, 3, 3.3340, 3.0000, 3.0000, 3.0000, 14.0000 },
	{ 13, 1, 3, 3, 3, 3.6118, 4.0000, 4.0000, 4.0000, 15.0000 },
	{ 15.5, 1, 3, 3, 3, 4.3064, 4.0000, 4.0000, 4.0000, 18.0000 },
	{ 16, 1, 3, 3, 3, 4.4453, 4.0000, 4.0000, 4.0000, 19.0000 },
	{ 16.5, 1, 3, 1, 3, 4.5842, 5.0000, 4.5842, 5.0000, 19.0000 },
	{ 18, 1, 3, 1, 3, 5.0010, 5.0000, 5.0010, 5.0000, 21.0000 },
	{ 20, 1, 3, 1, 3, 5.5566, 6.0000, 5.5566, 6.0000, 24.0000 },
};

// Layout: size, NSString width of the three strings, layout manager line height, layout
// manager width without screen fonts (strings 1 and 2), location of glyph 5 with screen fonts
// (string 1) and without (string 2).
static const struct { double size, width0, width1, width2, lineHeight, plain1, plain2, loc1, plainLoc2; } layout[] = {
	{ 9, 30.0000, 160.0000, 81.0000, 10.0, 151.7036, 75.3794, 25.0000, 27.9053 },
	{ 10.5, 30.0000, 175.0000, 91.0000, 12.0, 176.9875, 87.9426, 26.0000, 32.5562 },
	{ 11, 30.0000, 186.0000, 103.0000, 13.0, 185.4155, 92.1304, 28.0000, 34.1064 },
	{ 11.5, 30.0000, 195.0000, 106.0000, 14.0, 193.8435, 96.3181, 29.0000, 35.6567 },
	{ 12, 30.0000, 204.0000, 107.0000, 14.0, 202.2715, 100.5059, 29.0000, 37.2070 },
	{ 13, 40.0000, 221.0000, 119.0000, 15.0, 219.1274, 108.8813, 34.0000, 40.3076 },
	{ 14, 40.0000, 240.0000, 130.0000, 16.0, 235.9834, 117.2568, 37.0000, 43.4082 },
	{ 15, 40.0000, 256.0000, 135.0000, 18.0, 252.8394, 125.6323, 37.0000, 46.5088 },
	{ 16, 40.0000, 270.0000, 146.0000, 19.0, 269.6953, 134.0078, 40.0000, 49.6094 },
	{ 16.5, 45.8423, 278.1233, 138.1956, 19.0, 278.1233, 138.1956, 41.8220, 51.1597 },
	{ 18, 50.0098, 303.4072, 150.7588, 21.0, 303.4072, 150.7588, 45.6240, 55.8105 },
	{ 20, 55.5664, 337.1191, 167.5098, 24.0, 337.1191, 167.5098, 50.6934, 62.0117 },
};

// Sizes above the sampled range: size, NSString width of string 0 and 1.
static const struct { double size, width0, width1; } big[] = {
	{ 22, 61.1230, 370.8311 },
	{ 23, 63.9014, 387.6870 },
	{ 23.5, 65.2905, 396.1150 },
	{ 24, 66.6797, 404.5430 },
};

// CTLine widths of strings 2 and 1: size, string, kerned (default), without kerning.
static const struct { double size; int string; double kerned, plain; } lines[] = {
	{ 9, 2, 75.3794, 81.7646 },
	{ 9, 1, 151.7036, 152.7056 },
	{ 11.5, 2, 96.3181, 104.4771 },
	{ 11.5, 1, 193.8435, 195.1238 },
	{ 13, 2, 108.8813, 118.1045 },
	{ 13, 1, 219.1274, 220.5747 },
	{ 16, 2, 134.0078, 145.3594 },
	{ 16, 1, 269.6953, 271.4766 },
	{ 18, 2, 150.7588, 163.5293 },
	{ 18, 1, 303.4072, 305.4111 },
	{ 24, 2, 201.0117, 218.0391 },
	{ 24, 1, 404.5430, 407.2148 },
};

// Glyph positions of string 0: CTRun positions, and the layout manager's glyph locations with
// and without screen fonts.
typedef struct { double size; double x[15]; } Positions;
static const Positions ctPositions[] = {
	{ 9, { 0.0000, 5.5811, 11.1621, 16.7432, 22.3242, 27.9053, 34.0620, 36.9229, 40.8911, 46.3975, 49.2583, 57.5815, 63.0967, 65.9575, 70.0532 } },
	{ 11.5, { 0.0000, 7.1313, 14.2627, 21.3940, 28.5254, 35.6567, 43.5237, 47.1792, 52.2498, 59.2856, 62.9412, 73.5764, 80.6235, 84.2791, 89.5125 } },
	{ 13, { 0.0000, 8.0615, 16.1230, 24.1846, 32.2461, 40.3076, 49.2007, 53.3330, 59.0649, 67.0186, 71.1509, 83.1733, 91.1396, 95.2720, 101.1880 } },
	{ 16, { 0.0000, 9.9219, 19.8438, 29.7656, 39.6875, 49.6094, 60.5547, 65.6406, 72.6953, 82.4844, 87.5703, 102.3672, 112.1719, 117.2578, 124.5391 } },
	{ 18, { 0.0000, 11.1621, 22.3242, 33.4863, 44.6484, 55.8105, 68.1240, 73.8457, 81.7822, 92.7949, 98.5166, 115.1631, 126.1934, 131.9150, 140.1064 } },
	{ 24, { 0.0000, 14.8828, 29.7656, 44.6484, 59.5312, 74.4141, 90.8320, 98.4609, 109.0430, 123.7266, 131.3555, 153.5508, 168.2578, 175.8867, 186.8086 } },
};
static const Positions screenPositions[] = {
	{ 9, { 0.0000, 6.0000, 12.0000, 18.0000, 24.0000, 30.0000, 36.0000, 39.0000, 44.0000, 50.0000, 53.0000, 62.0000, 68.0000, 71.0000, 76.0000 } },
	{ 11.5, { 0.0000, 8.0000, 16.0000, 24.0000, 32.0000, 40.0000, 48.0000, 52.0000, 59.0000, 66.0000, 70.0000, 81.0000, 88.0000, 92.0000, 99.0000 } },
	{ 13, { 0.0000, 9.0000, 18.0000, 27.0000, 36.0000, 45.0000, 54.0000, 58.0000, 66.0000, 74.0000, 78.0000, 91.0000, 99.0000, 103.0000, 111.0000 } },
	{ 16, { 0.0000, 11.0000, 22.0000, 33.0000, 44.0000, 55.0000, 66.0000, 71.0000, 81.0000, 91.0000, 96.0000, 112.0000, 122.0000, 127.0000, 137.0000 } },
	{ 18, { 0.0000, 11.1621, 22.3242, 33.4863, 44.6484, 55.8105, 68.1240, 73.8457, 81.7822, 92.7949, 98.5166, 115.1631, 126.1934, 131.9150, 140.1064 } },
	{ 24, { 0.0000, 14.8828, 29.7656, 44.6484, 59.5312, 74.4141, 90.8320, 98.4609, 109.0430, 123.7266, 131.3555, 153.5508, 168.2578, 175.8867, 186.8086 } },
};
static const Positions plainPositions[] = {
	{ 9, { 0.0000, 5.5811, 11.1621, 16.7432, 22.3242, 27.9053, 34.0620, 36.9229, 40.8911, 46.3975, 49.2583, 57.5815, 63.0967, 65.9575, 70.0532 } },
	{ 11.5, { 0.0000, 7.1313, 14.2627, 21.3940, 28.5254, 35.6567, 43.5237, 47.1792, 52.2498, 59.2856, 62.9412, 73.5764, 80.6235, 84.2791, 89.5125 } },
	{ 13, { 0.0000, 8.0615, 16.1230, 24.1846, 32.2461, 40.3076, 49.2007, 53.3330, 59.0649, 67.0186, 71.1509, 83.1733, 91.1396, 95.2720, 101.1880 } },
	{ 16, { 0.0000, 9.9219, 19.8438, 29.7656, 39.6875, 49.6094, 60.5547, 65.6406, 72.6953, 82.4844, 87.5703, 102.3672, 112.1719, 117.2578, 124.5391 } },
	{ 18, { 0.0000, 11.1621, 22.3242, 33.4863, 44.6484, 55.8105, 68.1240, 73.8457, 81.7822, 92.7949, 98.5166, 115.1631, 126.1934, 131.9150, 140.1064 } },
	{ 24, { 0.0000, 14.8828, 29.7656, 44.6484, 59.5312, 74.4141, 90.8320, 98.4609, 109.0430, 123.7266, 131.3555, 153.5508, 168.2578, 175.8867, 186.8086 } },
};

static NSFont *fontAt(double size) { return [NSFont fontWithName: @"DejaVuSans" size: size]; }

static NSLayoutManager *layoutManager(NSString *s, NSFont *f, BOOL screen) {
	NSTextStorage *ts = [[NSTextStorage alloc] initWithString: s attributes: @{ NSFontAttributeName: f }];
	NSLayoutManager *lm = [[NSLayoutManager alloc] init];
	NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize: NSMakeSize(1e6, 1e6)];
	[tc setLineFragmentPadding: 0];
	[lm addTextContainer: tc];
	[ts addLayoutManager: lm];
	[lm setUsesScreenFonts: screen];
	[lm glyphRangeForTextContainer: tc];
	return lm;
}

static NSTextContainer *container(NSLayoutManager *lm) { return [[lm textContainers] firstObject]; }

static void screenFontApi(void) {
	for (size_t i = 0; i < sizeof(api) / sizeof(api[0]); i++) {
		char what[96];
		double s = api[i].size;
		NSFont *f = fontAt(s);
		UniChar c = 'i'; CGGlyph cg = 0;
		CTFontRef ct = CTFontCreateWithName((__bridge CFStringRef) [f fontName], s, NULL);
		CTFontGetGlyphsForCharacters(ct, &c, &cg, 1);
		CFRelease(ct);
		NSGlyph g = cg;
		NSFont *sf = [f screenFont], *sfd = [f screenFontWithRenderingMode: NSFontDefaultRenderingMode];
		NSFont *sfa = [f screenFontWithRenderingMode: NSFontAntialiasedIntegerAdvancementsRenderingMode];
		NSFont *sfp = [f screenFontWithRenderingMode: NSFontAntialiasedRenderingMode];
		snprintf(what, sizeof what, "%g: font rendering mode", s);
		EQUAL(what, (int) [f renderingMode], api[i].fontMode);
		snprintf(what, sizeof what, "%g: quirk_screenFont is antialiased integer advancements", s);
		EQUAL(what, (int) [sf renderingMode], api[i].screenMode);
		snprintf(what, sizeof what, "%g: quirk_default screen font mode", s);
		EQUAL(what, (int) [sfd renderingMode], api[i].defaultMode);
		snprintf(what, sizeof what, "%g: integer screen font mode", s);
		EQUAL(what, (int) [sfa renderingMode], api[i].integerMode);
		snprintf(what, sizeof what, "%g: antialiased screen font mode", s);
		EQUAL(what, (int) [sfp renderingMode], (int) NSFontAntialiasedRenderingMode);
		snprintf(what, sizeof what, "%g: screen font keeps name and size", s);
		report([[sf fontName] isEqualToString: [f fontName]] && [sf pointSize] == s, what, [sf pointSize], s);
		snprintf(what, sizeof what, "%g: font advance stays exact", s);
		NEAR(what, [f advancementForGlyph: g].width, api[i].fontAdv, 0.001);
		snprintf(what, sizeof what, "%g: screen font advance", s);
		NEAR(what, [sf advancementForGlyph: g].width, api[i].screenAdv, 0.001);
		snprintf(what, sizeof what, "%g: default screen font advance", s);
		NEAR(what, [sfd advancementForGlyph: g].width, api[i].defaultAdv, 0.001);
		snprintf(what, sizeof what, "%g: integer screen font advance", s);
		NEAR(what, [sfa advancementForGlyph: g].width, api[i].integerAdv, 0.001);
		snprintf(what, sizeof what, "%g: antialiased screen font advance is exact", s);
		NEAR(what, [sfp advancementForGlyph: g].width, api[i].fontAdv, 0.001);
		NSSize adv;
		[sf getAdvancements: &adv forGlyphs: &g count: 1];
		snprintf(what, sizeof what, "%g: getAdvancements of the screen font", s);
		NEAR(what, adv.width, api[i].screenAdv, 0.001);
		snprintf(what, sizeof what, "%g: quirk_line height is the sum of the rounded components", s);
		NEAR(what, [f defaultLineHeightForFont], api[i].lineHeight, 0);
		snprintf(what, sizeof what, "%g: screen font line height", s);
		NEAR(what, [sf defaultLineHeightForFont], api[i].lineHeight, 0);
	}
	NSFont *f = fontAt(12);
	report([f screenFontWithRenderingMode: NSFontDefaultRenderingMode] == [f screenFontWithRenderingMode: NSFontDefaultRenderingMode],
	       "screen font is cached", 0, 0);
	report([NSFont fontWithName: @"DejaVuSans" size: 12] == f && [f renderingMode] == NSFontAntialiasedRenderingMode,
	       "fontWithName:size: still returns the ordinary font", 0, 0);
	report([[f screenFont] screenFontWithRenderingMode: NSFontAntialiasedIntegerAdvancementsRenderingMode] == [f screenFont],
	       "screen font of a screen font of the same mode is itself", 0, 0);
}

static void stringAndLayoutWidths(void) {
	for (size_t i = 0; i < sizeof(layout) / sizeof(layout[0]); i++) {
		char what[96];
		double s = layout[i].size;
		NSFont *f = fontAt(s);
		NSDictionary *at = @{ NSFontAttributeName: f };
		snprintf(what, sizeof what, "%g: NSString width of string 0", s);
		NEAR(what, [strings[0] sizeWithAttributes: at].width, layout[i].width0, 0.01);
		snprintf(what, sizeof what, "%g: NSString width of string 1", s);
		NEAR(what, [strings[1] sizeWithAttributes: at].width, layout[i].width1, 0.01);
		snprintf(what, sizeof what, "%g: NSString width of string 2", s);
		NEAR(what, [strings[2] sizeWithAttributes: at].width, layout[i].width2, 0.01);
		NSLayoutManager *lm = layoutManager(strings[1], f, YES);
		snprintf(what, sizeof what, "%g: layout manager line height", s);
		NEAR(what, [lm lineFragmentRectForGlyphAtIndex: 0 effectiveRange: NULL].size.height, layout[i].lineHeight, 0);
		snprintf(what, sizeof what, "%g: layout manager defaultLineHeightForFont", s);
		NEAR(what, [lm defaultLineHeightForFont: f], layout[i].lineHeight, 0);
		snprintf(what, sizeof what, "%g: screen layout width of string 1", s);
		NEAR(what, [lm usedRectForTextContainer: container(lm)].size.width, layout[i].width1, 0.01);
		snprintf(what, sizeof what, "%g: location of glyph 5, screen", s);
		NEAR(what, [lm locationForGlyphAtIndex: 5].x, layout[i].loc1, 0.01);
		NSLayoutManager *plain = layoutManager(strings[1], f, NO);
		snprintf(what, sizeof what, "%g: layout width of string 1 without screen fonts (exact, kerned)", s);
		NEAR(what, [plain usedRectForTextContainer: container(plain)].size.width, layout[i].plain1, 0.01);
		plain = layoutManager(strings[2], f, NO);
		snprintf(what, sizeof what, "%g: layout width of string 2 without screen fonts", s);
		NEAR(what, [plain usedRectForTextContainer: container(plain)].size.width, layout[i].plain2, 0.01);
		snprintf(what, sizeof what, "%g: location of glyph 5 without screen fonts", s);
		NEAR(what, [plain locationForGlyphAtIndex: 5].x, layout[i].plainLoc2, 0.01);
	}
	for (size_t i = 0; i < sizeof(big) / sizeof(big[0]); i++) {
		char what[96];
		NSFont *f = fontAt(big[i].size);
		NSDictionary *at = @{ NSFontAttributeName: f };
		snprintf(what, sizeof what, "%g: NSString width of string 0", big[i].size);
		NEAR(what, [strings[0] sizeWithAttributes: at].width, big[i].width0, 0.01);
		snprintf(what, sizeof what, "%g: NSString width of string 1 (exact, kerned)", big[i].size);
		NEAR(what, [strings[1] sizeWithAttributes: at].width, big[i].width1, 0.01);
	}
}

static void kerning(void) {
	for (size_t i = 0; i < sizeof(lines) / sizeof(lines[0]); i++) {
		char what[96];
		NSFont *f = fontAt(lines[i].size);
		NSString *s = strings[lines[i].string];
		NSDictionary *no = @{ NSFontAttributeName: f, (id) kCTKernAttributeName: @0 };
		CTLineRef l1 = CTLineCreateWithAttributedString((CFAttributedStringRef) [[NSAttributedString alloc] initWithString: s attributes: @{ NSFontAttributeName: f }]);
		CTLineRef l2 = CTLineCreateWithAttributedString((CFAttributedStringRef) [[NSAttributedString alloc] initWithString: s attributes: no]);
		snprintf(what, sizeof what, "%g string %d: CTLine width is kerned by default", lines[i].size, lines[i].string);
		NEAR(what, CTLineGetTypographicBounds(l1, NULL, NULL, NULL), lines[i].kerned, 0.002);
		snprintf(what, sizeof what, "%g string %d: CTLine width without kerning", lines[i].size, lines[i].string);
		NEAR(what, CTLineGetTypographicBounds(l2, NULL, NULL, NULL), lines[i].plain, 0.002);
		CFRelease(l1); CFRelease(l2);
	}
	for (size_t i = 0; i < sizeof(ctPositions) / sizeof(ctPositions[0]); i++) {
		char what[96];
		double s = ctPositions[i].size;
		NSFont *f = fontAt(s);
		CTLineRef l = CTLineCreateWithAttributedString((CFAttributedStringRef) [[NSAttributedString alloc] initWithString: strings[2] attributes: @{ NSFontAttributeName: f }]);
		CTRunRef run = (CTRunRef) CFArrayGetValueAtIndex(CTLineGetGlyphRuns(l), 0);
		CGPoint p[15];
		CTRunGetPositions(run, CFRangeMake(0, 15), p);
		double worst = 0;
		for (int g = 0; g < 15; g++) worst = fmax(worst, fabs(p[g].x - ctPositions[i].x[g]));
		snprintf(what, sizeof what, "%g: CTRun glyph positions of a kerned line", s);
		NEAR(what, worst, 0, 0.002);
		CFRelease(l);

		for (int screen = 0; screen < 2; screen++) {
			const char *mode = screen ? "screen fonts" : "exact advances";
			NSLayoutManager *lm = layoutManager(strings[2], f, screen);
			const Positions *want = screen ? &screenPositions[i] : &plainPositions[i];
			worst = 0;
			for (int g = 0; g < 15; g++) worst = fmax(worst, fabs([lm locationForGlyphAtIndex: g].x - want->x[g]));
			snprintf(what, sizeof what, "%g: layout manager glyph locations, %s", s, mode);
			NEAR(what, worst, 0, 0.002);
			// The glyph rects and the hit test use the same advances as the locations.
			NSRect r = [lm boundingRectForGlyphRange: NSMakeRange(0, 15) inTextContainer: container(lm)];
			NSRect used = [lm usedRectForTextContainer: container(lm)];
			snprintf(what, sizeof what, "%g: glyph rect width equals used width, %s", s, mode);
			NEAR(what, r.size.width, used.size.width, 0.002);
			int wrong = 0;
			for (int g = 0; g < 15; g++) {
				double x0 = want->x[g], x1 = g < 14 ? want->x[g + 1] : used.size.width;
				if (x1 - x0 < 0.5) continue;
				CGFloat frac;
				NSUInteger hit = [lm glyphIndexForPoint: NSMakePoint((x0 + x1) / 2, 5) inTextContainer: container(lm) fractionOfDistanceThroughGlyph: &frac];
				if (hit != (NSUInteger) g) wrong++;
			}
			snprintf(what, sizeof what, "%g: hit test of glyph midpoints, %s", s, mode);
			EQUAL(what, wrong, 0);
		}
	}
	// Setting usesScreenFonts after layout lays the text out again.
	NSLayoutManager *lm = layoutManager(strings[1], fontAt(11.5), YES);
	EQUAL("usesScreenFonts default", (int) [lm usesScreenFonts], 1);
	NEAR("width with screen fonts", [lm usedRectForTextContainer: container(lm)].size.width, 195, 0.01);
	[lm setUsesScreenFonts: NO];
	EQUAL("usesScreenFonts off", (int) [lm usesScreenFonts], 0);
	[lm glyphRangeForTextContainer: container(lm)];
	NEAR("width after switching screen fonts off", [lm usedRectForTextContainer: container(lm)].size.width, 193.8435, 0.01);
}

int main(int argc, char **argv) {
	@autoreleasepool {
		if (argc < 2) { printf("usage: appkit-screen-font-metrics DejaVuSans.ttf\n"); return 2; }
		NSURL *url = [NSURL fileURLWithPath: [NSString stringWithUTF8String: argv[1]]];
		CTFontManagerRegisterFontsForURL((__bridge CFURLRef) url, kCTFontManagerScopeProcess, NULL);
		[NSApplication sharedApplication];
		screenFontApi();
		stringAndLayoutWidths();
		kerning();
		printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
	}
	return failures != 0;
}
