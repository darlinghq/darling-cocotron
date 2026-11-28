// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// The window ids of CoreGraphics windows are the window server's names for windows: positive numbers that fit a
// CGWindowID, handed out one counter for the whole system, so that two processes never have a window of the same id
// (another process lists a window under the id its owner knows it by). A process without AppKit, on X11 or Wayland:
// the program makes windows, starts itself as a second process (argument "child") that makes windows too, and
// compares what both see. A Wayland client cannot list the windows of other clients, so only the ids are compared
// there.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

// The window server calls are private: no public header declares them.
typedef int CGSConnectionID;
typedef unsigned CGSWindowID;
typedef CFTypeRef RegionRef;
extern CGSConnectionID CGSMainConnectionID(void);
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeDisplay(CGSConnectionID cid);
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

static CGSWindowID makeWindow(CGSConnectionID cid, int index) {
    CGRect frame = CGRectMake(100 + 40 * index, 100 + 40 * index, 200, 150);
    RegionRef region = NULL;
    CGSWindowID wid = 0;
    if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess ||
        CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess)
        return 0;
    return wid;
}

static NSDictionary *listing(CGWindowID number) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    NSDictionary *found = nil;
    for (NSDictionary *entry in (NSArray *) list) {
        if ([[entry objectForKey: (NSString *) kCGWindowNumber] unsignedIntValue] == number)
            found = [[entry retain] autorelease];
    }
    if (list != NULL)
        CFRelease(list);
    return found;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CGSConnectionID cid = CGSMainConnectionID();
        if (cid == 0 || _CGSNativeDisplay(cid) == NULL) {
            printf("FAIL: no connection to the window system\n");
            return 1;
        }
        CGSWindowID mine[3];
        for (int i = 0; i < 3; i++)
            mine[i] = makeWindow(cid, i);

        if (argc > 1 && strcmp(argv[1], "child") == 0) {
            printf("CHILD %u %u %u %d\n", mine[0], mine[1], mine[2], (int) getpid());
            fflush(stdout);
            for (;;)
                [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1]];
        }

        BOOL ok = YES;
        for (int i = 0; i < 3; i++)
            ok = ok && mine[i] > 0 && mine[i] <= 0x7fffffff;
        CHECK(ok, "the windows have positive 32-bit ids");
        CHECK(mine[0] != mine[1] && mine[1] != mine[2] && mine[0] != mine[2], "the ids differ from window to window");
        CHECK(listing(mine[0]) != nil, "CGWindowListCopyWindowInfo() lists the window under its id");

        char path[4096];
        uint32_t size = sizeof(path);
        int pipefd[2];
        pid_t child = 0;
        if (_NSGetExecutablePath(path, &size) != 0 || pipe(pipefd) != 0) {
            CHECK(0, "could not start the second process");
        } else {
            posix_spawn_file_actions_t actions;
            posix_spawn_file_actions_init(&actions);
            posix_spawn_file_actions_adddup2(&actions, pipefd[1], 1);
            posix_spawn_file_actions_addclose(&actions, pipefd[0]);
            char *args[] = {path, "child", NULL};
            if (posix_spawn(&child, path, &actions, NULL, args, environ) != 0)
                child = 0;
            posix_spawn_file_actions_destroy(&actions);
            close(pipefd[1]);
            unsigned other[3] = {0, 0, 0};
            int otherPID = 0;
            if (child != 0) {
                FILE *in = fdopen(pipefd[0], "r");
                char line[256];
                time_t end = time(NULL) + 30;
                while (time(NULL) < end && fgets(line, sizeof(line), in) != NULL) {
                    if (sscanf(line, "CHILD %u %u %u %d", &other[0], &other[1], &other[2], &otherPID) == 4)
                        break;
                }
            }
            CHECK(otherPID != 0 && other[0] > 0 && other[1] > 0 && other[2] > 0, "the second process made windows");
            BOOL distinct = YES;
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                    distinct = distinct && mine[i] != other[j];
            CHECK(distinct, "no id of the second process is an id of the first");
            const char *wayland = getenv("WAYLAND_DISPLAY");
            if (wayland == NULL || wayland[0] == '\0') {
                BOOL listed = YES;
                for (int i = 0; i < 3; i++) {
                    NSDictionary *entry = listing(other[i]);
                    listed = listed && entry != nil && [[entry objectForKey: (NSString *) kCGWindowOwnerPID] intValue] == otherPID;
                }
                CHECK(listed, "the first process lists the windows of the second under the ids their owner has");
            } else {
                printf("SKIP: a Wayland client cannot list the windows of other clients\n");
            }
            if (child != 0) {
                kill(child, SIGKILL);
                waitpid(child, NULL, 0);
            }
        }
    }
    printf(failures == 0 ? "ALL PASSED\n" : "FAILURES: %d\n", failures);
    return failures != 0;
}
