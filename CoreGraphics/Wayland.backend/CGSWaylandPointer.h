/* CoreGraphics Wayland backend: the pointer.

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

// The process' one wl_pointer, with the pinch gesture object made on it (zwp_pointer_gestures_v1): it
// decodes what the compositor sends into CGEvents (left, right and other mouse down, up and dragged, mouse
// moved, scroll wheel, and magnify and rotate gestures) and posts them to the process' event stream, where
// the event taps see them before the frameworks above CoreGraphics do. The events are made with the HID
// event source, so the hardware state functions of CGEventSource follow them.
//
// The surface the pointer is over is a wl_surface that the framework that created the window maps to its
// window: the events name it by value (kCGSEventNativeWindow) and carry the pointer's position in it
// (kCGSEventNativeLocationX/Y). Entering and leaving a surface are not CGEvent types; the observer is told.
// The pointer lock is this object's too: CGAssociateMouseAndMouseCursorPosition(false) locks the pointer to a
// surface of the process and the relative pointer's motion makes the mouse events (the cursor stays where it
// was, the events carry the deltas), CGWarpMouseCursorPosition() moves where the cursor is while it is locked
// and asks the compositor for the position through a short lock otherwise, and the hide count of the cursor
// is applied to the pointer's cursor (CGDisplayHideCursor()).

#ifndef CGSWAYLANDPOINTER_H
#define CGSWAYLANDPOINTER_H

#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <CoreGraphics/CGError.h>
#include <stdint.h>
#include <wayland-util.h>

@class CGSConnectionWayland;
@class CGSWaylandCursor;
@class NSMutableDictionary;
struct wl_proxy;

@interface CGSWaylandPointer : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionWayland *_connection; // not retained: the connection owns the pointer
    void *_source;                     // CGEventSourceRef of the hardware state
    // The high-resolution time of the next input event, in CGEvent's clock (nanoseconds since boot).
    uint64_t _pendingTimestamp;
    BOOL _hasPendingTimestamp;
    struct wl_proxy *_pointer;
    struct wl_proxy *_pinch;
    // Where the pointer is: the surface (compared by value), the compositor's serial of the enter, the
    // position in the surface in points.
    struct wl_proxy *_focus;
    uint32_t _enterSerial;
    // The serial of the latest button press while a button is still down in a surface of the process, 0 otherwise: what a
    // drag that starts from the press is tied to.
    uint32_t _dragSerial;
    CGPoint _point;
    // The buttons that are down: 1 left, 2 right, 4 middle, 8 any other, and the code of the last other one.
    unsigned _pressed;
    // The compositor's serial of the press of the left button that is down.
    uint32_t _leftPressSerial;
    // The Cocoa numbers of the buttons that are down (bit n: the button numbered n), and where the pointer was
    // last in a surface of the process, in global coordinates (the state queries; guarded by @synchronized(self)).
    uint32_t _pressedNumbers;
    BOOL _lastGlobalValid;
    CGPoint _lastGlobal;
    uint32_t _otherButton;
    // The last press, for the click state: its surface, button, compositor time (milliseconds, wraps) and
    // position. The count of the press of each button that is down, which its release reports.
    struct wl_proxy *_lastClickSurface;
    uint32_t _lastClickButton, _lastClickTime;
    CGPoint _lastClickPoint;
    int64_t _clickCount;
    NSMutableDictionary *_downClickState;
    // The previous position, and the part of the motion in points that the whole deltas did not carry.
    BOOL _located;
    CGPoint _lastPoint;
    double _remainderX, _remainderY;
    // The scroll frame being collected: axis values (positive is down and right), wheel steps, the source,
    // the axes that stopped, and where the pointer was when it began.
    BOOL _scrollActive, _scrollSourceNamed, _scrollHasSteps;
    uint32_t _scrollSource, _scrollStopped;
    double _scrollX, _scrollY, _scrollStepsX, _scrollStepsY;
    struct wl_proxy *_scrollSurface;
    CGPoint _scrollPoint;
    uint64_t _scrollFlags;
    // The whole pixels of a smooth scroll that the carried remainder holds back.
    double _scrollRemainderX, _scrollRemainderY;
    // A finger scroll that has begun and not ended: where it is.
    BOOL _fingerActive;
    struct wl_proxy *_fingerSurface;
    CGPoint _fingerPoint;
    // A pinch that has begun, with its scale at the previous update.
    struct wl_proxy *_pinchSurface;
    BOOL _pinchActive;
    double _pinchScale;
    // The hold gesture of pointer-gestures v3: a hold with no movement is sent as a zero scroll
    // event with a phase, which is how AppKit cancels a kinetic scroll.
    struct wl_proxy *_hold, *_holdSurface;
    BOOL _holdActive;
    // The pointer lock of the relative mouse mode: the lock and relative pointer objects, the surface locked
    // and whether the compositor has activated the lock; the part of the relative motion that the whole
    // deltas did not carry.
    struct wl_proxy *_lock, *_relative, *_lockSurface;
    BOOL _lockActive, _loggedLockMissing;
    double _relativeRemainderX, _relativeRemainderY;
    // A warp of the unlocked pointer: the short lock that gives the compositor the new position, the surface
    // and the point.
    struct wl_proxy *_warpLock, *_warpSurface;
    CGPoint _warpPoint;
    // What the pointer shows (see CGSWaylandCursor.h).
    CGSWaylandCursor *_cursorObject;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection;
// The serial of the left button's press while it is held down with the pointer in the surface, else 0.
- (uint32_t) heldLeftPressSerialForSurface: (struct wl_proxy *) surface;

// The seat's capabilities changed. The pointer exists while the seat has one.
- (void) seatCapabilities: (uint32_t) capabilities seat: (struct wl_proxy *) seat;
// The compositor offers (or no longer offers) the pointer gestures: the pinch object follows it.
- (void) pointerGesturesChanged;
// The timestamp of the next input event, from input-timestamps-unstable-v1.
- (void) setPendingTimestamp: (uint64_t) timestamp;
// An event of the wl_pointer, or of the pinch or hold gesture object.
- (void) pointerEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
- (void) pinchEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
- (void) holdEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
// Posts the scroll frame that is not complete yet (before an event of another device).
- (void) flushPending;
// The connection closes, or the seat has no pointer any more.
- (void) stop;
// The window system object is gone: the pointer focus on it ends without a leave event.
- (void) surfaceDestroyed: (struct wl_proxy *) surface;
// The framework above moved the pointer within its surface: the next events start from there.
- (void) setSurfacePointX: (double) x y: (double) y;
// Whether the button (CGMouseButton numbering) is held, as the compositor's button events say. Any thread.
- (BOOL) isButtonDown: (uint32_t) button;
// Where the pointer is in global coordinates: where it was last in a surface of the process while it is over
// none, since Wayland tells a client nothing of the pointer elsewhere. NO before it has been over a surface.
// Any thread.
- (BOOL) getLastGlobalLocation: (CGPoint *) location;

// The lock globals appeared or went away; the relative mouse mode wanted by the connection changed or the
// surface to lock may be another one; the lock objects go (the globals or the pointer go away).
- (void) pointerLockGlobalsChanged;
- (void) updatePointerLock;
- (void) releasePointerLockObjects;
- (BOOL) pointerLocked;
// An event of a lock object (the locked pointer, the relative pointer, the lock of a warp).
- (void) lockEvent: (uint32_t) opcode kind: (int) kind proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;
// CGWarpMouseCursorPosition(): the global point; kCGErrorCannotComplete when there is no surface or the
// compositor offers neither pointer-warp nor a pointer lock.
- (CGError) warpToGlobalPoint: (CGPoint) point;
// The hide count of the cursor changed, or the cursor of the process.
- (void) cursorHiddenChanged;
- (void) cursorChanged;
// The compositor's cursor shape or fractional scale global appeared or went away.
- (void) cursorGlobalsChanged;
// The serial of the latest wl_pointer.enter, 0 while the pointer is over no surface of the process.
- (uint32_t) enterSerial;
// The serial of the button press that a drag started now would be tied to, 0 when no button is down (or a drag took the
// press already).
- (uint32_t) dragSerial;
- (void) consumeDragSerial;

@property (readonly) struct wl_proxy *pointerProxy;

@end

#endif
