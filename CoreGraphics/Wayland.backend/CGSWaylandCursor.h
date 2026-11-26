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

// What the process' wl_pointer shows (see CGSCursor.h): the cursor the process selected, a blank one while it is
// hidden. The compositor draws a shape of the cursor-shape protocol itself when it offers one; otherwise, and for
// every image cursor, the cursor is a wl_surface of its own with a shm buffer: an image's pixels at the scale of the
// output, or the cursor theme's image of the shape. The request is made for the serial of the pointer's latest
// enter, so it is made again on every enter, and when the cursor, the hide count or the scale changes.

#ifndef CGSWAYLANDCURSOR_H
#define CGSWAYLANDCURSOR_H

#import <Foundation/NSObject.h>
#include <stdint.h>
#include <wayland-util.h>

@class CGSConnectionWayland;
@class CGSCursor;
@class CGSWaylandPointer;
struct wl_cursor_theme;
struct wl_proxy;

@interface CGSWaylandCursor : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionWayland *_connection; // not retained: the connection owns the pointer, which owns this
    CGSWaylandPointer *_pointer;       // not retained, for the same reason
    // The cursor surface and its fractional scale object (the compositor's preferred scale for it).
    struct wl_proxy *_surface, *_fractionalScale;
    uint32_t _preferredScale120;
    // The cursor shape device of the pointer.
    struct wl_proxy *_shapeDevice;
    // The theme the shapes are taken from, loaded for the nominal size at the scale.
    struct wl_cursor_theme *_theme;
    uint32_t _themeScale120;
    // The buffer of the image cursor shown, made for the cursor at the scale.
    struct wl_proxy *_imageBuffer;
    CGSCursor *_imageCursor;
    uint32_t _imageScale120;
    BOOL _applyQueued;
    // What the pointer was last given, so that a request that would change nothing is not made: the serial of the
    // enter it was for, the kind of cursor (hidden, shape, surface) and what identifies it.
    uint32_t _appliedSerial;
    int _appliedKind;
    uintptr_t _appliedKey;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection pointer: (CGSWaylandPointer *) pointer;
// The pointer appeared or went away, or the compositor's cursor shape or fractional scale globals did: the objects
// follow them.
- (void) objectsChanged;
// The cursor, the hide count or the pointer's focus changed: the pointer is given what it shows again, after the
// events being dispatched.
- (void) setNeedsApply;
// The compositor's preferred scale (in 1/120) of the cursor surface.
- (void) preferredScaleChanged: (uint32_t) scale120;
// The scale (in 1/120) of the cursor that is shown; a whole one. Tests.
- (uint32_t) renderScale120;
// Destroys what this made, on the connection.
- (void) invalidate;

@end

#endif
