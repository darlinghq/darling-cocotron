/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Window numbers. On macOS an NSWindow's windowNumber is the window server's id for the window, a
// small positive integer that fits a CGWindowID (32 bits) and is unique across the applications of the
// login session. The same number is the window's kCGWindowNumber in CGWindowListCopyWindowInfo(), the
// window of an NSEvent, the argument of -[NSApplication windowWithWindowNumber:]
// and the result of +[NSWindow windowNumberAtPoint:belowWindowWithWindowNumber:] and
// +[NSWindow windowNumbersWithOptions:]. A window that was created deferred and never ordered in has no
// window device and the number -1.
//
// Run as `appkit-window-number`; the program starts itself with the argument "child" to get the window
// of a second process. Needs an X server (with a window manager) or a Wayland compositor.
#import <AppKit/AppKit.h>
#include <CoreGraphics/CoreGraphics.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int failures;
#define CHECK(cond, what)                                                      \
    do {                                                                       \
        if (cond)                                                              \
            printf("PASS: %s\n", what);                                        \
        else {                                                                 \
            printf("FAIL: %s (line %d)\n", what, __LINE__);                    \
            failures++;                                                        \
        }                                                                      \
    } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSDictionary *listing(CGWindowID number) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    NSDictionary *found = nil;
    if (list != NULL) {
        for (NSDictionary *entry in (NSArray *) list) {
            if ([[entry objectForKey: (NSString *) kCGWindowNumber] unsignedIntValue] == number)
                found = [[entry retain] autorelease];
        }
        CFRelease(list);
    }
    return found;
}

static NSWindow *makeWindow(NSRect frame, NSWindowStyleMask style, BOOL defer) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                   styleMask: style
                                                     backing: NSBackingStoreBuffered
                                                       defer: defer];
    [window setReleasedWhenClosed: NO];
    return window;
}

static BOOL isWindowID(NSInteger number) {
    return number > 0 && number <= 0x7fffffff && (NSInteger) (CGWindowID) number == number;
}

static int childMain(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = makeWindow(NSMakeRect(40, 40, 120, 90), NSWindowStyleMaskBorderless, NO);
        [window orderFront: nil];
        spin(0.5);
        printf("CHILD %ld %d\n", (long) [window windowNumber], (int) getpid());
        fflush(stdout);
        // Stays until the parent ends it.
        for (;;)
            spin(1);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "child") == 0)
        return childMain();

    @autoreleasepool {
        [NSApplication sharedApplication];

        // A window with a device has its number from the start; a deferred one has none until it is ordered in.
        NSWindow *immediate = makeWindow(NSMakeRect(300, 300, 200, 200), NSWindowStyleMaskBorderless, NO);
        NSWindow *deferred = makeWindow(NSMakeRect(350, 350, 200, 200), NSWindowStyleMaskBorderless, YES);
        NSWindow *lower = makeWindow(NSMakeRect(500, 100, 200, 150), NSWindowStyleMaskBorderless, NO);
        CHECK([deferred windowNumber] == -1, "a deferred window that was never ordered in has the number -1");
        CHECK(isWindowID([immediate windowNumber]), "a window with a device has a small positive number that fits a CGWindowID");

        [immediate orderFront: nil];
        [deferred orderFront: nil];
        [lower setLevel: NSNormalWindowLevel - 1];
        [lower orderFront: nil];
        spin(0.7);

        NSInteger n1 = [immediate windowNumber], n2 = [deferred windowNumber], n3 = [lower windowNumber];
        CHECK(isWindowID(n1) && isWindowID(n2) && isWindowID(n3),
              "after ordering in, every window's number is a positive 32-bit window id");
        CHECK(n1 != n2 && n2 != n3 && n1 != n3, "the numbers differ from window to window");
        CHECK(n1 == [immediate windowNumber], "the number does not change");
        CHECK(n1 < 1000000 && n2 < 1000000 && n3 < 1000000, "the numbers are small");

        // CoreGraphics lists the window under the number.
        NSDictionary *entry = listing((CGWindowID) n1);
        CHECK(entry != nil, "CGWindowListCopyWindowInfo() lists the window under its number");
        CHECK([[entry objectForKey: (NSString *) kCGWindowOwnerPID] intValue] == getpid(),
              "the listing names this process as the owner");
        CHECK(listing((CGWindowID) n2) != nil && listing((CGWindowID) n3) != nil,
              "the other windows are listed under their numbers too");

        // The application finds the window by its number, and only by a number it has.
        CHECK([NSApp windowWithWindowNumber: n1] == immediate && [NSApp windowWithWindowNumber: n2] == deferred &&
                      [NSApp windowWithWindowNumber: n3] == lower,
              "-[NSApplication windowWithWindowNumber:] finds the windows");
        CHECK([NSApp windowWithWindowNumber: 0] == nil && [NSApp windowWithWindowNumber: -1] == nil &&
                      [NSApp windowWithWindowNumber: 0x7ffffff0] == nil,
              "no window has the numbers 0, -1 or one nobody was given");
        CHECK([NSApp windowWithWindowNumber: (NSInteger) (n1 + (1LL << 32))] == nil || sizeof(NSInteger) == 4,
              "a number with bits above the 32nd names no window");

        // An NSEvent made with the number has the window, and a CGEvent keeps the number in its window field.
        NSEvent *made = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                                           location: NSMakePoint(10, 10)
                                      modifierFlags: 0
                                          timestamp: 0
                                       windowNumber: n1
                                            context: nil
                                        eventNumber: 1
                                         clickCount: 1
                                           pressure: 1];
        CHECK([made windowNumber] == n1 && [made window] == immediate, "an NSEvent made with the number has the window");

        CGEventRef cg = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(310, 310), kCGMouseButtonLeft);
        CGEventSetIntegerValueField(cg, kCGMouseEventWindowUnderMousePointer, n1);
        CGEventSetIntegerValueField(cg, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, n1);
        CHECK(CGEventGetIntegerValueField(cg, kCGMouseEventWindowUnderMousePointer) == n1,
              "the CGEvent field keeps the number");
        CFRelease(cg);

        // The windows of the application, front to back. An X server stacks the windows by level (the lower level
        // last); a Wayland compositor stacks the windows itself and does not tell the stacking, so there the windows of
        // the application are listed in the order they were activated in, and only the order within one level is known.
        id display = [NSClassFromString(@"NSDisplay") performSelector: NSSelectorFromString(@"currentDisplay")];
        BOOL wayland = [NSStringFromClass([display class]) isEqualToString: @"WaylandDisplay"];
        NSArray *ours = [NSWindow windowNumbersWithOptions: 0];
        NSArray *expected = @[ @(n2), @(n1), @(n3) ];
        BOOL listed;
        if (wayland)
            listed = [ours count] == 3 && [ours containsObject: @(n1)] && [ours containsObject: @(n2)] &&
                     [ours containsObject: @(n3)] && [ours indexOfObject: @(n2)] < [ours indexOfObject: @(n1)];
        else
            listed = [ours isEqualToArray: expected];
        CHECK(listed, "+windowNumbersWithOptions:0 lists the ordered-in windows front to back");
        if (!listed)
            printf("  got %s, expected %s\n", [[ours description] UTF8String], [[expected description] UTF8String]);
        NSArray *all = [NSWindow windowNumbersWithOptions: NSWindowNumberListAllApplications];
        BOOL allHaveOurs = YES;
        for (NSNumber *number in expected)
            allHaveOurs = allHaveOurs && [all containsObject: number];
        CHECK(allHaveOurs, "the list for all applications has these windows too");

        NSWindow *never = makeWindow(NSMakeRect(50, 50, 80, 80), NSWindowStyleMaskBorderless, NO);
        CHECK(![[NSWindow windowNumbersWithOptions: 0] containsObject: @([never windowNumber])],
              "a window that was never ordered in is not listed");
        [lower orderOut: nil];
        spin(0.3);
        CHECK(![[NSWindow windowNumbersWithOptions: 0] containsObject: @(n3)], "a window ordered out is not listed");
        [lower orderFront: nil];
        spin(0.5);

        // The window at a point: the frontmost of the windows whose frame has it.
        NSRect fa = [immediate frame], fb = [deferred frame];
        // Points near a corner of each window, away from every edge.
        NSPoint inA = NSMakePoint(NSMinX(fa) + 10, NSMinY(fa) + 10);
        NSPoint inB = NSMakePoint(NSMaxX(fb) - 10, NSMaxY(fb) - 10);
        NSInteger expectA = NSPointInRect(inA, fb) ? n2 : n1;
        NSInteger expectB = NSPointInRect(inB, fa) ? n1 : n2;
        CHECK([NSWindow windowNumberAtPoint: inA belowWindowWithWindowNumber: 0] == expectA,
              "+windowNumberAtPoint: finds the window at a point inside the first window");
        CHECK([NSWindow windowNumberAtPoint: inB belowWindowWithWindowNumber: 0] == expectB,
              "+windowNumberAtPoint: finds the window at a point inside the second window");
        NSInteger below = [NSWindow windowNumberAtPoint: inB belowWindowWithWindowNumber: n2];
        CHECK(below != n2, "the window at a point below a window is not that window");
        CHECK([NSWindow windowNumberAtPoint: NSMakePoint(-100000, -100000) belowWindowWithWindowNumber: 0] == 0,
              "no window is far outside every screen");

        // A second process: its window number is a number of its own, and the first process lists the window under it.
        char path[4096];
        uint32_t size = sizeof(path);
        int pipefd[2];
        pid_t child = 0;
        if (_NSGetExecutablePath(path, &size) == 0 && pipe(pipefd) == 0) {
            posix_spawn_file_actions_t actions;
            posix_spawn_file_actions_init(&actions);
            posix_spawn_file_actions_adddup2(&actions, pipefd[1], 1);
            posix_spawn_file_actions_addclose(&actions, pipefd[0]);
            char *args[] = {path, "child", NULL};
            if (posix_spawn(&child, path, &actions, NULL, args, environ) != 0)
                child = 0;
            posix_spawn_file_actions_destroy(&actions);
            close(pipefd[1]);
            long childNumber = 0;
            int childPID = 0;
            if (child != 0) {
                FILE *in = fdopen(pipefd[0], "r");
                char line[256];
                time_t end = time(NULL) + 30;
                while (time(NULL) < end && fgets(line, sizeof(line), in) != NULL) {
                    if (sscanf(line, "CHILD %ld %d", &childNumber, &childPID) == 2)
                        break;
                }
            }
            CHECK(childPID != 0 && isWindowID(childNumber), "the second process has a window with a window id");
            CHECK(childNumber != n1 && childNumber != n2 && childNumber != n3,
                  "the second process' window number differs from the first process' numbers");
            if (!wayland) {
                NSDictionary *other = listing((CGWindowID) childNumber);
                CHECK(other != nil && [[other objectForKey: (NSString *) kCGWindowOwnerPID] intValue] == childPID,
                      "the first process lists the second process' window under the second process' number");
            } else {
                printf("SKIP: a Wayland client cannot list the windows of other clients\n");
            }
            if (child != 0) {
                kill(child, SIGKILL);
                waitpid(child, NULL, 0);
            }
        } else {
            CHECK(0, "could not start the second process");
        }
    }
    printf(failures == 0 ? "ALL PASSED\n" : "FAILURES: %d\n", failures);
    return failures != 0;
}
