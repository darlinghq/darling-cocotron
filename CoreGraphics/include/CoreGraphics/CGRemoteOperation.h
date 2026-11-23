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

#ifndef CGREMOTEOPERATION_H
#define CGREMOTEOPERATION_H

#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CoreGraphicsExport.h>

#include <CoreGraphics/CGError.h>
#include <mach/boolean.h>
#include <stdint.h>

typedef CGError CGEventErr;
typedef uint32_t CGButtonCount;
typedef uint32_t CGWheelCount;
typedef uint16_t CGCharCode;
typedef uint16_t CGKeyCode;
typedef uint32_t CGRectCount;

typedef CF_OPTIONS(uint32_t, CGEventFilterMask) {
    kCGEventFilterMaskPermitLocalMouseEvents = 0x00000001,
    kCGEventFilterMaskPermitLocalKeyboardEvents = 0x00000002,
    kCGEventFilterMaskPermitSystemDefinedEvents = 0x00000004
};

typedef CF_ENUM(uint32_t, CGEventSuppressionState) {
    kCGEventSuppressionStateSuppressionInterval = 0,
    kCGEventSuppressionStateRemoteMouseDrag,
    kCGNumberOfEventSuppressionStates
};

typedef CF_OPTIONS(uint32_t, CGScreenUpdateOperation) {
    kCGScreenUpdateOperationRefresh                    =        0,
    kCGScreenUpdateOperationMove                       = 1u <<  0,
    kCGScreenUpdateOperationReducedDirtyRectangleCount = 1u << 31,
};

typedef struct CGScreenUpdateMoveDelta {
    int32_t dX, dY;
} CGScreenUpdateMoveDelta;

typedef void (*CGScreenUpdateMoveCallback)(CGScreenUpdateMoveDelta delta, size_t count, const CGRect *rects, void *userInfo);
typedef void (*CGScreenRefreshCallback)(uint32_t count, const CGRect *rects, void *userInfo);

#define kCGEventFilterMaskPermitAllEvents (kCGEventFilterMaskPermitLocalMouseEvents | kCGEventFilterMaskPermitLocalKeyboardEvents | kCGEventFilterMaskPermitSystemDefinedEvents)

// TODO: All those deprecated functions
extern CGError CGScreenRegisterMoveCallback(CGScreenUpdateMoveCallback callback, void *userInfo);
extern void CGScreenUnregisterMoveCallback(CGScreenUpdateMoveCallback callback, void *userInfo);

COREGRAPHICS_EXPORT CGError CGRegisterScreenRefreshCallback(CGScreenRefreshCallback callback, void *userInfo);
COREGRAPHICS_EXPORT void CGUnregisterScreenRefreshCallback(CGScreenRefreshCallback callback, void *userInfo);
CGError CGWaitForScreenRefreshRects(CGRect * _Nullable *rects, uint32_t *count);
void CGReleaseScreenRefreshRects(CGRect *rects);
CGError CGWaitForScreenUpdateRects(CGScreenUpdateOperation requestedOperations, CGScreenUpdateOperation *currentOperation, CGRect * _Nullable *rects, size_t *rectCount, CGScreenUpdateMoveDelta *delta);

COREGRAPHICS_EXPORT boolean_t CGCursorIsDrawnInFramebuffer(void);

// Obsolete event posting functions, which CGEventPost() replaces. They post to the combined
// session state. Each CGButtonCount button value is the state the button is to have (the first
// is the left button, then right, then the others).
CGError CGPostMouseEvent(CGPoint mouseCursorPosition, boolean_t updateMouseCursorPosition, CGButtonCount buttonCount, boolean_t mouseButtonDown, ...);
CGError CGPostScrollWheelEvent(CGWheelCount wheelCount, int32_t wheel1, ...);
CGError CGPostKeyboardEvent(CGCharCode keyChar, CGKeyCode virtualKey, boolean_t keyDown);

CGError CGWarpMouseCursorPosition(CGPoint newCursorPosition);
CGError CGAssociateMouseAndMouseCursorPosition(boolean_t connected);
// The mouse motion since the last call, in the global display space's units (pixels, y down).
void CGGetLastMouseDelta(int32_t *deltaX, int32_t *deltaY);

#endif
