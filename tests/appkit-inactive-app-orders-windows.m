/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// An application that is not active does not become active, and none of its
// windows becomes key, by ordering windows in. Only activation does that:
// -activateIgnoringOtherApps:, a click, or the launch of the application.
// Background-style applications show and hide tiny or borderless windows all
// the time; with another client active, that must leave the input focus with
// the other client. Needs a window server and a focus-granting window manager
// (DARLING_APPKIT_BACKEND=x11 on Xvfb with xfwm4, or DARLING_APPKIT_BACKEND=wayland
// in a compositor with a seat).
//
//   appkit-inactive-app-orders-windows                  all combinations (24 runs; on Wayland the kinds that
//          keep ordering windows in while inactive are only checked for resigning and activating, as the
//          compositor decides the focus of a newly mapped window)
//   appkit-inactive-app-orders-windows bg <policy> <when> <call> <secs> <kind>
//          the background app by itself, printing every activation change
//          for a harness that watches the window system's own focus
//   appkit-inactive-app-orders-windows other <secs>     the other client
//   policy: regular | accessory
//   when:   early (windows made while launching) | late
//   call:   front | regardless | key | relative
//   kind:   inert (windows that cannot become key) | keyable | titled
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static NSDate *startDate;
static int activations;
static int resignations;
static int failures;

static void say(const char *what) {
    printf("%6.2f %s\n", -[startDate timeIntervalSinceNow], what);
    fflush(stdout);
}

static void expect(BOOL ok, const char *what) {
    if (!ok) {
        failures++;
        printf("FAIL: %s\n", what);
        fflush(stdout);
    }
}

// A borderless window that can become key, as the windows of a background helper may be.
@interface KeyableWindow : NSWindow
@end

@implementation KeyableWindow
- (BOOL) canBecomeKeyWindow {
    return YES;
}
@end

@interface Watcher : NSObject <NSApplicationDelegate> {
    NSString *call;
    NSString *when;
    NSString *kind;
    BOOL isOther;
    NSMutableArray *windows;
    int step;
    NSTimer *timer;
}
@property (copy) NSString *call;
@property (copy) NSString *when;
@property (copy) NSString *kind;
@property BOOL isOther;
@property (retain) NSMutableArray *windows;
@property int step;
@property (retain) NSTimer *timer;
- (void) startWindows;
@end

@implementation Watcher
// i386 has no automatic synthesis (legacy runtime).
@synthesize call, when, kind, isOther, windows, step, timer;
- (void) applicationDidFinishLaunching: (NSNotification *) note {
    say("launched");
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(didBecomeActive:)
                                                 name: NSApplicationDidBecomeActiveNotification
                                               object: NSApp];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(didResignActive:)
                                                 name: NSApplicationDidResignActiveNotification
                                               object: NSApp];
    if (self.isOther)
        return;
    if ([self.when isEqualToString: @"early"])
        [self startWindows];
    else
        [self performSelector: @selector(startWindows) withObject: nil afterDelay: 0.5];
}

- (void) didBecomeActive: (NSNotification *) note {
    activations++;
    say("DidBecomeActive");
}

- (void) didResignActive: (NSNotification *) note {
    resignations++;
    say("DidResignActive");
}

// The windows of a background-style application: tiny, borderless or
// transparent, some of which can become key and some not.
- (void) startWindows {
    if (self.windows != nil)
        return;
    self.windows = [NSMutableArray array];

    NSMutableArray *made = [NSMutableArray array];
    if ([self.kind isEqualToString: @"vgui"]) {
        // The windows a UI toolkit keeps for itself: 1x1, clear, able to become key, one at level 0
        // and one at level 1, re-ordered every pass of its frame loop (see -tick:).
        for (int i = 0; i < 2; i++) {
            NSWindow *w = [[KeyableWindow alloc] initWithContentRect: NSMakeRect(19, 19, 1, 1)
                                                           styleMask: NSWindowStyleMaskBorderless
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [w setTitle: i == 0 ? @"FS-BG-VGUI1" : @"FS-BG-VGUI2"];
            [w setReleasedWhenClosed: NO];
            [w setLevel: i];
            [w setAlphaValue: 0];
            [w setOpaque: NO];
            [w setBackgroundColor: [NSColor clearColor]];
            [self.windows addObject: w];
        }
        self.timer = [NSTimer scheduledTimerWithTimeInterval: 0.2
                                                      target: self
                                                    selector: @selector(tick:)
                                                    userInfo: nil
                                                     repeats: YES];
        return;
    }
    if ([self.kind isEqualToString: @"static"]) {
        // The state of a background application at rest: one 1x1 window far off screen, level 1,
        // alpha 0, ordered in once, and nothing else shown. No window is ordered in or out again.
        NSWindow *rest = [[NSWindow alloc] initWithContentRect: NSMakeRect(-15000, 16106, 1, 1)
                                                     styleMask: NSWindowStyleMaskBorderless
                                                       backing: NSBackingStoreBuffered
                                                         defer: NO];
        [rest setTitle: @"FS-BG-REST"];
        [rest setReleasedWhenClosed: NO];
        [rest setLevel: 1];
        [rest setAlphaValue: 0];
        [rest setOpaque: NO];
        [rest setBackgroundColor: [NSColor clearColor]];
        [self.windows addObject: rest];
        [rest orderFront: nil];
        return;
    }
    NSWindow *borderless = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 1, 1)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
    [borderless setTitle: @"FS-BG-BORDERLESS"];
    NSWindow *clear = [[NSWindow alloc] initWithContentRect: NSMakeRect(10, 10, 4, 4)
                                                  styleMask: NSWindowStyleMaskBorderless
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
    [clear setTitle: @"FS-BG-CLEAR"];
    [clear setOpaque: NO];
    [clear setBackgroundColor: [NSColor clearColor]];
    [made addObjectsFromArray: @[ borderless, clear ]];
    if ([self.kind isEqualToString: @"keyable"]) {
        NSWindow *keyable = [[KeyableWindow alloc] initWithContentRect: NSMakeRect(20, 20, 1, 1)
                                                             styleMask: NSWindowStyleMaskBorderless
                                                               backing: NSBackingStoreBuffered
                                                                 defer: NO];
        [keyable setTitle: @"FS-BG-KEYABLE"];
        [made addObject: keyable];
    } else if ([self.kind isEqualToString: @"titled"]) {
        NSWindow *titled = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 1, 1)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [titled setTitle: @"FS-BG-TITLED"];
        [made addObject: titled];
    }
    for (NSWindow *w in made) {
        [w setReleasedWhenClosed: NO];
        [self.windows addObject: w];
    }
    self.timer = [NSTimer scheduledTimerWithTimeInterval: 0.2
                                                  target: self
                                                selector: @selector(tick:)
                                                userInfo: nil
                                                 repeats: YES];
}

- (void) order: (NSWindow *) w {
    if ([self.call isEqualToString: @"front"])
        [w orderFront: nil];
    else if ([self.call isEqualToString: @"regardless"])
        [w orderFrontRegardless];
    else if ([self.call isEqualToString: @"key"])
        [w makeKeyAndOrderFront: nil];
    else
        [w orderWindow: NSWindowAbove relativeTo: 0];
}

// Hides and shows the windows in turn, a few times a second.
- (void) tick: (NSTimer *) timer {
    if ([self.kind isEqualToString: @"vgui"]) {
        // The toolkit keeps its windows key while its application is active, and leaves them alone
        // otherwise: an active application whose windows are not key gets them ordered in and keyed.
        if (![NSApp isActive])
            return;
        for (NSWindow *w in self.windows) {
            [w orderOut: nil];
            [w setAlphaValue: 1];
            [w makeKeyAndOrderFront: nil];
            [w orderWindow: NSWindowAbove relativeTo: 0];
            [w makeKeyWindow];
        }
        return;
    }
    for (NSWindow *w in self.windows) {
        if (self.step % 2 == 0)
            [self order: w];
        else
            [w orderOut: nil];
    }
    self.step++;
}

- (BOOL) anyWindowKey {
    for (NSWindow *w in self.windows)
        if ([w isKeyWindow])
            return YES;
    return NO;
}
@end

static int runOther(double seconds, const char *policy) {
    @autoreleasepool {
        startDate = [NSDate date];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: strcmp(policy, "accessory") == 0 ? NSApplicationActivationPolicyAccessory
                                                                       : NSApplicationActivationPolicyRegular];
        Watcher *w = [Watcher new];
        w.isOther = YES;
        [NSApp setDelegate: w];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setReleasedWhenClosed: NO];
        [window setTitle: @"FS-OTHER"];
        [window makeKeyAndOrderFront: nil];
        [NSTimer scheduledTimerWithTimeInterval: 0.1 repeats: YES block: ^(NSTimer *t) {
            static BOOL announced;
            if (!announced && [NSApp isActive] && [window isKeyWindow]) {
                announced = YES;
                printf("READY\n");
                fflush(stdout);
            }
        }];
        [NSTimer scheduledTimerWithTimeInterval: seconds repeats: NO block: ^(NSTimer *t) {
            [NSApp terminate: nil];
        }];
        [NSApp run];
    }
    return 0;
}

// The background application. In the harness mode it only reports; with a
// child process playing the other client (the self-checking mode) it also
// judges.
static pid_t childPid;
static int childOut = -1;

static void startOther(const char *self, const char *policy) {
    int fds[2];
    pipe(fds);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    // Another program name: window managers group windows by their class, and
    // the other client must not look like part of the application under test.
    char *argv[] = {"inactive-app-other-client", "other", "60", (char *) policy, NULL};
    posix_spawn(&childPid, self, &actions, NULL, argv, environ);
    close(fds[1]);
    childOut = fds[0];
    fcntl(childOut, F_SETFL, O_NONBLOCK);
}

static BOOL otherIsReady(void) {
    char buffer[64];
    ssize_t n = read(childOut, buffer, sizeof(buffer) - 1);
    if (n <= 0)
        return NO;
    buffer[n] = 0;
    return strstr(buffer, "READY") != NULL;
}

static int runBackground(const char *self, const char *policy, const char *when, const char *call,
                         const char *kind, double seconds, BOOL judge) {
    @autoreleasepool {
        startDate = [NSDate date];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: strcmp(policy, "accessory") == 0
                                           ? NSApplicationActivationPolicyAccessory
                                           : NSApplicationActivationPolicyRegular];
        Watcher *w = [Watcher new];
        w.call = [NSString stringWithUTF8String: call];
        w.when = [NSString stringWithUTF8String: when];
        w.kind = [NSString stringWithUTF8String: kind];
        [NSApp setDelegate: w];

        __block BOOL readySeen = NO;
        __block int activationsAtReady = 0;
        __block BOOL finished = NO;
        if (judge) {
            // Let launching settle, then let the other client start and take the focus.
            // Two seconds after the application became active, however long launching took. The
            // other client is of the other kind: a regular application against an accessory
            // (LSUIElement-like) one, as an application and its helper process with the windows.
            __block double activeSince = 0;
            __block BOOL otherStarted = NO;
            [NSTimer scheduledTimerWithTimeInterval: 0.1 repeats: YES block: ^(NSTimer *t) {
                if (otherStarted || activations == 0)
                    return;
                if (activeSince == 0)
                    activeSince = -[startDate timeIntervalSinceNow];
                if (-[startDate timeIntervalSinceNow] - activeSince < 2.0)
                    return;
                otherStarted = YES;
                startOther(self, strcmp(policy, "regular") == 0 ? "accessory" : "regular");
            }];
            [NSTimer scheduledTimerWithTimeInterval: 0.1 repeats: YES block: ^(NSTimer *t) {
                if (childOut < 0 || readySeen || finished)
                    return;
                if (otherIsReady()) {
                    readySeen = YES;
                    say("other client is active");
                    // Window systems report the focus change a moment later.
                    [NSTimer scheduledTimerWithTimeInterval: 1.5 repeats: NO block: ^(NSTimer *t2) {
                        say("checking");
                        // Compositors give the keyboard focus to a toplevel when it is mapped, and
                        // xdg-shell has no way to map one without that. A program that keeps ordering
                        // windows in while its application is inactive (every kind but vgui) can
                        // therefore get the focus back on Wayland, whatever AppKit does; only the
                        // application that stops (vgui) is checked there.
                        BOOL compositorDecides = getenv("DARLING_APPKIT_BACKEND") != NULL &&
                                                 strcmp(getenv("DARLING_APPKIT_BACKEND"), "wayland") == 0 &&
                                                 strcmp(kind, "vgui") != 0;
                        if (compositorDecides)
                            say("NOTE: Wayland compositor decides the focus of newly mapped windows");
                        expect(compositorDecides || ![NSApp isActive],
                               "the application resigns when another client takes the focus");
                        activationsAtReady = activations;
                        [NSTimer scheduledTimerWithTimeInterval: 4.0 repeats: NO block: ^(NSTimer *t3) {
                            expect(compositorDecides || activations == activationsAtReady,
                                   "ordering windows in does not make the application active again");
                            expect(compositorDecides || ![NSApp isActive], "the application is still inactive");
                            // Activation by request still works.
                            [w.timer invalidate];
                            for (NSWindow *hidden in w.windows)
                                [hidden orderOut: nil];
                            NSWindow *main = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 200, 100)
                                                                          styleMask: NSWindowStyleMaskTitled
                                                                            backing: NSBackingStoreBuffered
                                                                              defer: NO];
                            [main setReleasedWhenClosed: NO];
                            [main setTitle: @"FS-BG-MAIN"];
                            [main makeKeyAndOrderFront: nil];
                            [NSApp activateIgnoringOtherApps: YES];
                            [NSTimer scheduledTimerWithTimeInterval: 2.5 repeats: NO block: ^(NSTimer *t4) {
                                expect([NSApp isActive], "activateIgnoringOtherApps: still activates");
                                expect([main isKeyWindow], "and the window it ordered in becomes key");
                                finished = YES;
                                if (childPid > 0) {
                                    kill(childPid, SIGTERM);
                                    waitpid(childPid, NULL, 0);
                                }
                                printf("%s\n", failures ? "FAIL" : "PASS");
                                fflush(stdout);
                                _exit(failures ? 1 : 0);
                            }];
                        }];
                    }];
                }
            }];
            [NSTimer scheduledTimerWithTimeInterval: 25.0 repeats: NO block: ^(NSTimer *t) {
                if (!readySeen) {
                    printf("SKIP: the other client never became active (no focus-granting window manager?)\n");
                    fflush(stdout);
                    if (childPid > 0)
                        kill(childPid, SIGTERM);
                    _exit(2);
                }
            }];
        } else {
            [NSTimer scheduledTimerWithTimeInterval: seconds repeats: NO block: ^(NSTimer *t) {
                [NSApp terminate: nil];
            }];
        }
        [NSApp run];
    }
    if (childPid > 0) {
        kill(childPid, SIGTERM);
        waitpid(childPid, NULL, 0);
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}

// Runs one combination in a child process and returns its exit status.
static int runCombination(const char *self, const char *policy, const char *when, const char *call,
                          const char *kind) {
    pid_t pid;
    char *argv[] = {(char *) self, "check", (char *) policy, (char *) when, (char *) call, (char *) kind, NULL};
    printf("--- %s %s %s %s\n", policy, when, call, kind);
    fflush(stdout);
    if (posix_spawn(&pid, self, NULL, NULL, argv, environ) != 0)
        return 1;
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *path = [[NSBundle mainBundle] executablePath];
        const char *self = [path fileSystemRepresentation];

        if (argc >= 3 && strcmp(argv[1], "other") == 0)
            return runOther(atof(argv[2]), argc >= 4 ? argv[3] : "regular");
        if (argc >= 7 && strcmp(argv[1], "bg") == 0)
            return runBackground(self, argv[2], argv[3], argv[4], argv[6], atof(argv[5]), NO);
        if (argc >= 6 && strcmp(argv[1], "check") == 0)
            return runBackground(self, argv[2], argv[3], argv[4], argv[5], 0, YES);

        int bad = 0, skipped = 0;
        const char *policies[] = {"regular", "accessory"};
        const char *whens[] = {"early", "late"};
        const char *calls[] = {"front", "key"};
        const char *kinds[] = {"inert", "titled", "vgui"};
        for (int p = 0; p < 2; p++)
            for (int w = 0; w < 2; w++)
                for (int c = 0; c < 2; c++)
                  for (int k = 0; k < 3; k++) {
                    int rc = runCombination(self, policies[p], whens[w], calls[c], kinds[k]);
                    if (rc == 2)
                        skipped++;
                    else if (rc != 0)
                        bad++;
                }
        printf("%s\n", bad ? "FAIL" : (skipped ? "SKIP" : "PASS"));
        return bad ? 1 : 0;
    }
}
