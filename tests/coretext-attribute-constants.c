/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Public CoreText constants that were defined but not declared in the headers. The string values are
 * those observed on macOS 10.14.4 and 26.7.3 (printed from the constants); attributed strings carry
 * them as keys, so they are part of the compatibility surface.
 */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void check(CFStringRef value, const char *expected, const char *name)
{
	char buffer[128] = "";
	if (value != NULL)
		CFStringGetCString(value, buffer, sizeof(buffer), kCFStringEncodingUTF8);
	int ok = value != NULL && strcmp(buffer, expected) == 0;
	printf("%s %s = %s\n", ok ? "PASS" : "FAIL", name, buffer);
	if (!ok)
		failures++;
}

int main(void)
{
	check(kCTStrokeWidthAttributeName, "NSStrokeWidth", "kCTStrokeWidthAttributeName");
	check(kCTVerticalFormsAttributeName, "CTVerticalForms", "kCTVerticalFormsAttributeName");
	check(kCTLanguageAttributeName, "NSLanguage", "kCTLanguageAttributeName");
	check(kCTTypesetterOptionForcedEmbeddingLevel, "CTTypesetterOptionForcedEmbeddingLevel", "kCTTypesetterOptionForcedEmbeddingLevel");
	return failures ? 1 : 0;
}
