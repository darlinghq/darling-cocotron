// Host test for X11KeyEventPlanFor() in AppKit/X11.backend/X11KeyEvent.h, and the event pump's use of it against a
// real XIM server. Two modes (build: cc x11-key-event-plan.c -lX11):
//   table            the decision table and a model of the Shift flag, no X server needed.
//   pump new|old SECS  a window with an input context on a display whose XMODIFIERS name an XIM server; reads
//                    events for SECS seconds the way the X11 backend does, with the filter first for every key
//                    ("new") or with a modifier handled ahead of the filter ("old", the previous behaviour), and
//                    prints what it would report. Run by tests/x11-key-event-plan.sh against a private fcitx5.
#include "../AppKit/X11.backend/X11KeyEvent.h"
#include <X11/keysym.h>
#include <assert.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#ifdef NDEBUG
#error Assertions are required
#endif

static void table(void) {
    for (int sent = 0; sent < 2; ++sent) {
        // A modifier the input method took changes nothing; one that came through is tracked and reported.
        X11KeyEventPlan kept = X11KeyEventPlanFor(true, true, sent);
        assert(!kept.trackModifier && !kept.resyncFromState && !kept.lookUpText);
        X11KeyEventPlan seen = X11KeyEventPlanFor(true, false, sent);
        assert(seen.trackModifier && !seen.resyncFromState && !seen.lookUpText);
        // A key that is not a modifier is looked up only when the filter let it through; the flags are
        // corrected from the state of events this client did not send, filtered or not.
        X11KeyEventPlan taken = X11KeyEventPlanFor(false, true, sent);
        assert(!taken.trackModifier && !taken.lookUpText);
        assert(taken.resyncFromState == !sent);
        X11KeyEventPlan text = X11KeyEventPlanFor(false, false, sent);
        assert(!text.trackModifier && text.lookUpText);
        assert(text.resyncFromState == !sent);
    }
    puts("PASS: key event plan decision table");
}

/* A model of what the X11 backend does with the Shift flag: the backend itself is Objective-C and cannot be built
 * here, so this applies X11KeyEventPlanFor() the way -[X11Display postXEvent:] does, for the one modifier the test
 * can type. `state` is the modifier state the server put in the event. */
typedef struct {
    int shiftDown;      /* the flag the application is told of */
    unsigned posted;    /* flagsChanged events posted for the key itself */
    unsigned resynced;  /* flagsChanged events posted for a flag corrected from the event's state */
    unsigned texts;     /* key down and up events posted */
} Model;

static void modelKey(Model *model, bool isShift, bool pressed, bool filtered, bool sent, unsigned state) {
    X11KeyEventPlan plan = X11KeyEventPlanFor(isShift, filtered, sent);
    if (isShift) {
        if (plan.trackModifier) {
            model->shiftDown = pressed;
            model->posted++;
        }
        return;
    }
    if (plan.resyncFromState && model->shiftDown != !!(state & ShiftMask)) {
        model->shiftDown = !!(state & ShiftMask);
        model->resynced++;
    }
    if (plan.lookUpText)
        model->texts++;
}

static void model(void) {
    /* The input method forwards the press and keeps the release (an engine that switches on Shift): the filter
     * saw the release first, so nothing was tracked for it, and the flag is still down until the server's own
     * state corrects it on the next key. */
    Model m = {0, 0, 0, 0};
    modelKey(&m, true, true, true, false, 0);          /* press, filtered */
    modelKey(&m, true, true, false, false, 0);         /* the forwarded copy of the press */
    assert(m.shiftDown && m.posted == 1);
    modelKey(&m, true, false, true, false, ShiftMask); /* release, kept by the input method */
    assert(m.shiftDown && m.posted == 1);              /* nothing changed behind the application's back */
    modelKey(&m, false, true, false, false, 0);        /* the next key: the server says Shift is up */
    assert(!m.shiftDown && m.resynced == 1 && m.texts == 1);

    /* Both kept: the application never heard of the Shift and still agrees with the server. */
    Model k = {0, 0, 0, 0};
    modelKey(&k, true, true, true, false, 0);
    modelKey(&k, true, false, true, false, ShiftMask);
    modelKey(&k, false, true, false, false, 0);
    assert(!k.shiftDown && k.posted == 0 && k.resynced == 0 && k.texts == 1);

    /* Both forwarded back: each reported once. */
    Model f = {0, 0, 0, 0};
    modelKey(&f, true, true, true, false, 0);
    modelKey(&f, true, true, false, false, 0);
    modelKey(&f, true, false, true, false, ShiftMask);
    modelKey(&f, true, false, false, false, ShiftMask);
    assert(!f.shiftDown && f.posted == 2 && f.resynced == 0);
    puts("PASS: a modifier the input method keeps is corrected by the next event's state");
}

static int isShift(Display *display, unsigned keycode) {
    KeySym symbol = XkbKeycodeToKeysym(display, keycode, 0, 0);
    return symbol == XK_Shift_L || symbol == XK_Shift_R;
}

static void pump(int newOrder, int seconds) {
    assert(setlocale(LC_ALL, "C.UTF-8"));
    assert(XSetLocaleModifiers(""));
    Display *display = XOpenDisplay(NULL);
    assert(display);
    XIM im = XOpenIM(display, NULL, NULL, NULL);
    assert(im);
    Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, 100, 100, 0, 0, 0);
    XSelectInput(display, window, KeyPressMask | KeyReleaseMask);
    XMapWindow(display, window);
    XIC ic = XCreateIC(im, XNInputStyle, XIMPreeditNothing | XIMStatusNothing, XNClientWindow, window,
                       XNFocusWindow, window, NULL);
    assert(ic);
    XSetICFocus(ic);
    XSetInputFocus(display, window, RevertToParent, CurrentTime);
    XFlush(display);
    puts("READY");
    fflush(stdout);

    Model m = {0, 0, 0, 0};
    time_t end = time(NULL) + seconds;
    while (time(NULL) < end) {
        while (XPending(display)) {
            XEvent event;
            XNextEvent(display, &event);
            if (event.type != KeyPress && event.type != KeyRelease) {
                XFilterEvent(&event, None);
                continue;
            }
            int pressed = event.type == KeyPress;
            int shift = isShift(display, event.xkey.keycode);
            // "old" is the pump before the change: a modifier never reaches the filter.
            int filtered = (newOrder || !shift) ? XFilterEvent(&event, None) : 0;
            unsigned postedBefore = m.posted;
            modelKey(&m, shift, pressed, filtered, event.xany.send_event, event.xkey.state);
            if (m.posted != postedBefore)
                printf("flagsChanged %s shift=%d\n", pressed ? "press" : "release", m.shiftDown);
            fflush(stdout);
        }
        usleep(20000);
    }
    printf("SUMMARY posted=%u texts=%u shift=%d\n", m.posted, m.texts, m.shiftDown);
    XDestroyIC(ic);
    XCloseIM(im);
    XCloseDisplay(display);
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "table")) {
        table();
        model();
        return 0;
    }
    if (argc == 4 && !strcmp(argv[1], "pump") && (!strcmp(argv[2], "new") || !strcmp(argv[2], "old"))) {
        pump(!strcmp(argv[2], "new"), atoi(argv[3]));
        return 0;
    }
    fprintf(stderr, "usage: %s table | pump new|old SECONDS\n", argv[0]);
    return 2;
}
