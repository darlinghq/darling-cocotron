#include "../AppKit/X11.backend/X11RelativeMouse.h"
#include <assert.h>
#include <stdio.h>

/* Host model of the X11 backend's relative mouse mode (CGAssociateMouseAndMouseCursorPosition(false)).
 * A warp's echo is simulated as the MotionNotify the server queues at the target; `queued` is the number of
 * X events queued after the backend's XSync. */
static X11RelativeMouseMotion motion(X11RelativeMouse *m, int x, int y, bool honoured) {
    return X11RelativeMouseHandleMotion(m, x, y, honoured);
}

static void xorgHonouredWarps(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400);
    /* Physical motion: delta reported, the cursor stays frozen, the pointer is warped back. */
    X11RelativeMouseMotion r = motion(&m, 510, 395, true);
    assert(r.post && !r.echo && r.deltaX == 10 && r.deltaY == -5);
    assert(r.rewarp && r.warpX == 500 && r.warpY == 400);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1);
    /* The rewarp's echo is consumed and is not a delta back to the centre. */
    r = motion(&m, 500, 400, true);
    assert(!r.post && r.echo && !r.rewarp && m.echoCount == 0);
    assert(m.physicalX == 500 && m.physicalY == 400);
    r = motion(&m, 503, 404, true);
    assert(r.post && r.deltaX == 3 && r.deltaY == 4 && r.rewarp);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1);

    /* A real motion queued before the echo still measures against the last physical position. */
    X11RelativeMouseBegin(&m, 500, 400);
    r = motion(&m, 520, 400, true);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 2); /* the next motion was already queued */
    r = motion(&m, 530, 400, true);
    assert(r.post && r.deltaX == 10 && r.deltaY == 0 && r.rewarp);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1); /* same target: merged, not a second echo */
    assert(m.echoCount == 1);
    r = motion(&m, 500, 400, true);
    assert(r.echo && m.echoCount == 0);
    r = motion(&m, 499, 400, true);
    assert(r.post && r.deltaX == -1);

    /* The application warps from the event it was given while our rewarp's echo is still queued:
     * both echoes are dropped in order and neither cancels the motion. */
    X11RelativeMouseBegin(&m, 500, 400);
    r = motion(&m, 512, 400, true);
    assert(r.deltaX == 12 && r.rewarp);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1);
    X11RelativeMouseWarp(&m, 524.0, 400.0, 2); /* game: mouseLocation + 2 * delta */
    assert(m.virtualX == 524.0 && m.physicalX == 512);
    r = motion(&m, 500, 400, true);
    assert(r.echo && m.physicalX == 500);
    r = motion(&m, 524, 400, true);
    assert(r.echo && m.physicalX == 524 && m.echoCount == 0);
    r = motion(&m, 530, 401, true);
    assert(r.post && r.deltaX == 6 && r.deltaY == 1 && r.rewarp && r.warpX == 524 && r.warpY == 400);
    puts("PASS: Xorg honoured warps rewarp to the frozen cursor and drop their echoes");
}

static void xwaylandVisibleCursor(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 800, 450);
    /* Warps are not honoured: no rewarp, the pointer moves freely, deltas follow it. */
    X11RelativeMouseMotion r = motion(&m, 810, 450, false);
    assert(r.post && r.deltaX == 10 && !r.rewarp);
    X11RelativeMouseWarp(&m, 820.0, 450.0, 1);
    /* The echo at the target is dropped without moving the physical position... */
    r = motion(&m, 820, 450, false);
    assert(r.echo && !r.post && m.physicalX == 810 && m.physicalY == 450);
    /* ...so the next real motion, at the real absolute position, gives the true delta. */
    r = motion(&m, 812, 453, false);
    assert(r.post && r.deltaX == 2 && r.deltaY == 3 && !r.rewarp);
    assert(m.virtualX == 820.0 && m.virtualY == 450.0);
    /* An expected echo that never arrives expires after the queued events and cannot eat a later motion. */
    X11RelativeMouseWarp(&m, 700.0, 400.0, 1);
    X11RelativeMouseTick(&m); /* some other X event was the one queued */
    assert(m.echoCount == 0);
    r = motion(&m, 700, 400, false);
    assert(r.post && !r.echo && r.deltaX == -112 && r.deltaY == -53);
    puts("PASS: Xwayland visible cursor keeps the physical position across unhonoured warp echoes");
}

static void gameWarpUpdatesVirtual(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 100, 100);
    X11RelativeMouseWarp(&m, 150.75, 120.5, 0); /* no event: the pointer was already there */
    assert(m.virtualX == 150.75 && m.virtualY == 120.5 && m.echoCount == 0);
    assert(m.physicalX == 100 && m.physicalY == 100);
    /* mouseLocation reports the virtual cursor, Cocoa bottom-up global, for a 1080-pixel screen. */
    double cocoaX = m.virtualX, cocoaY = 1080 - m.virtualY;
    assert(cocoaX == 150.75 && cocoaY == 959.5);
    X11RelativeMouseMotion r = motion(&m, 101, 100, true);
    assert(r.post && r.deltaX == 1 && r.rewarp && r.warpX == 150 && r.warpY == 120);
    puts("PASS: application warps while relative move the virtual cursor that mouseLocation returns");
}

static void deltaSign(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 0, 0);
    X11RelativeMouseMotion r = motion(&m, 0, 7, false);
    assert(r.deltaY == 7); /* X root y grows downwards: positive deltaY means down, as on macOS */
    double dx, dy;
    /* Absolute motion in Cocoa window coordinates (bottom-up): moving down lowers y. */
    X11AbsoluteMouseDelta(10, 300, 14, 290, &dx, &dy);
    assert(dx == 4 && dy == 10);
    puts("PASS: deltaY is positive downwards for relative and absolute motion");
}

static void ungrabRestores(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 10, 10);
    X11RelativeMouseWarp(&m, 40, 40, 3);
    X11RelativeMouseEnd(&m);
    assert(!m.active && m.echoCount == 0);
    X11RelativeMouseBegin(&m, 60, 70);
    assert(m.active && m.virtualX == 60 && m.virtualY == 70 && m.physicalX == 60 && m.physicalY == 70);
    X11RelativeMouseMotion r = motion(&m, 40, 40, true);
    assert(r.post && !r.echo && r.deltaX == -20 && r.deltaY == -30);
    puts("PASS: ungrab clears expected echoes and a new grab starts from the current pointer");
}

static void echoQueueBound(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 0, 0);
    for (int i = 1; i <= X11_RELATIVE_MOUSE_MAX_ECHOES + 3; ++i)
        X11RelativeMouseWarp(&m, i, 0, 100);
    assert(m.echoCount == X11_RELATIVE_MOUSE_MAX_ECHOES && m.echoes[0].x == 4);
    X11RelativeMouseMotion r = motion(&m, 6, 0, true);
    assert(r.echo && m.echoCount == X11_RELATIVE_MOUSE_MAX_ECHOES - 3 && m.echoes[0].x == 7);
    puts("PASS: expected echoes are bounded and consumed in order");
}

int main(void) {
    xorgHonouredWarps();
    xwaylandVisibleCursor();
    gameWarpUpdatesVirtual();
    deltaSign();
    ungrabRestores();
    echoQueueBound();
    return 0;
}
