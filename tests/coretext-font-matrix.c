/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A font keeps the transformation matrix it was created with and CTFontGetMatrix returns it; a NULL
 * matrix means the identity matrix, and a copy made with a NULL matrix keeps the original font's matrix (not
 * so for CTFontCreateCopyWithFamily, which gives the identity matrix, and the translation of a matrix is
 * not kept; both observed on macOS 10.14.4 and 26.7.3):
 * https://developer.apple.com/documentation/coretext/ctfontgetmatrix(_:)
 * https://developer.apple.com/documentation/coretext/ctfontcreatewithname(_:_:_:)
 * https://developer.apple.com/documentation/coretext/ctfontcreatecopywithattributes(_:_:_:_:)
 * https://developer.apple.com/documentation/coretext/ctfontcreatecopywithfamily(_:_:_:_:)
 * https://developer.apple.com/documentation/coretext/ctfontcreatewithgraphicsfont(_:_:_:_:)
 * A copy that applies a variation, and a font made from font data, are separate paths in the implementation
 * and are checked separately; each prints SKIP when no installed font can exercise it.
 *
 * The matrix scales the metrics of a font on macOS (the ascent follows it); that is not implemented here and
 * the test does not check it. It
 * finds a font among the installed ones, so it works with whatever fonts the system has.
 *
 * Usage: coretext-font-matrix
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

static int same(CGAffineTransform a, CGAffineTransform b)
{
	return a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d && a.tx == b.tx && a.ty == b.ty;
}

static int isIdentity(CTFontRef font)
{
	return same(CTFontGetMatrix(font), CGAffineTransformIdentity);
}

// The contents of the file a face is installed from, or NULL.
static CFDataRef copyFileData(CFURLRef url)
{
	char path[1024];
	if (url == NULL || !CFURLGetFileSystemRepresentation(url, true, (UInt8 *) path, sizeof(path)))
		return NULL;
	FILE *file = fopen(path, "rb");
	if (file == NULL)
		return NULL;
	CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
	UInt8 buffer[65536];
	size_t count;
	while ((count = fread(buffer, 1, sizeof(buffer), file)) > 0)
		CFDataAppendBytes(data, buffer, (CFIndex) count);
	fclose(file);
	if (CFDataGetLength(data) == 0) {
		CFRelease(data);
		return NULL;
	}
	return data;
}

// A copy that applies a variation is a new font object: it keeps the matrix. Needs an installed variable font
// with a face the copy can apply a variation to; prints SKIP when there is none.
static void checkVariationKeepsMatrix(CFArrayRef faces, CGAffineTransform matrix)
{
	for (CFIndex i = 0; i < CFArrayGetCount(faces); i++) {
		CTFontDescriptorRef face = (CTFontDescriptorRef) CFArrayGetValueAtIndex(faces, i);
		CTFontRef font = CTFontCreateWithFontDescriptor(face, 14, &matrix);
		CFArrayRef axes = font != NULL ? CTFontCopyVariationAxes(font) : NULL;
		CFDictionaryRef axis = axes != NULL && CFArrayGetCount(axes) > 0 ? CFArrayGetValueAtIndex(axes, 0) : NULL;
		CFNumberRef identifier = axis != NULL ? CFDictionaryGetValue(axis, kCTFontVariationAxisIdentifierKey) : NULL;
		CFNumberRef value = axis != NULL ? CFDictionaryGetValue(axis, kCTFontVariationAxisDefaultValueKey) : NULL;
		if (identifier != NULL && value != NULL) {
			double number = 0;
			CFNumberGetValue(value, kCFNumberDoubleType, &number);
			CTFontDescriptorRef varied = CTFontDescriptorCreateCopyWithVariation(face, identifier, number);
			CTFontRef copy = varied != NULL ? CTFontCreateCopyWithAttributes(font, 0, NULL, varied) : NULL;
			CFDictionaryRef variation = copy != NULL ? CTFontCopyVariation(copy) : NULL;
			if (variation != NULL && CFDictionaryGetCount(variation) > 0) {
				expect(same(CTFontGetMatrix(copy), matrix), "a copy with a variation keeps the matrix");
				CFRelease(variation);
				CFRelease(copy);
				CFRelease(varied);
				CFRelease(axes);
				CFRelease(font);
				return;
			}
			if (variation != NULL)
				CFRelease(variation);
			if (copy != NULL)
				CFRelease(copy);
			if (varied != NULL)
				CFRelease(varied);
		}
		if (axes != NULL)
			CFRelease(axes);
		if (font != NULL)
			CFRelease(font);
	}
	printf("SKIP no installed variable font a variation can be applied to\n");
}

// A descriptor made from font data names a face that is not installed; the font made from it takes the matrix too.
static void checkFontDataKeepsMatrix(CFArrayRef faces, CGAffineTransform matrix)
{
	for (CFIndex i = 0; i < CFArrayGetCount(faces); i++) {
		CFURLRef url = CTFontDescriptorCopyAttribute((CTFontDescriptorRef) CFArrayGetValueAtIndex(faces, i), kCTFontURLAttribute);
		CFDataRef data = copyFileData(url);
		if (url != NULL)
			CFRelease(url);
		if (data == NULL)
			continue;
		CTFontDescriptorRef fromData = CTFontManagerCreateFontDescriptorFromData(data);
		CFRelease(data);
		if (fromData == NULL)
			continue;
		CTFontRef font = CTFontCreateWithFontDescriptor(fromData, 14, &matrix);
		expect(font != NULL && same(CTFontGetMatrix(font), matrix), "a font made from font data keeps the matrix");
		CTFontRef plain = CTFontCreateWithFontDescriptor(fromData, 14, NULL);
		expect(plain != NULL && isIdentity(plain), "a font made from font data without a matrix is the identity");
		if (font != NULL)
			CFRelease(font);
		if (plain != NULL)
			CFRelease(plain);
		CFRelease(fromData);
		return;
	}
	printf("SKIP no installed font file could be read\n");
}

int main(void)
{
	CTFontCollectionRef collection = CTFontCollectionCreateFromAvailableFonts(NULL);
	CFArrayRef faces = CTFontCollectionCreateMatchingFontDescriptors(collection);
	CFStringRef name = NULL;
	if (faces != NULL && CFArrayGetCount(faces) > 0)
		name = CTFontDescriptorCopyAttribute((CTFontDescriptorRef) CFArrayGetValueAtIndex(faces, 0),
				kCTFontNameAttribute);
	if (name == NULL) {
		printf("SKIP no installed font\n");
		return 0;
	}

	CGAffineTransform skew = CGAffineTransformMake(1, 0, 0.25, 1, 0, 0);
	CGAffineTransform scale = CGAffineTransformMake(2, 0, 0, 0.5, 0, 0);

	// NULL is the identity matrix.
	CTFontRef plain = CTFontCreateWithName(name, 14, NULL);
	expect(plain != NULL, "a font is created for the name");
	expect(plain != NULL && isIdentity(plain), "no matrix reads as the identity matrix");

	// The matrix given is the matrix returned, and it does not change the size.
	CTFontRef skewed = CTFontCreateWithName(name, 14, &skew);
	expect(skewed != NULL && same(CTFontGetMatrix(skewed), skew), "CTFontCreateWithName keeps the matrix");
	expect(skewed != NULL && CTFontGetSize(skewed) == 14, "the size is as given");
	CGAffineTransform translated = CGAffineTransformMake(1, 0, 0.25, 1, 2, -3);
	CTFontRef translatedFont = CTFontCreateWithName(name, 14, &translated);
	expect(translatedFont != NULL && same(CTFontGetMatrix(translatedFont), skew), "the translation of the matrix is not kept");
	if (translatedFont != NULL)
		CFRelease(translatedFont);
	CTFontRef identity = CTFontCreateWithName(name, 14, &CGAffineTransformIdentity);
	expect(identity != NULL && isIdentity(identity), "the identity matrix reads as the identity matrix");
	CTFontRef options = CTFontCreateWithNameAndOptions(name, 14, &skew, 0);
	expect(options != NULL && same(CTFontGetMatrix(options), skew), "CTFontCreateWithNameAndOptions keeps the matrix");

	// A font descriptor.
	CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithNameAndSize(name, 14);
	CTFontRef fromDescriptor = CTFontCreateWithFontDescriptor(descriptor, 14, &skew);
	expect(fromDescriptor != NULL && same(CTFontGetMatrix(fromDescriptor), skew),
			"CTFontCreateWithFontDescriptor keeps the matrix");
	CTFontRef descriptorPlain = CTFontCreateWithFontDescriptor(descriptor, 14, NULL);
	expect(descriptorPlain != NULL && isIdentity(descriptorPlain), "a descriptor font without matrix is the identity");

	// A copy: NULL keeps the original's matrix, a given matrix replaces it, the size does not matter.
	if (skewed != NULL) {
		CTFontRef kept = CTFontCreateCopyWithAttributes(skewed, 0, NULL, NULL);
		expect(kept != NULL && same(CTFontGetMatrix(kept), skew), "a copy with a NULL matrix keeps the matrix");
		CTFontRef resized = CTFontCreateCopyWithAttributes(skewed, 20, NULL, NULL);
		expect(resized != NULL && same(CTFontGetMatrix(resized), skew) && CTFontGetSize(resized) == 20,
				"a copy with another size keeps the matrix");
		CTFontRef replaced = CTFontCreateCopyWithAttributes(skewed, 0, &scale, NULL);
		expect(replaced != NULL && same(CTFontGetMatrix(replaced), scale), "a copy with a matrix gets it");
		CTFontRef reset = CTFontCreateCopyWithAttributes(skewed, 0, &CGAffineTransformIdentity, NULL);
		expect(reset != NULL && isIdentity(reset), "a copy with the identity matrix gets the identity");
		expect(same(CTFontGetMatrix(skewed), skew), "the original keeps its matrix");

		// The family copy of a face in its own family with its own traits is the face itself.
		CFStringRef family = CTFontCopyFamilyName(skewed);
		CTFontRef sameFamily = family != NULL ? CTFontCreateCopyWithFamily(skewed, 0, NULL, family) : NULL;
		if (sameFamily != NULL) {
			expect(isIdentity(sameFamily), "CTFontCreateCopyWithFamily with NULL gives the identity matrix (QUIRK)");
			CFRelease(sameFamily);
			sameFamily = CTFontCreateCopyWithFamily(skewed, 0, &scale, family);
			expect(sameFamily != NULL && same(CTFontGetMatrix(sameFamily), scale),
					"CTFontCreateCopyWithFamily with a matrix gets it");
		} else
			printf("SKIP no face of the family with the original's traits\n");
		if (sameFamily != NULL)
			CFRelease(sameFamily);
		if (family != NULL)
			CFRelease(family);

		CTFontRef traits = CTFontCreateCopyWithSymbolicTraits(skewed, 0, NULL, 0, 0);
		if (traits != NULL)
			expect(same(CTFontGetMatrix(traits), skew), "CTFontCreateCopyWithSymbolicTraits with NULL keeps the matrix");
		else
			printf("SKIP no face with the original's traits\n");
		if (traits != NULL)
			CFRelease(traits);

		// A Core Graphics font.
		CGFontRef graphicsFont = CTFontCopyGraphicsFont(skewed, NULL);
		CTFontRef fromGraphics = graphicsFont != NULL ? CTFontCreateWithGraphicsFont(graphicsFont, 14, &scale, NULL) : NULL;
		expect(fromGraphics != NULL && same(CTFontGetMatrix(fromGraphics), scale),
				"CTFontCreateWithGraphicsFont keeps the matrix");
		CTFontRef graphicsPlain = graphicsFont != NULL ? CTFontCreateWithGraphicsFont(graphicsFont, 14, NULL, NULL) : NULL;
		expect(graphicsPlain != NULL && isIdentity(graphicsPlain), "a graphics font without matrix is the identity");

		if (kept != NULL) CFRelease(kept);
		if (resized != NULL) CFRelease(resized);
		if (replaced != NULL) CFRelease(replaced);
		if (reset != NULL) CFRelease(reset);
		if (fromGraphics != NULL) CFRelease(fromGraphics);
		if (graphicsPlain != NULL) CFRelease(graphicsPlain);
		if (graphicsFont != NULL) CGFontRelease(graphicsFont);
	}

	checkVariationKeepsMatrix(faces, skew);
	checkFontDataKeepsMatrix(faces, skew);

	if (plain != NULL) CFRelease(plain);
	if (skewed != NULL) CFRelease(skewed);
	if (identity != NULL) CFRelease(identity);
	if (options != NULL) CFRelease(options);
	if (fromDescriptor != NULL) CFRelease(fromDescriptor);
	if (descriptorPlain != NULL) CFRelease(descriptorPlain);
	CFRelease(descriptor);
	CFRelease(name);
	CFRelease(faces);
	CFRelease(collection);
	return failures ? 1 : 0;
}
