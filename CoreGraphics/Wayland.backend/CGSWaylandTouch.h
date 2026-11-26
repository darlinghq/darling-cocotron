/* CoreGraphics Wayland backend: the touch screen.

 Copyright (C) 2026 Lubos Dolezel

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

// The process' touch screen on Wayland: it decodes the seat's wl_touch into touch CGEvents (a gesture event, type 29,
// with the finger number, the phase and the position, see CoreGraphicsPrivate.h) and posts them to the process' event
// stream, where the event taps see them before the frameworks above CoreGraphics do. Compositors emulate no pointer
// from a touch screen, so what a finger does to a view that takes no touches is the framework above's to decide.

#ifndef CGSWAYLANDTOUCH_H
#define CGSWAYLANDTOUCH_H

#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdint.h>
#include <wayland-util.h>

@class CGSConnectionWayland;
@class NSMutableDictionary;
struct wl_proxy;

@interface CGSWaylandTouch : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionWayland *_connection; // not retained: the connection owns the decoder
    void *_source;                     // CGEventSourceRef of the hardware state
    struct wl_proxy *_touch;
    // The surface each finger that is down went down on (an NSValue of the pointer, compared by value only), by the
    // compositor's number of the finger.
    NSMutableDictionary *_fingers;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection;

// The seat gained or lost its touch screen.
- (void) seatCapabilities: (uint32_t) capabilities seat: (struct wl_proxy *) seat;
// One event of the wl_touch (down, up, motion, frame, cancel), with the arguments of the wl_touch protocol. These are
// also the entry points a test of the decoding uses, as a compositor with a touch screen cannot be started everywhere.
- (void) touchEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
// A surface of the process went away: its fingers are forgotten.
- (void) surfaceDestroyed: (struct wl_proxy *) surface;
// Cancels every finger, releases the wl_touch.
- (void) stop;

@end

#endif
