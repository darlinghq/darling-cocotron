/* cc tests/x11-shortcut-characters.c -lX11 -o /tmp/x11-shortcuts
 * xvfb-run -a /tmp/x11-shortcuts
 * Real Xlib fallback lookup, default US layout; not full AppKit dispatch. */
#include "../AppKit/X11.backend/X11KeyEvent.h"
#include <X11/keysym.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef NDEBUG
#error This test requires assertions
#endif
int main(int argc, char **argv) {
    Display *display = XOpenDisplay(NULL);
    assert(display);
    KeySym keys[] = {XK_x, XK_1};
    KeySym unshifted[] = {XK_x, XK_1};
    KeySym shifted[] = {XK_X, XK_exclam};
    unsigned group=0, count=2;
    if (argc==5) {
        keys[0]=XStringToKeysym(argv[1]);
        unshifted[0]=XStringToKeysym(argv[2]);
        shifted[0]=XStringToKeysym(argv[3]);
        group=(unsigned)strtoul(argv[4],NULL,10);
        assert(keys[0] && unshifted[0] && shifted[0] && group<4);
        count=1;
    } else assert(argc==1);
    for (unsigned k=0;k<count;++k) {
        for (unsigned state=0;state<256;++state) {
            XKeyEvent event;
            memset(&event,0,sizeof(event));
            event.display=display;
            event.type=KeyPress;
            event.window=event.root=DefaultRootWindow(display);
            event.keycode=XKeysymToKeycode(display,keys[k]);
            event.state=XkbBuildCoreState(state,group);
            unsigned originalState=event.state;
            event.same_screen=True;
            assert(event.keycode);
            assert(X11KeySymIgnoringModifiers(&event)==
                   ((state & ShiftMask) ? shifted[k] : unshifted[k]));
            assert(event.state==originalState);
            event.type=KeyRelease;
            assert(X11KeySymIgnoringModifiers(&event)==
                   ((state & ShiftMask) ? shifted[k] : unshifted[k]));
        }
    }
    XCloseDisplay(display);
    printf("PASS: %u X11 shortcut lookups, group %u\n",count*512,group);
    return 0;
}
