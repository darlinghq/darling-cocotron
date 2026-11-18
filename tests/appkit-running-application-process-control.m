/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSRunningApplication for another process: bundleURL, bundleIdentifier, activationPolicy, icon, isHidden,
// hide, unhide and terminate, and +runningApplicationsWithBundleIdentifier:. The helper application is a
// copy of this program in a bundle (it runs as the helper when started from inside a .app); it is
// started directly and found through the registry of applications. terminate is a quit request, not a
// signal: the helper ends through its own quit path with status 0. Prints PASS on success. Needs a
// window system session (X11 or Wayland, as selected by DARLING_APPKIT_BACKEND).
#import <AppKit/AppKit.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL waitUntil(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while (!condition()) {
        if ([end timeIntervalSinceNow] <= 0)
            return NO;
        usleep(50 * 1000);
    }
    return YES;
}

static BOOL runsFromBundle(void) {
    return [[[NSBundle mainBundle] executablePath] containsString: @".app/Contents/MacOS/"];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (runsFromBundle()) {
            // The helper: an application that waits for requests, and gives up after a minute.
            [NSApplication sharedApplication];
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 60];
            while ([end timeIntervalSinceNow] > 0)
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
            return 3;
        }

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *tag = [NSString stringWithFormat: @"%d", (int) getpid()];
        NSString *bundle = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                           [NSString stringWithFormat: @"processcontrol%@.app", tag]];
        NSString *macos = [bundle stringByAppendingPathComponent: @"Contents/MacOS"];
        NSString *identifier = [@"org.darlinghq.test.processcontrol" stringByAppendingString: tag];
        [fm createDirectoryAtPath: macos withIntermediateDirectories: YES attributes: nil error: NULL];
        NSString *executable = [macos stringByAppendingPathComponent: @"helper"];
        expect([fm copyItemAtPath: [[NSBundle mainBundle] executablePath] toPath: executable error: NULL],
               "helper executable copied");
        [@{
            @"CFBundleIdentifier" : identifier,
            @"CFBundleExecutable" : @"helper",
            @"CFBundlePackageType" : @"APPL",
            @"CFBundleName" : @"helper",
            @"CFBundleVersion" : @"1",
            @"LSUIElement" : @YES,
        } writeToFile: [bundle stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: YES];

        // The current process is not in a bundle: nothing to say about its bundle, a regular application.
        NSRunningApplication *self_ = [NSRunningApplication currentApplication];
        expect(self_.bundleURL == nil, "a process outside a bundle has no bundle URL");
        expect(self_.activationPolicy == NSApplicationActivationPolicyRegular, "its policy is regular");
        expect(!self_.isHidden, "it is not hidden");

        pid_t child = fork();
        if (child == 0) {
            execl([executable fileSystemRepresentation], [executable fileSystemRepresentation], (char *) NULL);
            _exit(127);
        }
        expect(child > 0, "helper started");

        __block NSRunningApplication *app = nil;
        expect(waitUntil(^BOOL {
                   app = [NSRunningApplication runningApplicationWithProcessIdentifier: child];
                   return app != nil;
               }, 20),
               "the helper becomes a running application");
        if (app != nil) {
            NSString *real = [bundle stringByResolvingSymlinksInPath];
            expect([[[app.bundleURL path] stringByResolvingSymlinksInPath] isEqualToString: real],
                   "bundleURL is the helper's bundle");
            expect([app.bundleIdentifier isEqualToString: identifier], "bundleIdentifier comes from the bundle");
            expect(app.activationPolicy == NSApplicationActivationPolicyAccessory, "LSUIElement gives accessory");
            expect(app.icon != nil, "the application has an icon");
            expect(!app.isHidden, "not hidden at first");

            NSArray *byIdentifier = [NSRunningApplication runningApplicationsWithBundleIdentifier: identifier];
            expect([byIdentifier count] == 1 && [byIdentifier containsObject: app],
                   "runningApplicationsWithBundleIdentifier: finds the helper");
            expect([[NSRunningApplication runningApplicationsWithBundleIdentifier: @"org.darlinghq.test.nosuch"] count] == 0,
                   "an unknown identifier has no running applications");

            expect([app hide], "hide is requested");
            expect(waitUntil(^BOOL { return app.isHidden; }, 10), "the application becomes hidden");
            expect([app unhide], "unhide is requested");
            expect(waitUntil(^BOOL { return !app.isHidden; }, 10), "the application is shown again");

            expect([app terminate], "terminate is requested");
            int status = 0;
            BOOL ended = waitUntil(^BOOL { return waitpid(child, &status, WNOHANG) == child; }, 20);
            expect(ended, "the application ends after the quit request");
            if (ended)
                expect(WIFEXITED(status) && WEXITSTATUS(status) == 0, "it ended through its quit path (not a signal)");
            else {
                kill(child, SIGKILL);
                waitpid(child, NULL, 0);
            }
            expect(app.isTerminated, "isTerminated after it ended");
            expect(![app hide] && ![app unhide] && ![app terminate], "no request reaches a terminated application");
            expect(!app.isHidden, "a terminated application is not hidden");
        } else {
            kill(child, SIGKILL);
            waitpid(child, NULL, 0);
        }
        [fm removeItemAtPath: bundle error: NULL];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
