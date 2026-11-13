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
}

-(instancetype) initWithRegion:(CGSRegionRef) region
					connection:(CGSConnection*) connection
					  windowID:(CGSWindowID) windowID;

@end

#endif
