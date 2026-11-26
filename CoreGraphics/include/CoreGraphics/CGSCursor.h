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
#ifndef CGSCURSOR_H
#define CGSCURSOR_H

// The cursor SPI: what the pointer shows over the windows of the process. A cursor is either one of a fixed
// set of shapes, which the window system draws in the user's cursor theme, or an image with a hot spot. The
// frameworks above (AppKit's NSCursor) make cursors with the functions below and select the one in effect with
// CGSCursorSetCurrent(); the backend gives it to the window system for the pointer's focus (the X windows the
// pointer is over, the Wayland pointer's focus surface), at the scale of the output, and keeps showing it over
// new windows and after the cursor was hidden and is shown again.
//
// The rest of the pointer is the public API and the existing SPI: CGDisplayHideCursor() and CGDisplayShowCursor()
// (counted), CGSForceShowCursor(), _CGSSetCursorHiddenUntilMouseMoves() (CGSNativeConnection.h; the cursor comes
// back with the next motion of the mouse) and CGWarpMouseCursorPosition(). A hidden cursor stays hidden while
// another cursor is selected, and is the selected one when it is shown again.
//
// A CGSCursorRef is an Objective-C object (an NSObject subclass), so a framework can keep it as an id.

#include <CoreGraphics/CGBase.h>
#include <CoreGraphics/CGError.h>
#include <CoreGraphics/CGGeometry.h>
#include <CoreGraphics/CGImage.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CGSCursor *CGSCursorRef;

typedef enum {
    kCGSCursorShapeArrow = 0,
    kCGSCursorShapeIBeam,
    kCGSCursorShapeVerticalIBeam,
    kCGSCursorShapeCrosshair,
    kCGSCursorShapeClosedHand,
    kCGSCursorShapeOpenHand,
    kCGSCursorShapePointingHand,
    kCGSCursorShapeZoomIn,
    kCGSCursorShapeZoomOut,
    kCGSCursorShapeResizeUp,
    kCGSCursorShapeResizeDown,
    kCGSCursorShapeResizeLeft,
    kCGSCursorShapeResizeRight,
    kCGSCursorShapeResizeLeftRight,
    kCGSCursorShapeResizeUpDown,
    kCGSCursorShapeResizeNorthWest,
    kCGSCursorShapeResizeNorthEast,
    kCGSCursorShapeResizeSouthEast,
    kCGSCursorShapeResizeSouthWest,
    kCGSCursorShapeResizeNorthWestSouthEast,
    kCGSCursorShapeResizeNorthEastSouthWest,
    kCGSCursorShapeCount
} CGSCursorShape;

// A cursor of one of the shapes; an unknown shape gives the arrow. Follows the Create rule (release it with
// CGSCursorRelease()). Never NULL.
COREGRAPHICS_EXPORT CGSCursorRef CGSCursorCreateWithShape(CGSCursorShape shape);
// A cursor showing the image at the logical size (in points; the image's pixels are scaled to the pixels of the
// output, so an image of twice the logical size is sharp on a 2x output). The hot spot is in points from the
// image's top-left corner, and is moved into the image when it lies outside. NULL for an image or size that is
// empty or not finite, or too big for the window system.
COREGRAPHICS_EXPORT CGSCursorRef CGSCursorCreateWithImage(CGImageRef image, CGSize logicalSize, CGPoint hotSpot);
COREGRAPHICS_EXPORT CGSCursorRef CGSCursorRetain(CGSCursorRef cursor);
COREGRAPHICS_EXPORT void CGSCursorRelease(CGSCursorRef cursor);

// The cursor the process shows over its windows from now on; NULL selects the default one (the arrow). Any thread.
COREGRAPHICS_EXPORT CGError CGSCursorSetCurrent(CGSCursorRef cursor);

#ifdef __cplusplus
}
#endif

#endif
