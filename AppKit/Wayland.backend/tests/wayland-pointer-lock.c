// Drives WaylandPointerLock.h against a real compositor: lock, relative motion,
// and the cursor position hint on unlock. Run it through wayland-pointer-lock.sh
// (private headless sway); a virtual pointer plays the mouse.
#define _GNU_SOURCE
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"
#include "../WaylandPointerLock.h"

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
static struct wl_seat *seat;
static struct xdg_wm_base *wm;
static struct wl_proxy *constraints, *relativeManager;
static struct zwlr_virtual_pointer_manager_v1 *vpm;

static struct wl_pointer *pointer;
static int enters, motions, lockedEvents, unlockedEvents, relativeEvents;
static double enterX, enterY, motionX, motionY, sumDx, sumDy;

static void p_enter(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *f, wl_fixed_t x, wl_fixed_t y) {
    enters++; enterX = wl_fixed_to_double(x); enterY = wl_fixed_to_double(y);
}
static void p_leave(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *f) {}
static void p_motion(void *d, struct wl_pointer *p, uint32_t t, wl_fixed_t x, wl_fixed_t y) {
    motions++; motionX = wl_fixed_to_double(x); motionY = wl_fixed_to_double(y);
}
static void p_button(void *d, struct wl_pointer *p, uint32_t s, uint32_t t, uint32_t b, uint32_t st) {}
static void p_axis(void *d, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v) {}
static const struct wl_pointer_listener p_listener = {p_enter, p_leave, p_motion, p_button, p_axis};

// The events of the lock objects arrive through the same decoding the backend uses.
static int dispatch(const void *data, void *proxy, uint32_t opcode, const struct wl_message *m,
                    union wl_argument *args)
{
    double dx, dy;
    if (data == &lockedEvents) {
        if (opcode == WP_LOCKED_POINTER_EV_LOCKED) lockedEvents++;
        else if (opcode == WP_LOCKED_POINTER_EV_UNLOCKED) unlockedEvents++;
    } else if (WaylandRelativeMotionDelta(opcode, args, &dx, &dy)) {
        relativeEvents++; sumDx += dx; sumDy += dy;
    }
    return 0;
}

static int hasPointer;
static void s_capabilities(void *d, struct wl_seat *s, uint32_t caps) { hasPointer = caps & WL_SEAT_CAPABILITY_POINTER; }
static void s_name(void *d, struct wl_seat *s, const char *n) {}
static const struct wl_seat_listener s_listener = {s_capabilities, s_name};

static void global(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
    if (!strcmp(i, "wl_compositor")) compositor = wl_registry_bind(r, n, &wl_compositor_interface, 4);
    else if (!strcmp(i, "wl_shm")) shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
    else if (!strcmp(i, "wl_seat")) seat = wl_registry_bind(r, n, &wl_seat_interface, 4);
    else if (!strcmp(i, "xdg_wm_base")) wm = wl_registry_bind(r, n, &xdg_wm_base_interface, 1);
    else if (!strcmp(i, "zwp_pointer_constraints_v1")) constraints = wl_registry_bind(r, n, &zwp_pointer_constraints_v1_interface, 1);
    else if (!strcmp(i, "zwp_relative_pointer_manager_v1")) relativeManager = wl_registry_bind(r, n, &zwp_relative_pointer_manager_v1_interface, 1);
    else if (!strcmp(i, "zwlr_virtual_pointer_manager_v1")) vpm = wl_registry_bind(r, n, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void global_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener r_listener = {global, global_remove};

static int configured;
static void x_configure(void *d, struct xdg_surface *s, uint32_t serial) { xdg_surface_ack_configure(s, serial); configured++; }
static const struct xdg_surface_listener x_listener = {x_configure};
static void t_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *s) {}
static void t_close(void *d, struct xdg_toplevel *t) {}
static const struct xdg_toplevel_listener t_listener = {t_configure, t_close};

static void settle(void) { for (int i = 0; i < 5; i++) { wl_display_roundtrip(display); usleep(20000); } }

static void sway(const char *command) {
    char line[256];
    snprintf(line, sizeof line, "swaymsg '%s' >/dev/null", command);
    if (system(line) != 0) { fprintf(stderr, "failed: %s\n", line); exit(2); }
}

static void motion(struct zwlr_virtual_pointer_v1 *vp, double dx, double dy) {
    static uint32_t time = 1000;
    zwlr_virtual_pointer_v1_motion(vp, time += 10, wl_fixed_from_double(dx), wl_fixed_from_double(dy));
    zwlr_virtual_pointer_v1_frame(vp);
    wl_display_flush(display);
    settle();
}

// What WaylandWindow -transformPoint: does with a wl_pointer.motion point.
static void transformPoint(double sx, double sy, double frameH, double offX, double offY,
                           double *wx, double *wy) {
    *wx = sx - offX;
    *wy = frameH - sy + offY;
}

static void units(void) {
    // A warp stores a window point, like every other writer of the cursor position
    // (enter and motion store transformPoint of the surface point), and the surface
    // point it reports must map back to that same window point, with and without
    // the client-side decoration offset (6,34).
    static const double offsets[2][2] = {{0, 0}, {6, 34}};
    for (int i = 0; i < 2; i++) {
        double ox = offsets[i][0], oy = offsets[i][1];
        WaylandWarp w = WaylandWarpTarget(1100 + 120, 500 + 80, 1100, 500, 400, 300, ox, oy);
        CHECK(w.windowX == 120 && w.windowY == 80);
        CHECK(w.surfaceX == 120 + ox && w.surfaceY == 300 - 80 + oy);
        double wx, wy;
        transformPoint(w.surfaceX, w.surfaceY, 300, ox, oy, &wx, &wy);
        CHECK(wx == w.windowX && wy == w.windowY);
        // Clamped to the content on every side.
        w = WaylandWarpTarget(-50, 9999, 1100, 500, 400, 300, ox, oy);
        CHECK(w.windowX == 0 && w.windowY == 300);
        w = WaylandWarpTarget(9999, -50, 1100, 500, 400, 300, ox, oy);
        CHECK(w.windowX == 400 && w.windowY == 0);
    }

    // relative_motion(utime_hi, utime_lo, dx, dy, dx_unaccel, dy_unaccel): the
    // deltas of an unlocked pointer have the acceleration applied, so these do too.
    union wl_argument args[6] = {{.u = 0}, {.u = 1}, {.f = wl_fixed_from_double(7)},
                                 {.f = wl_fixed_from_double(-3)}, {.f = wl_fixed_from_double(70)},
                                 {.f = wl_fixed_from_double(-30)}};
    double dx = 0, dy = 0;
    CHECK(WaylandRelativeMotionDelta(WP_RELATIVE_POINTER_EV_RELATIVE_MOTION, args, &dx, &dy));
    CHECK(dx == 7 && dy == -3);
    CHECK(!WaylandRelativeMotionDelta(WP_RELATIVE_POINTER_EV_RELATIVE_MOTION + 1, args, &dx, &dy));
}

int main(void) {
    units();
    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no compositor\n"); return 2; }
    wl_registry_add_listener(wl_display_get_registry(display), &r_listener, NULL);
    wl_display_roundtrip(display);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !seat || !wm || !constraints || !relativeManager || !vpm) {
        fprintf(stderr, "compositor lacks a required global\n"); return 2;
    }
    // A headless compositor has no pointer until the virtual one exists.
    struct zwlr_virtual_pointer_v1 *vp = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(vpm, seat);
    wl_seat_add_listener(seat, &s_listener, NULL);
    settle();
    if (!hasPointer) { fprintf(stderr, "no pointer capability\n"); return 2; }
    pointer = wl_seat_get_pointer(seat);
    wl_pointer_add_listener(pointer, &p_listener, NULL);

    struct wl_surface *surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xdg = xdg_wm_base_get_xdg_surface(wm, surface);
    xdg_surface_add_listener(xdg, &x_listener, NULL);
    struct xdg_toplevel *top = xdg_surface_get_toplevel(xdg);
    xdg_toplevel_add_listener(top, &t_listener, NULL);
    xdg_toplevel_set_app_id(top, "wl-lock-test"); // the .sh makes it float
    wl_surface_commit(surface);
    settle();
    int fd = memfd_create("lock-test", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, 400 * 300 * 4) != 0) return 2;
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, 400 * 300 * 4);
    wl_surface_attach(surface, wl_shm_pool_create_buffer(pool, 0, 400, 300, 1600, WL_SHM_FORMAT_XRGB8888), 0, 0);
    wl_surface_damage(surface, 0, 0, 400, 300);
    wl_surface_commit(surface);
    settle();
    CHECK(configured > 0);

    sway("[app_id=\"wl-lock-test\"] move position 100 100");
    sway("seat seat0 cursor set 250 200");
    for (int i = 0; i < 50 && enters == 0; i++) { wl_display_roundtrip(display); usleep(20000); }
    CHECK(enters == 1 && fabs(enterX - 150) < 1 && fabs(enterY - 100) < 1);
    double startX = enterX, startY = enterY;
    printf("pointer entered at %.1f,%.1f\n", startX, startY);

    // Before the lock the pointer is an ordinary one: motion arrives, no deltas.
    int motionsBefore = motions;
    motion(vp, 3, 4);
    CHECK(motions > motionsBefore);

    struct wl_proxy *locked = WaylandLockPointer((struct wl_proxy *) constraints, (struct wl_proxy *) surface,
                                                 (struct wl_proxy *) pointer);
    struct wl_proxy *relative = WaylandGetRelativePointer((struct wl_proxy *) relativeManager,
                                                          (struct wl_proxy *) pointer);
    CHECK(locked && relative);
    wl_proxy_add_dispatcher(locked, dispatch, &lockedEvents, NULL);
    wl_proxy_add_dispatcher(relative, dispatch, &relativeEvents, NULL);
    settle();
    CHECK(lockedEvents == 1 && unlockedEvents == 0);

    // Locked: deltas arrive, absolute motion does not.
    motionsBefore = motions;
    sumDx = sumDy = 0; relativeEvents = 0;
    for (int i = 0; i < 3; i++) motion(vp, 10, -5);
    CHECK(relativeEvents == 3);
    CHECK(fabs(sumDx - 30) < 0.01 && fabs(sumDy + 15) < 0.01);
    CHECK(motions == motionsBefore);

    // The lock is persistent: when the window leaves the screen (workspace switch) the compositor
    // deactivates it, and when the pointer comes back it is active again without a
    // new request. A oneshot lock would be spent by the first leave.
    sway("workspace number 2");
    settle();
    CHECK(unlockedEvents == 1 && lockedEvents == 1);
    sway("workspace number 1");
    settle();
    CHECK(lockedEvents == 2);
    motionsBefore = motions;
    sumDx = sumDy = 0; relativeEvents = 0;
    motion(vp, 4, 2);
    CHECK(relativeEvents == 1 && fabs(sumDx - 4) < 0.01 && fabs(sumDy - 2) < 0.01);
    CHECK(motions == motionsBefore);

    // Unlock with a hint: the pointer reappears there, not where the deltas took it.
    WaylandUnlockPointer(locked, relative, (struct wl_proxy *) surface, startX + 40, startY + 30);
    settle();
    motion(vp, 1, 0);
    printf("after unlock motion at %.1f,%.1f (hint %.1f,%.1f)\n", motionX, motionY, startX + 40, startY + 30);
    CHECK(fabs(motionX - (startX + 40 + 1)) < 1.5 && fabs(motionY - (startY + 30)) < 1.5);
    int deltas = relativeEvents;
    motion(vp, 5, 5);
    CHECK(relativeEvents == deltas); // the relative pointer object is gone too

    printf("RESULT checks=%u failures=%u\n", checks, failures);
    return failures ? 1 : 0;
}
