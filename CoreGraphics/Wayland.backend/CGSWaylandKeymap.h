/* Copyright (C) 2026 Lubos Dolezel

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

// The keymap the compositor gives the client that owns the keyboard, as the keyboard layout the Text
// Input Sources API describes. The keyboard layout of the window system belongs to CoreGraphics'
// connection (the same connection AppKit's windows live on), so the 'uchr' layout is built here from
// the xkb keymap and the layout group the compositor reports.

#ifndef CGSWAYLANDKEYMAP_H
#define CGSWAYLANDKEYMAP_H

#import <Foundation/NSObject.h>
#include <stdint.h>
#import "../CGSKeyCompose.h"

@class CGSKeyboardLayout;
struct xkb_context;
struct xkb_keymap;
struct xkb_state;

@interface CGSWaylandKeymap : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    struct xkb_context *_context;
    struct xkb_keymap *_keymap;
    struct xkb_state *_state;
    // The layout built from the keymap and group, until either changes.
    CGSKeyboardLayout *_layout;
    // The dead key and compose sequences of the locale (CGSKeyCompose.h), loaded when the first key needs them.
    struct CGSKeyCompose *_compose;
    BOOL _composeLoaded;
}

// Starts with the system default layout (the evdev rules, honouring XKB_DEFAULT_*), which describes
// the keyboard until a compositor's keymap arrives (a compositor with no input device never sends
// one). Returns nil when xkbcommon is unavailable.
- (instancetype) init;

// The wl_keyboard.keymap event: a format and a file descriptor with size bytes, which is closed
// here. A keymap that cannot be used (no_keymap, an empty or unreadable map) leaves the one in force.
- (void) installKeymapWithFormat: (uint32_t) format fd: (int) fd size: (uint32_t) size;

// The wl_keyboard.modifiers event, which carries the layout group.
- (void) updateDepressed: (uint32_t) depressed latched: (uint32_t) latched locked: (uint32_t) locked
                   group: (uint32_t) group;

// The layout of the keymap in its current group, or nil. The caller releases it.
- (CGSKeyboardLayout *) copyLayout;

// What the keyboard decoder asks of the keymap in force and its modifier state. All of it answers
// from the xkb state the wl_keyboard.modifiers events keep.

// Whether a keymap is in force (the keyboard is ignored without one).
- (BOOL) isUsable;
// The wl_keyboard.keymap event, as above, but telling whether a new keymap came into force.
- (BOOL) installKeymapAndReport: (uint32_t) format fd: (int) fd size: (uint32_t) size;
// The modifier key the key code (an xkb key code: the evdev code plus 8) is, as a virtual key code, or -1.
- (int) modifierKeyCodeForKeycode: (uint32_t) keycode;
// The modifier flags (CGEventFlags bits) the xkb state has in effect, without the device-dependent bits.
- (uint64_t) activeModifierFlags;
// The text the key produces in the current state, with the private-use code of the function keys
// (arrows, F keys, ...) for the keys that produce no text. Never nil.
- (NSString *) charactersForKeycode: (uint32_t) keycode;
// The character of the key with only Shift taken into account. Never nil.
- (NSString *) unmodifiedCharactersForKeycode: (uint32_t) keycode;
- (BOOL) keyRepeats: (uint32_t) keycode;

// Feeds the key press (an xkb key code) to the sequence in progress. A completed sequence returns its text; one
// that no entry of the table continues returns the characters of its keys and of this one, as typed.
- (CGSKeyComposeResult) composeKeycode: (uint32_t) keycode text: (NSString **) text;
// Drops the sequence in progress (the keymap or the focus changed, or the keyboard goes away).
- (void) resetCompose;
// No modifier in effect (the focus changed).
- (void) resetModifiers;
// The index and name of the layout group in effect, -1 and nil without a keymap.
- (int) layoutGroup;
- (NSString *) layoutName;

@end

#endif
