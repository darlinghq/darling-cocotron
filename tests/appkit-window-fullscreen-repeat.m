/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// -[NSWindow toggleFullScreen:] called over and over on one window: every request
// must be confirmed (Did enter / Did exit notification, once each), the style mask
// must follow, and the window must come back to the size it had before.
// Run on the X11 backend or, with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY set, on
// a Wayland compositor (a headless sway or KWin). Usage: appkit-window-fullscreen-repeat [rounds [gap-ms]]
// gap: pause in milliseconds between a Did notification and the next request.

static NSMutableArray *log_;
static int failures;

static void expectTrue(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Rec : NSObject
@end
@implementation Rec
- (void) note: (NSNotification *) n { [log_ addObject: n.name]; }
@end

static BOOL waitFor(NSString *name, NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0) {
        if ([log_ containsObject: name])
            return YES;
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]];
    }
    return NO;
}

static void spin(NSTimeInterval s) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: s]];
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 10;
    int gap = argc > 2 ? atoi(argv[2]) : 500;
    @autoreleasepool {
        [NSApplication sharedApplication];
        log_ = [NSMutableArray array];
        NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 640, 400)
                styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable
                  backing: NSBackingStoreBuffered defer: NO];
        w.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        Rec *rec = [Rec new];
        for (NSNotificationName n in @[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
                                       NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification])
            [[NSNotificationCenter defaultCenter] addObserver: rec selector: @selector(note:) name: n object: w];
        [w makeKeyAndOrderFront: nil];
        spin(1.5);
        NSSize before = [w contentRectForFrameRect: w.frame].size;
        NSSize screen = [[NSScreen mainScreen] frame].size;
        printf("start content=%gx%g screen=%gx%g\n", before.width, before.height, screen.width, screen.height);
        int enterOk = 0, exitOk = 0, maskOk = 0, sizeOk = 0, onceOk = 0;
        for (int i = 0; i < rounds; i++) {
            [log_ removeAllObjects];
            [w toggleFullScreen: nil];
            BOOL e = waitFor(NSWindowDidEnterFullScreenNotification, 8);
            spin(0.3);
            BOOL m = (w.styleMask & NSWindowStyleMaskFullScreen) != 0;
            NSSize fs = [w frame].size;
            int enters = 0;
            for (NSString *s in log_) if ([s isEqualToString: NSWindowDidEnterFullScreenNotification]) enters++;
            BOOL big = fs.width >= screen.width - 1 && fs.height >= screen.height - 1;
            if (e) enterOk++;
            if (m) maskOk++;
            if (enters == 1) onceOk++;
            printf("round %d enter: did=%d mask=%d frame=%gx%g (full=%d) log=%s\n", i, e, m, fs.width, fs.height, big,
                   [[log_ componentsJoinedByString: @","] UTF8String]);
            if (!e) { // the request was dropped or never confirmed: do not toggle on blindly
                spin(4);
                printf("  late log=%s\n", [[log_ componentsJoinedByString: @","] UTF8String]);
            }
            if (gap > 0) spin(gap / 1000.0);
            [log_ removeAllObjects];
            [w toggleFullScreen: nil];
            BOOL x = waitFor(NSWindowDidExitFullScreenNotification, 8);
            spin(0.3);
            BOOL mm = (w.styleMask & NSWindowStyleMaskFullScreen) == 0;
            NSSize after = [w contentRectForFrameRect: w.frame].size;
            if (x) exitOk++;
            if (mm) maskOk++;
            if (after.width == before.width && after.height == before.height) sizeOk++;
            printf("round %d exit: did=%d mask=%d content=%gx%g log=%s\n", i, x, mm, after.width, after.height,
                   [[log_ componentsJoinedByString: @","] UTF8String]);
            if (gap > 0) spin(gap / 1000.0);
        }
        char buf[128];
        snprintf(buf, sizeof buf, "all %d enters confirmed (%d)", rounds, enterOk); expectTrue(enterOk == rounds, buf);
        snprintf(buf, sizeof buf, "all %d exits confirmed (%d)", rounds, exitOk); expectTrue(exitOk == rounds, buf);
        snprintf(buf, sizeof buf, "style mask followed every transition (%d of %d)", maskOk, 2 * rounds); expectTrue(maskOk == 2 * rounds, buf);
        snprintf(buf, sizeof buf, "windowed size restored every time (%d of %d)", sizeOk, rounds); expectTrue(sizeOk == rounds, buf);
        snprintf(buf, sizeof buf, "one Did enter per request (%d of %d)", onceOk, rounds); expectTrue(onceOk == rounds, buf);
        [w close];
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
