/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSWorkspace frontmostApplication] and -menuBarOwningApplication name the application that
// has the input focus; both are key-value observable. NSWorkspaceDidDeactivateApplicationNotification
// (old application) and NSWorkspaceDidActivateApplicationNotification (new one) carry the
// application under NSWorkspaceApplicationKey. Checked for this process once its window has the
// focus, and for a child application with its own window that takes it over and gives it back.
// Needs a display (X11 with a window manager, or a Wayland compositor that focuses new windows).
// Prints PASS on success.
#import <AppKit/AppKit.h>
#import "test-argument-words.h"
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
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

static void pumpFor(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: (NSEventMask) NSUIntegerMax
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static NSWindow *showWindow(const char *title) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
    TestIgnoreArgumentWords();
    [NSApp finishLaunching];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: [NSString stringWithUTF8String: title]];
    [window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    return window;
}

// The child shows a window and waits to be killed; it reports with a byte on stdout.
static int runChild(void) {
    @autoreleasepool {
        showWindow("frontmost-child");
        write(1, "R", 1);
        pumpFor(60);
    }
    return 0;
}

static pid_t startChild(const char *self) {
    int fds[2];
    if (pipe(fds) != 0)
        return -1;
    pid_t pid = fork();
    if (pid == 0) {
        dup2(fds[1], 1);
        close(fds[0]);
        close(fds[1]);
        execl(self, self, "child", (char *) NULL);
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

@interface Recorder : NSObject {
    NSMutableArray<NSString *> *_log;
}
@property(readonly) NSMutableArray<NSString *> *log;
@end

@implementation Recorder
@synthesize log = _log;
- (instancetype) init {
    self = [super init];
    _log = [[NSMutableArray alloc] init];
    return self;
}

- (void) note: (NSNotification *) notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    BOOL activate = [notification.name isEqualToString: NSWorkspaceDidActivateApplicationNotification];
    expect(notification.object == [NSWorkspace sharedWorkspace], "notifications are posted by the workspace");
    [_log addObject: [NSString stringWithFormat: @"%s %d", activate ? "activate" : "deactivate",
                               (int) app.processIdentifier]];
}

- (void) observeValueForKeyPath: (NSString *) keyPath ofObject: (id) object
                         change: (NSDictionary *) change context: (void *) context {
    NSRunningApplication *old = change[NSKeyValueChangeOldKey];
    NSRunningApplication *new = change[NSKeyValueChangeNewKey];
    [_log addObject: [NSString stringWithFormat: @"kvo %@ %d %d", keyPath,
                               [old isKindOfClass: [NSRunningApplication class]] ? (int) old.processIdentifier : 0,
                               [new isKindOfClass: [NSRunningApplication class]] ? (int) new.processIdentifier : 0]];
}
@end

static BOOL waitForFront(pid_t pid) {
    for (int i = 0; i < 100; i++) {
        pumpFor(0.1);
        if ([[NSWorkspace sharedWorkspace] frontmostApplication].processIdentifier == pid)
            return YES;
    }
    return NO;
}

static NSUInteger indexOf(Recorder *recorder, NSString *entry) {
    return [recorder.log indexOfObject: entry];
}

int main(int argc, char **argv) {
    if (argc > 1)
        return runChild();

    @autoreleasepool {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        Recorder *recorder = [[Recorder alloc] init];
        [workspace addObserver: recorder forKeyPath: @"frontmostApplication"
                       options: NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context: NULL];
        [workspace addObserver: recorder forKeyPath: @"menuBarOwningApplication"
                       options: NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context: NULL];
        [[workspace notificationCenter] addObserver: recorder selector: @selector(note:)
                                               name: NSWorkspaceDidActivateApplicationNotification object: nil];
        [[workspace notificationCenter] addObserver: recorder selector: @selector(note:)
                                               name: NSWorkspaceDidDeactivateApplicationNotification object: nil];

        NSWindow *window = showWindow("frontmost-parent");
        pid_t me = getpid();
        expect(waitForFront(me), "frontmostApplication is the current application once its window has the focus");
        NSRunningApplication *front = workspace.frontmostApplication;
        expect([[NSRunningApplication currentApplication] isActive], "the current application is active");
        expect([[NSRunningApplication currentApplication] ownsMenuBar], "the current application owns the menu bar");
        expect([front isEqual: [NSRunningApplication currentApplication]], "it is the current running application");
        expect([workspace.menuBarOwningApplication isEqual: front], "the front application owns the menu bar");

        pid_t child = startChild(argv[0]);
        expect(child > 0, "child application started");
        if (child > 0) {
            [recorder.log removeAllObjects];
            NSRunningApplication *childApp = [NSRunningApplication runningApplicationWithProcessIdentifier: child];
            expect(childApp != nil, "the child is a running application");
            [childApp activateWithOptions: NSApplicationActivateIgnoringOtherApps];
            expect(waitForFront(child), "frontmostApplication is the child after it activates");
            expect([workspace.frontmostApplication isEqual: childApp], "it is the child's running application");
            expect([workspace.menuBarOwningApplication isEqual: childApp], "the child owns the menu bar");
            expect([childApp isActive] && [childApp ownsMenuBar], "the child is active and owns the menu bar");
            expect(![[NSRunningApplication currentApplication] isActive] &&
                       ![[NSRunningApplication currentApplication] ownsMenuBar],
                   "the current application is not active any more");
            pumpFor(0.3);

            NSString *deactivated = [NSString stringWithFormat: @"deactivate %d", (int) me];
            NSString *activated = [NSString stringWithFormat: @"activate %d", (int) child];
            // The old application is this one, or none when the focus was seen leaving it before the
            // child's window took it.
            NSString *kvo = [NSString stringWithFormat: @"kvo frontmostApplication %d %d", (int) me, (int) child];
            NSString *kvoNone = [NSString stringWithFormat: @"kvo frontmostApplication 0 %d", (int) child];
            NSString *kvoMenu = [NSString stringWithFormat: @"kvo menuBarOwningApplication %d %d", (int) me, (int) child];
            NSString *kvoMenuNone = [NSString stringWithFormat: @"kvo menuBarOwningApplication 0 %d", (int) child];
            expect(indexOf(recorder, kvo) != NSNotFound || indexOf(recorder, kvoNone) != NSNotFound,
                   "key-value observers see frontmostApplication change");
            expect(indexOf(recorder, kvoMenu) != NSNotFound || indexOf(recorder, kvoMenuNone) != NSNotFound,
                   "key-value observers see menuBarOwningApplication change");
            expect(indexOf(recorder, deactivated) != NSNotFound, "the current application is reported deactivated");
            expect(indexOf(recorder, activated) != NSNotFound, "the child is reported activated");
            expect(indexOf(recorder, deactivated) < indexOf(recorder, activated), "deactivation comes first");

            // The child ends; its window goes and the window system gives the focus back.
            [recorder.log removeAllObjects];
            stopChild(child);
            expect(waitForFront(me), "frontmostApplication is the current application again");
            pumpFor(0.3);
            expect(indexOf(recorder, [NSString stringWithFormat: @"deactivate %d", (int) child]) != NSNotFound,
                   "the ended child is reported deactivated");
            expect(indexOf(recorder, [NSString stringWithFormat: @"activate %d", (int) me]) != NSNotFound,
                   "the current application is reported activated again");
            expect([NSRunningApplication runningApplicationWithProcessIdentifier: child] == nil,
                   "a process that ended is not an application");
        }
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
