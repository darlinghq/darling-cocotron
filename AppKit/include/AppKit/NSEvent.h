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

#import <AppKit/AppKitExport.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CGEventTypes.h>

@class NSEvent, NSWindow, NSGraphicsContext, NSTrackingArea, NSView, NSSet;

typedef NS_ENUM(NSUInteger, NSEventType) {
    NSEventTypeLeftMouseDown = 1,
    NSLeftMouseDown = 1,

    NSEventTypeLeftMouseUp = 2,
    NSLeftMouseUp = 2,

    NSEventTypeRightMouseDown = 3,
    NSRightMouseDown = 3,

    NSEventTypeRightMouseUp = 4,
    NSRightMouseUp = 4,

    NSEventTypeMouseMoved = 5,
    NSMouseMoved = 5,

    NSEventTypeLeftMouseDragged = 6,
    NSLeftMouseDragged = 6,

    NSEventTypeRightMouseDragged = 7,
    NSRightMouseDragged = 7,

    NSEventTypeMouseEntered = 8,
    NSMouseEntered = 8,

    NSEventTypeMouseExited = 9,
    NSMouseExited = 9,

    NSEventTypeKeyDown = 10,
    NSKeyDown = 10,

    NSEventTypeKeyUp = 11,
    NSKeyUp = 11,

    NSEventTypeFlagsChanged = 12,
    NSFlagsChanged = 12,

    NSEventTypeAppKitDefined = 13,
    NSAppKitDefined = 13,

    NSEventTypeSystemDefined = 14,
    NSSystemDefined = 14,

    NSEventTypeApplicationDefined = 15,
    NSApplicationDefined = 15,

    NSEventTypePeriodic = 16,
    NSPeriodic = 16,

    NSEventTypeCursorUpdate = 17,
    NSCursorUpdate = 17,

    NSEventTypeScrollWheel = 22,
    NSScrollWheel = 22,

    NSEventTypeOtherMouseDown = 25,
    NSOtherMouseDown = 25,

    NSEventTypeOtherMouseUp = 26,
    NSOtherMouseUp = 26,

    NSEventTypeOtherMouseDragged = 27,
    NSOtherMouseDragged = 27,

    NSAppKitSystem = 100,

    NSPlatformSpecific = 29,
    NSPlatformSpecificDisplayEvent = 30
};

typedef NS_OPTIONS(unsigned long long, NSEventMask) {
    NSEventMaskLeftMouseDown = 1ULL << NSEventTypeLeftMouseDown,
    NSEventMaskLeftMouseUp = 1ULL << NSEventTypeLeftMouseUp,
    NSEventMaskRightMouseDown = 1ULL << NSEventTypeRightMouseDown,
    NSEventMaskRightMouseUp = 1ULL << NSEventTypeRightMouseUp,
    NSEventMaskMouseMoved = 1ULL << NSEventTypeMouseMoved,
    NSEventMaskLeftMouseDragged = 1ULL << NSEventTypeLeftMouseDragged,
    NSEventMaskRightMouseDragged = 1ULL << NSEventTypeRightMouseDragged,
    NSEventMaskMouseEntered = 1ULL << NSEventTypeMouseEntered,
    NSEventMaskMouseExited = 1ULL << NSEventTypeMouseExited,
    NSEventMaskKeyDown = 1ULL << NSEventTypeKeyDown,
    NSEventMaskKeyUp = 1ULL << NSEventTypeKeyUp,
    NSEventMaskFlagsChanged = 1ULL << NSEventTypeFlagsChanged,
    NSEventMaskPeriodic = 1ULL << NSEventTypePeriodic,
    NSEventMaskCursorUpdate = 1ULL << NSEventTypeCursorUpdate,
    NSEventMaskScrollWheel = 1ULL << NSEventTypeScrollWheel,
    NSEventMaskApplicationDefined = 1ULL << NSEventTypeApplicationDefined,
    NSEventMaskAppKitDefined = 1ULL << NSEventTypeAppKitDefined,
    NSEventMaskOtherMouseDown = 1ULL << NSEventTypeOtherMouseDown,
    NSEventMaskOtherMouseUp = 1ULL << NSEventTypeOtherMouseUp,
    NSEventMaskOtherMouseDragged = 1ULL << NSEventTypeOtherMouseDragged,
};

// Pre-10.12 spellings.  NSAnyEventMask keeps Cocotron's 32-bit value rather
// than AppKit's NSEventMaskAny (NSUIntegerMax); widening it is a behaviour
// change and is left alone here.
static const NSEventMask NSLeftMouseDownMask = NSEventMaskLeftMouseDown;
static const NSEventMask NSLeftMouseUpMask = NSEventMaskLeftMouseUp;
static const NSEventMask NSRightMouseDownMask = NSEventMaskRightMouseDown;
static const NSEventMask NSRightMouseUpMask = NSEventMaskRightMouseUp;
static const NSEventMask NSMouseMovedMask = NSEventMaskMouseMoved;
static const NSEventMask NSLeftMouseDraggedMask = NSEventMaskLeftMouseDragged;
static const NSEventMask NSRightMouseDraggedMask = NSEventMaskRightMouseDragged;
static const NSEventMask NSMouseEnteredMask = NSEventMaskMouseEntered;
static const NSEventMask NSMouseExitedMask = NSEventMaskMouseExited;
static const NSEventMask NSKeyDownMask = NSEventMaskKeyDown;
static const NSEventMask NSKeyUpMask = NSEventMaskKeyUp;
static const NSEventMask NSFlagsChangedMask = NSEventMaskFlagsChanged;
static const NSEventMask NSPeriodicMask = NSEventMaskPeriodic;
static const NSEventMask NSCursorUpdateMask = NSEventMaskCursorUpdate;
static const NSEventMask NSScrollWheelMask = NSEventMaskScrollWheel;
static const NSEventMask NSApplicationDefinedMask = NSEventMaskApplicationDefined;
static const NSEventMask NSAppKitDefinedMask = NSEventMaskAppKitDefined;
static const NSEventMask NSOtherMouseDownMask = NSEventMaskOtherMouseDown;
static const NSEventMask NSOtherMouseUpMask = NSEventMaskOtherMouseUp;
static const NSEventMask NSOtherMouseDraggedMask = NSEventMaskOtherMouseDragged;
static const NSEventMask NSAnyEventMask = 0xffffffff;
static const NSEventMask NSPlatformSpecificDisplayMask =
        1ULL << NSPlatformSpecificDisplayEvent;

typedef NS_OPTIONS(NSUInteger, NSEventModifierFlags) {
    NSEventModifierFlagCapsLock = 1 << 16,
    NSEventModifierFlagShift = 1 << 17,
    NSEventModifierFlagControl = 1 << 18,
    NSEventModifierFlagOption = 1 << 19,
    NSEventModifierFlagCommand = 1 << 20,
    NSEventModifierFlagNumericPad = 1 << 21,
    NSEventModifierFlagHelp = 1 << 22,
    NSEventModifierFlagFunction = 1 << 23,
    NSEventModifierFlagDeviceIndependentFlagsMask = 0xffff0000UL
};

// Pre-10.12 spellings.
static const NSEventModifierFlags NSAlphaShiftKeyMask = NSEventModifierFlagCapsLock;
static const NSEventModifierFlags NSShiftKeyMask = NSEventModifierFlagShift;
static const NSEventModifierFlags NSControlKeyMask = NSEventModifierFlagControl;
static const NSEventModifierFlags NSAlternateKeyMask = NSEventModifierFlagOption;
static const NSEventModifierFlags NSCommandKeyMask = NSEventModifierFlagCommand;
static const NSEventModifierFlags NSNumericPadKeyMask = NSEventModifierFlagNumericPad;
static const NSEventModifierFlags NSHelpKeyMask = NSEventModifierFlagHelp;
static const NSEventModifierFlags NSFunctionKeyMask = NSEventModifierFlagFunction;
static const NSEventModifierFlags NSDeviceIndependentModifierFlagsMask =
        NSEventModifierFlagDeviceIndependentFlagsMask;

enum : unsigned int {
    NSUpArrowFunctionKey = 0xF700,
    NSDownArrowFunctionKey = 0xF701,
    NSLeftArrowFunctionKey = 0xF702,
    NSRightArrowFunctionKey = 0xF703,
    NSF1FunctionKey = 0xF704,
    NSF2FunctionKey = 0xF705,
    NSF3FunctionKey = 0xF706,
    NSF4FunctionKey = 0xF707,
    NSF5FunctionKey = 0xF708,
    NSF6FunctionKey = 0xF709,
    NSF7FunctionKey = 0xF70A,
    NSF8FunctionKey = 0xF70B,
    NSF9FunctionKey = 0xF70C,
    NSF10FunctionKey = 0xF70D,
    NSF11FunctionKey = 0xF70E,
    NSF12FunctionKey = 0xF70F,
    NSF13FunctionKey = 0xF710,
    NSF14FunctionKey = 0xF711,
    NSF15FunctionKey = 0xF712,
    NSF16FunctionKey = 0xF713,
    NSF17FunctionKey = 0xF714,
    NSF18FunctionKey = 0xF715,
    NSF19FunctionKey = 0xF716,
    NSF20FunctionKey = 0xF717,
    NSF21FunctionKey = 0xF718,
    NSF22FunctionKey = 0xF719,
    NSF23FunctionKey = 0xF71A,
    NSF24FunctionKey = 0xF71B,
    NSF25FunctionKey = 0xF71C,
    NSF26FunctionKey = 0xF71D,
    NSF27FunctionKey = 0xF71E,
    NSF28FunctionKey = 0xF71F,
    NSF29FunctionKey = 0xF720,
    NSF30FunctionKey = 0xF721,
    NSF31FunctionKey = 0xF722,
    NSF32FunctionKey = 0xF723,
    NSF33FunctionKey = 0xF724,
    NSF34FunctionKey = 0xF725,
    NSF35FunctionKey = 0xF726,
    NSInsertFunctionKey = 0xF727,
    NSDeleteFunctionKey = 0xF728,
    NSHomeFunctionKey = 0xF729,
    NSBeginFunctionKey = 0xF72A,
    NSEndFunctionKey = 0xF72B,
    NSPageUpFunctionKey = 0xF72C,
    NSPageDownFunctionKey = 0xF72D,
    NSPrintScreenFunctionKey = 0xF72E,
    NSScrollLockFunctionKey = 0xF72F,
    NSPauseFunctionKey = 0xF730,
    NSSysReqFunctionKey = 0xF731,
    NSBreakFunctionKey = 0xF732,
    NSResetFunctionKey = 0xF733,
    NSStopFunctionKey = 0xF734,
    NSMenuFunctionKey = 0xF735,
    NSUserFunctionKey = 0xF736,
    NSSystemFunctionKey = 0xF737,
    NSPrintFunctionKey = 0xF738,
    NSClearLineFunctionKey = 0xF739,
    NSClearDisplayFunctionKey = 0xF73A,
    NSInsertLineFunctionKey = 0xF73B,
    NSDeleteLineFunctionKey = 0xF73C,
    NSInsertCharFunctionKey = 0xF73D,
    NSDeleteCharFunctionKey = 0xF73E,
    NSPrevFunctionKey = 0xF73F,
    NSNextFunctionKey = 0xF740,
    NSSelectFunctionKey = 0xF741,
    NSExecuteFunctionKey = 0xF742,
    NSUndoFunctionKey = 0xF743,
    NSRedoFunctionKey = 0xF744,
    NSFindFunctionKey = 0xF745,
    NSHelpFunctionKey = 0xF746,
    NSModeSwitchFunctionKey = 0xF747
};

enum { NSApplicationActivated = 0, NSApplicationDeactivated = 1 };

typedef NS_ENUM(short, NSEventSubtype) {
    NSEventSubtypeMouseEvent = 0,
    NSEventSubtypeTabletPoint = 1,
    NSEventSubtypeTabletProximity = 2,
    NSEventSubtypeTouch = 3,
};

enum {
    NSMouseEventSubtype = NSEventSubtypeMouseEvent,
    NSTabletPointEventSubtype = NSEventSubtypeTabletPoint,
    NSTabletProximityEventSubtype = NSEventSubtypeTabletProximity,
    NSTouchEventSubtype = NSEventSubtypeTouch,
};

typedef NS_OPTIONS(NSUInteger, NSEventPhase) {
    NSEventPhaseNone = 0,
    NSEventPhaseBegan = 0x1 << 0,
    NSEventPhaseStationary = 0x1 << 1,
    NSEventPhaseChanged = 0x1 << 2,
    NSEventPhaseEnded = 0x1 << 3,
    NSEventPhaseCancelled = 0x1 << 4,
    NSEventPhaseMayBegin = 0x1 << 5,
};

@interface NSEvent : NSObject {
    NSEventType _type;
    NSTimeInterval _timestamp;
    NSPoint _locationInWindow;
    NSEventModifierFlags _modifierFlags;
    NSInteger _windowNumber;
}

+ (NSPoint) mouseLocation;
@property (class, readonly) NSEventModifierFlags modifierFlags;
+ (NSUInteger) pressedMouseButtons;

+ (id) addLocalMonitorForEventsMatchingMask: (NSEventMask) mask
                                    handler: (NSEvent *_Nullable (^)(NSEvent *_Nonnull event)) block;
+ (void) removeMonitor: (id) eventMonitor;
+ (void) setMouseCoalescingEnabled: (BOOL) flag;
+ (BOOL) isMouseCoalescingEnabled;
- (NSSet *) touchesMatchingPhase: (NSUInteger) phase inView: (NSView *) view;

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                       window: (NSWindow *) window;

// FIXME: get rid of
+ (NSEvent *) mouseEventWithType: (NSEventType) type
                        location: (NSPoint) location
                   modifierFlags: (NSEventModifierFlags) modifierFlags
                          window: (NSWindow *) window
                      clickCount: (NSInteger) clickCount
                          deltaX: (CGFloat) deltaX
                          deltaY: (CGFloat) deltaY;

// FIXME: get rid of
+ (NSEvent *) mouseEventWithType: (NSEventType) type
                        location: (NSPoint) location
                   modifierFlags: (NSEventModifierFlags) modifierFlags
                          window: (NSWindow *) window
                          deltaY: (CGFloat) deltaY;

+ (NSEvent *) enterExitEventWithType: (NSEventType) type
                            location: (NSPoint) location
                       modifierFlags: (NSEventModifierFlags) flags
                           timestamp: (NSTimeInterval) timestamp
                        windowNumber: (NSInteger) windowNumber
                             context: (NSGraphicsContext *) context
                         eventNumber: (NSInteger) eventNumber
                      trackingNumber: (NSInteger) tracking
                            userData: (void *) userData;

+ (NSEvent *) mouseEventWithType: (NSEventType) type
                        location: (NSPoint) location
                   modifierFlags: (NSEventModifierFlags) flags
                       timestamp: (NSTimeInterval) timestamp
                    windowNumber: (NSInteger) windowNumber
                         context: (NSGraphicsContext *) context
                     eventNumber: (NSInteger) eventNumber
                      clickCount: (NSInteger) clickCount
                        pressure: (float) pressure;

+ (NSEvent *) keyEventWithType: (NSEventType) type
                           location: (NSPoint) location
                      modifierFlags: (NSEventModifierFlags) modifierFlags
                          timestamp: (NSTimeInterval) timestamp
                       windowNumber: (NSInteger) windowNumber
                            context: (NSGraphicsContext *) context
                         characters: (NSString *) characters
        charactersIgnoringModifiers: (NSString *) charactersIgnoringModifiers
                          isARepeat: (BOOL) isARepeat
                            keyCode: (unsigned short) keyCode;

+ (NSEvent *) otherEventWithType: (NSEventType) type
                        location: (NSPoint) location
                   modifierFlags: (NSEventModifierFlags) flags
                       timestamp: (NSTimeInterval) timestamp
                    windowNumber: (NSInteger) windowNum
                         context: (NSGraphicsContext *) context
                         subtype: (short) subtype
                           data1: (NSInteger) data1
                           data2: (NSInteger) data2;

- (NSEventType) type;
@property (readonly) NSTimeInterval timestamp;
@property (readonly) NSPoint locationInWindow;
@property (readonly) NSEventModifierFlags modifierFlags;
@property (readonly, weak) NSWindow *window;
- (NSInteger) windowNumber;

@property (readonly) NSInteger clickCount;
- (CGFloat) deltaX;
- (CGFloat) deltaY;
- (CGFloat) deltaZ;

- (NSEventPhase) phase;
- (NSEventPhase) momentumPhase;
- (BOOL) hasPreciseScrollingDeltas;
- (CGFloat) scrollingDeltaX;
- (CGFloat) scrollingDeltaY;
- (BOOL) isDirectionInvertedFromDevice;
+ (BOOL) isSwipeTrackingFromScrollEventsEnabled;

- (CGEventRef) CGEvent;

- (NSString *) characters;
- (NSString *) charactersIgnoringModifiers;
- (unsigned short) keyCode;

+ (void) startPeriodicEventsAfterDelay: (NSTimeInterval) delay
                            withPeriod: (NSTimeInterval) period;
+ (void) stopPeriodicEvents;

- (short) subtype;
- (NSInteger) data1;
- (NSInteger) data2;
- (NSInteger) trackingNumber;
- (NSTrackingArea *) trackingArea;
- (void *) userData;

@property(getter=isARepeat, readonly) BOOL ARepeat;
- (BOOL) isARepeat;
@property(readonly) NSInteger buttonNumber;
- (NSInteger) buttonNumber;

@end

APPKIT_EXPORT NSEventMask NSEventMaskFromType(NSEventType type);
