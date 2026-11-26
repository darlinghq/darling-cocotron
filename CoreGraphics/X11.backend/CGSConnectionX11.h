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

@class CGSWindowX11;
@class CGSX11Keyboard;
@class CGSX11Pointer;

@interface CGSConnectionX11 : CGSConnection {
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
// Shows a blank cursor on the windows of this connection, or the cursor they had (the process' cursor is hidden).
-(void) _setBlankCursorOnWindows:(BOOL)blank;
// The blank cursor, made on first use.
-(Cursor) _blankCursorMade;
-(NSArray<NSDictionary*>*) copyWindowDescriptions;

+(BOOL) isAvailable;
// The pointer of the process' connection, nil without one. Not retained for the caller (a test of the pointer's
// decoding uses it to give the decoder an event of its own).
+(CGSX11Pointer*) _processPointer;

@end

#endif

