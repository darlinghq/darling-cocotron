// Copyright (C) 2026 Lubos Dolezel
//
// NSSharingServicePicker and its delegate. The contract is the NSSharingServicePicker and
// NSSharingServicePickerDelegate references
// (https://developer.apple.com/documentation/appkit/nssharingservicepicker,
// https://developer.apple.com/documentation/appkit/nssharingservicepickerdelegate):
//  - the delegate can replace the proposed services before the picker appears;
//  - when a service is chosen the picker tells the delegate, and the service receives the items
//    after that call returns;
//  - the delegate can give the chosen service its own delegate;
//  - NSSharingServiceDelegate: when a service performs, its delegate is sent
//    sharingService:willShareItems: before the service shares and
//    sharingService:didShareItems: after it (public NSSharingService.h; a probe on macOS 26.1
//    saw will, handler, did, also for an empty array);
//  - QUIRK (not documented; macOS 26.1 arm64 probe, 15 of 15 cases): showRelativeToRect:ofView:preferredEdge:
//    returns before the picker is on screen, and the delegate is asked for the services inside the call;
//    -close before the picker is on screen means it never appears;
//  - QUIRK (same probe, 8 of 8 edge cases): the picker touches the named edge of the rectangle (gap 0) and is
//    centred on the middle of that edge, whatever its size. The tests measure the size, they do not assume one.
//    A flipped view was not probed: GUESS that the edge is read in the view's own coordinates.
// Darling has no system services, so the proposed list is empty and the services here are
// custom ones made with a handler. The menu of services is read through -menu, which is not in
// the reference. Showing the picker runs a menu: those tests need a window server.
// Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-sharing-service-picker.m (no ARC)
#import <AppKit/AppKit.h>
#import "../AppKit/NSMenu.subproj/NSMenuWindow.h"
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSMutableArray *log_;

@interface ServiceDelegate : NSObject <NSSharingServiceDelegate>
@end
@implementation ServiceDelegate
@end

@interface PickerDelegate : NSObject <NSSharingServicePickerDelegate> {
@public
    NSSharingService *custom;
    ServiceDelegate *serviceDelegate;
    NSArray *seenProposed;
    NSArray *seenItems;
}
@end
@implementation PickerDelegate
- (NSArray *) sharingServicePicker: (NSSharingServicePicker *) picker sharingServicesForItems: (NSArray *) items
           proposedSharingServices: (NSArray *) proposed {
    seenItems = items;
    seenProposed = proposed;
    NSMutableArray *services = [NSMutableArray arrayWithArray: proposed];
    [services addObject: custom];
    return services;
}
- (id <NSSharingServiceDelegate>) sharingServicePicker: (NSSharingServicePicker *) picker
                             delegateForSharingService: (NSSharingService *) service {
    [log_ addObject: @"delegateFor"];
    return serviceDelegate;
}
- (void) sharingServicePicker: (NSSharingServicePicker *) picker didChooseSharingService: (NSSharingService *) service {
    [log_ addObject: service == custom ? @"didChoose" : @"didChoose-other"];
}
@end

static void test_delegate_services_and_choice(void) {
    PickerDelegate *delegate = [[PickerDelegate new] autorelease];
    delegate->serviceDelegate = [[ServiceDelegate new] autorelease];
    delegate->custom = [[[NSSharingService alloc] initWithTitle: @"Custom" image: nil alternateImage: nil
                                                         handler: ^{ [log_ addObject: @"handler"]; }] autorelease];
    NSArray *items = [NSArray arrayWithObject: @"item"];
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: items] autorelease];
    [picker setDelegate: delegate];

    NSMenu *menu = [picker menu];
    CHECK([delegate->seenProposed isKindOfClass: [NSArray class]]);
    CHECK([delegate->seenItems isEqual: items]);
    CHECK([menu numberOfItems] == 1);
    CHECK([[[menu itemAtIndex: 0] title] isEqualToString: @"Custom"]);

    log_ = [NSMutableArray array];
    [menu performActionForItemAtIndex: 0];
    CHECK([[delegate->custom delegate] isEqual: delegate->serviceDelegate]);
    NSArray *expected = [NSArray arrayWithObjects: @"delegateFor", @"didChoose", @"handler", nil];
    CHECK([log_ isEqual: expected]);
}

@interface RecordingServiceDelegate : NSObject <NSSharingServiceDelegate>
@end
@implementation RecordingServiceDelegate
- (void) sharingService: (NSSharingService *) service willShareItems: (NSArray *) items {
    [log_ addObject: [NSString stringWithFormat: @"will%lu", (unsigned long) [items count]]];
}
- (void) sharingService: (NSSharingService *) service didShareItems: (NSArray *) items {
    [log_ addObject: [NSString stringWithFormat: @"did%lu", (unsigned long) [items count]]];
}
@end

static void test_perform_notifies_the_service_delegate(void) {
    RecordingServiceDelegate *delegate = [[RecordingServiceDelegate new] autorelease];
    NSSharingService *service = [[[NSSharingService alloc] initWithTitle: @"Custom" image: nil alternateImage: nil
                                                                 handler: ^{ [log_ addObject: @"handler"]; }] autorelease];
    NSArray *one = [NSArray arrayWithObject: @"item"];

    log_ = [NSMutableArray array];
    [service performWithItems: one];
    CHECK([log_ isEqual: [NSArray arrayWithObject: @"handler"]]); // no delegate

    [service setDelegate: delegate];
    log_ = [NSMutableArray array];
    [service performWithItems: one];
    CHECK([log_ isEqual: ([NSArray arrayWithObjects: @"will1", @"handler", @"did1", nil])]);

    log_ = [NSMutableArray array];
    [service performWithItems: [NSArray array]];
    CHECK([log_ isEqual: ([NSArray arrayWithObjects: @"will0", @"handler", @"did0", nil])]);
}

static void test_no_delegate(void) {
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"x"]] autorelease];

    CHECK([[picker menu] numberOfItems] == 0);
    [picker close];
}

// A delegate may release the picker from its callback; the service must still get the items.
@interface ReleasingDelegate : NSObject <NSSharingServicePickerDelegate> {
@public
    NSSharingServicePicker *picker;
}
@end
@implementation ReleasingDelegate
- (NSArray *) sharingServicePicker: (NSSharingServicePicker *) p sharingServicesForItems: (NSArray *) items
           proposedSharingServices: (NSArray *) proposed {
    return [NSArray arrayWithObject: [[[NSSharingService alloc] initWithTitle: @"Once" image: nil alternateImage: nil
                                                                        handler: ^{ [log_ addObject: @"handler"]; }] autorelease]];
}
- (void) sharingServicePicker: (NSSharingServicePicker *) p didChooseSharingService: (NSSharingService *) service {
    [picker release];
    picker = nil;
}
@end

static void test_picker_released_by_the_delegate(void) {
    ReleasingDelegate *delegate = [[ReleasingDelegate new] autorelease];
    delegate->picker = [[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"x"]];
    [delegate->picker setDelegate: delegate];
    NSMenu *menu = [delegate->picker menu];
    log_ = [NSMutableArray array];
    [menu performActionForItemAtIndex: 0];
    CHECK(delegate->picker == nil);
    CHECK([log_ isEqual: [NSArray arrayWithObject: @"handler"]]);
}

static NSMenuWindow *openMenuWindow(void) {
    for (NSWindow *window in [NSApp windows])
        if ([window isKindOfClass: [NSMenuWindow class]] && [window isVisible])
            return (NSMenuWindow *) window;
    return nil;
}

// Runs the run loop until `done` is YES or the time is up.
static void spin(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];

    while ([end timeIntervalSinceNow] > 0 && !(done != nil && done()))
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]];
}

// Calls `block` every 20 ms, also while a menu is being tracked, until it invalidates the timer.
static NSTimer *poll(void (^block)(NSTimer *)) {
    NSTimer *timer = [NSTimer timerWithTimeInterval: 0.02 repeats: YES block: block];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
    return timer;
}

static NSWindow *makeHost(void) {
    NSWindow *host = [[NSWindow alloc] initWithContentRect: NSMakeRect(400, 400, 500, 400)
                                                 styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
    [host makeKeyAndOrderFront: nil];
    return host;
}

// While the picker is up, blocks dispatched to the main queue still run (on macOS the picker is an
// ordinary window, so the application keeps running); the timer-based poll alone cannot show that.
static void test_main_queue_runs_while_picker_is_up(void) {
    NSWindow *host = makeHost();
    PickerDelegate *delegate = [[PickerDelegate new] autorelease];
    delegate->custom = [[[NSSharingService alloc] initWithTitle: @"Custom" image: nil alternateImage: nil handler: ^{}] autorelease];
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"item"]] autorelease];
    __block BOOL posted = NO, ran = NO, finished = NO;
    __block int ticks = 0;

    [picker setDelegate: delegate];
    NSTimer *timer = poll(^(NSTimer *t) {
        if (openMenuWindow() == nil)
            return;
        if (!posted) {
            posted = YES;
            dispatch_async(dispatch_get_main_queue(), ^{ ran = YES; });
            return;
        }
        // Give the posted block time to run while the menu is still up, then dismiss it.
        if (ran || ++ticks > 50) {
            finished = YES;
            [t invalidate];
            [picker close];
        }
    });
    [picker showRelativeToRect: NSMakeRect(200, 150, 60, 30) ofView: [host contentView] preferredEdge: NSMinYEdge];
    spin(5.0, ^BOOL { return finished; });
    [timer invalidate];
    CHECK(finished);
    CHECK(ran);
    spin(0.3, nil);
    [host close];
}

// The picker is asked for its services inside the call and shows up only after it has returned.
static void test_show_returns_before_presenting(void) {
    NSWindow *host = makeHost();
    PickerDelegate *delegate = [[PickerDelegate new] autorelease];
    delegate->custom = [[[NSSharingService alloc] initWithTitle: @"Custom" image: nil alternateImage: nil handler: ^{}] autorelease];
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"item"]] autorelease];
    __block BOOL returned = NO, seen = NO, returnedWhenSeen = NO;

    [picker setDelegate: delegate];
    // The menu is tracked in a nested loop: the timer sees it, then dismisses it.
    poll(^(NSTimer *timer) {
        if (openMenuWindow() == nil)
            return;
        seen = YES;
        returnedWhenSeen = returned;
        [timer invalidate];
        [picker close];
    });
    [picker showRelativeToRect: NSMakeRect(200, 150, 60, 30) ofView: [host contentView] preferredEdge: NSMinYEdge];
    returned = YES;
    CHECK(delegate->seenItems != nil);        // the delegate was asked inside the call
    CHECK(openMenuWindow() == nil);           // and nothing is on screen yet

    spin(3.0, ^BOOL { return seen; });
    CHECK(seen);
    CHECK(returnedWhenSeen);                  // it appeared after show had returned
    spin(0.3, nil);
    CHECK(openMenuWindow() == nil);
    [host close];
}

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL) isFlipped { return YES; }
@end

static NSRect screenRect(NSView *view, NSRect rect) {
    NSPoint low = [[view window] convertBaseToScreen: [view convertPoint: NSMakePoint(NSMinX(rect), NSMinY(rect)) toView: nil]];
    NSPoint high = [[view window] convertBaseToScreen: [view convertPoint: NSMakePoint(NSMaxX(rect), NSMaxY(rect)) toView: nil]];

    return NSMakeRect(MIN(low.x, high.x), MIN(low.y, high.y), fabs(high.x - low.x), fabs(high.y - low.y));
}

// Shows the picker beside `edge` of a rectangle in `view` and returns the frame of its window.
static NSRect pickerFrame(NSView *view, NSRect rect, NSRectEdge edge) {
    PickerDelegate *delegate = [[PickerDelegate new] autorelease];
    delegate->custom = [[[NSSharingService alloc] initWithTitle: @"Custom" image: nil alternateImage: nil handler: ^{}] autorelease];
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"item"]] autorelease];
    __block NSRect frame = NSZeroRect;

    [picker setDelegate: delegate];
    poll(^(NSTimer *timer) {
        NSWindow *window = openMenuWindow();

        if (window == nil)
            return;
        frame = [window frame];
        [timer invalidate];
        [picker close];
    });
    [picker showRelativeToRect: rect ofView: view preferredEdge: edge];
    spin(3.0, ^BOOL { return !NSIsEmptyRect(frame); });
    spin(0.3, nil);
    return frame;
}

static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) <= 1.0; }

// The window lies on the edge's side with no gap and is centred on the middle of the edge. `visual` says on
// which side of the rectangle on screen: 0 left, 1 right, 2 below, 3 above.
static void checkPlacement(NSRect frame, NSRect anchor, int visual, const char *what) {
    CHECK(!NSIsEmptyRect(frame));
    switch (visual) {
    case 0: CHECK(near(NSMaxX(frame), NSMinX(anchor)) && near(NSMidY(frame), NSMidY(anchor))); break;
    case 1: CHECK(near(NSMinX(frame), NSMaxX(anchor)) && near(NSMidY(frame), NSMidY(anchor))); break;
    case 2: CHECK(near(NSMaxY(frame), NSMinY(anchor)) && near(NSMidX(frame), NSMidX(anchor))); break;
    default: CHECK(near(NSMinY(frame), NSMaxY(anchor)) && near(NSMidX(frame), NSMidX(anchor))); break;
    }
    if (failures)
        fprintf(stderr, "  placement case: %s, frame %s, anchor %s\n", what, [NSStringFromRect(frame) UTF8String], [NSStringFromRect(anchor) UTF8String]);
}

static void test_placement(void) {
    NSWindow *host = makeHost();
    NSRect rect = NSMakeRect(200, 150, 60, 30);
    NSView *plain = [host contentView];
    NSRect anchor = screenRect(plain, rect);

    // y up: minY is below the rectangle, maxY above.
    checkPlacement(pickerFrame(plain, rect, NSMinXEdge), anchor, 0, "minX");
    checkPlacement(pickerFrame(plain, rect, NSMaxXEdge), anchor, 1, "maxX");
    checkPlacement(pickerFrame(plain, rect, NSMinYEdge), anchor, 2, "minY");
    checkPlacement(pickerFrame(plain, rect, NSMaxYEdge), anchor, 3, "maxY");

    // GUESS: in a flipped view minY is visually the top.
    FlippedView *flipped = [[[FlippedView alloc] initWithFrame: [plain bounds]] autorelease];
    [plain addSubview: flipped];
    anchor = screenRect(flipped, rect);
    checkPlacement(pickerFrame(flipped, rect, NSMinYEdge), anchor, 3, "flipped minY");
    checkPlacement(pickerFrame(flipped, rect, NSMaxYEdge), anchor, 2, "flipped maxY");
    checkPlacement(pickerFrame(flipped, rect, NSMinXEdge), anchor, 0, "flipped minX");
    [host close];
}

// -close before the picker is on screen cancels the pending presentation.
static void test_close_before_presenting(void) {
    NSWindow *host = makeHost();
    PickerDelegate *delegate = [[PickerDelegate new] autorelease];
    delegate->custom = [[[NSSharingService alloc] initWithTitle: @"Custom" image: nil alternateImage: nil handler: ^{}] autorelease];
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"item"]] autorelease];
    __block BOOL appeared = NO;

    [picker setDelegate: delegate];
    NSTimer *watch = poll(^(NSTimer *timer) {
        if (openMenuWindow() == nil)
            return;
        appeared = YES;
        [timer invalidate];
        [picker close];
    });
    [picker showRelativeToRect: NSMakeRect(200, 150, 60, 30) ofView: [host contentView] preferredEdge: NSMinYEdge];
    [picker close];
    spin(0.6, nil);
    [watch invalidate];
    CHECK(!appeared);
    [host close];
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_delegate_services_and_choice());
    RUN(test_perform_notifies_the_service_delegate());
    RUN(test_no_delegate());
    RUN(test_picker_released_by_the_delegate());
    [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
    RUN(test_show_returns_before_presenting());
    RUN(test_main_queue_runs_while_picker_is_up());
    RUN(test_close_before_presenting());
    RUN(test_placement());
    if (failures == 0)
        printf("PASS appkit-sharing-service-picker\n");
    [pool release];
    return failures != 0;
}
