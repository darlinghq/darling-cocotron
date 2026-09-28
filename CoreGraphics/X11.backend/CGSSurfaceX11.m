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
#import "CGSSurfaceX11.h"
#import "CGSWindowX11.h"

@implementation CGSSurfaceX11

-(instancetype) initWithWindow:(CGSWindow*) window surfaceID:(CGSSurfaceID) surfaceID
{
	// A surface of another backend's window has no X11 window to live in.
	if (![window isKindOfClass: [CGSWindowX11 class]])
	{
		[self release];
		return nil;
	}

	self = [super initWithWindow: window surfaceID: surfaceID];
	if (self == nil)
		return nil;

	CGSWindowX11* x11Window = (CGSWindowX11*) window;
	_display = x11Window->_display;

	// The surface starts out covering its window. XGetGeometry() leaves the sizes
	// untouched when the window cannot be queried, which leaves a 1x1 surface.
	unsigned int width = 1, height = 1, borderWidth, depth;
	Window root, child;
	int x, y;
	XGetGeometry(_display, x11Window->_window, &root, &x, &y,
		&width, &height, &borderWidth, &depth);

	_xWindow = XCreateSimpleWindow(_display, x11Window->_window, 0, 0,
		width, height, 0, 0, 0);
	if (_xWindow == None)
	{
		NSLog(@"CoreGraphics X11 backend: cannot create a %u x %u surface for CGS window %d",
			width, height, (int) window.windowId);
		[self release];
		return nil;
	}

	return self;
}

-(void) dealloc
{
	if (_display != NULL && _xWindow != None)
		XDestroyWindow(_display, _xWindow);

	[super dealloc];
}

-(void*) nativeWindow
{
	return (void*) (uintptr_t) _xWindow;
}

-(CGError) setBounds:(CGRect) rect
{
	// X11 refuses a zero-sized window, and a size below one pixel rounds down to it.
	if (!(rect.size.width >= 1) || !(rect.size.height >= 1))
		return kCGErrorIllegalArgument;

	XMoveResizeWindow(_display, _xWindow, lround(rect.origin.x), lround(rect.origin.y),
		lround(rect.size.width), lround(rect.size.height));
	return kCGSErrorSuccess;
}

@end
