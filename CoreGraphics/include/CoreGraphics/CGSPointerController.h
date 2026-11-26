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
#ifndef CGSPOINTERCONTROLLER_H
#define CGSPOINTERCONTROLLER_H
#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdint.h>

// What owns the pointer in this process. CoreGraphics' pointer functions (CGDisplayHideCursor,
// CGWarpMouseCursorPosition, CGAssociateMouseAndMouseCursorPosition, CGGetLastMouseDelta, CGSForceShowCursor)
// need the window system's pointer state, which belongs to the connection that has the windows and
// their input. Until CoreGraphics owns that connection, the framework that does (AppKit) registers
// itself here, so that CoreGraphics does not have to reach up to find it. A connection whose backend decodes
// the pointer itself (X11) keeps this state and does not use the controller (-[CGSConnection managesPointer]).
// Without a controller a
// connection of CoreGraphics' own answers where the window system allows it, and the rest does nothing.
//
// The methods can be called from any thread.
@protocol CGSPointerController <NSObject>
// Each call hides the cursor once more; -unhideCursor undoes one (a call with nothing hidden does nothing).
- (void) hideCursor;
- (void) unhideCursor;
// Shows the cursor and forgets every pending hide.
- (void) forceShowCursor;
// Moves the pointer to a point in CoreGraphics' global space that lies inside the desktop.
- (void) warpPointerToPoint: (CGPoint) point;
// NO disconnects the mouse from the cursor: the cursor stays where it is and the mouse only produces deltas.
- (void) setMouseAssociatedWithCursor: (BOOL) associated;
// The mouse motion since the previous call, in whole pixels.
- (void) takeMouseDeltaX: (int32_t *) dx y: (int32_t *) dy;
@optional
// Whether no hide is pending (CGCursorIsVisible); without it the cursor counts as visible.
- (BOOL) cursorIsVisible;
@end

// Registers the controller (not retained; pass nil when it goes away).
extern void _CGSSetPointerController(id<CGSPointerController> controller);

#endif
