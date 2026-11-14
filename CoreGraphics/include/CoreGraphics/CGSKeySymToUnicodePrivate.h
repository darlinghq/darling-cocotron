#ifndef CGSKEYSYMTOUNICODEPRIVATE_H
#define CGSKEYSYMTOUNICODEPRIVATE_H
#include <stdint.h>

// Maps an X11 keysym (xkbcommon keysyms have the same values) to a Unicode code
// point, or to the private-use code AppKit uses for a function key
// (NSUpArrowFunctionKey and the like). Returns 0 when the keysym has no mapping.
// Used by CoreGraphics's X11 backend and by AppKit's X11 and Wayland backends.
uint32_t CGSKeySymToUnicode(uint32_t keySym);

#endif
