/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Dead keys and Compose sequences of the keyboard backends that read the keymap themselves (Wayland, and X11
// when no input method does the composing). The sequences are those of the Compose table of the locale
// (LC_ALL, LC_CTYPE, LANG, else C), interpreted by libxkbcommon, which is loaded with dlopen() when the first
// sequence is looked up. Compiled into each backend that uses it; nothing here is exported.
//
// A backend feeds the keysym of each key press and gets one of three answers:
//   None       the key is no part of a sequence: its characters are the ones the keymap gives,
//   Consumed   the key started or continued a sequence: it produces no event, nor does its release,
//   Committed  the key ended a sequence (completed or abandoned): its characters are the returned text.
// A sequence that no table entry continues commits the characters typed, a dead key as its spacing form, in
// the order typed.
#ifndef CGS_KEY_COMPOSE_H
#define CGS_KEY_COMPOSE_H

#include <stdbool.h>
#include <stdint.h>

@class NSString;

typedef struct CGSKeyCompose CGSKeyCompose;

typedef enum {
    CGSKeyComposeNone,
    CGSKeyComposeConsumed,
    CGSKeyComposeCommitted,
} CGSKeyComposeResult;

// NULL when libxkbcommon, or its compose support (version 0.5), is not available.
__attribute__((visibility("hidden"))) CGSKeyCompose *CGSKeyComposeCreate(void);
__attribute__((visibility("hidden"))) void CGSKeyComposeDestroy(CGSKeyCompose *compose);

// Feeds a key press (an X11 keysym). `shortcut` is set while Control or Command is held: a shortcut is not
// text, so the key is no part of a sequence and ends the one in progress.
__attribute__((visibility("hidden"))) CGSKeyComposeResult
CGSKeyComposeFeed(CGSKeyCompose *compose, uint32_t keysym, bool shortcut, NSString **text);

// Drops the sequence in progress (the keymap or the focus changed, or the keyboard goes away).
__attribute__((visibility("hidden"))) void CGSKeyComposeReset(CGSKeyCompose *compose);

#endif
