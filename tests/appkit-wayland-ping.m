/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A compositor can ping a client (xdg_wm_base.ping) to find out whether it still responds, and treats one that does
// not pong in time as hung. The Wayland backend answers from the main thread's run loop only, so a client whose main
// thread is busy (here: blocked in sleep(), not running the run loop) looks hung, as it does on macOS. Opens a window,
// lets it be shown and resized by the compositor, runs the run loop for a while, blocks the main thread, then runs the
// run loop again. The start and the end of the block are announced to the compositor by setting the window's title to
// "STALL" and "UNSTALLED". The harness appkit-wayland-ping.sh runs it against wayland-ping-server, which pings
// repeatedly and records which pings were answered when.
//
//   appkit-wayland-ping stall     blocks the main thread for 2.5 s
//   appkit-wayland-ping fork      forks (and execs in one case) with the connection open before the block and after
//                                 it: the children neither crash nor hang, and the parent's connection keeps working
//
// Needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY; prints SKIP otherwise. Build without ARC.
#import <AppKit/AppKit.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures;
static int resizeCount;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        printf("FAIL: %s\n", what);
        failures++;
    }
}

@interface PingDelegate : NSObject <NSWindowDelegate>
@end
@implementation PingDelegate
- (void) windowDidResize: (NSNotification *) note {
    resizeCount++;
}
@end

static void spin(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
}

static void forkChildren(void) {
    pid_t pid = fork();
    if (pid == 0)
        _exit(7);
    expect(pid > 0, "fork");
    int status = 0;
    expect(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 7, "forked child exits");

    pid = fork();
    if (pid == 0) {
        execl("/usr/bin/true", "true", (char *) NULL);
        _exit(127);
    }
    expect(pid > 0, "fork before exec");
    expect(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0, "exec'ed child exits");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *backend = getenv("DARLING_APPKIT_BACKEND");
        if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
            printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
            return 0;
        }
        BOOL fork_mode = argc > 1 && strcmp(argv[1], "fork") == 0;
        [NSApplication sharedApplication];
        if (![NSStringFromClass([[NSClassFromString(@"NSDisplay") performSelector: @selector(currentDisplay)] class])
                    isEqualToString: @"WaylandDisplay"]) {
            printf("SKIP: the Wayland backend is not in use\n");
            return 0;
        }

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 300, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        PingDelegate *delegate = [[PingDelegate alloc] init];
        window.delegate = delegate;
        [window orderFront: nil];
        spin(1.0);
        expect(resizeCount > 0, "the compositor's resize reached the window");

        if (fork_mode)
            forkChildren();
        // Several pings arrive while the run loop is idle.
        spin(2.0);

        window.title = @"STALL";
        spin(0.2); // the title is on the wire before the thread blocks
        // The main thread does not run the run loop for longer than several of the compositor's pings.
        printf("STALL\n");
        fflush(stdout);
        sleep(2);
        usleep(500000);
        printf("UNSTALLED\n");
        fflush(stdout);

        window.title = @"UNSTALLED";
        if (fork_mode)
            forkChildren();
        // The pings that arrived during the block are answered now.
        spin(1.5);
        [window close];
        printf(failures == 0 ? "PASS\n" : "FAILED\n");
    }
    return failures == 0 ? 0 : 1;
}
