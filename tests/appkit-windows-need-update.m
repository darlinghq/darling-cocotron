// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: -[NSApplication setWindowsNeedUpdate:] and -updateWindows.
// Apple's documentation describes updateWindows as sending -update to the
// windows with NSApplicationWillUpdateNotification before and
// NSApplicationDidUpdateNotification after. When it happens after
// setWindowsNeedUpdate:YES was observed on macOS 26.7.3 (x86_64) with the same
// calls: the next -nextEventMatchingMask:untilDate:inMode:dequeue: in the
// default or modal panel run loop mode updates the windows once, whether or
// not it dequeues or finds an event; other modes don't. A later NO cancels
// the update.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static int updates, willUpdate, didUpdate;
static int failures;

@interface CountingWindow : NSWindow
@end

@implementation CountingWindow
- (void)update
{
    updates++;
    [super update];
}
@end

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

static void postEvent(void)
{
    [NSApp postEvent: [NSEvent otherEventWithType: NSEventTypeApplicationDefined location: NSZeroPoint modifierFlags: 0
                                        timestamp: 0 windowNumber: 0 context: nil subtype: 0 data1: 0 data2: 0]
             atStart: NO];
}

static void drainEvents(void)
{
    while ([NSApp nextEventMatchingMask: NSEventMaskAny untilDate: [NSDate distantPast] inMode: NSDefaultRunLoopMode dequeue: YES])
        ;
}

// The number of window updates one call makes with the flag set (or not).
static int updatesFor(NSRunLoopMode mode, BOOL dequeue, BOOL withEvent, BOOL flag)
{
    drainEvents();
    if (withEvent)
        postEvent();
    if (flag)
        [NSApp setWindowsNeedUpdate: YES];
    updates = 0;
    [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2] inMode: mode dequeue: dequeue];
    return updates;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        CountingWindow *window = [[[CountingWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                                    styleMask: NSWindowStyleMaskTitled
                                                                      backing: NSBackingStoreBuffered
                                                                        defer: NO] autorelease];
        [window orderFront: nil];
        // Let the window system finish showing and activating the window first.
        NSDate *settle = [NSDate dateWithTimeIntervalSinceNow: 1];
        while ([settle timeIntervalSinceNow] > 0)
            [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: settle inMode: NSDefaultRunLoopMode dequeue: YES];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName: NSApplicationWillUpdateNotification object: nil queue: nil
                        usingBlock: ^(NSNotification *note) { willUpdate++; }];
        [center addObserverForName: NSApplicationDidUpdateNotification object: nil queue: nil
                        usingBlock: ^(NSNotification *note) { didUpdate++; }];

        updates = willUpdate = didUpdate = 0;
        [NSApp updateWindows];
        report("updateWindows updates the window", updates == 1);
        report("updateWindows posts the notifications", willUpdate == 1 && didUpdate == 1);

        drainEvents();
        report("default mode with an event", updatesFor(NSDefaultRunLoopMode, YES, YES, YES) == 1);
        report("default mode without an event", updatesFor(NSDefaultRunLoopMode, YES, NO, YES) == 1);
        report("default mode without dequeuing", updatesFor(NSDefaultRunLoopMode, NO, YES, YES) == 1);
        report("modal panel mode", updatesFor(NSModalPanelRunLoopMode, YES, YES, YES) == 1);
        report("not in event tracking mode", updatesFor(NSEventTrackingRunLoopMode, YES, YES, YES) == 0);
        report("not in another mode", updatesFor(@"OtherMode", YES, YES, YES) == 0);
        // the flag from the two cases above is still set
        drainEvents();
        report("no update unless asked for", updatesFor(NSDefaultRunLoopMode, YES, YES, NO) == 0);

        drainEvents();
        [NSApp setWindowsNeedUpdate: YES];
        postEvent();
        postEvent();
        updates = 0;
        [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: [NSDate distantPast] inMode: NSDefaultRunLoopMode dequeue: YES];
        int first = updates;
        [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: [NSDate distantPast] inMode: NSDefaultRunLoopMode dequeue: YES];
        report("one update per request", first == 1 && updates == 1);

        drainEvents();
        [NSApp setWindowsNeedUpdate: YES];
        [NSApp setWindowsNeedUpdate: NO];
        report("NO cancels", updatesFor(NSDefaultRunLoopMode, YES, YES, NO) == 0);
    }
    return failures != 0;
}
