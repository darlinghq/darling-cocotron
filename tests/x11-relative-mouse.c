#ifndef X11_RELATIVE_MOUSE_HEADER
#define X11_RELATIVE_MOUSE_HEADER "../AppKit/X11.backend/X11RelativeMouse.h"
#endif
#include X11_RELATIVE_MOUSE_HEADER
#undef NDEBUG /* the checks are asserts */
#include <assert.h>
#include <limits.h>
#include <stdio.h>

/* Host model of the X11 backend's relative mouse mode (CGAssociateMouseAndMouseCursorPosition(false)).
 * A warp's echo is simulated as the MotionNotify the server queues at the target; `queued` is the number of
 * X events queued after the backend's XSync. */
/* Room for every coordinate these scenarios use; scenarios about reachability pass their own bounds. */
static const X11RelativeMouseBounds anywhere = {-100000, -100000, 100000, 100000};

static X11RelativeMouseMotion motion(X11RelativeMouse *m, int x, int y, bool honoured) {
    return X11RelativeMouseHandleMotion(m, x, y, honoured, 0);
}

static void xorgHonouredWarps(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    /* Physical motion: delta reported, the cursor stays frozen, the pointer is warped back. */
    X11RelativeMouseMotion r = motion(&m, 510, 395, true);
    assert(r.post && !r.echo && r.deltaX == 10 && r.deltaY == -5);
    assert(r.rewarp && r.warpX == 500 && r.warpY == 400);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1, 0);
    /* The rewarp's echo is consumed and is not a delta back to the centre. */
    r = motion(&m, 500, 400, true);
    assert(!r.post && r.echo && !r.rewarp && m.echoCount == 0);
    assert(m.physicalX == 500 && m.physicalY == 400);
    r = motion(&m, 503, 404, true);
    assert(r.post && r.deltaX == 3 && r.deltaY == 4 && r.rewarp);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1, 0);

    /* A real motion queued before the echo still measures against the last physical position. */
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    r = motion(&m, 520, 400, true);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 2, 0); /* the next motion was already queued */
    r = motion(&m, 530, 400, true);
    assert(r.post && r.deltaX == 10 && r.deltaY == 0 && r.rewarp);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1, 0); /* same target: merged, not a second echo */
    assert(m.echoCount == 1);
    r = motion(&m, 500, 400, true);
    assert(r.echo && m.echoCount == 0);
    r = motion(&m, 499, 400, true);
    assert(r.post && r.deltaX == -1);

    /* The application warps from the event it was given while our rewarp's echo is still queued:
     * both echoes are dropped in order and neither cancels the motion. */
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    r = motion(&m, 512, 400, true);
    assert(r.deltaX == 12 && r.rewarp);
    X11RelativeMouseExpectEcho(&m, r.warpX, r.warpY, 1, 0);
    X11RelativeMouseWarp(&m, 524.0, 400.0, 2, 0, true); /* game: mouseLocation + 2 * delta */
    assert(m.virtualX == 524.0 && m.physicalX == 512);
    r = motion(&m, 500, 400, true);
    assert(r.echo && m.physicalX == 500);
    r = motion(&m, 524, 400, true);
    assert(r.echo && m.physicalX == 524 && m.echoCount == 0);
    r = motion(&m, 530, 401, true);
    assert(r.post && r.deltaX == 6 && r.deltaY == 1 && r.rewarp && r.warpX == 524 && r.warpY == 400);
    X11RelativeMouseEnd(&m);
    puts("PASS: Xorg honoured warps rewarp to the frozen cursor and drop their echoes");
}

static void xwaylandVisibleCursor(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 800, 450, 0, anywhere);
    /* Warps are not honoured: no rewarp, the pointer moves freely, deltas follow it. */
    X11RelativeMouseMotion r = motion(&m, 810, 450, false);
    assert(r.post && r.deltaX == 10 && !r.rewarp);
    X11RelativeMouseWarp(&m, 820.0, 450.0, 1, 0, false);
    /* The echo at the target is dropped without moving the physical position... */
    r = motion(&m, 820, 450, false);
    assert(r.echo && !r.post && m.physicalX == 810 && m.physicalY == 450);
    /* ...so the next real motion, at the real absolute position, gives the true delta. */
    r = motion(&m, 812, 453, false);
    assert(r.post && r.deltaX == 2 && r.deltaY == 3 && !r.rewarp);
    assert(m.virtualX == 812.0 && m.virtualY == 453.0);
    /* An expected echo that never arrives expires after the queued events and cannot eat a later motion. */
    X11RelativeMouseWarp(&m, 700.0, 400.0, 1, 0, false);
    X11RelativeMouseTick(&m); /* some other X event was the one queued */
    assert(m.echoCount == 0);
    r = motion(&m, 700, 400, false);
    assert(r.post && !r.echo && r.deltaX == -112 && r.deltaY == -53);
    X11RelativeMouseEnd(&m);
    puts("PASS: Xwayland visible cursor keeps the physical position across unhonoured warp echoes");
}

static void visibleCursorWarpsFollowPointer(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 2888, 30, 0, anywhere);
    int x = 2888, y = 30;
    for (int step = 0; step < 40; ++step) {
        x -= 20;
        y += 16;
        X11RelativeMouseMotion r = motion(&m, x, y, false);
        assert(r.post && r.deltaX == -20 && r.deltaY == 16 && !r.rewarp);
        double gameX = m.virtualX + r.deltaX / 2, gameY = m.virtualY + r.deltaY / 2;
        X11RelativeMouseWarp(&m, gameX, gameY, 1, 0, false);
        r = motion(&m, (int) gameX, (int) gameY, false); /* the unhonoured warp's echo */
        assert(r.echo && !r.post);
        assert(m.virtualX == x && m.virtualY == y);
    }
    /* The pointer stops at the right edge of a 3440-pixel screen; the cursor is there too. */
    X11RelativeMouseMotion r = motion(&m, 3439, 700, false);
    assert(r.post && m.virtualX == 3439 && m.virtualY == 700);
    X11RelativeMouseEnd(&m);
    puts("PASS: a game's visible-cursor warps leave the virtual cursor on the pointer, up to the screen edge");
}

static void gameWarpUpdatesVirtual(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 100, 100, 0, anywhere);
    X11RelativeMouseWarp(&m, 150.75, 120.5, 0, 0, true); /* no event: the pointer was already there */
    assert(m.virtualX == 150.75 && m.virtualY == 120.5 && m.echoCount == 0);
    assert(m.physicalX == 100 && m.physicalY == 100);
    X11RelativeMouseMotion r = motion(&m, 101, 100, true);
    assert(r.post && r.deltaX == 1 && r.rewarp && r.warpX == 150 && r.warpY == 120);
    X11RelativeMouseEnd(&m);
    puts("PASS: application warps while relative move the virtual cursor that mouseLocation returns");
}

static void deltaSign(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 0, 0, 0, anywhere);
    X11RelativeMouseMotion r = motion(&m, 0, 7, false);
    assert(r.deltaY == 7); /* X root y grows downwards: positive deltaY means down, as on macOS */
    X11RelativeMouseEnd(&m);
    puts("PASS: relative deltaY is positive downwards");
}

static void ungrabRestores(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 10, 10, 0, anywhere);
    X11RelativeMouseWarp(&m, 40, 40, 3, 0, true);
    X11RelativeMouseEnd(&m);
    assert(!m.active && m.echoCount == 0);
    X11RelativeMouseBegin(&m, 60, 70, 0, anywhere);
    assert(m.active && m.virtualX == 60 && m.virtualY == 70 && m.physicalX == 60 && m.physicalY == 70);
    X11RelativeMouseMotion r = motion(&m, 40, 40, true);
    assert(r.post && !r.echo && r.deltaX == -20 && r.deltaY == -30);
    X11RelativeMouseEnd(&m);
    puts("PASS: ungrab clears expected echoes and a new grab starts from the current pointer");
}

static void echoQueueGrowth(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 0, 0, 0, anywhere);
    for (int i = 1; i <= X11_RELATIVE_MOUSE_INITIAL_ECHOES + 3; ++i)
        X11RelativeMouseWarp(&m, i, 0, 100, 0, true);
    assert(m.echoCount == X11_RELATIVE_MOUSE_INITIAL_ECHOES + 3 && m.echoes[0].x == 1);
    X11RelativeMouseMotion r = motion(&m, 6, 0, true);
    assert(r.echo && m.echoCount == X11_RELATIVE_MOUSE_INITIAL_ECHOES - 3 && m.echoes[0].x == 7);
    X11RelativeMouseEnd(&m);
    puts("PASS: echo backlog grows without discarding warps and is consumed in order");
}

static void serialsSeparateMotionFromEchoes(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 100, anywhere);
    /* Events queued before the grab snapshot must not turn into a jump from that snapshot. */
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 0, 0, true, 99);
    assert(!r.post && !r.rewarp && m.physicalX == 500 && m.physicalY == 400);
    X11RelativeMouseExpectEcho(&m, 500, 400, 4, 110);
    /* Real pre-warp motion happens to cross the anchor. Coordinates alone would discard it. */
    m.physicalX = 510;
    r = X11RelativeMouseHandleMotion(&m, 500, 400, true, 105);
    assert(r.post && !r.echo && r.deltaX == -10 && m.echoCount == 1);
    r = X11RelativeMouseHandleMotion(&m, 500, 400, true, 110);
    assert(r.echo && !r.post && m.echoCount == 0);
    /* A later real event at the same target must not be swallowed either. */
    X11RelativeMouseExpectEcho(&m, 520, 400, 2, 120);
    r = X11RelativeMouseHandleMotion(&m, 520, 400, true, 121);
    assert(r.post && !r.echo && r.deltaX == 20);
    X11RelativeMouseEnd(&m);
    puts("PASS: grab snapshot and warp request serials distinguish queued motion from echoes");
}

static void queuedMotionDoesNotMultiplyWarps(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 510, 400, true, 100);
    assert(r.post && r.deltaX == 10 && r.rewarp);
    X11RelativeMouseExpectEcho(&m, 500, 400, 4, 110);
    r = X11RelativeMouseHandleMotion(&m, 520, 400, true, 101);
    assert(r.post && r.deltaX == 10 && !r.rewarp);
    r = X11RelativeMouseHandleMotion(&m, 530, 400, true, 102);
    assert(r.post && r.deltaX == 10 && !r.rewarp && m.echoCount == 1);
    r = X11RelativeMouseHandleMotion(&m, 500, 400, true, 110);
    assert(r.echo && !r.post);
    r = X11RelativeMouseHandleMotion(&m, 502, 401, true, 111);
    assert(r.post && r.deltaX == 2 && r.deltaY == 1 && r.rewarp);
    X11RelativeMouseEnd(&m);
    puts("PASS: queued physical motion uses one pending rewarp without losing deltas");
}

static void confinedWarpAndApplicationReanchor(void) {
    X11RelativeMouse m = {0};
    /* A second monitor at +1920, with a 24-pixel panel above the game. */
    X11RelativeMouseBegin(&m, 2500, 400, 0, (X11RelativeMouseBounds){1920, 24, 3839, 1079});
    double x = 3900, y = -100;
    X11RelativeMouseClamp(&m, &x, &y);
    assert(x == 3839 && y == 24);
    X11RelativeMouseWarp(&m, 3900, -100, 3, 210, true); /* the model clamps an unclamped caller too */
    assert(m.virtualX == 3839 && m.virtualY == 24);
    /* Another application warp must preserve both outstanding echoes, even at the same position. */
    X11RelativeMouseWarp(&m, x, y, 4, 220, true);
    assert(m.echoCount == 2);
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 3839, 24, true, 210);
    assert(r.echo && !r.post && m.echoCount == 1);
    r = X11RelativeMouseHandleMotion(&m, 3839, 24, true, 220);
    assert(r.echo && !r.post && m.echoCount == 0);
    r = X11RelativeMouseHandleMotion(&m, 3830, 30, true, 221);
    assert(r.post && r.deltaX == -9 && r.deltaY == 6);
    assert(r.rewarp && r.warpX == 3839 && r.warpY == 24);
    assert(m.virtualX == 3839 && m.virtualY == 24);
    X11RelativeMouseEnd(&m);
    puts("PASS: confined application warps share one position with events and rewarping on a secondary monitor");
}

static void warpsAreClampedByTheModel(void) {
    X11RelativeMouse m = {0};
    /* The pointer can only be at x >= 0; the server clamps a warp to x = -10 to x = 0. */
    X11RelativeMouseBegin(&m, 500, 400, 0, (X11RelativeMouseBounds){0, 0, 1279, 719});
    X11RelativeMouseWarp(&m, -10, 400, 1, 7, true);
    assert(m.virtualX == 0 && m.echoCount == 1 && m.echoes[0].x == 0);
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 0, 400, true, 7);
    assert(r.echo && !r.post && m.physicalX == 0);
    /* Real motion afterwards is not cancelled by a mismatched echo. */
    int sum = 0;
    for (int i = 1; i <= 5; ++i) {
        r = X11RelativeMouseHandleMotion(&m, 3 * i, 400, true, 20 + i);
        assert(r.post);
        sum += (int) r.deltaX;
    }
    assert(sum == 15);
    /* Also when warps are not honoured: the echo is where the server put the pointer. */
    X11RelativeMouseWarp(&m, 5000, 5000, 1, 40, false);
    assert(m.echoes[m.echoCount - 1].x == 1279 && m.echoes[m.echoCount - 1].y == 719);
    X11RelativeMouseEnd(&m);
    puts("PASS: the model clamps warp targets to the reachable bounds");
}

static void serialsWrap(void) {
    X11RelativeMouse m = {0};
    /* A serial counter that wrapped during the grab (32 bits on i386) is still newer than the snapshot. */
    unsigned long first = ULONG_MAX - 15;
    X11RelativeMouseBegin(&m, 500, 400, first, anywhere);
    assert(X11RelativeMouseSerialBefore(first - 1, first) && !X11RelativeMouseSerialBefore(first, first));
    assert(!X11RelativeMouseSerialBefore(first + 1, first));
    unsigned long wrapped = 16; /* first + 32 */
    assert(!X11RelativeMouseSerialBefore(wrapped, first));
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 505, 400, true, wrapped);
    assert(r.post && r.deltaX == 5);
    /* The pending-rewarp suppression compares serials the same way. */
    X11RelativeMouseExpectEcho(&m, 500, 400, 4, 40);
    r = X11RelativeMouseHandleMotion(&m, 510, 400, true, ULONG_MAX - 2); /* before the echo's serial, across the wrap */
    assert(r.post && !r.rewarp);
    X11RelativeMouseEnd(&m);
    puts("PASS: serial comparisons survive wraparound");
}

int main(void) {
    warpsAreClampedByTheModel();
    serialsWrap();
    serialsSeparateMotionFromEchoes();
    queuedMotionDoesNotMultiplyWarps();
    confinedWarpAndApplicationReanchor();
    xorgHonouredWarps();
    xwaylandVisibleCursor();
    visibleCursorWarpsFollowPointer();
    gameWarpUpdatesVirtual();
    deltaSign();
    ungrabRestores();
    echoQueueGrowth();
    return 0;
}
