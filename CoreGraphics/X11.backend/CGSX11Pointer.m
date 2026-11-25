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

#import "CGSX11Pointer.h"
#import "CGSConnectionX11.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>
#include <X11/Xutil.h>

// The wheel buttons: vertical 4 and 5, horizontal 6 and 7.
static BOOL isWheelButton(unsigned int button) {
    return button >= Button4 && button <= 7;
}

// Cocoa numbers the mouse buttons from 0 (left), 1 (right) and 2 for the middle one, where X numbers them
// 1, 3 and 2. The extra buttons start at 8 (back) and 9 (forward), which are 3 and 4.
static int64_t buttonNumberForX(unsigned int xButton) {
    switch (xButton) {
    case Button1: return 0;
    case Button3: return 1;
    case Button2: return 2;
    default: return xButton >= 8 ? (int64_t) xButton - 5 : (int64_t) xButton;
    }
}

@implementation CGSX11Pointer

- (instancetype) initWithConnection: (CGSConnectionX11 *) connection {
    self = [super init];
    if (self == nil)
        return nil;
    _connection = connection;
    // The pointer is hardware: the events it posts change the state the hardware state functions report.
    _source = (void *) CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    return self;
}

- (void) dealloc {
    if (_source != NULL)
        CFRelease((CFTypeRef) _source);
    [super dealloc];
}

// Cocoa groups clicks only within its double-click interval and four points of the preceding press, and
// only for the same button in the same window. The X server's timestamp is used rather than the wall
// clock, which the client cannot compare against a server that may be a different machine, and its
// unsigned subtraction covers the 32-bit wrap.
- (int64_t) clickStateForPress: (XButtonEvent *) press point: (CGPoint) point {
    CGFloat dx = point.x - _lastClickPoint.x;
    CGFloat dy = point.y - _lastClickPoint.y;
    if (_lastClickWindow == press->window && _lastClickButton == press->button &&
        (uint32_t) (press->time - _lastClickTime) < _CGSDoubleClickInterval() * 1000 &&
        dx * dx + dy * dy <= 16 && _clickCount < INT64_MAX)
        _clickCount++;
    else
        _clickCount = 1;
    _lastClickTime = press->time;
    _lastClickButton = press->button;
    _lastClickWindow = press->window;
    _lastClickPoint = point;
    return _clickCount;
}

// The motion since the previous pointer event in whole points; what is left stays for the next one, so
// that a slow motion at a fractional scale is not lost.
- (void) takeDeltaForRoot: (CGPoint) root x: (int64_t *) dx y: (int64_t *) dy {
    *dx = *dy = 0;
    if (!_located) {
        _located = YES;
        _lastRoot = root;
        return;
    }
    CGPoint last = [_connection _cgPointFromRoot: _lastRoot];
    CGPoint now = [_connection _cgPointFromRoot: root];
    double x = now.x - last.x + _remainderX;
    double y = now.y - last.y + _remainderY;
    double wholeX = x < 0 ? ceil(x) : floor(x);
    double wholeY = y < 0 ? ceil(y) : floor(y);
    _remainderX = x - wholeX;
    _remainderY = y - wholeY;
    _lastRoot = root;
    *dx = (int64_t) wholeX;
    *dy = (int64_t) wholeY;
}

- (void) crossingEvent: (XEvent *) event {
    if (!event->xcrossing.same_screen)
        return;
    _lastRoot = CGPointMake(event->xcrossing.x_root, event->xcrossing.y_root);
    _located = YES;
}

- (void) pointerEvent: (XEvent *) ev {
    id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
    CGEventType type;
    int64_t button = 0, clickState = -1;
    unsigned int xButton = 0, state;
    Window window;
    int winX, winY, rootX, rootY;

    switch (ev->type) {
    case ButtonPress:
    case ButtonRelease:
        xButton = ev->xbutton.button;
        if (isWheelButton(xButton))
            return;
        window = ev->xbutton.window;
        winX = ev->xbutton.x;
        winY = ev->xbutton.y;
        rootX = ev->xbutton.x_root;
        rootY = ev->xbutton.y_root;
        state = ev->xbutton.state;
        button = buttonNumberForX(xButton);
        break;
    case MotionNotify:
        window = ev->xmotion.window;
        winX = ev->xmotion.x;
        winY = ev->xmotion.y;
        rootX = ev->xmotion.x_root;
        rootY = ev->xmotion.y_root;
        state = ev->xmotion.state;
        break;
    default:
        return;
    }

    // The observer holds the pointer for itself, or the window is not one input is decoded for.
    if ([observer respondsToSelector: @selector(nativeConnectionObserverHandlesPointerEvent:)] &&
        [observer nativeConnectionObserverHandlesPointerEvent: ev]) {
        _located = NO;
        return;
    }

    CGPoint root = CGPointMake(rootX, rootY);
    CGPoint global = [_connection _cgPointFromRoot: root];
    int64_t deltaX = 0, deltaY = 0;

    if (ev->type == MotionNotify) {
        // X numbers the right button 3 (Button3Mask) and Button2Mask is the middle button, whose drags
        // are other-mouse drags.
        if (state & Button1Mask) {
            type = kCGEventLeftMouseDragged;
            button = 0;
        } else if (state & Button3Mask) {
            type = kCGEventRightMouseDragged;
            button = 1;
        } else if (state & Button2Mask) {
            type = kCGEventOtherMouseDragged;
            button = 2;
        } else {
            type = kCGEventMouseMoved;
            button = 0;
        }
        [self takeDeltaForRoot: root x: &deltaX y: &deltaY];
    } else {
        BOOL pressed = ev->type == ButtonPress;
        switch (xButton) {
        case Button1: type = pressed ? kCGEventLeftMouseDown : kCGEventLeftMouseUp; break;
        case Button3: type = pressed ? kCGEventRightMouseDown : kCGEventRightMouseUp; break;
        default: type = pressed ? kCGEventOtherMouseDown : kCGEventOtherMouseUp; break;
        }
        if (pressed) {
            clickState = [self clickStateForPress: &ev->xbutton point: global];
            if (button < 32)
                _downClickState[button] = clickState;
        } else {
            // The release of a click reports the count its press was given, so that a double click's two
            // presses are matched by their own releases. A release with no press behind it (the process
            // started with the button held) is a single click.
            clickState = button < 32 && _downClickState[button] > 0 ? _downClickState[button] : 1;
            if (button < 32)
                _downClickState[button] = 0;
        }
        // The pointer does not move with a button; where it is now is where the next motion starts from.
        _lastRoot = root;
        _located = YES;
    }

    CGEventRef event = CGEventCreateMouseEvent((CGEventSourceRef) _source, type, global, (CGMouseButton) button);
    if (event == NULL)
        return;
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, button);
    if (clickState >= 0)
        CGEventSetIntegerValueField(event, kCGMouseEventClickState, clickState);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, deltaX);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, deltaY);
    // The modifier flags are the keyboard's (the pointer event's state was already compared with it).
    CGEventSetFlags(event, (CGEventFlags) [_connection modifierFlags]);

    // The window of a CGS window; the windows of the framework above are known to it by the X window.
    CGSWindowID windowID = [_connection _windowIDForNativeWindow: window];
    if (windowID != 0) {
        CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer, windowID);
        CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, windowID);
    }
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) window);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationX, winX);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationY, winY);
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationX, llround(global.x * 1024));
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationY, llround(global.y * 1024));

    if ([observer respondsToSelector: @selector(nativeConnectionWillPostPointerEvent:forXEvent:)] &&
        ![observer nativeConnectionWillPostPointerEvent: (struct __CGEvent *) event forXEvent: ev])
        CGEventSetIntegerValueField(event, kCGSEventTapsOnly, 1);

    _CGSEventStreamPost(event);
    CFRelease(event);
}

@end
