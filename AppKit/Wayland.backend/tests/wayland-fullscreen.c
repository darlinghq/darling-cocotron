// Drives WaylandFullscreen.h against a real compositor: the requests sent for
// fullscreen, what the compositor answers, and how the size comes back.
// Run it through wayland-fullscreen.sh (private headless sway, two outputs).
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"
#include "../WaylandFullscreen.h"

struct wl_proxy *WaylandMarshal(struct wl_proxy *proxy, uint32_t opcode,
                                const struct wl_interface *interface,
                                uint32_t flags, union wl_argument *args)
{
    return wl_proxy_marshal_array_flags(proxy, opcode, interface,
                                        wl_proxy_get_version(proxy), flags, args);
}

static unsigned checks, failures;
#define CHECK(x) do { checks++; if (!(x)) { failures++; fprintf(stderr, "line %d: %s\n", __LINE__, #x); } } while (0)

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm;
static struct { struct wl_output *output; int w, h; } outputs[4];
static int noutputs;

static void o_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph,
                       int32_t sp, const char *mk, const char *md, int32_t t) {}
static void o_mode(void *d, struct wl_output *o, uint32_t f, int32_t w, int32_t h, int32_t r) {
    for (int i = 0; i < noutputs; i++)
        if (outputs[i].output == o && (f & 1)) { outputs[i].w = w; outputs[i].h = h; }
}
static void o_done(void *d, struct wl_output *o) {}
static void o_scale(void *d, struct wl_output *o, int32_t f) {}
static const struct wl_output_listener o_listener = {o_geometry, o_mode, o_done, o_scale};

static void global(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
    if (!strcmp(i, "wl_compositor")) compositor = wl_registry_bind(r, n, &wl_compositor_interface, 4);
    else if (!strcmp(i, "wl_shm")) shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
    else if (!strcmp(i, "xdg_wm_base")) wm = wl_registry_bind(r, n, &xdg_wm_base_interface, 1);
    else if (!strcmp(i, "wl_output") && noutputs < 4) {
        outputs[noutputs].output = wl_registry_bind(r, n, &wl_output_interface, 2);
        wl_output_add_listener(outputs[noutputs++].output, &o_listener, NULL);
    }
}
static void global_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener r_listener = {global, global_remove};

struct window {
    bool entered[4]; // per outputs[]: wl_surface.enter seen, leave not
    int32_t unsetConfigureW, unsetConfigureH; // what the compositor sent when leaving
    struct wl_surface *surface;
    struct xdg_surface *xdg;
    struct xdg_toplevel *toplevel;
    int32_t pendingW, pendingH, w, h; // configured; what the backend would resize to
    bool pendingFullscreen, fullscreen;
    int configures;
    WaylandFullscreenTracker tracker;
};

static void s_enter(void *d, struct wl_surface *s, struct wl_output *o) {
    struct window *win = d;
    for (int i = 0; i < noutputs; i++) if (outputs[i].output == o) win->entered[i] = true;
}
static void s_leave(void *d, struct wl_surface *s, struct wl_output *o) {
    struct window *win = d;
    for (int i = 0; i < noutputs; i++) if (outputs[i].output == o) win->entered[i] = false;
}
static const struct wl_surface_listener s_listener = {s_enter, s_leave};

static void t_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *states) {
    struct window *win = d;
    win->pendingW = w; win->pendingH = h;
    win->pendingFullscreen = WaylandStatesContain(states, WP_TOPLEVEL_STATE_FULLSCREEN);
    if (!win->pendingFullscreen && win->tracker.active) {
        win->unsetConfigureW = w; win->unsetConfigureH = h;
    }
}
static void t_close(void *d, struct xdg_toplevel *t) {}
static const struct xdg_toplevel_listener t_listener = {t_configure, t_close};

static void commit_buffer(struct window *win);

// What WaylandWindow's applyConfigure does: acknowledge, apply the size rule, draw.
static void x_configure(void *d, struct xdg_surface *s, uint32_t serial) {
    struct window *win = d;
    xdg_surface_ack_configure(s, serial);
    int32_t w, h;
    WaylandFullscreenConfigure(&win->tracker, win->pendingFullscreen, win->w, win->h,
                               win->pendingW, win->pendingH, &w, &h);
    if (w > 0 && h > 0) { win->w = w; win->h = h; }
    win->fullscreen = win->pendingFullscreen;
    win->configures++;
    commit_buffer(win);
}
static const struct xdg_surface_listener x_listener = {x_configure};

static void commit_buffer(struct window *win) {
    int fd = memfd_create("fullscreen-test", MFD_CLOEXEC);
    size_t size = (size_t) win->w * win->h * 4;
    if (fd < 0 || ftruncate(fd, size) != 0) exit(2);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    wl_surface_attach(win->surface, wl_shm_pool_create_buffer(pool, 0, win->w, win->h, win->w * 4,
                                                              WL_SHM_FORMAT_XRGB8888), 0, 0);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_surface_damage(win->surface, 0, 0, win->w, win->h);
    wl_surface_commit(win->surface);
}

static void settle(void) {
    for (int i = 0; i < 6; i++) { wl_display_roundtrip(display); usleep(20000); }
}

static struct window *open_window(int w, int h, bool fullscreen, struct wl_output *output) {
    struct window *win = calloc(1, sizeof *win);
    win->w = w; win->h = h;
    win->surface = wl_compositor_create_surface(compositor);
    wl_surface_add_listener(win->surface, &s_listener, win);
    win->xdg = xdg_wm_base_get_xdg_surface(wm, win->surface);
    xdg_surface_add_listener(win->xdg, &x_listener, win);
    win->toplevel = xdg_surface_get_toplevel(win->xdg);
    xdg_toplevel_add_listener(win->toplevel, &t_listener, win);
    xdg_toplevel_set_app_id(win->toplevel, "wl-fs-test"); // the .sh makes these windows float
    if (fullscreen)
        WaylandToplevelSetFullscreen((struct wl_proxy *) win->toplevel, (struct wl_proxy *) output);
    wl_surface_commit(win->surface);
    settle();
    return win;
}

static void close_window(struct window *win) {
    xdg_toplevel_destroy(win->toplevel);
    xdg_surface_destroy(win->xdg);
    wl_surface_destroy(win->surface);
    wl_display_roundtrip(display);
    free(win);
}

// --- sway as the reference: where it really put the window ---------------------

static char out_name[2][64]; // by outputs[] index

static bool sway_query(const char *jqfilter, char *result, size_t size) {
    char cmd[512];
    snprintf(cmd, sizeof cmd, "swaymsg -t %s", jqfilter);
    FILE *pipe = popen(cmd, "r");
    if (!pipe) return false;
    size_t n = fread(result, 1, size - 1, pipe);
    result[n] = 0;
    return pclose(pipe) == 0;
}

// View geometry and fullscreen_mode (0 none, 1 workspace) sway reports for the test window.
static bool sway_window(int *w, int *h, int *mode) {
    char buf[128];
    if (!sway_query("get_tree -r | jq -r '[.. | objects | select(.app_id? == \"wl-fs-test\")] | "
                    "first | \"\\(.geometry.width) \\(.geometry.height) \\(.fullscreen_mode)\"'", buf, sizeof buf))
        return false;
    return sscanf(buf, "%d %d %d", w, h, mode) == 3;
}

static void sway_move_to(int output) {
    char cmd[256];
    snprintf(cmd, sizeof cmd, "swaymsg '[app_id=\"wl-fs-test\"] move container to output %s' >/dev/null",
             out_name[output]);
    if (system(cmd) != 0) { fprintf(stderr, "swaymsg move failed\n"); exit(2); }
    settle();
}

// The decision for a window of this size, from what the window has entered.
// A NULL window has entered nothing.
static bool decide(const struct window *win, int w, int h, bool canBecomeKey, int *target) {
    WaylandFullscreenOutput o[4];
    for (int i = 0; i < noutputs; i++)
        o[i] = (WaylandFullscreenOutput) {outputs[i].w, outputs[i].h, win ? win->entered[i] : false};
    WaylandFullscreenWindow window = {.canBecomeKey = canBecomeKey, .width = w, .height = h};
    return WaylandFullscreenDecide(&window, o, noutputs, target);
}

static void policy(void) {
    // Pure table checks of the decision: outputs 1280x720 and 1920x1080.
    const WaylandFullscreenOutput none[2] = {{1280, 720, false}, {1920, 1080, false}};
    const WaylandFullscreenOutput onBig[2] = {{1280, 720, false}, {1920, 1080, true}};
    const WaylandFullscreenOutput onSmall[2] = {{1280, 720, true}, {1920, 1080, false}};
    const WaylandFullscreenOutput twins[2] = {{1920, 1080, false}, {1920, 1080, false}};
    WaylandFullscreenWindow w = {.canBecomeKey = true, .width = 1920, .height = 1080};
    int target;
    CHECK(WaylandFullscreenDecide(&w, none, 2, &target) && target == 1);
    w.width = 1279;
    CHECK(!WaylandFullscreenDecide(&w, none, 2, &target) && target == -1); // one point short
    w.width = 1920; w.titled = true;
    CHECK(!WaylandFullscreenDecide(&w, none, 2, &target));  // a titled window is never promoted
    w.titled = false; w.canBecomeKey = false;
    CHECK(!WaylandFullscreenDecide(&w, none, 2, &target));  // tooltips and overlays
    w.canBecomeKey = true; w.popupOrMenu = true;
    CHECK(!WaylandFullscreenDecide(&w, none, 2, &target));
    w.popupOrMenu = false; w.width = 800; w.height = 600; w.fullScreenStyle = true;
    CHECK(WaylandFullscreenDecide(&w, none, 2, &target) && target == -1); // the style mask asks outright
    w.fullScreenStyle = false;
    CHECK(!WaylandFullscreenDecide(&w, NULL, 0, &target));

    // Output selection. A window on an output may only go fullscreen on one it is on.
    w = (WaylandFullscreenWindow) {.canBecomeKey = true, .width = 1280, .height = 720};
    CHECK(!WaylandFullscreenDecide(&w, onBig, 2, &target) && target == -1); // size of the other output
    CHECK(WaylandFullscreenDecide(&w, onSmall, 2, &target) && target == 0);
    CHECK(WaylandFullscreenDecide(&w, none, 2, &target) && target == 0);    // nothing entered: unique match
    w.width = 1920; w.height = 1080;
    CHECK(WaylandFullscreenDecide(&w, twins, 2, &target) && target == -1);  // ambiguous: compositor chooses
    const WaylandFullscreenOutput twinsOnSecond[2] = {{1920, 1080, false}, {1920, 1080, true}};
    CHECK(WaylandFullscreenDecide(&w, twinsOnSecond, 2, &target) && target == 1);
    const WaylandFullscreenOutput twinsBoth[2] = {{1920, 1080, true}, {1920, 1080, true}};
    CHECK(WaylandFullscreenDecide(&w, twinsBoth, 2, &target) && target == 0);   // on both: the first

    // Width and height both have to match: same width, other height is another output.
    const WaylandFullscreenOutput tall[2] = {{1920, 1080, false}, {1920, 1200, false}};
    w.width = 1920; w.height = 1200;
    CHECK(WaylandFullscreenDecide(&w, tall, 2, &target) && target == 1);
    w.height = 1000;
    CHECK(!WaylandFullscreenDecide(&w, tall, 2, &target));

    // An empty window is never as large as an output that has not reported a size.
    const WaylandFullscreenOutput blank[1] = {{0, 0, false}};
    w.width = 0; w.height = 0;
    CHECK(!WaylandFullscreenDecide(&w, blank, 1, &target));

    // Leaving after 0x0 restores the saved size; a size from the compositor wins ...
    WaylandFullscreenTracker t = {0};
    int32_t ow, oh;
    WaylandFullscreenConfigure(&t, true, 640, 480, 1920, 1080, &ow, &oh);
    CHECK(ow == 1920 && t.active && t.savedWidth == 640 && t.savedHeight == 480);
    WaylandFullscreenConfigure(&t, true, 1920, 1080, 1920, 1080, &ow, &oh);
    CHECK(t.savedWidth == 640);
    WaylandFullscreenConfigure(&t, false, 1920, 1080, 0, 0, &ow, &oh);
    CHECK(ow == 640 && oh == 480 && !t.active);
    WaylandFullscreenConfigure(&t, true, 640, 480, 1280, 720, &ow, &oh);
    WaylandFullscreenConfigure(&t, false, 1280, 720, 700, 500, &ow, &oh);
    CHECK(ow == 700 && oh == 500);
    // A configure with only one positive dimension is "choose your own size".
    WaylandFullscreenConfigure(&t, true, 640, 480, 1280, 720, &ow, &oh);
    WaylandFullscreenConfigure(&t, false, 1280, 720, 0, 500, &ow, &oh);
    CHECK(ow == 640 && oh == 480);
    // ... unless the application chose a size meanwhile: then that size wins.
    WaylandFullscreenConfigure(&t, true, 640, 480, 1280, 720, &ow, &oh);
    WaylandFullscreenApplicationResized(&t, 800, 600);
    WaylandFullscreenConfigure(&t, false, 800, 600, 640, 480, &ow, &oh);
    CHECK(ow == 800 && oh == 600 && !t.active && !t.applicationSized);
    // A resize outside fullscreen is nothing to remember.
    WaylandFullscreenApplicationResized(&t, 300, 200);
    CHECK(!t.applicationSized);
    // The tracker survives hiding: re-entering fullscreen does not save a second time.
    WaylandFullscreenConfigure(&t, true, 640, 480, 1280, 720, &ow, &oh);
    WaylandFullscreenConfigure(&t, true, 1280, 720, 1280, 720, &ow, &oh);
    WaylandFullscreenConfigure(&t, false, 1280, 720, 0, 0, &ow, &oh);
    CHECK(ow == 640 && oh == 480);
    CHECK(WaylandFullscreenRound(1706.67) == 1707 && WaylandFullscreenRound(1706.4) == 1706);
}

int main(void) {
    policy();
    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no compositor\n"); return 2; }
    wl_registry_add_listener(wl_display_get_registry(display), &r_listener, NULL);
    wl_display_roundtrip(display);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !wm || noutputs != 2) { fprintf(stderr, "need two outputs\n"); return 2; }
    for (int i = 0; i < 2; i++) {
        char filter[128], buf[64];
        snprintf(filter, sizeof filter, "get_outputs -r | jq -r '.[] | select(.current_mode.width == %d) | .name'",
                 outputs[i].w);
        if (!sway_query(filter, buf, sizeof buf)) { fprintf(stderr, "swaymsg failed\n"); return 2; }
        buf[strcspn(buf, "\n")] = 0;
        snprintf(out_name[i], sizeof out_name[i], "%s", buf);
    }

    // Requested before the first commit: the first configure already has the state.
    struct window *a = open_window(640, 480, true, NULL);
    CHECK(a->fullscreen && a->w > 640 && a->h > 480);
    close_window(a);

    // On a chosen output the window gets that output's size, whichever output it is.
    for (int i = 0; i < 2; i++) {
        struct window *b = open_window(640, 480, true, outputs[i].output);
        CHECK(b->fullscreen && b->w == outputs[i].w && b->h == outputs[i].h);
        close_window(b);
    }

    // Leaving restores the size from before.
    struct window *c = open_window(640, 480, false, NULL);
    CHECK(!c->fullscreen && c->w == 640 && c->h == 480);
    WaylandToplevelSetFullscreen((struct wl_proxy *) c->toplevel, (struct wl_proxy *) outputs[1].output);
    wl_surface_commit(c->surface);
    settle();
    CHECK(c->fullscreen && c->w == outputs[1].w && c->tracker.savedWidth == 640);
    WaylandToplevelUnsetFullscreen((struct wl_proxy *) c->toplevel);
    wl_surface_commit(c->surface);
    settle();
    CHECK(!c->fullscreen && c->w == 640 && c->h == 480);
    close_window(c);

    // The application resizes the window while it is fullscreen, then leaves. sway
    // answers unset_fullscreen with the size it remembered (640x480, recorded in
    // unsetConfigure*); the application's 800x600 must win on the client side.
    struct window *d = open_window(640, 480, false, NULL);
    WaylandToplevelSetFullscreen((struct wl_proxy *) d->toplevel, (struct wl_proxy *) outputs[1].output);
    wl_surface_commit(d->surface);
    settle();
    CHECK(d->fullscreen);
    d->w = 800; d->h = 600;
    WaylandFullscreenApplicationResized(&d->tracker, 800, 600);
    commit_buffer(d);
    settle();
    WaylandToplevelUnsetFullscreen((struct wl_proxy *) d->toplevel);
    wl_surface_commit(d->surface);
    settle();
    int sw, sh, mode;
    CHECK(!d->fullscreen && d->w == 800 && d->h == 600);
    CHECK(sway_window(&sw, &sh, &mode) && mode == 0);
    // sway sizes floating windows itself and keeps its own rect whatever buffer the
    // client commits (it showed 640x480 here), so only the client side is checked:
    // the backend keeps the size the application asked for instead of undoing it.
    fprintf(stderr, "note: sway keeps its own rect %dx%d\n", sw, sh);
    fprintf(stderr, "note: sway answered unset_fullscreen with %dx%d\n", d->unsetConfigureW, d->unsetConfigureH);
    close_window(d);

    // A borderless window promoted because it is as large as an output, then resized
    // smaller by the application: it leaves fullscreen at the new size, not at the
    // output's size.
    struct window *e;
    {
        int target;
        bool wanted = decide(NULL, 1920, 1080, true, &target); // nothing entered yet
        CHECK(wanted && target == 1);
        e = open_window(1920, 1080, true, outputs[target].output);
    }
    CHECK(e->fullscreen && e->w == 1920 && e->h == 1080);
    e->w = 1280; e->h = 720;
    WaylandFullscreenApplicationResized(&e->tracker, 1280, 720);
    {
        int target;
        CHECK(!decide(e, 1280, 720, true, &target)); // entered only the 1920x1080 output
    }
    WaylandToplevelUnsetFullscreen((struct wl_proxy *) e->toplevel);
    commit_buffer(e);
    settle();
    CHECK(!e->fullscreen && e->w == 1280 && e->h == 720);
    CHECK(sway_window(&sw, &sh, &mode) && mode == 0);
    close_window(e);

    // Output selection on the wire. A borderless 1280x720 window on the 1920x1080
    // output matches the other output's size and must stay an ordinary window.
    struct window *f = open_window(1280, 720, false, NULL);
    sway_move_to(1);
    CHECK(f->entered[1] && !f->entered[0]);
    {
        int target;
        CHECK(!decide(f, 1280, 720, true, &target));
    }
    CHECK(sway_window(&sw, &sh, &mode) && mode == 0 && sw == 1280 && sh == 720 && !f->fullscreen);
    // On the 1280x720 output the same window is fullscreen material, on that output.
    sway_move_to(0);
    CHECK(f->entered[0] && !f->entered[1]);
    {
        int target;
        CHECK(decide(f, 1280, 720, true, &target) && target == 0);
        WaylandToplevelSetFullscreen((struct wl_proxy *) f->toplevel,
                                     (struct wl_proxy *) outputs[target].output);
        wl_surface_commit(f->surface);
        settle();
    }
    CHECK(f->fullscreen && f->w == 1280 && f->h == 720);
    CHECK(sway_window(&sw, &sh, &mode) && mode == 1 && sw == 1280 && sh == 720);
    close_window(f);

    printf("RESULT checks=%u failures=%u\n", checks, failures);
    return failures ? 1 : 0;
}
