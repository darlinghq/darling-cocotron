/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

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
#ifndef CGEVENTSOURCE_H
#define CGEVENTSOURCE_H
#include <CoreFoundation/CFBase.h>
#include <CoreGraphics/CGEventTypes.h>
#include <stdint.h>

__BEGIN_DECLS

extern CFTypeID CGEventSourceGetTypeID(void);

extern CGEventSourceRef _Nullable CGEventSourceCreate(
    CGEventSourceStateID stateID);

extern CGEventSourceKeyboardType CGEventSourceGetKeyboardType(
    CGEventSourceRef _Nullable source);

extern void CGEventSourceSetKeyboardType(CGEventSourceRef _Nullable source,
    CGEventSourceKeyboardType keyboardType);
extern double CGEventSourceGetPixelsPerLine(
    CGEventSourceRef _Nullable source);
extern void CGEventSourceSetPixelsPerLine(CGEventSourceRef _Nullable source,
    double pixelsPerLine);
extern CGEventSourceStateID CGEventSourceGetSourceStateID(
    CGEventSourceRef _Nullable source);

extern bool CGEventSourceButtonState(CGEventSourceStateID stateID,
    CGMouseButton button);

extern bool CGEventSourceKeyState(CGEventSourceStateID stateID,
    CGKeyCode key);

extern CGEventFlags CGEventSourceFlagsState(CGEventSourceStateID stateID);

extern CFTimeInterval CGEventSourceSecondsSinceLastEventType(
    CGEventSourceStateID stateID, CGEventType eventType);
extern uint32_t CGEventSourceCounterForEventType(CGEventSourceStateID
                                                     stateID,
    CGEventType eventType);
extern void CGEventSourceSetUserData(CGEventSourceRef _Nullable source,
    int64_t userData);
extern int64_t CGEventSourceGetUserData(CGEventSourceRef _Nullable source);
extern bool CGEventSourceKeyState(CGEventSourceStateID stateID, CGKeyCode key);
extern void CGEventSourceSetLocalEventsFilterDuringSuppressionState(
    CGEventSourceRef _Nullable source, CGEventFilterMask filter,
    CGEventSuppressionState state);
extern CGEventFilterMask
CGEventSourceGetLocalEventsFilterDuringSuppressionState(
    CGEventSourceRef _Nullable source, CGEventSuppressionState state);
extern void CGEventSourceSetLocalEventsSuppressionInterval(
    CGEventSourceRef _Nullable source, CFTimeInterval seconds);

extern CFTimeInterval CGEventSourceGetLocalEventsSuppressionInterval(
    CGEventSourceRef _Nullable source);

__END_DECLS

#endif
