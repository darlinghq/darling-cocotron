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
#import "CGSWindowX11.h"
#import "CGSConnectionX11.h"
#import "CGSSurfaceX11.h"

#import <Foundation/NSString.h>

// X11's stacking requests need both windows mapped, which is the only precondition
// XConfigureWindow() does not check for us.
static BOOL isViewable(Display* display, Window window)
{
	XWindowAttributes attributes;
	return XGetWindowAttributes(display, window, &attributes) &&
		attributes.map_state == IsViewable;
}

@implementation CGSWindowX11

-(instancetype) initWithRegion:(CGSRegionRef) region
				   connection:(CGSConnection*) connection
					 windowID:(CGSWindowID) windowID
{
	self = [super initWithRegion: region connection: connection windowID: windowID];
	if (self == nil)
		return nil;

	_x11Connection = (CGSConnectionX11*) connection;
	_display = _x11Connection->_display;

	CGRect frame = CGRectZero;
	if (region != NULL)
		CGSRegionToRect(region, &frame);

	if (_display == NULL || !(frame.size.width >= 1) || !(frame.size.height >= 1))
	{
		NSLog(@"CoreGraphics X11 backend: refusing a %g x %g CGS window",
			frame.size.width, frame.size.height);
		[self release];
		return nil;
	}

	// The region is in CG points, X11 wants whole pixels. The rect is rounded rather
	// than scaled, because this backend has no backing scale to apply.
	_window = XCreateSimpleWindow(_display, DefaultRootWindow(_display),
		lround(frame.origin.x), lround(frame.origin.y),
		lround(frame.size.width), lround(frame.size.height), 0, 0, 0);
	if (_window == None)
	{
		NSLog(@"CoreGraphics X11 backend: cannot create an X11 window for CGS window %d",
			(int) windowID);
		[self release];
		return nil;
	}

	// Left unmapped: this backend cannot put pixels into a CGS window, so mapping it
	// here would drop an empty window on the host desktop. CGSOrderWindow() maps it
	// when a caller asks for it to be shown.
	return self;
}

-(void) dealloc
{
	// The surfaces destroy X11 child windows of ours, which have to go first.
	// -[CGSWindow dealloc] would only release _surfaces after this body.
	@synchronized (_surfaces)
	{
		[_surfaces removeAllObjects];
	}

	[_title release];

	if (_display != NULL && _window != None)
		XDestroyWindow(_display, _window);

	[super dealloc];
}

-(void*) nativeWindow
{
	// EGLNativeWindowType on X11 is the drawable's XID.
	return (void*) (uintptr_t) _window;
}

-(CGSSurface*) createSurface
{
	CGSSurfaceID surfaceID = _nextSurfaceId++;
	CGSSurfaceX11* surface = [[CGSSurfaceX11 alloc] initWithWindow: self surfaceID: surfaceID];
	if (surface == nil)
		return nil;

	@synchronized (_surfaces)
	{
		[_surfaces setObject: surface forKey: [NSNumber numberWithInt: surfaceID]];
	}
	[surface release];
	return surface;
}

-(CGError) orderWindow:(CGSWindowOrderingMode) place relativeTo:(CGSWindow*) window
{
	if (window != nil)
	{
		if (![window isKindOfClass: [CGSWindowX11 class]])
		{
			NSLog(@"CoreGraphics X11 backend: cannot order CGS window %d relative to a "
				@"window of another backend", (int) self.windowId);
			return kCGErrorIllegalArgument;
		}

		// Restacking needs a viewable sibling on either side; ordering an unmapped
		// window is refused by the server as a BadMatch.
		Window sibling = ((CGSWindowX11*) window)->_window;
		if (!isViewable(_display, _window) || !isViewable(_display, sibling))
		{
			NSLog(@"CoreGraphics X11 backend: both CGS windows have to be mapped before "
				"one can be ordered relative to the other");
			return kCGErrorIllegalArgument;
		}

		XWindowChanges changes = {
			.sibling = sibling,
			.stack_mode = (place == kCGSOrderBelow) ? Below : Above,
		};
		XConfigureWindow(_display, _window, CWSibling | CWStackMode, &changes);
		return kCGSErrorSuccess;
	}

	switch (place)
	{
		case kCGSOrderOut:
			XUnmapWindow(_display, _window);
			return kCGSErrorSuccess;
		case kCGSOrderIn:
			XMapWindow(_display, _window);
			return kCGSErrorSuccess;
		case kCGSOrderAbove:
			XMapRaised(_display, _window);
			return kCGSErrorSuccess;
		case kCGSOrderBelow:
		default:
			// X11 needs a sibling to order below; below everything else would put the
			// window behind the root window's own contents.
			NSLog(@"CoreGraphics X11 backend: ordering CGS window %d with mode %d without "
				"another window is not available on X11", (int) self.windowId, (int) place);
			return kCGErrorNotImplemented;
	}
}

-(CGError) moveTo:(const CGPoint*) point
{
	if (point == NULL)
		return kCGErrorIllegalArgument;

	XMoveWindow(_display, _window, lround(point->x), lround(point->y));
	return kCGSErrorSuccess;
}

-(CGError) setRegion:(CGSRegionRef) region
{
	// CGSRegionToRect() dereferences its argument.
	if (region == NULL)
		return kCGErrorIllegalArgument;

	CGRect frame;
	CGSRegionToRect(region, &frame);
	if (!(frame.size.width >= 1) || !(frame.size.height >= 1))
		return kCGErrorIllegalArgument;

	XMoveResizeWindow(_display, _window, lround(frame.origin.x), lround(frame.origin.y),
		lround(frame.size.width), lround(frame.size.height));
	return kCGSErrorSuccess;
}

-(CGError) getRect:(CGRect*) outRect
{
	if (outRect == NULL)
		return kCGErrorIllegalArgument;

	Window root, child;
	int x, y;
	unsigned int width, height, borderWidth, depth;
	if (!XGetGeometry(_display, _window, &root, &x, &y, &width, &height,
		&borderWidth, &depth))
	{
		NSLog(@"CoreGraphics X11 backend: cannot read the geometry of CGS window %d",
			(int) self.windowId);
		return kCGErrorFailure;
	}

	// XGetGeometry reports the position within the parent, which a reparenting window
	// manager rewrites; CGS callers mean the position on the root window.
	int rootX = 0, rootY = 0;
	XTranslateCoordinates(_display, _window, root, 0, 0, &rootX, &rootY, &child);

	*outRect = CGRectMake(rootX, rootY, width, height);
	return kCGSErrorSuccess;
}

-(CGError) setProperty:(CFStringRef) key value:(CFTypeRef) value
{
	if (key == NULL)
		return kCGErrorIllegalArgument;

	if (CFStringCompare(key, kCGSWindowTitle, 0) != kCFCompareEqualTo)
	{
		NSLog(@"CoreGraphics X11 backend: CGS window property %@ is not supported",
			(NSString*) key);
		return kCGErrorNotImplemented;
	}

	if (value != NULL && ![(id) value isKindOfClass: [NSString class]])
		return kCGErrorTypeCheck;

	NSString* title = (NSString*) value;

	[_title release];
	_title = [title copy];

	// A window with no title is reported as one with an empty title, because
	// XStoreName() reads its argument as a C string.
	const char* utf8 = [_title UTF8String];
	if (utf8 == NULL)
		utf8 = "";

	// WM_NAME for window managers that predate UTF-8 titles, _NET_WM_NAME for the
	// ones that do not.
	XStoreName(_display, _window, utf8);
	Atom netWMName = XInternAtom(_display, "_NET_WM_NAME", False);
	Atom utf8String = XInternAtom(_display, "UTF8_STRING", False);
	XChangeProperty(_display, _window, netWMName, utf8String, 8, PropModeReplace,
		(const unsigned char*) utf8,
		[_title lengthOfBytesUsingEncoding: NSUTF8StringEncoding]);
	return kCGSErrorSuccess;
}

-(CGError) getProperty:(CFStringRef) key value:(CFTypeRef*) value
{
	if (value == NULL)
		return kCGErrorIllegalArgument;

	if (key != NULL && CFStringCompare(key, kCGSWindowTitle, 0) == kCFCompareEqualTo)
	{
		*value = _title != nil ? (CFTypeRef) CFRetain((CFTypeRef) _title) : NULL;
		return kCGSErrorSuccess;
	}

	NSLog(@"CoreGraphics X11 backend: CGS window property %@ is not supported",
		(NSString*) key);
	return kCGErrorNotImplemented;
}

@end
