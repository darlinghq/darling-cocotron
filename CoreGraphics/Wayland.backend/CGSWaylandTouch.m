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

#import "CGSWaylandTouch.h"
#import "CGSConnectionWayland.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSValue.h>
#include <math.h>

@implementation CGSWaylandTouch

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection {
    self = [super init];
    if (self == nil)
        return nil;
    _connection = connection;
    _fingers = [NSMutableDictionary new];
    // A touch screen is hardware, as the pointer is.
    _source = (void *) CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    return self;
}

- (void) dealloc {
    [self stop];
    [_fingers release];
    if (_source != NULL)
        CFRelease((CFTypeRef) _source);
    [super dealloc];
}

- (id<CGSNativeConnectionObserver>) observer {
    return [CGSConnection nativeObserver];
}

#pragma mark - The object

- (void) seatCapabilities: (uint32_t) capabilities seat: (struct wl_proxy *) seat {
    if ((capabilities & WP_SEAT_CAPABILITY_TOUCH) && _touch == NULL && seat != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        _touch = [_connection createObject: seat
                                    opcode: WP_SEAT_GET_TOUCH
                                 interface: &wl_touch_interface
                                 arguments: args
                                      kind: CGSWaylandObjectTouch
                                    object: self];
    } else if (!(capabilities & WP_SEAT_CAPABILITY_TOUCH) && _touch != NULL) {
        [self stop];
    }
}

- (void) stop {
    // The compositor takes the touch screen away: every finger is cancelled.
    [self cancelAll];
    if (_touch == NULL)
        return;
    // wl_touch.release exists from version 3.
    if (WL.wl_proxy_get_version(_touch) >= 3) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(_touch, WP_TOUCH_RELEASE, NULL, WL_MARSHAL_FLAG_DESTROY, args);
    } else {
        WL.wl_proxy_destroy(_touch);
    }
    _touch = NULL;
}

- (void) surfaceDestroyed: (struct wl_proxy *) surface {
    NSValue *value = [NSValue valueWithPointer: surface];

    if (surface == NULL)
        return;
    // The window is gone with its fingers: there is nobody to tell.
    for (NSNumber *finger in [_fingers allKeysForObject: value])
        [_fingers removeObjectForKey: finger];
}

#pragma mark - Posting

// Where a point of a surface is in global coordinates: the framework that owns the surface says, and a window of this
// connection knows its own position.
- (CGPoint) globalLocationOfSurface: (struct wl_proxy *) surface point: (CGPoint) point {
    id<CGSNativeConnectionObserver> observer = [self observer];
    CGPoint global;

    if ([observer respondsToSelector: @selector(nativeConnectionGlobalLocation:ofSurface:point:)] &&
        [observer nativeConnectionGlobalLocation: &global ofSurface: surface point: point])
        return global;
    if ([_connection globalLocation: &global ofSurface: surface point: point])
        return global;
    return point;
}

// One change of a finger: the finger's number (the compositor's), the phase (NSTouchPhase bits), the surface and the
// point in it in points; NAN coordinates for a finger without a position (the end of a finger, a cancel): it is where
// its previous event left it.
- (void) postPhase: (int64_t) phase
        identifier: (int32_t) identifier
           surface: (struct wl_proxy *) surface
             point: (CGPoint) point
{
    BOOL known = !isnan(point.x) && !isnan(point.y);
    CGEventRef event = CGEventCreate((CGEventSourceRef) _source);

    if (event == NULL)
        return;
    // What the other devices held back (a modifier key, a scroll frame) came before this finger moved.
    [_connection flushPendingKeyboardEvents];
    [_connection flushPendingPointerEvents];
    CGEventSetType(event, (CGEventType) kCGSEventTypeGesture);
    CGEventSetFlags(event, (CGEventFlags) [_connection modifierFlags]);
    CGEventSetIntegerValueField(event, kCGSTouchIdentifier, identifier);
    CGEventSetIntegerValueField(event, kCGSTouchPhase, phase);
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) (intptr_t) surface);
    if (known) {
        CGPoint global = [self globalLocationOfSurface: surface point: point];

        CGEventSetLocation(event, global);
        CGEventSetIntegerValueField(event, kCGSEventNativeLocationX, llround(point.x * 1024));
        CGEventSetIntegerValueField(event, kCGSEventNativeLocationY, llround(point.y * 1024));
        CGEventSetIntegerValueField(event, kCGSEventPostedLocationX, llround(global.x * 1024));
        CGEventSetIntegerValueField(event, kCGSEventPostedLocationY, llround(global.y * 1024));
    } else {
        CGEventSetIntegerValueField(event, kCGSTouchLocationUnknown, 1);
    }
    _CGSEventStreamPost(event);
    CFRelease(event);
}

- (void) cancelAll {
    NSDictionary *fingers = [[_fingers copy] autorelease];

    [_fingers removeAllObjects];
    for (NSNumber *finger in fingers) {
        struct wl_proxy *surface = [[fingers objectForKey: finger] pointerValue];

        [self postPhase: kCGSTouchPhaseCancelled identifier: [finger intValue] surface: surface
                  point: CGPointMake(NAN, NAN)];
    }
}

- (void) touchEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    switch (opcode) {
    case WP_TOUCH_EV_DOWN: {
        struct wl_proxy *surface = (struct wl_proxy *) args[2].o;

        if (surface == NULL)
            break;
        id<CGSNativeConnectionObserver> observer = [self observer];

        if ([observer respondsToSelector: @selector(nativeConnectionTouchDownWithSerial:)])
            [observer nativeConnectionTouchDownWithSerial: args[0].u];
        [_fingers setObject: [NSValue valueWithPointer: surface] forKey: @(args[3].i)];
        [self postPhase: kCGSTouchPhaseBegan identifier: args[3].i surface: surface
                  point: CGPointMake(wl_fixed_to_double(args[4].f), wl_fixed_to_double(args[5].f))];
        break;
    }
    case WP_TOUCH_EV_MOTION: {
        struct wl_proxy *surface = [[_fingers objectForKey: @(args[1].i)] pointerValue];

        if (surface == NULL)
            break;
        [self postPhase: kCGSTouchPhaseMoved identifier: args[1].i surface: surface
                  point: CGPointMake(wl_fixed_to_double(args[2].f), wl_fixed_to_double(args[3].f))];
        break;
    }
    case WP_TOUCH_EV_UP: {
        struct wl_proxy *surface = [[_fingers objectForKey: @(args[2].i)] pointerValue];

        [_fingers removeObjectForKey: @(args[2].i)];
        if (surface == NULL)
            break;
        // Up carries no position: the finger leaves where it last was.
        [self postPhase: kCGSTouchPhaseEnded identifier: args[2].i surface: surface point: CGPointMake(NAN, NAN)];
        break;
    }
    case WP_TOUCH_EV_CANCEL:
        [self cancelAll];
        break;
    }
}

@end
