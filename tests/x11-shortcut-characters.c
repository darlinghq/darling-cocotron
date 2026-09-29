/* cc tests/x11-shortcut-characters.c -lX11 -o /tmp/x11-shortcuts
 * xvfb-run -a /tmp/x11-shortcuts
 * Real Xlib fallback lookup, default US layout; not full AppKit dispatch. */
#include "../AppKit/X11.backend/X11KeyEvent.h"
#include <X11/keysym.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#ifdef NDEBUG
#error This test requires assertions
#endif
int main(void) {
    Display *display = XOpenDisplay(NULL);
    assert(display);
    const KeySym keys[] = {XK_x, XK_1};
    const KeySym shifted[] = {XK_X, XK_exclam};
    for (unsigned k=0;k<2;++k) {
        for (unsigned state=0;state<256;++state) {
            XKeyEvent event;
            memset(&event,0,sizeof(event));
            event.display=display;
            event.type=KeyPress;
            event.window=event.root=DefaultRootWindow(display);
            event.keycode=XKeysymToKeycode(display,keys[k]);
            event.state=state;
            event.same_screen=True;
            assert(event.keycode);
            assert(X11KeySymIgnoringModifiers(&event)==
                   ((state & ShiftMask) ? shifted[k] : keys[k]));
            assert(event.state==state);
            event.type=KeyRelease;
            assert(X11KeySymIgnoringModifiers(&event)==
                   ((state & ShiftMask) ? shifted[k] : keys[k]));
        }
    }
    XCloseDisplay(display);
    puts("PASS: 1024 X11 shortcut lookups preserve Shift and ignore other modifiers");
    return 0;
}
