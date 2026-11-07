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
#include "CGEventObjC.h"
#include <CoreGraphics/CGEventSource.h>
#include <CoreGraphics/CGSConnection.h>

static CGEventFlags g_sourceStates[3];

CFTypeID CGEventSourceGetTypeID(void) {
    return (CFTypeID)[CGEventSource self];
}

CGEventSourceRef CGEventSourceCreate(CGEventSourceStateID stateID) {
    return (CGEventSourceRef) [[CGEventSource alloc] initWithState: stateID];
}

CGEventSourceKeyboardType CGEventSourceGetKeyboardType(CGEventSourceRef source)
{
    CGEventSource *src = (CGEventSource *) source;
    return src.keyboardType;
}

void CGEventSourceSetKeyboardType(CGEventSourceRef source,
                                  CGEventSourceKeyboardType keyboardType)
{
    CGEventSource *src = (CGEventSource *) source;
    src.keyboardType = keyboardType;
}

CGEventSourceStateID CGEventSourceGetSourceStateID(CGEventSourceRef source) {
    CGEventSource *src = (CGEventSource *) source;
    return src.stateID;
}

int64_t CGEventSourceGetUserData(CGEventSourceRef source) {
    CGEventSource *src = (CGEventSource *) source;
    return src.userData;
}

void CGEventSourceSetUserData(CGEventSourceRef source, int64_t userData) {
    CGEventSource *src = (CGEventSource *) source;
    src.userData = userData;
}

double CGEventSourceGetPixelsPerLine(CGEventSourceRef source) {
    CGEventSource *src = (CGEventSource *) source;
    return src.pixelsPerLine;
}

void CGEventSourceSetPixelsPerLine(CGEventSourceRef source,
                                   double pixelsPerLine)
{
    CGEventSource *src = (CGEventSource *) source;
    src.pixelsPerLine = pixelsPerLine;
}

CGEventFlags CGEventSourceFlagsState(CGEventSourceStateID stateID) {
    return g_sourceStates[stateID + 1];
}

void CGEventSourceSetLocalEventsSuppressionInterval(CGEventSourceRef source, CFTimeInterval seconds) {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

// The private state of a source is only changed by events posted with it,
// which this implementation does not track, so keys and buttons are up there.
// The other states are the hardware state seen by the window server.
static CGSConnection *hardwareStateConnection(CGEventSourceStateID stateID) {
    if (stateID != kCGEventSourceStateCombinedSessionState &&
        stateID != kCGEventSourceStateHIDSystemState)
        return nil;
    return _CGSConnectionForID(CGSDefaultConnection);
}

bool CGEventSourceKeyState(CGEventSourceStateID stateID, CGKeyCode key) {
    return [hardwareStateConnection(stateID) isKeyDown: key];
}

bool CGEventSourceButtonState(CGEventSourceStateID stateID, CGMouseButton button) {
    return [hardwareStateConnection(stateID) isMouseButtonDown: button];
}

// The window server's event stream is not observed, so there is no event
// history to count or to measure the time since: every event type is
// reported as having occurred just now, never as a count.
CFTimeInterval CGEventSourceSecondsSinceLastEventType(CGEventSourceStateID stateID,
                                                      CGEventType eventType)
{
    return 0;
}

uint32_t CGEventSourceCounterForEventType(CGEventSourceStateID stateID,
                                          CGEventType eventType)
{
    return 0;
}
