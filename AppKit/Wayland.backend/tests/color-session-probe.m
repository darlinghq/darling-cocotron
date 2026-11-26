/*
  Copyright (C) 2026 Lubos Dolezel

  Licensed under the MIT license, the same as the rest of this project.
*/
// Guest side of wayland-color-session.sh. It asks for a P3 window and checks the output description
// that NSScreen reports. The fake compositor checks the per-surface description and alpha mode.
// Usage: color-session-probe color <seconds>
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface ColorProbeDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *_window;
    double _seconds;
    int _failures;
}
- (void) showWindow;
- (void) run;
- (int) failures;
@end

@implementation ColorProbeDelegate

- (BOOL) application: (NSApplication *) application openFiles: (NSArray *) files {
    return YES;
}

- (void) showWindow {
    [_window makeKeyAndOrderFront: nil];
    NSScreen *screen = [NSScreen mainScreen];
    NSColorSpace *space = [screen colorSpace];
    BOOL p3 = [[space localizedName] isEqualToString: @"Display P3"];
    double edr = [screen maximumExtendedDynamicRangeColorComponentValue];
    double potential = [screen maximumPotentialExtendedDynamicRangeColorComponentValue];
    double reference = [screen maximumReferenceExtendedDynamicRangeColorComponentValue];
    printf("SCREEN p3=%d edr=%.2f potential=%.2f reference=%.2f\n", p3, edr, potential, reference);
    fflush(stdout);
    if (!p3 || fabs(edr - 1.97) > 0.01 || fabs(potential - 4.93) > 0.01 ||
        fabs(reference - 4.93) > 0.01)
        _failures++;
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
    printf("PROBE done failures=%d\n", _failures);
    fflush(stdout);
}

- (void) setWindow: (NSWindow *) window {
    [window retain];
    [_window release];
    _window = window;
}

- (void) setSeconds: (double) seconds {
    _seconds = seconds;
}

- (int) failures {
    return _failures;
}

- (void) dealloc {
    [_window release];
    [super dealloc];
}

@end

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: color-session-probe color <seconds>\n");
        return 2;
    }
    if (strcmp(argv[1], "color") != 0) {
        fprintf(stderr, "unknown mode %s\n", argv[1]);
        return 2;
    }
    @autoreleasepool {
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 240, 120)
                                                      styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                        backing: NSBackingStoreBuffered
                                                          defer: YES];
        [window setIdentifier: @"main"];
        [window setRestorable: YES];
        [window setTitle: @"color-test"];
        [window setColorSpace: [NSColorSpace displayP3ColorSpace]];

        [NSApplication sharedApplication];
        id display = [NSClassFromString(@"NSDisplay") currentDisplay];
        NSString *backend = NSStringFromClass([display class]);
        if ([backend rangeOfString: @"Wayland"].location == NSNotFound) {
            printf("SKIP backend=%s\n", [backend UTF8String]);
            [window release];
            return 2;
        }

        ColorProbeDelegate *delegate = [[ColorProbeDelegate alloc] init];
        [delegate setSeconds: atof(argv[2])];
        [delegate setWindow: window];
        [NSApp setDelegate: delegate];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        [delegate showWindow];
        [delegate run];
        int failures = [delegate failures];
        [delegate release];
        [window release];
        return failures == 0 ? 0 : 1;
    }
}
