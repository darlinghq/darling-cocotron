// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// AppKit and the Carbon Event Manager share the main event queue: what one posts the other
// receives, in queue order; an NSEvent keeps its CGEvent and its Carbon event; mouse events taken
// from the queue pass the Carbon handlers before -sendEvent:. The cases marked QUIRK are not
// documented; they were observed on macOS 26.7.3 (vd-upstream/mac-probes/937-a4-events.m, probes
// named in each case). The other cases follow the documentation.
//
// Needs a window system (DISPLAY, or WAYLAND_DISPLAY with DARLING_APPKIT_BACKEND=wayland).
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static NSEvent *next(NSEventMask mask, BOOL dequeue) {
    return [NSApp nextEventMatchingMask: mask
                              untilDate: [NSDate distantPast]
                                 inMode: NSDefaultRunLoopMode
                                dequeue: dequeue];
}

static void drain(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    for (int i = 0; i < 1000 && next(NSEventMaskAny, YES) != nil; i++)
        ;
    EventRef event;
    while (ReceiveNextEvent(0, NULL, kEventDurationNoWait, true, &event) == noErr)
        ReleaseEvent(event);
    [pool release];
}

static NSEvent *appDefined(short subtype, NSInteger data1) {
    return [NSEvent otherEventWithType: NSEventTypeApplicationDefined
                              location: NSZeroPoint
                         modifierFlags: 0
                             timestamp: 0
                          windowNumber: 0
                               context: nil
                               subtype: subtype
                                 data1: data1
                                 data2: 0];
}

static NSEvent *makeMouseDown(void) {
    return [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                              location: NSMakePoint(20, 20)
                         modifierFlags: 0
                             timestamp: 0
                          windowNumber: 0
                               context: nil
                           eventNumber: 0
                            clickCount: 1
                              pressure: 1];
}

static void postCarbonKey(CGKeyCode code) {
    CGEventRef cg = CGEventCreateKeyboardEvent(NULL, code, true);
    EventRef event = NULL;
    CreateEventWithCGEvent(NULL, cg, kEventAttributeNone, &event);
    PostEventToQueue(GetMainEventQueue(), event, kEventPriorityStandard);
    ReleaseEvent(event);
    CFRelease(cg);
}

static void testPostedNSEventReachesCarbon(void) {
    drain();
    [NSApp postEvent: appDefined(3, 42) atStart: NO];

    EventRef event = NULL;
    OSStatus status = ReceiveNextEvent(0, NULL, kEventDurationNoWait, true, &event);
    expect(status == noErr && event != NULL, "ReceiveNextEvent returns the event NSApp posted");
    if (event == NULL)
        return;
    NSEvent *back = [NSEvent eventWithEventRef: event];
    expect(back != nil && [back type] == NSEventTypeApplicationDefined && [back subtype] == 3 && [back data1] == 42,
          "+eventWithEventRef: gives the application-defined event back");
    ReleaseEvent(event);
    expect(next(NSEventMaskAny, NO) == nil, "the event left the queue for both");
}

static void testCarbonPostReachesNSApp(void) {
    drain();
    CGEventRef cg = CGEventCreateKeyboardEvent(NULL, 0 /* a */, true);
    UniChar a = 'a';
    CGEventKeyboardSetUnicodeString(cg, 1, &a);
    EventRef event = NULL;
    CreateEventWithCGEvent(NULL, cg, kEventAttributeNone, &event);
    PostEventToQueue(GetMainEventQueue(), event, kEventPriorityStandard);

    NSEvent *got = next(NSEventMaskKeyDown, YES);
    expect(got != nil && [got type] == NSEventTypeKeyDown && [[got characters] isEqual: @"a"],
          "-nextEventMatchingMask: returns the key event posted with PostEventToQueue");
    expect(got != nil && [got CGEvent] == cg, "  its -CGEvent is the CGEvent it was made from (P10)");
    expect(got != nil && [got eventRef] == event, "  its -eventRef is the posted Carbon event (P10)");
    ReleaseEvent(event);
    CFRelease(cg);
}

static void testQueueOrder(void) {
    drain();
    [NSApp postEvent: appDefined(0, 1) atStart: NO];
    postCarbonKey(1);
    [NSApp postEvent: appDefined(0, 2) atStart: NO];
    [NSApp postEvent: appDefined(0, 3) atStart: YES];

    NSMutableArray *order = [NSMutableArray array];
    NSEvent *event;
    while ((event = next(NSEventMaskAny, YES)) != nil)
        [order addObject: [event type] == NSEventTypeKeyDown ? @"key" : [NSString stringWithFormat: @"%ld", (long) [event data1]]];
    NSString *sequence = [order componentsJoinedByString: @","];
    expect([sequence isEqual: @"3,1,key,2"], [[NSString stringWithFormat: @"AppKit and Carbon posts share one queue order (%@)", sequence] UTF8String]);
}

static void testIdentity(void) {
    drain();
    CGEventRef cg = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(30, 40), kCGMouseButtonLeft);
    NSEvent *fromCG = [NSEvent eventWithCGEvent: cg];
    expect(fromCG != nil && [fromCG type] == NSEventTypeLeftMouseDown && [fromCG CGEvent] == cg,
          "+eventWithCGEvent: keeps the CGEvent");
    const void *ref = [fromCG eventRef];
    expect(ref != NULL && [fromCG eventRef] == ref, "-eventRef is made once");
    expect(ref != NULL && GetEventClass((EventRef) ref) == kEventClassMouse && GetEventKind((EventRef) ref) == kEventMouseDown,
          "  and is a Carbon mouse-down event (P4)");
    expect([NSEvent eventWithCGEvent: NULL] == nil, "+eventWithCGEvent: NULL is nil");

    [NSApp postEvent: fromCG atStart: NO];
    NSEvent *dequeued = next(NSEventMaskAny, YES);
    expect(dequeued != nil && [dequeued CGEvent] == cg, "a posted +eventWithCGEvent: event comes back with the same CGEvent (P4)");
    CFRelease(cg);

    NSEvent *posted = appDefined(7, 99);
    [NSApp postEvent: posted atStart: NO];
    NSEvent *got = next(NSEventMaskApplicationDefined, YES);
    CGEventRef first = [got CGEvent];
    expect(got != nil && [got data1] == 99 && first != NULL && [got CGEvent] == first,
          "a dequeued event has a stable CGEvent (P4)");
    expect(got != nil && [got eventRef] != NULL && [got eventRef] == [got eventRef], "  and a stable eventRef");
    NSEvent *again = [NSEvent eventWithEventRef: [got eventRef]];
    expect(again != nil && [again data1] == 99 && [again CGEvent] == first, "+eventWithEventRef: of it has its CGEvent");
}

// QUIRK cases (macOS 26.7.3, P3, P5, P6)
static OSStatus countHandler(EventHandlerCallRef call, EventRef event, void *info) {
    (*(int *) info)++;
    return noErr;
}

static Boolean isEvent(EventRef event, void *info) {
    return event == (EventRef) info;
}

static BOOL discardingAnyLeaves(EventRef custom) {
    [NSApp discardEventsMatchingMask: NSEventMaskAny beforeEvent: nil];
    return FindSpecificEventInQueue(GetMainEventQueue(), isEvent, custom) != NULL;
}

static void testQuirkCarbonOnlyEvents(void) {
    drain();
    int handled = 0;
    EventTypeSpec spec = {'Tst ', 1};
    EventHandlerRef handler = NULL;
    InstallEventHandler(GetApplicationEventTarget(), countHandler, 1, &spec, &handled, &handler);

    EventRef custom = NULL;
    CreateEvent(NULL, 'Tst ', 1, 0, kEventAttributeNone, &custom);
    PostEventToQueue(GetMainEventQueue(), custom, kEventPriorityStandard);

    expect(next(NSEventMaskKeyDown, YES) == nil && handled == 0 &&
          FindSpecificEventInQueue(GetMainEventQueue(), isEvent, custom) != NULL,
          "QUIRK: a custom Carbon event stays queued for a key mask (P3)");
    expect(next(NSEventMaskAny, NO) == nil && handled == 0, "QUIRK: a peek does not return a custom Carbon event (P3)");
    expect(discardingAnyLeaves(custom), "QUIRK: discarding any event leaves a custom Carbon event (P5)");
    NSEvent *got = next(NSEventMaskAny, YES);
    expect(got == nil && handled == 1 && FindSpecificEventInQueue(GetMainEventQueue(), isEvent, custom) == NULL,
          "QUIRK: dequeuing any event sends a custom Carbon event to the handlers and returns nil (P3)");
    RemoveEventHandler(handler);

    EventRef rawKey = NULL;
    CreateEvent(NULL, kEventClassKeyboard, kEventRawKeyDown, 0, kEventAttributeNone, &rawKey);
    expect([NSEvent eventWithEventRef: rawKey] == nil, "QUIRK: +eventWithEventRef: of a raw key event without a CGEvent is nil (P6)");
    expect([NSEvent eventWithEventRef: custom] == nil, "QUIRK: +eventWithEventRef: of a custom event is nil (P6)");
    PostEventToQueue(GetMainEventQueue(), rawKey, kEventPriorityStandard);
    [NSApp discardEventsMatchingMask: NSEventMaskKeyDown beforeEvent: nil];
    expect(FindSpecificEventInQueue(GetMainEventQueue(), isEvent, rawKey) == NULL,
          "QUIRK: discarding key-down events removes a raw Carbon key event (P5)");
    ReleaseEvent(rawKey);
    ReleaseEvent(custom);
}

// QUIRK cases (macOS 26.7.3, P1, P2, P12): mouse events pass the Carbon handlers when dequeued
static NSMutableArray *callLog;
static OSStatus mouseResult;

static OSStatus mouseHandler(EventHandlerCallRef call, EventRef event, void *info) {
    [callLog addObject: @"carbon"];
    return mouseResult;
}

static void testQuirkMouseEventsPassCarbonHandlers(void) {
    drain();
    callLog = [NSMutableArray array];
    mouseResult = eventNotHandledErr;
    EventTypeSpec spec = {kEventClassMouse, kEventMouseDown};
    EventHandlerRef handler = NULL;
    InstallEventHandler(GetApplicationEventTarget(), mouseHandler, 1, &spec, NULL, &handler);
    id monitor = [NSEvent addLocalMonitorForEventsMatchingMask: NSEventMaskLeftMouseDown
                                                       handler: ^NSEvent *(NSEvent *event) {
                                                           [callLog addObject: @"monitor"];
                                                           return nil;
                                                       }];

    [NSApp postEvent: makeMouseDown() atStart: NO];
    expect(next(NSEventMaskKeyDown, YES) == nil && [callLog count] == 0, "QUIRK: a mask without mouse events leaves it, no handler runs (P2)");
    NSEvent *peeked = next(NSEventMaskAny, NO);
    expect(peeked != nil && [callLog count] == 0, "QUIRK: a peek returns it without the Carbon handlers (P2)");
    NSEvent *got = [NSApp nextEventMatchingMask: NSEventMaskAny
                                      untilDate: [NSDate distantPast]
                                         inMode: NSEventTrackingRunLoopMode
                                        dequeue: YES];
    expect(got != nil && [got type] == NSEventTypeLeftMouseDown && [[callLog componentsJoinedByString: @","] isEqual: @"carbon"],
          "QUIRK: dequeuing it runs the Carbon handlers, also in the tracking mode (P2)");
    if (got != nil)
        [NSApp sendEvent: got];
    NSString *order = [callLog componentsJoinedByString: @","];
    expect([order isEqual: @"carbon,monitor"],
          [[NSString stringWithFormat: @"QUIRK: the Carbon handlers run before -sendEvent: and the local monitors (P12: %@)", order] UTF8String]);

    [callLog removeAllObjects];
    mouseResult = noErr;
    [NSApp postEvent: makeMouseDown() atStart: NO];
    got = next(NSEventMaskAny, YES);
    expect(got == nil && [[callLog componentsJoinedByString: @","] isEqual: @"carbon"],
          "QUIRK: a mouse event a Carbon handler handles is not returned (P1)");

    [NSEvent removeMonitor: monitor];
    RemoveEventHandler(handler);
}

static void *postLater(void *arg) {
    usleep(200000);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApp postEvent: appDefined(0, 77) atStart: NO];
    [pool release];
    return NULL;
}

static void testCrossThreadWakeup(void) {
    drain();
    pthread_t thread;
    pthread_create(&thread, NULL, postLater, NULL);
    NSDate *start = [NSDate date];
    NSEvent *got = [NSApp nextEventMatchingMask: NSEventMaskApplicationDefined
                                      untilDate: [NSDate dateWithTimeIntervalSinceNow: 5]
                                         inMode: NSDefaultRunLoopMode
                                        dequeue: YES];
    NSTimeInterval waited = -[start timeIntervalSinceNow];
    pthread_join(thread, NULL);
    expect(got != nil && [got data1] == 77 && waited < 2,
          [[NSString stringWithFormat: @"an event posted on another thread ends the wait (%.2f s)", waited] UTF8String]);
}

static void testInputCoalescing(void) {
    drain();
    // Two moves of the input stream: the queue keeps the second, with both moves' deltas
    for (int i = 0; i < 2; i++) {
        CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(100 + 3 * i, 100), kCGMouseButtonLeft);
        CGEventSetIntegerValueField(move, kCGMouseEventDeltaX, 3 + i);
        CGEventSetIntegerValueField(move, kCGMouseEventDeltaY, 1);
        CGEventPost(kCGSessionEventTap, move);
        CFRelease(move);
    }
    NSMutableArray *deltas = [NSMutableArray array];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskMouseMoved
                                       untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]
                                          inMode: NSDefaultRunLoopMode
                                         dequeue: YES]) != nil)
        [deltas addObject: [NSString stringWithFormat: @"%g/%g", [event deltaX], [event deltaY]]];
    NSString *got = [deltas componentsJoinedByString: @","];
    BOOL coalescing = [NSEvent isMouseCoalescingEnabled];
    expect(coalescing && [got isEqual: @"7/2"],
          [[NSString stringWithFormat: @"input mouse moves coalesce into one with both deltas (%@)", got] UTF8String]);

    // Moves coalesce only with the move at the end of the queue: moves, click, moves keeps the
    // click between the two moves that come out, each with its own position and summed deltas
    drain();
    CGEventType types[5] = { kCGEventMouseMoved, kCGEventMouseMoved, kCGEventLeftMouseDown, kCGEventMouseMoved, kCGEventMouseMoved };
    for (int i = 0; i < 5; i++) {
        CGEventRef e = CGEventCreateMouseEvent(NULL, types[i], CGPointMake(100 + 10 * i, 100), kCGMouseButtonLeft);
        CGEventSetIntegerValueField(e, kCGMouseEventDeltaX, types[i] == kCGEventMouseMoved ? i + 1 : 0);
        CGEventSetIntegerValueField(e, kCGMouseEventDeltaY, types[i] == kCGEventMouseMoved ? 1 : 0);
        CGEventPost(kCGSessionEventTap, e);
        CFRelease(e);
    }
    NSMutableArray *order = [NSMutableArray array];
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskMouseMoved | NSEventMaskLeftMouseDown
                                       untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]
                                          inMode: NSDefaultRunLoopMode
                                         dequeue: YES]) != nil)
        [order addObject: [NSString stringWithFormat: @"%d@%g(%g/%g)", (int)[event type], [event CGEvent] ? CGEventGetLocation([event CGEvent]).x : -1, [event deltaX], [event deltaY]]];
    NSString *gotOrder = [order componentsJoinedByString: @" "];
    // type 5 = moved, 1 = left mouse down; the click is between the moves
    expect([gotOrder isEqual: @"5@110(3/2) 1@120(0/0) 5@140(9/2)"],
          [[NSString stringWithFormat: @"moves, click, moves: order, positions and deltas are kept (%@)", gotOrder] UTF8String]);

    // Without coalescing every move arrives, in order
    [NSEvent setMouseCoalescingEnabled: NO];
    for (int i = 0; i < 3; i++) {
        CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(100 + 10 * i, 100), kCGMouseButtonLeft);
        CGEventPost(kCGSessionEventTap, e);
        CFRelease(e);
    }
    int uncoalesced = 0;
    while ([NSApp nextEventMatchingMask: NSEventMaskMouseMoved
                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]
                                 inMode: NSDefaultRunLoopMode
                                dequeue: YES] != nil)
        uncoalesced++;
    [NSEvent setMouseCoalescingEnabled: YES];
    expect(uncoalesced == 3 && [NSEvent isMouseCoalescingEnabled], "with coalescing disabled every move is delivered");

    // Posted moves are not coalesced (P8)
    for (int i = 0; i < 2; i++)
        [NSApp postEvent: [NSEvent mouseEventWithType: NSEventTypeMouseMoved
                                             location: NSMakePoint(10 * i, 10)
                                        modifierFlags: 0
                                            timestamp: 0
                                         windowNumber: 0
                                              context: nil
                                          eventNumber: 0
                                           clickCount: 0
                                             pressure: 0]
                 atStart: NO];
    int count = 0;
    while (next(NSEventMaskMouseMoved, YES) != nil)
        count++;
    expect(count == 2, "posted mouse moves are not coalesced (P8)");
}

static void testPeriodicEvents(void) {
    drain();
    [NSEvent startPeriodicEventsAfterDelay: 0 withPeriod: 0.02];
    usleep(100000);
    NSEvent *first = [NSApp nextEventMatchingMask: NSEventMaskPeriodic
                                        untilDate: [NSDate dateWithTimeIntervalSinceNow: 1]
                                           inMode: NSEventTrackingRunLoopMode
                                          dequeue: YES];
    NSEvent *second = next(NSEventMaskPeriodic, YES);
    [NSEvent stopPeriodicEvents];
    expect(first != nil && [first type] == NSEventTypePeriodic && second == nil,
          "periodic events arrive, and only the newest one is kept queued");
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    [NSApp finishLaunching];

    testPostedNSEventReachesCarbon();
    testCarbonPostReachesNSApp();
    testQueueOrder();
    testIdentity();
    testQuirkCarbonOnlyEvents();
    testQuirkMouseEventsPassCarbonHandlers();
    testCrossThreadWakeup();
    testInputCoalescing();
    testPeriodicEvents();

    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    [pool release];
    return failures ? 1 : 0;
}
