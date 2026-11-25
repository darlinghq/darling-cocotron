#ifndef COCOTRON_X11_KEY_EVENT_H
#define COCOTRON_X11_KEY_EVENT_H

#include <stdbool.h>
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

/* What the event pump does with one key event once XFilterEvent() has seen it. Xlib requires every event to go
 * through the filter, and an input method only hears of the keys that do, so the filter runs first for every
 * key. A filtered key is the input method's: it forwards the key back (as a copy the filter lets through) or
 * keeps it, so the application acts on the unfiltered copy and on nothing else. That holds for a modifier too:
 * one the input method keeps changes nothing here, because tracking it would make the flags follow a key whose
 * matching release may be kept or forwarded independently, and nothing would tell the application. A modifier
 * that is lost this way is corrected by the modifier state of the next key or pointer event, which the X server
 * fills in whatever the input method did. */
typedef struct {
    bool trackModifier;   /* a modifier: update the reported flags and the held keys, post a flagsChanged */
    bool resyncFromState; /* correct the reported flags from the event's modifier state */
    bool lookUpText;      /* look the key up and post it as a key down or up */
} X11KeyEventPlan;

static inline X11KeyEventPlan X11KeyEventPlanFor(bool isModifier, bool filtered, bool sentByClient) {
    X11KeyEventPlan plan = {false, false, false};
    if (isModifier) {
        plan.trackModifier = !filtered;
        return plan;
    }
    /* Events another client sent carry whatever state it chose. */
    plan.resyncFromState = !sentByClient;
    plan.lookUpText = !filtered;
    return plan;
}

#endif
