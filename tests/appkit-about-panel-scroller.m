// Copyright (C) 2026 Lubos Dolezel
//
// The scroller of the credits text in the standard About panel (-orderFrontStandardAboutPanel:), which
// scrolls with the wheel but must also scroll when the user drags its knob or clicks its track, for the
// harnesses appkit-about-panel-scroller-x11.sh and -wayland.sh. The panel shows Credits.rtf from the main
// bundle's resources; the harness puts a long one next to the executable (a bare executable's main bundle
// is its directory).
//   appkit-about-panel-scroller <seconds>
// prints "READY" once the panel is shown, then
//   scroller <x> <y> <w> <h> <knob y> <knob h>    points from the top left corner of the panel's frame
//   enabled <0|1> proportion <p>
// and "VALUE <v>" whenever the scroller's value changes. The harness presses the knob and drags it, then
// clicks in the track below the knob, and checks that VALUE grew each time.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static NSScrollView *findScrollView(NSView *view) {
    if ([view isKindOfClass: [NSScrollView class]])
        return (NSScrollView *) view;
    for (NSView *sub in [view subviews]) {
        NSScrollView *found = findScrollView(sub);
        if (found)
            return found;
    }
    return nil;
}

@interface Watcher : NSObject {
    NSWindow *_panel;
    NSScroller *_scroller;
    double _last;
}
- (id) initWithPanel: (NSWindow *) panel scroller: (NSScroller *) scroller;
- (void) poll: (NSTimer *) timer;
@end
@implementation Watcher
- (id) initWithPanel: (NSWindow *) panel scroller: (NSScroller *) scroller {
    if ((self = [super init])) {
        _panel = panel;
        _scroller = scroller;
        _last = -1;
    }
    return self;
}
- (void) poll: (NSTimer *) timer {
    double v = [_scroller doubleValue];
    if (v != _last) {
        _last = v;
        printf("VALUE %.4f\n", v);
        fflush(stdout);
    }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 30;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        [NSApp orderFrontStandardAboutPanel: nil];
        [NSApp activateIgnoringOtherApps: YES];

        NSWindow *panel = nil;
        for (NSWindow *w in [NSApp windows])
            if ([w isVisible] && findScrollView([w contentView]))
                panel = w;
        if (!panel) {
            printf("FAIL: no panel with a scroll view\n");
            return 1;
        }
        [panel setTitle: @"about-panel"];  // so that the harnesses find its window
        // Let the panel settle: layout and display happen on the first turns of the run loop.
        for (int i = 0; i < 20; i++)
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

        NSScrollView *sv = findScrollView([panel contentView]);
        NSScroller *scroller = [sv verticalScroller];
        NSRect r = [scroller convertRect: [scroller bounds] toView: nil];
        NSRect knob = [scroller convertRect: [scroller rectForPart: NSScrollerKnob] toView: nil];
        CGFloat top = [panel frame].size.height;
        printf("scroller %d %d %d %d %d %d\n", (int) r.origin.x, (int) (top - NSMaxY(r)), (int) r.size.width,
               (int) r.size.height, (int) (top - NSMaxY(knob)), (int) knob.size.height);
        printf("enabled %d proportion %.3f\n", (int) [scroller isEnabled], [scroller knobProportion]);
        printf("READY\n");
        fflush(stdout);

        Watcher *watcher = [[Watcher alloc] initWithPanel: panel scroller: scroller];
        [NSTimer scheduledTimerWithTimeInterval: 0.05 target: watcher selector: @selector(poll:) userInfo: nil
                                        repeats: YES];
        // Dispatch events as the application's run loop does: a bare run loop leaves them queued.
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
        while ([end timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event)
                [NSApp sendEvent: event];
        }
    }
    return 0;
}
