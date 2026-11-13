// Copyright (C) 2026 Lubos Dolezel
//
// Mouse event numbers, mouse coalescing in the display event queue, and the
// main menu item title. Needs no window server: it drives an NSDisplay's queue
// directly, like tests/appkit-event-mask-queue.m.
#import <AppKit/AppKit.h>
#import <AppKit/NSDisplay.h>
#include <stdio.h>
#include <stdlib.h>

@interface QueueDisplay : NSDisplay
@end
@implementation QueueDisplay
@end

static void expect(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

@interface WheelEvent : NSEvent
@end
@implementation WheelEvent
- (NSEventType)type { return NSScrollWheel; }
- (CGFloat)deltaX { return 0; }
- (CGFloat)deltaY { return -2; }
@end

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSEvent *motion(NSEventType type, CGFloat x) {
    return [NSEvent mouseEventWithType:type
                              location:NSMakePoint(x, 0)
                         modifierFlags:0
                             timestamp:0
                          windowNumber:0
                               context:nil
                           eventNumber:0
                            clickCount:0
                              pressure:0];
}

static NSEvent *take(NSDisplay *display) {
    return [display nextEventMatchingMask:NSAnyEventMask
                                untilDate:[NSDate distantPast]
                                   inMode:NSDefaultRunLoopMode
                                  dequeue:YES];
}

int main(void) {
    @autoreleasepool {
        // The caller-supplied event number is kept by mouse and tracking events.
        NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
                                           location:NSZeroPoint
                                      modifierFlags:0
                                          timestamp:0
                                       windowNumber:0
                                            context:nil
                                        eventNumber:4711
                                         clickCount:2
                                           pressure:1];
        expect([down eventNumber] == 4711 && [down clickCount] == 2,
               "mouse event keeps eventNumber and clickCount");
        NSEvent *enter = [NSEvent enterExitEventWithType:NSMouseEntered
                                                location:NSZeroPoint
                                           modifierFlags:0
                                               timestamp:0
                                            windowNumber:0
                                                 context:nil
                                             eventNumber:-3
                                          trackingNumber:71
                                                userData:NULL];
        expect([enter eventNumber] == -3 && [enter trackingNumber] == 71,
               "tracking event keeps eventNumber and trackingNumber");

        // Coalescing is on by default and replaces a trailing moved event.
        expect([NSEvent isMouseCoalescingEnabled], "coalescing is enabled by default");
        QueueDisplay *display = [[QueueDisplay alloc] init];
        [display postEvent:motion(NSMouseMoved, 1) atStart:NO];
        [display postEvent:motion(NSMouseMoved, 2) atStart:NO];
        [display postEvent:motion(NSMouseMoved, 3) atStart:NO];
        NSEvent *moved = take(display);
        expect(moved != nil && [moved type] == NSMouseMoved && [moved locationInWindow].x == 3,
               "queued moved events collapse to the latest");
        expect([take(display) type] == NSAppKitSystem, "nothing else is queued");

        // Different types are not merged; non-motion events are never replaced.
        [display postEvent:motion(NSLeftMouseDragged, 1) atStart:NO];
        [display postEvent:motion(NSMouseMoved, 2) atStart:NO];
        [display postEvent:down atStart:NO];
        [display postEvent:down atStart:NO];
        expect([take(display) type] == NSLeftMouseDragged, "drag kept before moved");
        expect([take(display) type] == NSMouseMoved, "moved kept after drag");
        expect(take(display) == down && take(display) == down, "presses are not coalesced");

        // With coalescing off every event is delivered.
        [NSEvent setMouseCoalescingEnabled:NO];
        [display postEvent:motion(NSMouseMoved, 1) atStart:NO];
        [display postEvent:motion(NSMouseMoved, 2) atStart:NO];
        expect([take(display) locationInWindow].x == 1 && [take(display) locationInWindow].x == 2,
               "events are all delivered when coalescing is disabled");
        [NSEvent setMouseCoalescingEnabled:YES];

        // A main menu item shows the title of its submenu.
        NSMenu *bar = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Item" action:NULL keyEquivalent:@""];
        NSMenu *submenu = [[NSMenu alloc] initWithTitle:@"Submenu"];
        [bar addItem:item];
        [item setSubmenu:submenu];
        expect([[item title] isEqualToString:@"Item"] &&
               [[(id)item _mainMenuTitle] isEqualToString:@"Submenu"],
               "main menu item displays the submenu title");

        // A wheel event sent to a view inside a scroll view scrolls it; one sent
        // to the scroll view itself does too and does not recurse.
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        FlippedView *document = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 100, 1000)];
        [scroll setDocumentView:document];
        WheelEvent *wheel = [[WheelEvent alloc] init];
        [document scrollWheel:wheel];
        CGFloat first = [[scroll contentView] bounds].origin.y;
        expect(first > 0, "wheel over the document view scrolls the scroll view");
        [scroll scrollWheel:wheel];
        expect([[scroll contentView] bounds].origin.y > first,
               "wheel sent to the scroll view scrolls it");

        // drawsBackground on the scroll view reaches its clip view.
        [scroll setDrawsBackground:NO];
        expect(![[scroll contentView] drawsBackground], "clip view stops drawing its background");
        [scroll setDrawsBackground:YES];
        expect([[scroll contentView] drawsBackground], "clip view draws its background again");

        puts("PASS: event numbers, mouse coalescing, wheel routing and main menu titles");
    }
    return 0;
}
