/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CTFontCreateCopyWithSymbolicTraits makes a font in the family of the original with the
 * symbolic traits given, and CTFontCreateCopyWithFamily makes a font in the family given with
 * the traits of the original. For both, a size of 0.0 keeps the original's size, and NULL means
 * the system has no such font:
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
#include <stdio.h>

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
