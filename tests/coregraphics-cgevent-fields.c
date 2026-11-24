// CGEvent fields, flags, location, timestamp, the Unicode string, copies and CGEventCreateData.
//
// Public API only; the expected values are what the documentation says and, where it is silent,
// what macOS 26.7.3 does (black box; the test passes unchanged there). Tests whose name starts
// with quirk_ pin behaviour that no documentation describes.
//
// Copyright (C) 2026 Lubos Dolezel
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

static int g_failed;

#define CHECK(cond, ...) do { if (!(cond)) { g_failed++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
#define CHECK_INT(got, want, what) do { long long g_ = (long long)(got), w_ = (long long)(want); \
    if (g_ != w_) { g_failed++; printf("FAIL line %d: %s: got %lld, want %lld\n", __LINE__, what, g_, w_); } } while (0)
#define CHECK_DBL(got, want, what) do { double g_ = (got), w_ = (want); \
    if (g_ < w_ - 1e-5 || g_ > w_ + 1e-5) { g_failed++; printf("FAIL line %d: %s: got %g, want %g\n", __LINE__, what, g_, w_); } } while (0)

static CGEventRef newMouse(CGEventType type)
{
    return CGEventCreateMouseEvent(NULL, type, CGPointMake(10, 20), kCGMouseButtonLeft);
}

static void test_field_defaults_and_ranges(void)
{
    CGEventRef e = CGEventCreate(NULL);

    CHECK_INT(CGEventGetType(e), kCGEventNull, "type of CGEventCreate");
    CHECK_INT(CGEventGetFlags(e), 0, "flags of CGEventCreate");
    CHECK_INT(CGEventGetTimestamp(e), 0, "timestamp of a new event");
    CHECK_INT(CGEventGetIntegerValueField(e, kCGEventSourceUnixProcessID), getpid(), "source pid");
    CHECK_INT(CGEventGetIntegerValueField(e, kCGEventSourceUserID), getuid(), "source user id");
    // Fields of events of another kind do not exist on this one.
    CGEventSetIntegerValueField(e, kCGKeyboardEventKeycode, 5);
    CHECK_INT(CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode), 0, "keycode of a null event");
    // No field outside the array.
    CGEventSetIntegerValueField(e, 100000, 5);
    CHECK_INT(CGEventGetIntegerValueField(e, 100000), 0, "field 100000");
    CGEventSetIntegerValueField(e, 0xFFFFFFFF, 5);
    CHECK_INT(CGEventGetIntegerValueField(e, 0xFFFFFFFF), 0, "field -1");
    // The fields that every event has.
    CGEventSetIntegerValueField(e, kCGEventSourceUserData, 0x123456789ALL);
    CHECK_INT(CGEventGetIntegerValueField(e, kCGEventSourceUserData), 0x123456789ALL, "user data field keeps 64 bits");
    CGEventSetIntegerValueField(e, kCGEventTargetUnixProcessID, -1);
    CHECK_INT(CGEventGetIntegerValueField(e, kCGEventTargetUnixProcessID), -1, "target pid");
    CGEventSetIntegerValueField(e, kCGEventTargetProcessSerialNumber, 1234567890123LL);
    CHECK_INT(CGEventGetIntegerValueField(e, kCGEventTargetProcessSerialNumber), 1234567890123LL, "target psn");
    CFRelease(e);
}

static void test_mouse_fields(void)
{
    CGEventRef e = newMouse(kCGEventMouseMoved);
    int fields[] = { kCGMouseEventNumber, kCGMouseEventClickState, kCGMouseEventButtonNumber, kCGMouseEventDeltaX,
        kCGMouseEventDeltaY, kCGMouseEventSubtype, kCGMouseEventWindowUnderMousePointer,
        kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, kCGEventUnacceleratedPointerMovementX,
        kCGEventUnacceleratedPointerMovementY };

    for (unsigned i = 0; i < sizeof fields / sizeof fields[0]; i++)
    {
        CGEventSetIntegerValueField(e, fields[i], 9);
        CHECK_INT(CGEventGetIntegerValueField(e, fields[i]), 9, "mouse field integer round trip");
        CGEventSetDoubleValueField(e, fields[i], 2.75);
        CHECK_INT(CGEventGetIntegerValueField(e, fields[i]), 2, "mouse field double stored as integer, truncated");
        CHECK_DBL(CGEventGetDoubleValueField(e, fields[i]), 2, "mouse field double read");
    }

    // The pressure is a byte in the integer view and 0..1 in the double view.
    CGEventSetDoubleValueField(e, kCGMouseEventPressure, 0.5);
    CHECK_INT(CGEventGetIntegerValueField(e, kCGMouseEventPressure), 127, "pressure 0.5 as integer");
    CHECK_DBL(CGEventGetDoubleValueField(e, kCGMouseEventPressure), 127 / 255.0, "pressure 0.5 as double");
    CGEventSetIntegerValueField(e, kCGMouseEventPressure, 100);
    CHECK_DBL(CGEventGetDoubleValueField(e, kCGMouseEventPressure), 100 / 255.0, "pressure 100 as double");
    // Not a mouse field of a key event.
    CGEventRef k = CGEventCreateKeyboardEvent(NULL, 3, true);
    CGEventSetIntegerValueField(k, kCGMouseEventClickState, 4);
    CHECK_INT(CGEventGetIntegerValueField(k, kCGMouseEventClickState), 0, "click state of a key event");
    CFRelease(k);
    CFRelease(e);
}

static void test_key_fields(void)
{
    CGEventRef k = CGEventCreateKeyboardEvent(NULL, 3, true);

    CGEventSetIntegerValueField(k, kCGKeyboardEventAutorepeat, 1);
    CGEventSetIntegerValueField(k, kCGKeyboardEventKeycode, 99);
    CGEventSetIntegerValueField(k, kCGKeyboardEventKeyboardType, 41);
    CHECK_INT(CGEventGetIntegerValueField(k, kCGKeyboardEventAutorepeat), 1, "autorepeat");
    CHECK_INT(CGEventGetIntegerValueField(k, kCGKeyboardEventKeycode), 99, "keycode");
    CHECK_INT(CGEventGetIntegerValueField(k, kCGKeyboardEventKeyboardType), 41, "keyboard type");
    // A key code is 16 bits.
    CGEventSetIntegerValueField(k, kCGKeyboardEventKeycode, 70000);
    CHECK_INT(CGEventGetIntegerValueField(k, kCGKeyboardEventKeycode), 70000 - 65536, "keycode of 70000");
    CFRelease(k);
}

static void test_scroll_fields(void)
{
    CGEventRef s = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 3, 0, 0, 0);

#define CHECK_AXES(d1, d2, d3, f1, f2, f3, p1, p2, p3, label) do { \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventDeltaAxis1), d1, label " delta1"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventDeltaAxis2), d2, label " delta2"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventDeltaAxis3), d3, label " delta3"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventFixedPtDeltaAxis1), f1, label " fixed1"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventFixedPtDeltaAxis2), f2, label " fixed2"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventFixedPtDeltaAxis3), f3, label " fixed3"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventPointDeltaAxis1), p1, label " point1"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventPointDeltaAxis2), p2, label " point2"); \
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventPointDeltaAxis3), p3, label " point3"); } while (0)

    CHECK_AXES(0, 0, 0, 0, 0, 0, 0, 0, 0, "new");
    // A whole line delta set by the application also sets the other forms of it.
    CGEventSetIntegerValueField(s, kCGScrollWheelEventDeltaAxis2, 3);
    CHECK_AXES(0, 3, 0, 0, 196608, 0, 0, 24, 0, "set delta2=3");
    CGEventSetIntegerValueField(s, kCGScrollWheelEventDeltaAxis3, -2);
    CHECK_AXES(0, 3, -2, 0, 196608, -131072, 0, 24, -16, "set delta3=-2");
    // The fixed point and the pixel forms are independent of the others.
    CGEventSetIntegerValueField(s, kCGScrollWheelEventFixedPtDeltaAxis2, 5 << 16);
    CHECK_AXES(0, 3, -2, 0, 327680, -131072, 0, 24, -16, "set fixed2=5<<16");
    CGEventSetIntegerValueField(s, kCGScrollWheelEventPointDeltaAxis2, 40);
    CHECK_AXES(0, 3, -2, 0, 327680, -131072, 0, 40, -16, "set point2=40");
    CGEventSetDoubleValueField(s, kCGScrollWheelEventFixedPtDeltaAxis2, 1.5);
    CHECK_AXES(0, 3, -2, 0, 98304, -131072, 0, 40, -16, "set fixed2 double 1.5");
    CGEventSetDoubleValueField(s, kCGScrollWheelEventFixedPtDeltaAxis3, -4.25);
    CHECK_AXES(0, 3, -2, 0, 98304, -278528, 0, 40, -16, "set fixed3 double -4.25");
    CHECK_DBL(CGEventGetDoubleValueField(s, kCGScrollWheelEventFixedPtDeltaAxis3), -4.25, "fixed3 as double");
    CGEventSetDoubleValueField(s, kCGScrollWheelEventPointDeltaAxis3, 33.9);
    CHECK_AXES(0, 3, -2, 0, 98304, -278528, 0, 40, 33, "set point3 double 33.9");
    // A double line delta is truncated, then the same as an integer one.
    CGEventSetDoubleValueField(s, kCGScrollWheelEventDeltaAxis2, -6.5);
    CHECK_AXES(0, -6, -2, 0, -393216, -278528, 0, -48, 33, "set delta2 double -6.5");

    // The flags that tell what kind of scrolling it is.
    CGEventSetIntegerValueField(s, kCGScrollWheelEventIsContinuous, 77);
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventIsContinuous), 1, "is continuous is a flag");
    CGEventSetIntegerValueField(s, kCGScrollWheelEventScrollPhase, kCGScrollPhaseEnded);
    CGEventSetIntegerValueField(s, kCGScrollWheelEventScrollCount, 2);
    CGEventSetIntegerValueField(s, kCGScrollWheelEventMomentumPhase, kCGMomentumScrollPhaseEnd);
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventScrollPhase), kCGScrollPhaseEnded, "scroll phase");
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventScrollCount), 2, "scroll count");
    CHECK_INT(CGEventGetIntegerValueField(s, kCGScrollWheelEventMomentumPhase), kCGMomentumScrollPhaseEnd, "momentum phase");
    CFRelease(s);
}

static void test_tablet_fields(void)
{
    CGEventRef t = CGEventCreate(NULL);

    CGEventSetType(t, kCGEventTabletPointer);
    CGEventSetDoubleValueField(t, kCGTabletEventPointPressure, 0.5);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletEventPointPressure), 32767, "tablet pressure 0.5");
    CGEventSetIntegerValueField(t, kCGTabletEventPointPressure, 1000);
    CHECK_DBL(CGEventGetDoubleValueField(t, kCGTabletEventPointPressure), 1000 / 65535.0, "tablet pressure 1000");
    CGEventSetDoubleValueField(t, kCGTabletEventTiltX, -0.25);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletEventTiltX), -8191, "tilt x -0.25");
    CGEventSetDoubleValueField(t, kCGTabletEventTiltY, 0.5);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletEventTiltY), 16383, "tilt y 0.5");
    CGEventSetDoubleValueField(t, kCGTabletEventTangentialPressure, 0.5);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletEventTangentialPressure), 16383, "tangential pressure 0.5");
    CGEventSetDoubleValueField(t, kCGTabletEventRotation, 0.5);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletEventRotation), 32, "rotation 0.5");
    CGEventSetDoubleValueField(t, kCGTabletEventRotation, -0.25);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletEventRotation), 65520, "rotation -0.25 wraps to 16 bits");
    CGEventSetIntegerValueField(t, kCGTabletEventDeviceID, 12);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletEventDeviceID), 12, "device id");
    // The proximity fields are not those of a pointer event.
    CGEventSetIntegerValueField(t, kCGTabletProximityEventVendorID, 12);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletProximityEventVendorID), 0, "vendor id of a pointer event");
    CGEventSetType(t, kCGEventTabletProximity);
    CGEventSetIntegerValueField(t, kCGTabletProximityEventVendorID, 12);
    CHECK_INT(CGEventGetIntegerValueField(t, kCGTabletProximityEventVendorID), 12, "vendor id of a proximity event");
    CFRelease(t);
}

static void test_set_type_changes_kind(void)
{
    CGEventRef k = CGEventCreateKeyboardEvent(NULL, 5, true);

    CGEventSetType(k, kCGEventKeyUp);
    CHECK_INT(CGEventGetIntegerValueField(k, kCGKeyboardEventKeycode), 5, "keycode kept by a change within the kind");
    CGEventSetType(k, kCGEventScrollWheel);
    CHECK_INT(CGEventGetType(k), kCGEventScrollWheel, "type after SetType");
    CHECK_INT(CGEventGetIntegerValueField(k, kCGKeyboardEventKeycode), 0, "keycode of a scroll event");
    CGEventSetType(k, kCGEventKeyDown);
    CGEventSetType(k, 77);
    CHECK_INT(CGEventGetType(k), 77, "an unknown type is kept");
    CGEventSetType(k, kCGEventTapDisabledByTimeout);
    CHECK_INT(CGEventGetType(k), kCGEventTapDisabledByTimeout, "tap disabled type is kept");
    CFRelease(k);

    // Fields of the same kind stay across mouse button changes
    CGEventRef m = newMouse(kCGEventLeftMouseDown);
    CGEventSetType(m, kCGEventLeftMouseUp);
    CHECK_INT(CGEventGetIntegerValueField(m, kCGMouseEventClickState), 1, "click state kept by down to up");
    CFRelease(m);
}

static void test_quirk_flags_keep_32_bits(void)
{
    // QUIRK test: see CGEventSetFlags(). Only the low 32 bits of the flags are kept.
    CGEventRef e = CGEventCreate(NULL);

    CGEventSetFlags(e, kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
    CHECK_INT(CGEventGetFlags(e), kCGEventFlagMaskShift | kCGEventFlagMaskCommand, "flags round trip");
    CGEventSetFlags(e, 0x1234567890ULL);
    CHECK_INT(CGEventGetFlags(e), 0x34567890ULL, "flags above 32 bits");
    CGEventSetFlags(e, ~0ULL);
    CHECK_INT(CGEventGetFlags(e), 0xFFFFFFFFULL, "all flags");
    CFRelease(e);
}

static void test_location_and_timestamp(void)
{
    CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(100.5, 200.25), kCGMouseButtonLeft);
    CGPoint p = CGEventGetLocation(e);

    CHECK_DBL(p.x, 100.5, "x");
    CHECK_DBL(p.y, 200.25, "y");
    CGEventSetLocation(e, CGPointMake(-5, 1e6));
    p = CGEventGetLocation(e);
    CHECK_DBL(p.x, -5, "x set");
    CHECK_DBL(p.y, 1e6, "y set");
    CGEventSetTimestamp(e, 123456789012ULL);
    CHECK_INT(CGEventGetTimestamp(e), 123456789012ULL, "timestamp");
    CFRelease(e);
}

static void test_unicode_string(void)
{
    UniChar src[70000];
    UniChar out[70000];
    UniCharCount n;
    int lengths[] = { 1, 5, 6, 20, 39, 40, 41, 100, 1000, 4096, 65535 };
    CGEventRef k = CGEventCreateKeyboardEvent(NULL, 0, true);

    for (int i = 0; i < 70000; i++)
        src[i] = 'A' + i % 26;

    for (unsigned i = 0; i < sizeof lengths / sizeof lengths[0]; i++)
    {
        CGEventKeyboardSetUnicodeString(k, lengths[i], src);
        memset(out, 0, sizeof out);
        n = 777;
        CGEventKeyboardGetUnicodeString(k, 70000, &n, out);
        CHECK_INT(n, lengths[i], "length of a string");
        CHECK(memcmp(out, src, lengths[i] * sizeof(UniChar)) == 0, "string of %d characters differs", lengths[i]);
    }

    CGEventKeyboardSetUnicodeString(k, 3, src);
    n = 777;
    CGEventKeyboardGetUnicodeString(k, 0, &n, NULL);
    CHECK_INT(n, 3, "length asked for with no room");
    memset(out, 0, sizeof out);
    n = 777;
    CGEventKeyboardGetUnicodeString(k, 2, &n, out);
    CHECK_INT(n, 2, "length with room for 2");
    CHECK(out[0] == 'A' && out[1] == 'B' && out[2] == 0, "only 2 characters are copied");

    CGEventKeyboardSetUnicodeString(k, 0, src);
    n = 777;
    CGEventKeyboardGetUnicodeString(k, 100, &n, out);
    CHECK_INT(n, 0, "length after setting an empty string");

    UniChar withNul[4] = { 'a', 0, 'b', 'c' };
    CGEventKeyboardSetUnicodeString(k, 4, withNul);
    n = 777;
    memset(out, 0, sizeof out);
    CGEventKeyboardGetUnicodeString(k, 100, &n, out);
    CHECK_INT(n, 4, "a string with a NUL inside");
    CHECK(out[2] == 'b', "characters after the NUL");
    CFRelease(k);

    // The string belongs to any event.
    CGEventRef m = newMouse(kCGEventLeftMouseDown);
    CGEventKeyboardSetUnicodeString(m, 3, src);
    n = 777;
    CGEventKeyboardGetUnicodeString(m, 100, &n, out);
    CHECK_INT(n, 3, "string of a mouse event");
    CFRelease(m);
}

static void test_copy_is_independent(void)
{
    CGEventRef k = CGEventCreateKeyboardEvent(NULL, 7, true);
    UniChar chars[3] = { 'x', 'y', 'z' };

    CGEventKeyboardSetUnicodeString(k, 3, chars);
    CGEventSetTimestamp(k, 55);
    CGEventSetLocation(k, CGPointMake(3, 4));

    CGEventRef c = CGEventCreateCopy(k);

    CGEventSetIntegerValueField(c, kCGKeyboardEventKeycode, 100);
    chars[0] = 'q';
    CGEventKeyboardSetUnicodeString(c, 1, chars);
    CGEventSetFlags(c, kCGEventFlagMaskShift);

    CHECK_INT(CGEventGetIntegerValueField(k, kCGKeyboardEventKeycode), 7, "original keycode after changing the copy");
    CHECK_INT(CGEventGetIntegerValueField(c, kCGKeyboardEventKeycode), 100, "copy keycode");
    CHECK_INT(CGEventGetTimestamp(c), 55, "copy timestamp");
    CGPoint p = CGEventGetLocation(c);
    CHECK_DBL(p.x, 3, "copy location x");
    UniCharCount n = 0;
    UniChar out[8];
    CGEventKeyboardGetUnicodeString(k, 8, &n, out);
    CHECK_INT(n, 3, "original string length");
    CHECK(out[0] == 'x', "original string");
    CFRelease(c);
    CFRelease(k);
}

static void test_data_round_trip(void)
{
    CGEventSourceRef priv = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventRef e = CGEventCreateMouseEvent(priv, kCGEventOtherMouseDown, CGPointMake(12.5, 34.25), 4);

    CGEventSetFlags(e, kCGEventFlagMaskCommand);
    CGEventSetTimestamp(e, 987654321);
    CGEventSetIntegerValueField(e, kCGMouseEventClickState, 3);
    CGEventSetIntegerValueField(e, kCGMouseEventDeltaX, -7);
    CGEventSetIntegerValueField(e, kCGEventSourceUserData, 0x1122334455667788LL);

    CFDataRef data = CGEventCreateData(NULL, e);

    CHECK(data != NULL, "CGEventCreateData");
    CGEventRef r = data ? CGEventCreateFromData(NULL, data) : NULL;
    CHECK(r != NULL, "CGEventCreateFromData");
    if (r)
    {
        CGPoint p = CGEventGetLocation(r);

        CHECK_INT(CGEventGetType(r), kCGEventOtherMouseDown, "type");
        CHECK_INT(CGEventGetFlags(r), kCGEventFlagMaskCommand, "flags");
        CHECK_INT(CGEventGetTimestamp(r), 987654321, "timestamp");
        CHECK_DBL(p.x, 12.5, "x");
        CHECK_DBL(p.y, 34.25, "y");
        CHECK_INT(CGEventGetIntegerValueField(r, kCGMouseEventButtonNumber), 4, "button");
        CHECK_INT(CGEventGetIntegerValueField(r, kCGMouseEventClickState), 3, "click state");
        CHECK_INT(CGEventGetIntegerValueField(r, kCGMouseEventDeltaX), -7, "delta x");
        CHECK_INT(CGEventGetIntegerValueField(r, kCGMouseEventPressure), 255, "pressure");
        // QUIRK test, see CGEventCreateData(): what names the source is not in the data.
        CHECK_INT(CGEventGetIntegerValueField(r, kCGEventSourceUserData), 0, "user data is not in the data");
        CHECK_INT(CGEventGetIntegerValueField(r, kCGEventSourceStateID), 0, "state ID is not in the data");
        CGEventSourceRef src = CGEventCreateSourceFromEvent(r);
        CHECK(src != NULL, "source of an event made from data");
        if (src)
            CFRelease(src);
        CFRelease(r);
    }

    // A keyboard event with a string.
    CGEventRef k = CGEventCreateKeyboardEvent(NULL, 7, true);
    UniChar chars[3] = { 'x', 'y', 'z' };
    CGEventKeyboardSetUnicodeString(k, 3, chars);
    CFDataRef kdata = CGEventCreateData(NULL, k);
    CGEventRef kr = CGEventCreateFromData(NULL, kdata);
    UniChar out[8];
    UniCharCount n = 0;
    CHECK(kr != NULL, "key event from data");
    if (kr)
    {
        CGEventKeyboardGetUnicodeString(kr, 8, &n, out);
        CHECK_INT(n, 3, "string length after the round trip");
        CHECK(out[0] == 'x' && out[2] == 'z', "string after the round trip");
        CHECK_INT(CGEventGetIntegerValueField(kr, kCGKeyboardEventKeycode), 7, "keycode after the round trip");
        CHECK_INT(CGEventGetFlags(kr), CGEventGetFlags(k), "key event flags after the round trip");
        CFRelease(kr);
    }

    // Data that is not an event.
    CFDataRef junk = CFDataCreate(NULL, (const UInt8*) "hello world, this is not an event", 33);
    CHECK(CGEventCreateFromData(NULL, junk) == NULL, "junk data");
    CFRelease(junk);
    if (kdata)
        CFRelease(kdata);
    if (data)
        CFRelease(data);
    CFRelease(k);
    CFRelease(e);
    CFRelease(priv);
}

int main(void)
{
    test_field_defaults_and_ranges();
    test_mouse_fields();
    test_key_fields();
    test_scroll_fields();
    test_tablet_fields();
    test_set_type_changes_kind();
    test_quirk_flags_keep_32_bits();
    test_location_and_timestamp();
    test_unicode_string();
    test_copy_is_independent();
    test_data_round_trip();

    if (g_failed)
    {
        printf("%d checks failed\n", g_failed);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
