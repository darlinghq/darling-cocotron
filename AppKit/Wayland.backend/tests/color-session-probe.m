/*
  Copyright (C) 2026 Lubos Dolezel

  Licensed under the MIT license, the same as the rest of this project.
*/
// Guest side of wayland-color-session.sh. It exercises the compositor's color description (NSScreen),
// the per-surface description and alpha mode (WaylandWindow), and the three ways a compositor session
// can start: launch, recover after a crash, and restore saved state.
// Usage: color-session-probe <color|launch|restore|recover|marker> <seconds>
// The marker mode runs on any backend, only to report whether the running marker exists while the
// application runs: it is expected with a window-system session (Wayland offering
// xdg-session-management) and nowhere else.
// The program re-executes itself from a small .app bundle so that the saved state has a bundle
// identifier. It prints READY when the window is up, then PROBE done with a failure count.
#import <AppKit/AppKit.h>
#include <math.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static NSString *const TestBundleID = @"test.color-session";
static NSString *const TestSessionID = @"test-session-1";
static NSString *const TestWindowName = @"saved-window";
static NSString *const TestWindowIdentifier = @"main";

static NSMutableArray *restoredWindows;

@class ColorSessionRestorer;

@interface NSObject (ColorSessionProbeDisplay)
+ (id) currentDisplay;
@end

static NSData *ArchiveState(void (^encode)(NSKeyedArchiver *archiver)) {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
    [archiver setOutputFormat: NSPropertyListBinaryFormat_v1_0];
    encode(archiver);
    [archiver finishEncoding];
    [archiver release];
    return data;
}

static NSString *StateDirectory(void) {
    NSArray *libraries = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    if ([libraries count] == 0)
        return nil;
    return [[[libraries objectAtIndex: 0] stringByAppendingPathComponent: @"Saved Application State"]
            stringByAppendingPathComponent: [TestBundleID stringByAppendingString: @".savedState"]];
}

static NSString *StatePath(NSString *name) {
    NSString *directory = StateDirectory();
    return directory == nil ? nil : [directory stringByAppendingPathComponent: name];
}

static void RemoveState(void) {
    NSString *directory = StateDirectory();
    if (directory != nil)
        [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
}

// A saved state that names both the compositor session and one of its toplevels.
static void WriteSavedState(void) {
    RemoveState();
    NSString *directory = StateDirectory();
    if (directory == nil)
        return;
    [[NSFileManager defaultManager] createDirectoryAtPath: directory
                              withIntermediateDirectories: YES
                                               attributes: nil
                                                    error: NULL];
    NSData *application = ArchiveState(^(NSKeyedArchiver *archiver) {
        [archiver encodeObject: @"color-session-probe" forKey: @"Application"];
    });
    NSData *window = ArchiveState(^(NSKeyedArchiver *archiver) {
        [archiver encodeRect: NSMakeRect(100, 100, 240, 120) forKey: @"NSWindowRestorationFrame"];
        [archiver encodeObject: NSStringFromClass([ColorSessionRestorer class])
                        forKey: @"NSWindowRestorationClass"];
    });
    NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
            TestWindowIdentifier, @"Identifier",
            window, @"State",
            TestWindowName, @"WindowSession",
            nil];
    NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt: 1], @"Version",
            application, @"Application",
            TestSessionID, @"Session",
            [NSArray arrayWithObject: entry], @"Windows",
            nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList: plist
                                                              format: NSPropertyListBinaryFormat_v1_0
                                                             options: 0
                                                               error: NULL];
    [data writeToFile: StatePath(@"state.plist") options: NSDataWritingAtomic error: NULL];
}

// A leftover marker is what an application that died before saving its state leaves behind.
static void WriteRunningMarker(void) {
    NSString *directory = StateDirectory();
    if (directory == nil)
        return;
    [[NSFileManager defaultManager] createDirectoryAtPath: directory
                              withIntermediateDirectories: YES
                                               attributes: nil
                                                    error: NULL];
    [[TestSessionID dataUsingEncoding: NSUTF8StringEncoding]
            writeToFile: StatePath(@"running") options: NSDataWritingAtomic error: NULL];
}

@interface ColorSessionRestorer : NSObject <NSWindowRestoration>
@end

@implementation ColorSessionRestorer

+ (void) restoreWindowWithIdentifier: (NSString *) identifier
                               state: (NSCoder *) state
                   completionHandler: (void (^)(NSWindow *, NSError *)) completion {
    NSRect frame = NSMakeRect(100, 100, 240, 120);
    if ([state containsValueForKey: @"NSWindowRestorationFrame"])
        frame = [state decodeRectForKey: @"NSWindowRestorationFrame"];
    // Deferred: the saved session name is applied by the completion handler before this window
    // gets a platform window and commits its surface.
    NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                   styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                     backing: NSBackingStoreBuffered
                                                       defer: YES];
    [window setIdentifier: identifier];
    [window setRestorable: YES];
    [window setRestorationClass: self];
    [window setTitle: @"session-test"];
    if (restoredWindows == nil)
        restoredWindows = [NSMutableArray new];
    [restoredWindows addObject: window];
    completion(window, nil);
    [window release];
}

@end

@interface ProbeDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *_window;
    NSArray *_restored;
    double _seconds;
    int _failures;
    BOOL _ready;
    BOOL _markerOnly;
}
- (void) setMarkerOnly: (BOOL) markerOnly;
- (void) showWindows;
- (void) run;
- (int) failures;
@end

@implementation ProbeDelegate

- (BOOL) application: (NSApplication *) application openFiles: (NSArray *) files {
    return YES;
}

- (void) showWindows {
    NSArray *windows = [_restored count] > 0 ? _restored : [NSArray arrayWithObject: _window];
    for (NSWindow *window in windows)
        [window makeKeyAndOrderFront: nil];
    if (_markerOnly) {
        printf("READY\n");
        fflush(stdout);
        return;
    }
    NSScreen *screen = [NSScreen mainScreen];
    NSColorSpace *space = [screen colorSpace];
    BOOL p3 = [[space localizedName] isEqualToString: @"Display P3"];
    double edr = [screen maximumExtendedDynamicRangeColorComponentValue];
    double potential = [screen maximumPotentialExtendedDynamicRangeColorComponentValue];
    double reference = [screen maximumReferenceExtendedDynamicRangeColorComponentValue];
    printf("SCREEN p3=%d edr=%.2f potential=%.2f reference=%.2f\n", p3, edr, potential, reference);
    fflush(stdout);
    if (!p3 || fabs(edr - 1.97) > 0.01 || fabs(potential - 4.93) > 0.01 ||
        fabs(reference - 4.93) > 0.01) {
        _failures++;
    }
    printf("READY\n");
    fflush(stdout);
}

- (void) run {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: _seconds];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
    printf("BACKEND %s\n", [NSStringFromClass([[NSClassFromString(@"NSDisplay") currentDisplay] class]) UTF8String]);
    printf("RUNNING_MARKER present=%d\n",
           [[NSFileManager defaultManager] fileExistsAtPath: StatePath(@"running")] ? 1 : 0);
    printf("PROBE done failures=%d\n", _failures);
    fflush(stdout);
    [NSApp terminate: nil];
}

- (void) applicationWillTerminate: (NSNotification *) notification {
    BOOL absent = ![[NSFileManager defaultManager] fileExistsAtPath: StatePath(@"running")];
    printf("MARKER absent=%d\n", absent);
    fflush(stdout);
    if (!absent)
        _failures++;
    RemoveState();
}

- (void) setMarkerOnly: (BOOL) markerOnly {
    _markerOnly = markerOnly;
}

- (void) setWindow: (NSWindow *) window {
    [window retain];
    [_window release];
    _window = window;
}

- (void) setSeconds: (double) seconds {
    _seconds = seconds;
}

- (void) setRestoredWindows: (NSArray *) windows {
    [windows retain];
    [_restored release];
    _restored = windows;
}

- (int) failures {
    return _failures;
}

- (void) dealloc {
    [_window release];
    [_restored release];
    [super dealloc];
}

@end

static NSString *MakeBundle(void) {
    NSString *app = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"color-session-%d.app", getpid()]];
    NSString *macos = [app stringByAppendingPathComponent: @"Contents/MacOS"];
    [[NSFileManager defaultManager] createDirectoryAtPath: macos
                              withIntermediateDirectories: YES
                                               attributes: nil
                                                    error: NULL];
    NSString *copy = [macos stringByAppendingPathComponent: @"color-session-probe"];
    if (![[NSFileManager defaultManager] copyItemAtPath: [[NSBundle mainBundle] executablePath]
                                                 toPath: copy error: NULL])
        return nil;
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
            @"color-session-probe", @"CFBundleExecutable",
            @"color-session-probe", @"CFBundleName",
            @"APPL", @"CFBundlePackageType",
            TestBundleID, @"CFBundleIdentifier",
            nil];
    [info writeToFile: [app stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: NO];
    return copy;
}

static int RunBundled(const char *mode, double seconds) {
    NSString *directory = StateDirectory();
    if (directory == nil) {
        fprintf(stderr, "no saved state directory\n");
        return 2;
    }
    if (strcmp(mode, "restore") == 0)
        WriteSavedState();
    else if (strcmp(mode, "recover") == 0)
        WriteRunningMarker();
    else
        RemoveState();

    [NSApplication sharedApplication];
    id display = [NSClassFromString(@"NSDisplay") currentDisplay];
    NSString *backend = NSStringFromClass([display class]);
    BOOL markerOnly = strcmp(mode, "marker") == 0;
    if (!markerOnly && [backend rangeOfString: @"Wayland"].location == NSNotFound) {
        printf("SKIP backend=%s\n", [backend UTF8String]);
        RemoveState();
        return 2;
    }

    ProbeDelegate *delegate = [[ProbeDelegate alloc] init];
    [delegate setSeconds: seconds];
    [delegate setMarkerOnly: markerOnly];
    [NSApp setDelegate: delegate];
    [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];

    if (strcmp(mode, "restore") == 0) {
        [delegate setRestoredWindows: restoredWindows];
    } else {
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 240, 120)
                                                      styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                        backing: NSBackingStoreBuffered
                                                          defer: YES];
        [window setIdentifier: TestWindowIdentifier];
        [window setRestorable: YES];
        [window setTitle: strcmp(mode, "color") == 0 ? @"color-test" : @"session-test"];
        if (strcmp(mode, "color") == 0)
            [window setColorSpace: [NSColorSpace displayP3ColorSpace]];
        [delegate setWindow: window];
        [window release];
    }
    [delegate showWindows];
    [delegate run];
    int failures = [delegate failures];
    [delegate release];
    return failures == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: color-session-probe <color|launch|restore|recover|marker> <seconds>\n");
        return 2;
    }
    const char *mode = argv[1];
    if (strcmp(mode, "color") != 0 && strcmp(mode, "launch") != 0 &&
        strcmp(mode, "restore") != 0 && strcmp(mode, "recover") != 0 && strcmp(mode, "marker") != 0) {
        fprintf(stderr, "unknown mode %s\n", mode);
        return 2;
    }
    @autoreleasepool {
        NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
        if ([identifier isEqualToString: TestBundleID])
            return RunBundled(mode, atof(argv[2]));
        NSString *copy = MakeBundle();
        if (copy == nil) {
            fprintf(stderr, "cannot make the test bundle\n");
            return 2;
        }
        char *args[] = {(char *) [copy fileSystemRepresentation], (char *) mode, argv[2], NULL};
        pid_t pid;
        if (posix_spawn(&pid, args[0], NULL, NULL, args, environ) != 0) {
            fprintf(stderr, "cannot run the bundled copy\n");
            return 2;
        }
        int status = 0;
        waitpid(pid, &status, 0);
        NSString *bundle = [[[copy stringByDeletingLastPathComponent]
                             stringByDeletingLastPathComponent]
                            stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] removeItemAtPath: bundle error: NULL];
        return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    }
}
