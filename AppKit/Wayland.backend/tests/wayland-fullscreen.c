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
    struct wl_surface *surface;
    struct xdg_surface *xdg;
    struct xdg_toplevel *toplevel;
    int32_t pendingW, pendingH, w, h; // configured; what the backend would resize to
    bool pendingFullscreen, fullscreen;
    int configures;
    WaylandFullscreenTracker tracker;
};

static void t_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *states) {
    struct window *win = d;
    win->pendingW = w; win->pendingH = h;
    win->pendingFullscreen = WaylandStatesContain(states, WP_TOPLEVEL_STATE_FULLSCREEN);
}
static void t_close(void *d, struct xdg_toplevel *t) {}
static const struct xdg_toplevel_listener t_listener = {t_configure, t_close};

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
static const struct xdg_surface_listener x_listener = {x_configure};

static void settle(void) {
    for (int i = 0; i < 6; i++) { wl_display_roundtrip(display); usleep(20000); }
}

static struct window *open_window(int w, int h, bool fullscreen, struct wl_output *output) {
    struct window *win = calloc(1, sizeof *win);
    win->w = w; win->h = h;
    win->surface = wl_compositor_create_surface(compositor);
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

static void policy(void) {
    const int32_t sizes[2][2] = {{1280, 720}, {1920, 1080}};
    WaylandFullscreenWindow w = {.canBecomeKey = true, .width = 1920, .height = 1080};
    CHECK(WaylandFullscreenWanted(&w, sizes, 2) && WaylandFullscreenOutputIndex(&w, sizes, 2) == 1);
    w.width = 1279;
    CHECK(!WaylandFullscreenWanted(&w, sizes, 2));  // one point short
    w.width = 1920; w.titled = true;
    CHECK(!WaylandFullscreenWanted(&w, sizes, 2));  // a titled window is never promoted
    w.titled = false; w.canBecomeKey = false;
    CHECK(!WaylandFullscreenWanted(&w, sizes, 2));  // tooltips and overlays
    w.canBecomeKey = true; w.popupOrMenu = true;
    CHECK(!WaylandFullscreenWanted(&w, sizes, 2));
    w.popupOrMenu = false; w.width = 800; w.height = 600; w.fullScreenStyle = true;
    CHECK(WaylandFullscreenWanted(&w, sizes, 2));   // the style mask asks outright
    w.fullScreenStyle = false;
    CHECK(!WaylandFullscreenWanted(&w, NULL, 0));

    // Leaving after 0x0 restores the saved size; a size from the compositor wins.
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
}

int main(void) {
    policy();
    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no compositor\n"); return 2; }
    wl_registry_add_listener(wl_display_get_registry(display), &r_listener, NULL);
    wl_display_roundtrip(display);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !wm || noutputs != 2) { fprintf(stderr, "need two outputs\n"); return 2; }

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

    printf("RESULT checks=%u failures=%u\n", checks, failures);
    return failures ? 1 : 0;
}
