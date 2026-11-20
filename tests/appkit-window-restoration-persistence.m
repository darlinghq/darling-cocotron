// Copyright (C) 2026 Lubos Dolezel
//
// Persistent window state restoration: windows kept at quit are recreated at the next launch.
// Expected values are from black-box runs of the same scenarios on macOS 26.7.3 (x86_64) and
// Mac OS X 10.14.4 (i386); this test passes on both.
//
// The test is its own test application. Run without arguments it builds a throw-away
// application bundle (a copy of itself with an Info.plist and a bundle identifier) in the
// temporary directory and launches it several times, each time as a "child" that logs what
// AppKit calls, and checks the logs. A child (-child create|check) creates windows or only
// observes the launch, then quits through -[NSApplication terminate:].
//  - test_restore: with NSQuitAlwaysKeepsWindows YES, the restorable windows that are open at quit
//    are saved; at the next launch application:didDecodeRestorableState: comes first, then
//    +restoreWindowWithIdentifier:state:completionHandler: of the restoration class of each
//    saved window in the order they were saved, all between applicationWillFinishLaunching: and
//    applicationDidFinishLaunching:. After applicationDidFinishLaunching: the windows receive
//    their state (window:didDecodeRestorableState:, then -restoreStateWithCoder: of the views
//    with an identifier that invalidated their state), the last saved first, then
//    NSApplicationDidFinishRestoringWindowsNotification follows. The frame is restored.
//    A window without a restoration class is encoded but not restored, a window that is not
//    restorable is not encoded.
//  - the state is discarded when the application quits without NSQuitAlwaysKeepsWindows (the
//    default), so the launch after that restores nothing; a launch without anything to restore
//    posts NSApplicationDidFinishRestoringWindowsNotification before
//    applicationDidFinishLaunching:.
//  - ApplePersistenceIgnoreState YES: nothing is restored, the saved state is left untouched.
//  - closed windows are not saved; a state with only application state is delivered to the
//    delegate.
// Usage: appkit-window-restoration-persistence
// Build: clang -framework AppKit appkit-window-restoration-persistence.m (no ARC)
#import <AppKit/AppKit.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static FILE *logFile;
#define LOG(...) do { fprintf(logFile, __VA_ARGS__); fputc('\n', logFile); fflush(logFile); } while (0)
#define S(x) ([x length] ? [[x description] UTF8String] : "(nil)")

@interface Probe : NSView {
    NSString *_foo, *_bar;
}
@property (copy) NSString *foo, *bar;
@end
@implementation Probe
@synthesize foo = _foo, bar = _bar;
- (void) encodeRestorableStateWithCoder: (NSCoder *) coder {
    LOG("viewEncode %s", S(_foo));
    [super encodeRestorableStateWithCoder: coder];
    [coder encodeObject: _bar forKey: @"bar"];
}
- (void) restoreStateWithCoder: (NSCoder *) coder {
    [super restoreStateWithCoder: coder];
    self.bar = [coder decodeObjectOfClass: [NSString class] forKey: @"bar"];
    LOG("viewRestore bar=%s", S(_bar));
}
@end

@interface WindowDelegate : NSObject <NSWindowDelegate>
@end
@implementation WindowDelegate
- (void) window: (NSWindow *) window willEncodeRestorableState: (NSCoder *) state {
    LOG("windowEncode %s", S([window identifier]));
    [state encodeObject: @"wd-state" forKey: @"wdelegate"];
}
- (void) window: (NSWindow *) window didDecodeRestorableState: (NSCoder *) state {
    LOG("windowDecode %s wdelegate=%s", S([window identifier]),
        S([state decodeObjectOfClass: [NSString class] forKey: @"wdelegate"]));
}
@end
static WindowDelegate *windowDelegate;

static NSWindow *makeWindow(NSString *identifier, int index, BOOL restorable, Class restorationClass, BOOL fresh);

@interface Restorer : NSObject <NSWindowRestoration>
@end
@implementation Restorer
+ (void) restoreWindowWithIdentifier: (NSString *) identifier state: (NSCoder *) state
                   completionHandler: (void (^)(NSWindow *, NSError *)) handler {
    LOG("restore %s", S(identifier));
    // The window is made anew; its state is applied after launching.
    NSWindow *window = makeWindow(identifier, 5, YES, self, YES);
    handler(window, nil);
    LOG("restored %s", S(identifier));
}
@end

static NSWindow *makeWindow(NSString *identifier, int index, BOOL restorable, Class restorationClass, BOOL fresh) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100 + 70 * index, 300 - 40 * index, 220, 120)
                                                   styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setReleasedWhenClosed: NO];
    [window setTitle: identifier ? identifier : @"none"];
    if (identifier)
        [window setIdentifier: identifier];
    [window setRestorable: restorable];
    [window setRestorationClass: restorationClass];
    [window setDelegate: windowDelegate];
    Probe *view = [[Probe alloc] initWithFrame: NSMakeRect(0, 0, 220, 120)];
    NSString *suffix = identifier ? identifier : @"none";
    view.foo = fresh ? @"fresh" : [@"foo-" stringByAppendingString: suffix];
    view.bar = fresh ? @"fresh" : [@"bar-" stringByAppendingString: suffix];
    [view setIdentifier: [@"v-" stringByAppendingString: suffix]];
    [window setContentView: view];
    [window makeKeyAndOrderFront: nil];
    return window;
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation AppDelegate
- (void) applicationWillFinishLaunching: (NSNotification *) n {
    LOG("willFinish windows=%d", (int) [[NSApp windows] count]);
}
- (void) applicationDidFinishLaunching: (NSNotification *) n {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *child = [defaults stringForKey: @"child"];
    LOG("didFinish windows=%d", (int) [[NSApp windows] count]);
    NSString *act = [defaults stringForKey: @"act"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        if ([child isEqualToString: @"create"]) {
            NSWindow *a = makeWindow(@"winA", 0, YES, [Restorer class], NO);
            NSWindow *b = makeWindow(@"winB", 1, YES, Nil, NO);
            NSWindow *c = makeWindow(@"winC", 2, NO, [Restorer class], NO);
            NSWindow *e = makeWindow(nil, 3, YES, [Restorer class], NO);
            NSArray *windows = [NSArray arrayWithObjects: a, b, c, e, nil];
            for (NSWindow *w in windows) {
                [w invalidateRestorableState];
                [(NSView *) [w contentView] invalidateRestorableState];
                LOG("created %s frame=%s", S([w title]), [NSStringFromRect([w frame]) UTF8String]);
            }
            if ([act isEqualToString: @"close-one"])
                [a close];
            if ([act isEqualToString: @"close-all"])
                for (NSWindow *w in windows)
                    [w close];
        } else {
            for (NSWindow *w in [NSApp windows]) {
                Probe *view = (Probe *) [w contentView];
                LOG("window %s frame=%s restorable=%d class=%s foo=%s bar=%s", S([w identifier]),
                    [NSStringFromRect([w frame]) UTF8String], [w isRestorable],
                    [w restorationClass] ? [NSStringFromClass([w restorationClass]) UTF8String] : "Nil", S(view.foo), S(view.bar));
            }
        }
        LOG("terminate");
        [NSApp terminate: nil];
    });
}
- (void) application: (NSApplication *) app willEncodeRestorableState: (NSCoder *) coder {
    LOG("appEncode");
    [coder encodeObject: @"app-state" forKey: @"appkey"];
}
- (void) application: (NSApplication *) app didDecodeRestorableState: (NSCoder *) coder {
    LOG("appDecode appkey=%s", S([coder decodeObjectOfClass: [NSString class] forKey: @"appkey"]));
}
- (BOOL) applicationSupportsSecureRestorableState: (NSApplication *) app {
    return YES;
}
- (NSApplicationTerminateReply) applicationShouldTerminate: (NSApplication *) app {
    LOG("shouldTerminate");
    return NSTerminateNow;
}
- (void) applicationWillTerminate: (NSNotification *) n {
    LOG("willTerminate");
}
@end

static int runChild(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    logFile = fopen([[defaults stringForKey: @"log"] UTF8String], "a");
    if (logFile == NULL)
        return 2;
    LOG("main %s", S([defaults stringForKey: @"child"]));
    [[NSNotificationCenter defaultCenter] addObserverForName: NSApplicationDidFinishRestoringWindowsNotification
                                                      object: nil
                                                       queue: nil
                                                  usingBlock: ^(NSNotification *n) {
        LOG("finishedRestoring windows=%d", (int) [[NSApp windows] count]);
    }];
    windowDelegate = [WindowDelegate new];
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy: NSApplicationActivationPolicyRegular];
    [app setDelegate: [AppDelegate new]];
    [app run];
    return 0;
}

// ---- the driver ----

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *bundleExecutable;
static NSString *logPath;

// Launches the test application with the given arguments and returns the log lines it wrote.
static NSArray *launchChild(NSArray *arguments) {
    [[NSFileManager defaultManager] removeItemAtPath: logPath error: NULL];
    NSMutableArray *args = [NSMutableArray arrayWithObject: bundleExecutable];
    [args addObjectsFromArray: arguments];
    [args addObjectsFromArray: [NSArray arrayWithObjects: @"-log", logPath, nil]];
    char *argv[32];
    int n = 0;
    for (NSString *a in args)
        argv[n++] = (char *) [a UTF8String];
    argv[n] = NULL;
    pid_t pid;
    if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) != 0) {
        fprintf(stderr, "FAIL: cannot launch %s\n", argv[0]);
        failures++;
        return nil;
    }
    int status = 0, waited = 0;
    for (int i = 0; i < 600 && !waited; i++) {
        waited = waitpid(pid, &status, WNOHANG) == pid;
        if (!waited)
            usleep(100000);
    }
    if (!waited) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
        failures++;
    }
    NSString *log = [NSString stringWithContentsOfFile: logPath encoding: NSUTF8StringEncoding error: NULL];
    if (!waited)
        fprintf(stderr, "FAIL: %s did not quit, log:\n%s\n", [[arguments componentsJoinedByString: @" "] UTF8String],
                [log UTF8String]);
    return log ? [[log stringByTrimmingCharactersInSet: [NSCharacterSet newlineCharacterSet]]
                         componentsSeparatedByString: @"\n"]
               : [NSArray array];
}

static NSString *frameLine(NSArray *log, NSString *title) {
    NSString *prefix = [NSString stringWithFormat: @"created %@ frame=", title];
    for (NSString *line in log)
        if ([line hasPrefix: prefix])
            return [line substringFromIndex: [prefix length]];
    return nil;
}

static NSArray *lines(NSArray *log, NSString *prefix) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *line in log)
        if ([line hasPrefix: prefix])
            [result addObject: line];
    return result;
}

static BOOL logIs(NSArray *log, NSArray *expected) {
    if ([log isEqualToArray: expected])
        return YES;
    fprintf(stderr, "  log:\n    %s\n  expected:\n    %s\n", [[log componentsJoinedByString: @"\n    "] UTF8String],
            [[expected componentsJoinedByString: @"\n    "] UTF8String]);
    return NO;
}

#define KEEP @"-NSQuitAlwaysKeepsWindows", @"YES"

static void test_restore(void) {
    NSArray *log = launchChild([NSArray arrayWithObjects: @"-child", @"create", KEEP, nil]);
    // A launch without saved state: the notification comes before applicationDidFinishLaunching:.
    NSArray *expected = [NSArray arrayWithObjects: @"main create", @"willFinish windows=0", @"finishedRestoring windows=0",
                                                   @"didFinish windows=0", nil];
    CHECK(logIs([log subarrayWithRange: NSMakeRange(0, MIN([log count], [expected count]))], expected));
    NSString *frameA = frameLine(log, @"winA"), *frameNone = frameLine(log, @"none");
    CHECK(frameA != nil && frameNone != nil);
    // At quit the restorable windows are encoded (windows first, each with the views that
    // invalidated their state, then the application), a window that is not restorable is not.
    NSArray *quit = [log subarrayWithRange: NSMakeRange(MIN([log count], 8), [log count] - MIN([log count], 8))];
    expected = [NSArray arrayWithObjects: @"terminate", @"windowEncode winA", @"viewEncode foo-winA", @"windowEncode winB",
                                          @"viewEncode foo-winB", @"windowEncode (nil)", @"viewEncode foo-none", @"appEncode",
                                          @"shouldTerminate", @"willTerminate", nil];
    CHECK(logIs(quit, expected));

    // The next launch restores the saved windows; it quits without NSQuitAlwaysKeepsWindows.
    log = launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);
    expected = [NSArray arrayWithObjects:
            @"main check", @"willFinish windows=0", @"appDecode appkey=app-state",
            @"restore winA", @"restored winA", @"restore (nil)", @"restored (nil)", @"didFinish windows=2",
            @"windowDecode (nil) wdelegate=wd-state", @"viewRestore bar=bar-none",
            @"windowDecode winA wdelegate=wd-state", @"viewRestore bar=bar-winA", @"finishedRestoring windows=2",
            [NSString stringWithFormat: @"window winA frame=%@ restorable=1 class=Restorer foo=fresh bar=bar-winA", frameA],
            [NSString stringWithFormat: @"window (nil) frame=%@ restorable=1 class=Restorer foo=fresh bar=bar-none", frameNone],
            @"terminate", @"shouldTerminate", @"willTerminate", nil];
    CHECK(logIs(log, expected));

    // That launch quit without NSQuitAlwaysKeepsWindows: the state is gone.
    log = launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);
    expected = [NSArray arrayWithObjects: @"main check", @"willFinish windows=0", @"finishedRestoring windows=0",
                                          @"didFinish windows=0", @"terminate", @"shouldTerminate", @"willTerminate", nil];
    CHECK(logIs(log, expected));
}

static void test_default_does_not_keep(void) {
    launchChild([NSArray arrayWithObjects: @"-child", @"create", nil]);
    NSArray *log = launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);
    CHECK([lines(log, @"restore ") count] == 0 && [lines(log, @"window ") count] == 0);
    CHECK([lines(log, @"appDecode") count] == 0);
}

static void test_ignore_state(void) {
    launchChild([NSArray arrayWithObjects: @"-child", @"create", KEEP, nil]);
    NSArray *log = launchChild([NSArray arrayWithObjects: @"-child", @"check", @"-ApplePersistenceIgnoreState", @"YES", nil]);
    NSArray *expected = [NSArray arrayWithObjects: @"main check", @"willFinish windows=0", @"finishedRestoring windows=0",
                                                   @"didFinish windows=0", @"terminate", @"shouldTerminate", @"willTerminate", nil];
    CHECK(logIs(log, expected));
    // The ignored state was left alone.
    log = launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);
    CHECK([lines(log, @"restore ") count] == 2);
    // (That launch quit without keeping, so the state is gone again.)
}

static void test_closed_windows_are_not_saved(void) {
    launchChild([NSArray arrayWithObjects: @"-child", @"create", @"-act", @"close-one", KEEP, nil]);
    NSArray *log = launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);
    CHECK([lines(log, @"restore ") count] == 1);
    CHECK([lines(log, @"restore (nil)") count] == 1);
    CHECK([lines(log, @"window winA") count] == 0);

    // All windows closed: nothing is restored, the application state still is.
    launchChild([NSArray arrayWithObjects: @"-child", @"create", @"-act", @"close-all", KEEP, nil]);
    log = launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);
    NSArray *expected = [NSArray arrayWithObjects: @"main check", @"willFinish windows=0", @"appDecode appkey=app-state",
                                                   @"finishedRestoring windows=0", @"didFinish windows=0", @"terminate",
                                                   @"shouldTerminate", @"willTerminate", nil];
    CHECK(logIs(log, expected));
}

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if ([[NSUserDefaults standardUserDefaults] stringForKey: @"child"])
        return runChild();

    char self[4096];
    uint32_t size = sizeof(self);
    if (_NSGetExecutablePath(self, &size) != 0)
        return 2;
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent: @"wrp.XXXXXX"];
    char *templ = strdup([directory fileSystemRepresentation]);
    if (mkdtemp(templ) == NULL)
        return 2;
    directory = [NSString stringWithUTF8String: templ];
    free(templ);
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *macos = [directory stringByAppendingPathComponent: @"Restore.app/Contents/MacOS"];
    [files createDirectoryAtPath: macos withIntermediateDirectories: YES attributes: nil error: NULL];
    bundleExecutable = [macos stringByAppendingPathComponent: @"restore"];
    CHECK([files copyItemAtPath: [NSString stringWithUTF8String: self] toPath: bundleExecutable error: NULL]);
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
            @"org.darlinghq.test.window-restoration-persistence", @"CFBundleIdentifier",
            @"restore", @"CFBundleExecutable", @"restore", @"CFBundleName", @"APPL", @"CFBundlePackageType",
            @"1", @"CFBundleVersion", @"NSApplication", @"NSPrincipalClass", nil];
    CHECK([info writeToFile: [directory stringByAppendingPathComponent: @"Restore.app/Contents/Info.plist"] atomically: NO]);
    logPath = [directory stringByAppendingPathComponent: @"log"];

    // Starts from a launch that keeps nothing, which discards state left by an earlier run.
    launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);
    test_restore();
    test_default_does_not_keep();
    test_ignore_state();
    test_closed_windows_are_not_saved();
    // Leaves no state behind.
    launchChild([NSArray arrayWithObjects: @"-child", @"check", nil]);

    [files removeItemAtPath: directory error: NULL];
    printf(failures ? "FAIL\n" : "PASS\n");
    [pool drain];
    return failures ? 1 : 0;
}
