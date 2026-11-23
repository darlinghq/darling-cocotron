// What CGEventCreateKeyboardEvent, CGEventCreateMouseEvent and CGEventCreateScrollWheelEvent(2) put
// in the events they make, and what the event source adds to them.
//
// Public API only. The expected values come from the documentation where it speaks and from
// black-box observation on macOS 26.7.3 where it does not (the test passes unchanged there).
// Tests named quirk_ pin behaviour that no documentation describes.
//
// Copyright (C) 2026 Lubos Dolezel
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int g_failed;

#define CHECK(cond, ...) do { if (!(cond)) { g_failed++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
#define CHECK_INT(got, want, what) do { long long g_ = (long long)(got), w_ = (long long)(want); \
    if (g_ != w_) { g_failed++; printf("FAIL line %d: %s: got %lld (0x%llx), want %lld (0x%llx)\n", __LINE__, what, g_, g_, w_, w_); } } while (0)
#define CHECK_DBL(got, want, what) do { double g_ = (got), w_ = (want); \
    if (g_ < w_ - 1e-5 || g_ > w_ + 1e-5) { g_failed++; printf("FAIL line %d: %s: got %g, want %g\n", __LINE__, what, g_, w_); } } while (0)

#define F(e, f) CGEventGetIntegerValueField(e, f)

static void test_key_event(void)
{
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, 12, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, 12, false);

    CHECK_INT(CGEventGetType(down), kCGEventKeyDown, "type of a key down event");
    CHECK_INT(CGEventGetType(up), kCGEventKeyUp, "type of a key up event");
    CHECK_INT(F(down, kCGKeyboardEventKeycode), 12, "key code");
    CHECK_INT(F(up, kCGKeyboardEventKeycode), 12, "key code of up");
    CHECK_INT(F(down, kCGKeyboardEventAutorepeat), 0, "autorepeat");
    CHECK_INT(F(down, kCGKeyboardEventKeyboardType), 3, "keyboard type of an event made without a source type");
    CHECK_INT(CGEventGetTimestamp(down), 0, "timestamp of a new event");
    CHECK_INT(F(down, kCGEventSourceUnixProcessID), getpid(), "source process");
    CFRelease(down);
    CFRelease(up);

    CGEventRef big = CGEventCreateKeyboardEvent(NULL, 300, true);
    CHECK_INT(F(big, kCGKeyboardEventKeycode), 300, "key code 300");
    CFRelease(big);
}

static void test_quirk_key_event_default_flags(void)
{
    // QUIRK test, see CGEventCreateKeyboardEvent(): flag bit 0x20000000 and the flags of the key.
    struct { CGKeyCode key; uint64_t down; } cases[] = {
        { 0, 0x20000000 }, { 12, 0x20000000 }, { 49, 0x20000000 },
        { 54, 0x20100010 }, { 55, 0x20100008 }, { 56, 0x20020002 }, { 57, 0x20010000 }, { 58, 0x20080020 },
        { 59, 0x20040001 }, { 60, 0x20020004 }, { 61, 0x20080040 }, { 62, 0x20042000 }, { 63, 0x20800000 },
        { 64, 0x20800000 }, { 65, 0x20200000 }, { 71, 0x20800000 }, { 82, 0x20200000 }, { 96, 0x20800000 },
        { 114, 0x20c00000 }, { 117, 0x20800000 }, { 123, 0x20a00000 }, { 126, 0x20a00000 },
    };

    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++)
    {
        CGEventRef d = CGEventCreateKeyboardEvent(NULL, cases[i].key, true);
        CGEventRef u = CGEventCreateKeyboardEvent(NULL, cases[i].key, false);
        int modifier = cases[i].key >= 54 && cases[i].key <= 63;
        char what[64];

        snprintf(what, sizeof what, "key %d down flags", cases[i].key);
        CHECK_INT(CGEventGetFlags(d), cases[i].down, what);
        snprintf(what, sizeof what, "key %d up flags", cases[i].key);
        CHECK_INT(CGEventGetFlags(u), modifier ? 0x20000000 : cases[i].down, what);
        snprintf(what, sizeof what, "key %d type", cases[i].key);
        CHECK_INT(CGEventGetType(d), modifier ? kCGEventFlagsChanged : kCGEventKeyDown, what);
        CHECK_INT(CGEventGetType(u), modifier ? kCGEventFlagsChanged : kCGEventKeyUp, what);
        CFRelease(d);
        CFRelease(u);
    }
}

static void test_quirk_mouse_event_defaults(void)
{
    CGPoint pt = CGPointMake(100.5, 200.25);
    struct { CGEventType type; CGMouseButton param; int button; int click; } cases[] = {
        { kCGEventLeftMouseDown, kCGMouseButtonLeft, 0, 1 },
        { kCGEventLeftMouseUp, kCGMouseButtonLeft, 0, 0 },
        { kCGEventLeftMouseDragged, kCGMouseButtonLeft, 0, 1 },
        { kCGEventRightMouseDown, kCGMouseButtonLeft, 1, 1 },
        { kCGEventRightMouseUp, kCGMouseButtonCenter, 1, 0 },
        { kCGEventRightMouseDragged, kCGMouseButtonLeft, 1, 1 },
        { kCGEventLeftMouseDown, kCGMouseButtonRight, 0, 1 },
        { kCGEventMouseMoved, kCGMouseButtonCenter, 0, 0 },
        { kCGEventMouseMoved, kCGMouseButtonLeft, 0, 0 },
        { kCGEventOtherMouseDown, 3, 3, 1 },
        { kCGEventOtherMouseDown, kCGMouseButtonCenter, 2, 1 },
        { kCGEventOtherMouseDown, 40, 40, 1 },
        { kCGEventOtherMouseDragged, 4, 4, 1 },
        { kCGEventOtherMouseUp, 5, 5, 0 },
    };

    // The button follows the type unless the type is
    // "other"; click state and pressure start at 1 and 255 for a pressing event, else at 0.
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++)
    {
        CGEventRef e = CGEventCreateMouseEvent(NULL, cases[i].type, pt, cases[i].param);
        char what[80];

        CHECK(e != NULL, "mouse event of type %u made", cases[i].type);
        if (!e)
            continue;
        snprintf(what, sizeof what, "case %u: type", i);
        CHECK_INT(CGEventGetType(e), cases[i].type, what);
        snprintf(what, sizeof what, "case %u: button", i);
        CHECK_INT(F(e, kCGMouseEventButtonNumber), cases[i].button, what);
        snprintf(what, sizeof what, "case %u: click state", i);
        CHECK_INT(F(e, kCGMouseEventClickState), cases[i].click, what);
        snprintf(what, sizeof what, "case %u: pressure", i);
        CHECK_INT(F(e, kCGMouseEventPressure), cases[i].click ? 255 : 0, what);
        CHECK_DBL(CGEventGetDoubleValueField(e, kCGMouseEventPressure), cases[i].click ? 1.0 : 0.0, "pressure as double");
        CHECK_DBL(CGEventGetLocation(e).x, 100.5, "x");
        CHECK_DBL(CGEventGetLocation(e).y, 200.25, "y");
        CHECK_INT(CGEventGetFlags(e), 0, "flags of a mouse event");
        CFRelease(e);
    }

    // The types that are not mouse events make no event.
    CGEventType notMouse[] = { kCGEventNull, 8, 9, kCGEventKeyDown, kCGEventKeyUp, kCGEventFlagsChanged, 13, 14, 15, 20,
        kCGEventScrollWheel, kCGEventTabletPointer, kCGEventTabletProximity, 28, 32 };
    for (unsigned i = 0; i < sizeof notMouse / sizeof notMouse[0]; i++)
    {
        CGEventRef e = CGEventCreateMouseEvent(NULL, notMouse[i], pt, 0);
        CHECK(e == NULL, "type %u is not a mouse event", notMouse[i]);
        if (e)
            CFRelease(e);
    }
}

static void test_scroll_event(void)
{
    CGEventRef e;

    // Lines: the pixel form is derived with the pixels per line of the source (10 by default).
    e = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 2, 5, -3);
    CHECK_INT(CGEventGetType(e), kCGEventScrollWheel, "type");
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis1), 5, "line delta1");
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis2), -3, "line delta2");
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis3), 0, "line delta3");
    CHECK_INT(F(e, kCGScrollWheelEventFixedPtDeltaAxis1), 5 << 16, "fixed1");
    CHECK_INT(F(e, kCGScrollWheelEventFixedPtDeltaAxis2), -3 * 65536, "fixed2");
    CHECK_DBL(CGEventGetDoubleValueField(e, kCGScrollWheelEventFixedPtDeltaAxis1), 5.0, "fixed1 as double");
    CHECK_INT(F(e, kCGScrollWheelEventPointDeltaAxis1), 50, "point1");
    CHECK_INT(F(e, kCGScrollWheelEventPointDeltaAxis2), -30, "point2");
    CHECK_INT(F(e, kCGScrollWheelEventIsContinuous), 0, "lines are not continuous");
    CFRelease(e);

    // Pixels: the line form is the pixel count over the pixels per line, truncated, and at least
    // one line when there is any movement.
    struct { int px; int lines; int64_t fixed; } pixel[] = {
        { 0, 0, 0 }, { 1, 1, 6553 }, { 5, 1, 32768 }, { 9, 1, 58982 }, { 10, 1, 65536 }, { 15, 1, 98304 },
        { 25, 2, 163840 }, { 35, 3, 229376 }, { 95, 9, 622592 }, { 100, 10, 655360 },
        { -1, -1, -6553 }, { -5, -1, -32768 }, { -15, -1, -98304 }, { -25, -2, -163840 },
    };
    for (unsigned i = 0; i < sizeof pixel / sizeof pixel[0]; i++)
    {
        char what[64];

        e = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, pixel[i].px);
        snprintf(what, sizeof what, "%d pixels: lines", pixel[i].px);
        CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis1), pixel[i].lines, what);
        snprintf(what, sizeof what, "%d pixels: fixed point", pixel[i].px);
        CHECK_INT(F(e, kCGScrollWheelEventFixedPtDeltaAxis1), pixel[i].fixed, what);
        snprintf(what, sizeof what, "%d pixels: pixels", pixel[i].px);
        CHECK_INT(F(e, kCGScrollWheelEventPointDeltaAxis1), pixel[i].px, what);
        CHECK_INT(F(e, kCGScrollWheelEventIsContinuous), 1, "pixels are continuous");
        CFRelease(e);
    }

    // Three axes, and the second creator.
    e = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 3, 25, -12, 7);
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis1), 2, "axis1 lines");
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis2), -1, "axis2 lines");
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis3), 1, "axis3 lines (less than one, so one)");
    CHECK_INT(F(e, kCGScrollWheelEventFixedPtDeltaAxis2), -78643, "axis2 fixed");
    CHECK_INT(F(e, kCGScrollWheelEventFixedPtDeltaAxis3), 45875, "axis3 fixed");
    CHECK_INT(F(e, kCGScrollWheelEventPointDeltaAxis3), 7, "axis3 pixels");
    CFRelease(e);
    e = CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitPixel, 2, 25, -12, 99);
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis2), -1, "creator 2 axis2");
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis3), 0, "axes past the count are 0");
    CHECK_INT(F(e, kCGScrollWheelEventPointDeltaAxis2), -12, "creator 2 axis2 pixels");
    CFRelease(e);
    e = CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitLine, 1, 5, 0, 0);
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis1), 5, "creator 2 lines");
    CFRelease(e);

    // The source decides what a line is.
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventSourceSetPixelsPerLine(source, 20);
    CHECK_DBL(CGEventSourceGetPixelsPerLine(source), 20, "pixels per line of the source");
    e = CGEventCreateScrollWheelEvent(source, kCGScrollEventUnitPixel, 1, 25);
    CHECK_INT(F(e, kCGScrollWheelEventDeltaAxis1), 1, "25 pixels of 20 per line");
    CHECK_INT(F(e, kCGScrollWheelEventFixedPtDeltaAxis1), 81920, "25 pixels of 20 per line, fixed");
    CFRelease(e);
    e = CGEventCreateScrollWheelEvent(source, kCGScrollEventUnitLine, 1, 2);
    CHECK_INT(F(e, kCGScrollWheelEventPointDeltaAxis1), 40, "2 lines of 20 pixels");
    CFRelease(e);
    CFRelease(source);

    // No wheel, no event.
    CHECK(CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitLine, 0, 0, 0, 0) == NULL, "wheelCount 0");
}

static void test_source_fields(void)
{
    CGEventSourceRef priv = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventSourceRef priv2 = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventSourceRef hid = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventSourceRef comb = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);

    CHECK_INT(CGEventSourceGetSourceStateID(comb), kCGEventSourceStateCombinedSessionState, "state ID of the combined state");
    CHECK_INT(CGEventSourceGetSourceStateID(hid), kCGEventSourceStateHIDSystemState, "state ID of the HID state");
    // A private source's state ID is a number of its own, which the state functions take.
    int32_t id1 = CGEventSourceGetSourceStateID(priv), id2 = CGEventSourceGetSourceStateID(priv2);
    CHECK(id1 > 1 && id2 > 1 && id1 != id2, "private state IDs %d and %d are distinct and past the fixed ones", id1, id2);

    CGEventRef e = CGEventCreate(priv);
    CHECK_INT(F(e, kCGEventSourceStateID), id1, "state ID field of an event of a private source");
    CFRelease(e);
    e = CGEventCreate(hid);
    CHECK_INT(F(e, kCGEventSourceStateID), 1, "state ID field of an event of the HID state");
    CFRelease(e);
    e = CGEventCreate(comb);
    CHECK_INT(F(e, kCGEventSourceStateID), 0, "state ID field of an event of the combined state");
    CFRelease(e);
    e = CGEventCreate(NULL);
    CHECK_INT(F(e, kCGEventSourceStateID), 0, "state ID field of an event without a source");

    // User data and keyboard type are taken when the event is made, not followed afterwards.
    CGEventSourceSetUserData(priv, 0x1234567890LL);
    CHECK_INT(CGEventSourceGetUserData(priv), 0x1234567890LL, "user data of the source");
    CGEventRef k = CGEventCreateKeyboardEvent(priv, 5, true);
    CHECK_INT(F(k, kCGEventSourceUserData), 0x1234567890LL, "user data of the event");
    CGEventSourceSetUserData(priv, 99);
    CHECK_INT(F(k, kCGEventSourceUserData), 0x1234567890LL, "the event keeps the user data it was made with");
    CGEventSourceSetKeyboardType(priv, 7);
    CGEventRef k2 = CGEventCreateKeyboardEvent(priv, 5, true);
    CHECK_INT(F(k2, kCGKeyboardEventKeyboardType), 7, "keyboard type of the event of a source that has one");
    CHECK_INT(F(k, kCGKeyboardEventKeyboardType), 3, "an event made before keeps its keyboard type");
    // QUIRK test, see -[CGEventSource keyboardType]: asking for the type gives the keyboard type of
    // the system (40) and makes it the type of the events the source makes from then on.
    CHECK_INT(CGEventSourceGetKeyboardType(priv), 40, "keyboard type of the source");
    CGEventRef k3 = CGEventCreateKeyboardEvent(priv, 5, true);
    CHECK_INT(F(k3, kCGKeyboardEventKeyboardType), 40, "the event after asking for the type");
    CGEventSourceSetKeyboardType(priv, 9);
    CGEventRef k4 = CGEventCreateKeyboardEvent(priv, 5, true);
    CHECK_INT(F(k4, kCGKeyboardEventKeyboardType), 9, "the event after setting the type again");
    CFRelease(k3);
    CFRelease(k4);

    // CGEventSetSource takes the state ID and user data of the source.
    CGEventSetSource(e, priv);
    CHECK_INT(F(e, kCGEventSourceUserData), 99, "user data after CGEventSetSource");
    CHECK_INT(F(e, kCGEventSourceStateID), id1, "state ID after CGEventSetSource");
    CGEventSourceRef fromEvent = CGEventCreateSourceFromEvent(e);
    CHECK(fromEvent != NULL, "source of an event");
    if (fromEvent)
    {
        CHECK_INT(CGEventSourceGetSourceStateID(fromEvent), id1, "state ID of the source of the event");
        CHECK_INT(CGEventSourceGetUserData(fromEvent), 99, "user data of the source of the event");
        CFRelease(fromEvent);
    }
    CFRelease(k2);
    CFRelease(k);
    CFRelease(e);

    // The settings of a source.
    CHECK_DBL(CGEventSourceGetPixelsPerLine(comb), 10, "default pixels per line");
    CHECK_DBL(CGEventSourceGetLocalEventsSuppressionInterval(hid), 0.25, "default suppression interval");
    CGEventSourceSetLocalEventsSuppressionInterval(hid, 0.5);
    CHECK_DBL(CGEventSourceGetLocalEventsSuppressionInterval(hid), 0.5, "suppression interval set");
    CHECK_INT(CGEventSourceGetLocalEventsFilterDuringSuppressionState(hid, kCGEventSuppressionStateRemoteMouseDrag), 0, "default filter");
    CGEventSourceSetLocalEventsFilterDuringSuppressionState(hid, 5, kCGEventSuppressionStateRemoteMouseDrag);
    CHECK_INT(CGEventSourceGetLocalEventsFilterDuringSuppressionState(hid, kCGEventSuppressionStateRemoteMouseDrag), 5, "filter set");
    CHECK_INT(CGEventSourceGetLocalEventsFilterDuringSuppressionState(hid, kCGEventSuppressionStateSuppressionInterval), 0, "other filter untouched");

    // The state of a private source that has not had an event: nothing is down.
    CHECK(!CGEventSourceKeyState(id1, 12), "key state of a fresh private source");
    CHECK(!CGEventSourceButtonState(id1, 0), "button state of a fresh private source");
    CHECK_INT(CGEventSourceFlagsState(id1), 0, "flags state of a fresh private source");
    CHECK_INT(CGEventSourceCounterForEventType(id1, kCGEventKeyDown), 0, "counter of a fresh private source");
    CHECK_INT(CGEventSourceCounterForEventType(id1, kCGAnyInputEventType), 0, "any counter of a fresh private source");
    CFRelease(priv);
    CFRelease(priv2);
    CFRelease(hid);
    CFRelease(comb);
}

int main(void)
{
    test_key_event();
    test_quirk_key_event_default_flags();
    test_quirk_mouse_event_defaults();
    test_scroll_event();
    test_source_fields();

    if (g_failed)
    {
        printf("%d checks failed\n", g_failed);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
