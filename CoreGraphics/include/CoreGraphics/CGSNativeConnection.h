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
#ifndef CGSNATIVECONNECTION_H
#define CGSNATIVECONNECTION_H
#import <Foundation/NSObject.h>
#include <stdbool.h>

// A process has one connection to the window system (X11 or Wayland), and CoreGraphics owns it:
// it opens it, reads its socket on the main run loop and keeps the state that belongs to the
// connection itself (displays, keyboard layout, hot keys, activation requests). The framework
// that builds windows on top of the native objects (AppKit's backends) uses the same
// connection instead of opening a second one, and is told what CoreGraphics does not take
// for itself through the observer registered here.

typedef enum {
	CGSNativeConnectionKindNone = 0,
	CGSNativeConnectionKindX11 = 1,
	CGSNativeConnectionKindWayland = 2,
} CGSNativeConnectionKind;

// All the methods are called on the main thread, from the run loop pass that read the events (or
// from -_CGSProcessNativeEvents()).
@protocol CGSNativeConnectionObserver <NSObject>
@optional
// X11: an event read from the connection that CoreGraphics did not handle itself (an XEvent*). The
// observer calls XFilterEvent() as Xlib requires.
- (void) nativeConnectionEvent: (void *) event;
// The pending events have been read and dispatched (on Wayland the listeners of every object on the
// connection have run). The observer sends what it queued meanwhile.
- (void) nativeConnectionDidProcessEvents;
// The displays changed. CoreGraphics has read the new layout and reported it to the display
// reconfiguration callbacks.
- (void) nativeConnectionDisplayLayoutChanged;
// Another process asked for the windows of this one to be activated and the window system offers
// no request for that, so only the process can do it (Wayland). Called on the main thread.
- (void) nativeConnectionActivationRequested;
// The keyboard focus moved to a window system object of the process (the wl_surface on Wayland), or
// left it (NULL). The pointer is compared by value only.
- (void) nativeConnectionKeyboardFocusChanged: (void *) surface;
// A key was pressed with the window system's serial for the input (Wayland), before the key event is posted.
- (void) nativeConnectionKeyPressedWithSerial: (uint32_t) serial;
// Called before CoreGraphics posts the events a keyboard event of the window system makes, so that
// the observer can send what it holds back from earlier input first (the order of the events).
- (void) nativeConnectionWillPostKeyboardEvent;
// X11: the text a key press (an XKeyEvent*) makes after the input method of the window it is for has
// composed it. The input contexts belong to the framework that owns the windows (the input method
// stays in the application); nil when the observer has no input context for the window, which makes
// CoreGraphics look the key up in the keymap. The keysym is set when the lookup gives one (NoSymbol,
// 0, otherwise).
- (NSString *) nativeConnectionComposedTextForKeyEvent: (void *) event keySym: (unsigned long *) keySym;
// X11: whether the observer makes the events of a pointer event (an XEvent*: button, motion) itself, so
// that CoreGraphics posts nothing for it. The observer holds the pointer for itself (relative mouse
// mode) or the window the event is for is one CoreGraphics does not decode input for (a display overlay).
// Asked for every button and motion event, before it is decoded.
- (BOOL) nativeConnectionObserverHandlesPointerEvent: (void *) event;
// X11: CoreGraphics has decoded a pointer event (an XEvent*) into the CGEvent and is about to post it.
// The observer may add what only it knows (kCGSMouseEventWindowKeyState). Returns whether the process'
// event stream gets the event: NO when the window it is for does not take it (a mouse moved event for a
// window that did not ask for them); the event taps see it either way.
- (BOOL) nativeConnectionWillPostPointerEvent: (struct __CGEvent *) cgEvent forXEvent: (void *) event;
@end

// The kind of the process' connection to the window system, opening it if needed.
extern CGSNativeConnectionKind _CGSNativeConnectionKind(void);
// The native display of that connection (Display* on X11, wl_display* on Wayland), NULL without one.
extern void *_CGSNativeConnectionDisplay(void);
// Registers the observer (not retained; pass nil when it goes away). One observer per process.
extern void _CGSSetNativeConnectionObserver(id<CGSNativeConnectionObserver> observer);
// Reads and dispatches what the window system has sent, now, from the calling (main) thread.
extern void _CGSProcessNativeConnectionEvents(void);

// The window system's object with the keyboard focus (the wl_surface on Wayland), NULL when none of the
// process' objects has it or the window system does not say (X11).
extern void *_CGSNativeConnectionKeyboardFocus(void);
// The modifier flags in effect, with the device-dependent bits of the keys held down (CGEventFlags bits).
extern uint64_t _CGSNativeConnectionModifierFlags(void);
// A window system object the process created has been destroyed: the keyboard focus on it ends.
extern void _CGSNativeConnectionObjectDestroyed(void *object);
// Posts what the keyboard decoder holds back until the compositor confirms it (a modifier key that is
// not yet known to have changed the flags), so that a later event of another device follows it.
extern void _CGSNativeConnectionFlushPendingKeyboardEvents(void);
// The index and name of the keyboard layout group in effect. -1 and NULL when there is none.
extern int _CGSNativeConnectionKeyboardLayoutGroup(CFStringRef *name);

#endif
