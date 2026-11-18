/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// +[NSRunningApplication runningApplicationWithProcessIdentifier:] knows only applications:
// processes that connected to the window system. A plain command line tool and a system
// daemon (pid 1) have no application object and cannot be activated; a process that created
// NSApplication has one, and its activation is requested. Needs a display (X11 or Wayland, as
// selected by DARLING_APPKIT_BACKEND) for the application child. Prints PASS on success.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

// Private CoreGraphics entry point, not in the SDK headers.
typedef int (*ActivateProcessFunction)(pid_t pid, uint32_t options);

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

// Child modes: "tool" never uses AppKit's application object, "app" creates it. Each reports
// readiness with a byte on stdout and then waits to be killed.
static int runChild(const char *mode) {
    @autoreleasepool {
        if (strcmp(mode, "app") == 0)
            [NSApplication sharedApplication];
        write(1, "R", 1);
        for (int i = 0; i < 60; i++)
            sleep(1);
    }
    return 0;
}

static pid_t startChild(const char *self, const char *mode) {
    int fds[2];
    if (pipe(fds) != 0)
        return -1;
    pid_t pid = fork();
    if (pid == 0) {
        dup2(fds[1], 1);
        close(fds[0]);
        close(fds[1]);
        execl(self, self, mode, (char *) NULL);
        _exit(127);
    }
    close(fds[1]);
    char ready = 0;
    BOOL ok = pid > 0 && read(fds[0], &ready, 1) == 1;
    close(fds[0]);
    if (!ok && pid > 0) {
        kill(pid, SIGKILL);
        waitpid(pid, NULL, 0);
        return -1;
    }
    return pid;
}

static void stopChild(pid_t pid) {
    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
}

int main(int argc, char **argv) {
    if (argc > 1)
        return runChild(argv[1]);

    @autoreleasepool {
        NSRunningApplication *init = [NSRunningApplication runningApplicationWithProcessIdentifier: 1];
        expect(init == nil, "pid 1 has no running application");
        expect(![init activateWithOptions: 0], "pid 1 cannot be activated");

        pid_t tool = startChild(argv[0], "tool");
        expect(tool > 0, "tool child started");
        if (tool > 0) {
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier: tool];
            expect(app == nil, "a command line tool has no running application");
            expect(![app activateWithOptions: 0], "a command line tool cannot be activated");
            ActivateProcessFunction activate = (ActivateProcessFunction) dlsym(RTLD_DEFAULT, "_CGSActivateProcess");
            expect(activate != NULL && activate(tool, 0) != 0, "activating a tool through CoreGraphics fails");
            stopChild(tool);
        }

        pid_t child = startChild(argv[0], "app");
        expect(child > 0, "application child started");
        if (child > 0) {
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier: child];
            expect(app != nil, "an application has a running application object");
            expect([app processIdentifier] == child, "the object carries the pid");
            expect([app activateWithOptions: 0], "an application activation is requested");
            stopChild(child);
            expect([NSRunningApplication runningApplicationWithProcessIdentifier: child] == nil,
                   "a process that ended has no running application");
        }

        expect([NSRunningApplication runningApplicationWithProcessIdentifier: getpid()] != nil,
               "the current process has a running application");
        expect([NSRunningApplication runningApplicationWithProcessIdentifier: -1] == nil,
               "an invalid pid has no running application");
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
