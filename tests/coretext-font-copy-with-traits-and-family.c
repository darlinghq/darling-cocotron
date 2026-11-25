/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CTFontCreateCopyWithSymbolicTraits makes a font in the family of the original with the
 * symbolic traits given, and CTFontCreateCopyWithFamily makes a font in the family given with
 * the traits of the original, or NULL when none is found. For both, a size of 0.0 keeps the
 * original's size. macOS 26.1 departs from that documented NULL for CTFontCreateCopyWithFamily when
 * the family lacks the original's bold or italic (QUIRK checks below):
 * https://developer.apple.com/documentation/coretext/ctfontcreatecopywithsymbolictraits(_:_:_:_:_:)
 * https://developer.apple.com/documentation/coretext/ctfontcreatecopywithfamily(_:_:_:_:)
 *
 * The test finds suitable families among the installed fonts, so it works with whatever fonts
 * the system has, and prints SKIP for a check the installed fonts cannot exercise. The documented
 * results are the family, the traits, the size and NULL. How value and mask combine, which bits
 * count and which of several matching faces is chosen are not documented; the checks that
 * rely on the implementation's reading of them say so (GUESS) and run only where it applies.
 *
 * Usage: coretext-font-copy-with-traits-and-family
 * Prints PASS/FAIL/SKIP lines; exit status 1 on failure.
 */
#include <ApplicationServices/ApplicationServices.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void expect(int ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

static const CTFontSymbolicTraits styleBits = kCTFontTraitItalic | kCTFontTraitBold
		| kCTFontTraitExpanded | kCTFontTraitCondensed | kCTFontTraitMonoSpace;

static CTFontRef faceFont(CFArrayRef faces, CFIndex i)
{
	return CTFontCreateWithFontDescriptor((CTFontDescriptorRef) CFArrayGetValueAtIndex(faces, i),
			14, NULL);
}

static int sameFamily(CTFontRef a, CTFontRef b)
{
	CFStringRef fa = CTFontCopyFamilyName(a), fb = CTFontCopyFamilyName(b);
	int same = fa != NULL && fb != NULL && CFEqual(fa, fb);
	if (fa != NULL)
		CFRelease(fa);
	if (fb != NULL)
		CFRelease(fb);
	return same;
}

static int familyAllHave(CFArrayRef faces, CFIndex count, CTFontRef member, CTFontSymbolicTraits bit)
{
	for (CFIndex i = 0; i < count; i++) {
		CTFontRef f = faceFont(faces, i);
		int bad = f != NULL && sameFamily(member, f) && !(CTFontGetSymbolicTraits(f) & bit);
		if (f != NULL)
			CFRelease(f);
		if (bad)
			return 0;
	}
	return 1;
}

// The first face whose style bits equal `value`, outside the family of `notIn` when that is not
// NULL, and, when `wholeFamily` is not 0, in a family all of whose faces have that bit.
static CTFontRef findFace(CFArrayRef faces, CFIndex count, CTFontSymbolicTraits value,
		CTFontRef notIn, CTFontSymbolicTraits wholeFamily)
{
	for (CFIndex i = 0; i < count; i++) {
		CTFontRef f = faceFont(faces, i);
		if (f != NULL && (CTFontGetSymbolicTraits(f) & styleBits) == value
				&& (notIn == NULL || !sameFamily(f, notIn))
				&& (wholeFamily == 0 || familyAllHave(faces, count, f, wholeFamily)))
			return f;
		if (f != NULL)
			CFRelease(f);
	}
	return NULL;
}

static void release(CTFontRef f)
{
	if (f != NULL)
		CFRelease(f);
}

static CGFloat weightOf(CTFontRef f)
{
	CGFloat weight = 0;
	CFDictionaryRef traits = CTFontCopyTraits(f);
	CFNumberRef number = traits != NULL ? CFDictionaryGetValue(traits, kCTFontWeightTrait) : NULL;
	if (number != NULL)
		CFNumberGetValue(number, kCFNumberCGFloatType, &weight);
	if (traits != NULL)
		CFRelease(traits);
	return weight;
}

// The bits CTFontCreateCopyWithSymbolicTraits compares inside a family.
static const CTFontSymbolicTraits comparedBits = kCTFontTraitItalic | kCTFontTraitBold
		| kCTFontTraitExpanded | kCTFontTraitCondensed | kCTFontTraitColorGlyphs;

// What the checks over all installed faces need of each face, read once so that the checks do not
// create a font for every pair of faces.
typedef struct {
	CTFontRef font;
	CFStringRef family, postScriptName;
	CTFontSymbolicTraits traits;
	CGFloat weight;
} FaceInfo;

static FaceInfo *collectFaces(CFArrayRef faces, CFIndex count)
{
	FaceInfo *infos = calloc(count > 0 ? count : 1, sizeof(FaceInfo));
	for (CFIndex i = 0; i < count; i++) {
		CTFontRef f = faceFont(faces, i);
		infos[i].font = f;
		if (f != NULL) {
			infos[i].family = CTFontCopyFamilyName(f);
			infos[i].postScriptName = CTFontCopyPostScriptName(f);
			infos[i].traits = CTFontGetSymbolicTraits(f);
			infos[i].weight = weightOf(f);
		}
	}
	return infos;
}

static void releaseFaces(FaceInfo *infos, CFIndex count)
{
	for (CFIndex i = 0; i < count; i++) {
		release(infos[i].font);
		if (infos[i].family != NULL)
			CFRelease(infos[i].family);
		if (infos[i].postScriptName != NULL)
			CFRelease(infos[i].postScriptName);
	}
	free(infos);
}

static int sameFamilyInfo(const FaceInfo *a, const FaceInfo *b)
{
	return a->family != NULL && b->family != NULL && CFEqual(a->family, b->family);
}

// Whether some face of the family of `member` has the bit.
static int familyAny(const FaceInfo *infos, CFIndex count, const FaceInfo *member, CTFontSymbolicTraits bit)
{
	for (CFIndex i = 0; i < count; i++)
		if (infos[i].font != NULL && sameFamilyInfo(member, &infos[i]) && (infos[i].traits & bit))
			return 1;
	return 0;
}

static int hasPostScriptName(CTFontRef a, CFStringRef nameOfB)
{
	CFStringRef na = CTFontCopyPostScriptName(a);
	int same = na != NULL && nameOfB != NULL && CFEqual(na, nameOfB);
	if (na != NULL)
		CFRelease(na);
	return same;
}

// QUIRK (macOS 26.7.3 and 10.14.4, probe 639.E.nochange): a request that changes no trait (value 0, mask 0)
// returns the original face itself, even where another face of the family has the same traits and weight
// (Avenir-Roman and Avenir-Book). SKIP when no installed family has such an equal.
static void checkEmptyMaskKeepsTheFace(const FaceInfo *infos, CFIndex count)
{
	int tied = 0, wrong = 0;
	for (CFIndex i = 0; i < count; i++) {
		const FaceInfo *f = &infos[i];
		int hasEqual = 0;
		for (CFIndex j = 0; f->font != NULL && j < count && !hasEqual; j++) {
			const FaceInfo *g = &infos[j];
			hasEqual = j != i && g->font != NULL && sameFamilyInfo(f, g)
					&& !(f->postScriptName != NULL && g->postScriptName != NULL
							&& CFEqual(f->postScriptName, g->postScriptName))
					&& (g->traits & comparedBits) == (f->traits & comparedBits)
					&& fabs(g->weight - f->weight) < 1e-6;
		}
		if (hasEqual) {
			tied++;
			CTFontRef copy = CTFontCreateCopyWithSymbolicTraits(f->font, 0, NULL, 0, 0);
			if (copy == NULL || !hasPostScriptName(copy, f->postScriptName))
				wrong++;
			release(copy);
		}
	}
	if (tied == 0)
		printf("SKIP no installed family has two faces equal in traits and weight\n");
	else
		expect(wrong == 0, "QUIRK: an empty mask returns the original face among faces equal in traits and weight");
}

// QUIRK (macOS 26.1, probe 639): every installed face whose weight trait is 0.3 or more has the bold
// trait (a Semibold or Demibold face has it). SKIP when no installed face weighs between 0.3 and 0.4,
// the faces this threshold decides.
static void checkBoldThreshold(const FaceInfo *infos, CFIndex count)
{
	int semibold = 0, wrong = 0;
	for (CFIndex i = 0; i < count; i++) {
		if (infos[i].font == NULL || infos[i].weight < 0.3 - 1e-6)
			continue;
		if (infos[i].weight < 0.4 - 1e-6)
			semibold++;
		if (!(infos[i].traits & kCTFontTraitBold))
			wrong++;
	}
	if (semibold == 0)
		printf("SKIP no installed face has a weight between 0.3 and 0.4\n");
	else
		expect(wrong == 0, "QUIRK: faces of weight 0.3 and more have the bold trait");
}

// QUIRK (macOS 26.1, probe 639.E): turning the bold trait on from a face without it picks, among the
// family's faces with the resulting traits, the one whose weight is nearest 0.4 (the Bold weight class),
// not the one nearest the original's weight; turning it off aims at weight 0.0. Checked for every
// installed face; SKIP unless some family makes the two rules differ (a family with Semibold, weight 0.3,
// and Bold, 0.4, faces, which needs the bold threshold above).
static void checkBoldWeightTarget(const FaceInfo *infos, CFIndex count, int turnOn)
{
	const CGFloat target = turnOn ? 0.4 : 0;
	int discriminating = 0, wrong = 0;
	for (CFIndex i = 0; i < count; i++) {
		const FaceInfo *f = &infos[i];
		if (f->font == NULL || ((f->traits & kCTFontTraitBold) != 0) != !turnOn)
			continue;
		CTFontRef copy = CTFontCreateCopyWithSymbolicTraits(f->font, 0, NULL, turnOn ? kCTFontTraitBold : 0,
				kCTFontTraitBold);
		if (copy == NULL)
			continue;
		CTFontSymbolicTraits wanted = CTFontGetSymbolicTraits(copy) & comparedBits;
		CGFloat best = 9, nearOriginal = 9, weightNearOriginal = 0;
		for (CFIndex j = 0; j < count; j++) {
			const FaceInfo *g = &infos[j];
			if (g->font == NULL || !sameFamilyInfo(f, g) || (g->traits & comparedBits) != wanted)
				continue;
			if (fabs(g->weight - target) < best)
				best = fabs(g->weight - target);
			if (fabs(g->weight - f->weight) < nearOriginal) {
				nearOriginal = fabs(g->weight - f->weight);
				weightNearOriginal = g->weight;
			}
		}
		if (fabs(fabs(weightOf(copy) - target) - best) > 1e-6)
			wrong++;
		if (fabs(fabs(weightNearOriginal - target) - best) > 1e-6)
			discriminating++;
		CFRelease(copy);
	}
	const char *what = turnOn ? "QUIRK: setting bold aims at weight 0.4, not the original's weight"
			: "QUIRK: clearing bold aims at weight 0.0, not the original's weight";
	if (discriminating == 0)
		printf("SKIP no installed family tells the weight rules apart (%s)\n", what);
	else
		expect(wrong == 0, what);
}

int main(void)
{
	CTFontCollectionRef collection = CTFontCollectionCreateFromAvailableFonts(NULL);
	CFArrayRef faces = CTFontCollectionCreateMatchingFontDescriptors(collection);
	CFIndex count = faces != NULL ? CFArrayGetCount(faces) : 0;
	expect(count > 0, "the system lists faces");

	// A plain face with a bold-only face in its family.
	CTFontRef plain = NULL, bold = NULL;
	for (CFIndex i = 0; i < count && plain == NULL; i++) {
		CTFontRef a = faceFont(faces, i);
		if (a != NULL && (CTFontGetSymbolicTraits(a) & styleBits) == 0) {
			for (CFIndex j = 0; j < count && bold == NULL; j++) {
				CTFontRef b = faceFont(faces, j);
				if (b != NULL && sameFamily(a, b)
						&& (CTFontGetSymbolicTraits(b) & styleBits) == kCTFontTraitBold)
					bold = b;
				else
					release(b);
			}
			if (bold != NULL)
				plain = a;
		}
		if (plain == NULL)
			release(a);
	}
	CTFontRef otherPlain = findFace(faces, count, 0, plain, 0);
	// A monospace family, and a family whose every face is condensed.
	CTFontRef mono = findFace(faces, count, kCTFontTraitMonoSpace, plain, kCTFontTraitMonoSpace);
	CTFontRef condensed = findFace(faces, count, kCTFontTraitCondensed, plain, kCTFontTraitCondensed);
	// A family with no italic face.
	CTFontRef noItalic = NULL;
	for (CFIndex i = 0; i < count && noItalic == NULL; i++) {
		CTFontRef a = faceFont(faces, i);
		CTFontRef italic = NULL;
		if (a != NULL) {
			for (CFIndex j = 0; j < count && italic == NULL; j++) {
				CTFontRef b = faceFont(faces, j);
				if (b != NULL && sameFamily(a, b) && (CTFontGetSymbolicTraits(b) & kCTFontTraitItalic))
					italic = b;
				else
					release(b);
			}
		}
		if (italic == NULL && a != NULL)
			noItalic = a;
		else
			release(a);
		release(italic);
	}

	if (plain == NULL) {
		printf("SKIP no family with a plain and a bold face is installed\n");
	} else {
		CTFontRef copy = CTFontCreateCopyWithSymbolicTraits(plain, 0, NULL, kCTFontTraitBold,
				kCTFontTraitBold);
		expect(copy != NULL, "bold copy of a plain face exists");
		if (copy != NULL) {
			expect(sameFamily(plain, copy), "bold copy is in the original's family");
			expect((CTFontGetSymbolicTraits(copy) & styleBits) == kCTFontTraitBold,
					"bold copy has the bold trait and no other style trait");
			expect(CTFontGetSize(copy) == CTFontGetSize(plain), "size 0.0 keeps the original size");
			CFRelease(copy);
		}

		copy = CTFontCreateCopyWithSymbolicTraits(plain, 21, NULL, kCTFontTraitBold, kCTFontTraitBold);
		expect(copy != NULL && CTFontGetSize(copy) == 21, "an explicit size is used");
		release(copy);

		// QUIRK (macOS 26.7.3, 10.14.4 and 26.1, probe 639.B.size): a negative size keeps the original's size.
		copy = CTFontCreateCopyWithSymbolicTraits(plain, -5, NULL, kCTFontTraitBold, kCTFontTraitBold);
		expect(copy != NULL && CTFontGetSize(copy) == CTFontGetSize(plain),
				"QUIRK: a negative size keeps the original size");
		release(copy);

		// QUIRK (macOS 26.7.3 and 10.14.4, probe ctvert.c): the vertical bit is not looked for but is
		// carried into the copy's traits, and no later copy loses it, except a copy into another family.
		copy = CTFontCreateCopyWithSymbolicTraits(plain, 0, NULL, kCTFontTraitVertical, kCTFontTraitVertical);
		expect(copy != NULL && sameFamily(plain, copy)
				&& (CTFontGetSymbolicTraits(copy) & kCTFontTraitVertical),
				"QUIRK: setting the vertical trait reaches the copy's traits");
		CTFontRef again = copy != NULL
				? CTFontCreateCopyWithSymbolicTraits(copy, 0, NULL, 0, kCTFontTraitVertical) : NULL;
		expect(again != NULL && (CTFontGetSymbolicTraits(again) & kCTFontTraitVertical),
				"QUIRK: clearing the vertical trait does not remove it from a copy that has it");
		release(again);
		again = copy != NULL ? CTFontCreateCopyWithSymbolicTraits(copy, 0, NULL, 0, 0) : NULL;
		expect(again != NULL && (CTFontGetSymbolicTraits(again) & kCTFontTraitVertical),
				"QUIRK: an empty mask keeps the vertical trait");
		release(again);
		again = copy != NULL ? CTFontCreateCopyWithSymbolicTraits(copy, 14, NULL, kCTFontTraitBold, kCTFontTraitBold) : NULL;
		expect(again != NULL && (CTFontGetSymbolicTraits(again) & kCTFontTraitVertical),
				"QUIRK: a copy with a new size and the bold trait keeps the vertical trait");
		release(again);
		again = copy != NULL ? CTFontCreateCopyWithAttributes(copy, 0, NULL, NULL) : NULL;
		expect(again != NULL && (CTFontGetSymbolicTraits(again) & kCTFontTraitVertical),
				"QUIRK: CTFontCreateCopyWithAttributes keeps the vertical trait");
		release(again);
		release(copy);
		copy = CTFontCreateCopyWithSymbolicTraits(plain, 0, NULL, 0, kCTFontTraitVertical);
		expect(copy != NULL && !(CTFontGetSymbolicTraits(copy) & kCTFontTraitVertical),
				"observed (639.C.clear-vertical): clearing the vertical trait of a face without it leaves it without");
		release(copy);

		// GUESS (value and mask are not defined by the documentation): the mask selects the
		// bits of the value that replace the original's.
		copy = CTFontCreateCopyWithSymbolicTraits(plain, 0, NULL, kCTFontTraitBold | kCTFontTraitItalic,
				kCTFontTraitBold);
		expect(copy != NULL && !(CTFontGetSymbolicTraits(copy) & kCTFontTraitItalic),
				"GUESS: bits of the value outside the mask are ignored");
		release(copy);

		copy = CTFontCreateCopyWithSymbolicTraits(bold, 0, NULL, 0, kCTFontTraitBold);
		expect(copy != NULL && sameFamily(bold, copy)
				&& !(CTFontGetSymbolicTraits(copy) & kCTFontTraitBold),
				"GUESS: clearing the bold trait under the mask gives a face without it");
		release(copy);
	}

	if (noItalic == NULL) {
		printf("SKIP every installed family has an italic face\n");
	} else {
		CTFontRef copy = CTFontCreateCopyWithSymbolicTraits(noItalic, 0, NULL, kCTFontTraitItalic,
				kCTFontTraitItalic);
		expect(copy == NULL, "NULL when the family has no face with the traits");
		release(copy);
	}

	if (plain == NULL || otherPlain == NULL) {
		printf("SKIP fewer than two families with a plain face are installed\n");
	} else {
		CFStringRef family = CTFontCopyFamilyName(otherPlain);
		CTFontRef copy = CTFontCreateCopyWithFamily(plain, 33, NULL, family);
		expect(copy != NULL && CTFontGetSize(copy) == 33 && sameFamily(copy, otherPlain),
				"a plain face copied to another family, explicit size");
		release(copy);
		copy = CTFontCreateCopyWithFamily(plain, 0, NULL, family);
		expect(copy != NULL && CTFontGetSize(copy) == CTFontGetSize(plain),
				"size 0.0 keeps the original size");
		release(copy);
		CFRelease(family);
	}

	// Monospace, condensed and expanded describe whole families, so a copy to such a family
	// from a family without them must be found (GUESS: its italic and bold traits are kept).
	if (plain == NULL || mono == NULL) {
		printf("SKIP no plain face and monospace family pair is installed\n");
	} else {
		CFStringRef family = CTFontCopyFamilyName(mono);
		CTFontRef copy = CTFontCreateCopyWithFamily(plain, 0, NULL, family);
		expect(copy != NULL && sameFamily(copy, mono)
				&& (CTFontGetSymbolicTraits(copy) & kCTFontTraitMonoSpace)
				&& !(CTFontGetSymbolicTraits(copy) & (kCTFontTraitBold | kCTFontTraitItalic)),
				"a plain face copied to a monospace family");
		release(copy);
		CFRelease(family);
		family = CTFontCopyFamilyName(plain);
		copy = CTFontCreateCopyWithFamily(mono, 0, NULL, family);
		expect(copy != NULL && sameFamily(copy, plain), "a monospace face copied to a proportional family");
		release(copy);
		CFRelease(family);
	}
	if (plain == NULL || condensed == NULL) {
		printf("SKIP no family whose faces are all condensed is installed\n");
	} else {
		CFStringRef family = CTFontCopyFamilyName(condensed);
		CTFontRef copy = CTFontCreateCopyWithFamily(plain, 0, NULL, family);
		expect(copy != NULL && sameFamily(copy, condensed)
				&& (CTFontGetSymbolicTraits(copy) & kCTFontTraitCondensed),
				"a plain face copied to a family of condensed faces");
		release(copy);
		CFRelease(family);
	}

	if (plain != NULL) {
		CTFontRef copy = CTFontCreateCopyWithFamily(plain, 0, NULL, CFSTR("No Such Family 7F3A91"));
		expect(copy == NULL, "NULL when the family is not found");
		release(copy);
	}

	// Observed on macOS 26.7.3 and Mac OS X 10.14.4: setting the color-glyph trait on a family without a color
	// face gives NULL, while the monospace trait is not compared (the font comes back).
	if (plain != NULL) {
		CTFontRef copy = CTFontCreateCopyWithSymbolicTraits(plain, 0, NULL, kCTFontTraitColorGlyphs,
				kCTFontTraitColorGlyphs);
		expect(copy == NULL, "observed: NULL when the color-glyph trait is requested and no face has it");
		release(copy);
		copy = CTFontCreateCopyWithSymbolicTraits(plain, 0, NULL, kCTFontTraitMonoSpace, kCTFontTraitMonoSpace);
		expect(copy != NULL && sameFamily(plain, copy),
				"observed: the monospace trait is not compared within a family");
		release(copy);

		// Observed: the cascade list of the original is carried over to the copy, by both functions.
		CFStringRef family = CTFontCopyFamilyName(plain);
		CTFontDescriptorRef fallback = CTFontDescriptorCreateWithNameAndSize(CFSTR("Courier"), 12);
		CFArrayRef list = CFArrayCreate(NULL, (const void **) &fallback, 1, &kCFTypeArrayCallBacks);
		CFDictionaryRef attributes = CFDictionaryCreate(NULL, (const void **) &kCTFontCascadeListAttribute,
				(const void **) &list, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(attributes);
		CTFontRef withCascade = CTFontCreateWithName(CFSTR("Helvetica"), 14, NULL);
		CTFontRef carrier = CTFontCreateCopyWithAttributes(withCascade, 14, NULL, descriptor);
		CTFontRef byTraits = CTFontCreateCopyWithSymbolicTraits(carrier, 20, NULL, 0, 0);
		CTFontRef byFamily = CTFontCreateCopyWithFamily(carrier, 0, NULL, family);
		CTFontRef fonts[2] = { byTraits, byFamily };
		for (int i = 0; i < 2; i++) {
			CTFontDescriptorRef copied = fonts[i] != NULL ? CTFontCopyFontDescriptor(fonts[i]) : NULL;
			CFArrayRef cascade = copied != NULL
					? CTFontDescriptorCopyAttribute(copied, kCTFontCascadeListAttribute) : NULL;
			expect(cascade != NULL && CFArrayGetCount(cascade) == 1,
					i == 0 ? "observed: the cascade list is carried over by CreateCopyWithSymbolicTraits"
					       : "observed: the cascade list is carried over by CreateCopyWithFamily");
			if (cascade != NULL)
				CFRelease(cascade);
			if (copied != NULL)
				CFRelease(copied);
		}
		release(byTraits);
		release(byFamily);
		release(carrier);
		release(withCascade);
		CFRelease(descriptor);
		CFRelease(attributes);
		CFRelease(list);
		CFRelease(fallback);
		CFRelease(family);
	}

	FaceInfo *infos = collectFaces(faces, count);
	checkEmptyMaskKeepsTheFace(infos, count);
	checkBoldThreshold(infos, count);
	checkBoldWeightTarget(infos, count, 1);
	checkBoldWeightTarget(infos, count, 0);

	// QUIRK (macOS 26.7.3, 10.14.4 and 26.1, probe 639.F.family): a family without a face of the original's boldness
	// still gives a face; only a family that does not exist gives NULL. The structure is checked, not
	// which face a family of several gives. GUESS: italic is kept when the family has it, then
	// the nearest weight.
	const FaceInfo *boldFace = NULL, *noBoldFamily = NULL, *boldItalicFace = NULL, *noBoldItalicFamily = NULL;
	for (CFIndex i = 0; i < count; i++) {
		const FaceInfo *f = &infos[i];
		if (f->font == NULL)
			continue;
		if (boldFace == NULL && (f->traits & styleBits) == kCTFontTraitBold)
			boldFace = f;
		if (boldItalicFace == NULL && (f->traits & styleBits) == (kCTFontTraitBold | kCTFontTraitItalic))
			boldItalicFace = f;
		if (!familyAny(infos, count, f, kCTFontTraitBold)) {
			if (noBoldFamily == NULL)
				noBoldFamily = f;
			if (noBoldItalicFamily == NULL && familyAny(infos, count, f, kCTFontTraitItalic))
				noBoldItalicFamily = f;
		}
	}
	if (boldFace == NULL || noBoldFamily == NULL) {
		printf("SKIP no bold face and family without a bold face are installed\n");
	} else {
		CTFontRef copy = CTFontCreateCopyWithFamily(boldFace->font, 0, NULL, noBoldFamily->family);
		expect(copy != NULL && sameFamily(copy, noBoldFamily->font),
				"QUIRK: a bold face copied to a family with no bold face gives a face of that family");
		release(copy);
	}
	if (boldItalicFace == NULL || noBoldItalicFamily == NULL) {
		printf("SKIP no bold italic face and family with italic but no bold faces are installed\n");
	} else {
		CTFontRef copy = CTFontCreateCopyWithFamily(boldItalicFace->font, 0, NULL, noBoldItalicFamily->family);
		expect(copy != NULL && sameFamily(copy, noBoldItalicFamily->font)
				&& (CTFontGetSymbolicTraits(copy) & kCTFontTraitItalic),
				"GUESS: a bold italic face copied to a family with italic faces but no bold face keeps the italic");
		release(copy);
	}

	releaseFaces(infos, count);
	release(plain);
	release(bold);
	release(otherPlain);
	release(mono);
	release(condensed);
	release(noItalic);
	if (faces != NULL)
		CFRelease(faces);
	CFRelease(collection);
	return failures ? 1 : 0;
}
