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
// needed for the smooth scroll deltas (the scroll wheel stays with the framework above for now).
//
// The wheel buttons (4 to 7) are not decoded: a wheel notch is not a click.

#ifndef CGSX11POINTER_H
#define CGSX11POINTER_H

#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <X11/Xlib.h>
#include <stdint.h>

@class CGSConnectionX11;

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
    // Where the pointer was at the previous event, in root pixels, and the part of the motion in points
    // that the whole-number deltas did not carry.
    BOOL _located;
    CGPoint _lastRoot;
    double _remainderX, _remainderY;
}

- (instancetype) initWithConnection: (CGSConnectionX11 *) connection;

// A ButtonPress, ButtonRelease or MotionNotify of a window of the process. The wheel buttons are ignored.
- (void) pointerEvent: (XEvent *) event;
// A crossing event: only where the pointer is (a motion's delta starts from there).
- (void) crossingEvent: (XEvent *) event;

@end

#endif
