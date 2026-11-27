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
// Identity of NSEvents: the window system's input reaches AppKit only as CGEvents, from which the
// NSEvent is made (input method text and the like are added by the display's keyEventCreated: and
// pointerEventCreated: hooks). An NSEvent that AppKit or the application itself made and queued
// (-[NSApplication postEvent:atStart:], the events AppKit synthesises from touches) travels with
// its CGEvent as the object attached to it (_CGSEventSetClientData), so that whoever dequeues it
// gets back the object that was posted. The attached object is used while no event tap has changed
// the event; otherwise the NSEvent is made from the CGEvent's fields.

#import "NSEventQueue.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent_mouse.h>
#import "NSEvent.subproj/NSEvent_tablet.h"
#import "NSEvent_gesture.h"
#import <AppKit/NSEvent_keyboard.h>
#import <AppKit/NSEvent_other.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSTouch.h>
#import <AppKit/NSEvent_touch.h>
#import <AppKit/NSTouchBackend.h>
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
typedef void (*HIEventStreamEmitProc)(CGEventRef event, void *info);
typedef void (*HIEventStreamFilterProc)(CGEventRef event, HIEventStreamEmitProc emit, void *info);
extern void _HISetEventStreamFilter(HIEventStreamFilterProc filter);
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

// Touch events

// The NSTouchPhase of a touch event's phase field, 0 for an event that is not a change of a finger
static NSTouchPhase touchPhaseOfCGEvent(CGEventRef cgEvent) {
    if (CGEventGetType(cgEvent) != (CGEventType) kCGSEventTypeGesture)
        return (NSTouchPhase) 0;
    switch (CGEventGetIntegerValueField(cgEvent, kCGSTouchPhase)) {
    case kCGSTouchPhaseBegan:
        return NSTouchPhaseBegan;
    case kCGSTouchPhaseMoved:
        return NSTouchPhaseMoved;
    case kCGSTouchPhaseEnded:
        return NSTouchPhaseEnded;
    case kCGSTouchPhaseCancelled:
        return NSTouchPhaseCancelled;
    default:
        return (NSTouchPhase) 0;
    }
}

// The window a touch event is for and the finger's location in its base coordinates (NAN for a finger
// without a position). The window is named by the window system's handle or, for an event of the
// application, by its number (kCGSTouchWindowNumber).
static NSWindow *touchEventWindow(CGEventRef cgEvent, NSPoint *outLocation) {
    NSInteger windowNumber = 0;
    NSPoint location = NSZeroPoint;
    BOOL hasLocation = NO;

    if (CGEventGetIntegerValueField(cgEvent, kCGSEventNativeWindow) != 0)
        [[NSDisplay currentDisplay] windowNumber: &windowNumber
                                        location: &location
                                     hasLocation: &hasLocation
                                 forPointerEvent: cgEvent];
    else
        windowNumber = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGSTouchWindowNumber);
    NSWindow *window = windowNumber != 0 ? [NSApp windowWithWindowNumber: windowNumber] : nil;

    if (CGEventGetIntegerValueField(cgEvent, kCGSTouchLocationUnknown) != 0)
        location = NSMakePoint(NAN, NAN);
    else if (window != nil && !hasLocation)
        location = [window convertScreenToBase: screenLocation(cgEvent)];
    else if (window == nil)
        location = screenLocation(cgEvent);
    *outLocation = location;
    return window;
}

static NSPoint touchNormalizedPosition(CGEventRef cgEvent) {
    return NSMakePoint(CGEventGetIntegerValueField(cgEvent, kCGSTouchNormalizedX) / 1000000.0,
                       CGEventGetIntegerValueField(cgEvent, kCGSTouchNormalizedY) / 1000000.0);
}

static NSSize touchDeviceSize(CGEventRef cgEvent) {
    return NSMakeSize(CGEventGetIntegerValueField(cgEvent, kCGSTouchDeviceWidth) / 1024.0,
                      CGEventGetIntegerValueField(cgEvent, kCGSTouchDeviceHeight) / 1024.0);
}

// The reader of the event stream: a touch event (a change of a finger) becomes the events AppKit's touch handling
// makes of it (touch events, or the mouse events of a finger on a view that takes no touches), in the
// order of the stream; every other event is passed on.
static void streamFilter(CGEventRef cgEvent, HIEventStreamEmitProc emit, void *info) {
    NSTouchPhase phase = touchPhaseOfCGEvent(cgEvent);
    if (phase == 0) {
        emit(cgEvent, info);
        return;
    }

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSPoint location;
    NSWindow *window = touchEventWindow(cgEvent, &location);
    NSTimeInterval timestamp = CGEventGetTimestamp(cgEvent) / 1e9;
    NSArray *events = NSTouchEventsForReport(window, CGEventGetIntegerValueField(cgEvent, kCGSTouchIdentifier), phase,
                                             location, timestamp, touchNormalizedPosition(cgEvent),
                                             touchDeviceSize(cgEvent));

    for (NSEvent *event in events) {
        CGEventRef made = _NSEventCreateCGEvent(event, _NSEventMainScreenMaxY());

        if (made == NULL)
            continue;
        _CGSEventSetClientData(made, (CFTypeRef) event);
        emit(made, info);
        CFRelease(made);
    }
    [pool release];
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
    case NSEventTypeTabletPoint:
    case NSEventTypeTabletProximity: {
        cgEvent = CGEventCreate(NULL);
        if (cgEvent == NULL)
            break;
        CGEventSetType(cgEvent, (CGEventType) type);
        CGEventSetIntegerValueField(cgEvent, kCGTabletEventPointX, [event absoluteX]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletEventPointY, [event absoluteY]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletEventPointZ, [event absoluteZ]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletEventPointButtons, [event buttonMask]);
        CGEventSetDoubleValueField(cgEvent, kCGTabletEventPointPressure, [event pressure]);
        CGEventSetDoubleValueField(cgEvent, kCGTabletEventTiltX, [event tilt].x);
        CGEventSetDoubleValueField(cgEvent, kCGTabletEventTiltY, [event tilt].y);
        CGEventSetDoubleValueField(cgEvent, kCGTabletEventRotation, [event rotation]);
        CGEventSetDoubleValueField(cgEvent, kCGTabletEventTangentialPressure, [event tangentialPressure]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventVendorID, [event vendorID]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventTabletID, [event tabletID]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventPointerID, [event pointingDeviceID]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventDeviceID, [event deviceID]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventSystemTabletID, [event systemTabletID]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventVendorPointerType, [event vendorPointingDeviceType]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventVendorPointerSerialNumber,
                                    [event pointingDeviceSerialNumber]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventVendorUniqueID, [event uniqueID]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventCapabilityMask, [event capabilityMask]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventPointerType, [event pointingDeviceType]);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventEnterProximity, [event isEnteringProximity]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletPointerID, [event pointingDeviceID]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletSystemTabletID, [event systemTabletID]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletCapabilityMask, [event capabilityMask]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletVendorPointerType, [event vendorPointingDeviceType]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletPointerType, [event pointingDeviceType]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletVendorPointerSerialNumber, [event pointingDeviceSerialNumber]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletWindowNumber, [event windowNumber]);
        CGEventSetIntegerValueField(cgEvent, kCGSTabletWindowNumberThatCanHandleThisEvent, [event windowNumber]);
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
        // An event of the window system's pointer names the window by its native handle: the display knows
        // the window it belongs to, and where the pointer was in it.
        NSPoint windowLocation = NSZeroPoint;
        BOOL hasWindowLocation = NO;
        if (CGEventGetIntegerValueField(cgEvent, kCGSEventNativeWindow) != 0) {
            NSInteger nativeNumber = 0;
            if ([[NSDisplay currentDisplay] windowNumber: &nativeNumber
                                                location: &windowLocation
                                             hasLocation: &hasWindowLocation
                                         forPointerEvent: cgEvent])
                windowNumber = nativeNumber;
        }
        NSWindow *window = windowNumber != 0 ? [NSApp windowWithWindowNumber: windowNumber] : nil;
        NSPoint location = screenLocation(cgEvent);
        if (window != nil)
            location = hasWindowLocation ? windowLocation : [window convertScreenToBase: location];
        else
            windowNumber = 0;

        NSEvent_mouse *mouse;
        if (type == kCGEventScrollWheel) {
            mouse = [[NSEvent_mouse alloc] initWithType: NSScrollWheel
                                               location: location
                                          modifierFlags: flags
                                                 window: window
                                                 deltaY: CGEventGetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis1)];
            double lineDeltaX = CGEventGetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis2);
            double lineDeltaY = CGEventGetDoubleValueField(cgEvent, kCGScrollWheelEventFixedPtDeltaAxis1);
            // QUIRK: with Shift held, the NSEvent of a wheel of whole lines (not a continuous scroll) moves
            // the vertical delta to the horizontal axis (the horizontal delta when there is no vertical one)
            // and has no vertical delta, so that Shift and the wheel scroll sideways. The CGEvent keeps the
            // deltas it was made with, and a continuous scroll is not converted. Not documented. Evidence:
            // black-box observation of CGEventCreateScrollWheelEvent2 + NSEvent eventWithCGEvent: on
            // macOS 26.7.3 (tier 2): line (3,0), (3,2) and (0,3) with Shift give deltaX 3, deltaY 0; pixel
            // (25,10) with Shift gives the unchanged (1, 2.5). Test: appkit-scroll-cgevents-x11
            if ((flags & NSShiftKeyMask) && !CGEventGetIntegerValueField(cgEvent, kCGScrollWheelEventIsContinuous)) {
                lineDeltaX = lineDeltaY != 0 ? lineDeltaY : lineDeltaX;
                lineDeltaY = 0;
            }
            [mouse _setDeltaX: lineDeltaX deltaY: lineDeltaY];
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
            // Whether the window was the key window when the press arrived, as the window system's
            // framework judged it then.
            int64_t keyState = CGEventGetIntegerValueField(cgEvent, kCGSMouseEventWindowKeyState);
            if (keyState != 0)
                [mouse _setWindowWasKeyOnArrival: keyState == 1];
            [[NSDisplay currentDisplay] pointerEventCreated: mouse fromCGEvent: cgEvent];
        }
        result = mouse;
        break;
    }
    case kCGEventTabletPointer:
    case kCGEventTabletProximity: {
        // A tablet belongs to the window under the tool like the pointer does. The backend posts
        // the fields; AppKit only reads them, so the same protocol works for Wayland and X11.
        NSInteger windowNumber = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGSTabletWindowNumberThatCanHandleThisEvent);
        if (windowNumber == 0)
            windowNumber = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGSTabletWindowNumber);
        NSPoint windowLocation = NSZeroPoint;
        BOOL hasWindowLocation = NO;
        if (CGEventGetIntegerValueField(cgEvent, kCGSEventNativeWindow) != 0) {
            NSInteger nativeNumber = 0;
            if ([[NSDisplay currentDisplay] windowNumber: &nativeNumber
                                                location: &windowLocation
                                             hasLocation: &hasWindowLocation
                                         forPointerEvent: cgEvent])
                windowNumber = nativeNumber;
        }
        NSWindow *window = windowNumber != 0 ? [NSApp windowWithWindowNumber: windowNumber] : nil;
        NSPoint location = screenLocation(cgEvent);
        if (window != nil)
            location = hasWindowLocation ? windowLocation : [window convertScreenToBase: location];
        else
            windowNumber = 0;
        result = [[NSEvent_tablet alloc]
                initWithType: type == kCGEventTabletPointer ? NSEventTypeTabletPoint : NSEventTypeTabletProximity
                    location: location
               modifierFlags: flags
                   timestamp: timestamp
                windowNumber: windowNumber
                     context: nil
                     cgEvent: cgEvent];
        break;
    }
    case 18: // NSEventTypeRotate
    case 30: { // NSEventTypeMagnify
        // A gesture of the window system's pointer (a touchpad pinch): the window and the location in it as
        // for the mouse events, the phase and the amount from the fields of our own.
        NSInteger windowNumber = 0;
        NSPoint windowLocation = NSZeroPoint;
        BOOL hasWindowLocation = NO;
        if (CGEventGetIntegerValueField(cgEvent, kCGSEventNativeWindow) != 0)
            [[NSDisplay currentDisplay] windowNumber: &windowNumber
                                            location: &windowLocation
                                         hasLocation: &hasWindowLocation
                                     forPointerEvent: cgEvent];
        NSWindow *window = windowNumber != 0 ? [NSApp windowWithWindowNumber: windowNumber] : nil;
        NSPoint location = screenLocation(cgEvent);
        if (window != nil)
            location = hasWindowLocation ? windowLocation : [window convertScreenToBase: location];
        result = [[NSEvent_gesture alloc]
                initWithType: (NSEventType) type
                    location: location
               modifierFlags: flags
                      window: window
                       phase: (NSEventPhase) CGEventGetIntegerValueField(cgEvent, kCGSGesturePhase)
               magnification: CGEventGetIntegerValueField(cgEvent, kCGSGestureMagnification) / 1000000.0
                    rotation: (float) (CGEventGetIntegerValueField(cgEvent, kCGSGestureRotation) / 1000000.0)];
        break;
    }
    case kCGSEventTypeGesture: {
        // A touch event that was not read from the stream (+eventWithCGEvent:): the one finger it reports, with
        // no memory of the other fingers or of the view the finger began in. Any other gesture event is an
        // ordinary event.
        NSTouchPhase phase = touchPhaseOfCGEvent(cgEvent);
        if (phase == 0) {
            result = [[NSEvent alloc] initWithType: (NSEventType) type
                                          location: screenLocation(cgEvent)
                                     modifierFlags: flags
                                            window: nil];
            break;
        }
        NSPoint location;
        NSWindow *window = touchEventWindow(cgEvent, &location);
        if (isnan(location.x) || isnan(location.y))
            location = NSZeroPoint;
        NSTouch *touch = [[NSTouch alloc] _initWithIdentity: [NSNumber numberWithLongLong: CGEventGetIntegerValueField(cgEvent, kCGSTouchIdentifier)]
                                                     window: window
                                                   location: location];
        [touch _moveTo: location phase: phase];
        [touch _setNormalizedPosition: touchNormalizedPosition(cgEvent) deviceSize: touchDeviceSize(cgEvent)];
        result = [[NSEvent_touch alloc] initWithWindow: window
                                              location: location
                                             timestamp: timestamp
                                               touches: [NSSet setWithObject: touch]];
        [touch release];
        break;
    }
    case kCGEventKeyDown:
    case kCGEventKeyUp:
    case kCGEventFlagsChanged: {
        UniChar buffer[256];
        UniCharCount length = 0;
        NSString *characters = @"", *charactersIgnoringModifiers = @"";
        if (type != kCGEventFlagsChanged) {
            length = _CGEventGetKeyCharacters(cgEvent, false, buffer, 256);
            characters = [NSString stringWithCharacters: buffer length: length];
            length = _CGEventGetKeyCharacters(cgEvent, true, buffer, 256);
            charactersIgnoringModifiers = [NSString stringWithCharacters: buffer length: length];
        }
        // The characters without the modifiers other than Shift come with the event when the window system
        // posted it (the window system's keyboard) and no tap gave the event another key code; otherwise
        // they are the characters.
        NSString *unmodified = charactersIgnoringModifiers;
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
        // QUIRK: a key event with Shift in its flags whose string is the tab character U+0009 gives the characters
        // U+0019 (NSBackTabCharacter), both characters and charactersIgnoringModifiers. The key code does not
        // matter (it is U+0009 as the layout's result for the Tab key, as UCKeyTranslate gives it, that Shift
        // turns into the back tab character). Any other Shift or Tab combination keeps the string.
        // Evidence (tier 2, black-box): NSEvent +eventWithCGEvent: of key down and key up events made with
        // CGEventCreateKeyboardEvent on macOS 26.7.3 and 10.14.4 (x86_64): Shift, Shift+Command, Shift+Control
        // and Shift+Option with the Tab key and the string U+0009 give U+0019 while the CGEvent's own string
        // stays U+0009; the same string with the A key or the Escape key and Shift gives U+0019 too; without
        // Shift, with Control, Option, Command or Caps Lock alone it stays U+0009, and a string U+0019 stays.
        // Probe: vd-upstream/mac-probes/937-b2b1-backtab-layer.m.
        // Test: appkit-nsevent-backtab (and the typed Shift+Tab in appkit-keyboard-cgevents).
        if (type != kCGEventFlagsChanged && (flags & NSEventModifierFlagShift) && [characters length] == 1 &&
            [characters characterAtIndex: 0] == '\t')
            characters = unmodified = [NSString stringWithCharacters: (const unichar[]) { NSBackTabCharacter } length: 1];
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
        return [[display keyEventCreated: result fromCGEvent: cgEvent] retain];
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
    _HISetEventStreamFilter(streamFilter);
    _HIBeginEventStreamReading();
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
