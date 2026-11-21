// Copyright (C) 2026 Lubos Dolezel
//
// NSViewController -viewWillAppear, -viewDidAppear, -viewWillDisappear and -viewDidDisappear follow whether the
// controller's view is in a visible window and not hidden, however it got there: the window's content view
// controller, a controller's view put into a window as the content view or as a subview, a child controller,
// split view items. Expected sequences observed black-box on macOS 26.7.3 (x86_64): the will call comes before the
// change (window not yet visible or view not yet in the window), the did call after; a controller and its children
// get all will calls before the did calls, parents first; ordering a window out and closing it, removing the view,
// hiding the view and replacing the content controller send the disappear pair; a view that was never in a
// visible window sends nothing; showing a window again sends the appear pair again.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static int failures;
static NSMutableArray *events;

@interface VC : NSViewController {
    NSString *tag;
}
- (NSString *) tag;
- (void) setTag: (NSString *) value;
@end

@implementation VC
- (NSString *) tag {
    return tag;
}
- (void) setTag: (NSString *) value {
    [tag release];
    tag = [value copy];
}
- (void) loadView {
    [self setView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease]];
}
- (void) note: (NSString *) what {
    [events addObject: [NSString stringWithFormat: @"%@ %@ win=%d vis=%d", [self tag], what,
                        [self view].window != nil, [self view].window.isVisible]];
}
- (void) viewWillAppear { [self note: @"willAppear"]; [super viewWillAppear]; }
- (void) viewDidAppear { [self note: @"didAppear"]; [super viewDidAppear]; }
- (void) viewWillDisappear { [self note: @"willDisappear"]; [super viewWillDisappear]; }
- (void) viewDidDisappear { [self note: @"didDisappear"]; [super viewDidDisappear]; }
@end

static VC *mk(NSString *tag) {
    VC *vc = [[[VC alloc] init] autorelease];
    [vc setTag: tag];
    return vc;
}

static NSWindow *makeWindow(void) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 300, 300)
                                              styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
    [w setReleasedWhenClosed: NO];
    return w;
}

static void pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.15]];
}

static void expect(const char *step, NSArray *want) {
    pump();
    if (![events isEqualToArray: want]) {
        failures++;
        fprintf(stderr, "FAIL %s\n  got:\n", step);
        for (NSString *e in events)
            fprintf(stderr, "    %s\n", [e UTF8String]);
        fprintf(stderr, "  want:\n");
        for (NSString *e in want)
            fprintf(stderr, "    %s\n", [e UTF8String]);
    } else {
        printf("PASS %s\n", step);
    }
    [events removeAllObjects];
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        events = [[NSMutableArray alloc] init];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];

        // The window's content view controller
        {
            NSWindow *w = makeWindow();
            w.contentViewController = mk(@"A");
            expect("content controller, window not shown: nothing", @[]);
            [w orderFront: nil];
            expect("orderFront", @[ @"A willAppear win=1 vis=0", @"A didAppear win=1 vis=1" ]);
            [w orderOut: nil];
            expect("orderOut", @[ @"A willDisappear win=1 vis=1", @"A didDisappear win=1 vis=0" ]);
            [w orderFront: nil];
            expect("orderFront again", @[ @"A willAppear win=1 vis=0", @"A didAppear win=1 vis=1" ]);
            [w orderFront: nil];
            expect("orderFront of a visible window: nothing", @[]);
            [w close];
            expect("close", @[ @"A willDisappear win=1 vis=1", @"A didDisappear win=1 vis=0" ]);
        }

        // A controller's view added to and removed from a visible window
        {
            NSWindow *w = makeWindow();
            VC *b = mk(@"B");
            (void) b.view;
            [w orderFront: nil];
            expect("view loaded, not in the window: nothing", @[]);
            [w.contentView addSubview: b.view];
            expect("view added to a visible window", @[ @"B willAppear win=0 vis=0", @"B didAppear win=1 vis=1" ]);
            [b.view removeFromSuperview];
            expect("view removed", @[ @"B willDisappear win=1 vis=1", @"B didDisappear win=0 vis=0" ]);
            [w.contentView addSubview: b.view];
            expect("view added again", @[ @"B willAppear win=0 vis=0", @"B didAppear win=1 vis=1" ]);
            [b.view setHidden: YES];
            expect("view hidden", @[ @"B willDisappear win=1 vis=1", @"B didDisappear win=1 vis=1" ]);
            [b.view setHidden: NO];
            expect("view unhidden", @[ @"B willAppear win=1 vis=1", @"B didAppear win=1 vis=1" ]);
            [w.contentView setHidden: YES];
            expect("a superview hidden", @[ @"B willDisappear win=1 vis=1", @"B didDisappear win=1 vis=1" ]);
            [w.contentView setHidden: NO];
            expect("the superview unhidden", @[ @"B willAppear win=1 vis=1", @"B didAppear win=1 vis=1" ]);
            [w close];
            expect("close", @[ @"B willDisappear win=1 vis=1", @"B didDisappear win=1 vis=0" ]);
        }

        // A view put into a window that is shown later
        {
            NSWindow *w = makeWindow();
            VC *c = mk(@"C");
            [w.contentView addSubview: c.view];
            expect("view added to a window not shown: nothing", @[]);
            [w orderFront: nil];
            expect("orderFront", @[ @"C willAppear win=1 vis=0", @"C didAppear win=1 vis=1" ]);
            [w close];
            expect("close", @[ @"C willDisappear win=1 vis=1", @"C didDisappear win=1 vis=0" ]);
        }

        // A view added hidden to a visible window does not appear until it is shown
        {
            NSWindow *w = makeWindow();
            VC *h = mk(@"H");
            [w orderFront: nil];
            [h.view setHidden: YES];
            [w.contentView addSubview: h.view];
            expect("hidden view added to a visible window: nothing", @[]);
            [h.view setHidden: NO];
            expect("then shown", @[ @"H willAppear win=1 vis=1", @"H didAppear win=1 vis=1" ]);
            [w close];
            expect("close", @[ @"H willDisappear win=1 vis=1", @"H didDisappear win=1 vis=0" ]);
        }

        // Parent and child: all will calls, then all did calls, parent first
        {
            NSWindow *w = makeWindow();
            VC *p = mk(@"P"), *k = mk(@"K");
            [p addChildViewController: k];
            [p.view addSubview: k.view];
            w.contentViewController = p;
            [w orderFront: nil];
            expect("parent and child shown", (@[ @"P willAppear win=1 vis=0", @"K willAppear win=1 vis=0",
                                                  @"P didAppear win=1 vis=1", @"K didAppear win=1 vis=1" ]));
            [w close];
            expect("parent and child closed", (@[ @"P willDisappear win=1 vis=1", @"K willDisappear win=1 vis=1",
                                                   @"P didDisappear win=1 vis=0", @"K didDisappear win=1 vis=0" ]));
        }

        // A child whose view is not in the hierarchy does not appear until it is
        {
            NSWindow *w = makeWindow();
            VC *p = mk(@"P"), *k = mk(@"K");
            [p addChildViewController: k];
            w.contentViewController = p;
            [w orderFront: nil];
            expect("child view not in the window", @[ @"P willAppear win=1 vis=0", @"P didAppear win=1 vis=1" ]);
            [p.view addSubview: k.view];
            expect("child view added later", @[ @"K willAppear win=0 vis=0", @"K didAppear win=1 vis=1" ]);
            [w close];
            expect("close", (@[ @"P willDisappear win=1 vis=1", @"K willDisappear win=1 vis=1",
                                 @"P didDisappear win=1 vis=0", @"K didDisappear win=1 vis=0" ]));
        }

        // Replacing the content controller
        {
            NSWindow *w = makeWindow();
            VC *a = mk(@"A"), *b = mk(@"B");
            w.contentViewController = a;
            [w orderFront: nil];
            [events removeAllObjects];
            w.contentViewController = b;
            expect("content controller replaced", (@[ @"A willDisappear win=1 vis=1", @"A didDisappear win=0 vis=0",
                                                       @"B willAppear win=0 vis=0", @"B didAppear win=1 vis=1" ]));
            [w close];
            expect("close", @[ @"B willDisappear win=1 vis=1", @"B didDisappear win=1 vis=0" ]);
        }

        // A controller's view as the window's content view
        {
            NSWindow *w = makeWindow();
            VC *a = mk(@"A");
            [w setContentView: a.view];
            [w orderFront: nil];
            expect("view as content view", @[ @"A willAppear win=1 vis=0", @"A didAppear win=1 vis=1" ]);
            [w close];
            expect("close", @[ @"A willDisappear win=1 vis=1", @"A didDisappear win=1 vis=0" ]);
        }

        // Split view items
        {
            NSWindow *w = makeWindow();
            NSSplitViewController *sv = [[[NSSplitViewController alloc] init] autorelease];
            VC *a = mk(@"SA"), *b = mk(@"SB");
            [sv addSplitViewItem: [NSSplitViewItem splitViewItemWithViewController: a]];
            [sv addSplitViewItem: [NSSplitViewItem splitViewItemWithViewController: b]];
            w.contentViewController = sv;
            [w orderFront: nil];
            expect("split view controller shown", (@[ @"SA willAppear win=1 vis=0", @"SB willAppear win=1 vis=0",
                                                       @"SA didAppear win=1 vis=1", @"SB didAppear win=1 vis=1" ]));
            [w close];
            expect("close", (@[ @"SA willDisappear win=1 vis=1", @"SB willDisappear win=1 vis=1",
                                 @"SA didDisappear win=1 vis=0", @"SB didDisappear win=1 vis=0" ]));
        }

        // The base implementations exist and do nothing (a subclass calls super)
        {
            NSViewController *plain = [[[NSViewController alloc] init] autorelease];
            [plain viewWillAppear];
            [plain viewDidAppear];
            [plain viewWillDisappear];
            [plain viewDidDisappear];
            printf("PASS base implementations\n");
        }

        if (failures) {
            printf("%d FAILED\n", failures);
            return 1;
        }
        printf("ALL PASSED\n");
    }
    return 0;
}
