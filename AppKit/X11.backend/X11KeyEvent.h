#ifndef COCOTRON_X11_KEY_EVENT_H
#define COCOTRON_X11_KEY_EVENT_H

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/XKBlib.h>

/* Retain the active layout group and Shift, but not Caps Lock, Control,
 * Option, Command or level-switch modifiers. Do not mutate the real event or
 * feed this synthetic lookup through XIM: composed input belongs in characters. */
static inline KeySym X11KeySymIgnoringModifiers(const XKeyEvent *event) {
    XKeyEvent lookup = *event;
    lookup.state = XkbBuildCoreState(event->state & ShiftMask,
                                    XkbGroupForCoreState(event->state));
    KeySym symbol = NoSymbol;
    char ignored[32];
    XLookupString(&lookup, ignored, sizeof(ignored), &symbol, NULL);
    return symbol;
}

#endif
