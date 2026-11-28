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

#ifndef CGSCONNECTIONX11_H
#define CGSCONNECTIONX11_H
#import <CoreGraphics/CGSConnection.h>
#import <X11/Xlib.h>
#import <CoreFoundation/CFRunLoop.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <CoreFoundation/CFSocket.h>
#import "X11Monitors.h"
#import <CoreGraphics/CGSCursorPrivate.h>

@class CGSWindowX11;
@class CGSX11Keyboard;
@class CGSX11Pointer;
@class CGSX11Drag;
@class CGSX11InputMethod;

@interface CGSConnectionX11 : CGSConnection <CGSCursorNativeOwner> {
@public
	// The X11 display, which the CGS windows and surfaces of this connection draw on.
	Display *_display;

@protected
	// We use CFRunLoop directly, without going through any Foundation wrapper,
    // because Apple's Cocoa has none. Unlike Apple's Cocoa, we need to watch
    // over a Unix domain socket, not a Mach port.
    CFSocketRef _cfSocket;
    CFRunLoopSourceRef _source;
    CFRunLoopObserverRef _beforeWaitingObserver;

	// RandR reported a layout change that -processPendingEvents has not looked at yet.
	BOOL _layoutChanged;

	CGSKeyboardLayout* _keyboardLayout;
	int _keyboardLayoutGroup;

	int _xkbEventBase;
	int _xrrEventBase;

	// Registered global hot keys (X11HotKeyEntry), the combinations grabbed on the X server
	// (as NSNumbers) and the uids whose press was reported and release is still due.
	// Guarded by @synchronized(self).
	NSMutableArray* _hotKeys;
	NSMutableSet<NSNumber*>* _grabbedHotKeys;
	NSMutableSet<NSNumber*>* _pressedHotKeys;
	BOOL _detectableAutoRepeat;

	// The keyboard of the connection: its key events become CGEvents (see CGSX11Keyboard.h).
	CGSX11Keyboard* _keyboard;
	// The pointer of the connection: its button and motion events become CGEvents (see CGSX11Pointer.h).
	CGSX11Pointer* _pointer;
	// The connection's part in XDND (see CGSX11Drag.h), made when the first window gets a drag destination or
	// the first drag starts.
	CGSX11Drag* _dragSupport;
	// The connection's input method (see CGSX11InputMethod.h), made when the first window uses it.
	CGSX11InputMethod* _inputMethodSupport;

	// The windows of the menus that are shown (see -[CGSWindow setToplevelHoldsInputForMenu:]), oldest first (not retained
	// beyond the window's own call to -menuWindowHidden:).
	NSMutableArray* _openMenuWindows;

@private
	// The main monitor in root coordinates, cached for -mouseLocation. Guarded by
	// @synchronized(self); the cache is dropped when XRandR reports a
	// reconfiguration, like _screens.
	X11Frame _primaryRoot;
	// Device pixels per point, read together with _primaryRoot.
	CGFloat _primaryScale;
	BOOL _primaryRootValid;
	// The cursor the connection's windows show while the process' cursor is hidden (None before the first hide).
	Cursor _blankCursor;

	// Whether another client's window covers a toplevel window (see X11Occlusion.h). The window manager
	// publishes the focused window and the stacking order on the root window, and the focused foreign window is
	// watched for changes of its size, its fullscreen state and its unmapping; the windows are judged once per
	// batch of events, when _occlusionDirty is set.
	BOOL _occlusionDirty;
	Window _occlusionWatchWindow;
	// What the judgement needs, read again only after an event that can change it: the focused foreign window
	// (_occlusionActive, from _NET_ACTIVE_WINDOW), its geometry and whether it is fullscreen and opaque.
	BOOL _occlusionActiveKnown;
	Window _occlusionActive;
	BOOL _occlusionCoverValid;
	BOOL _occlusionCoverOK;
	BOOL _occlusionCoverFullscreen;
	BOOL _occlusionCoverOpaque;
	int _occlusionCoverX, _occlusionCoverY;
	unsigned int _occlusionCoverWidth, _occlusionCoverHeight;
	BOOL _occlusionWatchGeometryKnown;
	int _occlusionWatchX, _occlusionWatchY, _occlusionWatchWidth, _occlusionWatchHeight;

	// The arrow shown over the windows of the framework above while no cursor is selected.
	Cursor _defaultArrow;
	CGFloat _defaultArrowScale;
}

-(instancetype) initWithConnectionID:(CGSConnectionID)connId;
-(void) dealloc;
-(CGSWindow*) newWindow:(CGSRegionRef)region;
-(CGSWindow*) newToplevelWindowWithAttributes:(const CGSToplevelAttributes*)attributes;
-(BOOL) supportsTranslucentToplevels;

-(void) processPendingEvents;
// The main monitor's rectangle in root coordinates (device pixels).
-(X11Frame) _primaryRoot;
// A point in root coordinates (device pixels) in CoreGraphics' global space (points).
-(CGPoint) _cgPointFromRoot:(CGPoint)root;
// The CGS window that has this X window, 0 when none.
-(CGSWindowID) _windowIDForNativeWindow:(Window)native;
-(CGSWindowX11*) _cgsWindowForNativeWindow:(Window)native;
// The display overlay (see -[CGSWindow becomeDisplayOverlay:]) shown last, nil when there is none, and whether an
// X window is a display overlay.
-(CGSWindowX11*) _displayOverlayWindow;
-(BOOL) _isDisplayOverlayNativeWindow:(Window)native;
// The device pixel position of a point of CoreGraphics' global space (rounded).
-(void) _getRootX:(int*)x y:(int*)y forPoint:(CGPoint)point;
// The blank cursor, made on first use.
-(Cursor) _blankCursorMade;
// Gives the window system what the process shows over its windows: the blank cursor while it is hidden, else the
// selected cursor. Main thread.
-(void) _applyCursor;
-(NSArray<NSDictionary*>*) copyWindowDescriptions;
// The toplevel windows of the UI layer.
-(NSArray<CGSWindowX11*>*) _toplevelWindows;
// The toplevel window that has this X window, nil when none.
-(CGSWindowX11*) _toplevelForNativeWindow:(Window)native;
// A toplevel window was made or made again: the windows are judged again for being covered.
-(void) _toplevelWindowCreated;
// Puts the windows of this connection in the order of their levels around a window that was ordered to the front,
// mapped or given another level (see X11LevelStacking.h): an unmanaged window is above the frames the window
// manager restacks around it, so the unmanaged windows are moved, never the managed ones.
-(void) _restackToplevelWindowsForLevelsAround:(CGSWindowX11*)anchor;

+(BOOL) isAvailable;
// The pointer of the process' connection, nil without one. Not retained for the caller (a test of the pointer's
// decoding uses it to give the decoder an event of its own).
+(CGSX11Pointer*) _processPointer;
// The connection's input method, made on first use, and whether an input method of the application composes
// dead keys and Compose sequences (see CGSX11InputMethod.h).
-(CGSX11InputMethod*) _inputMethod;
-(BOOL) _inputMethodComposes;

// A window that holds the input for its menu was shown or hidden: the pointer and the keyboard are held for the newest
// shown one, and let go when none is left.
-(void) menuWindowShown:(CGSWindowX11*) window;
-(void) menuWindowHidden:(CGSWindowX11*) window;

@end

#endif

