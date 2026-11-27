/* CoreGraphics Wayland backend: the keyboard.

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

// The process' one wl_keyboard: it decodes what the compositor sends into CGEvents (key down, key up
// and flags changed, with the modifier flags, the characters and the key repeat) and posts them to the
// process' event stream, where the event taps see them before the frameworks above CoreGraphics do.
// The keymap and the modifier state are CGSWaylandKeymap's; the focus is a wl_surface, which the
// framework that created the window maps to its window.

#ifndef CGSWAYLANDKEYBOARD_H
#define CGSWAYLANDKEYBOARD_H

#import <Foundation/NSObject.h>
#import <CoreFoundation/CFRunLoop.h>
#include <stdint.h>
#include <wayland-util.h>

@class CGSConnectionWayland;
@class CGSWaylandKeymap;
@class NSMutableDictionary;
@class NSMutableSet;
struct wl_proxy;

@interface CGSWaylandKeyboard : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionWayland *_connection; // not retained: the connection owns the keyboard
    CGSWaylandKeymap *_keymap;         // not retained either
    struct wl_proxy *_focus;           // the surface with the keyboard focus, compared by value only
    NSMutableDictionary *_heldKeyIdentities;
    NSMutableDictionary *_heldHotKeys; // keycode -> uids of the hot keys its press selected
    NSMutableSet *_composingKeys;      // keycodes held down whose press went into a dead key or compose sequence
    struct wl_proxy *_modifierSync;
    int _modifierKeycode;
    BOOL _hasModifierKeycode, _syncModifierFlags, _classifyHeldKeys;
    int32_t _repeatRate, _repeatDelay;
    uint32_t _repeatKeycode;
    CFRunLoopTimerRef _repeatTimer;
    void *_source; // CGEventSourceRef of the hardware state
    // The high-resolution time of the next input event, in CGEvent's clock (nanoseconds since boot).
    uint64_t _pendingTimestamp;
    BOOL _hasPendingTimestamp;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection keymap: (CGSWaylandKeymap *) keymap;

// The timestamp of the next input event, from input-timestamps-unstable-v1.
- (void) setPendingTimestamp: (uint64_t) timestamp;
// An event of the wl_keyboard.
- (void) keyboardEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
// The wl_callback of the pending modifier key is done.
- (void) modifierSyncDone: (struct wl_proxy *) proxy;
// A new keymap came into force.
- (void) keymapInstalled;
// The seat has no keyboard any more, or the connection closes.
- (void) flushPendingModifier;
- (void) stop;
// The window system object is gone: the focus on it ends without a leave event.
- (void) surfaceDestroyed: (struct wl_proxy *) surface;

@property (readonly) struct wl_proxy *focusSurface;
// The modifier flags in effect, with the device-dependent bits of the keys held down.
- (uint64_t) modifierFlags;

@end

#endif
