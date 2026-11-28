/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

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
#ifndef CGSCONNECTION_H
#define CGSCONNECTION_H
#import <Foundation/NSObject.h>
#import <Foundation/NSDictionary.h>
#include <CoreGraphics/CGSServerSPI.h>
#include <CoreGraphics/CGEventTypes.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdatomic.h>

@class CGSWindow;
@class CGSCursor;
@class CGSScreen;
@class CGSKeyboardLayout;

@interface CGSConnection : NSObject {
	CGSConnectionID _connectionId;
	_Atomic CGSWindowID _nextWindowId;
	NSMutableDictionary<NSNumber*, CGSWindow*>* _windows;
	_Atomic int _hotKeyOperatingMode;

@protected
	// The displays as -buildScreens described them, until the layout changes. Guarded by
	// @synchronized(self).
	NSArray<CGSScreen*>* _screens;
	// The pointer's bookkeeping shared by the backends (guarded by @synchronized(self)): the hide count, whether the
	// mouse is connected to the cursor, the motion not yet taken by CGGetLastMouseDelta() and when the
	// suppression of the local mouse motion after a warp ends (CFAbsoluteTime, 0 for none).
	int _pointerHideCount;
	BOOL _pointerDisassociated;
	double _pointerDeltaX, _pointerDeltaY;
	double _pointerSuppressUntil;
	BOOL _pointerHiddenUntilMouseMoves;
	// The cursor the process selected for its windows (nil: the default one). Guarded by @synchronized(self).
	CGSCursor* _cursor;
	// The displays the reconfiguration callbacks were last told about (nil until the displays
	// have been read once). Guarded by @synchronized(self).
	NSArray<CGSScreen*>* _reportedScreens;
	// Non-zero while this process changes a mode itself, which it reports itself.
	_Atomic int _suppressLayoutReports;
	// Whether the desktop shows application menus, as the framework above said (see -setGlobalMenuAvailable:). Guarded by
	// @synchronized(self).
	BOOL _globalMenuAvailable;
}
-(instancetype) initWithConnectionID:(CGSConnectionID)connId;
-(void) dealloc;
-(CGSWindow*) windowForId:(CGSWindowID)winId;
// A snapshot of the connection's windows (the caller releases it)
-(NSArray<CGSWindow*>*) copyAllWindows;
-(CGSWindow*) newWindow:(CGSRegionRef)region;
// A new window id: a positive number that fits 32 bits and that no window of any process of the system has, like the
// ids the window server hands out (windows of different processes are told apart by their ids).
-(CGSWindowID) _allocateWindowID;
// A toplevel window for the application's UI layer (see CGSWindow.h), or nil when the window system cannot make
// one, which is the default. The window's id is the number CGWindow gives the UI layer's platform window.
-(CGSWindow*) newToplevelWindowWithAttributes:(const CGSToplevelAttributes*)attributes;
-(BOOL) supportsTranslucentToplevels;
// The ids of the shown toplevel windows, front to back (see _CGSOrderedToplevelWindowIDs()). The default knows of none.
-(NSArray<NSNumber*>*) orderedToplevelWindowIDs;

// Activates the windows of another process directly through the display server (see
// _CGSActivateProcess() for the options). Returns kCGErrorSuccess when a request was sent and
// kCGErrorNoneAvailable when the process has no window that can be activated this way. The
// default implementation does nothing and returns kCGErrorNotImplemented: the display server
// offers no way to activate another process' windows.
+(CGError) activateWindowsOfProcess:(pid_t)pid options:(uint32_t)options;
// The Darling process that owns the window with the input focus, as far as the display server
// tells. Returns kCGErrorSuccess and sets *pid, kCGErrorNoneAvailable when no Darling process
// has the focus, and kCGErrorNotImplemented (the default) when the display server does not say
// who has it, as on Wayland.
+(CGError) copyFrontProcessID:(pid_t*)pid;
-(CGError) destroyWindow:(CGSWindowID)winId;

// The windows of Darling processes, front to back, each described with the
// kCGWindow* keys of CGWindowListCopyWindowInfo(). Only the caller's own
// windows carry kCGWindowName. The default implementation knows no windows.
-(NSArray<NSDictionary*>*) copyWindowDescriptions;

// Mouse location in CG coordinates, i.e. relative to the upper left corner
-(CGPoint) mouseLocation;

// Hardware state of a key (a virtual key code) and of a mouse button. The
// default implementation reports them as up.
-(BOOL) isKeyDown:(CGKeyCode)keyCode;
-(BOOL) isMouseButtonDown:(CGMouseButton)button;

// Global hot keys, behind CGSSetHotKeyWithExclusion() and the rest of that family. A hot
// key is a virtual key code with modifier flags (the kCGEventFlagMask{Shift,Control,
// Alternate,Command} bits; the others are ignored), identified by a uid the caller chooses,
// whose presses and releases are reported wherever the keyboard focus is: each calls
// -postHotKeyEventForUID:pressed:flags:location:time: on the main run loop, which delivers it as a
// system-defined event (see CGSSetHotKeyWithExclusion in CoreGraphicsPrivate.h). Autorepeat
// produces no extra presses. A uid set again replaces the old hot key. A hot key that
// cannot be set up (another client holds the combination, no such key on this system) is not
// stored: -getHotKeyWithUID:... then returns NO. A hot key reports only while it is enabled and
// the global operating mode is 0. The default implementations store nothing.
-(void) setHotKeyWithUID:(int)uid keyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags exclusion:(int)exclusion;
-(BOOL) getHotKeyWithUID:(int)uid keyCode:(CGKeyCode*)outKeyCode flags:(CGEventFlags*)outFlags;
-(void) removeHotKeyWithUID:(int)uid;
-(BOOL) isHotKeyEnabledWithUID:(int)uid;
-(void) setHotKeyWithUID:(int)uid enabled:(BOOL)enabled;
// 0: hot keys are reported, 1: none is, 2: none is (the hot keys of universal access are
// the exception on macOS, and this system has none). Other values are illegal arguments.
-(CGError) getGlobalHotKeyOperatingMode:(int*)outMode;
-(CGError) setGlobalHotKeyOperatingMode:(int)mode;
// For backends: the operating mode has changed
-(void) hotKeyOperatingModeChanged;
// For backends: a hot key was pressed or released. flags, location (CG global coordinates) and
// time (nanoseconds since startup) are those of the key event (the time is when it was seen).
-(void) postHotKeyEventForUID:(int)uid pressed:(BOOL)pressed flags:(CGEventFlags)flags location:(CGPoint)location time:(uint64_t)time;

// The modes of a display, and the one it is in, are in the display's CGSScreen (-createScreens).
// Calls -setMode:forScreen: and, when it succeeded, makes the new layout the one that was reported:
// the caller reports the change itself (CGDisplaySwitchToMode() does), so what the window system
// sends about it is not a further change. Backends implement -setMode:forScreen:.
-(BOOL) changeMode:(NSDictionary *)mode forScreen:(int)screenIndex;
// Changes the mode of display screenIndex + 1 (the CGDirectDisplayID minus one) to one of the
// modes in its CGSScreen, matched by PixelWidth, PixelHeight and RefreshRate. Returns whether the
// window system applied it; the new layout is then visible to -createScreens. A window system
// that leaves the mode to the user's session answers NO. The default implementation answers NO.
-(BOOL) setMode:(NSDictionary *)mode forScreen:(int)screenIndex;

// The active displays, the main display first, as the window system describes them now; nil when
// it reports none. Cached (it is read for every CoreGraphics call about displays) until the
// layout changes, and every call returns the same objects until then. The caller releases the
// array. Backends implement -buildScreens, not this.
-(NSArray<CGSScreen*>*) createScreens;
// For backends: describes the displays afresh, each with its displayID, bounds, backingScale, modes
// and currentMode (and the edid and name when the window system tells). Called with the lock held.
-(NSArray<CGSScreen*>*) buildScreens;
// Drops the cached displays without telling anyone. Backends that cache more of the layout
// override it and call super.
-(void) invalidateScreens;
// For backends: the window system reported that the layout or a mode changed. Drops the cache and
// reports what differs from the previously reported layout to the callbacks registered with
// CGDisplayRegisterReconfigurationCallback(), on the calling thread, which is the main thread
// for events the backend reads.
-(void) displayLayoutChanged;
// Makes the current layout the one that was reported, for a change CoreGraphics itself reported.
-(void) acceptDisplayLayout;

// Moves the pointer to a point in CoreGraphics' global space (inside the desktop). The default
// implementation does nothing and returns kCGErrorCannotComplete.
-(CGError) warpPointerToPoint:(CGPoint)point;

// The pointer state of the process (CGDisplayHideCursor(), CGAssociateMouseAndMouseCursorPosition(),
// CGGetLastMouseDelta() and the warp above). A connection that keeps it answers YES here and implements
// the methods below; with NO the functions go to the controller a framework registered (see
// CGSPointerController.h). The methods can be called from any thread.
-(BOOL) managesPointer;
// Each call hides the cursor once more, -unhideCursor undoes one (nothing hidden: nothing happens),
// -forceShowCursor forgets every pending hide.
-(void) hideCursor;
-(void) unhideCursor;
-(void) forceShowCursor;
-(BOOL) cursorIsVisible;
// The cursor the process shows over its windows (CGSCursorSetCurrent(); nil is the default one). The backend that
// keeps the pointer gives it to the window system in -cursorChanged, which is called on the thread that set it
// (the default does nothing). While the cursor is hidden nothing of it is shown, and it is the one shown again.
-(void) setCursor:(CGSCursor*)cursor;
-(CGSCursor*) cursor;
-(void) cursorChanged;
// NO disconnects the mouse from the cursor: the cursor stays where it is and the mouse only makes deltas.
-(void) setMouseAssociatedWithCursor:(BOOL)associated;
// The mouse motion since the previous call in whole points, and the way for a framework that makes mouse events
// of its own for the window system (a display overlay) to add the motion it saw.
-(void) takeMouseDeltaX:(int32_t*)dx y:(int32_t*)dy;
-(void) accumulateMouseDeltaX:(double)dx y:(double)dy;
// The shared bookkeeping (hide count, deltas, suppression after a warp) is implemented here, so that every
// backend that keeps the pointer behaves the same. A backend tells a warp with -noteMouseWarp, asks
// -localMouseMotionSuppressed for each local motion it decodes, and reacts to a change in the hooks below
// (called on the thread that changed the state, outside the lock).
-(void) cursorHiddenStateChanged:(BOOL)hidden;
-(void) mouseAssociationChanged:(BOOL)associated;
-(void) noteMouseWarp;
-(BOOL) localMouseMotionSuppressed;
-(BOOL) mouseAssociated;
// Whether the mouse is disassociated from the cursor with the cursor held (the frozen position in
// *frozenRoot, window system pixels), and whether the application wants that; for the framework above.
-(BOOL) relativeMouseState:(BOOL*)requested frozenRoot:(CGPoint*)frozenRoot;
// What the window system does for the application's menu (see _CGSNativeConnectionCarriesApplicationMenuAddress() and
// the ones that follow it). The defaults are for a window system that does neither.
-(BOOL) carriesApplicationMenuAddress;
-(BOOL) placesMenuBar;
-(BOOL) globalMenuAvailable;
-(void) setGlobalMenuAvailable:(BOOL) available;
// The windows the pointer could be confined to changed.
-(void) pointerWindowsChanged;
-(void) selectTouchInputOnNativeWindow:(unsigned long)window;
// +[NSCursor setHiddenUntilMouseMoves:]: the flag is idempotent and counts as one hide; the backend that
// answers YES to -cancelsHiddenUntilMouseMoves calls -pointerDidMove when the mouse moves, which clears it.
// A backend that does not leaves the flag to the framework above (the default, NO).
-(BOOL) cancelsHiddenUntilMouseMoves;
-(void) setCursorHiddenUntilMouseMoves:(BOOL)flag;
-(void) pointerDidMove;
// The pointer is locked to a surface (Wayland: the lock of the disassociated mouse is active), and the surface to
// lock may be another one now. The defaults say no and do nothing.
-(BOOL) pointerLocked;
-(void) pointerLockTargetMayHaveChanged;
// Whether the native window (the handle the connection's events name a window by: an X window, a wl_surface)
// is a display overlay (see -[CGSWindow becomeDisplayOverlay:]), whose input belongs to no window of the
// application. The default is NO.
-(BOOL) isDisplayOverlayNativeWindow:(void*)nativeWindow;
// Whether this process holds a power assertion that keeps the display from sleeping on idle
// (kIOPMAssertPreventUserIdleDisplaySleep, or the older kIOPMAssertionTypeNoDisplaySleep). Backends
// whose window system has to be told learn it from IOKit (IOPMCopyAssertionsByProcess). The default is NO.
-(BOOL) displaySleepPrevented;
// The WaylandColorManager (see WaylandColor.h) of a Wayland connection, which the framework above
// shares for the color management of its windows instead of binding the compositor's globals again.
// The default is nil.
-(id) waylandColorManager;
// The WaylandRenderManager (see WaylandRender.h) of a Wayland connection: the dma-buf, explicit
// synchronization and fifo client. The framework above shares it, because a wl_surface takes only one
// syncobj surface and one fifo object. The default is nil.
-(id) waylandRenderManager;
// Whether a display of this connection reports luminance above its reference white. The default is NO.
-(BOOL) extendedDynamicRangeAvailable;

// Implementations should also emit kTISNotifySelectedKeyboardInputSourceChanged via NSDistributedNotificationCenter
// if layout changes.
// Implementations should also cache this and return the same pointer if nothing changed.
-(CGSKeyboardLayout*) createKeyboardLayout;

+(BOOL) isAvailable;

-(void) _windowInvalidated: (CGSWindowID) winId;

// For CGL
-(void*) nativeDisplay;

// The connection to the window system is shared with the framework that builds windows on its native
// objects (see CGSNativeConnection.h). The kind of this backend's connection; the default is none.
+(int) nativeConnectionKind;
// The framework's observer, if any. A connection with an observer must outlive it: the observer
// uses its native display.
+(id) nativeObserver;
+(void) setNativeObserver:(id)observer;
// Keyboard state for the frameworks that read the window system's input from the event stream: the
// object with the keyboard focus, the modifier flags with the device bits, the end of the focus
// on a destroyed object and the keyboard layout group in effect. The defaults know nothing.
-(void*) keyboardFocus;
-(uint64_t) modifierFlags;
// The modifier flags the window system says are held now: the state of the session's keyboard, which may differ
// from what the decoder has seen of the process' own events (no window of the process had the focus). The
// default is the decoder's.
-(uint64_t) hardwareModifierFlags;
-(void) nativeObjectDestroyed:(void*)object;
-(void) flushPendingKeyboardEvents;
// The pointer: the seat's wl_pointer (Wayland), and where the pointer is in its surface, set by the
// framework that moved it without the compositor saying so. The defaults know nothing.
-(void*) nativePointer;
-(void) setPointerSurfacePointX:(double)x y:(double)y;
-(int) keyboardLayoutGroup;
-(NSString*) keyboardLayoutName;
// Reads what the window system has sent and handles it: this is what the run loop calls when the
// connection's socket is readable. The default implementation does nothing.
-(void) processPendingEvents;
// The windows of this process were asked (by another process) to be activated, and the window
// system has no request for it: the observer is told. Backends call it on the main thread.
-(void) activationRequested;
@end

// The window system's input focus moved to a window of this process (ours), or to another client; the
// backends report it from their native focus events (-[CGSConnectionX11 _activeWindowChanged], the Wayland
// keyboard enter and leave). The front process follows it: see CGS.m.
extern void _CGSNativeFocusReport(BOOL ours);

#endif

