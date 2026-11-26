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
#import <X11/Xutil.h>
#import <X11/Xatom.h>
#import <X11/extensions/shape.h>

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

	// The keys typed into the window and the keyboard focus are the keyboard's, the buttons and the
	// pointer's motion the pointer's: they decode them into CGEvents (see CGSX11Keyboard.h and
	// CGSX11Pointer.h) whichever framework asked for the window.
	XSelectInput(_display, _window, KeyPressMask | KeyReleaseMask | FocusChangeMask | ButtonPressMask |
		ButtonReleaseMask | PointerMotionMask | EnterWindowMask | LeaveWindowMask | ExposureMask |
		StructureNotifyMask);
	// Touch screens, and the touchpad pinch gestures of the server that has them.
	_CGSNativeConnectionSelectTouchInput((unsigned long) _window);

	// The window manager asks the window to close (a client message) instead of destroying it
	// and asks whether the window is alive (_NET_WM_PING), which the connection answers
	Atom protocols[2] = { XInternAtom(_display, "WM_DELETE_WINDOW", False), XInternAtom(_display, "_NET_WM_PING", False) };
	XSetWMProtocols(_display, _window, protocols, 2);

	[self _setSizeHints];

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

	if (_display != NULL && _gc != None)
		XFreeGC(_display, _gc);
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
			// The window system asks for the contents with an expose event once it is shown
			XMapRaised(_display, _window);
			// Another connection (the application's UI layer) grabs the
			// pointer on the window once it is announced, so it must be
			// mapped on the server by then.
			XSync(_display, False);
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

-(CGError) becomeDisplayOverlay:(void**) drawable
{
	if (drawable == NULL)
		return kCGErrorIllegalArgument;

	// Override-redirect: the window manager neither decorates, places nor
	// focuses the window, and it stays where it was stacked when it was mapped.
	XSetWindowAttributes attributes = { .override_redirect = True };
	XChangeWindowAttributes(_display, _window, CWOverrideRedirect, &attributes);

	// The drawable is used through other connections to the server (the GL
	// library's), which only know the window once this connection's requests
	// have reached the server.
	XSync(_display, False);

	// The window itself is the drawable: it is the one that gets mapped.
	*drawable = (void*) (uintptr_t) _window;
	return kCGSErrorSuccess;
}

-(CGError) moveTo:(const CGPoint*) point
{
	if (point == NULL)
		return kCGErrorIllegalArgument;

	XMoveWindow(_display, _window, lround(point->x), lround(point->y));
	[self _setSizeHints];
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
	[self _setSizeHints];
	// The server needs the request before the contents are put on the resized window
	XSync(_display, False);
	[self resizeContentsTo: frame.size];
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

#pragma mark - Contents and style

-(void) presentRect:(CGRect) rect
{
	[self withContents: ^(const void* bytes, size_t rowBytes, CGSize size) {
		if (_gc == None)
			_gc = XCreateGC(_display, _window, 0, NULL);

		int screen = DefaultScreen(_display);
		XImage* image = XCreateImage(_display, DefaultVisual(_display, screen), DefaultDepth(_display, screen),
			ZPixmap, 0, (char*) bytes, (unsigned) size.width, (unsigned) size.height, 32, (int) rowBytes);
		if (image == NULL)
			return;

		CGRect part = CGRectIntersection(CGRectIntegral(rect), CGRectMake(0, 0, size.width, size.height));
		if (!CGRectIsNull(part) && part.size.width >= 1 && part.size.height >= 1)
			XPutImage(_display, _window, _gc, image, (int) part.origin.x, (int) part.origin.y,
				(int) part.origin.x, (int) part.origin.y, (unsigned) part.size.width, (unsigned) part.size.height);

		if (_styleFlags & kCGSWindowStyleTransparent)
			[self _shapeWindowToAlpha: (const uint8_t*) bytes rowBytes: rowBytes size: size];

		// The pixels belong to the window's contents
		image->data = NULL;
		XDestroyImage(image);
		XFlush(_display);
	}];
}

// Without a compositor an X11 window cannot be translucent: the window takes the outline of what
// has any alpha, so a transparent window does not block what is below where it draws nothing.
-(void) _shapeWindowToAlpha:(const uint8_t*) bytes rowBytes:(size_t) rowBytes size:(CGSize) size
{
	int width = (int) size.width, height = (int) size.height;
	size_t capacity = 64, count = 0;
	XRectangle* rects = malloc(capacity * sizeof(XRectangle));
	if (rects == NULL)
		return;

	for (int y = 0; y < height; y++)
	{
		const uint8_t* row = bytes + (size_t) y * rowBytes;
		int x = 0;
		while (x < width)
		{
			while (x < width && row[x * 4 + 3] == 0)
				x++;
			int start = x;
			while (x < width && row[x * 4 + 3] != 0)
				x++;
			if (x > start)
			{
				if (count == capacity)
				{
					XRectangle* grown = realloc(rects, capacity * 2 * sizeof(XRectangle));
					if (grown == NULL)
					{
						free(rects);
						return;
					}
					rects = grown;
					capacity *= 2;
				}
				rects[count++] = (XRectangle) { (short) start, (short) y, (unsigned short) (x - start), 1 };
			}
		}
	}

	XShapeCombineRectangles(_display, _window, ShapeBounding, 0, 0, rects, (int) count, ShapeSet, YXBanded);
	_contentsShaped = YES;
	free(rects);
}

-(void) windowSystemDidExpose:(const XExposeEvent*) event
{
	[self presentRect: CGRectMake(event->x, event->y, event->width, event->height)];
}

-(void) windowSystemDidConfigure
{
	CGRect frame;
	if ([self getRect: &frame] != kCGSErrorSuccess)
		return;
	[self resizeContentsTo: frame.size];
	_CGSPostWindowEvent(kCGSWindowEventBounds, self.windowId, frame);
}

// The position and size are the program's (a window manager places a window that has no such hint
// where it likes); a window that is not to be resized by the user has them as its only size
-(void) _setSizeHints
{
	CGRect frame;
	if ([self getRect: &frame] != kCGSErrorSuccess)
		return;
	XSizeHints hints = {0};
	hints.flags = USPosition | USSize | PWinGravity;
	// The position is where the window's own area goes, not where the window manager's frame around it
	hints.win_gravity = StaticGravity;
	hints.x = (int) frame.origin.x;
	hints.y = (int) frame.origin.y;
	hints.width = (int) frame.size.width;
	hints.height = (int) frame.size.height;
	if (_styleFlags & kCGSWindowStyleFixedSize)
	{
		hints.flags |= PMinSize | PMaxSize;
		hints.min_width = hints.max_width = (int) frame.size.width;
		hints.min_height = hints.max_height = (int) frame.size.height;
	}
	XSetWMNormalHints(_display, _window, &hints);
}

// The window manager's states of the window, set before it is mapped; once mapped they are requested of
// the window manager with a message to the root window.
-(void) _setNetWmState:(Atom) state on:(BOOL) on
{
	Atom netWmState = XInternAtom(_display, "_NET_WM_STATE", False);
	XWindowAttributes attributes;
	if (XGetWindowAttributes(_display, _window, &attributes) && attributes.map_state != IsUnmapped)
	{
		XEvent event = {0};
		event.xclient.type = ClientMessage;
		event.xclient.window = _window;
		event.xclient.message_type = netWmState;
		event.xclient.format = 32;
		event.xclient.data.l[0] = on ? 1 : 0;
		event.xclient.data.l[1] = (long) state;
		event.xclient.data.l[3] = 1;
		XSendEvent(_display, DefaultRootWindow(_display), False,
			SubstructureNotifyMask | SubstructureRedirectMask, &event);
	}
	else if (on)
	{
		XChangeProperty(_display, _window, netWmState, XA_ATOM, 32, PropModeAppend,
			(const unsigned char*) &state, 1);
	}
}

-(CGError) setStyle:(uint32_t) styleFlags
{
	uint32_t previous = _styleFlags;
	uint32_t changed = previous ^ styleFlags;
	[super setStyle: styleFlags];

	if (changed & kCGSWindowStyleFloating)
		[self _setNetWmState: XInternAtom(_display, "_NET_WM_STATE_ABOVE", False)
			on: (styleFlags & kCGSWindowStyleFloating) != 0];

	if (changed & kCGSWindowStyleUtility)
	{
		Atom type = XInternAtom(_display, "_NET_WM_WINDOW_TYPE", False);
		Atom value = XInternAtom(_display, (styleFlags & kCGSWindowStyleUtility) ?
			"_NET_WM_WINDOW_TYPE_UTILITY" : "_NET_WM_WINDOW_TYPE_NORMAL", False);
		XChangeProperty(_display, _window, type, XA_ATOM, 32, PropModeReplace, (const unsigned char*) &value, 1);
		[self _setNetWmState: XInternAtom(_display, "_NET_WM_STATE_SKIP_TASKBAR", False)
			on: (styleFlags & kCGSWindowStyleUtility) != 0];
	}

	if (changed & (kCGSWindowStyleBorderless | kCGSWindowStyleNoClose))
	{
		// _MOTIF_WM_HINTS: flags 1 = functions, 2 = decorations. Functions 1 (all) | 32 (but close).
		unsigned long hints[5] = {0, 0, 1, 0, 0};
		if (styleFlags & kCGSWindowStyleNoClose)
		{
			hints[0] |= 1;
			hints[1] = 1 | 32;
		}
		if (styleFlags & kCGSWindowStyleBorderless)
		{
			hints[0] |= 2;
			hints[2] = 0;
		}
		Atom motif = XInternAtom(_display, "_MOTIF_WM_HINTS", False);
		XChangeProperty(_display, _window, motif, motif, 32, PropModeReplace, (const unsigned char*) hints, 5);
	}

	if (changed & kCGSWindowStyleUnmanaged)
	{
		XSetWindowAttributes attributes = { .override_redirect = (styleFlags & kCGSWindowStyleUnmanaged) ? True : False };
		XChangeWindowAttributes(_display, _window, CWOverrideRedirect, &attributes);
	}

	if (changed & kCGSWindowStyleIgnoresMouse)
	{
		if (styleFlags & kCGSWindowStyleIgnoresMouse)
			XShapeCombineRectangles(_display, _window, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
		else
			XShapeCombineMask(_display, _window, ShapeInput, 0, 0, None, ShapeSet);
	}

	if (changed & kCGSWindowStyleFixedSize)
		[self _setSizeHints];

	if (changed & kCGSWindowStyleNoFocus)
	{
		XWMHints wmHints = {0};
		wmHints.flags = InputHint;
		wmHints.input = (styleFlags & kCGSWindowStyleNoFocus) ? False : True;
		XSetWMHints(_display, _window, &wmHints);
	}

	if ((changed & kCGSWindowStyleTransparent) && !(styleFlags & kCGSWindowStyleTransparent) && _contentsShaped)
	{
		XShapeCombineMask(_display, _window, ShapeBounding, 0, 0, None, ShapeSet);
		_contentsShaped = NO;
	}

	XFlush(_display);
	return kCGSErrorSuccess;
}

@end
