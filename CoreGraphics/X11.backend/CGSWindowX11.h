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
#ifndef CGSWINDOWX11_H
#define CGSWINDOWX11_H

#import <CoreGraphics/CGSWindow.h>
#import <X11/Xlib.h>
#import <X11/Xutil.h>

// A CGS window is a plain X11 top-level window: a child of the root window, so that
// there is no window manager in the way of its geometry. Its pixels come from its
// CGSSurface, which is a child X11 window of this one; nothing in this tree composites
// a CGS window, so it stays unmapped until CGSOrderWindow() is asked to show it.

@class CGSX11InputContext;
@class CGSConnectionX11;

@interface CGSWindowX11 : CGSWindow {
@public
	CGSConnectionX11* _x11Connection; // Not retained; the connection owns us.
	Display* _display; // Borrowed from _x11Connection.
	Window _window;
	NSString* _title;
	GC _gc;                  // for putting the contents on the window; created when first needed
	BOOL _contentsShaped;    // the window's shape follows the alpha of its contents
	BOOL _displayOverlay;    // -becomeDisplayOverlay: made this window the cover of a display

	// A toplevel window of the application's UI layer (see CGSWindow.h), which draws into it itself.
	BOOL _toplevel;
	BOOL _toplevelUnmanaged;     // override-redirect: the window manager leaves the window alone
	XVisualInfo* _visualInfo;    // the visual of the window (not owned)
	Colormap _colormap;          // made with the window; freed with it
	CGRect _toplevelRoot;        // the window's frame on the root window, in points (y down)
	CGFloat _toplevelScale;      // device pixels per point the window is sized with
	BOOL _toplevelShown;
	BOOL _hasPendingExpose;      // an expose event of a series was received; _pendingExpose is their union (device pixels)
	CGRect _pendingExpose;
	BOOL _hasShadow;
	BOOL _contentsOpaque;
	CGSize _opaqueRegionSize;    // device size of the opaque region set on the window, zero for none
	CGFloat _cornerRadius;       // in points
	BOOL _roundedShapeSet;       // the bounding shape has rounded corners
	BOOL _shapeEmpty;
	BOOL _ignoresMouse;
	BOOL _skipsTaskList;
	CGSToplevelTitlebarKind _titlebarKind;

	BOOL _holdsMenuInput;        // see -setToplevelHoldsInputForMenu:
	NSString* _menuService;      // see -setToplevelApplicationMenuServiceName:objectPath:
	NSString* _menuPath;
	// Ordering, focus and the window system's state of a toplevel window (see CGSWindow.h).
	CGSToplevelKind _toplevelKind;
	int _toplevelLevel;
	BOOL _toplevelStacksByLevel;
	BOOL _wantsInputFocus;       // the focus was asked for before the window was viewable: asked again when it is
	BOOL _fullscreenRequested;   // what the window system was asked for, or last said
	BOOL _fullscreenReported;    // what the UI layer was last told
	BOOL _miniaturizedKnown;     // _miniaturized is what _NET_WM_STATE said; a change of the property drops it
	BOOL _miniaturized;
	BOOL _miniaturizedReported;
	BOOL _occluded;
	BOOL _configureKnown;        // the geometry of the last configure event, to tell a repeat from a change
	int _configureX, _configureY, _configureWidth, _configureHeight;

	// The window's input context, while it uses the input method (see CGSInputMethod.h); nil otherwise.
	CGSX11InputContext* _inputContext;
}

// Whether the window is a toplevel window of the UI layer, which handles the window system's events for it.
-(BOOL) isToplevel;
// The visual the window was made with (a toplevel window only; the window's depth is visualInfo->depth).
-(XVisualInfo*) visualInfo;
// Whether the display has a 32-bit visual with alpha for translucent toplevel windows.
+(BOOL) translucentVisualAvailableOnDisplay:(Display*) display;
-(instancetype) initToplevelWithAttributes:(const CGSToplevelAttributes*) attributes
								connection:(CGSConnection*) connection
								  windowID:(CGSWindowID) windowID;

// Whether the window is a display overlay (see -becomeDisplayOverlay:). Its input is the process' own, but
// belongs to no window of the application: its events name no window.
-(BOOL) isDisplayOverlay;

// A toplevel window's reports of the window system (see CGSToplevelEvent): the user asked to close it.
-(void) windowSystemDidRequestClose;
// The display layout changed: a toplevel window follows a change of the backing scale (the window keeps its
// size in points) and reports it.
-(void) windowSystemLayoutChanged;

// The window system asked for the window to be painted again (an expose event): the contents are put on it.
-(void) windowSystemDidExpose:(const XExposeEvent*) event;
// The window changed place or size (a configure event): follows with the contents and reports the bounds.
-(void) windowSystemDidConfigure;
// The window system's focus came to the window or left it (a FocusIn or FocusOut that is not a grab or the
// pointer passing over), the window was mapped (the manager has stacked it by now) or put in a manager's frame,
// or its _NET_WM_STATE changed.
-(void) windowSystemFocusChanged:(BOOL) gained;
// The text a key press makes as the window's input method composes it (nil: no input context, the keymap's).
// The window system's keyboard focus came to the window or left it: the window's input method follows (a
// FocusIn or FocusOut that is not a grab or the pointer passing over). Not only toplevel windows have one.
-(void) inputMethodFocusChanged:(BOOL) gained;
-(NSString*) inputMethodTextForKeyEvent:(XKeyEvent*) event keySym:(KeySym*) keySym;
-(void) windowSystemDidMap;
-(void) windowSystemDidReparent;
-(void) windowSystemStateChanged;
// A configure event that moved or sized the window: whether the geometry differs from the one before. Used to
// know when another client's window may cover this one.
-(BOOL) noteConfigureGeometryChanged:(const XConfigureEvent*) event;
// Whether another client's window covers this window, as the connection judged it (see
// -[CGSConnectionX11 _updateOcclusion]); posts the change.
-(void) setOccludedByWindowSystem:(BOOL) occluded;
// Whether the window is on the screen as far as the process knows, and takes part in stacking by level.
-(BOOL) takesPartInLevelStacking;
-(BOOL) isUnmanaged;
-(int) stackingLevel;

-(instancetype) initWithRegion:(CGSRegionRef) region
					connection:(CGSConnection*) connection
					  windowID:(CGSWindowID) windowID;

@end

#endif
