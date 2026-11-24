/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// AppKit's events are the events of HIToolbox's main event queue.
//
// - The window system's input enters as CGEvents: the backend's events go through the event taps
//   of the process into the CoreGraphics event stream, which HIToolbox reads into the main queue
//   while the main thread waits for events (coalescing mouse motion there).
// - An event the application posts (-[NSApplication postEvent:atStart:]) goes into the same queue
//   as a Carbon event made from its CGEvent, so Carbon's queue functions see it, and Carbon events
//   posted with PostEventToQueue() reach AppKit.
// - -[NSApplication nextEventMatchingMask:...] waits in HIToolbox (in the run loop mode it is
//   given) and turns the Carbon event it takes into an NSEvent that keeps the CGEvent and the
//   Carbon event (-CGEvent, -eventRef).
//
// Interim (darlinghq/darling#937): until the window system backends decode input into CGEvents
// themselves, the NSEvent a backend built travels with the CGEvent (_CGSEventSetClientData), as it
// carries what a CGEvent cannot (input method text, gesture phases, tablet data, tracking areas).
// It is used when no event tap changed the event; otherwise the NSEvent is made from the
// CGEvent's fields. Events the application posts travel the same way, so that it gets back the
// object it posted.

#import "NSEventQueue.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent_mouse.h>
#import <AppKit/NSEvent_keyboard.h>
#import <AppKit/NSEvent_other.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <HIToolbox/CarbonEvents.h>
#import <HIToolbox/CarbonEventsCore.h>

// The interface of HIToolbox for AppKit. HIToolbox declares it in its private header
// (HIToolboxPrivate.h, not part of the SDK).
typedef Boolean (*HIEventMatchProc)(EventRef event, void *info);
extern OSStatus _HIPostEventToQueueAtHead(EventQueueRef queue, EventRef event);
extern OSStatus _HIReceiveNextEventMatchingWithOptions(HIEventMatchProc match, void *info, CFStringRef runLoopMode,
                                                       EventTimeout timeout, OptionBits options, EventRef *outEvent);
extern OSStatus _HIFlushEventsMatching(EventQueueRef queue, HIEventMatchProc match, void *info, EventRef beforeEvent);
extern void _HIBeginEventStreamReading(void);
enum {
    kHIReceiveNextEventPull = 1 << 0,
    kHIReceiveNextEventFilterIsPure = 1 << 1,
    kHIReceiveNextEventSinglePass = 1 << 2,
};

// NSEventMaskAny is NSUIntegerMax, which is only 32 bits wide in a 32-bit process, so it has no bit
// for the event types from 32 up (direct touch is 37). Such a mask still asks for every event.
static inline BOOL maskSelectsType(NSEventMask mask, NSEventType type) {
    return mask == NSEventMaskAny || (NSEventMaskFromType(type) & mask) != 0;
}

static inline BOOL isMouseMotionType(NSEventType type) {
    return type == NSMouseMoved || type == NSLeftMouseDragged || type == NSRightMouseDragged ||
           type == NSOtherMouseDragged;
}

// What AppKit makes of a queued event
typedef enum {
    QueuedEventNone,     // nothing AppKit knows: only Carbon handlers take it
    QueuedEventCarbon,   // a Carbon keyboard or mouse event without a CGEvent: it counts as an
                         // event of that type for masks, but Carbon handlers take it
    QueuedEventNSEvent,  // made from a CGEvent: an NSEvent
} QueuedEventKind;

static QueuedEventKind classifyQueuedEvent(EventRef event, NSEventType *outType) {
    CGEventRef cgEvent = CopyEventCGEvent(event);

    if (cgEvent != NULL) {
        *outType = (NSEventType) CGEventGetType(cgEvent);
        CFRelease(cgEvent);
        return QueuedEventNSEvent;
    }

    UInt32 kind = GetEventKind(event);
    switch (GetEventClass(event)) {
    case kEventClassKeyboard:
        if (kind == kEventRawKeyDown || kind == kEventRawKeyRepeat) {
            *outType = NSKeyDown;
            return QueuedEventCarbon;
        }
        if (kind == kEventRawKeyUp) {
            *outType = NSKeyUp;
            return QueuedEventCarbon;
        }
        if (kind == kEventRawKeyModifiersChanged) {
            *outType = NSFlagsChanged;
            return QueuedEventCarbon;
        }
        break;
    case kEventClassMouse:
        switch (kind) {
        case kEventMouseDown: *outType = NSLeftMouseDown; return QueuedEventCarbon;
        case kEventMouseUp: *outType = NSLeftMouseUp; return QueuedEventCarbon;
        case kEventMouseMoved: *outType = NSMouseMoved; return QueuedEventCarbon;
        case kEventMouseDragged: *outType = NSLeftMouseDragged; return QueuedEventCarbon;
        case kEventMouseWheelMoved: *outType = NSScrollWheel; return QueuedEventCarbon;
        }
        break;
    }
    *outType = 0;
    return QueuedEventNone;
}

struct NextEventFilter {
    NSEventMask mask;
    BOOL dequeue;
};

// QUIRK: -nextEventMatchingMask:... returns only events made from a CGEvent. A Carbon event without
// one is taken only by a call that dequeues: a keyboard or mouse event when the mask selects its
// type, any other event only for NSEventMaskAny; it then goes to the event dispatcher target and the
// call returns nil. A call that only looks (dequeue NO) passes over such events. Not documented.
// Evidence: black-box observation on macOS 26.7.3 (tier 2, vd-upstream/mac-probes/937-a4-events.m:
// P3, P5, P7, P10). Test: tests/appkit-carbon-event-queue.m (testQuirkCarbonOnlyEvents)
static Boolean nextEventFilter(EventRef event, void *info) {
    const struct NextEventFilter *filter = info;
    NSEventType type;

    switch (classifyQueuedEvent(event, &type)) {
    case QueuedEventNSEvent:
        return maskSelectsType(filter->mask, type);
    case QueuedEventCarbon:
        return filter->dequeue && maskSelectsType(filter->mask, type);
    case QueuedEventNone:
    default:
        return filter->dequeue && filter->mask == NSEventMaskAny;
    }
}

struct DiscardFilter {
    NSEventMask mask;
    NSUInteger removed;
};

// QUIRK: -discardEventsMatchingMask:beforeEvent: removes Carbon keyboard and mouse events that
// have no CGEvent by their type, and never removes Carbon events of other classes. Not documented.
// Evidence: black-box observation on macOS 26.7.3 (tier 2, vd-upstream/mac-probes/937-a4-events.m:
// P5). Test: tests/appkit-carbon-event-queue.m (testQuirkCarbonOnlyEvents)
static Boolean discardFilter(EventRef event, void *info) {
    struct DiscardFilter *filter = info;
    NSEventType type;

    if (classifyQueuedEvent(event, &type) == QueuedEventNone || !maskSelectsType(filter->mask, type))
        return false;
    filter->removed++;
    return true;
}

static Boolean carriesEvent(EventRef event, void *info) {
    CGEventRef cgEvent = CopyEventCGEvent(event);
    BOOL carries = cgEvent != NULL && _CGSEventGetClientData(cgEvent) == info;

    if (cgEvent != NULL)
        CFRelease(cgEvent);
    return carries;
}

@interface NSDisplay (NSEventQueueScreen)
- (CGFloat) _mainScreenMaxY;
@end

// Kept by the display, which forgets it when the screens change
CGFloat _NSEventMainScreenMaxY(void) {
    return [[NSDisplay currentDisplay] _mainScreenMaxY];
}

// Conversions

static CGPoint globalLocation(NSEvent *event, CGFloat mainScreenMaxY) {
    NSPoint point = [event locationInWindow];
    NSWindow *window = [event window];

    if (window != nil)
        point = [window convertBaseToScreen: point];
    return CGPointMake(point.x, mainScreenMaxY - point.y);
}

// The global location of a CGEvent in AppKit's screen coordinates
static NSPoint screenLocation(CGEventRef cgEvent) {
    CGPoint point = CGEventGetLocation(cgEvent);
    return NSMakePoint(point.x, _NSEventMainScreenMaxY() - point.y);
}

static uint32_t scrollPhaseFromEventPhase(NSEventPhase phase) {
    uint32_t result = 0;

    if (phase & NSEventPhaseBegan)
        result |= kCGScrollPhaseBegan;
    if (phase & (NSEventPhaseChanged | NSEventPhaseStationary))
        result |= kCGScrollPhaseChanged;
    if (phase & NSEventPhaseEnded)
        result |= kCGScrollPhaseEnded;
    if (phase & NSEventPhaseCancelled)
        result |= kCGScrollPhaseCancelled;
    if (phase & NSEventPhaseMayBegin)
        result |= kCGScrollPhaseMayBegin;
    return result;
}

static NSEventPhase eventPhaseFromScrollPhase(int64_t phase) {
    NSEventPhase result = NSEventPhaseNone;

    if (phase & kCGScrollPhaseBegan)
        result |= NSEventPhaseBegan;
    if (phase & kCGScrollPhaseChanged)
        result |= NSEventPhaseChanged;
    if (phase & kCGScrollPhaseEnded)
        result |= NSEventPhaseEnded;
    if (phase & kCGScrollPhaseCancelled)
        result |= NSEventPhaseCancelled;
    if (phase & kCGScrollPhaseMayBegin)
        result |= NSEventPhaseMayBegin;
    return result;
}

CGEventRef _NSEventCreateCGEvent(NSEvent *event, CGFloat mainScreenMaxY) {
    NSEventType type = [event type];
    CGPoint location = globalLocation(event, mainScreenMaxY);
    CGEventRef cgEvent = NULL;

    switch (type) {
    case NSLeftMouseDown:
    case NSLeftMouseUp:
    case NSRightMouseDown:
    case NSRightMouseUp:
    case NSMouseMoved:
    case NSLeftMouseDragged:
    case NSRightMouseDragged:
    case NSOtherMouseDown:
    case NSOtherMouseUp:
    case NSOtherMouseDragged: {
        // The mouse event types have the same values in both enums
        NSInteger button = [event buttonNumber];
        cgEvent = CGEventCreateMouseEvent(NULL, (CGEventType) type, location, (CGMouseButton) button);
        if (cgEvent == NULL)
            break;
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventButtonNumber, button);
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventClickState, [event clickCount]);
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventNumber, [event eventNumber]);
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventDeltaX, (int64_t) [event deltaX]);
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventDeltaY, (int64_t) [event deltaY]);
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventWindowUnderMousePointer, [event windowNumber]);
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                                    [event windowNumber]);
        break;
    }
    case NSScrollWheel: {
        CGFloat deltaY = [event deltaY], deltaX = [event deltaX];
        cgEvent = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 2, (int32_t) deltaY, (int32_t) deltaX);
        if (cgEvent == NULL)
            break;
        CGEventSetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis1, deltaY);
        CGEventSetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis2, deltaX);
        if ([event hasPreciseScrollingDeltas]) {
            CGEventSetIntegerValueField(cgEvent, kCGScrollWheelEventIsContinuous, 1);
            CGEventSetIntegerValueField(cgEvent, kCGScrollWheelEventPointDeltaAxis1, (int64_t) [event scrollingDeltaY]);
            CGEventSetIntegerValueField(cgEvent, kCGScrollWheelEventPointDeltaAxis2, (int64_t) [event scrollingDeltaX]);
            CGEventSetIntegerValueField(cgEvent, kCGScrollWheelEventScrollPhase, scrollPhaseFromEventPhase([event phase]));
        }
        break;
    }
    case NSKeyDown:
    case NSKeyUp:
    case NSFlagsChanged: {
        cgEvent = CGEventCreateKeyboardEvent(NULL, [event keyCode], type != NSKeyUp);
        if (cgEvent == NULL)
            break;
        CGEventSetType(cgEvent, (CGEventType) type);
        if (type != NSFlagsChanged) {
            NSString *characters = [event characters];
            NSUInteger length = [characters length];
            if (length > 0) {
                UniChar stackBuffer[32];
                UniChar *buffer = length <= 32 ? stackBuffer : malloc(length * sizeof(UniChar));
                [characters getCharacters: buffer range: NSMakeRange(0, length)];
                CGEventKeyboardSetUnicodeString(cgEvent, length, buffer);
                if (buffer != stackBuffer)
                    free(buffer);
            }
            CGEventSetIntegerValueField(cgEvent, kCGKeyboardEventAutorepeat, [event isARepeat]);
        }
        break;
    }
    case NSAppKitDefined:
    case NSSystemDefined:
    case NSApplicationDefined:
    case NSPeriodic: {
        // These events are event records, which carry the subtype and the two data words (as 32-bit
        // values, which is what the record has room for)
        CGSEventRecord record;
        memset(&record, 0, sizeof(record));
        record.length = sizeof(record);
        record.type = (int32_t) type;
        record.location = location;
        record.windowLocation = location;
        record.time = (CGSEventRecordTime) ([event timestamp] * 1e9);
        // NSEventModifierFlags and CGEventFlags use the same bits
        record.flags = (CGEventFlags) [event modifierFlags];
        record.window = (CGSWindowID) [event windowNumber];
        if ([event isKindOfClass: [NSEvent_other class]]) {
            record.data.compound.subType = [event subtype];
            record.data.compound.misc.L[0] = (SInt32) [event data1];
            record.data.compound.misc.L[1] = (SInt32) [event data2];
        }
        cgEvent = CGEventCreateWithEventRecord(&record, sizeof(record));
        break;
    }
    default:
        break;
    }

    if (cgEvent == NULL) {
        cgEvent = CGEventCreate(NULL);
        CGEventSetType(cgEvent, (CGEventType) type);
    }

    CGEventSetLocation(cgEvent, location);
    // CGEvent times are nanoseconds on the clock NSEvent times count seconds of
    CGEventSetTimestamp(cgEvent, (CGEventTimestamp) ([event timestamp] * 1e9));
    CGEventSetFlags(cgEvent, (CGEventFlags) [event modifierFlags]);
    return cgEvent;
}

NSEvent *_NSEventCreateFromCGEvent(CGEventRef cgEvent) {
    CGEventType type = CGEventGetType(cgEvent);
    NSEventModifierFlags flags = (NSEventModifierFlags) CGEventGetFlags(cgEvent);
    NSTimeInterval timestamp = CGEventGetTimestamp(cgEvent) / 1e9;
    NSEvent *result = nil;

    switch (type) {
    case kCGEventLeftMouseDown:
    case kCGEventLeftMouseUp:
    case kCGEventRightMouseDown:
    case kCGEventRightMouseUp:
    case kCGEventMouseMoved:
    case kCGEventLeftMouseDragged:
    case kCGEventRightMouseDragged:
    case kCGEventOtherMouseDown:
    case kCGEventOtherMouseUp:
    case kCGEventOtherMouseDragged:
    case kCGEventScrollWheel: {
        NSInteger windowNumber = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent);
        if (windowNumber == 0)
            windowNumber = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGMouseEventWindowUnderMousePointer);
        NSWindow *window = windowNumber != 0 ? [NSApp windowWithWindowNumber: windowNumber] : nil;
        NSPoint location = screenLocation(cgEvent);
        if (window != nil)
            location = [window convertScreenToBase: location];
        else
            windowNumber = 0;

        NSEvent_mouse *mouse;
        if (type == kCGEventScrollWheel) {
            mouse = [[NSEvent_mouse alloc] initWithType: NSScrollWheel
                                               location: location
                                          modifierFlags: flags
                                                 window: window
                                                 deltaY: CGEventGetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis1)];
            [mouse _setDeltaX: CGEventGetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis2)
                       deltaY: CGEventGetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis1)];
            if (CGEventGetIntegerValueField(cgEvent, kCGScrollWheelEventIsContinuous))
                [mouse _setPreciseScrollingDeltaX: CGEventGetIntegerValueField(cgEvent, kCGScrollWheelEventPointDeltaAxis2)
                                           deltaY: CGEventGetIntegerValueField(cgEvent, kCGScrollWheelEventPointDeltaAxis1)
                                            phase: eventPhaseFromScrollPhase(CGEventGetIntegerValueField(cgEvent, kCGScrollWheelEventScrollPhase))];
        } else {
            mouse = [[NSEvent_mouse alloc] initWithType: (NSEventType) type
                                               location: location
                                          modifierFlags: flags
                                              timestamp: timestamp
                                           windowNumber: windowNumber
                                                context: nil
                                            eventNumber: CGEventGetIntegerValueField(cgEvent, kCGMouseEventNumber)
                                             clickCount: CGEventGetIntegerValueField(cgEvent, kCGMouseEventClickState)
                                               pressure: CGEventGetDoubleValueField(cgEvent, kCGMouseEventPressure)];
            [mouse _setButtonNumber: CGEventGetIntegerValueField(cgEvent, kCGMouseEventButtonNumber)];
            [mouse _setDeltaX: CGEventGetIntegerValueField(cgEvent, kCGMouseEventDeltaX)
                       deltaY: CGEventGetIntegerValueField(cgEvent, kCGMouseEventDeltaY)];
        }
        result = mouse;
        break;
    }
    case kCGEventKeyDown:
    case kCGEventKeyUp:
    case kCGEventFlagsChanged: {
        UniChar buffer[256];
        UniCharCount length = 0;
        NSString *characters = @"";
        if (type != kCGEventFlagsChanged) {
            CGEventKeyboardGetUnicodeString(cgEvent, 256, &length, buffer);
            characters = [NSString stringWithCharacters: buffer length: MIN(length, (UniCharCount) 256)];
        }
        // The characters without the modifiers other than Shift come with the event when the window system
        // posted it (the window system's keyboard) and no tap gave the event another key code; otherwise
        // they are the characters.
        NSString *unmodified = characters;
        int64_t unmodifiedLength = CGEventGetIntegerValueField(cgEvent, kCGSKeyboardEventUnmodifiedLength);
        if (type != kCGEventFlagsChanged && unmodifiedLength > 0 &&
            CGEventGetIntegerValueField(cgEvent, kCGSKeyboardEventUnmodifiedKeyCode) ==
                    CGEventGetIntegerValueField(cgEvent, kCGKeyboardEventKeycode)) {
            UniChar units[4];
            int64_t packed = CGEventGetIntegerValueField(cgEvent, kCGSKeyboardEventUnmodifiedUnicode);
            if (unmodifiedLength > 4)
                unmodifiedLength = 4;
            for (int64_t i = 0; i < unmodifiedLength; i++)
                units[i] = (UniChar) (packed >> (16 * i));
            unmodified = [NSString stringWithCharacters: units length: (NSUInteger) unmodifiedLength];
        }
        // The display says which window the event is for
        NSInteger windowNumber = 0;
        NSPoint keyLocation = NSZeroPoint;
        NSDisplay *display = [NSDisplay currentDisplay];
        if (![display windowNumber: &windowNumber location: &keyLocation forKeyEvent: cgEvent])
            return nil;
        result = [NSEvent keyEventWithType: (NSEventType) type
                                  location: keyLocation
                             modifierFlags: flags
                                 timestamp: timestamp
                              windowNumber: windowNumber
                                   context: nil
                                characters: characters
                charactersIgnoringModifiers: unmodified
                                 isARepeat: CGEventGetIntegerValueField(cgEvent, kCGKeyboardEventAutorepeat) != 0
                                   keyCode: (unsigned short) CGEventGetIntegerValueField(cgEvent, kCGKeyboardEventKeycode)];
        [display keyEventCreated: result fromCGEvent: cgEvent];
        return [result retain];
    }
    case NSAppKitDefined:
    case NSSystemDefined:
    case NSApplicationDefined:
    case NSPeriodic: {
        CGSEventRecord record;
        memset(&record, 0, sizeof(record));
        BOOL hasRecord = CGEventGetEventRecordSize(cgEvent) > 0 &&
                         CGEventGetEventRecord(cgEvent, &record, sizeof(record)) == kCGErrorSuccess;
        result = [[NSEvent_other alloc] initWithType: (NSEventType) type
                                            location: screenLocation(cgEvent)
                                       modifierFlags: flags
                                           timestamp: timestamp
                                        windowNumber: hasRecord ? record.window : 0
                                             context: nil
                                             subtype: hasRecord ? record.data.compound.subType : 0
                                               data1: hasRecord ? record.data.compound.misc.L[0] : 0
                                               data2: hasRecord ? record.data.compound.misc.L[1] : 0];
        break;
    }
    default:
        result = [[NSEvent alloc] initWithType: (NSEventType) type
                                      location: screenLocation(cgEvent)
                                 modifierFlags: flags
                                        window: nil];
        break;
    }
    return result;
}

// Queue

void _NSEventQueueBeginReading(void) {
    _HIBeginEventStreamReading();
}

void _NSEventQueuePostWindowSystemEvent(NSEvent *event, CGFloat mainScreenMaxY) {
    CGEventRef cgEvent = _NSEventCreateCGEvent(event, mainScreenMaxY);

    _CGSEventSetClientData(cgEvent, (CFTypeRef) event);
    _CGSEventStreamPost(cgEvent);
    CFRelease(cgEvent);
}

void _NSEventQueuePost(NSEvent *event, BOOL atStart) {
    if (event == nil)
        return;

    // The queued event carries the NSEvent: it must not be the CGEvent the NSEvent keeps, which
    // would then keep the NSEvent
    CGEventRef stored = [event _storedCGEvent];
    CGEventRef cgEvent = stored != NULL ? CGEventCreateCopy(stored) : _NSEventCreateCGEvent(event, _NSEventMainScreenMaxY());
    EventRef carbonEvent = NULL;

    _CGSEventSetClientData(cgEvent, (CFTypeRef) event);
    OSStatus status = CreateEventWithCGEvent(NULL, cgEvent, kEventAttributeNone, &carbonEvent);
    CFRelease(cgEvent);
    if (status != noErr)
        return;

    if (atStart)
        _HIPostEventToQueueAtHead(GetMainEventQueue(), carbonEvent);
    else
        PostEventToQueue(GetMainEventQueue(), carbonEvent, kEventPriorityStandard);
    ReleaseEvent(carbonEvent);
}

// The NSEvent of a queued Carbon event that has a CGEvent. While the Carbon event stays queued the
// NSEvent stays attached to the CGEvent, so a later look at the queue gives the same object; once
// it leaves the queue, the NSEvent keeps the CGEvent and the Carbon event instead.
static NSEvent *eventForQueuedEvent(EventRef carbonEvent, CGEventRef cgEvent, BOOL dequeued) {
    id attached = (id) _CGSEventGetClientData(cgEvent);
    NSEvent *event = [attached isKindOfClass: [NSEvent class]] ? [[attached retain] autorelease] : nil;

    if (event == nil) {
        event = [_NSEventCreateFromCGEvent(cgEvent) autorelease];
        if (event == nil)
            return nil;
        if (!dequeued)
            _CGSEventSetClientData(cgEvent, (CFTypeRef) event);
    } else if (dequeued && isMouseMotionType([event type]) && [event isKindOfClass: [NSEvent_mouse class]]) {
        // Coalescing added the deltas of the events it dropped to the CGEvent
        NSEvent_mouse *mouse = (NSEvent_mouse *) event;
        CGFloat moreX = CGEventGetIntegerValueField(cgEvent, kCGMouseEventDeltaX) - (int64_t) [mouse deltaX];
        CGFloat moreY = CGEventGetIntegerValueField(cgEvent, kCGMouseEventDeltaY) - (int64_t) [mouse deltaY];
        if (moreX != 0 || moreY != 0)
            [mouse _setDeltaX: [mouse deltaX] + moreX deltaY: [mouse deltaY] + moreY];
    }

    if (dequeued) {
        _CGSEventSetClientData(cgEvent, NULL);
        [event _setCGEvent: cgEvent eventRef: carbonEvent];
    }
    return event;
}

NSEvent *_NSEventQueueNextEvent(NSEventMask mask, NSDate *untilDate, NSString *mode, BOOL dequeue) {
    struct NextEventFilter filter = {mask, dequeue};
    NSTimeInterval timeout = untilDate != nil ? [untilDate timeIntervalSinceNow] : 0;
    OptionBits options = kHIReceiveNextEventSinglePass | kHIReceiveNextEventFilterIsPure;
    EventRef carbonEvent = NULL;

    if (timeout < 0)
        timeout = 0;
    if (dequeue)
        options |= kHIReceiveNextEventPull;
    if (_HIReceiveNextEventMatchingWithOptions(nextEventFilter, &filter, (CFStringRef) mode, timeout, options,
                                               &carbonEvent) != noErr)
        return nil;

    CGEventRef cgEvent = CopyEventCGEvent(carbonEvent);
    if (!dequeue) {
        // The queue keeps the event; it was only looked at
        NSEvent *event = cgEvent != NULL ? eventForQueuedEvent(carbonEvent, cgEvent, NO) : nil;
        if (cgEvent != NULL)
            CFRelease(cgEvent);
        return event;
    }

    if (cgEvent == NULL) {
        // A Carbon event AppKit has no NSEvent for goes to the Carbon handlers
        SendEventToEventTarget(carbonEvent, GetEventDispatcherTarget());
        ReleaseEvent(carbonEvent);
        return nil;
    }

    NSEvent *event = eventForQueuedEvent(carbonEvent, cgEvent, YES);

    // QUIRK: a mouse event taken from the queue goes to the Carbon handlers of the event dispatcher
    // target (which passes it on to the application target) before AppKit returns it; when a
    // handler handles it, AppKit does not return it at all. Not documented. Evidence: black-box
    // observation on macOS 26.7.3 (tier 2, vd-upstream/mac-probes/937-a4-events.m: P1, P2, P8, P12;
    // the design in darlinghq/darling#937, section 2.6): posted mouse-down and mouse-moved events,
    // the handlers run inside -nextEventMatchingMask: (also in the event tracking mode), not for a
    // call that does not dequeue, before -sendEvent: and the local monitors.
    // Test: tests/appkit-carbon-event-queue.m (testQuirkMouseEventsPassCarbonHandlers)
    if (GetEventClass(carbonEvent) == kEventClassMouse) {
        if (SendEventToEventTarget(carbonEvent, GetEventDispatcherTarget()) == noErr)
            event = nil;
    }

    CFRelease(cgEvent);
    ReleaseEvent(carbonEvent);
    return event;
}

NSUInteger _NSEventQueueDiscard(NSEventMask mask, NSEvent *beforeEvent) {
    EventQueueRef queue = GetMainEventQueue();
    EventRef before = NULL;

    if (beforeEvent != nil) {
        // Events in front of the given one. One that is not queued (any more) removes nothing.
        before = FindSpecificEventInQueue(queue, carriesEvent, beforeEvent);
        if (before == NULL)
            return 0;
    }

    struct DiscardFilter filter = {mask, 0};
    _HIFlushEventsMatching(queue, discardFilter, &filter, before);
    return filter.removed;
}

@implementation NSEvent (NSEventQueue)

- (void) _setCGEvent: (CGEventRef) cgEvent eventRef: (void *) eventRef {
    if (cgEvent != NULL) {
        CGEventRef expected = NULL;
        CFRetain(cgEvent);
        if (!__atomic_compare_exchange_n(&NS_EXTRA(NSEvent, self)->_cgEvent, &expected, cgEvent, 0,
                                         __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
            CFRelease(cgEvent);
    }
    if (eventRef != NULL) {
        void *expected = NULL;
        RetainEvent((EventRef) eventRef);
        if (!__atomic_compare_exchange_n(&NS_EXTRA(NSEvent, self)->_eventRef, &expected, eventRef, 0,
                                         __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
            ReleaseEvent((EventRef) eventRef);
    }
}

- (CGEventRef) _storedCGEvent {
    return __atomic_load_n(&NS_EXTRA(NSEvent, self)->_cgEvent, __ATOMIC_ACQUIRE);
}

@end
