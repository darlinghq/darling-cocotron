// CFLAGS: -framework CoreText -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// CTFontDescriptorIsSystemUIFont (exported by CoreText, not declared in the SDK headers): true for
// the descriptor of a font made for a system UI font type, false for the user font types and for
// descriptors made from a name. Observed on macOS 26.7.3; the program passes unchanged there.
#import <CoreText/CoreText.h>
#include <stdio.h>

extern bool CTFontDescriptorIsSystemUIFont(CTFontDescriptorRef descriptor);

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); failures++; } } while (0)

static bool uiFontIsSystemUI(CTFontUIFontType type)
{
	CTFontRef font = CTFontCreateUIFontForLanguage(type, 12, NULL);
	CTFontDescriptorRef descriptor = CTFontCopyFontDescriptor(font);
	bool result = CTFontDescriptorIsSystemUIFont(descriptor);
	CFRelease(descriptor);
	CFRelease(font);
	return result;
}

int main(void)
{
	CHECK(uiFontIsSystemUI(kCTFontUIFontSystem));
	CHECK(uiFontIsSystemUI(kCTFontUIFontEmphasizedSystem));
	CHECK(uiFontIsSystemUI(kCTFontUIFontMenuItem));
	CHECK(!uiFontIsSystemUI(kCTFontUIFontUser));
	CHECK(!uiFontIsSystemUI(kCTFontUIFontUserFixedPitch));

	CTFontDescriptorRef helvetica = CTFontDescriptorCreateWithNameAndSize(CFSTR("Helvetica"), 12);
	CHECK(!CTFontDescriptorIsSystemUIFont(helvetica));
	CFRelease(helvetica);
	CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
	CTFontDescriptorRef fromFont = CTFontCopyFontDescriptor(font);
	CHECK(!CTFontDescriptorIsSystemUIFont(fromFont));
	CFRelease(fromFont);
	CFRelease(font);
	CHECK(!CTFontDescriptorIsSystemUIFont(NULL));

	printf(failures ? "FAILED\n" : "PASS\n");
	return failures != 0;
}
