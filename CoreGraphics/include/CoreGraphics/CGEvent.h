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

#ifndef _CGEVENT_H_
#define _CGEVENT_H_

#include <CoreGraphics/CGEventTypes.h>
#include <CoreGraphics/CGGeometry.h>
#include <CoreGraphics/CGError.h>
#include <CoreGraphics/CGRemoteOperation.h>
// Darling's own code gets the window server SPI with the public header; macOS
// keeps it out of the SDK, and code built against the SDK declares the parts
// it uses itself (with types of its choosing, which would conflict).
#ifdef DARLING
#include <CoreGraphics/CoreGraphicsPrivate.h>
#endif

__BEGIN_DECLS

extern CFTypeID CGEventGetTypeID(void);

extern CGEventRef _Nullable CGEventCreate(CGEventSourceRef _Nullable source);
extern CFDataRef _Nullable CGEventCreateData(
    CFAllocatorRef _Nullable allocator,
    CGEventRef _Nullable event);

extern CGEventRef _Nullable CGEventCreateFromData(
    CFAllocatorRef _Nullable allocator, CFDataRef _Nullable data);
extern CGEventRef _Nullable CGEventCreateMouseEvent(
    CGEventSourceRef _Nullable source,
    CGEventType mouseType, CGPoint mouseCursorPosition,
    CGMouseButton mouseButton);
extern CGEventRef _Nullable CGEventCreateKeyboardEvent(
    CGEventSourceRef _Nullable source,
    CGKeyCode virtualKey, bool keyDown);
extern CGEventRef _Nullable CGEventCreateScrollWheelEvent(
    CGEventSourceRef _Nullable source,
    CGScrollEventUnit units, uint32_t wheelCount, int32_t wheel1, ...);



extern CGEventRef _Nullable CGEventCreateScrollWheelEvent2(
    CGEventSourceRef _Nullable source,
    CGScrollEventUnit units, uint32_t wheelCount, int32_t wheel1, int32_t wheel2, int32_t wheel3);



extern CGEventRef _Nullable CGEventCreateCopy(CGEventRef _Nullable event);
extern CGEventSourceRef _Nullable CGEventCreateSourceFromEvent(
    CGEventRef _Nullable event);



extern void CGEventSetSource(CGEventRef _Nullable event,
    CGEventSourceRef _Nullable source);

extern CGEventType CGEventGetType(CGEventRef _Nullable event);

extern void CGEventSetType(CGEventRef _Nullable event, CGEventType type);

extern CGEventTimestamp CGEventGetTimestamp(CGEventRef _Nullable event);

extern void CGEventSetTimestamp(CGEventRef _Nullable event,
    CGEventTimestamp timestamp);

extern CGPoint CGEventGetLocation(CGEventRef _Nullable event);

extern CGPoint CGEventGetUnflippedLocation(CGEventRef _Nullable event);

extern void CGEventSetLocation(CGEventRef _Nullable event, CGPoint location);


extern CGEventFlags CGEventGetFlags(CGEventRef _Nullable event);

extern void CGEventSetFlags(CGEventRef _Nullable event, CGEventFlags flags);

extern void CGEventKeyboardGetUnicodeString(CGEventRef _Nullable event,
    UniCharCount maxStringLength, UniCharCount *_Nullable actualStringLength,
    UniChar * _Nullable unicodeString);

extern void CGEventKeyboardSetUnicodeString(CGEventRef _Nullable event,
    UniCharCount stringLength, const UniChar * _Nullable unicodeString);

extern int64_t CGEventGetIntegerValueField(CGEventRef _Nullable event,
    CGEventField field);

extern void CGEventSetIntegerValueField(CGEventRef _Nullable event,
    CGEventField field, int64_t value);

extern double CGEventGetDoubleValueField(CGEventRef _Nullable event,
    CGEventField field);
extern void CGEventSetDoubleValueField(CGEventRef _Nullable event,
    CGEventField field, double value);

extern CFMachPortRef _Nullable CGEventTapCreate(CGEventTapLocation tap,
    CGEventTapPlacement place, CGEventTapOptions options,
    CGEventMask eventsOfInterest, CGEventTapCallBack callback,
    void * _Nullable userInfo);


extern CFMachPortRef _Nullable CGEventTapCreateForPSN(
    void * processSerialNumber,
    CGEventTapPlacement place, CGEventTapOptions options,
    CGEventMask eventsOfInterest, CGEventTapCallBack callback,
    void *_Nullable userInfo);

extern CFMachPortRef _Nullable CGEventTapCreateForPid(pid_t pid,
  CGEventTapPlacement place, CGEventTapOptions options,
  CGEventMask eventsOfInterest, CGEventTapCallBack callback,
  void * _Nullable userInfo);
extern void CGEventTapEnable(CFMachPortRef tap, bool enable);

extern bool CGEventTapIsEnabled(CFMachPortRef tap);
extern void CGEventTapPostEvent(CGEventTapProxy _Nullable proxy,
    CGEventRef _Nullable event);

extern void CGEventPost(CGEventTapLocation tap, CGEventRef _Nullable event);
extern void CGEventPostToPSN(void * _Nullable processSerialNumber,
    CGEventRef _Nullable event);

extern void CGEventPostToPid( pid_t pid,
    CGEventRef _Nullable event);

extern CGError CGGetEventTapList(uint32_t maxNumberOfTaps,
    CGEventTapInformation * _Nullable tapList,
    uint32_t * _Nullable eventTapCount);

__END_DECLS

#endif
