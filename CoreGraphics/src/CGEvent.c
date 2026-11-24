/*
 This file is part of Darling.

 Copyright (C) 2019-2026 Lubos Dolezel

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

#include <CoreGraphics/CGEvent.h>
#include <CoreGraphics/CGEventSource.h>
#include <stdarg.h>

// The obsolete posting functions are built on CGEventPost(): the state change they describe becomes
// events of the combined session state.

#define kMaxPostedButtons 32

static void postMouse(CGEventType type, CGPoint position, CGMouseButton button)
{
    CGEventRef event = CGEventCreateMouseEvent(NULL, type, position, button);

    if (event == NULL)
        return;
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
}

CGError CGPostMouseEvent(CGPoint mouseCursorPosition, boolean_t updateMouseCursorPosition, CGButtonCount buttonCount, boolean_t mouseButtonDown, ...) {
    boolean_t states[kMaxPostedButtons];
    va_list args;

    if (buttonCount == 0 || buttonCount > kMaxPostedButtons)
        return kCGErrorIllegalArgument;

    states[0] = mouseButtonDown;
    va_start(args, mouseButtonDown);
    for (CGButtonCount i = 1; i < buttonCount; i++)
        states[i] = va_arg(args, int);
    va_end(args);

    int changed = 0;
    int firstDown = -1;

    for (CGButtonCount i = 0; i < buttonCount; i++) {
        bool was = CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, i);
        bool down = states[i] != 0;

        if (down && firstDown < 0)
            firstDown = (int) i;
        if (down == was)
            continue;

        changed = 1;
        CGEventType type;
        if (i == 0)
            type = down ? kCGEventLeftMouseDown : kCGEventLeftMouseUp;
        else if (i == 1)
            type = down ? kCGEventRightMouseDown : kCGEventRightMouseUp;
        else
            type = down ? kCGEventOtherMouseDown : kCGEventOtherMouseUp;
        postMouse(type, mouseCursorPosition, i);
    }

    if (!changed && updateMouseCursorPosition) {
        // Only the pointer moved: a drag while a button is down.
        if (firstDown < 0)
            postMouse(kCGEventMouseMoved, mouseCursorPosition, 0);
        else if (firstDown == 0)
            postMouse(kCGEventLeftMouseDragged, mouseCursorPosition, 0);
        else if (firstDown == 1)
            postMouse(kCGEventRightMouseDragged, mouseCursorPosition, 1);
        else
            postMouse(kCGEventOtherMouseDragged, mouseCursorPosition, firstDown);
    }
    return kCGErrorSuccess;
}

CGError CGPostScrollWheelEvent(CGWheelCount wheelCount, int32_t wheel1, ...) {
    int32_t wheels[3] = { wheel1, 0, 0 };
    va_list args;

    if (wheelCount == 0 || wheelCount > 3)
        return kCGErrorIllegalArgument;

    va_start(args, wheel1);
    for (CGWheelCount i = 1; i < wheelCount; i++)
        wheels[i] = va_arg(args, int32_t);
    va_end(args);

    CGEventRef event = CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitLine, wheelCount, wheels[0], wheels[1], wheels[2]);

    if (event == NULL)
        return kCGErrorFailure;
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
    return kCGErrorSuccess;
}

CGError CGPostKeyboardEvent(CGCharCode keyChar, CGKeyCode virtualKey, boolean_t keyDown) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, virtualKey, keyDown != 0);

    if (event == NULL)
        return kCGErrorFailure;
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
    return kCGErrorSuccess;
}
