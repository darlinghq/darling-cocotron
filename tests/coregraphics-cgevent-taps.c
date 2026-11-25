// Event taps, posting and the event stream of the process.
//
// Taps are registered and run in this process: CGEventPost, CGEventPostToPid, CGEventTapPostEvent
// and the window system's _CGSEventStreamPost send an event through the taps, in order, then to the
// stream that the layers above CoreGraphics read. The stream functions are Darling's own and
// private; the tap and posting calls are the public API (macOS needs the right to listen to
// events before it makes a tap, and drops the events that an ssh session posts, so the macOS run of
// this test only reaches the first failure).
//
// Copyright (C) 2026 Lubos Dolezel
#include <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

extern void _CGSEventStreamPost(CGEventRef event);
extern CGEventRef _CGSEventStreamCopyNextEvent(void);
extern void _CGSEventStreamSetReadySource(CFRunLoopSourceRef source, CFRunLoopRef runLoop);

static int g_failed;

#define CHECK(cond, ...) do { if (!(cond)) { g_failed++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
#define CHECK_INT(got, want, what) do { long long g_ = (long long)(got), w_ = (long long)(want); \
    if (g_ != w_) { g_failed++; printf("FAIL line %d: %s: got %lld, want %lld\n", __LINE__, what, g_, w_); } } while (0)

static double nowSeconds(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

// --- the reader of the stream, as HIToolbox is one: a run loop source that is woken when the stream
// goes from empty to not empty and that drains it.

#define MAX_READ 256
static CGEventRef g_read[MAX_READ];
static int g_readCount;
static int g_wakeups;
static CFRunLoopSourceRef g_readerSource;

static void readerPerform(void* info)
{
    CGEventRef e;

    g_wakeups++;
    while ((e = _CGSEventStreamCopyNextEvent()) != NULL)
    {
        if (g_readCount < MAX_READ)
            g_read[g_readCount++] = e;
        else
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
    g_readerSource = NULL;
}

static void clearRead(void)
{
    for (int i = 0; i < g_readCount; i++)
        CFRelease(g_read[i]);
    g_readCount = 0;
    g_wakeups = 0;
}

// Runs the main run loop for up to `seconds`, ending early once `count` events were read and no more come
// in the next 50 ms (so that "nothing else arrives" can be tested without a long wait).
static void spinUntilRead(int count, double seconds)
{
    double end = nowSeconds() + seconds;

    while (nowSeconds() < end && g_readCount < count)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
}

static void spin(double seconds)
{
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

// --- the taps

static char g_order[64];
static int g_orderLen;

static void note(char c)
{
    if (g_orderLen < (int) sizeof g_order - 1)
        g_order[g_orderLen++] = c;
    g_order[g_orderLen] = 0;
}

static void resetOrder(void)
{
    g_orderLen = 0;
    g_order[0] = 0;
}

// userInfo: the character noted, and what the tap does
enum { PASS, DROP, MODIFY, REPLACE, REENTER, SLEEP };
typedef struct { char id; int action; int calls; CGEventType lastType; pthread_t thread; CGEventTapProxy proxy; } TapInfo;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* userInfo)
{
    TapInfo* t = (TapInfo*) userInfo;

    note(t->id);
    t->calls++;
    t->lastType = type;
    t->thread = pthread_self();
    t->proxy = proxy;

    switch (t->action)
    {
        case DROP:
            return NULL;
        case MODIFY:
            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 55);
            return event;
        case REPLACE:
        {
            CGEventRef other = CGEventCreateKeyboardEvent(NULL, 66, true);
            return other;
        }
        case REENTER:
        {
            // An event of the tap's own: enters after this tap
            CGEventRef extra = CGEventCreateKeyboardEvent(NULL, 77, true);
            CGEventTapPostEvent(proxy, extra);
            CFRelease(extra);
            return event;
        }
        case SLEEP:
            if (type != kCGEventTapDisabledByTimeout)
                usleep(1600 * 1000);
            return event;
    }
    return event;
}

static CGEventMask keys(void)
{
    return CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
}

static CFMachPortRef makeTap(CGEventTapLocation loc, CGEventTapPlacement place, CGEventTapOptions opts, TapInfo* info, CGEventMask mask)
{
    CFMachPortRef port = CGEventTapCreate(loc, place, opts, mask, tapCallback, info);

    CHECK(port != NULL, "tap %c made", info->id);
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

static CGEventRef keyDown(int code)
{
    return CGEventCreateKeyboardEvent(NULL, code, true);
}

// --- tests

static void test_post_reaches_stream(void)
{
    // Before a reader exists nothing is kept.
    CGEventRef e = keyDown(12);

    CGEventPost(kCGSessionEventTap, e);
    startReader();
    spin(0.1);
    CHECK_INT(g_readCount, 0, "an event posted before there was a reader");

    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 2);
    CHECK_INT(g_readCount, 1, "events read after a post");
    if (g_readCount == 1)
    {
        CHECK_INT(CGEventGetIntegerValueField(g_read[0], kCGKeyboardEventKeycode), 12, "key code of the event read");
        CHECK(CGEventGetTimestamp(g_read[0]) != 0, "the posted event is time stamped");
        CHECK(g_read[0] != e, "the stream has its own copy of the event");
    }
    CHECK_INT(CGEventGetTimestamp(e), 0, "the event of the caller is untouched by the post");
    CHECK(g_wakeups >= 1, "the reader source was signalled");

    // Order, and one wake up for a burst
    clearRead();
    for (int i = 0; i < 5; i++)
    {
        CGEventRef k = keyDown(20 + i);
        CGEventPost(kCGHIDEventTap, k);
        CFRelease(k);
    }
    spinUntilRead(5, 2);
    CHECK_INT(g_readCount, 5, "burst");
    for (int i = 0; i < g_readCount; i++)
        CHECK_INT(CGEventGetIntegerValueField(g_read[i], kCGKeyboardEventKeycode), 20 + i, "stream order");
    CHECK(g_wakeups <= 5, "wake ups %d", g_wakeups);

    // The window system's entry point retains the event itself.
    clearRead();
    CGEventRef w = keyDown(31);
    _CGSEventStreamPost(w);
    CFRelease(w);
    spinUntilRead(1, 2);
    CHECK_INT(g_readCount, 1, "event of _CGSEventStreamPost");
    if (g_readCount == 1)
        CHECK_INT(CGEventGetIntegerValueField(g_read[0], kCGKeyboardEventKeycode), 31, "its key code");

    // Nothing posted, nothing read
    CHECK(_CGSEventStreamCopyNextEvent() == NULL, "empty stream");
    CFRelease(e);

    // Stopping the reader drops what is waiting and stops keeping events
    clearRead();
    CGEventRef a = keyDown(40);
    CGEventPost(kCGSessionEventTap, a);
    _CGSEventStreamSetReadySource(NULL, NULL);
    CHECK(_CGSEventStreamCopyNextEvent() == NULL, "events dropped when the reader goes");
    CGEventPost(kCGSessionEventTap, a);
    CHECK(_CGSEventStreamCopyNextEvent() == NULL, "no events kept without a reader");
    CFRelease(a);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), g_readerSource, kCFRunLoopDefaultMode);
    CFRelease(g_readerSource);
    startReader();
}

static void test_tap_order(void)
{
    TapInfo hidHead = { 'a' }, hidTail = { 'b' }, hidHead2 = { 'c' }, session = { 'd' }, annotated = { 'e' }, sessionHead = { 'f' };
    CFMachPortRef p1 = makeTap(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &hidHead, keys());
    CFMachPortRef p2 = makeTap(kCGHIDEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault, &hidTail, keys());
    CFMachPortRef p3 = makeTap(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &hidHead2, keys());
    CFMachPortRef p4 = makeTap(kCGSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault, &session, keys());
    CFMachPortRef p5 = makeTap(kCGAnnotatedSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault, &annotated, keys());
    CFMachPortRef p6 = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &sessionHead, keys());
    CGEventRef e = keyDown(12);

    clearRead();
    resetOrder();
    CGEventPost(kCGHIDEventTap, e);
    spinUntilRead(1, 3);
    // HID head inserts (last made first), then HID tail, then session head, session tail, annotated
    CHECK(strcmp(g_order, "cabfde") == 0, "order of the taps for a HID post: %s", g_order);
    CHECK_INT(g_readCount, 1, "event arrives once after the taps");

    resetOrder();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(2, 3);
    CHECK(strcmp(g_order, "fde") == 0, "order for a session post (the HID taps do not see it): %s", g_order);

    resetOrder();
    CGEventPost(kCGAnnotatedSessionEventTap, e);
    spinUntilRead(3, 3);
    CHECK(strcmp(g_order, "e") == 0, "order for an annotated session post: %s", g_order);

    // The callback runs on the thread of the run loop that has the tap, with the right type.
    CHECK(pthread_equal(hidHead.thread, pthread_self()), "tap runs on the main thread");
    CHECK_INT(hidHead.lastType, kCGEventKeyDown, "type given to the callback");

    // Events whose type the mask does not have skip the tap
    resetOrder();
    CGEventRef m = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(1, 2), 0);
    CGEventPost(kCGHIDEventTap, m);
    spin(0.2);
    CHECK(strcmp(g_order, "") == 0, "mouse event is not in the mask of the key taps: %s", g_order);
    CFRelease(m);

    CFRelease(e);
    removeTap(p1);
    removeTap(p2);
    removeTap(p3);
    removeTap(p4);
    removeTap(p5);
    removeTap(p6);
    clearRead();
}

static void test_listen_only_active_drop_modify(void)
{
    TapInfo listen = { 'l', MODIFY }, passer = { 'p', PASS };
    CFMachPortRef pl = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, &listen, keys());
    CGEventRef e = keyDown(12);

    // A listen-only tap sees a copy: what it does to it is not seen by anyone else
    clearRead();
    resetOrder();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 3);
    CHECK(strcmp(g_order, "l") == 0, "listener saw the event: %s", g_order);
    CHECK_INT(g_readCount, 1, "event passes a listen-only tap");
    if (g_readCount == 1)
        CHECK_INT(CGEventGetIntegerValueField(g_read[0], kCGKeyboardEventKeycode), 12, "a listen-only tap does not change the event");
    removeTap(pl);

    // An active tap that modifies
    TapInfo modify = { 'm', MODIFY };
    CFMachPortRef pm = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &modify, keys());
    TapInfo after = { 'z', PASS };
    CFMachPortRef pz = makeTap(kCGSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault, &after, keys());
    clearRead();
    resetOrder();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 3);
    CHECK(strcmp(g_order, "mz") == 0, "order with a modifying tap: %s", g_order);
    CHECK_INT(g_readCount, 1, "modified event arrives");
    if (g_readCount == 1)
        CHECK_INT(CGEventGetIntegerValueField(g_read[0], kCGKeyboardEventKeycode), 55, "modified key code");
    CHECK_INT(CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode), 12, "the posted event of the caller is not modified");
    removeTap(pm);

    // A tap that returns another event
    TapInfo replace = { 'r', REPLACE };
    CFMachPortRef pr = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &replace, keys());
    clearRead();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 3);
    CHECK_INT(g_readCount, 1, "replacement arrives");
    if (g_readCount == 1)
        CHECK_INT(CGEventGetIntegerValueField(g_read[0], kCGKeyboardEventKeycode), 66, "the event the tap returned");
    removeTap(pr);

    // A tap that drops
    TapInfo drop = { 'd', DROP };
    CFMachPortRef pd = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &drop, keys());
    clearRead();
    resetOrder();
    CGEventPost(kCGSessionEventTap, e);
    spin(0.3);
    CHECK_INT(g_readCount, 0, "a dropped event does not arrive");
    CHECK(strcmp(g_order, "d") == 0, "taps after the dropping one do not see the event: %s", g_order);

    // The same tap listening only cannot drop
    removeTap(pd);
    TapInfo dropper = { 'd', DROP };
    CFMachPortRef pdl = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, &dropper, keys());
    clearRead();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 3);
    CHECK_INT(g_readCount, 1, "a listen-only tap cannot drop an event");
    removeTap(pdl);
    removeTap(pz);
    CFRelease(e);
    clearRead();
}

static void test_enable_disable_and_list(void)
{
    TapInfo t = { 't', PASS };
    CFMachPortRef p = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &t, keys());
    CGEventRef e = keyDown(12);

    CHECK(CGEventTapIsEnabled(p), "a new tap is enabled");
    CGEventTapEnable(p, false);
    CHECK(!CGEventTapIsEnabled(p), "disabled");
    clearRead();
    resetOrder();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 3);
    CHECK(strcmp(g_order, "") == 0, "a disabled tap is not called: %s", g_order);
    CHECK_INT(g_readCount, 1, "the event passes a disabled tap");
    CGEventTapEnable(p, true);
    CHECK(CGEventTapIsEnabled(p), "enabled again");
    clearRead();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 3);
    CHECK(strcmp(g_order, "t") == 0, "an enabled tap is called: %s", g_order);

    // The list of taps
    uint32_t count = 99;
    CHECK_INT(CGGetEventTapList(0, NULL, &count), kCGErrorSuccess, "CGGetEventTapList without a list");
    uint32_t total = count;
    CHECK(total >= 1, "one tap at least: %u", total);
    CGEventTapInformation list[8];
    memset(list, 0xAA, sizeof list);
    CHECK_INT(CGGetEventTapList(8, list, &count), kCGErrorSuccess, "CGGetEventTapList");
    CHECK_INT(count, total, "count with a list");
    int found = 0;
    for (uint32_t i = 0; i < count; i++)
    {
        if (list[i].tappingProcess == getpid() && list[i].eventsOfInterest == keys())
        {
            found++;
            CHECK_INT(list[i].tapPoint, kCGSessionEventTap, "tap point");
            CHECK_INT(list[i].options, kCGEventTapOptionDefault, "options");
            CHECK_INT(list[i].processBeingTapped, 0, "process being tapped");
            CHECK(list[i].enabled, "enabled in the list");
            CHECK(list[i].avgUsecLatency >= 0 && list[i].maxUsecLatency >= list[i].minUsecLatency, "latency");
        }
    }
    CHECK_INT(found, 1, "the tap is in the list once");
    CHECK_INT(CGGetEventTapList(1, list, &count), kCGErrorSuccess, "room for one");
    CHECK_INT(count, 1, "count is limited by the room");
    CHECK(CGGetEventTapList(8, list, NULL) != kCGErrorSuccess, "no count pointer is an error");

    // Invalidating the port removes the tap
    removeTap(p);
    uint32_t after = 99;
    CGGetEventTapList(0, NULL, &after);
    CHECK_INT(after, total - 1, "count after the tap is invalidated");
    resetOrder();
    clearRead();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(1, 3);
    CHECK_INT(g_readCount, 1, "events pass when the tap is gone");
    CHECK(strcmp(g_order, "") == 0, "removed tap is not called: %s", g_order);
    CFRelease(e);
    clearRead();
}

static void test_tap_post_event(void)
{
    // An event posted by a tap goes on from the tap after it, so the tap does not see its own event.
    TapInfo first = { '1', REENTER }, second = { '2', PASS };
    CFMachPortRef p1 = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &first, keys());
    CFMachPortRef p2 = makeTap(kCGSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault, &second, keys());
    CGEventRef e = keyDown(12);

    clearRead();
    resetOrder();
    CGEventPost(kCGSessionEventTap, e);
    spinUntilRead(2, 3);
    CHECK_INT(g_readCount, 2, "the event and the one the tap posted");
    CHECK_INT(first.calls, 1, "the tap that posted did not see its own event");
    CHECK_INT(second.calls, 2, "the next tap saw both");
    if (g_readCount == 2)
    {
        // The event the tap posted is not held up by the tap's own event, so it comes first or second.
        int a = (int) CGEventGetIntegerValueField(g_read[0], kCGKeyboardEventKeycode);
        int b = (int) CGEventGetIntegerValueField(g_read[1], kCGKeyboardEventKeycode);
        CHECK((a == 12 && b == 77) || (a == 77 && b == 12), "key codes %d and %d", a, b);
    }
    CFRelease(e);
    removeTap(p1);
    removeTap(p2);
    clearRead();
}

static void test_post_to_pid(void)
{
    TapInfo self = { 's', PASS }, other = { 'o', PASS }, anyTap = { 'a', PASS };
    CFMachPortRef ps = CGEventTapCreateForPid(getpid(), kCGHeadInsertEventTap, kCGEventTapOptionDefault, keys(), tapCallback, &self);
    CFMachPortRef po = CGEventTapCreateForPid(1, kCGHeadInsertEventTap, kCGEventTapOptionDefault, keys(), tapCallback, &other);
    CFMachPortRef pa = makeTap(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &anyTap, keys());
    CHECK(ps != NULL && po != NULL, "taps for a process made");
    if (ps)
    {
        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, ps, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
        CFRelease(src);
    }
    if (po)
    {
        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, po, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
        CFRelease(src);
    }

    CGEventRef e = keyDown(12);

    clearRead();
    resetOrder();
    CGEventPostToPid(getpid(), e);
    spinUntilRead(1, 3);
    CHECK_INT(g_readCount, 1, "an event posted to this process arrives");
    CHECK(strcmp(g_order, "s") == 0 || strcmp(g_order, "as") == 0, "taps seen by an event for this process: %s", g_order);
    CHECK_INT(other.calls, 0, "a tap for another process sees nothing");
    if (g_readCount == 1)
        CHECK_INT(CGEventGetIntegerValueField(g_read[0], kCGEventTargetUnixProcessID), getpid(), "target process of the delivered event");
    CHECK_INT(CGEventGetIntegerValueField(e, kCGEventTargetUnixProcessID), 0, "the event of the caller keeps its target");

    // An event for another process is not delivered here, and no tap sees it.
    clearRead();
    resetOrder();
    CGEventPostToPid(1, e);
    spin(0.3);
    CHECK_INT(g_readCount, 0, "an event for another process does not arrive");
    CHECK(strcmp(g_order, "") == 0, "taps do not see it: %s", g_order);

    // A process serial number of this process (kCurrentProcess)
    unsigned int psn[2] = { 0, 2 };
    CGEventPostToPSN(psn, e);
    spinUntilRead(1, 3);
    CHECK_INT(g_readCount, 1, "an event posted to the current process by serial number");

    // The list names the process of a tap
    CGEventTapInformation list[32];
    uint32_t count = 0;
    CGGetEventTapList(32, list, &count);
    int self_found = 0, other_found = 0;
    for (uint32_t i = 0; i < count; i++)
    {
        if (list[i].tappingProcess == getpid() && list[i].processBeingTapped == getpid())
            self_found++;
        if (list[i].tappingProcess == getpid() && list[i].processBeingTapped == 1)
            other_found++;
    }
    CHECK_INT(self_found, 1, "tap for this process in the list");
    CHECK_INT(other_found, 1, "tap for another process in the list");

    CFRelease(e);
    if (ps)
        removeTap(ps);
    if (po)
        removeTap(po);
    removeTap(pa);
    clearRead();
}

static void* postFromThread(void* arg)
{
    usleep(150 * 1000);

    CGEventRef e = keyDown(88);

    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
    return NULL;
}

static void test_post_from_other_thread_wakes_waiter(void)
{
    pthread_t th;
    TapInfo t = { 'w', PASS };
    CFMachPortRef p = makeTap(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, &t, keys());

    clearRead();
    double start = nowSeconds();
    pthread_create(&th, NULL, postFromThread, NULL);
    // The waiting thread sleeps in the run loop with nothing else to do
    while (g_readCount == 0 && nowSeconds() - start < 5)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
    double took = nowSeconds() - start;
    pthread_join(th, NULL);
    CHECK_INT(g_readCount, 1, "event posted from another thread arrives");
    CHECK(took < 1.0, "the waiter was woken at once (%.3f s)", took);
    CHECK_INT(t.calls, 1, "the tap ran for the event of the other thread");
    CHECK(pthread_equal(t.thread, pthread_self()), "tap runs on the thread of its run loop, not the one that posted");
    removeTap(p);
    clearRead();
}

static void test_post_updates_source_state(void)
{
    CGEventSourceRef priv = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventSourceRef hid = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    int32_t pid = CGEventSourceGetSourceStateID(priv);

    // A private source: only its own state
    CGEventRef k = CGEventCreateKeyboardEvent(priv, 100, true);
    CGEventSetFlags(k, kCGEventFlagMaskShift);
    CHECK(!CGEventSourceKeyState(pid, 100), "key up before the post");
    CGEventPost(kCGSessionEventTap, k);
    CHECK(CGEventSourceKeyState(pid, 100), "key down after posting key down with the source");
    CHECK_INT(CGEventSourceFlagsState(pid), kCGEventFlagMaskShift, "flags of the state");
    CHECK_INT(CGEventSourceCounterForEventType(pid, kCGEventKeyDown), 1, "key down counter");
    CHECK_INT(CGEventSourceCounterForEventType(pid, kCGAnyInputEventType), 1, "any counter");
    CHECK(CGEventSourceSecondsSinceLastEventType(pid, kCGEventKeyDown) < 1.0, "seconds since the key down");
    CHECK(CGEventSourceSecondsSinceLastEventType(pid, kCGEventKeyUp) > 1.0, "a type that never happened is long ago");
    CHECK(!CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, 100), "a private event does not change the combined state");
    CHECK(!CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, 100), "a private event does not change the HID state");

    CGEventRef u = CGEventCreateKeyboardEvent(priv, 100, false);
    CGEventPost(kCGSessionEventTap, u);
    CHECK(!CGEventSourceKeyState(pid, 100), "key up after posting key up");
    CHECK_INT(CGEventSourceCounterForEventType(pid, kCGEventKeyUp), 1, "key up counter");
    CFRelease(u);
    CFRelease(k);

    // A mouse button
    CGEventRef m = CGEventCreateMouseEvent(priv, kCGEventOtherMouseDown, CGPointMake(1, 2), 4);
    CGEventPost(kCGSessionEventTap, m);
    CHECK(CGEventSourceButtonState(pid, 4), "button 4 down");
    CHECK(!CGEventSourceButtonState(pid, 3), "button 3 is not down");
    CFRelease(m);
    m = CGEventCreateMouseEvent(priv, kCGEventOtherMouseUp, CGPointMake(1, 2), 4);
    CGEventPost(kCGSessionEventTap, m);
    CHECK(!CGEventSourceButtonState(pid, 4), "button 4 up");
    CFRelease(m);

    // The HID state also feeds the combined state
    CGEventRef h = CGEventCreateKeyboardEvent(hid, 38, true);
    CGEventPost(kCGHIDEventTap, h);
    CHECK(CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, 38), "HID key state");
    CHECK(CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, 38), "the combined state follows the HID state");
    CGEventRef hu = CGEventCreateKeyboardEvent(hid, 38, false);
    CGEventPost(kCGHIDEventTap, hu);
    CHECK(!CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, 38), "HID key state after key up");
    CHECK(!CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, 38), "combined key state after key up");
    CFRelease(hu);
    CFRelease(h);

    // A modifier key: down while its flag is set
    CGEventRef shiftDown = CGEventCreateKeyboardEvent(hid, 56, true);
    CGEventPost(kCGHIDEventTap, shiftDown);
    CHECK(CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, 56), "left shift is down");
    CHECK_INT(CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState) & kCGEventFlagMaskShift, kCGEventFlagMaskShift, "shift flag in the state");
    CGEventRef shiftUp = CGEventCreateKeyboardEvent(hid, 56, false);
    CGEventPost(kCGHIDEventTap, shiftUp);
    CHECK(!CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, 56), "left shift is up");
    CHECK_INT(CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState) & kCGEventFlagMaskShift, 0, "shift flag gone");
    CFRelease(shiftDown);
    CFRelease(shiftUp);

    // The state of a source that is gone is not found
    CFRelease(priv);
    CHECK(!CGEventSourceKeyState(pid, 100), "state of a released source");
    CFRelease(hid);
    spin(0.1);
    clearRead();
}

static void test_obsolete_posting_functions(void)
{
    clearRead();
    CGPostMouseEvent(CGPointMake(30, 40), true, 2, true, false);
    CGPostMouseEvent(CGPointMake(30, 40), true, 2, false, false);
    CGPostKeyboardEvent(0, 12, true);
    CGPostScrollWheelEvent(1, 3);
    spinUntilRead(4, 3);
    CHECK_INT(g_readCount, 4, "events of the obsolete functions");
    if (g_readCount == 4)
    {
        CHECK_INT(CGEventGetType(g_read[0]), kCGEventLeftMouseDown, "mouse down");
        CHECK_INT(CGEventGetType(g_read[1]), kCGEventLeftMouseUp, "mouse up");
        CHECK_INT(CGEventGetType(g_read[2]), kCGEventKeyDown, "key down");
        CHECK_INT(CGEventGetType(g_read[3]), kCGEventScrollWheel, "scroll");
        CHECK_INT(CGEventGetIntegerValueField(g_read[3], kCGScrollWheelEventDeltaAxis1), 3, "scroll delta");
        CHECK_INT((int) CGEventGetLocation(g_read[0]).x, 30, "mouse x");
    }
    clearRead();
}

// Event data that is cut short or damaged makes no event (macOS crashes on some of it, so this
// is not in the test that also runs there).
static void test_damaged_event_data(void)
{
    CGEventRef k = CGEventCreateKeyboardEvent(NULL, 7, true);
    UniChar chars[3] = { 'x', 'y', 'z' };

    CGEventKeyboardSetUnicodeString(k, 3, chars);

    CFDataRef data = CGEventCreateData(NULL, k);
    CFIndex length = CFDataGetLength(data);

    for (CFIndex cut = 0; cut < length; cut++)
    {
        CFDataRef part = CFDataCreate(NULL, CFDataGetBytePtr(data), cut);
        CGEventRef e = CGEventCreateFromData(NULL, part);

        if (e != NULL)
        {
            CHECK(0, "data cut to %ld of %ld bytes made an event", (long) cut, (long) length);
            CFRelease(e);
        }
        CFRelease(part);
    }

    CFMutableDataRef longer = CFDataCreateMutableCopy(NULL, 0, data);
    UInt8 extra = 1;
    CFDataAppendBytes(longer, &extra, 1);
    CHECK(CGEventCreateFromData(NULL, longer) == NULL, "data with extra bytes at the end");
    CFRelease(longer);

    CFMutableDataRef wrongVersion = CFDataCreateMutableCopy(NULL, 0, data);
    UInt8* bytes = CFDataGetMutableBytePtr(wrongVersion);
    bytes[4] = 99;
    CHECK(CGEventCreateFromData(NULL, wrongVersion) == NULL, "data of another version");
    CFRelease(wrongVersion);
    CFRelease(data);
    CFRelease(k);
}

// A tap on another thread's run loop that does not answer in time.
static CFRunLoopRef g_tapLoop;
static pthread_mutex_t g_tapLoopLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_tapLoopCond = PTHREAD_COND_INITIALIZER;
static CFMachPortRef g_slowTap;
static TapInfo g_slow = { 'S', SLEEP };

static void* slowTapThread(void* arg)
{
    pthread_mutex_lock(&g_tapLoopLock);
    g_slowTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, keys(), tapCallback, &g_slow);
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

static void test_tap_timeout(void)
{
    pthread_t th;

    pthread_create(&th, NULL, slowTapThread, NULL);
    pthread_mutex_lock(&g_tapLoopLock);
    while (!g_tapLoop)
        pthread_cond_wait(&g_tapLoopCond, &g_tapLoopLock);
    pthread_mutex_unlock(&g_tapLoopLock);
    CHECK(g_slowTap != NULL, "tap on the other thread");

    CGEventRef e = keyDown(12);

    clearRead();
    double start = nowSeconds();
    CGEventPost(kCGHIDEventTap, e);
    spinUntilRead(1, 5);
    double took = nowSeconds() - start;
    CHECK_INT(g_readCount, 1, "the event arrives although the tap does not answer");
    // The tap sleeps 1.6 s; the system stops waiting well before that.
    CHECK(took < 1.55, "the system gave up waiting after %.2f s", took);
    CHECK(took > 0.5, "the system did wait for the tap (%.2f s)", took);
    CHECK(!CGEventTapIsEnabled(g_slowTap), "a tap that timed out is disabled");

    // Once the callback returns it is told that it was disabled.
    double end = nowSeconds() + 4;
    while (g_slow.lastType != kCGEventTapDisabledByTimeout && nowSeconds() < end)
        usleep(20 * 1000);
    CHECK_INT(g_slow.lastType, kCGEventTapDisabledByTimeout, "the tap is told about the timeout");
    CHECK_INT(g_slow.calls, 2, "the tap was called for the event and for the notification");

    // It can be enabled again
    CGEventTapEnable(g_slowTap, true);
    CHECK(CGEventTapIsEnabled(g_slowTap), "enabled again");
    CGEventTapEnable(g_slowTap, false);
    pthread_join(th, NULL);
    removeTap(g_slowTap);
    CFRelease(e);
    clearRead();
}

int main(void)
{
    test_post_reaches_stream();
    test_tap_order();
    test_listen_only_active_drop_modify();
    test_enable_disable_and_list();
    test_tap_post_event();
    test_post_to_pid();
    test_post_from_other_thread_wakes_waiter();
    test_post_updates_source_state();
    test_obsolete_posting_functions();
    test_damaged_event_data();
    test_tap_timeout();
    stopReader();

    if (g_failed)
    {
        printf("%d checks failed\n", g_failed);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
