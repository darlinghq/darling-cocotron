/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// Symbolic hot key SPI of CoreGraphics. Read-only checks run on any system (also macOS);
// the write checks are for Darling only and run when SYMHK_WRITE=1, because they change
// the com.apple.symbolichotkeys domain of the current user (and restore it).
// Defaults pinned here are what macOS 26.7.3 reports (QUIRK tests).
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>

typedef int CGError;
static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); g_fail = 1; } } while (0)

static bool (*isEnabled)(int);
static CGError (*setEnabled)(int, bool);
static CGError (*getValue)(int, unsigned short*, unsigned short*, unsigned int*);
static CGError (*setValue)(int, unsigned short, unsigned short, unsigned int);

static void expectValue(int n, unsigned short ke, unsigned short vk, unsigned int mods)
{
	unsigned short a = 1, b = 1;
	unsigned int c = 1;
	CGError e = getValue(n, &a, &b, &c);
	if (e != 0 || a != ke || b != vk || c != mods)
	{
		printf("FAIL hot key %d: err %d ke %u vk %u mods 0x%x\n", n, e, a, b, c);
		g_fail = 1;
	}
}

int main(void)
{
	void* h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW);
	isEnabled = dlsym(h, "CGSIsSymbolicHotKeyEnabled");
	setEnabled = dlsym(h, "CGSSetSymbolicHotKeyEnabled");
	getValue = dlsym(h, "CGSGetSymbolicHotKeyValue");
	setValue = dlsym(h, "CGSSetSymbolicHotKeyValue");
	if (!isEnabled || !setEnabled || !getValue || !setValue)
	{
		printf("FAIL symbols missing\n");
		return 1;
	}

	// Defaults on macOS 26.7.3 (assuming the user did not change them).
	expectValue(64, 32, 49, 0x100000);  // Spotlight: Command-Space
	expectValue(60, 32, 49, 0x40000);   // previous input source: Control-Space
	expectValue(7, 65535, 120, 0x840000);
	expectValue(15, 56, 28, 0x180000);
	CHECK(isEnabled(64));
	CHECK(!isEnabled(15));

	// An unknown number: range-check error, outputs untouched, not enabled.
	unsigned short a = 0x1234, b = 0x1234;
	unsigned int c = 0x1234;
	CHECK(getValue(999, &a, &b, &c) == 1007);
	CHECK(a == 0x1234 && b == 0x1234 && c == 0x1234);
	CHECK(!isEnabled(999));
	CHECK(getValue(-1, &a, &b, &c) == 1007);
	CHECK(getValue(64, NULL, NULL, NULL) == 0);

	if (getenv("SYMHK_WRITE") && atoi(getenv("SYMHK_WRITE")) == 1)
	{
		bool was = isEnabled(64);
		CHECK(setEnabled(64, !was) == 0);
		CHECK(isEnabled(64) == !was);
		expectValue(64, 32, 49, 0x100000);  // the value is unchanged
		CHECK(setValue(64, 120, 7, 0x120000) == 0);
		expectValue(64, 120, 7, 0x120000);
		CHECK(isEnabled(64) == !was);
		// Persisted where the preference domain keeps it.
		CFPreferencesAppSynchronize(CFSTR("com.apple.symbolichotkeys"));
		CFDictionaryRef all = CFPreferencesCopyAppValue(CFSTR("AppleSymbolicHotKeys"), CFSTR("com.apple.symbolichotkeys"));
		CHECK(all != NULL && CFDictionaryGetValue(all, CFSTR("64")) != NULL);
		if (all) CFRelease(all);
		// Restore.
		setValue(64, 32, 49, 0x100000);
		setEnabled(64, was);
		expectValue(64, 32, 49, 0x100000);
	}

	printf(g_fail ? "FAIL\n" : "PASS\n");
	return g_fail;
}
