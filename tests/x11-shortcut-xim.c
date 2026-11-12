/* Local XIM interaction smoke test; not remote IME/composition coverage. */
#include "../AppKit/X11.backend/X11KeyEvent.h"
#include <X11/keysym.h>
#include <assert.h>
#include <locale.h>
#include <stdio.h>
#include <string.h>
#ifdef NDEBUG
#error Assertions are required
#endif
int main(void) {
    assert(setlocale(LC_ALL,"C.UTF-8"));
    assert(XSetLocaleModifiers("@im=none"));
    Display *display=XOpenDisplay(NULL); assert(display);
    Window window=XCreateSimpleWindow(display,DefaultRootWindow(display),0,0,80,80,0,0,0);
    XIM im=XOpenIM(display,NULL,NULL,NULL); assert(im);
    XIC ic=XCreateIC(im,XNInputStyle,XIMPreeditNothing|XIMStatusNothing,
                    XNClientWindow,window,XNFocusWindow,window,NULL); assert(ic);
    const unsigned states[]={0,ShiftMask,LockMask,ShiftMask|LockMask,
                             ControlMask,ControlMask|ShiftMask};
    for(unsigned i=0;i<sizeof(states)/sizeof(states[0]);++i) {
        XKeyEvent event; memset(&event,0,sizeof(event));
        event.display=display; event.window=window;
        event.root=DefaultRootWindow(display); event.type=KeyPress;
        event.same_screen=True; event.keycode=XKeysymToKeycode(display,XK_x);
        event.state=states[i];
        XKeyEvent saved=event;
        char before[32],after[32]; KeySym first,second; Status a,b;
        int n=Xutf8LookupString(ic,&event,before,sizeof(before),&first,&a);
        assert(n>=0 && n<(int)sizeof(before));
        KeySym shortcut=X11KeySymIgnoringModifiers(&event);
        assert(shortcut==((states[i]&ShiftMask)?XK_X:XK_x));
        assert(!memcmp(&event,&saved,sizeof(event)));
        int m=Xutf8LookupString(ic,&event,after,sizeof(after),&second,&b);
        assert(m==n && a==b && first==second && !memcmp(before,after,n));
        if (states[i]==LockMask) assert(n==1 && before[0]=='X' && shortcut==XK_x);
    }
    XDestroyIC(ic); XCloseIM(im); XDestroyWindow(display,window); XCloseDisplay(display);
    puts("PASS: local XIM text unchanged by shortcut lookup");
    return 0;
}
