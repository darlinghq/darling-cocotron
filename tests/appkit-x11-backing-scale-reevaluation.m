// Copyright (C) 2026 Lubos Dolezel
// X11: when RandR reports a layout change, the backend reads the backing scale
// again (the user's X11BackingScale default, else GDK_SCALE). If the value
// changed, the screens and windows report the new scale, a window keeps its
// size in points, and NSWindowDidChangeBackingPropertiesNotification is posted
// with the previous scale. A layout change that leaves the scale alone posts
// nothing. Run through tests/appkit-x11-backing-scale-reevaluation.sh, which
// performs the RandR changes this program asks for with READY1/READY2 lines.
// Needs an X server with RandR (Xvfb :99 +extension RANDR), GDK_SCALE unset.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
static int notifications;
static CGFloat notifiedOldScale;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static void setScalePreference(int scale) {
    CFNumberRef value = scale ? CFNumberCreate(NULL, kCFNumberIntType, &scale) : NULL;
    CFPreferencesSetAppValue(CFSTR("X11BackingScale"), value, CFSTR("org.darlinghq.AppKit"));
    if (value)
        CFRelease(value);
}

static void runLoopFor(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(void) {
    if (getenv("GDK_SCALE") != NULL) {
        printf("SKIP GDK_SCALE is set\n");
        return 0;
    }
    @autoreleasepool {
        setScalePreference(1);
        [NSApplication sharedApplication];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window makeKeyAndOrderFront: nil];
        runLoopFor(0.5);
        expect([window backingScaleFactor] == 1, "the window starts at scale 1");
        NSSize points = [window frame].size;

        [[NSNotificationCenter defaultCenter]
                addObserverForName: NSWindowDidChangeBackingPropertiesNotification
                            object: window
                             queue: nil
                        usingBlock: ^(NSNotification *note) {
                            notifications++;
                            notifiedOldScale = [[[note userInfo]
                                    objectForKey: NSBackingPropertyOldScaleFactorKey] doubleValue];
                        }];

        // The scale setting changes, then the layout does: the layout change is
        // what makes the backend look again.
        setScalePreference(2);
        printf("READY1\n");
        fflush(stdout);
        for (int i = 0; i < 100 && notifications == 0; i++)
            runLoopFor(0.2);

        expect(notifications == 1, "one NSWindowDidChangeBackingPropertiesNotification after the layout change");
        expect(notifiedOldScale == 1, "the notification carries the previous scale");
        expect([window backingScaleFactor] == 2, "the window reports the new scale");
        expect([[NSScreen mainScreen] backingScaleFactor] == 2, "the screen reports the new scale");
        runLoopFor(0.5);
        NSSize after = [window frame].size;
        expect(fabs(after.width - points.width) < 1 && fabs(after.height - points.height) < 1,
               "the window keeps its size in points");
        NSRect backing = [[window contentView] convertRectToBacking: [[window contentView] bounds]];
        expect(fabs(backing.size.width - 2 * points.width) < 2, "the content view is two device pixels per point");

        // Another layout change with the scale unchanged: no notification.
        printf("READY2\n");
        fflush(stdout);
        runLoopFor(4.0);
        expect(notifications == 1, "a layout change that leaves the scale alone posts nothing");

        setScalePreference(0);
        CFPreferencesAppSynchronize(CFSTR("org.darlinghq.AppKit"));
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
