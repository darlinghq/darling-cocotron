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
#import "X11InputMask.h"
#import "CGSConnectionX11.h"
#import "CGSWindowX11.h"
#import "CGSX11Tablet.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <X11/Xutil.h>

// The wheel buttons: vertical 4 and 5, horizontal 6 and 7.
static BOOL isWheelButton(unsigned int button) {
    return button >= Button4 && button <= 7;
}

// Whether a distance in notches is a whole number of them (a wheel click) and not a part of one (a smooth scroll).
static BOOL isWholeNotches(double notches) {
    return fabs(notches - round(notches)) < 1e-6;
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
    {
        int opcode, event, error;
        _isXwayland = connection->_display != NULL &&
                      XQueryExtension(connection->_display, "XWAYLAND", &opcode, &event, &error);
    }
    // The pointer is hardware: the events it posts change the state the hardware state functions report.
    _source = (void *) CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    [self setUpInputExtension];
    return self;
}

- (void) dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget: self];
    X11RelativeMouseEnd(&_relative);
    free(_scrollAxes);
    [_tablet release];
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
    // The pointer leaves for a child of the window it was in when the window reports the inferior.
    if (event->xcrossing.detail != NotifyInferior)
        [self setPointerInProcessWindow: event->type == EnterNotify];
    else if (event->type == EnterNotify)
        [self setPointerInProcessWindow: YES];
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
        if (isWheelButton(xButton)) {
            // A notch of the wheel is a press and a release, and the press scrolls.
            if (ev->type == ButtonPress)
                [self wheelButtonPress: &ev->xbutton];
            return;
        }
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

    // The motion a warp made is not mouse motion: the pointer is where the application put it.
    if (ev->type == MotionNotify && _echoRemaining > 0 && !_relative.active) {
        if (ev->xmotion.serial == _echoSerial) {
            _echoRemaining = 0;
            _lastRoot = CGPointMake(rootX, rootY);
            _located = YES;
            return;
        }
    }

    [self setPointerInProcessWindow: YES];
    // While the cursor is frozen the events are where it is, and the motion is the physical pointer's.
    BOOL frozen = _relative.active;
    X11RelativeMouseMotion relativeMotion = {false, false, 0.0, 0.0, false, 0, 0};
    if (frozen) {
        if (ev->type == MotionNotify) {
            bool recorded;
            relativeMotion = X11RelativeMouseMotionEvent(_connection->_display, &_relative, &ev->xmotion,
                                                         [self warpsHonoured], &recorded);
            // An echo that could not be recorded would be taken for input.
            if (!recorded) {
                [self suspendRelativeMouse];
                return;
            }
            if (!relativeMotion.post)
                return;
        }
        // The window's origin in root coordinates is (x_root - x, y_root - y).
        winX = (int) _relative.virtualX - (rootX - winX);
        winY = (int) _relative.virtualY - (rootY - winY);
        rootX = (int) _relative.virtualX;
        rootY = (int) _relative.virtualY;
    }
    CGPoint root = CGPointMake(rootX, rootY);
    CGPoint global = [_connection _cgPointFromRoot: root];
    int64_t deltaX = 0, deltaY = 0;

    if (ev->type == MotionNotify && frozen) {
        [self takeDeltaOfRootDistance: CGPointMake(relativeMotion.deltaX, relativeMotion.deltaY) x: &deltaX y: &deltaY];
    }
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
        if (!frozen)
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
        if (!frozen) {
            _lastRoot = root;
            _located = YES;
        }
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

    // The window of a CGS window; the windows of the framework above are known to it by the X window. The
    // events of a display overlay have none, like those of a captured display.
    CGSWindowID windowID = [_connection _windowIDForNativeWindow: window];
    if (windowID != 0 && ![_connection _isDisplayOverlayNativeWindow: window]) {
        CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer, windowID);
        CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, windowID);
    }
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) window);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationX, winX);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationY, winY);
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationX, llround(global.x * 1024));
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationY, llround(global.y * 1024));

    BOOL motion = ev->type == MotionNotify;
    if (motion) {
        // The deltas are what CGGetLastMouseDelta() reports, whether or not the event is posted.
        [_connection accumulateMouseDeltaX: (double) deltaX y: (double) deltaY];
        // For a while after a warp the local mouse motion is dropped (CGSetLocalEventsSuppressionInterval()).
        // The events of the frozen cursor are not the cursor's motion, and so are not suppressed.
        if (!frozen && [_connection localMouseMotionSuppressed]) {
            CFRelease(event);
            return;
        }
    }
    if ([observer respondsToSelector: @selector(nativeConnectionWillPostPointerEvent:forXEvent:)] &&
        ![observer nativeConnectionWillPostPointerEvent: (struct __CGEvent *) event forXEvent: ev])
        CGEventSetIntegerValueField(event, kCGSEventTapsOnly, 1);

    _CGSEventStreamPost(event);
    CFRelease(event);
}


#pragma mark - Scroll

// The wheel is a different device from the pointer's motion: it posts a scroll event at the position the
// pointer has, with the modifier flags of the keyboard. The event says which window system window it is for and
// where the pointer was in it, as the pointer events do.
- (void) postScrollContinuous: (BOOL) continuous
                     vertical: (int32_t) vertical
                   horizontal: (int32_t) horizontal
                       window: (Window) window
                         winX: (int) winX
                         winY: (int) winY
                         root: (CGPoint) root
                        state: (unsigned int) state {
    // While the cursor is frozen the wheel scrolls where the cursor is.
    if (_relative.active) {
        winX = (int) _relative.virtualX - ((int) root.x - winX);
        winY = (int) _relative.virtualY - ((int) root.y - winY);
        root = CGPointMake(_relative.virtualX, _relative.virtualY);
        window = _relativeWindow;
    }
    CGEventRef event = CGEventCreateScrollWheelEvent2((CGEventSourceRef) _source,
                                                      continuous ? kCGScrollEventUnitPixel : kCGScrollEventUnitLine, 2,
                                                      vertical, horizontal, 0);
    if (event == NULL)
        return;
    CGPoint global = [_connection _cgPointFromRoot: root];
    CGEventSetLocation(event, global);
    CGEventSetFlags(event, (CGEventFlags) [_connection modifierFlags]);
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) window);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationX, winX);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationY, winY);
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationX, llround(global.x * 1024));
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationY, llround(global.y * 1024));
    _CGSEventStreamPost(event);
    CFRelease(event);
}

// A press of a core wheel button: one notch of a wheel. Buttons 4 and 5 are up and down, 6 and 7 left and
// right; up and right are positive (the direction the content is moved to).
- (void) wheelButtonPress: (XButtonEvent *) press {
    // The server emulated the button for a notch of a smooth scrolling device, whose raw motion was posted.
    for (int i = 0; i < 16; i++) {
        if (_scrolledTimes[i] != 0 && _scrolledTimes[i] == press->time)
            return;
    }
    int32_t vertical = 0, horizontal = 0;
    switch (press->button) {
    case Button4: vertical = 1; break;
    case Button5: vertical = -1; break;
    case 6: horizontal = -1; break;
    case 7: horizontal = 1; break;
    }
    [self postScrollContinuous: NO
                      vertical: vertical
                    horizontal: horizontal
                        window: press->window
                          winX: press->x
                          winY: press->y
                          root: CGPointMake(press->x_root, press->y_root)
                         state: press->state];
}

// The window of the process the pointer is over, found as the server would deliver a button press: the
// deepest window at the pointer's position for which this connection selected button presses, and where the
// pointer is in it. NO when the pointer is not over one.
- (BOOL) windowUnderPointer: (Window *) found x: (int *) foundX y: (int *) foundY root: (CGPoint *) rootPoint state: (unsigned int *) state {
    Display *display = _connection->_display;
    Window rootWindow = DefaultRootWindow(display), reportedRoot, reportedChild;
    int rootX, rootY, x, y;
    unsigned int mask;

    if (!XQueryPointer(display, rootWindow, &reportedRoot, &reportedChild, &rootX, &rootY, &x, &y, &mask))
        return NO;
    *rootPoint = CGPointMake(rootX, rootY);
    *state = mask;
    BOOL result = NO;
    Window current = rootWindow;
    for (int depth = 0; depth < 32; depth++) {
        int atX, atY;
        Window child = None;
        if (!XTranslateCoordinates(display, rootWindow, current, rootX, rootY, &atX, &atY, &child))
            break;
        XWindowAttributes attributes;
        if (current != rootWindow && XGetWindowAttributes(display, current, &attributes) &&
            (attributes.your_event_mask & ButtonPressMask)) {
            *found = current;
            *foundX = atX;
            *foundY = atY;
            result = YES;
        }
        if (child == None)
            break;
        current = child;
    }
    return result;
}

- (void) rawMotionEvent: (const XIRawEvent *) raw {
    if (raw->evtype != XI_RawMotion || raw->valuators.mask == NULL || raw->raw_values == NULL)
        return;
    // The distance scrolled, in notches: up and right are positive. A vertical valuator grows when the content
    // moves up (scrolling down), a horizontal one when it moves left.
    double vertical = 0, horizontal = 0;
    BOOL scrolled = NO;
    const double *values = raw->raw_values;
    for (int bit = 0, index = 0; bit < raw->valuators.mask_len * 8; bit++) {
        if (!XIMaskIsSet(raw->valuators.mask, bit))
            continue;
        double value = values[index++];
        for (int i = 0; i < _scrollAxisCount; i++) {
            const CGSX11ScrollAxis *axis = &_scrollAxes[i];
            // Some libXi versions leave the source of a raw event 0 (freedesktop.org bug 34240): the first device that
            // has the valuator then.
            if ((raw->sourceid != 0 && axis->sourceID != raw->sourceid) || axis->valuator != bit || axis->increment == 0)
                continue;
            if (axis->horizontal)
                horizontal += value / axis->increment;
            else
                vertical -= value / axis->increment;
            scrolled = YES;
            if (raw->sourceid == 0)
                break;
        }
    }
    if (!scrolled)
        return;
    _scrolledTimes[_scrolledNext++ % 16] = raw->time;

    BOOL continuous = !(isWholeNotches(vertical) && isWholeNotches(horizontal));
    int32_t v, h;
    if (continuous) {
        // Points: what the event source says a line is worth, with the part the whole numbers do not carry kept
        // for the next event, so that a slow scroll is not lost.
        double perNotch = CGEventSourceGetPixelsPerLine((CGEventSourceRef) _source);
        double y = vertical * perNotch + _scrollRemainderY;
        double x = horizontal * perNotch + _scrollRemainderX;
        v = (int32_t) (y < 0 ? ceil(y) : floor(y));
        h = (int32_t) (x < 0 ? ceil(x) : floor(x));
        _scrollRemainderY = y - v;
        _scrollRemainderX = x - h;
        if (v == 0 && h == 0)
            return;
    } else {
        v = (int32_t) lround(vertical);
        h = (int32_t) lround(horizontal);
        if (v == 0 && h == 0)
            return;
    }

    Window window = None;
    int winX = 0, winY = 0;
    CGPoint root = CGPointZero;
    unsigned int state = 0;
    if (![self windowUnderPointer: &window x: &winX y: &winY root: &root state: &state]) {
        // The grab confines the pointer to a window of the process, whatever the hit test finds there.
        if (!_relative.active)
            return;
        window = _relativeWindow;
        winX = winY = 0;
        root = CGPointMake(_relative.virtualX, _relative.virtualY);
    }
    [self postScrollContinuous: continuous vertical: v horizontal: h window: window winX: winX winY: winY root: root state: state];
}


#pragma mark - Cursor

// Applies what the hide count says: the windows of the process show a blank cursor while it is not zero and the
// selected cursor after it, on the main thread, where Xlib is used.
- (void) reportCursorHidden {
    BOOL hidden = ![_connection cursorIsVisible];
    if (hidden == _hiddenReported)
        return;
    _hiddenReported = hidden;
    [_connection _applyCursor];
    // On Xwayland a warp is only honoured while the cursor is hidden, and the grab depends on it.
    if (_relativeRequested && !_relative.active)
        [self beginRelativeMouse];
}

- (void) cursorHiddenChanged {
    if ([NSThread isMainThread])
        [self reportCursorHidden];
    else
        [self performSelectorOnMainThread: @selector(reportCursorHidden) withObject: nil waitUntilDone: NO];
}

#pragma mark - Mouse deltas

// The motion of the physical pointer, a distance in root pixels, in whole points (the rest is carried).
- (void) takeDeltaOfRootDistance: (CGPoint) distance x: (int64_t *) dx y: (int64_t *) dy {
    CGPoint origin = [_connection _cgPointFromRoot: CGPointZero];
    CGPoint moved = [_connection _cgPointFromRoot: distance];
    double x = moved.x - origin.x + _remainderX;
    double y = moved.y - origin.y + _remainderY;
    double wholeX = x < 0 ? ceil(x) : floor(x);
    double wholeY = y < 0 ? ceil(y) : floor(y);
    _remainderX = x - wholeX;
    _remainderY = y - wholeY;
    *dx = (int64_t) wholeX;
    *dy = (int64_t) wholeY;
}

#pragma mark - Warp

// Whether the server moves the pointer for a warp. On Xwayland a warp only reaches the compositor while the
// cursor is hidden.
- (BOOL) warpsHonoured {
    return !_isXwayland || ![_connection cursorIsVisible];
}

- (CGError) warpToPoint: (CGPoint) point {
    if (![NSThread isMainThread]) {
        // The relative mouse state and Xlib are used from the main thread. The warp makes no delta, so the
        // caller need not wait.
        [self performSelectorOnMainThread: @selector(warpOnMainThread:)
                               withObject: [NSValue valueWithBytes: &point objCType: @encode(CGPoint)]
                            waitUntilDone: NO];
        return kCGErrorSuccess;
    }
    [self warpOnMainThread: [NSValue valueWithBytes: &point objCType: @encode(CGPoint)]];
    return kCGErrorSuccess;
}

- (void) warpOnMainThread: (NSValue *) value {
    CGPoint point;
    [value getValue: &point];
    Display *display = _connection->_display;
    int rootX, rootY;
    [_connection _getRootX: &rootX y: &rootY forPoint: point];

    if (_relative.active) {
        // The frozen cursor moves, with no delta; the warp's echo is dropped.
        if (!X11RelativeMouseApplicationWarp(display, &_relative, rootX, rootY, [self warpsHonoured]))
            [self suspendRelativeMouse];
        return;
    }
    unsigned long serial;
    unsigned queued = X11RelativeMouseWarpPointer(display, rootX, rootY, &serial);
    // The motion the warp makes comes with the request's serial and is no mouse motion.
    _echoSerial = serial;
    _echoRemaining = queued;
    _lastRoot = CGPointMake(rootX, rootY);
    _located = YES;
    // Local mouse motion is suppressed for a while (the pointer itself is the server's, so the events are what
    // can be held back).
    [_connection noteMouseWarp];
    [self forgetState];
    if (_relativeRequested) {
        // Suspended (focus lost, retry pending): the next grab must resume at the application's target.
        _resumeValid = YES;
        _resumeX = rootX;
        _resumeY = rootY;
    }
}

#pragma mark - Relative mouse

- (void) setMouseAssociatedWithCursor: (BOOL) associated {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread: @selector(setAssociatedOnMainThread:)
                               withObject: [NSNumber numberWithBool: associated]
                            waitUntilDone: NO];
        return;
    }
    [self setAssociatedOnMainThread: [NSNumber numberWithBool: associated]];
}

- (void) setAssociatedOnMainThread: (NSNumber *) wanted {
    if (![wanted boolValue]) {
        _relativeRequested = YES;
        [self beginRelativeMouse];
        // A failed first grab (AlreadyGrabbed while a window manager holds the pointer) is retried for a
        // while, like one after a reconfiguration.
        if (!_relative.active)
            [self scheduleRelativeMouseRetry];
    } else {
        _relativeRequested = NO;
        double x = _relative.virtualX, y = _relative.virtualY;
        BOOL wasActive = _relative.active;
        [self suspendRelativeMouse];
        _resumeValid = NO;
        // The cursor shows where it froze.
        if (wasActive && [self warpsHonoured]) {
            unsigned long serial;
            unsigned queued = X11RelativeMouseWarpPointer(_connection->_display, (int) x, (int) y, &serial);
            _echoSerial = serial;
            _echoRemaining = queued;
        }
        _lastRoot = CGPointMake(x, y);
        _located = wasActive;
    }
    XSync(_connection->_display, False);
}

// The window the pointer is grabbed for: a display overlay, which covers the screen above every window, so it is
// the one while there is one; else the framework's choice (the key window), else the window of the connection that
// holds the keyboard focus.
- (Window) relativeMouseWindowChoice {
    CGSWindowX11 *overlay = [_connection _displayOverlayWindow];
    if (overlay != nil)
        return overlay->_window;
    id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
    if ([observer respondsToSelector: @selector(nativeConnectionRelativeMouseWindow)]) {
        Window window = (Window) [observer nativeConnectionRelativeMouseWindow];
        if (window != None)
            return window;
    }
    Window focus;
    int revert;
    XGetInputFocus(_connection->_display, &focus, &revert);
    return focus != None && focus != PointerRoot && [_connection _windowIDForNativeWindow: focus] != 0 ? focus : None;
}

// Takes the pointer grab, starting the frozen cursor at the current pointer position. Without the keyboard
// focus nothing is grabbed (a grab would take the pointer from whichever client has it); FocusIn retries the
// preserved request.
- (void) beginRelativeMouse {
    Display *display = _connection->_display;
    Window window = [self relativeMouseWindowChoice];
    if (window == None)
        return;
    if (_relative.active && _relativeWindow == window)
        return;
    [self suspendRelativeMouse];

    int result = X11RelativeMouseGrab(display, &_relative, window, [self warpsHonoured]);
    if (result != GrabSuccess)
        return;
    _relativeWindow = window;
    _located = NO;
    if (_resumeValid) {
        // The cursor stays where it froze, not where the pointer is now.
        X11RelativeMouseRestoreCursor(&_relative, _resumeX, _resumeY);
        _resumeValid = NO;
    }
    [self reportRelativeMouseGrab];
}

- (void) reportRelativeMouseGrab {
    // What was known of the pointer is stale: a grab replaced the pointer's windows' view of it.
    [self forgetState];
    id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
    if ([observer respondsToSelector: @selector(nativeConnectionRelativeMouseGrabChanged:window:rootX:rootY:)])
        [observer nativeConnectionRelativeMouseGrabChanged: _relative.active
                                                    window: _relativeWindow
                                                      rootX: (int) _relative.virtualX
                                                      rootY: (int) _relative.virtualY];
}

// Releases the grab without cancelling the request (focus loss, window gone).
- (void) suspendRelativeMouse {
    if (!_relative.active)
        return;
    _resumeValid = YES;
    _resumeX = _relative.virtualX;
    _resumeY = _relative.virtualY;
    X11RelativeMouseRelease(_connection->_display, &_relative);
    _relativeWindow = None;
    [self reportRelativeMouseGrab];
}

// A reconfiguration (the grab window moved or resized, the screen layout changed) can move a confined pointer
// by itself and changes where it can go: take a new snapshot. The new grab can fail while the window manager
// is mid-operation, so a failure is retried for a while.
- (void) resnapshotRelativeMouse {
    if (!_relative.active)
        return;
    // Most RandR events change nothing the grab depends on: skip the new grab unless the reachable rectangle moved.
    X11RelativeMouseBounds bounds;
    if (X11RelativeMouseWindowBounds(_connection->_display, _relativeWindow, &bounds) &&
        bounds.minX == _relative.minX && bounds.minY == _relative.minY &&
        bounds.maxX == _relative.maxX && bounds.maxY == _relative.maxY)
        return;
    [self suspendRelativeMouse];
    [self beginRelativeMouse];
    if (_relativeRequested && !_relative.active)
        [self scheduleRelativeMouseRetry];
}

- (void) scheduleRelativeMouseRetry {
    _relativeRetriesLeft = 10;
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retryRelativeMouse) object: nil];
    [self performSelector: @selector(retryRelativeMouse) withObject: nil afterDelay: 0.1];
}

- (void) retryRelativeMouse {
    if (!_relativeRequested || _relative.active)
        return;
    [self beginRelativeMouse];
    if (_relativeRequested && !_relative.active && --_relativeRetriesLeft > 0)
        [self performSelector: @selector(retryRelativeMouse) withObject: nil afterDelay: 0.1];
}

- (void) windowsChanged {
    if (_relativeRequested && !_relative.active)
        [self beginRelativeMouse];
}

- (BOOL) relativeMouseRequested: (BOOL *) requested frozenRoot: (CGPoint *) root {
    if (requested != NULL)
        *requested = _relativeRequested;
    if (root != NULL && _relative.active)
        *root = CGPointMake(_relative.virtualX, _relative.virtualY);
    return _relative.active;
}

// Tracks the pointer from the event stream, so that asking for the mouse location, as applications do every frame,
// costs no round trip while the pointer moves over the process' windows. Motion over other clients' windows is
// not reported, which is why every event that can precede such motion forgets it.
- (void) trackStateOfEvent: (XEvent *) ev {
    switch (ev->type) {
    case MotionNotify:
        @synchronized(self) {
            _stateKnown = !ev->xmotion.send_event && ev->xmotion.same_screen &&
                          ev->xmotion.root == DefaultRootWindow(_connection->_display);
            _stateRootX = ev->xmotion.x_root;
            _stateRootY = ev->xmotion.y_root;
            _stateMask = ev->xmotion.state;
        }
        break;
    case ButtonPress:
    case ButtonRelease:
    case KeyPress:
    case KeyRelease:
    case EnterNotify:
    case LeaveNotify:
    case FocusIn:
    case FocusOut:
    case KeymapNotify:
        [self forgetState];
        break;
    default:
        break;
    }
}

- (void) forgetState {
    @synchronized(self) {
        _stateKnown = NO;
    }
}

- (BOOL) getRootX: (int *) x y: (int *) y state: (unsigned int *) state {
    @synchronized(self) {
        if (_stateKnown) {
            *x = _stateRootX;
            *y = _stateRootY;
            *state = _stateMask;
            return YES;
        }
    }
    // Not known from the event stream: ask the server, and again next time.
    Display *display = _connection->_display;
    Window root, child;
    int winX, winY;
    return XQueryPointer(display, DefaultRootWindow(display), &root, &child, x, y, &winX, &winY, state);
}

// Every event of the connection: a warp's expected echoes age with the events handled (the motion ages them
// itself).
- (void) willHandleEvent: (XEvent *) event {
    [self trackStateOfEvent: event];
    if (_relative.active && event->type != MotionNotify)
        X11RelativeMouseTick(&_relative);
    if (_echoRemaining > 0 && event->type != MotionNotify)
        _echoRemaining--;
}

- (void) focusEvent: (XEvent *) event {
    // Focus changes caused by a grab, or by the pointer entering the window or one of its children, do not
    // move the keyboard focus.
    if (event->xfocus.mode == NotifyGrab || event->xfocus.mode == NotifyUngrab ||
        event->xfocus.detail == NotifyPointer || event->xfocus.detail == NotifyPointerRoot ||
        event->xfocus.detail == NotifyInferior)
        return;
    if (event->type == FocusIn) {
        // Losing the focus released the pointer grab; the application still wants relative mode.
        if (_relativeRequested && !_relative.active)
            [self beginRelativeMouse];
    } else {
        // Give the pointer back to other clients; relative mode stays requested and resumes on FocusIn.
        [self suspendRelativeMouse];
    }
}

- (void) windowEvent: (XEvent *) event {
    if (!_relative.active)
        return;
    switch (event->type) {
    case ConfigureNotify:
        if (event->xconfigure.window == _relativeWindow)
            [self resnapshotRelativeMouse];
        break;
    case UnmapNotify:
        // The server released a grab on a window that became unviewable.
        if (event->xunmap.window == _relativeWindow)
            [self suspendRelativeMouse];
        break;
    default:
        break;
    }
}

- (void) windowDestroyed: (Window) window {
    [_tablet windowDestroyed: window];
    [self cancelPinchOnWindow: window];
    if (_relative.active && _relativeWindow == window)
        [self suspendRelativeMouse];
}

- (void) displayLayoutChanged {
    // The root may have shrunk or a monitor gone: the pointer's reachable area, and with it the grab's bounds, changed.
    [self resnapshotRelativeMouse];
    _located = NO;
}

#pragma mark - XInput2

// The raw motion events carry the scroll valuators of the devices that have them; they are selected while the
// pointer is over a window of the process (every motion over the desktop would otherwise wake the process).
- (void) setUpInputExtension {
    Display *display = _connection->_display;
    int opcode, firstEvent, firstError;
    if (display == NULL || !XQueryExtension(display, "XInputExtension", &opcode, &firstEvent, &firstError))
        return;
    // The server answers with the highest version it has up to the one asked for. 2.1 is the version that has smooth
    // scrolling, 2.2 adds touch screens and 2.4 the pinch gestures of touchpads, whose selection the framework above asks
    // for (-selectTouchInputOnWindow:). A device reports touches or gestures, never both, and gestures only come from
    // dependent devices such as touchpads: which one a device reports is a property of the device, not of the version
    // asked for, so touch screens and servers without 2.4 are not affected by asking.
    int major = 2, minor = 4;
    if (XIQueryVersion(display, &major, &minor) != Success || major < 2 || (major == 2 && minor < 1))
        return;
    _touchSelectable = major > 2 || minor >= 2;
#ifdef X11_XI_GESTURES
    _pinchSelectable = major > 2 || minor >= 4;
#endif
    _xiOpcode = opcode;
    _tablet = [[CGSX11Tablet alloc] initWithPointer: self connection: _connection source: _source];
    [self selectInputExtensionEvents];
    [self queryScrollAxes];
}

- (void) selectInputExtensionEvents {
    Display *display = _connection->_display;
    unsigned char hierarchy[XIMaskLen(XI_LASTEVENT)], masters[XIMaskLen(XI_LASTEVENT)];
    memset(hierarchy, 0, sizeof(hierarchy));
    memset(masters, 0, sizeof(masters));
    XISetMask(hierarchy, XI_HierarchyChanged);
    XISetMask(masters, XI_DeviceChanged);
    if (_rawSelected) {
        XISetMask(masters, XI_RawMotion);
        if ([_tablet deviceCount] > 0) {
            XISetMask(masters, XI_RawButtonPress);
            XISetMask(masters, XI_RawButtonRelease);
        }
    }
    // The tool serial numbers of tablets change with the tool in proximity.
    if ([_tablet deviceCount] > 0)
        XISetMask(hierarchy, XI_PropertyEvent);
    XIEventMask masks[2] = {
        {.deviceid = XIAllDevices, .mask_len = sizeof(hierarchy), .mask = hierarchy},
        {.deviceid = XIAllMasterDevices, .mask_len = sizeof(masters), .mask = masters},
    };
    XISelectEvents(display, DefaultRootWindow(display), masks, 2);
    XFlush(display);
}

// Reads the scroll axes of the physical devices from the server.
- (void) queryScrollAxes {
    int count = 0;
    XIDeviceInfo *devices = XIQueryDevice(_connection->_display, XIAllDevices, &count);
    int capacity = 0, axisCount = 0;
    CGSX11ScrollAxis *axes = NULL;
    for (int d = 0; d < count; d++) {
        if (devices[d].use != XISlavePointer && devices[d].use != XIFloatingSlave)
            continue;
        for (int c = 0; c < devices[d].num_classes; c++) {
            if (devices[d].classes[c]->type != XIScrollClass)
                continue;
            XIScrollClassInfo *info = (XIScrollClassInfo *) devices[d].classes[c];
            if (axisCount == capacity) {
                capacity = capacity ? capacity * 2 : 8;
                axes = realloc(axes, capacity * sizeof(*axes));
                if (axes == NULL) {
                    axisCount = 0;
                    break;
                }
            }
            axes[axisCount++] = (CGSX11ScrollAxis) {
                .sourceID = devices[d].deviceid,
                .valuator = info->number,
                .horizontal = info->scroll_type == XIScrollTypeHorizontal,
                .increment = info->increment,
            };
        }
    }
    if (devices != NULL)
        XIFreeDeviceInfo(devices);
    free(_scrollAxes);
    _scrollAxes = axes;
    _scrollAxisCount = axisCount;
    int tablets = [_tablet deviceCount];
    [_tablet queryDevices];
    [self updateRawSelection];
    // The events the raw selection and the property selection ask for depend on the tablets there are.
    if (_rawSelected || tablets != [_tablet deviceCount])
        [self selectInputExtensionEvents];
}

- (CGSX11Tablet *) tablet {
    return _tablet;
}

- (void) setScrollAxes: (const CGSX11ScrollAxis *) axes count: (int) count {
    CGSX11ScrollAxis *copy = count > 0 ? malloc(count * sizeof(*copy)) : NULL;
    if (copy != NULL)
        memcpy(copy, axes, count * sizeof(*copy));
    free(_scrollAxes);
    _scrollAxes = copy;
    _scrollAxisCount = copy != NULL ? count : 0;
}

- (void) setPointerInProcessWindow: (BOOL) inside {
    if (_pointerInside == inside)
        return;
    _pointerInside = inside;
    if (!inside)
        [_tablet proximityOut];
    [self updateRawSelection];
}

- (void) updateRawSelection {
    if (_xiOpcode == 0)
        return;
    BOOL wanted = _pointerInside && (_scrollAxisCount > 0 || [_tablet deviceCount] > 0);
    if (wanted == _rawSelected)
        return;
    _rawSelected = wanted;
    [self selectInputExtensionEvents];
}

- (BOOL) inputExtensionEvent: (XEvent *) event {
    Display *display = _connection->_display;
    if (_xiOpcode == 0 || event->type != GenericEvent || event->xcookie.extension != _xiOpcode)
        return NO;
    if (!XGetEventData(display, &event->xcookie))
        return YES;
    switch (event->xcookie.evtype) {
    case XI_RawMotion:
        [self rawMotionEvent: (XIRawEvent *) event->xcookie.data];
        [_tablet rawEvent: (XIRawEvent *) event->xcookie.data];
        break;
    case XI_RawButtonPress:
    case XI_RawButtonRelease:
        [_tablet rawEvent: (XIRawEvent *) event->xcookie.data];
        break;
    case XI_PropertyEvent:
        [_tablet propertyChangedOfDevice: ((XIPropertyEvent *) event->xcookie.data)->deviceid];
        break;
    case XI_HierarchyChanged:
    case XI_DeviceChanged:
        [self queryScrollAxes];
        break;
    case XI_TouchBegin:
    case XI_TouchUpdate:
    case XI_TouchEnd: {
        XIDeviceEvent *touch = event->xcookie.data;
        [self touchEventType: event->xcookie.evtype
                      device: touch->deviceid
                      detail: touch->detail
                      window: touch->event
                           x: touch->event_x
                           y: touch->event_y
                       rootX: touch->root_x
                       rootY: touch->root_y];
        break;
    }
#ifdef X11_XI_GESTURES
    case XI_GesturePinchBegin:
    case XI_GesturePinchUpdate:
    case XI_GesturePinchEnd: {
        XIGesturePinchEvent *gesture = event->xcookie.data;
        [self pinchEventType: event->xcookie.evtype
                      window: gesture->event
                           x: gesture->event_x
                           y: gesture->event_y
                       rootX: gesture->root_x
                       rootY: gesture->root_y
                       scale: gesture->scale
                  deltaAngle: gesture->delta_angle
                   cancelled: (gesture->flags & XIGesturePinchEventCancelled) != 0];
        break;
    }
#endif
    }
    XFreeEventData(display, &event->xcookie);
    return YES;
}

@end
