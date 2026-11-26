// The Unicode string of a keyboard event made with CGEventCreateKeyboardEvent() and the characters of the
// NSEvent made from it.
//
// The string is what the key types with no modifiers in the keyboard layout; flags set on the event
// afterwards do not change it. NSEvent applies the event's flags to the key code itself: characters has
// Shift, Caps Lock and Control applied, charactersIgnoringModifiers only Shift. A string set with
// CGEventKeyboardSetUnicodeString() is what NSEvent reports as it is. Keys that give the same on every
// layout (Return, Tab, Delete, the arrow, function and keypad keys) are checked as well.
//
// Public API only. The expected values come from black-box observation on macOS 26.7.3 and 10.14.4 (the
// test passes unchanged there, on a US layout); see mac-probes/cgevent-keyboard-unicode in the
// coordination repository for the full tables.
//
// "qwertz" as the first argument runs the layout check described there instead.
// Layout dependent keys assume a US layout (the built-in one is US when no window system is connected).
//
// Copyright (C) 2026 Lubos Dolezel
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static int g_failed;

#define CHECK(cond, ...) do { if (!(cond)) { g_failed++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSString *hex(NSString *s)
{
	NSMutableString *r = [NSMutableString string];
	for (NSUInteger i = 0; i < [s length]; i++)
		[r appendFormat: @"%s%04X", i ? "+" : "", [s characterAtIndex: i]];
	return [r length] ? r : @"-";
}

static NSString *cgString(CGEventRef e)
{
	UniChar buffer[16];
	UniCharCount length = 0;
	CGEventKeyboardGetUnicodeString(e, 16, &length, buffer);
	return [NSString stringWithCharacters: buffer length: length];
}

static void expectString(const char *what, NSString *got, unichar want)
{
	NSString *wanted = [NSString stringWithCharacters: &want length: 1];
	CHECK([got isEqualToString: wanted], "%s: got %s, want %s", what, [hex(got) UTF8String], [hex(wanted) UTF8String]);
}

// The CGEvent string and NSEvent's characters / charactersIgnoringModifiers of a key down event with the flags.
static void expectKey(const char *what, CGKeyCode key, CGEventFlags flags, unichar cg, unichar chars, unichar ignoring)
{
	CGEventRef e = CGEventCreateKeyboardEvent(NULL, key, true);
	if (flags)
		CGEventSetFlags(e, flags);
	char name[128];
	snprintf(name, sizeof(name), "%s cg", what);
	expectString(name, cgString(e), cg);
	NSEvent *ns = [NSEvent eventWithCGEvent: e];
	CHECK(ns != nil, "%s: no NSEvent", what);
	if (ns && [ns type] == NSKeyDown) {
		snprintf(name, sizeof(name), "%s characters", what);
		expectString(name, [ns characters], chars);
		snprintf(name, sizeof(name), "%s charactersIgnoringModifiers", what);
		expectString(name, [ns charactersIgnoringModifiers], ignoring);
	}
	CFRelease(e);
}

int main(int argc, char **argv)
{
	@autoreleasepool {
		// "qwertz": the layout of the window system is a German one (setxkbmap de on X11), which swaps
		// the keys of Y and Z; the characters follow the layout, not a fixed table.
		if (argc > 1 && strcmp(argv[1], "qwertz") == 0) {
			expectKey("key 6 (z on US)", 6, 0, 'y', 'y', 'y');
			expectKey("key 16 (y on US)", 16, 0, 'z', 'z', 'z');
			expectKey("key 16 +shift", 16, kCGEventFlagMaskShift, 'z', 'Z', 'Z');
			expectKey("Return", 36, 0, 0x0D, 0x0D, 0x0D);
			printf(g_failed ? "%d failures\n" : "PASS\n", g_failed);
			return g_failed ? 1 : 0;
		}

		// letters and digits, no modifiers
		expectKey("a", 0, 0, 'a', 'a', 'a');
		expectKey("b", 11, 0, 'b', 'b', 'b');
		expectKey("1", 18, 0, '1', '1', '1');
		expectKey("0", 29, 0, '0', '0', '0');
		expectKey("=", 24, 0, '=', '=', '=');
		expectKey("-", 27, 0, '-', '-', '-');
		expectKey("`", 50, 0, '`', '`', '`');
		expectKey("space", 49, 0, ' ', ' ', ' ');

		// flags set afterwards: the CGEvent string stays, NSEvent applies them
		expectKey("a+shift", 0, kCGEventFlagMaskShift, 'a', 'A', 'A');
		expectKey("1+shift", 18, kCGEventFlagMaskShift, '1', '!', '!');
		expectKey("a+caps", 0, kCGEventFlagMaskAlphaShift, 'a', 'A', 'a');
		expectKey("1+caps", 18, kCGEventFlagMaskAlphaShift, '1', '1', '1');
		expectKey("a+ctrl", 0, kCGEventFlagMaskControl, 'a', 0x01, 'a');
		expectKey("z+ctrl", 6, kCGEventFlagMaskControl, 'z', 0x1A, 'z');
		expectKey("a+cmd", 0, kCGEventFlagMaskCommand, 'a', 'a', 'a');
		expectKey("space+ctrl", 49, kCGEventFlagMaskControl, ' ', 0x00, ' ');

		// keys that give the same on every layout
		expectKey("Return", 36, 0, 0x0D, 0x0D, 0x0D);
		expectKey("Return+shift", 36, kCGEventFlagMaskShift, 0x0D, 0x0D, 0x0D);
		expectKey("Tab", 48, 0, 0x09, 0x09, 0x09);
		expectKey("Tab+shift", 48, kCGEventFlagMaskShift, 0x09, 0x19, 0x19);
		expectKey("Escape", 53, 0, 0x1B, 0x1B, 0x1B);
		expectKey("Delete", 51, 0, 0x08, 0x7F, 0x7F);
		expectKey("ForwardDelete", 117, 0, 0x7F, 0xF728, 0xF728);
		expectKey("Left", 123, 0, 0x1C, 0xF702, 0xF702);
		expectKey("Right", 124, 0, 0x1D, 0xF703, 0xF703);
		expectKey("Down", 125, 0, 0x1F, 0xF701, 0xF701);
		expectKey("Up", 126, 0, 0x1E, 0xF700, 0xF700);
		expectKey("Up+shift", 126, kCGEventFlagMaskShift, 0x1E, 0xF700, 0xF700);
		expectKey("Home", 115, 0, 0x01, 0xF729, 0xF729);
		expectKey("End", 119, 0, 0x04, 0xF72B, 0xF72B);
		expectKey("PageUp", 116, 0, 0x0B, 0xF72C, 0xF72C);
		expectKey("PageDown", 121, 0, 0x0C, 0xF72D, 0xF72D);
		expectKey("F1", 122, 0, 0x10, 0xF704, 0xF704);
		expectKey("F2", 120, 0, 0x10, 0xF705, 0xF705);
		expectKey("F5", 96, 0, 0x10, 0xF708, 0xF708);
		expectKey("keypad 0", 82, 0, '0', '0', '0');
		expectKey("keypad 9", 92, 0, '9', '9', '9');
		expectKey("keypad *", 67, 0, '*', '*', '*');
		expectKey("keypad +", 69, 0, '+', '+', '+');
		expectKey("keypad Enter", 76, 0, 0x03, 0x03, 0x03);

		// key up events have the string too
		CGEventRef up = CGEventCreateKeyboardEvent(NULL, 0, false);
		expectString("a up cg", cgString(up), 'a');
		NSEvent *ns = [NSEvent eventWithCGEvent: up];
		CHECK(ns && [ns type] == NSKeyUp, "key up type");
		expectString("a up characters", [ns characters], 'a');
		CFRelease(up);

		// no characters: modifier keys (flags changed events) and key codes that are not keys
		for (CGKeyCode key = 54; key <= 63; key++) {
			CGEventRef e = CGEventCreateKeyboardEvent(NULL, key, true);
			CHECK([cgString(e) length] == 0, "modifier key %d has a string", key);
			CFRelease(e);
		}
		CGEventRef big = CGEventCreateKeyboardEvent(NULL, 300, true);
		CHECK([cgString(big) length] == 0, "key code 300 has a string");
		CFRelease(big);

		// a copy has the string, and a string set by the client wins over the key code and the flags
		CGEventRef e = CGEventCreateKeyboardEvent(NULL, 0, true);
		CGEventRef copy = CGEventCreateCopy(e);
		expectString("copy cg", cgString(copy), 'a');
		CFRelease(copy);
		UniChar q = 'Q';
		CGEventKeyboardSetUnicodeString(e, 1, &q);
		CGEventSetFlags(e, kCGEventFlagMaskShift);
		expectString("explicit cg", cgString(e), 'Q');
		ns = [NSEvent eventWithCGEvent: e];
		expectString("explicit characters", [ns characters], 'Q');
		expectString("explicit charactersIgnoringModifiers", [ns charactersIgnoringModifiers], 'Q');
		copy = CGEventCreateCopy(e);
		ns = [NSEvent eventWithCGEvent: copy];
		expectString("explicit copy characters", [ns characters], 'Q');
		CFRelease(copy);
		CFRelease(e);

		// a source does not change the string
		CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
		e = CGEventCreateKeyboardEvent(source, 0, true);
		expectString("hid source cg", cgString(e), 'a');
		CFRelease(e);
		CFRelease(source);
	}
	printf(g_failed ? "%d failures\n" : "PASS\n", g_failed);
	return g_failed ? 1 : 0;
}
