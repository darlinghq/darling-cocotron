// Copyright (C) 2026 Lubos Dolezel
//
// -[NSView animator] (NSAnimatablePropertyContainer) returns a proxy for the view: messages sent through it reach
// the view, and with no animation group a property change made through it takes effect on the view at once.
// NSAnimationContext groups: the changes block runs, then the completion handler runs once (also when it is set on
// the context of a beginGrouping/endGrouping pair), after the changes were made. The contexts nest.
// macOS 26.7.3 (black-box, x86_64, from an ssh session without a display): -animator returns an instance of a
// private proxy class (isProxy is YES, it is not the view, isKindOfClass: NSView is YES). Only that part could be
// observed there: the effects of changes through the proxy and the group completion depend on animating on a
// display, which the session lacked, so the checks of effects and of completion follow the documented contract
// (the proxy acts as the receiver, a group runs its completion handler when it is over) and Darling's choice of
// applying changes at once.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void spin(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: end];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        NSView *host = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
        [window setContentView: host];
        [window orderFront: nil];
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        [host addSubview: view];

        // The proxy.
        id animator = [view animator];
        CHECK(animator != nil);
        CHECK(animator != view);
        CHECK([animator isKindOfClass: [NSView class]]);
        CHECK([animator respondsToSelector: @selector(setAlphaValue:)]);

        // Changes through it, with no group: arguments and results of struct, double and BOOL type.
        [animator setFrame: NSMakeRect(1, 2, 30, 40)];
        CHECK(NSEqualRects([view frame], NSMakeRect(1, 2, 30, 40)));
        NSRect viaProxy = [animator frame];
        CHECK(NSEqualRects(viaProxy, NSMakeRect(1, 2, 30, 40)));
        [animator setAlphaValue: 0.5];
        CHECK([view alphaValue] == 0.5);
        CHECK([animator alphaValue] == 0.5);
        [animator setHidden: YES];
        CHECK([view isHidden]);
        CHECK([animator isHidden]);
        [animator setFrameOrigin: NSMakePoint(7, 8)];
        CHECK(NSEqualPoints([view frame].origin, NSMakePoint(7, 8)));

        // Subclasses of views, as an application's scroll view or effect view are.
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        [host addSubview: scroll];
        [[scroll animator] setFrame: NSMakeRect(3, 3, 60, 60)];
        CHECK(NSEqualRects([scroll frame], NSMakeRect(3, 3, 60, 60)));
        NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        [host addSubview: effect];
        [[effect animator] setAlphaValue: 0.25];
        CHECK([effect alphaValue] == 0.25);
        CHECK([[view animator] animations] == [view animations]);

        // A group: the changes are made, then the completion handler runs once.
        __block int completions = 0;
        __block BOOL changesRan = NO;
        __block CGFloat widthAtCompletion = 0;
        [NSAnimationContext runAnimationGroup: ^(NSAnimationContext *context) {
            [[view animator] setFrame: NSMakeRect(5, 5, 60, 60)];
            changesRan = YES;
        } completionHandler: ^{
            completions++;
            widthAtCompletion = [view frame].size.width;
        }];
        spin(0.6);
        CHECK(changesRan);
        CHECK(completions == 1);
        CHECK(widthAtCompletion == 60);
        CHECK([view frame].size.width == 60);

        // A group without a completion handler.
        [NSAnimationContext runAnimationGroup: ^(NSAnimationContext *context) {
            [[view animator] setAlphaValue: 0.75];
        }];
        spin(0.3);
        CHECK([view alphaValue] == 0.75);

        // beginGrouping/endGrouping with the handler set on the context, nested.
        __block int outerDone = 0, innerDone = 0;
        [NSAnimationContext beginGrouping];
        NSAnimationContext *outer = [NSAnimationContext currentContext];
        [outer setCompletionHandler: ^{ outerDone++; }];
        [NSAnimationContext beginGrouping];
        NSAnimationContext *inner = [NSAnimationContext currentContext];
        CHECK(inner != outer);
        [inner setCompletionHandler: ^{ innerDone++; }];
        [[view animator] setFrame: NSMakeRect(1, 1, 11, 11)];
        [NSAnimationContext endGrouping];
        spin(0.4);
        CHECK(innerDone == 1);
        CHECK(outerDone == 0);
        CHECK([NSAnimationContext currentContext] == outer);
        [NSAnimationContext endGrouping];
        spin(0.4);
        CHECK(outerDone == 1);
        CHECK(innerDone == 1);
        CHECK([view frame].size.width == 11);
        CHECK([[NSAnimationContext currentContext] completionHandler] == nil);
    }
    puts(failures ? "FAIL" : "PASS");
    return failures != 0;
}
