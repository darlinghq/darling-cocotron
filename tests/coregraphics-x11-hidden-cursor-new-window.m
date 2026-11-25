// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A window made while the cursor is hidden shows the blank cursor like the windows that were there when it was
// hidden: CGDisplayHideCursor() hides the cursor over every window of the process, also over one made later,
// and CGDisplayShowCursor() undoes it for all of them. A process without AppKit, on X11. Driven by
// coregraphics-x11-hidden-cursor-new-window.sh (XTest, XFixes: the cursor image under the pointer): the program
// makes a window, hides the cursor, makes a second window, prints "READY <window> <window>" with the X window ids
// and takes its commands from the keys that come up in its first window (the tap sees them):
//   s show (one undo of the hide), h hide
//   n make a window while the cursor is hidden, print "NEW <window>"
//   q quit
// Usage: coregraphics-x11-hidden-cursor-new-window (no arguments)
// The verdict is the driver's (PASS or FAIL lines, then ALL PASSED or FAILED n); the program prints DONE at the end.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdio.h>

typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);
extern void *_CGSNativeDisplay(CGSConnectionID cid);
extern boolean_t CGCursorIsVisible(void);

static BOOL quit;
static CGSConnectionID cid;
static int windowsMade;

static unsigned long makeWindow(void) {
    CGRect frame = CGRectMake(100 + 450 * windowsMade, 100 + 20 * windowsMade, 400, 300);
    RegionRef region = NULL;
    CGSWindowID wid = 0;
    if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess ||
        CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess)
        return 0;
    windowsMade++;
    return (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, wid);
}

static void command(UniChar c) {
    switch (c) {
    case 's':
        CGDisplayShowCursor(kCGDirectMainDisplay);
        break;
    case 'h':
        CGDisplayHideCursor(kCGDirectMainDisplay);
        break;
    case 'n':
        printf("NEW %lu\n", makeWindow());
        break;
    case 'q':
        quit = YES;
        break;
    }
    fflush(stdout);
}

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventKeyUp) {
        UniChar c = 0;
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 1, &length, &c);
        if (length == 1)
            command(c);
    }
    return event;
}

int main(void) {
    @autoreleasepool {
        cid = CGSMainConnectionID();
        if (cid == 0 || _CGSNativeDisplay(cid) == NULL) {
            printf("FAIL no connection to the window system\n");
            return 1;
        }
        unsigned long first = makeWindow();
        CGDisplayHideCursor(kCGDirectMainDisplay);
        unsigned long second = makeWindow();
        if (first == 0 || second == 0 || CGCursorIsVisible()) {
            printf("FAIL no windows, or the cursor is not hidden\n");
            return 1;
        }

        CGEventMask mask = CGEventMaskBit(kCGEventKeyUp);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        printf("READY %lu %lu\n", first, second);
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 60];
        while (!quit && [deadline timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        CGDisplayShowCursor(kCGDirectMainDisplay);
        printf("DONE\n");
    }
    return 0;
}
