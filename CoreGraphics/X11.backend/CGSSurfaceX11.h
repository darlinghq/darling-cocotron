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
#ifndef CGSSURFACEX11_H
#define CGSSURFACEX11_H

#import <CoreGraphics/CGSSurface.h>
#import <X11/Xlib.h>

@class CGSWindowX11;

// A CGS surface is a child X11 window of its CGS window, which is the drawable a
// caller renders into. Unlike the Wayland backend, which can only ever give a toplevel
// one surface because that would need a wl_subsurface, a window on X11 can hold as many
// as the caller asks for, since each one is an independent X11 window.

@interface CGSSurfaceX11 : CGSSurface {
@public
	// The X11 window this surface draws on. -[_window] is the CGS window that owns us.
	Display* _display; // Borrowed from -[_window].
	Window _xWindow;
}

-(instancetype) initWithWindow:(CGSWindow*) window surfaceID:(CGSSurfaceID) surfaceID;

@end

#endif
