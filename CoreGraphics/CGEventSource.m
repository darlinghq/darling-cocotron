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

bool CGEventSourceKeyState(CGEventSourceStateID stateID, CGKeyCode key)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);

    return true;
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
