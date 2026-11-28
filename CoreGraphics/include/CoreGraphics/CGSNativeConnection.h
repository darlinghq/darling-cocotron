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
#include <stdint.h>
#include <CoreGraphics/CGGeometry.h>

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
// input method has seen it already (XFilterEvent(), as Xlib requires).
- (void) nativeConnectionEvent: (void *) event;
// The pending events have been read and dispatched (on Wayland the listeners of every object on the
// connection have run). The observer sends what it queued meanwhile.
- (void) nativeConnectionDidProcessEvents;
// The displays changed. CoreGraphics has read the new layout and reported it to the display
// reconfiguration callbacks.
- (void) nativeConnectionDisplayLayoutChanged;
// An output's color description changed. CoreGraphics has dropped the screens so the next
// -createScreens rebuilds them with the new description; the observer posts the color change
// notification.
- (void) nativeConnectionDisplayColorSpaceChanged;
// Another process asked for the windows of this one to be activated and the window system offers
// no request for that, so only the process can do it (Wayland). Called on the main thread.
- (void) nativeConnectionActivationRequested;
// The window system's input focus moved to a window of another client (not to a window of this process, and
// not to none). Called on the main thread by a backend whose window system tells (X11: the active window).
- (void) nativeConnectionFocusMovedToAnotherClient;
// The compositor's color management or color representation global arrived after the windows were made.
- (void) nativeConnectionColorManagerAvailable;
// The compositor's dma-buf, explicit synchronization or fifo global arrived after the windows were made.
- (void) nativeConnectionRenderManagerAvailable;
// The compositor's preferred image description for a surface changed. The pointer identifies the
// wp_color_management_surface_feedback_v1 proxy CoreGraphics made for that surface; the framework
// above reads the new description with WaylandColorManager's -preferredInfoForFeedback:.
- (void) nativeConnectionSurfaceColorPreferenceChanged: (void *) feedback;
// The process took or dropped its last power assertion that keeps the display awake.
- (void) nativeConnectionDisplaySleepPreventionChanged;
// The keyboard focus moved to a window system object of the process (the wl_surface on Wayland), or
// left it (NULL). The pointer is compared by value only.
- (void) nativeConnectionKeyboardFocusChanged: (void *) surface;
// A key was pressed with the window system's serial for the input (Wayland), before the key event is posted.
- (void) nativeConnectionKeyPressedWithSerial: (uint32_t) serial;
// Called before CoreGraphics posts the events a keyboard event of the window system makes, so that
// the observer can send what it holds back from earlier input first (the order of the events).
- (void) nativeConnectionWillPostKeyboardEvent;
// X11: CoreGraphics has decoded a pointer event (an XEvent*) into the CGEvent and is about to post it.
// The observer may add what only it knows (kCGSMouseEventWindowKeyState). Returns whether the process'
// event stream gets the event: NO when the window it is for does not take it (a mouse moved event for a
// window that did not ask for them); the event taps see it either way.
- (BOOL) nativeConnectionWillPostPointerEvent: (struct __CGEvent *) cgEvent forXEvent: (void *) event;

// The Wayland pointer (a wl_pointer of the process' one seat, which CoreGraphics binds and decodes into
// mouse, scroll and gesture CGEvents). Surfaces are wl_surface pointers, compared by value only.
// The pointer entered a surface of the process (serial: the compositor's, which a cursor request needs;
// x, y: surface-local points).
- (void) nativeConnectionPointerEntered: (void *) surface serial: (uint32_t) serial x: (double) x y: (double) y;
// The pointer left the surface it was in.
- (void) nativeConnectionPointerLeft;
// The pointer moved to x, y of the surface it is in (also while no surface of the process has it). Returns
// YES when the observer used the motion itself (the pointer is over a window decoration), so that
// CoreGraphics posts no event for it.
- (BOOL) nativeConnectionPointerMovedToX: (double) x y: (double) y;
// A pointer button (a Linux input event code) was pressed or released. Returns YES when the observer used
// the button itself (a window decoration), so that CoreGraphics posts no event for it.
- (BOOL) nativeConnectionPointerButton: (uint32_t) button pressed: (BOOL) pressed serial: (uint32_t) serial;
// CoreGraphics has decoded a pointer event (button, motion or scroll) and is about to post it, with the
// native window, the pointer location in it and, for a press, the serial (CGEvent fields of
// CoreGraphicsPrivate.h). The observer may add what only it knows (kCGSMouseEventWindowKeyState).
// Returns whether the process' event stream gets the event: NO when the window it is for does not take
// it (an unknown surface, a mouse moved event for a window that did not ask for them); the event
// taps see it either way.
- (BOOL) nativeConnectionWillPostWaylandPointerEvent: (struct __CGEvent *) cgEvent;
// The global location (top-left origin, points) of a point of one of the observer's surfaces; NO when
// the observer does not know the surface.
- (BOOL) nativeConnectionGlobalLocation: (CGPoint *) location ofSurface: (void *) surface point: (CGPoint) point;
// Wayland: the surface the pointer is locked to while the mouse is disconnected from the cursor (the surface of
// the window to lock: the one used last); NULL when the observer has none, and CoreGraphics takes the surface
// with the pointer or the keyboard focus.
- (void *) nativeConnectionSurfaceForPointerLock;
// Wayland: the point of a surface of the observer's that is at a global location (the inverse of
// -nativeConnectionGlobalLocation:ofSurface:point:, clamped to the surface's content); NO when the observer
// does not know the surface.
- (BOOL) nativeConnectionPoint: (CGPoint *) point ofSurface: (void *) surface forGlobalLocation: (CGPoint) location;
// Wayland: CGWarpMouseCursorPosition() moved the application's cursor within its surface to x, y (the
// compositor is asked to move the pointer there; the next events start from it).
- (void) nativeConnectionPointerWarpedToX: (double) x y: (double) y;
// Wayland: a finger went down on a surface of the process (the touch screen of the seat, which CoreGraphics decodes into
// touch CGEvents), with the compositor's serial of the touch down, which the requests that start a move or a grab need.
// Before the touch event is posted.
- (void) nativeConnectionTouchDownWithSerial: (uint32_t) serial;
// The seat gained or lost its pointer. The compositor objects that need it (cursor, locked pointer)
// are reached through _CGSNativeConnectionPointer().
- (void) nativeConnectionPointerAvailabilityChanged: (BOOL) available;
// X11: the window (an X window) the pointer is to be grabbed for when the mouse is disassociated from the
// cursor (CGAssociateMouseAndMouseCursorPosition(false)): the one the observer prefers (the key window). A
// display overlay comes first, whatever the observer says. 0 for none, which leaves the choice to CoreGraphics (the window of the connection with the focus).
- (unsigned long) nativeConnectionRelativeMouseWindow;
// X11: the pointer grab of the disassociated mouse was taken (active) on a window, with the frozen cursor in
// root pixels, or released. The observer forgets the pointer position it knew.
- (void) nativeConnectionRelativeMouseGrabChanged: (BOOL) active window: (unsigned long) window rootX: (int) x rootY: (int) y;
// X11: the pointer was grabbed for the window of a menu that is being tracked (active), or the grab ended (see
// -[CGSWindow setToplevelHoldsInputForMenu:]). Another grab of the observer's (the confinement of the pointer to a window)
// is replaced by it and has to be taken again when it ends.
- (void) nativeConnectionMenuGrabChanged: (BOOL) active;
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
// X11: whether the mouse is disassociated from the cursor and the pointer grab that implements it is held;
// then *frozenRoot is the frozen cursor in root pixels. *requested says whether the application wants it
// (the grab is held only while the focus is). Either may be NULL.
extern BOOL _CGSNativeConnectionRelativeMouseState(BOOL *requested, CGPoint *frozenRoot);
// The desktop's application menu. Whether the window system can carry the address of a window's application menu (a
// property of the window on X11, KDE's appmenu protocol on Wayland), for a desktop that shows application menus outside
// the application (see -[CGSWindow setToplevelApplicationMenuServiceName:objectPath:]).
extern BOOL _CGSNativeConnectionCarriesApplicationMenuAddress(void);
// Whether the window system places a menu bar window of the application along the top of the screen (X11: the window
// manager handles dock windows; Wayland: the compositor has a layer shell).
extern BOOL _CGSNativeConnectionPlacesMenuBar(void);
// Whether the session has a desktop that shows application menus, as the framework above found out (a registrar of
// application menus on the session bus: CoreGraphics has no bus connection of its own). NO until it says.
extern BOOL _CGSNativeConnectionGlobalMenuAvailable(void);
extern void _CGSNativeConnectionSetGlobalMenuAvailable(BOOL available);
// X11: the windows the pointer can be grabbed for changed (a display overlay appeared or went): a wanted
// grab that is not held is retried.
extern void _CGSNativeConnectionPointerWindowsChanged(void);
// X11: a window the process made asks for its touch screen events (and the touchpad pinch gestures, where the server has
// them), which CoreGraphics decodes into touch and gesture CGEvents (see CoreGraphicsPrivate.h). Called once the window
// exists and again when its other input selection changes; the window is an X window. A server without XInput 2.2 has no
// touches. Nothing on Wayland, where CoreGraphics reads the touch screen of the seat.
extern void _CGSNativeConnectionSelectTouchInput(unsigned long window);
// The index and name of the keyboard layout group in effect. -1 and NULL when there is none.
extern int _CGSNativeConnectionKeyboardLayoutGroup(CFStringRef *name);

// The seat's wl_pointer (a struct wl_proxy *) on Wayland, the process' only one: it is the argument of the
// requests that need it (cursor image, pointer constraints). NULL while the seat has no pointer and on X11.
extern void *_CGSNativeConnectionPointer(void);
// Where the pointer is in the surface that has it, when the framework above moved it without the compositor
// saying so (a warp while the pointer is locked). The next events start from there.
extern void _CGSNativeConnectionSetPointerSurfacePoint(double x, double y);


// +[NSCursor setHiddenUntilMouseMoves:] for a connection that keeps the flag; false when it does not, and
// nothing was done.
extern bool _CGSSetCursorHiddenUntilMouseMoves(bool flag);
// The pointer is locked to a surface (Wayland: the lock of the disassociated mouse is active).
extern bool _CGSNativeConnectionPointerLocked(void);
// The color manager of a Wayland connection (see WaylandColor.h), nil without one.
extern id _CGSNativeConnectionWaylandColorManager(void);
// The render-protocol manager of a Wayland connection (see WaylandRender.h), nil without one.
extern id _CGSNativeConnectionWaylandRenderManager(void);
// Whether any connected output reports luminance headroom above its reference white. False on a
// connection without color management; CAEDRMetadata.isAvailable asks this.
extern bool _CGSExtendedDynamicRangeAvailable(void);
// This process holds a power assertion that keeps the display awake; false without a backend that tracks it.
extern bool _CGSNativeConnectionDisplaySleepPrevented(void);
// The surface the lock should be made on may be another one (a window was mapped, unmapped or activated).
extern void _CGSNativeConnectionPointerLockTargetChanged(void);
// The native window an event names (kCGSEventNativeWindow) is a display overlay (_CGSCreateDisplayOverlayWindow):
// the cover of a display, whose events belong to no window of the application.
extern bool _CGSNativeConnectionIsDisplayOverlayWindow(void *nativeWindow);

#endif
