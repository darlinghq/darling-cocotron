// Copyright (C) 2026 Lubos Dolezel
//
// NSRunningApplication's executable, architecture, launch date, launch state and forced
// termination, for the current process and for a child process.
#import <AppKit/AppKit.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <sys/wait.h>

extern char **environ;

static int failures = 0;
#define expect(cond) do { int ok_ = (cond) ? 1 : 0; printf("%s: %s\n", ok_ ? "PASS" : "FAIL", #cond); if (!ok_) failures++; } while (0)

int main(void)
{
    @autoreleasepool {
        NSRunningApplication *me = [NSRunningApplication currentApplication];

        char path[PATH_MAX];
        uint32_t size = sizeof(path);
        _NSGetExecutablePath(path, &size);
        NSString *executable = [[NSString stringWithUTF8String: path] stringByResolvingSymlinksInPath];
        expect([[[[me executableURL] path] stringByResolvingSymlinksInPath] isEqualToString: executable]);
        expect([[me executableURL] isFileURL]);

#if defined(__x86_64__)
        expect([me executableArchitecture] == NSBundleExecutableArchitectureX86_64);
#else
        expect([me executableArchitecture] == NSBundleExecutableArchitectureI386);
#endif

        NSDate *launched = [me launchDate];
        expect(launched != nil);
        expect([launched timeIntervalSinceNow] <= 1 && [launched timeIntervalSinceNow] > -600);

        [NSApplication sharedApplication];
        expect(![me isFinishedLaunching]);
        [NSApp finishLaunching];
        expect([me isFinishedLaunching]);

        // A child that would run for a minute ends at once when forced.
        pid_t child;
        char *argv[] = { "/bin/sleep", "60", NULL };
        expect(posix_spawn(&child, "/bin/sleep", NULL, NULL, argv, environ) == 0);
        NSRunningApplication *other = [NSRunningApplication runningApplicationWithProcessIdentifier: child];
        if (other != nil) {
            expect([[[other executableURL] lastPathComponent] isEqualToString: @"sleep"]);
            expect([other executableArchitecture] != 0);
            expect([other launchDate] != nil);
            expect([other forceTerminate]);
        } else {
            kill(child, SIGKILL);
        }
        int status = 0;
        expect(waitpid(child, &status, 0) == child);
        expect(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
        if (other != nil) {
            expect([other isTerminated]);
            expect(![other forceTerminate]);
        }

        [NSRunningApplication terminateAutomaticallyTerminableApplications];
        expect(![me isTerminated]);
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
