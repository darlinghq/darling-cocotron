/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2010 Markus Hitter <mah@jump-ing.de>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSEvent_keyboard.h>
#import <AppKit/NSEvent_mouse.h>
#import <AppKit/NSEvent_other.h>
#import <AppKit/NSEvent_periodic.h>
#import <AppKit/NSWindow.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>
#import "../private-include/AppKit/NSEventTime.h"
#import "../NSEventQueue.h"
#import <HIToolbox/CarbonEvents.h>
#import <HIToolbox/CarbonEventsCore.h>
#import <Foundation/NSRaise.h>

// The object +addLocalMonitorForEventsMatchingMask:handler: returns.
@interface NSLocalEventMonitor : NSObject {
@public
    NSEventMask _mask;
    NSEvent * (^_handler)(NSEvent *);
}
@end

@implementation NSLocalEventMonitor

- (void) dealloc {
    [_handler release];
    [super dealloc];
}

@end

// The object +addGlobalMonitorForEventsMatchingMask:handler: returns. It keeps
// its handler only so that the monitor lives until it is removed; the handler
// is never called (see the method).
@interface NSGlobalEventMonitor : NSObject {
@public
    NSEventMask _mask;
    void (^_handler)(NSEvent *);
}
@end

@implementation NSGlobalEventMonitor

- (void) dealloc {
    [_handler release];
    [super dealloc];
}

@end

static NSMutableArray *localEventMonitors = nil;
static NSMutableArray *globalEventMonitors = nil;

__attribute__((visibility("hidden")))
NSEvent *NSEventApplyLocalMonitors(NSEvent *event) {
    if ([localEventMonitors count] == 0)
        return event;

    // A handler may add or remove monitors. Added ones see the next event;
    // removed ones are not called again, not even for this one.
    NSArray *monitors = [[localEventMonitors copy] autorelease];

    for (NSLocalEventMonitor *monitor in monitors) {
        if (event == nil)
            break;
        if ([localEventMonitors indexOfObjectIdenticalTo: monitor] == NSNotFound)
            continue;
        if (monitor->_mask & NSEventMaskFromType([event type]))
            event = monitor->_handler(event);
    }
    return event;
}

@implementation NSEvent

// The mouse motion is coalesced in HIToolbox's event queue, which holds AppKit's events
+ (void) setMouseCoalescingEnabled: (BOOL) flag {
    SetMouseCoalescingEnabled(flag, NULL);
}

+ (BOOL) isMouseCoalescingEnabled {
    return IsMouseCoalescingEnabled();
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(NSEvent, self)) {
        if (NS_EXTRA(NSEvent, self)->_cgEvent != NULL)
            CFRelease(NS_EXTRA(NSEvent, self)->_cgEvent);
        if (NS_EXTRA(NSEvent, self)->_eventRef != NULL)
            ReleaseEvent((EventRef) NS_EXTRA(NSEvent, self)->_eventRef);
    }
    NS_EXTRA_FREE(NSEvent, self);
    [super dealloc];
}

// The CGEvent the event was made from or taken from the queue as; any other event gives a new
// CGEvent each time (as observed on macOS 26.7.3 for events made with the class methods).
- (CGEventRef) CGEvent {
    CGEventRef stored = [self _storedCGEvent];

    if (stored != NULL)
        return stored;
    return (CGEventRef) CFAutorelease(_NSEventCreateCGEvent(self, _NSEventMainScreenMaxY()));
}

// Made once, from the event's CGEvent, unless the event came with one
- (const void *) eventRef {
    void *stored = __atomic_load_n(&NS_EXTRA(NSEvent, self)->_eventRef, __ATOMIC_ACQUIRE);
    EventRef carbonEvent = NULL;

    if (stored != NULL)
        return stored;
    if (CreateEventWithCGEvent(NULL, [self CGEvent], kEventAttributeNone, &carbonEvent) != noErr)
        return NULL;
    [self _setCGEvent: NULL eventRef: carbonEvent];
    ReleaseEvent(carbonEvent);
    return NS_EXTRA(NSEvent, self)->_eventRef;
}

+ (NSEvent *) eventWithCGEvent: (CGEventRef) cgEvent {
    if (cgEvent == NULL)
        return nil;

    NSEvent *event = _NSEventCreateFromCGEvent(cgEvent);
    [event _setCGEvent: cgEvent eventRef: NULL];
    return [event autorelease];
}

// Only a Carbon event made from a CGEvent becomes an NSEvent (macOS 26.7.3 returns nil for a raw
// keyboard event made with CreateEvent, and for events of other classes).
+ (NSEvent *) eventWithEventRef: (const void *) eventRef {
    if (eventRef == NULL)
        return nil;

    CGEventRef cgEvent = CopyEventCGEvent((EventRef) eventRef);
    if (cgEvent == NULL)
        return nil;

    NSEvent *event = _NSEventCreateFromCGEvent(cgEvent);
    [event _setCGEvent: cgEvent eventRef: (void *) eventRef];
    CFRelease(cgEvent);
    return [event autorelease];
}

- (NSSet *) touchesMatchingPhase: (NSUInteger) phase inView: (NSView *) view {
    return [NSSet set];
}

- (NSSet *) allTouches {
    return [NSSet set];
}

- (NSSet *) touchesForView: (NSView *) view {
    return [NSSet set];
}

- (NSArray *) coalescedTouchesForTouch: (id) touch {
    return @[];
}

// The state queries are CoreGraphics', whose decoders of the window system's input hold it: the location of an
// event made from nothing is where the pointer is, and the hardware state functions of the event source report
// the modifier flags and the buttons that are held.
+ (NSPoint) mouseLocation {
    CGEventRef event = CGEventCreate(NULL);
    if (event == NULL)
        return NSZeroPoint;
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);
    // A window system that does not say where the pointer is (Wayland outside the process' surfaces, before it has
    // been over one) gives no position.
    if (point.x >= CGFLOAT_MAX / 2 || point.y >= CGFLOAT_MAX / 2)
        return NSZeroPoint;
    return NSMakePoint(point.x, _NSEventMainScreenMaxY() - point.y);
}

+ (NSEventModifierFlags) modifierFlags {
    return (NSEventModifierFlags) CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
}

+ (NSUInteger) pressedMouseButtons {
    NSUInteger buttons = 0;
    for (unsigned button = 0; button < 32; button++) {
        if (CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, (CGMouseButton) button))
            buttons |= (NSUInteger) 1 << button;
    }
    return buttons;
}

// The user's double-click interval, which CoreGraphics reads from the global preferences.
+ (NSTimeInterval) doubleClickInterval {
    return _CGSDoubleClickInterval();
}

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                       window: (NSWindow *) window
{
    _type = type;
    // Event times are seconds since the system started (see -[NSEvent timestamp]).
    _timestamp = NSEventCurrentTime();
    _locationInWindow = location;
    _modifierFlags = modifierFlags;
    _windowNumber = [window windowNumber];
    return self;
}

+ (instancetype) mouseEventWithType: (NSEventType) type
                           location: (NSPoint) location
                      modifierFlags: (NSEventModifierFlags) modifierFlags
                             window: (NSWindow *) window
                         clickCount: (NSInteger) clickCount
                             deltaX: (CGFloat) deltaX
                             deltaY: (CGFloat) deltaY
{
    return [[[NSEvent_mouse alloc] initWithType: type
                                       location: location
                                  modifierFlags: modifierFlags
                                         window: window
                                     clickCount: clickCount
                                         deltaX: deltaX
                                         deltaY: deltaY] autorelease];
}

+ (instancetype) mouseEventWithType: (NSEventType) type
                           location: (NSPoint) location
                      modifierFlags: (NSEventModifierFlags) modifierFlags
                             window: (NSWindow *) window
                             deltaY: (CGFloat) deltaY
{
    return [[[NSEvent_mouse alloc] initWithType: type
                                       location: location
                                  modifierFlags: modifierFlags
                                         window: window
                                         deltaY: deltaY] autorelease];
}

+ (instancetype) enterExitEventWithType: (NSEventType) type
                               location: (NSPoint) location
                          modifierFlags: (NSEventModifierFlags) flags
                              timestamp: (NSTimeInterval) timestamp
                           windowNumber: (NSInteger) windowNumber
                                context: (NSGraphicsContext *) context
                            eventNumber: (NSInteger) eventNumber
                         trackingNumber: (NSInteger) tracking
                               userData: (void *) userData
{
    return [[[NSEvent_mouse alloc] initWithType: type
                                       location: location
                                  modifierFlags: flags
                                      timestamp: timestamp
                                   windowNumber: windowNumber
                                        context: context
                                    eventNumber: eventNumber
                                 trackingNumber: tracking
                                       userData: userData] autorelease];
}

+ (instancetype) mouseEventWithType: (NSEventType) type
                           location: (NSPoint) location
                      modifierFlags: (NSEventModifierFlags) modifierFlags
                          timestamp: (NSTimeInterval) timestamp
                       windowNumber: (NSInteger) windowNumber
                            context: (NSGraphicsContext *) context
                        eventNumber: (NSInteger) eventNumber
                         clickCount: (NSInteger) clickCount
                           pressure: (float) pressure
{
    return [[[NSEvent_mouse alloc] initWithType: type
                                       location: location
                                  modifierFlags: modifierFlags
                                      timestamp: timestamp
                                   windowNumber: windowNumber
                                        context: context
                                    eventNumber: eventNumber
                                     clickCount: clickCount
                                       pressure: pressure] autorelease];
}

+ (instancetype) keyEventWithType: (NSEventType) type
                           location: (NSPoint) location
                      modifierFlags: (NSEventModifierFlags) modifierFlags
                             window: (NSWindow *) window
                         characters: (NSString *) characters
        charactersIgnoringModifiers: (NSString *) charactersIgnoringModifiers
                          isARepeat: (BOOL) isARepeat
                            keyCode: (unsigned short) keyCode
{
    return [[[NSEvent_keyboard alloc] initWithType: type
                                          location: location
                                     modifierFlags: modifierFlags
                                            window: window
                                        characters: characters
                       charactersIgnoringModifiers: charactersIgnoringModifiers
                                         isARepeat: isARepeat
                                           keyCode: keyCode] autorelease];
}

+ (instancetype) keyEventWithType: (NSEventType) type
                           location: (NSPoint) location
                      modifierFlags: (NSEventModifierFlags) modifierFlags
                          timestamp: (NSTimeInterval) timestamp
                       windowNumber: (NSInteger) windowNumber
                            context: (NSGraphicsContext *) context
                         characters: (NSString *) characters
        charactersIgnoringModifiers: (NSString *) charactersIgnoringModifiers
                          isARepeat: (BOOL) isARepeat
                            keyCode: (unsigned short) keyCode
{
    NSEvent *event = [[[NSEvent_keyboard alloc]
                           initWithType: type
                               location: location
                          modifierFlags: modifierFlags
                                 window: [NSApp windowWithWindowNumber:
                                                         windowNumber]
                             characters: characters
            charactersIgnoringModifiers: charactersIgnoringModifiers
                              isARepeat: isARepeat
                                keyCode: keyCode] autorelease];
    event->_timestamp = timestamp;
    return event;
}

+ (instancetype) otherEventWithType: (NSEventType) type
                           location: (NSPoint) location
                      modifierFlags: (NSEventModifierFlags) flags
                          timestamp: (NSTimeInterval) timestamp
                       windowNumber: (NSInteger) windowNum
                            context: (NSGraphicsContext *) context
                            subtype: (short) subtype
                              data1: (NSInteger) data1
                              data2: (NSInteger) data2
{
    return [[[NSEvent_other alloc] initWithType: type
                                       location: location
                                  modifierFlags: flags
                                      timestamp: timestamp
                                   windowNumber: windowNum
                                        context: context
                                        subtype: subtype
                                          data1: data1
                                          data2: data2] autorelease];
}

- (NSEventType) type {
    return _type;
}

- (NSTimeInterval) timestamp {
    return _timestamp;
}

- (NSPoint) locationInWindow {
    return _locationInWindow;
}

- (NSEventModifierFlags) modifierFlags {
    return _modifierFlags;
}

- (NSWindow *) window {
    return [NSApp windowWithWindowNumber: [self windowNumber]];
}

- (NSInteger) windowNumber {
    return _windowNumber;
}

- (NSInteger) clickCount {
    return 0;
}

- (NSInteger) eventNumber {
    return 0;
}

- (CGFloat) deltaX {
    return 0;
}

- (CGFloat) deltaY {
    return 0;
}

// Only magnify and rotate events (NSEvent_gesture) and scroll events marked as
// precise (NSEvent_mouse) carry a phase. Every other scroll event is a wheel
// notch measured in lines, with no phase, as a mouse wheel reports on macOS.
- (NSEventPhase) phase {
    return NSEventPhaseNone;
}

- (NSEventPhase) momentumPhase {
    return NSEventPhaseNone;
}

- (BOOL) hasPreciseScrollingDeltas {
    return NO;
}

- (CGFloat) scrollingDeltaX {
    return [self deltaX];
}

- (CGFloat) scrollingDeltaY {
    return [self deltaY];
}

- (BOOL) isDirectionInvertedFromDevice {
    return NO;
}

+ (BOOL) isSwipeTrackingFromScrollEventsEnabled {
    return NO;
}

- (CGFloat) deltaZ {
    return 0;
}

- (CGFloat) magnification {
    return 0;
}

// No pressure stages: only the mouse (NSEvent_mouse) and tablet (NSEvent_tablet) classes carry
// pressure. The tablet accessors have neutral values on every other event.
- (float) pressure {
    return 0;
}

- (NSInteger) stage {
    return 0;
}

- (CGFloat) stageTransition {
    return 0;
}

// The private spelling, which returns the same event.
- (void *) _eventRef {
    return (void *) [self eventRef];
}

- (float) rotation {
    return 0;
}

- (NSInteger) absoluteX {
    return 0;
}

- (NSInteger) absoluteY {
    return 0;
}

- (NSInteger) absoluteZ {
    return 0;
}

- (NSEventButtonMask) buttonMask {
    return 0;
}

- (NSPoint) tilt {
    return NSZeroPoint;
}

- (float) tangentialPressure {
    return 0;
}

- (NSUInteger) vendorID {
    return 0;
}

- (NSUInteger) tabletID {
    return 0;
}

- (NSUInteger) pointingDeviceID {
    return 0;
}

- (NSUInteger) deviceID {
    return 0;
}

- (NSUInteger) systemTabletID {
    return 0;
}

- (NSUInteger) vendorPointingDeviceType {
    return 0;
}

- (NSUInteger) pointingDeviceSerialNumber {
    return 0;
}

- (unsigned long long) uniqueID {
    return 0;
}

- (NSUInteger) capabilityMask {
    return 0;
}

- (NSPointingDeviceType) pointingDeviceType {
    return NSPointingDeviceTypeUnknown;
}

- (BOOL) isEnteringProximity {
    return NO;
}

- (NSString *) characters {
    return nil;
}

- (NSString *) charactersIgnoringModifiers {
    return nil;
}

- (unsigned short) keyCode {
    return 0xFFFF;
}

- (NSString *) description {
    return [NSString
            stringWithFormat:
                    @"<NSEvent: type=%lu loc=(%f,%f) time=%f flags=0x%lX "
                    @"win=%p winNum=%lu>",
                    (unsigned long) [self type], [self locationInWindow].x,
                    [self locationInWindow].y, [self timestamp],
                    (unsigned long) [self modifierFlags], [self window],
                    (unsigned long) [self windowNumber]];
}

static NSTimer *_periodicTimer = nil;

+ (void) _periodicDelay: (NSTimer *) timer {
    NSTimeInterval period = [[timer userInfo] doubleValue];

    [_periodicTimer invalidate];
    [_periodicTimer release];

    _periodicTimer = [[NSTimer timerWithTimeInterval: period
                                              target: self
                                            selector: @selector(_periodicEvent:)
                                            userInfo: nil
                                             repeats: YES] retain];

    [[NSRunLoop currentRunLoop] addTimer: _periodicTimer
                                 forMode: NSEventTrackingRunLoopMode];
}

+ (void) _periodicEvent: (NSTimer *) timer {
    NSEvent *event = [[[NSEvent_periodic alloc] initWithType: NSPeriodic
                                                    location: NSZeroPoint
                                               modifierFlags: 0
                                                      window: nil] autorelease];

    // Only the newest periodic event stays queued
    _NSEventQueuePost(event, NO);
    _NSEventQueueDiscard(NSPeriodicMask, event);
}

+ (void) startPeriodicEventsAfterDelay: (NSTimeInterval) delay
                            withPeriod: (NSTimeInterval) period
{
    NSNumber *userInfo = [NSNumber numberWithDouble: period];

    if (_periodicTimer != nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"periodic events already enabled"];

    _periodicTimer = [[NSTimer timerWithTimeInterval: delay
                                              target: self
                                            selector: @selector(_periodicDelay:)
                                            userInfo: userInfo
                                             repeats: NO] retain];

    [[NSRunLoop currentRunLoop] addTimer: _periodicTimer
                                 forMode: NSEventTrackingRunLoopMode];
}

+ (void) stopPeriodicEvents {
    [_periodicTimer invalidate];
    [_periodicTimer release];
    _periodicTimer = nil;
}

- (short) subtype {
    [NSException raise: NSInternalInconsistencyException
                format: @"No event subtype in %@", [self class]];
    return 0;
}

- (NSInteger) data1 {
    [NSException raise: NSInternalInconsistencyException
                format: @"No event data1 in %@", [self class]];
    return 0;
}

- (NSInteger) data2 {
    [NSException raise: NSInternalInconsistencyException
                format: @"No event data2 in %@", [self class]];
    return 0;
}

- (void *) userData {
    [NSException raise: NSInternalInconsistencyException
                format: @"No userData in %@", [self class]];
    return 0;
}

- (NSInteger) trackingNumber {
    [NSException raise: NSInternalInconsistencyException
                format: @"No trackingNumber in %@", [self class]];
    return 0;
}

- (NSTrackingArea *) trackingArea {
    [NSException raise: NSInternalInconsistencyException
                format: @"No trackingArea in %@", [self class]];
    return nil;
}

- (BOOL) isARepeat {
    return FALSE;
}

- (NSInteger) buttonNumber {
    return 0;
}

+ (id) addLocalMonitorForEventsMatchingMask: (NSEventMask) mask
                                    handler: (NSEvent * (^)(NSEvent *event)) block
{
    if (block == nil)
        return nil;

    if (localEventMonitors == nil)
        localEventMonitors = [[NSMutableArray alloc] init];

    NSLocalEventMonitor *monitor = [[NSLocalEventMonitor alloc] init];
    monitor->_mask = mask;
    monitor->_handler = [block copy];
    [localEventMonitors addObject: monitor];
    return [monitor autorelease];
}

+ (id) addGlobalMonitorForEventsMatchingMask: (NSEventMask) mask
                                      handler: (void (^)(NSEvent *event)) block
{
    // A global monitor is for events that go to other applications. Neither
    // X11 nor Wayland lets a client see another client's input (Wayland
    // deliberately; X11 only through grabs or XInput2 root-window selection,
    // which would also steal or duplicate this application's own input), so
    // the handler never fires. The returned monitor is a valid token that
    // removeMonitor: accepts, which is all that callers can observe on a
    // system where the event stream of the other applications is hidden from
    // them, as when macOS withholds it without accessibility permission.
    if (block == nil)
        return nil;

    if (globalEventMonitors == nil)
        globalEventMonitors = [[NSMutableArray alloc] init];

    NSGlobalEventMonitor *monitor = [[NSGlobalEventMonitor alloc] init];
    monitor->_mask = mask;
    monitor->_handler = [block copy];
    [globalEventMonitors addObject: monitor];
    return [monitor autorelease];
}

+ (void) removeMonitor: (id) eventMonitor {
    // Removing a monitor that is already removed, or nil, does nothing.
    [localEventMonitors removeObjectIdenticalTo: eventMonitor];
    [globalEventMonitors removeObjectIdenticalTo: eventMonitor];
}

@end

NSEventMask NSEventMaskFromType(NSEventType type) {
    // Types from 32 up (touches) need the full width; NSAppKitSystem has no bit.
    return type < 64 ? 1ULL << type : 0;
}
