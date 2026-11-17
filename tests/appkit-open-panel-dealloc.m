// Copyright (C) 2026 Lubos Dolezel
//
// An open or save panel can be dismissed with Cancel and released without
// the folder navigation controls it added messaging views that are already gone: the release of the panel returns.
// A watchdog turns a hang into a failure. Needs a display.
#import <AppKit/AppKit.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static int deallocated;

// Attached to a panel to report when the panel is deallocated, so that the release below really ends its life.
@interface DeallocFlag : NSObject
@end
@implementation DeallocFlag
- (void)dealloc {
    deallocated++;
    [super dealloc];
}
@end
static char flagKey;

static void watchdog(int sig) {
    static const char msg[] = "FAIL: releasing the panel hung or crashed\n";
    (void) !write(2, msg, sizeof msg - 1);
    _exit(2);
}

// Runs the panel modally and dismisses it from a timer with Cancel, the way the user does. The panel is then released
// by the autorelease pool and the application's list of windows, and `expected` panels must have been deallocated. The panel owns the folder navigation controls
// and their views; its deallocation must return and not touch views that are already gone.
static void cycle(NSSavePanel *(^make)(void), int expected) {
    @autoreleasepool {
        NSSavePanel *panel = make();
        DeallocFlag *flag = [DeallocFlag new];
        objc_setAssociatedObject(panel, &flagKey, flag, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [flag release];
        [panel setDirectoryURL: [NSURL fileURLWithPath: NSTemporaryDirectory() isDirectory: YES]];
        NSTimer *timer = [NSTimer timerWithTimeInterval: 0.4 repeats: NO block: ^(NSTimer *t) { [panel cancel: nil]; }];
        [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
        CHECK([panel runModal] == NSModalResponseCancel);
    }
    // the application's list of windows lets the closed window go when the event loop finds it
    [NSApp nextEventMatchingMask: NSAnyEventMask
                       untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                          inMode: NSDefaultRunLoopMode
                         dequeue: YES];
    CHECK(deallocated == expected);
}

int main(void)
{
    signal(SIGSEGV, watchdog);
    signal(SIGBUS, watchdog);
    signal(SIGALRM, watchdog);
    alarm(60);
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (int i = 0; i < 3; i++) {
            cycle(^NSSavePanel *{ return [NSOpenPanel openPanel]; }, 2 * i + 1);
            cycle(^NSSavePanel *{ return [NSSavePanel savePanel]; }, 2 * i + 2);
        }
    }
    if (failures == 0)
        puts("PASS");
    return failures ? 1 : 0;
}
