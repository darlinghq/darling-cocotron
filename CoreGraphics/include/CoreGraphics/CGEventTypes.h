/*
 This file is part of Darling.

 Copyright (C) 2019-2020 Lubos Dolezel

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

#ifndef _CGEVENTTYPES_H_
#define _CGEVENTTYPES_H_

#include <CoreFoundation/CFBase.h>
#include <CoreFoundation/CFAvailability.h>
#include <CoreGraphics/CGBase.h>
#include <CoreGraphics/CGRemoteOperation.h>

typedef struct __CGEvent *CGEventRef;

typedef uint32_t CGMouseButton;
enum {
  kCGMouseButtonLeft = 0,
  kCGMouseButtonRight = 1,
  kCGMouseButtonCenter = 2
};

typedef uint32_t CGScrollEventUnit;
enum {
  kCGScrollEventUnitPixel = 0,
  kCGScrollEventUnitLine = 1,
};

typedef uint32_t CGMomentumScrollPhase;
enum {
    kCGMomentumScrollPhaseNone = 0,
    kCGMomentumScrollPhaseBegin = 1,
    kCGMomentumScrollPhaseContinue = 2,
    kCGMomentumScrollPhaseEnd = 3
};

typedef uint32_t CGScrollPhase;
enum {
    kCGScrollPhaseBegan = 1,
    kCGScrollPhaseChanged = 2,
    kCGScrollPhaseEnded = 4,
    kCGScrollPhaseCancelled = 8,
    kCGScrollPhaseMayBegin = 128
};


typedef uint32_t CGGesturePhase;
enum {
    kCGGesturePhaseNone = 0,
    kCGGesturePhaseBegan = 1,
    kCGGesturePhaseChanged = 2,
    kCGGesturePhaseEnded = 4,
    kCGGesturePhaseCancelled = 8,
    kCGGesturePhaseMayBegin = 128
};


typedef uint64_t CGEventFlags;
enum {

  kCGEventFlagMaskAlphaShift = 0x00010000,
  kCGEventFlagMaskShift = 0x00020000,
  kCGEventFlagMaskControl = 0x00040000,
  kCGEventFlagMaskAlternate = 0x00080000,
  kCGEventFlagMaskCommand = 0x00100000,
  kCGEventFlagMaskHelp = 0x00400000,
  kCGEventFlagMaskSecondaryFn = 0x00800000,
  kCGEventFlagMaskNumericPad = 0x00200000,
  kCGEventFlagMaskNonCoalesced = 0x00000100
};


typedef uint32_t CGEventType;
enum {
  kCGEventNull = 0,
  kCGEventLeftMouseDown = 1,
  kCGEventLeftMouseUp = 2,
  kCGEventRightMouseDown = 3,
  kCGEventRightMouseUp = 4,
  kCGEventMouseMoved = 5,
  kCGEventLeftMouseDragged = 6,
  kCGEventRightMouseDragged = 7,
  kCGEventKeyDown = 10,
  kCGEventKeyUp = 11,
  kCGEventFlagsChanged = 12,
  kCGEventScrollWheel = 22,
  kCGEventTabletPointer = 23,
  kCGEventTabletProximity = 24,
  kCGEventOtherMouseDown = 25,
  kCGEventOtherMouseUp = 26,
  kCGEventOtherMouseDragged = 27,
  kCGEventTapDisabledByTimeout = 0xFFFFFFFE,
  kCGEventTapDisabledByUserInput = 0xFFFFFFFF
};

// Any input event, for CGEventSourceSecondsSinceLastEventType and
// CGEventSourceCounterForEventType.
#define kCGAnyInputEventType ((CGEventType) (~0))

typedef uint64_t CGEventTimestamp;
typedef uint32_t CGEventField;
enum {
  kCGMouseEventNumber = 0,
  kCGMouseEventClickState = 1,
  kCGMouseEventPressure = 2,
  kCGMouseEventButtonNumber = 3,
  kCGMouseEventDeltaX = 4,
  kCGMouseEventDeltaY = 5,
  kCGMouseEventInstantMouser = 6,
  kCGMouseEventSubtype = 7,
  kCGKeyboardEventAutorepeat = 8,
  kCGKeyboardEventKeycode = 9,
  kCGKeyboardEventKeyboardType = 10,
  kCGScrollWheelEventDeltaAxis1 = 11,
  kCGScrollWheelEventDeltaAxis2 = 12,
  kCGScrollWheelEventDeltaAxis3 = 13,
  kCGScrollWheelEventFixedPtDeltaAxis1 = 93,
  kCGScrollWheelEventFixedPtDeltaAxis2 = 94,
  kCGScrollWheelEventFixedPtDeltaAxis3 = 95,
  kCGScrollWheelEventPointDeltaAxis1 = 96,
  kCGScrollWheelEventPointDeltaAxis2 = 97,
  kCGScrollWheelEventPointDeltaAxis3 = 98,
  kCGScrollWheelEventScrollPhase = 99,
  kCGScrollWheelEventScrollCount = 100,
  kCGScrollWheelEventMomentumPhase = 123,
  kCGScrollWheelEventInstantMouser = 14,
  kCGTabletEventPointX = 15,
  kCGTabletEventPointY = 16,
  kCGTabletEventPointZ = 17,
  kCGTabletEventPointButtons = 18,
  kCGTabletEventPointPressure = 19,
  kCGTabletEventTiltX = 20,
  kCGTabletEventTiltY = 21,
  kCGTabletEventRotation = 22,
  kCGTabletEventTangentialPressure = 23,
  kCGTabletEventDeviceID = 24,
  kCGTabletEventVendor1 = 25,
  kCGTabletEventVendor2 = 26,
  kCGTabletEventVendor3 = 27,
  kCGTabletProximityEventVendorID = 28,
  kCGTabletProximityEventTabletID = 29,
  kCGTabletProximityEventPointerID = 30,
  kCGTabletProximityEventDeviceID = 31,
  kCGTabletProximityEventSystemTabletID = 32,
  kCGTabletProximityEventVendorPointerType = 33,
  kCGTabletProximityEventVendorPointerSerialNumber = 34,
  kCGTabletProximityEventVendorUniqueID = 35,
  kCGTabletProximityEventCapabilityMask = 36,
  kCGTabletProximityEventPointerType = 37,
  kCGTabletProximityEventEnterProximity = 38,
  kCGEventTargetProcessSerialNumber = 39,
  kCGEventTargetUnixProcessID = 40,
  kCGEventSourceUnixProcessID = 41,
  kCGEventSourceUserData = 42,
  kCGEventSourceUserID = 43,
  kCGEventSourceGroupID = 44,
  kCGEventSourceStateID = 45,
  kCGScrollWheelEventIsContinuous = 88,
  kCGMouseEventWindowUnderMousePointer = 91,
  kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent = 92,
  kCGEventUnacceleratedPointerMovementX = 170,
  kCGEventUnacceleratedPointerMovementY = 171
};


typedef uint32_t CGEventMouseSubtype;
enum {
  kCGEventMouseSubtypeDefault = 0,
  kCGEventMouseSubtypeTabletPoint = 1,
  kCGEventMouseSubtypeTabletProximity = 2
};


typedef uint32_t CGEventTapLocation;
enum {
  kCGHIDEventTap = 0,
  kCGSessionEventTap,
  kCGAnnotatedSessionEventTap
};



typedef uint32_t CGEventTapPlacement;
enum {
  kCGHeadInsertEventTap = 0,
  kCGTailAppendEventTap
};

typedef uint32_t CGEventTapOptions;
enum {
  kCGEventTapOptionDefault = 0x00000000,
  kCGEventTapOptionListenOnly = 0x00000001
};

typedef uint64_t CGEventMask;
typedef struct __CGEventTapProxy *CGEventTapProxy;

typedef CGEventRef _Nullable (*CGEventTapCallBack)(CGEventTapProxy proxy,
  CGEventType type, CGEventRef event, void * _Nullable userInfo);
struct __CGEventTapInformation {
  uint32_t eventTapID;
  CGEventTapLocation tapPoint;
  CGEventTapOptions options;
  CGEventMask eventsOfInterest;
  pid_t tappingProcess;
  pid_t processBeingTapped;
  bool enabled;
  float minUsecLatency;
  float avgUsecLatency;
  float maxUsecLatency;
};
typedef struct __CGEventTapInformation CGEventTapInformation;


typedef struct __CGEventSource *CGEventSourceRef;

typedef int32_t CGEventSourceStateID;
enum {
  kCGEventSourceStatePrivate = -1,
  kCGEventSourceStateCombinedSessionState = 0,
  kCGEventSourceStateHIDSystemState = 1
};

typedef uint32_t CGEventSourceKeyboardType;

#define CGEventMaskBit(eventType) ((CGEventMask) 1 << (eventType))

#endif
