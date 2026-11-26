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

// The window system asked for the window to be painted again (an expose event): the contents are put on it.
-(void) windowSystemDidExpose:(const XExposeEvent*) event;
// The window changed place or size (a configure event): follows with the contents and reports the bounds.
-(void) windowSystemDidConfigure;

-(instancetype) initWithRegion:(CGSRegionRef) region
					connection:(CGSConnection*) connection
					  windowID:(CGSWindowID) windowID;

@end

#endif
