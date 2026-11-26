/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// See CGSKeyCompose.h.
#import "CGSKeyCompose.h"
#import <Foundation/NSString.h>

#include <elfcalls.h>
#include <stdlib.h>
#include <string.h>
#include <xkbcommon/xkbcommon-compose.h>
#include <xkbcommon/xkbcommon.h>

extern struct elf_calls *_elfcalls;

// The longest sequence a Compose table has is shorter than this.
#define MAX_SEQUENCE 16

struct CGSKeyCompose {
    struct xkb_context *context;
    struct xkb_compose_table *table;
    struct xkb_compose_state *state;
    // The keysyms of the sequence in progress: what an abandoned sequence commits as text.
    uint32_t sequence[MAX_SEQUENCE];
    unsigned count;
};

#define XKB_COMPOSE_FUNCTIONS(X)                                                                                       \
    X(xkb_context_new)                                                                                                 \
    X(xkb_context_unref)                                                                                               \
    X(xkb_keysym_to_utf32)                                                                                             \
    X(xkb_compose_table_new_from_locale)                                                                               \
    X(xkb_compose_table_unref)                                                                                         \
    X(xkb_compose_state_new)                                                                                           \
    X(xkb_compose_state_unref)                                                                                         \
    X(xkb_compose_state_feed)                                                                                          \
    X(xkb_compose_state_reset)                                                                                         \
    X(xkb_compose_state_get_status)                                                                                    \
    X(xkb_compose_state_get_utf8)

static struct {
#define DECLARE(name) __typeof__(name) *name;
    XKB_COMPOSE_FUNCTIONS(DECLARE)
#undef DECLARE
} XKB;

// Loads libxkbcommon once; the compose functions came with version 0.5, older libraries make this fail.
static bool loadLibrary(void) {
    static int loaded; // 0: not tried yet, 1: loaded, -1: failed
    if (loaded != 0)
        return loaded > 0;
    loaded = -1;
    if (_elfcalls == NULL)
        return false;
    void *handle = _elfcalls->dlopen("libxkbcommon.so.0");
    if (handle == NULL)
        return false;
#define RESOLVE(name)                                                                                                  \
    if ((XKB.name = _elfcalls->dlsym(handle, #name)) == NULL)                                                          \
        return false;
    XKB_COMPOSE_FUNCTIONS(RESOLVE)
#undef RESOLVE
    loaded = 1;
    return true;
}

// The locale of the character data: LC_ALL, LC_CTYPE, LANG, in the order setlocale() resolves them.
static const char *composeLocale(void) {
    static const char *const names[] = {"LC_ALL", "LC_CTYPE", "LANG"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        const char *value = getenv(names[i]);
        if (value != NULL && *value != '\0')
            return value;
    }
    return "C";
}

CGSKeyCompose *CGSKeyComposeCreate(void) {
    if (!loadLibrary())
        return NULL;
    CGSKeyCompose *compose = calloc(1, sizeof(*compose));
    if (compose == NULL)
        return NULL;
    compose->context = XKB.xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (compose->context != NULL) {
        const char *locale = composeLocale();
        compose->table = XKB.xkb_compose_table_new_from_locale(compose->context, locale, XKB_COMPOSE_COMPILE_NO_FLAGS);
        // A locale the table lookup does not know (a name without a character set, say) gets the C locale's.
        if (compose->table == NULL && strcmp(locale, "C") != 0)
            compose->table = XKB.xkb_compose_table_new_from_locale(compose->context, "C", XKB_COMPOSE_COMPILE_NO_FLAGS);
    }
    if (compose->table != NULL)
        compose->state = XKB.xkb_compose_state_new(compose->table, XKB_COMPOSE_STATE_NO_FLAGS);
    if (compose->state == NULL) {
        CGSKeyComposeDestroy(compose);
        return NULL;
    }
    return compose;
}

void CGSKeyComposeDestroy(CGSKeyCompose *compose) {
    if (compose == NULL)
        return;
    if (compose->state != NULL)
        XKB.xkb_compose_state_unref(compose->state);
    if (compose->table != NULL)
        XKB.xkb_compose_table_unref(compose->table);
    if (compose->context != NULL)
        XKB.xkb_context_unref(compose->context);
    free(compose);
}

void CGSKeyComposeReset(CGSKeyCompose *compose) {
    XKB.xkb_compose_state_reset(compose->state);
    compose->count = 0;
}

static NSString *stringWithCodepoint(uint32_t codepoint) {
    if (codepoint == 0 || codepoint > 0x10FFFF)
        return @"";
    if (codepoint < 0x10000) {
        unichar character = (unichar) codepoint;
        return [NSString stringWithCharacters: &character length: 1];
    }
    codepoint -= 0x10000;
    unichar pair[2] = {(unichar) (0xD800 + (codepoint >> 10)), (unichar) (0xDC00 + (codepoint & 0x3FF))};
    return [NSString stringWithCharacters: pair length: 2];
}

// The text of a completed sequence ("" when there is none).
static NSString *composedText(CGSKeyCompose *compose) {
    char buffer[64];
    int length = XKB.xkb_compose_state_get_utf8(compose->state, buffer, sizeof(buffer));
    if (length <= 0 || length >= (int) sizeof(buffer))
        return @"";
    return [NSString stringWithUTF8String: buffer] ?: @"";
}

static bool isDeadKeysym(uint32_t keysym) {
    return keysym >= XKB_KEY_dead_grave && keysym <= XKB_KEY_dead_greek;
}

// The text a key of an abandoned sequence stands for: the character of an ordinary key, the spacing form of
// a dead key (what the dead key followed by Space composes), nothing for the Compose key itself. Leaves the
// compose state reset.
static NSString *spacingText(CGSKeyCompose *compose, uint32_t keysym) {
    NSString *text = @"";
    if (isDeadKeysym(keysym)) {
        XKB.xkb_compose_state_reset(compose->state);
        XKB.xkb_compose_state_feed(compose->state, keysym);
        XKB.xkb_compose_state_feed(compose->state, XKB_KEY_space);
        if (XKB.xkb_compose_state_get_status(compose->state) == XKB_COMPOSE_COMPOSED)
            text = composedText(compose);
        XKB.xkb_compose_state_reset(compose->state);
    } else if (keysym != XKB_KEY_Multi_key) {
        text = stringWithCodepoint(XKB.xkb_keysym_to_utf32(keysym));
    }
    return text;
}

// Whether a key can be part of a sequence: a character, a dead key or the Compose key. An editing or
// function key (an arrow, Backspace, Return) acts on its own and ends the sequence without completing it.
static bool keysymMaySequence(uint32_t keysym) {
    if (keysym == XKB_KEY_Multi_key || isDeadKeysym(keysym))
        return true;
    uint32_t codepoint = XKB.xkb_keysym_to_utf32(keysym);
    return codepoint >= 0x20 && codepoint != 0x7F;
}

CGSKeyComposeResult CGSKeyComposeFeed(CGSKeyCompose *compose, uint32_t keysym, bool shortcut, NSString **text) {
    *text = nil;
    if (keysym == XKB_KEY_NoSymbol || shortcut || !keysymMaySequence(keysym)) {
        CGSKeyComposeReset(compose);
        return CGSKeyComposeNone;
    }

    XKB.xkb_compose_state_feed(compose->state, keysym);
    switch (XKB.xkb_compose_state_get_status(compose->state)) {
    case XKB_COMPOSE_COMPOSING:
        if (compose->count < MAX_SEQUENCE)
            compose->sequence[compose->count++] = keysym;
        return CGSKeyComposeConsumed;

    case XKB_COMPOSE_COMPOSED: {
        NSString *composed = composedText(compose);
        CGSKeyComposeReset(compose);
        if ([composed length] == 0)
            return CGSKeyComposeNone;
        *text = composed;
        return CGSKeyComposeCommitted;
    }

    case XKB_COMPOSE_CANCELLED: {
        // No entry continues the sequence: the text is what was typed, the keys one after the other.
        NSMutableString *typed = [NSMutableString string];
        for (unsigned i = 0; i < compose->count; i++)
            [typed appendString: spacingText(compose, compose->sequence[i])];
        CGSKeyComposeReset(compose);
        // The key that broke the sequence may start another one.
        XKB.xkb_compose_state_feed(compose->state, keysym);
        enum xkb_compose_status status = XKB.xkb_compose_state_get_status(compose->state);
        if (status == XKB_COMPOSE_COMPOSING) {
            compose->sequence[compose->count++] = keysym;
            if ([typed length] == 0)
                return CGSKeyComposeConsumed;
        } else {
            [typed appendString: status == XKB_COMPOSE_COMPOSED ? composedText(compose) : spacingText(compose, keysym)];
            CGSKeyComposeReset(compose);
        }
        *text = typed;
        return CGSKeyComposeCommitted;
    }

    case XKB_COMPOSE_NOTHING:
    default:
        return CGSKeyComposeNone;
    }
}
