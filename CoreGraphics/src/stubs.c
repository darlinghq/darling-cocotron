/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGDirectDisplay.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdio.h>

typedef float CGGammaValue;
typedef int32_t CGWindowLevel;

static int verbose = 0;

__attribute__((constructor)) static void initme(void) {
    verbose = getenv("STUB_VERBOSE") != NULL;
}

boolean_t CGCursorIsVisible(void) {
    if(verbose)
        puts("STUB: CGCursorIsVisible called");
    return false;
}

CGOpenGLDisplayMask CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID a) {
    if(verbose)
        puts("STUB: CGDisplayIDToOpenGLDisplayMask called");
    return 0;
}

CGError CGDisplayMoveCursorToPoint(CGDirectDisplayID a, CGPoint b) {
    if(verbose)
        puts("STUB: CGDisplayMoveCursorToPoint called");
    return (CGError)0;
}

void CGDisplayRestoreColorSyncSettings(void) {
    if(verbose)
        puts("STUB: CGDisplayRestoreColorSyncSettings called");
}

CGError CGGetDisplayTransferByFormula(CGDirectDisplayID a, CGGammaValue *b, CGGammaValue *c, CGGammaValue *d, CGGammaValue *e, CGGammaValue *f, CGGammaValue *g, CGGammaValue *h, CGGammaValue *i, CGGammaValue *j) {
    if(verbose)
        puts("STUB: CGGetDisplayTransferByFormula called");
    return (CGError)0;
}

CGError CGGetDisplayTransferByTable(CGDirectDisplayID a, uint32_t b, CGGammaValue *c, CGGammaValue *d, CGGammaValue *e, uint32_t *f) {
    if(verbose)
        puts("STUB: CGGetDisplayTransferByTable called");
    return (CGError)0;
}

void CGGetLastMouseDelta(int32_t *a, int32_t *b) {
    if(verbose)
        puts("STUB: CGGetLastMouseDelta called");
}

CGError CGSetDisplayTransferByFormula(CGDirectDisplayID a, CGGammaValue b, CGGammaValue c, CGGammaValue d, CGGammaValue e, CGGammaValue f, CGGammaValue g, CGGammaValue h, CGGammaValue i, CGGammaValue j) {
    if(verbose)
        puts("STUB: CGSetDisplayTransferByFormula called");
    return (CGError)0;
}

CGError CGSetDisplayTransferByTable(CGDirectDisplayID a, uint32_t b, const CGGammaValue *c, const CGGammaValue *d, const CGGammaValue *e) {
    if(verbose)
        puts("STUB: CGSetDisplayTransferByTable called");
    return (CGError)0;
}

CGError CGSetLocalEventsSuppressionInterval(CFTimeInterval a) {
    if(verbose)
        puts("STUB: CGSetLocalEventsSuppressionInterval called");
    return (CGError)0;
}

CGWindowLevel CGShieldingWindowLevel(void) {
    if(verbose)
        puts("STUB: CGShieldingWindowLevel called");
    return 0;
}
