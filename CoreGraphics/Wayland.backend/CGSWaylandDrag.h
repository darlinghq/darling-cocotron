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

#ifndef CGSWAYLANDDRAG_H
#define CGSWAYLANDDRAG_H

#import <CoreGraphics/CGSDrag.h>
#import "CGSConnectionWayland.h"
#import <Foundation/Foundation.h>

@class CGSWaylandClipboard, CGSWaylandDragSession, CGSWaylandDropSession;

// The drag and drop of the data device (see CGSDrag.h for what the UI layer sees of it): the drags that are over a
// window of the process, which the device reports (enter, motion, drop, leave) and the destination of the window
// answers, and the drag the process runs itself (wl_data_device.start_drag, with a wl_data_source and an icon
// surface). The device is the clipboard's: one device per seat serves both the selection and the drags, and
// CGSWaylandClipboard hands the drag's events over.
//
// The compositor decides where a drag is: a source gets no pointer positions and no button release while it is on,
// and is told by the compositor that the drag ended (dropped, cancelled or finished).
@interface CGSWaylandDrag : NSObject {
@public
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionWayland *_connection; // not retained: the connection owns the drag
    CGSWaylandClipboard *_clipboard;   // not retained
    CGSWaylandDragSession *_outgoing;  // the drag this process runs; not retained, the UI layer owns it
    CGSWaylandDropSession *_incoming;  // the drag over one of the windows, retained
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection clipboard: (CGSWaylandClipboard *) clipboard;
// Ends whatever is running; the connection calls this before it goes away.
- (void) invalidate;
- (BOOL) available;
- (id<CGSDragSession>) beginDragWithDescription: (const CGSDragDescription *) description;
// A window of the process was unmapped or destroyed: a drag that started in it is cancelled.
- (void) windowUnmapped: (uint32_t) windowID;

// What the data device says (the clipboard receives the events and hands over the drag's).
- (void) deviceEnteredSurface: (struct wl_proxy *) surface
                       serial: (uint32_t) serial
                        offer: (struct wl_proxy *) offer
                        mimes: (NSArray *) mimes
                sourceActions: (uint32_t) actions
                      atPoint: (CGPoint) point;
- (void) deviceMovedToPoint: (CGPoint) point;
- (void) deviceDropped;
- (void) deviceLeft;
// Whether the offer is the one of the drag that is over a window, and what it says of the drag.
- (BOOL) ownsOffer: (struct wl_proxy *) offer;
- (void) offer: (struct wl_proxy *) offer sourceActions: (uint32_t) actions;
- (void) offer: (struct wl_proxy *) offer action: (uint32_t) action;
// The events of the wl_data_source of the drag this process runs.
- (void) sourceEvent: (uint32_t) opcode proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;

@end

#endif
