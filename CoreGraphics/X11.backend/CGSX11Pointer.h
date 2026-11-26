/* CoreGraphics X11 backend: the pointer.

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

// The process' pointer on X11: it decodes the core pointer events of the one connection (button press and
// release, motion) into CGEvents (left, right and other mouse down, up and dragged, mouse moved) and posts
// them to the process' event stream, where the event taps see them before the frameworks above CoreGraphics
// do. The events carry the click state (the user's double-click interval), the button number, the deltas,
// the modifier flags of the keyboard and the global location; the hardware state functions of CGEventSource
// follow them (the events are made with the HID event source).
//
// Core events are used rather than XInput2: the windows of the process select the core pointer events
// anyway (a window that has no XInput2 device selection, such as the windows of a process that has only
// CoreGraphics, gets them without any setup), they carry the window the pointer is in and its position in
// it, which is what the framework above builds its events from, and every X server has them. XInput2 is
// used for the smooth scroll deltas only.
//
// The scroll wheel comes from two sources. The core wheel buttons (4 to 7) are one notch of a wheel each (line
// units, not continuous), and every X server has them. XInput2 (2.1, smooth scrolling) reports the scroll
// valuators of the devices that have them: the raw motion events of the root window carry the distance scrolled
// in units of the axis' increment, which makes continuous scroll events in points for what is not a whole
// number of notches (a touch pad, a finger scroll, a high resolution wheel), and line events for whole notches.
// A server that emulates the wheel buttons for such a device sends them with the same time as the raw event,
// and those are dropped (the motion was posted already). X11 does not say where a scroll gesture begins or ends,
// or what is momentum: the scroll and momentum phases of the events stay 0.

#ifndef CGSX11POINTER_H
#define CGSX11POINTER_H

#import <Foundation/Foundation.h>
#include <CoreGraphics/CGError.h>
#include <CoreGraphics/CGGeometry.h>
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <stdint.h>
#include "CGSX11RelativeMouseGrab.h"
#include "X11InputMask.h"

@class CGSConnectionX11;

// A scroll axis of an input device: the valuator that carries it and the distance of one notch of a wheel.
typedef struct {
    int sourceID;     // the (slave) device that has the axis
    int valuator;     // the valuator number of the axis
    int horizontal;   // 0 for the vertical axis, 1 for the horizontal one
    double increment; // the valuator distance of one wheel notch
} CGSX11ScrollAxis;

@interface CGSX11Pointer : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionX11 *_connection; // not retained: the connection owns the pointer
    void *_source;                 // CGEventSourceRef of the hardware state
    // The last press, for the click state: its window, button, server time (milliseconds, wraps) and where it was.
    Window _lastClickWindow;
    unsigned int _lastClickButton;
    Time _lastClickTime;
    CGPoint _lastClickPoint;
    int64_t _clickCount;
    // The click state of the press of each button that is down, which its release reports.
    int64_t _downClickState[32];
    // The pointer as the last motion event reported it (root pixels, and the state mask of the server), for the
    // location query; guarded by @synchronized(self). Valid until an event that may have moved the
    // pointer without one (a crossing, button, key or focus event, a warp).
    BOOL _stateKnown;
    int _stateRootX, _stateRootY;
    unsigned int _stateMask;
    // Where the pointer was at the previous event, in root pixels, and the part of the motion in points
    // that the whole-number deltas did not carry.
    BOOL _located;
    CGPoint _lastRoot;
    double _remainderX, _remainderY;
    // XInput2 smooth scrolling: the extension's major opcode (0 when it is not usable), the scroll axes of the
    // devices, whether the raw motion events of the root window are selected (only while the pointer is in
    // one of the process' windows), the part of a continuous scroll in points that the whole numbers did not
    // carry, and the server times of the raw events that scrolled (the wheel buttons the server emulated for
    // them carry the same time).
    int _xiOpcode;
    CGSX11ScrollAxis *_scrollAxes;
    int _scrollAxisCount;
    BOOL _rawSelected;
    BOOL _pointerInside; // the pointer is over one of the process' windows, as far as the crossing events say
    double _scrollRemainderX, _scrollRemainderY;
    Time _scrolledTimes[16];
    int _scrolledNext;
    // The cursor: how many times it was hidden (guarded by @synchronized(self)) and whether the observer was told
    // that it is hidden; the blank cursor the connection's own windows show while it is.
    BOOL _hiddenReported;
    BOOL _isXwayland;
    // XInput2 touch screens and touchpad pinch gestures (CGSX11Touch.m): whether the server speaks the versions that
    // have them (2.2 and 2.4), and the pinch in progress: its window, the scale it last reported and where its last
    // event was (in the window, in device pixels, and on the root window).
    BOOL _touchSelectable, _pinchSelectable;
    BOOL _pinchActive;
    Window _pinchWindow;
    double _pinchScale;
    double _pinchX, _pinchY, _pinchRootX, _pinchRootY;
    // After a warp: the request that made it, the number of events that were queued behind it (the one with the
    // request's serial is the warp's own motion, which is no mouse motion), and the time local mouse motion is
    // dropped until (CFAbsoluteTime).
    unsigned long _echoSerial;
    unsigned _echoRemaining;
    // Relative mouse mode (CGAssociateMouseAndMouseCursorPosition(false)); main thread only. _relativeRequested
    // stays set while the application wants it, _relative.active only while the pointer grab on _relativeWindow
    // is held, which losing the focus releases and regaining it retakes.
    BOOL _relativeRequested;
    int _relativeRetriesLeft;
    // Where the frozen cursor was when the grab was released for a reason other than the application asking,
    // so that the next grab puts it back instead of restarting it at the pointer.
    BOOL _resumeValid;
    double _resumeX, _resumeY;
    Window _relativeWindow;
    X11RelativeMouse _relative;
}

- (instancetype) initWithConnection: (CGSConnectionX11 *) connection;

// A ButtonPress, ButtonRelease or MotionNotify of a window of the process. A press of a wheel button scrolls
// (its release is ignored).
- (void) pointerEvent: (XEvent *) event;
// A crossing event: only where the pointer is (a motion's delta starts from there).
- (void) crossingEvent: (XEvent *) event;
// A generic event of the XInput2 extension (the cookie's data already fetched). Returns whether the event
// was one of the extension's, which the pointer has handled.
- (BOOL) inputExtensionEvent: (XEvent *) event;

// The scroll axes of the input devices, replacing what the server reported, and a raw motion event as the
// server sends it. The connection feeds these from XInput2; they are also the entry points a test of the
// decoding uses with an event it made itself, as an X server that has a smooth scrolling device cannot be
// started everywhere.
// The connection's pointer state changed (see -[CGSConnection cursorHiddenStateChanged:]), and the mouse was
// associated with the cursor or disconnected from it. Any thread.
- (void) cursorHiddenChanged;
- (void) setMouseAssociatedWithCursor: (BOOL) associated;
// Moves the pointer to a point of CoreGraphics' global space.
- (CGError) warpToPoint: (CGPoint) point;
// Called for every event of the connection before it is handled, and for the focus, the windows and the display layout.
- (void) willHandleEvent: (XEvent *) event;
- (void) focusEvent: (XEvent *) event;
- (void) windowEvent: (XEvent *) event;
- (void) windowDestroyed: (Window) window;
- (void) displayLayoutChanged;
// The windows the application could confine the pointer to changed (an overlay appeared): retakes a wanted grab.
- (void) windowsChanged;

// Where the pointer is in root pixels and the state mask of the server, from the event stream while it knows, else
// asked of the server. NO when the server does not say. Any thread.
- (BOOL) getRootX: (int *) x y: (int *) y state: (unsigned int *) state;
- (void) trackStateOfEvent: (XEvent *) event;
- (void) forgetState;
// Relative mode: whether it is wanted, and the frozen cursor in root pixels when the grab is held.
- (BOOL) relativeMouseRequested: (BOOL *) requested frozenRoot: (CGPoint *) root;

- (void) setScrollAxes: (const CGSX11ScrollAxis *) axes count: (int) count;
- (void) rawMotionEvent: (const XIRawEvent *) event;

@end

@interface CGSX11Pointer (Touch)
// Touch screens and pinch gestures (CGSX11Touch.m). A window the process made asks for its touch events (and the pinch
// gestures, where the server has them) with -selectTouchInputOnWindow:, which is a request for the whole XInput2 mask a
// client has on the window, so it is made once the window exists. The events then arrive as XInput2 events: each change
// of a finger of a touch screen is a touch CGEvent (type 29 with the fields kCGSTouchIdentifier to kCGSTouchWindowNumber
// of CoreGraphicsPrivate.h), a pinch is a magnify and a rotate CGEvent. These are also the entry points a test of the
// decoding uses with an event it made itself, as an X server that has a touch device cannot be started everywhere.
- (void) selectTouchInputOnWindow: (Window) window;
// One XI_TouchBegin, XI_TouchUpdate or XI_TouchEnd for the window it was selected on, with its position in that window
// and on the root window (device pixels).
- (void) touchEventType: (int) type
                 device: (int) deviceID
                 detail: (unsigned int) detail
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  rootX: (double) rootX
                  rootY: (double) rootY;
#ifdef X11_XI_GESTURES
// One XI_GesturePinchBegin, Update or End: the pinch's scale since the fingers began (1 at the start), the rotation since
// the previous update in degrees clockwise, and whether an end cancelled the gesture.
- (void) pinchEventType: (int) type
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  rootX: (double) rootX
                  rootY: (double) rootY
                  scale: (double) scale
             deltaAngle: (double) degrees
              cancelled: (BOOL) cancelled;
#endif
// Ends a pinch in progress as cancelled (the window it is on is going away); nothing when there is none, or it is on
// another window.
- (void) cancelPinchOnWindow: (Window) window;
@end

#endif
