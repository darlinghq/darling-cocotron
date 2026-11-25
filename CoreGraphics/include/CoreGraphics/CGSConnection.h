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
	// The displays the reconfiguration callbacks were last told about (nil until the displays
	// have been read once). Guarded by @synchronized(self).
	NSArray<CGSScreen*>* _reportedScreens;
	// Non-zero while this process changes a mode itself, which it reports itself.
	_Atomic int _suppressLayoutReports;
}
-(instancetype) initWithConnectionID:(CGSConnectionID)connId;
-(void) dealloc;
-(CGSWindow*) windowForId:(CGSWindowID)winId;
-(CGSWindow*) newWindow:(CGSRegionRef)region;

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
// Reads what the window system has sent and handles it: this is what the run loop calls when the
// connection's socket is readable. The default implementation does nothing.
-(void) processPendingEvents;
// The windows of this process were asked (by another process) to be activated, and the window
// system has no request for it: the observer is told. Backends call it on the main thread.
-(void) activationRequested;
@end

#endif

