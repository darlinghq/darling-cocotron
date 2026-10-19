#ifndef X11_RELATIVE_MOUSE_HEADER
#define X11_RELATIVE_MOUSE_HEADER "../AppKit/X11.backend/X11RelativeMouse.h"
#endif
#include X11_RELATIVE_MOUSE_HEADER
#undef NDEBUG /* the checks are asserts */
#include <assert.h>
#include <math.h>
#include <limits.h>
#include <stdio.h>

/* Host model of the X11 backend's relative mouse mode (CGAssociateMouseAndMouseCursorPosition(false)).
 * A warp's echo is simulated as the MotionNotify the server queues at the target; `queued` is the number of
 * X events queued after the backend's XSync. */
/* Room for every coordinate these scenarios use; scenarios about reachability pass their own bounds. */
static const X11RelativeMouseBounds anywhere = {-100000, -100000, 100000, 100000};

/* The server's request counter: events carry the serial of the last request processed when they were generated,
 * so real motion that arrives after a warp has a newer serial than the warp, motion queued before it an older one,
 * and the warp's own result carries the warp's serial. */
static unsigned long nextSerial = 100;

static X11RelativeMouseMotion motion(X11RelativeMouse *m, int x, int y, bool honoured) {
    return X11RelativeMouseHandleMotion(m, x, y, honoured, nextSerial++);
}

/* Records an echo expected for a warp request sent now and returns the request's serial. */
static unsigned long expectEcho(X11RelativeMouse *m, int x, int y, unsigned queued) {
    unsigned long serial = nextSerial++;
    X11RelativeMouseExpectEcho(m, x, y, queued, serial);
    return serial;
}

static unsigned long warp(X11RelativeMouse *m, double x, double y, unsigned queued, bool honoured) {
    unsigned long serial = nextSerial++;
    X11RelativeMouseWarp(m, x, y, queued, serial, honoured);
    return serial;
}

/* The MotionNotify a warp request generated, at the position the server put the pointer. */
static X11RelativeMouseMotion echo(X11RelativeMouse *m, unsigned long serial, int x, int y, bool honoured) {
    return X11RelativeMouseHandleMotion(m, x, y, honoured, serial);
}

static void xorgHonouredWarps(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    /* Physical motion: delta reported, the cursor stays frozen, the pointer is warped back. */
    X11RelativeMouseMotion r = motion(&m, 510, 395, true);
    assert(r.post && !r.echo && r.deltaX == 10 && r.deltaY == -5);
    assert(r.rewarp && r.warpX == 500 && r.warpY == 400);
    unsigned long s = expectEcho(&m, r.warpX, r.warpY, 1);
    /* The rewarp's echo is consumed and is not a delta back to the centre. */
    r = echo(&m, s, 500, 400, true);
    assert(!r.post && r.echo && !r.rewarp && m.echoCount == 0);
    assert(m.physicalX == 500 && m.physicalY == 400);
    r = motion(&m, 503, 404, true);
    assert(r.post && r.deltaX == 3 && r.deltaY == 4 && r.rewarp);
    expectEcho(&m, r.warpX, r.warpY, 1);

    /* A real motion queued before the warp's echo still measures against the last physical position, and
     * does not start a second warp. */
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    unsigned long queuedFirst = nextSerial++, queuedSecond = nextSerial++;
    r = echo(&m, queuedFirst, 520, 400, true);
    s = expectEcho(&m, r.warpX, r.warpY, 2); /* the second motion was already queued */
    r = echo(&m, queuedSecond, 530, 400, true);
    assert(r.post && r.deltaX == 10 && r.deltaY == 0 && !r.rewarp);
    assert(m.echoCount == 1);
    X11RelativeMouseExpectEcho(&m, 500, 400, 1, s); /* the same request again: merged, not a second echo */
    assert(m.echoCount == 1);
    r = echo(&m, s, 500, 400, true);
    assert(r.echo && m.echoCount == 0);
    r = motion(&m, 499, 400, true);
    assert(r.post && r.deltaX == -1);

    /* The application warps from the event it was given while our rewarp's echo is still queued:
     * both echoes are dropped in order and neither cancels the motion. */
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    r = motion(&m, 512, 400, true);
    assert(r.deltaX == 12 && r.rewarp);
    s = expectEcho(&m, r.warpX, r.warpY, 1);
    unsigned long gameWarp = warp(&m, 524.0, 400.0, 2, true); /* game: mouseLocation + 2 * delta */
    assert(m.virtualX == 524.0 && m.physicalX == 512);
    r = echo(&m, s, 500, 400, true);
    assert(r.echo && m.physicalX == 500);
    r = echo(&m, gameWarp, 524, 400, true);
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
    unsigned long s = warp(&m, 820.0, 450.0, 1, false);
    /* The echo at the target is dropped without moving the physical position... */
    r = echo(&m, s, 820, 450, false);
    assert(r.echo && !r.post && m.physicalX == 810 && m.physicalY == 450);
    /* ...so the next real motion, at the real absolute position, gives the true delta. */
    r = motion(&m, 812, 453, false);
    assert(r.post && r.deltaX == 2 && r.deltaY == 3 && !r.rewarp);
    assert(m.virtualX == 812.0 && m.virtualY == 453.0);
    /* An expected echo that never arrives expires after the queued events and cannot eat a later motion. */
    warp(&m, 700.0, 400.0, 1, false);
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
        unsigned long s = warp(&m, gameX, gameY, 1, false);
        r = echo(&m, s, (int) gameX, (int) gameY, false); /* the unhonoured warp's echo */
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
        X11RelativeMouseWarp(&m, i, 0, 100, 10 + i, true);
    assert(m.echoCount == X11_RELATIVE_MOUSE_INITIAL_ECHOES + 3 && m.echoes[0].x == 1);
    X11RelativeMouseMotion r = echo(&m, 16, 6, 0, true);
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
    assert(m.virtualX == 3839 && m.virtualY == 24 && m.echoes[0].x == 3775 && m.echoes[0].y == 88);
    /* Another application warp must preserve both outstanding echoes, even at the same position. */
    X11RelativeMouseWarp(&m, x, y, 4, 220, true);
    assert(m.echoCount == 2);
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 3775, 88, true, 210);
    assert(r.echo && !r.post && m.echoCount == 1);
    r = X11RelativeMouseHandleMotion(&m, 3775, 88, true, 220);
    assert(r.echo && !r.post && m.echoCount == 0);
    r = X11RelativeMouseHandleMotion(&m, 3766, 94, true, 221);
    assert(r.post && r.deltaX == -9 && r.deltaY == 6);
    assert(r.rewarp && r.warpX == 3775 && r.warpY == 88);
    assert(m.virtualX == 3839 && m.virtualY == 24);
    X11RelativeMouseEnd(&m);
    puts("PASS: confined application warps share one position with events and rewarping on a secondary monitor");
}

static void warpsAreClampedByTheModel(void) {
    X11RelativeMouse m = {0};
    /* The pointer can only be at x >= 100; the cursor goes to x = 100 for a warp to x = 50, and the pointer is
     * parked 64 pixels inside the edge. */
    X11RelativeMouseBegin(&m, 500, 400, 0, (X11RelativeMouseBounds){100, 0, 1379, 719});
    X11RelativeMouseWarp(&m, 50, 400, 1, 7, true);
    assert(m.virtualX == 100 && m.echoCount == 1 && m.echoes[0].x == 164 && m.echoes[0].y == 400);
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 164, 400, true, 7);
    assert(r.echo && !r.post && m.physicalX == 164 && m.virtualX == 100);
    /* Real motion afterwards is not cancelled by a mismatched echo. */
    int sum = 0;
    for (int i = 1; i <= 5; ++i) {
        r = X11RelativeMouseHandleMotion(&m, 164 + 3 * i, 400, true, 20 + i);
        assert(r.post);
        sum += (int) r.deltaX;
    }
    assert(sum == 15);
    /* Also when warps are not honoured: the echo is where the server put the pointer. */
    X11RelativeMouseWarp(&m, 5000, 5000, 1, 40, false);
    assert(m.echoes[m.echoCount - 1].x == 1379 && m.echoes[m.echoCount - 1].y == 719);
    X11RelativeMouseEnd(&m);
    puts("PASS: the model clamps warp targets to the reachable bounds");
}

static void frozenCursorNearAnEdgeKeepsFullDeltas(void) {
    X11RelativeMouse m = {0};
    /* The grab window starts at x = 100; the cursor froze 3 pixels from its left edge. */
    X11RelativeMouseBegin(&m, 103, 250, 0, (X11RelativeMouseBounds){100, 100, 499, 399});
    X11RelativeMouseMotion r = motion(&m, 103, 251, true);
    assert(r.post && r.rewarp && r.warpX == 164 && r.warpY == 250); /* parked inside, not on the cursor */
    unsigned long s = expectEcho(&m, r.warpX, r.warpY, 1);
    r = echo(&m, s, 164, 250, true);
    assert(r.echo && m.virtualX == 103 && m.virtualY == 250 && m.physicalX == 164);
    double sum = 0;
    for (int i = 0; i < 10; ++i) {
        r = motion(&m, 164 - 20, 250, true); /* the pointer travels 20 pixels left each time */
        assert(r.post && r.deltaX == -20 && r.rewarp && r.warpX == 164);
        s = expectEcho(&m, r.warpX, r.warpY, 1);
        sum += r.deltaX;
        r = echo(&m, s, 164, 250, true);
        assert(r.echo);
    }
    assert(sum == -200 && m.virtualX == 103); /* the cursor never moved */
    /* The window is too small for the full margin: a quarter of it. */
    X11RelativeMouseBegin(&m, 10, 10, 0, (X11RelativeMouseBounds){0, 0, 39, 39});
    int tx, ty;
    X11RelativeMousePointerTarget(&m, 0, 39, true, &tx, &ty);
    assert(tx == 9 && ty == 30);
    X11RelativeMousePointerTarget(&m, 0, 39, false, &tx, &ty); /* not honoured: nothing is parked */
    assert(tx == 0 && ty == 39);
    X11RelativeMouseEnd(&m);
    puts("PASS: a cursor frozen near the confine edge still gets full deltas");
}

static void unreachableWarpTargetIsFollowed(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    /* A warp to (900, 700), but the server could only put the pointer at (700, 500): same request serial. */
    X11RelativeMouseWarp(&m, 900, 700, 1, 30, true);
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 700, 500, true, 30);
    assert(r.echo && !r.post && !r.rewarp && m.echoCount == 0);
    assert(m.physicalX == 700 && m.virtualX == 700 && m.virtualY == 500);
    /* The next real motion warps back to a place that exists, not to (900, 700) again. */
    r = X11RelativeMouseHandleMotion(&m, 703, 500, true, 31);
    assert(r.post && r.deltaX == 3 && r.rewarp && r.warpX == 700 && r.warpY == 500);
    /* Another event with the serial of a consumed warp is motion. */
    X11RelativeMouseWarp(&m, 600, 500, 2, 40, true);
    r = X11RelativeMouseHandleMotion(&m, 600, 500, true, 40);
    assert(r.echo);
    r = X11RelativeMouseHandleMotion(&m, 604, 500, true, 40);
    assert(r.post && !r.echo && r.deltaX == 4);
    /* Not honoured: the echo is still dropped and nothing else changes. */
    X11RelativeMouseBegin(&m, 800, 450, 0, anywhere);
    X11RelativeMouseWarp(&m, 900, 450, 1, 50, false);
    r = X11RelativeMouseHandleMotion(&m, 850, 450, false, 50);
    assert(r.echo && !r.post && m.physicalX == 800 && m.virtualX == 800);
    X11RelativeMouseEnd(&m);
    puts("PASS: a warp's result at an unreachable target is an echo and the cursor follows the pointer");
}

static void warpToTheSamePlaceExpectsNoEcho(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    /* No MotionNotify comes back for a warp to where the pointer already is, even with other events queued. */
    warp(&m, 500, 400, 3, true);
    assert(m.echoCount == 0);
    /* So a real motion that carries the warp's serial is motion, not an echo. */
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 507, 400, true, nextSerial - 1);
    assert(r.post && !r.echo && r.deltaX == 7);
    /* A warp elsewhere still expects its echo. */
    warp(&m, 600, 400, 1, true);
    assert(m.echoCount == 1);
    X11RelativeMouseEnd(&m);
    /* A re-grab puts the frozen cursor back, clamped to the new bounds. */
    X11RelativeMouseBegin(&m, 500, 400, 0, (X11RelativeMouseBounds){0, 0, 799, 599});
    X11RelativeMouseRestoreCursor(&m, 700.5, 900);
    assert(m.virtualX == 700.5 && m.virtualY == 599 && m.physicalX == 500);
    X11RelativeMouseEnd(&m);
    puts("PASS: a warp to the pointer's own position expects no echo");
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

static void nonFiniteWarpsAreRefused(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 0, (X11RelativeMouseBounds){0, 0, 1279, 719});
    double bad[] = {NAN, INFINITY, -INFINITY};
    for (int i = 0; i < 3; ++i) {
        assert(!X11RelativeMouseWarp(&m, bad[i], 100, 1, 3, true));
        assert(!X11RelativeMouseWarp(&m, 100, bad[i], 1, 3, true));
    }
    assert(m.virtualX == 500 && m.virtualY == 400 && m.echoCount == 0);
    X11RelativeMouseEnd(&m);
    puts("PASS: non-finite warp targets are refused");
}

static void echoExpiryAndMotionAging(void) {
    X11RelativeMouse m = {0};
    /* An echo expected within 2 events survives one unrelated motion and expires on the second. */
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    X11RelativeMouseExpectEcho(&m, 500, 400, 2, 5);
    X11RelativeMouseMotion r = X11RelativeMouseHandleMotion(&m, 510, 400, true, 1);
    assert(r.post && !r.echo && m.echoCount == 1 && m.echoes[0].remaining == 1);
    r = X11RelativeMouseHandleMotion(&m, 520, 400, true, 2);
    assert(r.post && !r.echo && m.echoCount == 0);
    /* Merging an identical echo keeps the larger remaining count, whichever order they arrive in. */
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    X11RelativeMouseExpectEcho(&m, 500, 400, 2, 5);
    X11RelativeMouseExpectEcho(&m, 500, 400, 1, 5);
    assert(m.echoCount == 1 && m.echoes[0].remaining == 2);
    X11RelativeMouseExpectEcho(&m, 500, 400, 3, 5);
    assert(m.echoCount == 1 && m.echoes[0].remaining == 3);
    /* Consuming an echo ages the ones behind it. */
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    X11RelativeMouseExpectEcho(&m, 500, 400, 3, 7);
    X11RelativeMouseExpectEcho(&m, 520, 400, 3, 8);
    r = X11RelativeMouseHandleMotion(&m, 500, 400, true, 7);
    assert(r.echo && m.echoCount == 1 && m.echoes[0].x == 520 && m.echoes[0].remaining == 2);
    /* Motion predating the grab snapshot is ignored but still ages echoes. */
    X11RelativeMouseBegin(&m, 500, 400, 100, anywhere);
    X11RelativeMouseExpectEcho(&m, 500, 400, 2, 110);
    r = X11RelativeMouseHandleMotion(&m, 0, 0, true, 99);
    assert(!r.post && m.echoCount == 1 && m.echoes[0].remaining == 1);
    r = X11RelativeMouseHandleMotion(&m, 0, 0, true, 98);
    assert(!r.post && m.echoCount == 0);
    X11RelativeMouseEnd(&m);
    puts("PASS: expected echoes age on every handled event and expire");
}

static void zeroDeltaAndRewarpAxes(void) {
    X11RelativeMouse m = {0};
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    X11RelativeMouseMotion r = motion(&m, 500, 400, true);
    assert(!r.post && !r.echo && !r.rewarp && r.deltaX == 0 && r.deltaY == 0);
    /* The pointer differs from the frozen cursor in one axis only: still rewarped. */
    r = motion(&m, 500, 405, true);
    assert(r.post && r.rewarp && r.warpX == 500 && r.warpY == 400);
    X11RelativeMouseBegin(&m, 500, 400, 0, anywhere);
    r = motion(&m, 507, 400, true);
    assert(r.post && r.rewarp && r.warpX == 500 && r.warpY == 400);
    X11RelativeMouseEnd(&m);
    puts("PASS: zero-delta motion is not posted and a one-axis offset is rewarped");
}

int main(void) {
    echoExpiryAndMotionAging();
    zeroDeltaAndRewarpAxes();
    nonFiniteWarpsAreRefused();
    warpToTheSamePlaceExpectsNoEcho();
    frozenCursorNearAnEdgeKeepsFullDeltas();
    unreachableWarpTargetIsFollowed();
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
