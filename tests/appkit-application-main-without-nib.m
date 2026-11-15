// Link with candidate AppKit; no display is needed.
//
// NSApplicationMain loads the main nib named by the bundle's NSMainNibFile key. An app that declares
// none (a SwiftUI app, or one that builds its UI in code) has no main nib, so NSApplicationMain must
// start the run loop without trying to load one. This test executable has no bundle and so no
// NSMainNibFile either.
//
// Loading a nil nib name used to push a nil path onto the nib-path stack with -addObject:. Darling's
// own NSMutableArray lets that through, so a plain run only sees it by recording the call; the shared
// cache's NSMutableArray raises "object cannot be nil" and the app dies at launch.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static BOOL loadedNibNamedNil;
static BOOL pushedNilNibPath;
static IMP originalLoadNibNamed;
static IMP originalPushNibPath;

static BOOL recordLoadNibNamed(id self, SEL _cmd, NSString *name, id owner) {
    if (name == nil) loadedNibNamedNil = YES;
    return ((BOOL (*)(id, SEL, NSString *, id)) originalLoadNibNamed)(self, _cmd, name, owner);
}

static void recordPushNibPath(id self, SEL _cmd, id path) {
    if (path == nil) pushedNilNibPath = YES;
    ((void (*)(id, SEL, id)) originalPushNibPath)(self, _cmd, path);
}

static void stalled(int sig) {
    static const char message[] = "FAIL: NSApplicationMain did not return after the app was stopped\n";
    write(STDERR_FILENO, message, sizeof message - 1);
    _exit(1);
}

@interface Stopper : NSObject
@end
@implementation Stopper
// Stopping takes effect once an event is dispatched, so post a dummy one after it.
- (void) applicationDidFinishLaunching: (NSNotification *) note {
    [NSApp stop: nil];
    [NSApp postEvent: [NSEvent otherEventWithType: NSApplicationDefined location: NSZeroPoint
                                     modifierFlags: 0 timestamp: 0 windowNumber: 0
                                           context: nil subtype: 0 data1: 0 data2: 0]
             atStart: YES];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        expect([[[NSBundle mainBundle] infoDictionary] objectForKey: @"NSMainNibFile"] == nil,
               @"the test executable declares no NSMainNibFile");

        Method load = class_getClassMethod([NSBundle class], @selector(loadNibNamed:owner:));
        Method push = class_getClassMethod([NSBundle class], @selector(pushNibPath:));
        expect(load != NULL && push != NULL, @"NSBundle has the nib-loading class methods");
        originalLoadNibNamed = method_setImplementation(load, (IMP) recordLoadNibNamed);
        originalPushNibPath = method_setImplementation(push, (IMP) recordPushNibPath);

        [NSApplication sharedApplication];
        Stopper *stopper = [[Stopper new] autorelease];
        [NSApp setDelegate: stopper];

        char logPath[] = "/tmp/appkit-main-without-nib.XXXXXX";
        int logFd = mkstemp(logPath);
        expect(logFd >= 0, @"a temporary file for the app's log");
        fflush(stderr);
        int savedStderr = dup(STDERR_FILENO);
        dup2(logFd, STDERR_FILENO);

        signal(SIGALRM, stalled);
        alarm(20);
        NSString *raised = nil;
        int status = -1;
        @try {
            status = NSApplicationMain(1, argv);
        } @catch (NSException *exception) {
            raised = [NSString stringWithFormat: @"%@: %@", [exception name], [exception reason]];
        }
        alarm(0);

        fflush(stderr);
        dup2(savedStderr, STDERR_FILENO);
        close(savedStderr);
        NSData *logData = [NSData dataWithContentsOfFile: [NSString stringWithUTF8String: logPath]];
        NSString *log = [[[NSString alloc] initWithData: logData encoding: NSUTF8StringEncoding] autorelease];
        close(logFd);
        unlink(logPath);

        expect(raised == nil, [NSString stringWithFormat: @"NSApplicationMain raised %@", raised]);
        expect(!loadedNibNamedNil, @"NSApplicationMain asked NSBundle to load a nib with a nil name");
        expect(!pushedNilNibPath, @"a nil nib path was pushed onto the nib-path stack");
        expect(status == 0, [NSString stringWithFormat: @"NSApplicationMain returned %d", status]);
        expect([log rangeOfString: @"Unable to load main nib file"].location == NSNotFound,
               [NSString stringWithFormat: @"NSApplicationMain tried to load a nib the app does not declare: %@", log]);
        NSLog(@"PASS: NSApplicationMain starts an app that declares no main nib");
    }
    return 0;
}
