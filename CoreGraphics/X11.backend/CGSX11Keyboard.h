/* CoreGraphics X11 backend: the keyboard.

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

// The process' keyboard on X11: it decodes the core key events of the one connection into CGEvents (key
// down, key up and flags changed, with the modifier flags, the characters and the autorepeat) and posts
// them to the process' event stream, where the event taps see them before the frameworks above CoreGraphics
// do. It also keeps the modifier state: the pointer events carry the server's modifier state, and a
// difference from what the keys said is reported as a flags changed event that names no key.
//
// Core events are used rather than XInput2: an X input method (XIM) filters and composes the core key
// events (XFilterEvent, Xutf8LookupString), and the input context belongs to the framework that owns the
// windows. That framework is asked for the composed text through the connection's observer. When no
// input method of the application composes (Xlib's built-in one does, but loses the keys of a sequence
// that no entry of the Compose table continues), the keyboard composes dead keys and Compose sequences itself
// (CGSKeyCompose.h), as the Wayland backend does.

#ifndef CGSX11KEYBOARD_H
#define CGSX11KEYBOARD_H

#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <X11/Xlib.h>
#include <stdint.h>

@class CGSConnectionX11;
@class NSMutableSet;

@interface CGSX11Keyboard : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionX11 *_connection; // not retained: the connection owns the keyboard
    Display *_display;
    uint64_t _flags;               // the modifier flags of the keyboard as a whole (no device bits)
    // The modifier keys held down by X key code: the virtual key code of the key (-1: none) and the X mask
    // it drives, as they were when the key went down.
    short _heldKeyCode[256];
    unsigned char _heldMask[256];
    KeySym _lastKeySym;
    void *_source; // CGEventSourceRef of the hardware state
    // Dead keys and Compose sequences, when CoreGraphics composes them (no input method does); see -composesKeys.
    struct CGSKeyCompose *_compose;
    BOOL _composeLoaded;
    // The key codes held down whose press went into a sequence: their repeats and releases produce nothing.
    NSMutableSet *_composingKeys;
}

- (instancetype) initWithConnection: (CGSConnectionX11 *) connection;

// A KeyPress or KeyRelease of a window of the process. The input method sees it first (XFilterEvent).
- (void) keyEvent: (XEvent *) event;
// A pointer or crossing event carries the server's modifier state: a difference from the tracked state is
// reported. `root` is the pointer in root coordinates.
- (void) resyncWithState: (unsigned int) state window: (Window) window root: (CGPoint) root;
// The sequence in progress ends (the keymap changed, or the focus moved): the next key starts afresh.
- (void) resetComposition;
// A window of the process got the keyboard focus: keys went up and down meanwhile, so the keys that are
// held and the modifier state are read from the server.
- (void) focusGainedInWindow: (Window) window;

// The modifier flags in effect, with the device-dependent bits of the keys held down.
- (uint64_t) modifierFlags;
// The CGEventFlags the X server's modifier state (the core event state mask) stands for.
+ (uint64_t) flagsForState: (unsigned int) state;

@end

#endif
