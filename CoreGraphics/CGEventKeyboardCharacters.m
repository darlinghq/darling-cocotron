/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The characters of a virtual key code, for CGEventCreateKeyboardEvent() (the event's Unicode string)
// and for NSEvent's -characters and -charactersIgnoringModifiers of an event made from a CGEvent.
//
// The characters of the keys that depend on the keyboard layout (letters, digits, punctuation, space)
// come from the current layout, the 'uchr' data HIToolbox's Text Input Sources read through
// _CGSCopyCurrentKeyboardLayoutInfo(). UCKeyTranslate lives in CoreServices, above CoreGraphics, so this
// reads the layout's modifier and character tables itself; it needs nothing of UCKeyTranslate's dead key
// state machine because a key that starts a dead-key sequence has no characters of its own. Without a
// layout (no window system connection) a built-in US layout stands in.
//
// QUIRK: all of this (that a keyboard event has a string derived from its key code, which strings the
// special keys have, and how NSEvent applies the flags) is undocumented behaviour. Evidence: black-box
// observation on macOS 26.7.3 and 10.14.4, which agree (tier 2). Test:
// tests/coregraphics-cgevent-keyboard-characters.m
//
// The keys that give the same characters on every layout (Return, Tab, Escape, Delete, the keypad, the
// function, arrow and navigation keys) come from a table: black-box observation of macOS 26.7.3 and
// 10.14.4, which agree (mac-probes/cgevent-keyboard-unicode/allkeys-*.txt, tier 2).
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGEvent.h>
#import <CarbonCore/UnicodeUtilities.h>
#import "DarlingUnicodeKeyLayout.h"

extern CFDictionaryRef _CGSCopyCurrentKeyboardLayoutInfo(void);
#include <stdlib.h>
#include <string.h>

// Entries of the fixed table. For a key not in the table, the layout decides.
enum { kLayoutKey = 0xFFFF, kNoCharacters = 0 };

typedef struct {
	uint16_t cg;       // the Unicode string of CGEventCreateKeyboardEvent()
	uint16_t ns;       // NSEvent's characters
	uint16_t nsShift;  // NSEvent's characters with Shift set (0: same as ns)
} FixedKey;

#define LAYOUT { kLayoutKey, kLayoutKey, 0 }
#define NONE { 0, 0, 0 }
#define SAME(c) { c, c, 0 }
#define FUNCTION(ns) { 0x10, ns, 0 }

static const FixedKey g_fixedKeys[128] = {
	[0 ... 47] = LAYOUT,
	[36] = SAME(0x0D),
	[48] = { 0x09, 0x09, 0x19 },
	[49] = LAYOUT,
	[50] = LAYOUT,
	[51] = { 0x08, 0x7F, 0 },
	[52] = SAME(0x03),
	[53] = SAME(0x1B),
	[54 ... 63] = NONE, // modifier keys make flags changed events
	[64] = { 0, 0xF714, 0 },
	[65] = SAME(0x2E),
	[66] = { 0x1D, 0x1D, 0x2A },
	[67] = SAME(0x2A),
	[68] = NONE,
	[69] = SAME(0x2B),
	[70] = { 0x1C, 0x1C, 0x2B },
	[71] = { 0x1B, 0xF739, 0 },
	[72] = { 0x1F, 0x1F, 0x3D },
	[73] = NONE, [74] = NONE,
	[75] = SAME(0x2F),
	[76] = SAME(0x03),
	[77] = { 0x1E, 0x1E, 0x2F },
	[78] = SAME(0x2D),
	[79] = { 0, 0xF715, 0 },
	[80] = { 0, 0xF716, 0 },
	[81] = SAME(0x3D),
	[82] = SAME(0x30), [83] = SAME(0x31), [84] = SAME(0x32), [85] = SAME(0x33), [86] = SAME(0x34),
	[87] = SAME(0x35), [88] = SAME(0x36), [89] = SAME(0x37),
	[90] = { 0, 0x10, 0 },
	[91] = SAME(0x38), [92] = SAME(0x39),
	[93 ... 95] = NONE,
	[96] = FUNCTION(0xF708), [97] = FUNCTION(0xF709), [98] = FUNCTION(0xF70A), [99] = FUNCTION(0xF706),
	[100] = FUNCTION(0xF70B), [101] = FUNCTION(0xF70C), [102] = FUNCTION(0x10), [103] = FUNCTION(0xF70E),
	[104] = FUNCTION(0x10), [105] = FUNCTION(0xF710), [106] = FUNCTION(0xF713), [107] = FUNCTION(0xF711),
	[108] = FUNCTION(0x10), [109] = FUNCTION(0xF70D), [110] = FUNCTION(0x10), [111] = FUNCTION(0xF70F),
	[112] = FUNCTION(0x10), [113] = FUNCTION(0xF712),
	[114] = { 0x05, 0xF746, 0 },
	[115] = { 0x01, 0xF729, 0 },
	[116] = { 0x0B, 0xF72C, 0 },
	[117] = { 0x7F, 0xF728, 0 },
	[118] = FUNCTION(0xF707),
	[119] = { 0x04, 0xF72B, 0 },
	[120] = FUNCTION(0xF705),
	[121] = { 0x0C, 0xF72D, 0 },
	[122] = FUNCTION(0xF704),
	[123] = { 0x1C, 0xF702, 0 },
	[124] = { 0x1D, 0xF703, 0 },
	[125] = { 0x1F, 0xF701, 0 },
	[126] = { 0x1E, 0xF700, 0 },
	[127] = NONE,
};

// ---- the built-in US layout ----

static const struct { char base, shifted; } g_usKeys[51] = {
	[0] = {'a', 'A'}, [1] = {'s', 'S'}, [2] = {'d', 'D'}, [3] = {'f', 'F'}, [4] = {'h', 'H'}, [5] = {'g', 'G'},
	[6] = {'z', 'Z'}, [7] = {'x', 'X'}, [8] = {'c', 'C'}, [9] = {'v', 'V'}, [11] = {'b', 'B'}, [12] = {'q', 'Q'},
	[13] = {'w', 'W'}, [14] = {'e', 'E'}, [15] = {'r', 'R'}, [16] = {'y', 'Y'}, [17] = {'t', 'T'},
	[18] = {'1', '!'}, [19] = {'2', '@'}, [20] = {'3', '#'}, [21] = {'4', '$'}, [22] = {'6', '^'}, [23] = {'5', '%'},
	[24] = {'=', '+'}, [25] = {'9', '('}, [26] = {'7', '&'}, [27] = {'-', '_'}, [28] = {'8', '*'}, [29] = {'0', ')'},
	[30] = {']', '}'}, [31] = {'o', 'O'}, [32] = {'u', 'U'}, [33] = {'[', '{'}, [34] = {'i', 'I'}, [35] = {'p', 'P'},
	[37] = {'l', 'L'}, [38] = {'j', 'J'}, [39] = {'\'', '"'}, [40] = {'k', 'K'}, [41] = {';', ':'}, [42] = {'\\', '|'},
	[43] = {',', '<'}, [44] = {'/', '?'}, [45] = {'n', 'N'}, [46] = {'m', 'M'}, [47] = {'.', '>'},
	[49] = {' ', ' '}, [50] = {'`', '~'},
};

static uint32_t usKeysym(void* context, int key, unsigned layer)
{
	if (key >= 51 || g_usKeys[key].base == 0 || (layer & DarlingKeyLayerOption))
		return 0;
	BOOL letter = g_usKeys[key].base >= 'a' && g_usKeys[key].base <= 'z';
	BOOL shifted = (layer & DarlingKeyLayerShift) != 0;
	if ((layer & DarlingKeyLayerCaps) && letter)
		shifted = !shifted;
	// The keysym of an ASCII character is its code.
	return (uint32_t) (shifted ? g_usKeys[key].shifted : g_usKeys[key].base);
}

static uint32_t usCodepoint(void* context, uint32_t keysym)
{
	return keysym;
}

static uint32_t noComposition(void* context, uint32_t base, uint32_t combining)
{
	return 0;
}

static UCKeyboardLayout* usLayout(uint32_t* length)
{
	static UCKeyboardLayout* layout;
	static uint32_t layoutLength;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		DarlingKeyLayoutSource source = { NULL, usKeysym, usCodepoint, noComposition };
		layout = DarlingCreateUnicodeKeyLayout(&source, &layoutLength);
	});
	*length = layoutLength;
	return layout;
}

// ---- reading a 'uchr' layout ----

// The characters key gives with the Carbon modifier state (the modifier flags shifted down by 8: Command
// 1, Shift 2, Caps Lock 4, Option 8, Control 16), 0 for none. Only plain characters and character
// sequences are read; the key that starts a dead-key sequence has no characters.
static size_t layoutCharacters(const UCKeyboardLayout* layout, uint32_t length, CGKeyCode key, uint32_t modifierState, UniChar* out, size_t max)
{
	const uint8_t* base = (const uint8_t*) layout;
	if (layout == NULL || length < sizeof(UCKeyboardLayout) || layout->keyboardTypeCount == 0 || key >= 128)
		return 0;
	// The layouts built here have one keyboard type entry for every type; use the first.
	const UCKeyboardTypeHeader* header = &layout->keyboardTypeList[0];
	if (header->keyModifiersToTableNumOffset > length || header->keyToCharTableIndexOffset > length)
		return 0;
	if (header->keyModifiersToTableNumOffset + sizeof(UCKeyModifiersToTableNum) > length ||
			header->keyToCharTableIndexOffset + sizeof(UCKeyToCharTableIndex) > length)
		return 0;

	const UCKeyModifiersToTableNum* modifiers = (const UCKeyModifiersToTableNum*) (base + header->keyModifiersToTableNumOffset);
	const UCKeyToCharTableIndex* tables = (const UCKeyToCharTableIndex*) (base + header->keyToCharTableIndexOffset);
	if (header->keyModifiersToTableNumOffset + sizeof(*modifiers) + modifiers->modifiersCount > length)
		return 0;
	unsigned table = modifierState < modifiers->modifiersCount ? modifiers->tableNum[modifierState] : modifiers->defaultTableNum;
	if (table >= tables->keyToCharTableCount || key >= tables->keyToCharTableSize)
		return 0;
	const uint32_t* offsets = tables->keyToCharTableOffsets;
	if (header->keyToCharTableIndexOffset + sizeof(*tables) + (uint64_t) tables->keyToCharTableCount * sizeof(uint32_t) > length)
		return 0;
	uint64_t tableOffset = offsets[table];
	if (tableOffset + (uint64_t) tables->keyToCharTableSize * sizeof(UCKeyOutput) > length)
		return 0;
	UCKeyOutput output = ((const UCKeyOutput*) (base + tableOffset))[key];

	switch (output & kUCKeyOutputTestForIndexMask)
	{
		case 0:
			// 0xFFFE and 0xFFFF mean no output.
			if (output >= 0xFFFE || max < 1)
				return 0;
			out[0] = output;
			return 1;
		case kUCKeyOutputSequenceIndexMask:
		{
			if (header->keySequenceDataIndexOffset == 0 || header->keySequenceDataIndexOffset + sizeof(UCKeySequenceDataIndex) > length)
				return 0;
			const UCKeySequenceDataIndex* sequences = (const UCKeySequenceDataIndex*) (base + header->keySequenceDataIndexOffset);
			unsigned index = output & kUCKeyOutputGetIndexMask;
			if (index >= sequences->charSequenceCount ||
					header->keySequenceDataIndexOffset + sizeof(*sequences) + (uint64_t) (sequences->charSequenceCount + 1) * sizeof(uint16_t) > length)
				return 0;
			// The offsets are in bytes from the start of the sequence data.
			uint32_t start = sequences->charSequenceOffsets[index], end = sequences->charSequenceOffsets[index + 1];
			uint64_t sequencesAt = header->keySequenceDataIndexOffset;
			if (end < start || sequencesAt + end > length || (end - start) % sizeof(UniChar) != 0 || (end - start) / sizeof(UniChar) > max)
				return 0;
			memcpy(out, (const uint8_t*) sequences + start, end - start);
			return (end - start) / sizeof(UniChar);
		}
		default:
			// A dead key: no characters until it is combined.
			return 0;
	}
}

static uint32_t carbonModifierState(CGEventFlags flags)
{
	uint32_t state = 0;
	if (flags & kCGEventFlagMaskCommand)
		state |= 1u;
	if (flags & kCGEventFlagMaskShift)
		state |= 2u;
	if (flags & kCGEventFlagMaskAlphaShift)
		state |= 4u;
	if (flags & kCGEventFlagMaskAlternate)
		state |= 8u;
	if (flags & kCGEventFlagMaskControl)
		state |= 16u;
	return state;
}

static size_t currentLayoutCharacters(CGKeyCode key, uint32_t modifierState, UniChar* out, size_t max)
{
	size_t count = 0;
	CFDictionaryRef info = _CGSCopyCurrentKeyboardLayoutInfo();
	if (info)
	{
		CFDataRef data = CFDictionaryGetValue(info, CFSTR("data"));
		if (data && CFDataGetLength(data) >= (CFIndex) sizeof(UCKeyboardLayout))
		{
			// The data of a CFData is not necessarily aligned for the layout's structures.
			size_t length = (size_t) CFDataGetLength(data);
			void* copy = malloc(length);
			if (copy)
			{
				memcpy(copy, CFDataGetBytePtr(data), length);
				count = layoutCharacters(copy, (uint32_t) length, key, modifierState, out, max);
				free(copy);
			}
		}
		CFRelease(info);
		return count;
	}

	uint32_t usLength;
	UCKeyboardLayout* us = usLayout(&usLength);
	return us ? layoutCharacters(us, usLength, key, modifierState, out, max) : 0;
}

size_t _CGKeyCharacters(CGKeyCode key, CGEventFlags flags, CGKeyCharactersKind kind, UniChar* out, size_t max)
{
	if (key >= 128 || out == NULL || max == 0)
		return 0;
	const FixedKey* fixed = &g_fixedKeys[key];
	if (fixed->cg != kLayoutKey)
	{
		UniChar c;
		switch (kind)
		{
			case kCGKeyCharactersDefault:
				c = fixed->cg;
				break;
			case kCGKeyCharactersWithModifiers:
				c = (flags & kCGEventFlagMaskShift) && fixed->nsShift ? fixed->nsShift : fixed->ns;
				break;
			default:
				// Only Shift counts when the modifiers are ignored.
				c = (flags & kCGEventFlagMaskShift) && fixed->nsShift ? fixed->nsShift : fixed->ns;
				break;
		}
		if (c == 0)
			return 0;
		out[0] = c;
		return 1;
	}

	uint32_t state;
	switch (kind)
	{
		case kCGKeyCharactersDefault:
			state = 0;
			break;
		case kCGKeyCharactersWithModifiers:
			state = carbonModifierState(flags);
			// Control on the space key gives NUL; no layout table has a place for that.
			if (key == 49 && (flags & kCGEventFlagMaskControl))
			{
				out[0] = 0;
				return 1;
			}
			break;
		default:
			state = carbonModifierState(flags) & 2u;
			break;
	}
	return currentLayoutCharacters(key, state, out, max);
}
