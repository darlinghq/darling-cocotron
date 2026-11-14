#ifndef DARLINGKEYSYMTOUNICODE_H
#define DARLINGKEYSYMTOUNICODE_H
#include <stdint.h>

// Maps an X11 keysym (the values xkbcommon uses as well) to a Unicode code point,
// or to the private-use code AppKit uses for a function key (NSUpArrowFunctionKey
// and the like). Returns 0 when the keysym has no mapping. Shared by the X11 and
// Wayland display backends.
uint32_t DarlingKeySymToUnicode(uint32_t keySym);

#endif
