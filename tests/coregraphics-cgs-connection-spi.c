/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

// Connection properties, connection notifications, window rects and captures
// of the main connection, and the IOHIDEvent of created events.
// Expected values were observed on macOS 26.7.3 (x86_64) with the same calls:
// - a property that was never set reads as NULL; one that was set reads back;
//   setting NULL removes it. Another owner, or a connection that does not
//   exist, gives kCGErrorFailure.
// - registering a connection notify proc and enabling occlusion and window
//   modification notifications succeed.
// - a window that does not exist has no rect: kCGErrorFailure and the null rect.
// - capturing a window that does not exist, or no window, gives NULL.
// - created events have no IOHIDEvent.
// Needs a window system connection (X11 or Wayland).

typedef unsigned ConnectionID, WindowID;
typedef void (*NotifyProc)(unsigned type, void *data, unsigned length, void *arg, ConnectionID cid);

extern ConnectionID CGSMainConnectionID(void);
extern CGError CGSSetConnectionProperty(ConnectionID, ConnectionID, CFStringRef, CFTypeRef);
extern CGError CGSCopyConnectionProperty(ConnectionID, ConnectionID, CFStringRef, CFTypeRef *);
extern CGError CGSRegisterConnectionNotifyProc(ConnectionID, NotifyProc, unsigned, void *);
extern CGError CGSPackagesEnableConnectionOcclusionNotifications(ConnectionID, bool, bool *);
extern CGError CGSPackagesEnableConnectionWindowModificationNotifications(ConnectionID, bool, bool *);
extern CGError CGSGetScreenRectForWindow(ConnectionID, WindowID, CGRect *);
extern CFArrayRef CGSHWCaptureWindowList(ConnectionID, WindowID *, unsigned, unsigned);
extern CFTypeRef CGEventCopyIOHIDEvent(CGEventRef);

static int failures;

static void report(const char *name, int ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

static void notified(unsigned type, void *data, unsigned length, void *arg, ConnectionID cid)
{
}

int main(void)
{
    ConnectionID cid = CGSMainConnectionID();
    if (cid == 0) {
        printf("SKIP: no window system connection\n");
        return 0;
    }
    CFStringRef key = CFSTR("com.example.connection-property-test");

    CFTypeRef value = (CFTypeRef) 1;
    report("unset property reads as NULL", CGSCopyConnectionProperty(cid, cid, key, &value) == kCGErrorSuccess && value == NULL);
    report("set", CGSSetConnectionProperty(cid, cid, key, CFSTR("hello")) == kCGErrorSuccess);
    value = NULL;
    report("set property reads back", CGSCopyConnectionProperty(cid, cid, key, &value) == kCGErrorSuccess
           && value != NULL && CFEqual(value, CFSTR("hello")));
    if (value != NULL)
        CFRelease(value);
    CGSSetConnectionProperty(cid, cid, key, NULL);
    value = (CFTypeRef) 1;
    report("setting NULL removes", CGSCopyConnectionProperty(cid, cid, key, &value) == kCGErrorSuccess && value == NULL);
    report("another owner", CGSSetConnectionProperty(cid, cid + 12345, key, kCFBooleanTrue) == kCGErrorFailure);
    report("no such connection", CGSCopyConnectionProperty(cid + 12345, cid + 12345, key, &value) == kCGErrorFailure);

    report("register connection notify proc", CGSRegisterConnectionNotifyProc(cid, notified, 1500, NULL) == kCGErrorSuccess);
    bool state;
    report("occlusion notifications", CGSPackagesEnableConnectionOcclusionNotifications(cid, true, &state) == kCGErrorSuccess
           && CGSPackagesEnableConnectionOcclusionNotifications(cid, true, NULL) == kCGErrorSuccess);
    report("window modification notifications", CGSPackagesEnableConnectionWindowModificationNotifications(cid, true, &state) == kCGErrorSuccess);

    CGRect rect = CGRectMake(9, 9, 9, 9);
    report("no such window: no rect", CGSGetScreenRectForWindow(cid, 999999, &rect) == kCGErrorFailure && CGRectIsNull(rect));

    WindowID wid = 999999;
    report("capture: no such window", CGSHWCaptureWindowList(cid, &wid, 1, 0) == NULL);
    report("capture: no window", CGSHWCaptureWindowList(cid, NULL, 0, 0) == NULL);

    CGEventRef mouse = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(1, 1), kCGMouseButtonLeft);
    CGEventRef scroll = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, 5);
    report("created events: no IOHIDEvent", CGEventCopyIOHIDEvent(mouse) == NULL && CGEventCopyIOHIDEvent(scroll) == NULL);
    CFRelease(mouse);
    CFRelease(scroll);

    return failures != 0;
}
