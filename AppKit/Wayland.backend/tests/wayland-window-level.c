// Drives WaylandWindowLevel.h against a real compositor: a toplevel made transient
// for another with xdg_toplevel.set_parent, the relation removed again, and a parent
// that unmaps while it has a transient child. The compositor must raise no protocol
// error and the child must stay mapped. Also checks the level policy
// (DarlingWindowLevelPolicy.h). Run it through wayland-window-level.sh (private
// headless sway).
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"
#include "../WaylandWindowLevel.h"

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

static void global(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
    if (!strcmp(i, "wl_compositor")) compositor = wl_registry_bind(r, n, &wl_compositor_interface, 4);
    else if (!strcmp(i, "wl_shm")) shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
    else if (!strcmp(i, "xdg_wm_base")) wm = wl_registry_bind(r, n, &xdg_wm_base_interface, 1);
}
static void global_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener r_listener = {global, global_remove};

struct window {
    struct wl_surface *surface;
    struct xdg_surface *xdg;
    struct xdg_toplevel *toplevel;
    bool closed;
};

static void commit_buffer(struct window *win) {
    int fd = memfd_create("window-level-test", MFD_CLOEXEC);
    size_t size = 200 * 100 * 4;
    if (fd < 0 || ftruncate(fd, size) != 0) exit(2);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    wl_surface_attach(win->surface, wl_shm_pool_create_buffer(pool, 0, 200, 100, 200 * 4,
                                                              WL_SHM_FORMAT_XRGB8888), 0, 0);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_surface_damage(win->surface, 0, 0, 200, 100);
    wl_surface_commit(win->surface);
}

static void x_configure(void *d, struct xdg_surface *s, uint32_t serial) {
    xdg_surface_ack_configure(s, serial);
    commit_buffer(d);
}
static const struct xdg_surface_listener x_listener = {x_configure};
static void t_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *s) {}
static void t_close(void *d, struct xdg_toplevel *t) { ((struct window *) d)->closed = true; }
static const struct xdg_toplevel_listener t_listener = {t_configure, t_close};

static void settle(void) {
    for (int i = 0; i < 6; i++) { wl_display_roundtrip(display); usleep(20000); }
}

static struct window *open_window(const char *title) {
    struct window *win = calloc(1, sizeof *win);
    win->surface = wl_compositor_create_surface(compositor);
    win->xdg = xdg_wm_base_get_xdg_surface(wm, win->surface);
    xdg_surface_add_listener(win->xdg, &x_listener, win);
    win->toplevel = xdg_surface_get_toplevel(win->xdg);
    xdg_toplevel_add_listener(win->toplevel, &t_listener, win);
    xdg_toplevel_set_title(win->toplevel, title);
    xdg_toplevel_set_app_id(win->toplevel, "wl-level-test");
    wl_surface_commit(win->surface);
    settle();
    return win;
}

static void close_window(struct window *win) {
    xdg_toplevel_destroy(win->toplevel);
    xdg_surface_destroy(win->xdg);
    wl_surface_destroy(win->surface);
    settle();
    free(win);
}

int main(void) {
    // The level policy.
    CHECK(DarlingWindowRoleForLevel(-2147483623) == DarlingWindowRoleOrdinary); // desktop
    CHECK(DarlingWindowRoleForLevel(0) == DarlingWindowRoleOrdinary);           // normal
    CHECK(DarlingWindowRoleForLevel(3) == DarlingWindowRoleTransient);          // floating, torn-off menu
    CHECK(DarlingWindowRoleForLevel(8) == DarlingWindowRoleTransient);          // modal panel
    CHECK(DarlingWindowRoleForLevel(19) == DarlingWindowRoleTransient);         // utility
    CHECK(DarlingWindowRoleForLevel(23) == DarlingWindowRoleTransient);
    CHECK(DarlingWindowRoleForLevel(24) == DarlingWindowRoleNeedsLayering);     // main menu
    CHECK(DarlingWindowRoleForLevel(25) == DarlingWindowRoleNeedsLayering);     // status
    CHECK(DarlingWindowRoleForLevel(101) == DarlingWindowRoleNeedsLayering);    // pop-up menu
    CHECK(DarlingWindowRoleForLevel(1000) == DarlingWindowRoleNeedsLayering);   // screen saver
    int a, b, c;
    const void *chain[] = {&b, &c};
    CHECK(!DarlingWindowParentAllowed(&a, NULL, NULL, 0));
    CHECK(!DarlingWindowParentAllowed(&a, &a, NULL, 0));
    CHECK(DarlingWindowParentAllowed(&a, &b, NULL, 0));
    CHECK(DarlingWindowParentAllowed(&a, &b, chain, 2));
    const void *cycle[] = {&c, &a};
    CHECK(!DarlingWindowParentAllowed(&a, &b, cycle, 2)); // b's ancestors include a

    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no wayland display\n"); return 2; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &r_listener, NULL);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !wm) { fprintf(stderr, "missing globals\n"); return 2; }

    struct window *parent = open_window("parent");
    struct window *child = open_window("child");

    // Transient for the parent, then no longer.
    WaylandToplevelSetParent((struct wl_proxy *) child->toplevel, (struct wl_proxy *) parent->toplevel);
    CHECK(wl_display_roundtrip(display) >= 0);
    settle();
    CHECK(wl_display_get_error(display) == 0);
    WaylandToplevelSetParent((struct wl_proxy *) child->toplevel, NULL);
    CHECK(wl_display_roundtrip(display) >= 0);
    CHECK(wl_display_get_error(display) == 0);

    // A chain: grandchild for child for parent.
    struct window *grand = open_window("grandchild");
    WaylandToplevelSetParent((struct wl_proxy *) child->toplevel, (struct wl_proxy *) parent->toplevel);
    WaylandToplevelSetParent((struct wl_proxy *) grand->toplevel, (struct wl_proxy *) child->toplevel);
    CHECK(wl_display_roundtrip(display) >= 0);
    CHECK(wl_display_get_error(display) == 0);

    // The middle window goes away: the compositor reparents the grandchild.
    close_window(child);
    CHECK(wl_display_get_error(display) == 0);
    CHECK(!grand->closed);
    WaylandToplevelSetParent((struct wl_proxy *) grand->toplevel, NULL);
    CHECK(wl_display_roundtrip(display) >= 0);
    CHECK(wl_display_get_error(display) == 0);

    close_window(grand);
    close_window(parent);
    printf("%u checks, %u failures\n", checks, failures);
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
