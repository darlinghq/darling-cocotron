/* Copyright (C) 2026 Lubos Dolezel

   Licensed under the MIT license, the same as the rest of this project. */

// The keysym translation shared by the X11 and Wayland display backends:
// printable keysyms map to their code point, the function keys map to the
// private-use codes AppKit documents (NSUpArrowFunctionKey, ...), and keysyms
// without a mapping give 0. The helper lives in CoreGraphics (outside its X11
// backend), so no backend depends on another.
#import <AppKit/AppKit.h>
#include <stdio.h>

extern uint32_t CGSKeySymToUnicode(uint32_t keySym);

static int failures;

static void expect(uint32_t keySym, uint32_t want, const char *what) {
    uint32_t got = CGSKeySymToUnicode(keySym);
    if (got != want) {
        printf("FAIL: %s: keysym 0x%x -> 0x%x, expected 0x%x\n", what, keySym, got, want);
        failures++;
    }
}

int main(void) {
    expect(0x0061, 0x0061, "ASCII letter");
    expect(0x0020, 0x0020, "space");
    expect(0x00e9, 0x00e9, "Latin-1 letter");
    expect(0xff0d, 0x000d, "Return");
    expect(0xff52, NSUpArrowFunctionKey, "Up");
    expect(0xff54, NSDownArrowFunctionKey, "Down");
    expect(0xff51, NSLeftArrowFunctionKey, "Left");
    expect(0xffbe, NSF1FunctionKey, "F1");
    expect(0xffc9, NSF12FunctionKey, "F12");
    expect(0xffff, NSDeleteFunctionKey, "Delete");
    expect(0x00000000, 0, "NoSymbol");
    expect(0x0fffffff, 0, "unmapped keysym");
    if (failures == 0)
        puts("keysym to unicode: PASS");
    return failures != 0;
}
