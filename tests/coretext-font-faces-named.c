/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Every descriptor that CTFontCollectionCreateFromAvailableFonts reports
 * describes one face and carries its PostScript name (kCTFontNameAttribute),
 * its family name, its display name and its file URL. Callers compare these
 * values without checking for NULL, so a face without a name must not be
 * listed: a variable font is listed through its named instances, not as one
 * more nameless face. The same naming attributes are available from a
 * descriptor made from a PostScript name only, from the descriptors of a font
 * file, and from a UI font.
 *
 * The first check is vacuous on a system with no variable font installed.
 *
 * Usage: coretext-font-faces-named
 * Prints PASS/FAIL lines; exit status 1 on failure.
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

int main(void)
{
	CTFontCollectionRef collection = CTFontCollectionCreateFromAvailableFonts(NULL);
	CFArrayRef descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection);
	CFIndex count = descriptors != NULL ? CFArrayGetCount(descriptors) : 0;
	expect(count > 0, "the collection lists faces");

	CFIndex noName = 0, noFamily = 0, noURL = 0, noDisplay = 0;
	for (CFIndex i = 0; i < count; i++) {
		CTFontDescriptorRef descriptor =
				(CTFontDescriptorRef) CFArrayGetValueAtIndex(descriptors, i);
		CFTypeRef name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
		CFTypeRef family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute);
		CFTypeRef url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute);
		CFTypeRef display = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute);
		if (name == NULL)
			noName++;
		if (family == NULL)
			noFamily++;
		if (url == NULL)
			noURL++;
		if (display == NULL)
			noDisplay++;
		if (name != NULL)
			CFRelease(name);
		if (family != NULL)
			CFRelease(family);
		if (url != NULL)
			CFRelease(url);
		if (display != NULL)
			CFRelease(display);
	}
	expect(noName == 0, "every face has a PostScript name");
	expect(noFamily == 0, "every face has a family name");
	expect(noURL == 0, "every face has a file URL");
	expect(noDisplay == 0, "every face has a display name");

	// The naming attributes of an installed face are available from a descriptor
	// made from its PostScript name only, and from the descriptors of its file.
	if (count > 0) {
		CTFontDescriptorRef first = (CTFontDescriptorRef) CFArrayGetValueAtIndex(descriptors, 0);
		CFStringRef name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute);
		CFURLRef url = CTFontDescriptorCopyAttribute(first, kCTFontURLAttribute);

		CTFontDescriptorRef byName = CTFontDescriptorCreateWithNameAndSize(name, 12);
		CFTypeRef value;
		value = CTFontDescriptorCopyAttribute(byName, kCTFontFamilyNameAttribute);
		expect(value != NULL, "a descriptor made from a PostScript name has a family name");
		if (value != NULL)
			CFRelease(value);
		value = CTFontDescriptorCopyAttribute(byName, kCTFontDisplayNameAttribute);
		expect(value != NULL, "a descriptor made from a PostScript name has a display name");
		if (value != NULL)
			CFRelease(value);
		value = CTFontDescriptorCopyAttribute(byName, kCTFontURLAttribute);
		expect(value != NULL, "a descriptor made from a PostScript name has a file URL");
		if (value != NULL)
			CFRelease(value);
		CFRelease(byName);

		CFArrayRef fromFile = CTFontManagerCreateFontDescriptorsFromURL(url);
		expect(fromFile != NULL && CFArrayGetCount(fromFile) > 0, "the file of a face has descriptors");
		if (fromFile != NULL && CFArrayGetCount(fromFile) > 0) {
			CTFontDescriptorRef d = (CTFontDescriptorRef) CFArrayGetValueAtIndex(fromFile, 0);
			CFStringRef keys[] = { kCTFontNameAttribute, kCTFontFamilyNameAttribute,
				kCTFontDisplayNameAttribute, kCTFontStyleNameAttribute, kCTFontURLAttribute };
			const char *labels[] = { "name", "family name", "display name", "style name", "file URL" };
			for (int i = 0; i < 5; i++) {
				value = CTFontDescriptorCopyAttribute(d, keys[i]);
				char what[100];
				snprintf(what, sizeof what, "a descriptor from a font file has a %s", labels[i]);
				expect(value != NULL, what);
				if (value != NULL)
					CFRelease(value);
			}
		}
		if (fromFile != NULL)
			CFRelease(fromFile);
		CFRelease(name);
		CFRelease(url);
	}

	// The descriptor of a UI font names its face like any other.
	CTFontRef ui = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 12, NULL);
	expect(ui != NULL, "the system UI font exists");
	if (ui != NULL) {
		CFTypeRef value = CTFontCopyAttribute(ui, kCTFontDisplayNameAttribute);
		expect(value != NULL, "the system UI font has a display name");
		if (value != NULL)
			CFRelease(value);
		value = CTFontCopyAttribute(ui, kCTFontURLAttribute);
		expect(value != NULL, "the system UI font has a file URL");
		if (value != NULL)
			CFRelease(value);
		CFRelease(ui);
	}

	if (descriptors != NULL)
		CFRelease(descriptors);
	CFRelease(collection);
	return failures != 0;
}
