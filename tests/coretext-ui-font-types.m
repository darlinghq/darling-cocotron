// CFLAGS: -framework AppKit -framework CoreText -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// Two public contracts of the font classes:
//  - CTFontCreateUIFontForLanguage makes a font for every CTFontUIFontType the header declares, up to
//    kCTFontUIFontControlContent, with the default sizes of the tool tip and control content types.
//  - CoreText functions accept an NSFont in place of a CTFontRef (the classes are toll-free bridged).
// Values observed on macOS 26.7.3 and 10.14.4; the program passes unchanged on both.
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); failures++; } } while (0)

int main(void)
{
	@autoreleasepool {
		for (int type = kCTFontUIFontUser; type <= kCTFontUIFontControlContent; type++) {
			CTFontRef font = CTFontCreateUIFontForLanguage((CTFontUIFontType) type, 0, NULL);
			if (font == NULL)
				printf("UI font type %d: NULL\n", type);
			CHECK(font != NULL);
			if (font != NULL) {
				CHECK(CTFontGetSize(font) > 0);
				CFRelease(font);
			}
		}

		CTFontRef toolTip = CTFontCreateUIFontForLanguage(kCTFontUIFontToolTip, 0, NULL);
		CTFontRef content = CTFontCreateUIFontForLanguage(kCTFontUIFontControlContent, 0, NULL);
		CHECK(toolTip != NULL && CTFontGetSize(toolTip) == 11);
		CHECK(content != NULL && CTFontGetSize(content) == 12);
		CHECK(toolTip != NULL && CTFontGetSize(toolTip) == [[NSFont toolTipsFontOfSize: 0] pointSize]);
		CHECK(content != NULL && CTFontGetSize(content) == [[NSFont controlContentFontOfSize: 0] pointSize]);
		if (toolTip) CFRelease(toolTip);
		if (content) CFRelease(content);

		NSFont *system = [NSFont systemFontOfSize: 13];
		NSFont *named = [NSFont fontWithName: @"Helvetica" size: 14];
		NSFont *bold = [NSFont boldSystemFontOfSize: 13];
		CHECK(system != nil && named != nil && bold != nil);
		CHECK(CTFontGetSize((CTFontRef) system) == 13);
		CHECK(CTFontGetSize((CTFontRef) bold) == 13);
		CTFontRef created = CTFontCreateWithName(CFSTR("Helvetica"), 14, NULL);
		CHECK(CFGetTypeID(created) == CTFontGetTypeID());
		CFRelease(created);

		// CoreText accepts the NSFont.
		CHECK(CTFontGetSize((CTFontRef) named) == 14);
		CFStringRef name = CTFontCopyPostScriptName((CTFontRef) named);
		CHECK(name != NULL);
		if (name) CFRelease(name);
	}
	printf(failures ? "FAILED\n" : "PASS\n");
	return failures != 0;
}
