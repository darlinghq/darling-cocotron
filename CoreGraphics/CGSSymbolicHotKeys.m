/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// Symbolic hot keys: the system-wide shortcuts that macOS numbers (Spotlight, Mission
// Control, screenshots, input source switching ...). The window server owns their
// state; applications read it (to avoid clashing with a shortcut) and some change it.
// Darling has no system actions behind them, so this only keeps the state, where macOS
// keeps it: the AppleSymbolicHotKeys dictionary of the com.apple.symbolichotkeys
// preference domain. That dictionary holds only what was changed; every other hot key
// has a built-in default.
//
// An entry of the dictionary, keyed by the decimal hot key number, is
//   { enabled = <bool>; value = { type = standard; parameters = (keyEquivalent, keyCode, modifiers) } }
// where either member can be missing (a missing member means the default).
//
// QUIRK: the defaults below and the error code for an unknown number are observed values,
// not documented. Evidence: black-box observation of CGSGetSymbolicHotKeyValue and
// CGSIsSymbolicHotKeyEnabled on macOS 26.7.3 (tier 2, MC-V466 in the project's Mac
// evidence notes) for the numbers listed; the value of a hot key without a key is
// keyEquivalent 65535 (the "no character" value) and the modifiers are CGEventFlags
// bits. The setter semantics (store into the preference domain, success result) are
// inferred from the preference layout the Mac shows, since the Mac's settings were not
// changed. The function names and prototypes follow the CGSHotKeys.h of CGSInternal
// (https://github.com/NUIKit/CGSInternal, MIT license), declared independently.
// Test: tests/cgs-symbolic-hotkeys.c

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGError.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct
{
	int number;
	bool enabled;
	bool hasValue;
	uint16_t keyEquivalent;
	uint16_t keyCode;
	uint32_t modifiers;
} SymbolicHotKeyDefault;

// Modifier bits as in CGEventFlags.
#define SHIFT 0x20000u
#define CTRL 0x40000u
#define OPT 0x80000u
#define CMD 0x100000u
#define FN 0x800000u
#define NOCHAR 0xFFFF

static const SymbolicHotKeyDefault g_defaults[] = {
	{ 7, true, true, NOCHAR, 120, FN | CTRL },
	{ 8, true, true, NOCHAR, 99, FN | CTRL },
	{ 9, true, true, NOCHAR, 118, FN | CTRL },
	{ 10, true, true, NOCHAR, 96, FN | CTRL },
	{ 11, true, true, NOCHAR, 97, FN | CTRL },
	{ 12, true, true, NOCHAR, 122, FN | CTRL },
	{ 13, true, true, NOCHAR, 98, FN | CTRL },
	{ 15, false, true, 56, 28, OPT | CMD },
	{ 16, false, true, NOCHAR, 67, OPT | CMD },
	{ 17, false, true, 61, 24, OPT | CMD },
	{ 18, false, true, NOCHAR, 69, OPT | CMD },
	{ 19, false, true, 45, 27, OPT | CMD },
	{ 21, false, true, 56, 28, OPT | CTRL | CMD },
	{ 22, false, true, NOCHAR, 67, OPT | CTRL | CMD },
	{ 23, false, true, 92, 42, OPT | CMD },
	{ 24, false, true, 96, 50, OPT | CMD },
	{ 25, false, true, 46, 47, OPT | CTRL | CMD },
	{ 26, false, true, 44, 43, OPT | CTRL | CMD },
	{ 27, true, true, 96, 50, CMD },
	{ 28, true, true, 51, 20, SHIFT | CMD },
	{ 29, true, true, 51, 20, SHIFT | CTRL | CMD },
	{ 30, true, true, 52, 21, SHIFT | CMD },
	{ 31, true, true, 52, 21, SHIFT | CTRL | CMD },
	{ 32, true, true, NOCHAR, 126, FN | CTRL },
	{ 33, true, true, NOCHAR, 125, FN | CTRL },
	{ 34, true, true, NOCHAR, 126, FN | CTRL | SHIFT },
	{ 35, true, true, NOCHAR, 125, FN | CTRL | SHIFT },
	{ 36, true, true, NOCHAR, 103, FN },
	{ 37, true, true, NOCHAR, 103, FN | SHIFT },
	{ 51, true, true, 39, 50, OPT | CMD },
	{ 52, true, true, 100, 2, OPT | CMD },
	{ 57, true, true, NOCHAR, 100, FN | CTRL },
	{ 59, true, true, NOCHAR, 96, FN | CMD },
	{ 60, true, true, 32, 49, CTRL },
	{ 61, true, true, 32, 49, CTRL | OPT },
	{ 62, true, true, NOCHAR, 111, FN },
	{ 64, true, true, 32, 49, CMD },
	{ 65, true, true, 32, 49, OPT | CMD },
	{ 70, true, true, 100, 2, CTRL | CMD },
	{ 73, true, false, 0, 0, 0 },
	{ 79, true, true, NOCHAR, 123, FN | CTRL },
	{ 80, true, true, NOCHAR, 123, FN | CTRL | SHIFT },
	{ 81, true, true, NOCHAR, 124, FN | CTRL },
	{ 98, true, true, 47, 44, SHIFT | CMD },
	{ 118, false, true, NOCHAR, 18, CTRL },
	{ 160, false, true, NOCHAR, NOCHAR, 0 },
	{ 162, true, true, NOCHAR, 96, FN | CMD | OPT },
	{ 163, false, true, NOCHAR, NOCHAR, 0 },
	{ 164, true, false, 0, 0, 0 },
	{ 175, true, true, NOCHAR, NOCHAR, 0 },
	{ 184, true, true, 53, 23, SHIFT | CMD },
	{ 190, true, true, 113, 12, FN },
	{ 222, true, true, NOCHAR, NOCHAR, 0 },
};

#undef SHIFT
#undef CTRL
#undef OPT
#undef CMD
#undef FN

static const CFStringRef kDomain = CFSTR("com.apple.symbolichotkeys");
static const CFStringRef kHotKeysKey = CFSTR("AppleSymbolicHotKeys");

static const SymbolicHotKeyDefault* FindDefault(int number)
{
	for (size_t i = 0; i < sizeof(g_defaults) / sizeof(g_defaults[0]); i++)
	{
		if (g_defaults[i].number == number)
			return &g_defaults[i];
	}
	return NULL;
}

static CFStringRef CopyNumberKey(int number)
{
	return CFStringCreateWithFormat(NULL, NULL, CFSTR("%d"), number);
}

// The stored AppleSymbolicHotKeys dictionary (a copy the caller releases), or NULL.
static CFDictionaryRef CopyStoredHotKeys(void)
{
	CFPropertyListRef all = CFPreferencesCopyAppValue(kHotKeysKey, kDomain);
	if (all != NULL && CFGetTypeID(all) != CFDictionaryGetTypeID())
	{
		CFRelease(all);
		return NULL;
	}
	return (CFDictionaryRef) all;
}

static CFDictionaryRef StoredEntry(CFDictionaryRef all, int number)
{
	if (all == NULL)
		return NULL;
	CFStringRef key = CopyNumberKey(number);
	CFTypeRef entry = CFDictionaryGetValue(all, key);
	CFRelease(key);
	return (entry != NULL && CFGetTypeID(entry) == CFDictionaryGetTypeID()) ? (CFDictionaryRef) entry : NULL;
}

static bool NumberFromArray(CFArrayRef array, CFIndex index, int64_t* out)
{
	if (CFArrayGetCount(array) <= index)
		return false;
	CFTypeRef n = CFArrayGetValueAtIndex(array, index);
	return n != NULL && CFGetTypeID(n) == CFNumberGetTypeID() && CFNumberGetValue(n, kCFNumberSInt64Type, out);
}

bool CGSIsSymbolicHotKeyEnabled(int number)
{
	bool enabled = false;
	const SymbolicHotKeyDefault* def = FindDefault(number);
	if (def != NULL)
		enabled = def->enabled;

	CFDictionaryRef all = CopyStoredHotKeys();
	CFDictionaryRef entry = StoredEntry(all, number);
	if (entry != NULL)
	{
		CFTypeRef flag = CFDictionaryGetValue(entry, CFSTR("enabled"));
		if (flag != NULL && CFGetTypeID(flag) == CFBooleanGetTypeID())
			enabled = CFBooleanGetValue(flag);
		else if (flag != NULL && CFGetTypeID(flag) == CFNumberGetTypeID())
		{
			int v = 0;
			CFNumberGetValue(flag, kCFNumberIntType, &v);
			enabled = v != 0;
		}
	}
	if (all != NULL)
		CFRelease(all);
	return enabled;
}

CGError CGSGetSymbolicHotKeyValue(int number, uint16_t* keyEquivalent, uint16_t* keyCode, uint32_t* modifiers)
{
	bool found = false;
	uint16_t ke = 0, vk = 0;
	uint32_t mods = 0;

	const SymbolicHotKeyDefault* def = FindDefault(number);
	if (def != NULL && def->hasValue)
	{
		found = true;
		ke = def->keyEquivalent;
		vk = def->keyCode;
		mods = def->modifiers;
	}

	CFDictionaryRef all = CopyStoredHotKeys();
	CFDictionaryRef entry = StoredEntry(all, number);
	if (entry != NULL)
	{
		CFTypeRef value = CFDictionaryGetValue(entry, CFSTR("value"));
		CFTypeRef params = (value != NULL && CFGetTypeID(value) == CFDictionaryGetTypeID())
			? CFDictionaryGetValue((CFDictionaryRef) value, CFSTR("parameters")) : NULL;
		int64_t a, b, c;
		if (params != NULL && CFGetTypeID(params) == CFArrayGetTypeID()
				&& NumberFromArray(params, 0, &a) && NumberFromArray(params, 1, &b) && NumberFromArray(params, 2, &c))
		{
			found = true;
			ke = (uint16_t) a;
			vk = (uint16_t) b;
			mods = (uint32_t) c;
		}
	}
	if (all != NULL)
		CFRelease(all);

	if (!found)
		return kCGErrorRangeCheck;
	if (keyEquivalent != NULL)
		*keyEquivalent = ke;
	if (keyCode != NULL)
		*keyCode = vk;
	if (modifiers != NULL)
		*modifiers = mods;
	return kCGErrorSuccess;
}

// Rewrites the stored entry of the number: the callback changes a mutable copy of the
// current entry (empty when there is none), and the preference domain is saved.
typedef void (*EntryUpdate)(CFMutableDictionaryRef entry, const void* context);

static CGError UpdateEntry(int number, EntryUpdate update, const void* context)
{
	CFDictionaryRef all = CopyStoredHotKeys();
	CFMutableDictionaryRef newAll = all != NULL
		? CFDictionaryCreateMutableCopy(NULL, 0, all)
		: CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef old = StoredEntry(all, number);
	CFMutableDictionaryRef entry = old != NULL
		? CFDictionaryCreateMutableCopy(NULL, 0, old)
		: CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

	update(entry, context);

	CFStringRef key = CopyNumberKey(number);
	CFDictionarySetValue(newAll, key, entry);
	CFRelease(key);
	CFPreferencesSetAppValue(kHotKeysKey, newAll, kDomain);
	Boolean ok = CFPreferencesAppSynchronize(kDomain);

	CFRelease(entry);
	CFRelease(newAll);
	if (all != NULL)
		CFRelease(all);
	return ok ? kCGErrorSuccess : kCGErrorFailure;
}

static void SetEnabledUpdate(CFMutableDictionaryRef entry, const void* context)
{
	CFDictionarySetValue(entry, CFSTR("enabled"), *(const bool*) context ? kCFBooleanTrue : kCFBooleanFalse);
}

CGError CGSSetSymbolicHotKeyEnabled(int number, bool enabled)
{
	return UpdateEntry(number, SetEnabledUpdate, &enabled);
}

typedef struct
{
	uint16_t keyEquivalent;
	uint16_t keyCode;
	uint32_t modifiers;
} ValueUpdateContext;

static void SetValueUpdate(CFMutableDictionaryRef entry, const void* context)
{
	const ValueUpdateContext* v = context;
	int64_t numbers[3] = { v->keyEquivalent, v->keyCode, v->modifiers };
	CFNumberRef refs[3];
	for (int i = 0; i < 3; i++)
		refs[i] = CFNumberCreate(NULL, kCFNumberSInt64Type, &numbers[i]);
	CFArrayRef parameters = CFArrayCreate(NULL, (const void**) refs, 3, &kCFTypeArrayCallBacks);
	for (int i = 0; i < 3; i++)
		CFRelease(refs[i]);

	const void* keys[2] = { CFSTR("parameters"), CFSTR("type") };
	const void* values[2] = { parameters, CFSTR("standard") };
	CFDictionaryRef value = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(parameters);

	CFDictionarySetValue(entry, CFSTR("value"), value);
	CFRelease(value);
}

CGError CGSSetSymbolicHotKeyValue(int number, uint16_t keyEquivalent, uint16_t keyCode, uint32_t modifiers)
{
	ValueUpdateContext context = { keyEquivalent, keyCode, modifiers };
	return UpdateEntry(number, SetValueUpdate, &context);
}
