// Events keep their order through the event taps.
//
// An active tap holds an event until its callback answers. Events that come after the held one
// wait behind it, whether or not their type is in the tap's mask, and the stream that the layers
// above CoreGraphics read gets everything in the order the events were posted. A tap that does not
// answer in time is disabled (kCGEventTapDisabledByTimeout) and the held event goes on. With no
// event held nothing waits. The public contract (CGEventTapCreate, CGEventTapEnable, CGEventTypes.h)
// does not state the ordering; keeping the posting order is the conservative reading, and macOS
// cannot be asked over ssh (taps and posted events need the right to listen to and post events).
// The stream functions are Darling's own and private.
//
// Copyright (C) 2026 Lubos Dolezel
#include <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

extern CGEventRef _CGSEventStreamCopyNextEvent(void);
extern void _CGSEventStreamSetReadySource(CFRunLoopSourceRef source, CFRunLoopRef runLoop);

static int g_failed;

#define CHECK(cond, ...) do { if (!(cond)) { g_failed++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
#define CHECK_STR(got, want, what) do { if (strcmp((got), (want)) != 0) { g_failed++; \
    printf("FAIL line %d: %s: got \"%s\", want \"%s\"\n", __LINE__, what, (got), (want)); } } while (0)

static double nowSeconds(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

// --- the reader of the stream, as HIToolbox is one. Events are written down as text: K<code> for a
// key down, M<x> for a mouse move at x, D<x> for a left mouse down at x.

static char g_read[512];
static int g_readCount;
static double g_firstReadAt;
static CFRunLoopSourceRef g_readerSource;

static void describe(CGEventRef e, char* out)
{
    CGEventType t = CGEventGetType(e);

    if (t == kCGEventKeyDown)
        sprintf(out, "K%d ", (int) CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode));
    else if (t == kCGEventMouseMoved)
        sprintf(out, "M%d ", (int) CGEventGetLocation(e).x);
    else if (t == kCGEventLeftMouseDown)
        sprintf(out, "D%d ", (int) CGEventGetLocation(e).x);
    else
        sprintf(out, "?%d ", (int) t);
}

static void noteRead(CGEventRef e)
{
    char one[32];

    describe(e, one);
    if (g_readCount == 0)
        g_firstReadAt = nowSeconds();
    if (strlen(g_read) + strlen(one) < sizeof g_read)
        strcat(g_read, one);
    g_readCount++;
}

static void readerPerform(void* info)
{
    CGEventRef e;

    while ((e = _CGSEventStreamCopyNextEvent()) != NULL)
    {
        noteRead(e);
        CFRelease(e);
    }
}

static void startReader(void)
{
    CFRunLoopSourceContext ctx;

    memset(&ctx, 0, sizeof ctx);
    ctx.perform = readerPerform;
    g_readerSource = CFRunLoopSourceCreate(NULL, 0, &ctx);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), g_readerSource, kCFRunLoopDefaultMode);
    _CGSEventStreamSetReadySource(g_readerSource, CFRunLoopGetCurrent());
}

static void stopReader(void)
{
    _CGSEventStreamSetReadySource(NULL, NULL);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), g_readerSource, kCFRunLoopDefaultMode);
    CFRelease(g_readerSource);
}

static void clearRead(void)
{
    g_read[0] = 0;
    g_readCount = 0;
}

// Runs the main run loop until `count` events were read (or `seconds` passed), then a little more
// so that an event that should not be there shows up.
static void spinUntilRead(int count, double seconds)
{
    double end = nowSeconds() + seconds;

    while (nowSeconds() < end && g_readCount < count)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
}

// --- posting

// Where events enter the pipeline
static CGEventTapLocation g_loc = kCGSessionEventTap;

static void postKey(int code)
{
    CGEventRef e = CGEventCreateKeyboardEvent(NULL, code, true);

    CGEventPost(g_loc, e);
    CFRelease(e);
}

static void postMove(int x)
{
    CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(x, 5), kCGMouseButtonLeft);

    CGEventPost(g_loc, e);
    CFRelease(e);
}

static void postDown(int x)
{
    CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(x, 5), kCGMouseButtonLeft);

    CGEventPost(g_loc, e);
    CFRelease(e);
}

// --- the taps

enum { PASS, DROP, MODIFY, SLEEP, SLEEP_ONCE, REENTER };
typedef struct { int action; int sleepMs; int calls; int timeoutNotices; CGEventType lastType; } TapInfo;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* userInfo)
{
    TapInfo* t = (TapInfo*) userInfo;

    t->calls++;
    t->lastType = type;
    if (type == kCGEventTapDisabledByTimeout)
    {
        t->timeoutNotices++;
        return event;
    }

    switch (t->action)
    {
        case DROP:
            if (CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) % 2 == 1)
                return NULL;
            return event;
        case MODIFY:
            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) + 100);
            return event;
        case SLEEP:
            usleep(t->sleepMs * 1000);
            return event;
        case SLEEP_ONCE:
            if (t->calls == 1)
                usleep(t->sleepMs * 1000);
            return event;
        case REENTER:
        {
            // An event of the tap's own, posted from the callback: it goes on from this tap.
            CGEventRef extra = CGEventCreateKeyboardEvent(NULL, 77, true);

            CGEventTapPostEvent(proxy, extra);
            CFRelease(extra);
            return event;
        }
    }
    return event;
}

static CGEventMask keysMask(void)
{
    return CGEventMaskBit(kCGEventKeyDown);
}

static CGEventMask keysAndDownMask(void)
{
    return CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventLeftMouseDown);
}

static CFMachPortRef makeTap(CGEventTapPlacement place, CGEventTapOptions opts, TapInfo* info, CGEventMask mask)
{
    CFMachPortRef port = CGEventTapCreate(kCGSessionEventTap, place, opts, mask, tapCallback, info);

    CHECK(port != NULL, "tap made");
    if (port)
    {
        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, port, 0);

        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
        CFRelease(src);
    }
    return port;
}

static void removeTap(CFMachPortRef port)
{
    CFMachPortInvalidate(port);
    CFRelease(port);
}

// --- tests

static void test_mask_subset_keeps_order(void)
{
    // The tap is on keys and left mouse down. Events outside the mask (moves) must not get ahead of
    // the key that waits for the tap, which runs when the loop that has the tap runs.
    TapInfo info = { PASS };
    CFMachPortRef tap = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionDefault, &info, keysAndDownMask());

    clearRead();
    postMove(1);
    postKey(12);
    postMove(2);
    postMove(3);
    postDown(4);
    postMove(5);
    postKey(13);
    postMove(6);
    spinUntilRead(8, 3);
    CHECK_STR(g_read, "M1 K12 M2 M3 D4 M5 K13 M6 ", "order at the stream");
    CHECK(info.calls == 3, "the tap saw the three events of its mask (%d)", info.calls);
    removeTap(tap);
}

static void test_nothing_waits_when_nothing_is_held(void)
{
    // No event is at the tap: events outside the mask are in the stream as soon as they are posted,
    // and so are events in the mask that the tap does not hold (a listen-only tap).
    TapInfo info = { PASS };
    CFMachPortRef tap = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionDefault, &info, keysMask());
    CGEventRef e;

    clearRead();
    postMove(1);
    e = _CGSEventStreamCopyNextEvent();
    CHECK(e != NULL, "a move is in the stream at once");
    if (e)
        CFRelease(e);

    // With a key held, the move is not delivered yet
    postKey(12);
    postMove(2);
    e = _CGSEventStreamCopyNextEvent();
    CHECK(e == NULL, "a move does not pass the held key");
    if (e)
        CFRelease(e);
    spinUntilRead(2, 3);
    CHECK_STR(g_read, "K12 M2 ", "the key, then the move");

    // The tap has answered: it is the same as before
    postMove(3);
    e = _CGSEventStreamCopyNextEvent();
    CHECK(e != NULL, "a move is in the stream at once again");
    if (e)
        CFRelease(e);
    removeTap(tap);

    TapInfo listen = { PASS };
    CFMachPortRef listenTap = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, &listen, keysMask());

    clearRead();
    postKey(14);
    e = _CGSEventStreamCopyNextEvent();
    CHECK(e != NULL, "a key is not held by a listen-only tap");
    if (e)
        CFRelease(e);
    postMove(4);
    e = _CGSEventStreamCopyNextEvent();
    CHECK(e != NULL, "nor does a move wait for it");
    if (e)
        CFRelease(e);
    removeTap(listenTap);
}

static void test_drop_and_modify(void)
{
    // A tap that drops some events and one that changes them: the events that go on keep their order.
    TapInfo dropper = { DROP };
    CFMachPortRef tap = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionDefault, &dropper, keysMask());

    clearRead();
    postKey(2);
    postMove(1);
    postKey(3);
    postMove(2);
    postKey(4);
    postMove(3);
    spinUntilRead(5, 3);
    CHECK_STR(g_read, "K2 M1 M2 K4 M3 ", "a dropped key leaves no gap and no reordering");
    removeTap(tap);

    TapInfo modifier = { MODIFY };
    tap = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionDefault, &modifier, keysMask());
    clearRead();
    postMove(1);
    postKey(2);
    postMove(2);
    postKey(3);
    postMove(3);
    spinUntilRead(5, 3);
    CHECK_STR(g_read, "M1 K102 M2 K103 M3 ", "modified keys keep their place");
    removeTap(tap);
}

static void test_two_taps(void)
{
    // An event outside the mask of the first tap waits for the event the first tap holds even though
    // the second tap is the only one it is for.
    TapInfo first = { PASS }, second = { PASS };
    CFMachPortRef p1 = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionDefault, &first, keysMask());
    CFMachPortRef p2 = makeTap(kCGTailAppendEventTap, kCGEventTapOptionDefault, &second, CGEventMaskBit(kCGEventMouseMoved));

    clearRead();
    postKey(12);
    postMove(1);
    postKey(13);
    postMove(2);
    spinUntilRead(4, 3);
    CHECK_STR(g_read, "K12 M1 K13 M2 ", "order with two taps");
    CHECK(first.calls == 2 && second.calls == 2, "calls %d and %d", first.calls, second.calls);
    removeTap(p1);
    removeTap(p2);
}

static void test_tap_posts_event(void)
{
    // An event a tap posts from its callback goes on from that tap in front of the event the tap
    // holds; what was posted after the held event stays behind it.
    TapInfo info = { REENTER };
    CFMachPortRef tap = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionDefault, &info, keysMask());

    clearRead();
    postKey(12);
    postMove(1);
    spinUntilRead(3, 3);
    CHECK_STR(g_read, "K77 K12 M1 ", "the tap's own event, the held one, the move");
    removeTap(tap);
}

// A tap that answers slowly, on the main loop: events posted from another thread meanwhile.
static void* posterThread(void* arg)
{
    postKey(12);
    postMove(1);
    usleep(30 * 1000);
    postMove(2);
    postKey(13);
    usleep(30 * 1000);
    postMove(3);
    postDown(4);
    postMove(4);
    return NULL;
}

static void test_slow_callback(void)
{
    TapInfo info = { SLEEP, 150 };
    CFMachPortRef tap = makeTap(kCGHeadInsertEventTap, kCGEventTapOptionDefault, &info, keysAndDownMask());
    pthread_t th;

    clearRead();
    pthread_create(&th, NULL, posterThread, NULL);
    spinUntilRead(7, 5);
    pthread_join(th, NULL);
    CHECK_STR(g_read, "K12 M1 M2 K13 M3 D4 M4 ", "order with a slow callback");
    removeTap(tap);
}

// A tap on another thread's loop that does not answer in time.
static CFRunLoopRef g_tapLoop;
static pthread_mutex_t g_tapLoopLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_tapLoopCond = PTHREAD_COND_INITIALIZER;
static CFMachPortRef g_slowTap;
static TapInfo g_slow = { SLEEP_ONCE, 1600 };

static void* slowTapThread(void* arg)
{
    pthread_mutex_lock(&g_tapLoopLock);
    g_slowTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, keysMask(), tapCallback, &g_slow);
    if (g_slowTap)
    {
        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, g_slowTap, 0);

        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
        CFRelease(src);
    }
    g_tapLoop = CFRunLoopGetCurrent();
    pthread_cond_signal(&g_tapLoopCond);
    pthread_mutex_unlock(&g_tapLoopLock);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 6.0, false);
    return NULL;
}

static void test_timeout_keeps_order(void)
{
    pthread_t th;

    pthread_create(&th, NULL, slowTapThread, NULL);
    pthread_mutex_lock(&g_tapLoopLock);
    while (!g_tapLoop)
        pthread_cond_wait(&g_tapLoopCond, &g_tapLoopLock);
    pthread_mutex_unlock(&g_tapLoopLock);
    CHECK(g_slowTap != NULL, "tap on the other thread");

    g_loc = kCGHIDEventTap;
    clearRead();
    double start = nowSeconds();
    postKey(12);
    postMove(1);
    postMove(2);
    postKey(13);
    postMove(3);
    spinUntilRead(5, 6);
    // The moves wait for the key until the system stops waiting for the tap, then everything goes on
    // in order; the second key does not wait again, the tap is off.
    CHECK_STR(g_read, "K12 M1 M2 K13 M3 ", "order across a timeout");
    CHECK(g_readCount == 5 && g_firstReadAt - start > 0.5, "the first event came after %.2f s: the rest waited for it", g_firstReadAt - start);
    CHECK(g_firstReadAt - start < 1.55, "the system stopped waiting (%.2f s)", g_firstReadAt - start);
    CHECK(!CGEventTapIsEnabled(g_slowTap), "the tap that timed out is disabled");

    double end = nowSeconds() + 4;

    while (g_slow.timeoutNotices == 0 && nowSeconds() < end)
        usleep(20 * 1000);
    CHECK(g_slow.timeoutNotices == 1, "the tap is told about the timeout (%d)", g_slow.timeoutNotices);
    CHECK(g_slow.lastType == kCGEventTapDisabledByTimeout, "the last call was the notice");

    // With the tap off nothing waits
    clearRead();
    postKey(14);
    CGEventRef e = _CGSEventStreamCopyNextEvent();
    CHECK(e != NULL, "events go through at once while the tap is off");
    if (e)
        CFRelease(e);
    pthread_join(th, NULL);
    removeTap(g_slowTap);
}

int main(void)
{
    startReader();
    test_mask_subset_keeps_order();
    test_nothing_waits_when_nothing_is_held();
    test_drop_and_modify();
    test_two_taps();
    test_tap_posts_event();
    test_slow_callback();
    test_timeout_keeps_order();
    stopReader();

    if (g_failed)
    {
        printf("%d checks failed\n", g_failed);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
