/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The compose callback of DarlingKeyLayoutSource (DarlingUnicodeKeyLayout.h), using CoreFoundation's
// canonical composition, and the character of a keysym for a keysym that is already a Unicode
// character (X11 keysyms 0x01000000 + code point). Shared by the X11 and Wayland backends.
#ifndef DARLING_UNICODE_KEY_LAYOUT_COMPOSE_H
#define DARLING_UNICODE_KEY_LAYOUT_COMPOSE_H

#include <CoreFoundation/CFString.h>
#include <stdint.h>

static inline uint32_t DarlingComposeCharacters(void *context, uint32_t base, uint32_t combining) {
    (void) context;
    if (base > 0xFFFF || combining > 0xFFFF)
        return 0;
    UniChar units[2] = {(UniChar) base, (UniChar) combining};
    CFMutableStringRef string = CFStringCreateMutable(NULL, 0);
    if (string == NULL)
        return 0;
    CFStringAppendCharacters(string, units, 2);
    CFStringNormalize(string, kCFStringNormalizationFormC);
    uint32_t result = 0;
    if (CFStringGetLength(string) == 1)
        result = CFStringGetCharacterAtIndex(string, 0);
    CFRelease(string);
    return result;
}

static inline uint32_t DarlingUnicodeKeysymCharacter(uint32_t keysym) {
    if ((keysym & 0xff000000) == 0x01000000)
        return keysym & 0x00ffffff;
    return 0;
}

#endif
