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
#import "CGSX11Drag.h"
#import "CGSX11InputMethod.h"
#import "CGSSurfaceX11.h"
#import "X11WindowOwner.h"
#import "X11Monitors.h"
#import "X11OpaqueRegion.h"
#import "X11RoundedShape.h"
#import "X11InputShape.h"
#import "X11InvisibleWindow.h"
#import "X11Fullscreen.h"
#import "X11WindowManager.h"

#import <Foundation/NSString.h>
#import <Foundation/NSData.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSProcessInfo.h>
#import <X11/Xutil.h>
#import <X11/Xatom.h>
#import <X11/extensions/shape.h>
#import <GL/glx.h>
#include <math.h>

// X11's stacking requests need both windows mapped, which is the only precondition
// XConfigureWindow() does not check for us.
static BOOL isViewable(Display* display, Window window)
{
	XWindowAttributes attributes;
	return XGetWindowAttributes(display, window, &attributes) &&
		attributes.map_state == IsViewable;
}

// The visual of the opaque toplevel windows. Rendering goes through EGL, and a visual that glXChooseVisual
// picks can be one that only GLX can draw to (some EGL implementations reject such visuals), so the default
// visual comes first when it is TrueColor with at least 24 bits.
static XVisualInfo* opaqueToplevelVisualInfo(Display* display)
{
	static XVisualInfo* visualInfo;

	if (visualInfo != NULL)
		return visualInfo;

	int screen = DefaultScreen(display);
	XVisualInfo visualTemplate = {
		.visualid = XVisualIDFromVisual(DefaultVisual(display, screen)),
		.screen = screen,
	};
	int count = 0;
	visualInfo = XGetVisualInfo(display, VisualIDMask | VisualScreenMask, &visualTemplate, &count);
	if (visualInfo != NULL && (visualInfo->class != TrueColor || visualInfo->depth < 24))
	{
		XFree(visualInfo);
		visualInfo = NULL;
	}

	if (visualInfo == NULL)
	{
		int attributes[] = {GLX_RGBA, GLX_DOUBLEBUFFER, GLX_RED_SIZE, 4, GLX_GREEN_SIZE, 4,
			GLX_BLUE_SIZE, 4, GLX_DEPTH_SIZE, 4, None};
		visualInfo = glXChooseVisual(display, screen, attributes);
		if (visualInfo == NULL)
			NSLog(@"CoreGraphics X11 backend: glXChooseVisual failed");
	}
	return visualInfo;
}

// A 32-bit TrueColor visual with an alpha channel, for the toplevel windows that let what is behind them show
// through, or NULL if the screen has none.
static XVisualInfo* translucentToplevelVisualInfo(Display* display)
{
	static XVisualInfo visualInfo;
	static BOOL looked;

	if (!looked)
	{
		looked = YES;
		XVisualInfo visualTemplate = {
			.screen = DefaultScreen(display),
			.depth = 32,
			.class = TrueColor,
		};
		int count = 0;
		XVisualInfo* visuals = XGetVisualInfo(display, VisualScreenMask | VisualDepthMask | VisualClassMask,
			&visualTemplate, &count);
		for (int i = 0; i < count && visualInfo.visual == NULL; i++)
		{
			if (visuals[i].red_mask == 0xff0000 && visuals[i].green_mask == 0x00ff00 &&
				visuals[i].blue_mask == 0x0000ff)
				visualInfo = visuals[i];
		}
		if (visuals != NULL)
			XFree(visuals);
	}
	return visualInfo.visual != NULL ? &visualInfo : NULL;
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

	// _NET_WM_PID and WM_CLIENT_MACHINE, so that other clients, and other Darling processes listing windows or
	// following the focus, know whose window this is (the process' own windows are told from the others by it).
	X11WindowOwnerPublish(_display, _window);
	X11WindowOwnerPublishWindowID(_display, _window, windowID);

	[self _setSizeHints];

	// Left unmapped: this backend cannot put pixels into a CGS window, so mapping it
	// here would drop an empty window on the host desktop. CGSOrderWindow() maps it
	// when a caller asks for it to be shown.
	return self;
}

-(void) dealloc
{
	if (_holdsMenuInput)
		[(CGSConnectionX11*) _connection menuWindowHidden: self];
	// The surfaces destroy X11 child windows of ours, which have to go first.
	// -[CGSWindow dealloc] would only release _surfaces after this body.
	@synchronized (_surfaces)
	{
		[_surfaces removeAllObjects];
	}

	[_title release];
	[_menuService release];
	[_menuPath release];

	// The input context belongs to the X window.
	[_inputContext destroy];
	[_inputContext release];

	if (_display != NULL && _gc != None)
		XFreeGC(_display, _gc);
	if (_display != NULL && _window != None)
		XDestroyWindow(_display, _window);
	if (_display != NULL && _colormap != None)
		XFreeColormap(_display, _colormap);

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
			_toplevelShown = NO;
			if (_holdsMenuInput)
				[(CGSConnectionX11*) _connection menuWindowHidden: self];
			if (_toplevel)
			{
				// The manager drops the fullscreen state of a withdrawn window, and nothing covers it or
				// holds it iconic; a focus request still waiting for the map is void.
				_occluded = NO;
				_miniaturizedKnown = NO;
				_fullscreenRequested = NO;
				_fullscreenReported = NO;
				_wantsInputFocus = NO;
			}
			return kCGSErrorSuccess;
		case kCGSOrderIn:
			XMapWindow(_display, _window);
			_toplevelShown = YES;
			_miniaturizedKnown = NO;
			if (_holdsMenuInput)
				[(CGSConnectionX11*) _connection menuWindowShown: self];
			return kCGSErrorSuccess;
		case kCGSOrderAbove:
			// The window system asks for the contents with an expose event once it is shown
			XMapRaised(_display, _window);
			_toplevelShown = YES;
			// Another connection (the application's UI layer) grabs the
			// pointer on the window once it is announced, so it must be
			// mapped on the server by then.
			XSync(_display, False);
			if (_displayOverlay)
				[self _displayOverlayShown];
			if (_holdsMenuInput)
				[(CGSConnectionX11*) _connection menuWindowShown: self];
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
	// Its keys and buttons are selected like those of every CGS window; the events it gets name no CGS window
	// (see CGSX11Pointer.m), as those of a captured display do not.
	_displayOverlay = YES;

	// The drawable is used through other connections to the server (the GL
	// library's), which only know the window once this connection's requests
	// have reached the server.
	XSync(_display, False);

	// The window itself is the drawable: it is the one that gets mapped.
	*drawable = (void*) (uintptr_t) _window;
	return kCGSErrorSuccess;
}

-(BOOL) isDisplayOverlay
{
	return _displayOverlay;
}

// The overlay is on the screen: the keyboard focus goes to it (it is override-redirect, so the window manager
// does not give it any), and a pointer grab the application wanted for it that could not be taken before is
// taken now. The pointer is reached on the main thread, where its events are handled.
-(void) _displayOverlayShown
{
	if (![NSThread isMainThread])
	{
		[self performSelectorOnMainThread: _cmd withObject: nil waitUntilDone: YES];
		return;
	}
	XSetInputFocus(_display, _window, RevertToPointerRoot, CurrentTime);
	XFlush(_display);
	[_x11Connection pointerWindowsChanged];
}

-(CGError) moveTo:(const CGPoint*) point
{
	if (point == NULL)
		return kCGErrorIllegalArgument;

	XMoveWindow(_display, _window, lround(point->x), lround(point->y));
	// The UI layer of a toplevel window keeps its size hints.
	if (!_toplevel)
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
	// The UI layer of a toplevel window keeps its size hints and draws its pixels itself.
	if (_toplevel)
		return kCGSErrorSuccess;
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
	if (!_toplevel)
	{
		[self presentRect: CGRectMake(event->x, event->y, event->width, event->height)];
		return;
	}

	// The UI layer draws the window itself: it hears of the repaint once the window system has reported all of
	// the areas of a series, as their union.
	CGRect area = CGRectMake(event->x, event->y, event->width, event->height);
	if (_hasPendingExpose)
		area = CGRectUnion(_pendingExpose, area);
	if (event->count != 0)
	{
		_pendingExpose = area;
		_hasPendingExpose = YES;
		return;
	}
	_hasPendingExpose = NO;

	CGFloat scale = _toplevelScale;
	CGSToplevelEvent report = {
		.kind = kCGSToplevelEventExposed,
		.rect = CGRectMake(area.origin.x / scale, area.origin.y / scale, area.size.width / scale, area.size.height / scale),
	};
	[self postToplevelEvent: &report];
}

// The window can be destroyed while its configure event is handled.
static XErrorHandler g_previousErrorHandler;
static int ignoreBadWindow(Display* display, XErrorEvent* errorEvent)
{
	if (errorEvent->error_code == BadWindow || g_previousErrorHandler == NULL)
		return 0;
	return g_previousErrorHandler(display, errorEvent);
}

-(void) windowSystemDidConfigure
{
	if (_toplevel)
	{
		[self _toplevelDidConfigure];
		return;
	}

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

#pragma mark - Toplevel windows of the UI layer

+(BOOL) translucentVisualAvailableOnDisplay:(Display*) display
{
	return translucentToplevelVisualInfo(display) != NULL;
}

-(BOOL) isToplevel
{
	return _toplevel;
}

-(XVisualInfo*) visualInfo
{
	return _visualInfo;
}

-(instancetype) initToplevelWithAttributes:(const CGSToplevelAttributes*) attributes
								connection:(CGSConnection*) connection
								  windowID:(CGSWindowID) windowID
{
	self = [super initWithRegion: NULL connection: connection windowID: windowID];
	if (self == nil)
		return nil;

	_x11Connection = (CGSConnectionX11*) connection;
	_display = _x11Connection->_display;
	_toplevel = YES;
	_toplevelScale = (CGFloat) _CGSDisplayBackingScaleFactor(CGMainDisplayID());

	if (_display == NULL || ![self _makeNativeToplevelWithAttributes: attributes])
	{
		[self release];
		return nil;
	}
	return self;
}

// The extent in device pixels of one extent in points: rounded to the nearest pixel, and at least one pixel,
// as a zero-sized X window is invalid. The origin is rounded the same way, so that the window and what is
// drawn into it agree.
static CGFloat toplevelDeviceOrigin(CGFloat points, CGFloat scale)
{
	return floor(points * scale + 0.5);
}

static CGFloat toplevelDeviceExtent(CGFloat points, CGFloat scale)
{
	return fmax(toplevelDeviceOrigin(points, scale), 1.0);
}

// The main monitor's rectangle on the root window, in points.
-(X11Frame) _primaryRootInPoints
{
	X11Frame primary = [_x11Connection _primaryRoot];
	CGFloat scale = _toplevelScale;
	return (X11Frame){primary.x / scale, primary.y / scale, primary.width / scale, primary.height / scale};
}

// A frame in the application's global space (points, y up, the origin at the bottom left of the main
// display) as a rectangle on the root window (points, y down), at least a point in each extent.
-(CGRect) _rootPointsForFrame:(CGRect) frame
{
	X11Frame root = X11FrameToRoot([self _primaryRootInPoints], (X11Frame){frame.origin.x, frame.origin.y,
		frame.size.width, frame.size.height});
	return CGRectMake(root.x, root.y, fmax(root.width, 1.0), fmax(root.height, 1.0));
}

// The inverse of -_rootPointsForFrame:.
-(CGRect) _frameForRootPoints:(CGRect) root
{
	X11Frame frame = X11FrameFromRoot([self _primaryRootInPoints], (X11Frame){root.origin.x, root.origin.y,
		root.size.width, root.size.height});
	return CGRectMake(frame.x, frame.y, frame.width, frame.height);
}

// The rectangle on the root window in device pixels.
-(CGRect) _deviceRectForRootPoints:(CGRect) root
{
	CGFloat scale = _toplevelScale;
	return CGRectMake(toplevelDeviceOrigin(root.origin.x, scale), toplevelDeviceOrigin(root.origin.y, scale),
		toplevelDeviceExtent(root.size.width, scale), toplevelDeviceExtent(root.size.height, scale));
}

-(CGRect) _deviceRectForToplevelFrame:(CGRect) frame
{
	return [self _deviceRectForRootPoints: [self _rootPointsForFrame: frame]];
}

-(CGRect) toplevelFrame
{
	return _toplevel ? [self _frameForRootPoints: _toplevelRoot] : CGRectNull;
}

-(CGFloat) toplevelBackingScaleFactor
{
	return _toplevel ? _toplevelScale : 1;
}

-(CGRect) toplevelDeviceRectForFrame:(CGRect) frame
{
	return [self _deviceRectForToplevelFrame: frame];
}

-(CGSize) toplevelDeviceSizeForSize:(CGSize) size
{
	return CGSizeMake(toplevelDeviceExtent(size.width, _toplevelScale), toplevelDeviceExtent(size.height, _toplevelScale));
}

-(CGRect) toplevelDeviceRectForRect:(CGRect) rect
{
	CGFloat scale = _toplevelScale;
	CGSize size = [self toplevelDeviceSizeForSize: rect.size];
	return CGRectMake(toplevelDeviceOrigin(rect.origin.x, scale), toplevelDeviceOrigin(rect.origin.y, scale),
		size.width, size.height);
}

// Makes the native window of the attributes, and when there is one already moves its children to the new one
// and destroys it. NO, with the old window kept, when no visual can be found.
-(BOOL) _makeNativeToplevelWithAttributes:(const CGSToplevelAttributes*) attributes
{
	BOOL translucent = attributes->translucent && translucentToplevelVisualInfo(_display) != NULL;
	XVisualInfo* visualInfo = translucent ? translucentToplevelVisualInfo(_display) : opaqueToplevelVisualInfo(_display);
	if (visualInfo == NULL)
		return NO;

	XSetWindowAttributes xattr;
	xattr.override_redirect = attributes->unmanaged ? True : False;
	xattr.border_pixel = 0;
	xattr.colormap = XCreateColormap(_display, RootWindow(_display, visualInfo->screen), visualInfo->visual, AllocNone);
	// A window of another depth than its parent needs a border pixel of its own, or creating it fails with
	// BadMatch.
	unsigned long mask = CWOverrideRedirect | CWColormap | (translucent ? CWBorderPixel : 0);

	CGRect root = [self _rootPointsForFrame: attributes->frame];
	CGRect device = [self _deviceRectForRootPoints: root];
	Window window = XCreateWindow(_display, DefaultRootWindow(_display), (int) device.origin.x, (int) device.origin.y,
		(unsigned) device.size.width, (unsigned) device.size.height, 0, visualInfo->depth, InputOutput,
		visualInfo->visual, mask, &xattr);

	// The window's frame, the repaints it is asked for, the keyboard focus and the window manager's state of
	// the window are reported to the UI layer (its own selection of input replaces this one, and includes it).
	XSelectInput(_display, window, StructureNotifyMask | ExposureMask | FocusChangeMask | PropertyChangeMask);

	// The window manager asks the window to close with a message instead of destroying it.
	Atom deleteWindow = XInternAtom(_display, "WM_DELETE_WINDOW", False);
	XSetWMProtocols(_display, window, &deleteWindow, 1);

	const char* name = [[[NSProcessInfo processInfo] processName] UTF8String];
	XClassHint classHint = {.res_name = (char*) name, .res_class = (char*) name};
	XSetClassHint(_display, window, &classHint);

	// _NET_WM_PID and WM_CLIENT_MACHINE, so that other clients, and other Darling processes listing windows,
	// know whose window this is.
	X11WindowOwnerPublish(_display, window);
	X11WindowOwnerPublishWindowID(_display, window, (unsigned) [self windowId]);

	// Until the first frame, a translucent window shows its background: make that transparent rather than
	// black.
	if (translucent)
		XSetWindowBackground(_display, window, 0);
	else
		XSetWindowBackgroundPixmap(_display, window, None);

	Window old = _window;
	if (old != None)
	{
		Window root, parent, *children = NULL;
		unsigned int count = 0;
		if (XQueryTree(_display, old, &root, &parent, &children, &count))
		{
			for (unsigned int i = 0; i < count; i++)
			{
				XWindowAttributes childAttributes;
				if (XGetWindowAttributes(_display, children[i], &childAttributes))
					XReparentWindow(_display, children[i], window, childAttributes.x, childAttributes.y);
			}
			if (children != NULL)
				XFree(children);
		}
		// The input context belongs to the X window it was made for.
		[_inputContext destroy];
		XDestroyWindow(_display, old);
		// The old colormap stays: the children that moved may still have it.
	}

	_window = window;
	_visualInfo = visualInfo;
	_colormap = xattr.colormap;
	_toplevelUnmanaged = attributes->unmanaged;
	_toplevelRoot = root;

	// The new window has no shape, opaque region, input region or manager hints yet, is not shown and has
	// received no expose event.
	if (_holdsMenuInput)
		[(CGSConnectionX11*) _connection menuWindowHidden: self];
	_toplevelShown = NO;
	_hasPendingExpose = NO;
	_opaqueRegionSize = CGSizeZero;
	_roundedShapeSet = NO;
	_shapeEmpty = NO;
	_ignoresMouse = NO;
	[self _applyApplicationMenu];
	_skipsTaskList = NO;
	_wantsInputFocus = NO;
	_fullscreenRequested = NO;
	_fullscreenReported = NO;
	_miniaturizedKnown = NO;
	_occluded = NO;
	_configureKnown = NO;
	[self _refreshToplevelShapes];
	// A window that takes drops is a target on its new X window as well.
	if (_dragDestination != nil)
		[self dragDestinationChanged];
	// So does the input method: its context is made for the new X window.
	[_inputContext create];
	XFlush(_display);
	[_x11Connection _toplevelWindowCreated];
	return YES;
}

// The window uses the input method, or no more (see CGSInputMethod.h).
-(void) inputMethodEnabledChanged
{
	if (_x11Connection == nil)
		return;
	if (_inputMethodEnabled)
	{
		if (_inputContext == nil)
			_inputContext = [[CGSX11InputContext alloc] initWithWindow: self method: [_x11Connection _inputMethod]];
		[_inputContext create];
	}
	else
	{
		[_inputContext destroy];
		[_inputContext release];
		_inputContext = nil;
	}
}

-(void) inputMethodFocusChanged:(BOOL) gained
{
	[_inputContext setFocused: gained];
}

-(void) inputMethodCursorRectChanged
{
	[_inputContext updateSpot];
}

-(NSString*) inputMethodTextForKeyEvent:(XKeyEvent*) event keySym:(KeySym*) keySym
{
	return [_inputContext textForKeyEvent: event keySym: keySym];
}

// The window takes drops (XDND), or no more.
-(void) dragDestinationChanged
{
	if (_x11Connection != nil && _window != None)
		[[_x11Connection _drag] windowDestinationChanged: self];
}

-(CGError) recreateToplevelWithAttributes:(const CGSToplevelAttributes*) attributes
{
	if (!_toplevel || attributes == NULL)
		return kCGErrorIllegalArgument;
	return [self _makeNativeToplevelWithAttributes: attributes] ? kCGSErrorSuccess : kCGErrorFailure;
}

-(CGError) setToplevelFrame:(CGRect) frame
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;

	_toplevelRoot = [self _rootPointsForFrame: frame];
	[self _placeToplevel];
	return kCGSErrorSuccess;
}

// Puts the window on its frame (kept in points, so at the current scale), and what depends on its size with it.
-(void) _placeToplevel
{
	CGRect device = [self _deviceRectForRootPoints: _toplevelRoot];
	XMoveResizeWindow(_display, _window, (int) device.origin.x, (int) device.origin.y,
		(unsigned) device.size.width, (unsigned) device.size.height);
	[self _refreshToplevelShapes];
	XFlush(_display);
}

// ICCCM 4.1.2.3 minimum and maximum sizes, in device pixels. A minimum of zero and a maximum of zero or too
// large for a window are no limit, and a limit is hinted only when it applies in some dimension.
-(CGError) setToplevelMinimumSize:(CGSize) minimum maximumSize:(CGSize) maximum
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;

	const CGFloat largest = 65535;
	CGFloat scale = _toplevelScale;
	CGSize deviceMinimum = CGSizeMake(toplevelDeviceExtent(minimum.width, scale), toplevelDeviceExtent(minimum.height, scale));
	CGSize deviceMaximum = CGSizeMake(toplevelDeviceExtent(maximum.width, scale), toplevelDeviceExtent(maximum.height, scale));

	XSizeHints* hints = XAllocSizeHints();
	if (hints == NULL)
		return kCGErrorFailure;
	hints->flags = 0;
	if (minimum.width > 0 || minimum.height > 0)
	{
		hints->flags |= PMinSize;
		hints->min_width = minimum.width > 0 ? (int) fmin(deviceMinimum.width, largest) : 1;
		hints->min_height = minimum.height > 0 ? (int) fmin(deviceMinimum.height, largest) : 1;
	}
	BOOL limitedWidth = maximum.width > 0 && deviceMaximum.width < largest;
	BOOL limitedHeight = maximum.height > 0 && deviceMaximum.height < largest;
	if (limitedWidth || limitedHeight)
	{
		hints->flags |= PMaxSize;
		// A maximum below the minimum would make the hints inconsistent.
		hints->max_width = limitedWidth ? (int) fmax(deviceMaximum.width, hints->min_width) : (int) largest;
		hints->max_height = limitedHeight ? (int) fmax(deviceMaximum.height, hints->min_height) : (int) largest;
	}

	// The program always gives a window an explicit frame, so every window the window manager manages
	// positions itself: say so, or the manager may place it as it likes, typically in the middle of the screen
	// or over its parent. The frame is the client window's own rectangle, so a move must put the client window,
	// not the window manager's frame around it, where the frame says: StaticGravity.
	if (!_toplevelUnmanaged)
	{
		hints->flags |= USPosition | PPosition | PWinGravity;
		hints->win_gravity = StaticGravity;
	}

	XSetWMSizeHints(_display, _window, hints, XA_WM_NORMAL_HINTS);
	XFree(hints);
	XFlush(_display);
	return kCGSErrorSuccess;
}

// The window's opacity through the EWMH _NET_WM_WINDOW_OPACITY property (a CARDINAL where 0xffffffff is fully
// opaque), which a compositing window manager applies.
-(CGError) setToplevelAlpha:(CGFloat) alpha
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;

	Atom opacity = XInternAtom(_display, "_NET_WM_WINDOW_OPACITY", False);
	if (alpha >= 1.0)
	{
		XDeleteProperty(_display, _window, opacity);
	}
	else
	{
		unsigned long cardinal = (unsigned long) (fmax(alpha, 0.0) * (double) 0xffffffffUL);
		XChangeProperty(_display, _window, opacity, XA_CARDINAL, 32, PropModeReplace,
			(unsigned char*) &cardinal, 1);
	}
	XFlush(_display);
	return kCGSErrorSuccess;
}

#pragma mark - What the window system reports of a toplevel window

-(void) windowSystemDidRequestClose
{
	CGSToplevelEvent report = {.kind = kCGSToplevelEventCloseRequested, .rect = CGRectNull};
	[self postToplevelEvent: &report];
}

// The window system placed or sized the window: its frame is read again, and it is reported with whether the
// size is another one.
-(void) _toplevelDidConfigure
{
	if (_window == None)
		return;

	g_previousErrorHandler = XSetErrorHandler(ignoreBadWindow);
	Window root, child;
	int x, y, rootX = 0, rootY = 0;
	unsigned int width, height, border, depth;
	BOOL known = XGetGeometry(_display, _window, &root, &x, &y, &width, &height, &border, &depth) &&
		XTranslateCoordinates(_display, _window, root, 0, 0, &rootX, &rootY, &child);
	XSetErrorHandler(g_previousErrorHandler);
	g_previousErrorHandler = NULL;
	if (!known)
		return;

	// The window system's pixels are the window's device pixels: the frame is kept in points.
	CGFloat scale = _toplevelScale;
	CGRect frame = CGRectMake(rootX / scale, rootY / scale, width / scale, height / scale);
	BOOL resized = !CGSizeEqualToSize(_toplevelRoot.size, frame.size);
	_toplevelRoot = frame;
	[self _refreshToplevelShapes];

	CGSToplevelEvent report = {
		.kind = kCGSToplevelEventFrameChanged,
		.rect = [self toplevelFrame],
		.resized = resized,
	};
	[self postToplevelEvent: &report];
}

// X11 has no event for a new backing scale: it is read again when the layout of the displays changed. The
// window keeps its size in points, so its pixels follow.
-(void) windowSystemLayoutChanged
{
	if (!_toplevel || _window == None)
		return;
	CGFloat scale = (CGFloat) _CGSDisplayBackingScaleFactor(CGMainDisplayID());
	if (scale == _toplevelScale)
		return;

	CGFloat oldScale = _toplevelScale;
	_toplevelScale = scale;
	[self _placeToplevel];

	CGSToplevelEvent report = {.kind = kCGSToplevelEventBackingScaleChanged, .rect = CGRectNull, .oldScale = oldScale};
	[self postToplevelEvent: &report];
}

#pragma mark - Ordering, levels, focus, miniaturizing and fullscreen

-(int) stackingLevel
{
	return _toplevelLevel;
}

-(BOOL) isUnmanaged
{
	return _toplevelUnmanaged;
}

// A menu and the menu bar are not stacked by level: they are shown by the window system as menus.
-(BOOL) takesPartInLevelStacking
{
	return _toplevel && _toplevelShown && _toplevelStacksByLevel && _window != None;
}

-(CGError) setToplevelLevel:(int) level
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if (level == _toplevelLevel)
		return kCGSErrorSuccess;
	_toplevelLevel = level;
	return [self restackToplevelForLevels];
}

-(CGError) setToplevelStacksByLevel:(BOOL) stacks
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	_toplevelStacksByLevel = stacks;
	return kCGSErrorSuccess;
}

-(CGError) restackToplevelForLevels
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if ([self takesPartInLevelStacking])
		[_x11Connection _restackToplevelWindowsForLevelsAround: self];
	return kCGSErrorSuccess;
}

// With a window manager the two client windows live in frames of their own and are not siblings, so a plain
// stacking request naming the other window as sibling is a BadMatch; XReconfigureWMWindow makes the ICCCM
// request for that case (a ConfigureRequest sent to the root window, which the window manager carries out for
// the frames).
-(CGError) _stackRelativeTo:(CGSWindow*) sibling mode:(int) mode
{
	if (![sibling isKindOfClass: [CGSWindowX11 class]] || ((CGSWindowX11*) sibling)->_window == None)
		return kCGErrorIllegalArgument;
	XWindowChanges changes;
	changes.sibling = ((CGSWindowX11*) sibling)->_window;
	changes.stack_mode = mode;
	XReconfigureWMWindow(_display, _window, DefaultScreen(_display), CWSibling | CWStackMode, &changes);
	return kCGSErrorSuccess;
}

-(CGError) orderToplevelAbove:(CGSWindow*) sibling
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if (sibling == nil)
		XRaiseWindow(_display, _window);
	else if ([self _stackRelativeTo: sibling mode: Above] != kCGSErrorSuccess)
		return kCGErrorIllegalArgument;
	return [self restackToplevelForLevels];
}

-(CGError) orderToplevelBelow:(CGSWindow*) sibling
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if (sibling == nil)
	{
		XLowerWindow(_display, _window);
		return kCGSErrorSuccess;
	}
	return [self _stackRelativeTo: sibling mode: Below];
}

// Without a window manager nothing moves X input focus: it stays PointerRoot, so key events went to whichever
// window was under the pointer and no window ever received FocusIn. Ask for focus explicitly: through the EWMH
// _NET_ACTIVE_WINDOW request when a window manager is running, otherwise with XSetInputFocus once the window
// is viewable.
-(void) _requestInputFocus
{
	Window focused;
	int revert;
	XGetInputFocus(_display, &focused, &revert);
	if (focused == _window)
	{
		_wantsInputFocus = NO;
		return;
	}

	if (X11WindowManagerIsRunning(_display))
	{
		XEvent event;
		memset(&event, 0, sizeof(event));
		event.xclient.type = ClientMessage;
		event.xclient.window = _window;
		event.xclient.message_type = XInternAtom(_display, "_NET_ACTIVE_WINDOW", False);
		event.xclient.format = 32;
		event.xclient.data.l[0] = 1; // source indication: application
		event.xclient.data.l[1] = CurrentTime;
		XSendEvent(_display, DefaultRootWindow(_display), False, SubstructureRedirectMask | SubstructureNotifyMask, &event);
		XFlush(_display);
		_wantsInputFocus = NO;
		return;
	}

	XWindowAttributes attributes;
	if (XGetWindowAttributes(_display, _window, &attributes) && attributes.map_state == IsViewable)
	{
		XSetInputFocus(_display, _window, RevertToPointerRoot, CurrentTime);
		// Send it now: an idle run loop may not flush Xlib's output buffer until the next event, so key
		// events typed meanwhile would still go to the old window.
		XFlush(_display);
		_wantsInputFocus = NO;
	}
	else
	{
		// Not viewable yet (the map request is still pending): retry on MapNotify.
		_wantsInputFocus = YES;
	}
}

-(CGError) requestToplevelKeyboardFocus
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	XRaiseWindow(_display, _window);
	[self restackToplevelForLevels];
	[self _requestInputFocus];
	return kCGSErrorSuccess;
}

-(void) cancelToplevelKeyboardFocusRequest
{
	_wantsInputFocus = NO;
}

-(BOOL) toplevelHoldsKeyboardFocus
{
	if (!_toplevel || _window == None)
		return NO;
	Window focused;
	int revert;
	XGetInputFocus(_display, &focused, &revert);
	return focused == _window;
}

-(void) windowSystemFocusChanged:(BOOL) gained
{
	CGSToplevelEvent report = {
		.kind = gained ? kCGSToplevelEventFocusGained : kCGSToplevelEventFocusLost,
		.rect = CGRectNull,
	};
	[self postToplevelEvent: &report];
}

-(void) windowSystemDidMap
{
	// The window manager has stacked the frame by now.
	[self restackToplevelForLevels];
	if (_wantsInputFocus)
		[self _requestInputFocus];
}

-(void) windowSystemDidReparent
{
	// A new frame is stacked by the window manager as it sees fit: the unmanaged windows that are meant to be
	// below it are put where they belong.
	[self restackToplevelForLevels];
}

-(CGError) miniaturizeToplevel
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	XIconifyWindow(_display, _window, DefaultScreen(_display));
	return kCGSErrorSuccess;
}

// ICCCM: a client asks to leave the iconic state by mapping its window again (raising an iconified window does
// not restore it).
-(CGError) deminiaturizeToplevel
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	XMapRaised(_display, _window);
	return kCGSErrorSuccess;
}

// The UI layer asks this of every window on each pass of the event loop, and reading the property is a round
// trip. The window selects PropertyChangeMask, so a change of _NET_WM_STATE, whoever makes it, arrives as an
// event that drops what was read.
-(BOOL) toplevelIsMiniaturized
{
	if (!_toplevel || _window == None)
		return NO;
	if (!_miniaturizedKnown)
	{
		_miniaturized = [self _readMiniaturized];
		_miniaturizedKnown = YES;
	}
	return _miniaturized;
}

-(BOOL) _readMiniaturized
{
	Atom wmState = XInternAtom(_display, "_NET_WM_STATE", False);
	Atom hiddenState = XInternAtom(_display, "_NET_WM_STATE_HIDDEN", False);

	Atom type;
	int format;
	unsigned long count, bytesAfter;
	unsigned char* properties = NULL;
	BOOL hidden = NO;

	if (XGetWindowProperty(_display, _window, wmState, 0, (~0L), False, XA_ATOM, &type, &format, &count, &bytesAfter,
		&properties) == Success)
	{
		Atom* atoms = (Atom*) properties;
		for (unsigned long i = 0; i < count; i++)
		{
			if (atoms[i] == hiddenState)
			{
				hidden = YES;
				break;
			}
		}
		XFree(properties);
	}
	return hidden;
}

-(BOOL) toplevelFrameCoversDisplay:(CGRect) frame
{
	if (!_toplevel)
		return NO;
	CGRect device = [self toplevelDeviceRectForFrame: frame];
	X11FullscreenRect rect = {(int) device.origin.x, (int) device.origin.y,
		(unsigned int) device.size.width, (unsigned int) device.size.height};
	return X11FullscreenRectIsMonitor(_display, rect);
}

-(CGError) setToplevelFullscreen:(BOOL) fullscreen force:(BOOL) force
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if (!_toplevelShown)
	{
		// A withdrawn window has no _NET_WM_STATE (EWMH): the window says, before it is mapped, what it is.
		long states[4];
		int count = 0;
		if (_skipsTaskList)
		{
			states[count++] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_TASKBAR", False);
			states[count++] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_PAGER", False);
		}
		if (_toplevelKind == kCGSToplevelKindDialog)
			states[count++] = (long) XInternAtom(_display, "_NET_WM_STATE_MODAL", False);
		if (fullscreen)
			states[count++] = (long) XInternAtom(_display, "_NET_WM_STATE_FULLSCREEN", False);
		XChangeProperty(_display, _window, XInternAtom(_display, "_NET_WM_STATE", False), XA_ATOM, 32, PropModeReplace,
			(const unsigned char*) states, count);
	}
	else if (force || fullscreen != _fullscreenRequested)
	{
		X11FullscreenRequest(_display, _window, fullscreen);
	}
	_fullscreenRequested = fullscreen;
	return kCGSErrorSuccess;
}

-(BOOL) toplevelFullscreenRequested
{
	return _fullscreenRequested;
}

-(BOOL) toplevelIsFullscreen
{
	return _toplevelShown && _fullscreenReported;
}

-(BOOL) toplevelIsOccluded
{
	return _occluded;
}

// The window manager changes _NET_WM_STATE on its own too (it leaves fullscreen on a keybinding), so it is
// followed: a later move onto the same monitor then asks again instead of trusting the last request. While the
// window is not shown the property is ours.
-(void) windowSystemStateChanged
{
	_miniaturizedKnown = NO;
	// The manager may have hidden or restored the window (_NET_WM_STATE_HIDDEN), whoever asked.
	BOOL miniaturized = [self toplevelIsMiniaturized];
	if (miniaturized != _miniaturizedReported)
	{
		_miniaturizedReported = miniaturized;
		CGSToplevelEvent report = {
			.kind = miniaturized ? kCGSToplevelEventMiniaturized : kCGSToplevelEventDeminiaturized,
			.rect = CGRectNull,
		};
		[self postToplevelEvent: &report];
	}
	CGSToplevelEvent occlusion = {.kind = kCGSToplevelEventOcclusionChanged, .rect = CGRectNull, .state = _occluded};
	[self postToplevelEvent: &occlusion];
	if (_toplevelShown)
	{
		_fullscreenRequested = X11FullscreenIsSet(_display, _window);
		CGSToplevelEvent state = {.kind = kCGSToplevelEventStateChanged, .rect = CGRectNull};
		[self postToplevelEvent: &state];
		if (_fullscreenRequested != _fullscreenReported)
		{
			_fullscreenReported = _fullscreenRequested;
			CGSToplevelEvent report = {
				.kind = kCGSToplevelEventFullscreenChanged,
				.rect = CGRectNull,
				.state = _fullscreenReported,
			};
			[self postToplevelEvent: &report];
		}
	}
}

-(BOOL) noteConfigureGeometryChanged:(const XConfigureEvent*) event
{
	if (_configureKnown && event->x == _configureX && event->y == _configureY &&
		event->width == _configureWidth && event->height == _configureHeight)
		return NO;
	_configureKnown = YES;
	_configureX = event->x;
	_configureY = event->y;
	_configureWidth = event->width;
	_configureHeight = event->height;
	return YES;
}

-(void) setOccludedByWindowSystem:(BOOL) occluded
{
	if (occluded == _occluded)
		return;
	_occluded = occluded;
	CGSToplevelEvent report = {.kind = kCGSToplevelEventOcclusionChanged, .rect = CGRectNull, .state = occluded};
	[self postToplevelEvent: &report];
}

#pragma mark - How a toplevel window looks to the window system

-(CGError) setToplevelHasShadow:(BOOL) hasShadow
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	// Only a compositing manager draws shadows, and it does so by its own rules.
	_hasShadow = hasShadow;
	return kCGSErrorSuccess;
}

// The window's rectangle in device pixels, which what is set on it follows.
-(CGSize) _toplevelDeviceSize
{
	return [self toplevelDeviceSizeForSize: _toplevelRoot.size];
}

// The promise to a compositing manager that all of an opaque window with an alpha channel is opaque, asked
// again when the opacity or the size changes; a request is made only for a change.
-(void) _applyOpaqueRegion
{
	if (_window == None || _visualInfo == NULL)
		return;
	CGSize device = [self _toplevelDeviceSize];
	CGSize wanted = X11OpaqueRegionApplies(_visualInfo->depth, _contentsOpaque) ? device : CGSizeZero;
	if (CGSizeEqualToSize(wanted, _opaqueRegionSize))
		return;
	X11WindowSetOpaqueRegion(_display, _window, _visualInfo->depth, _contentsOpaque, (int) device.width,
		(int) device.height);
	_opaqueRegionSize = wanted;
}

// The bounding shape follows the window's size and whether it has rounded corners; a window that has an
// empty shape keeps it.
-(void) _applyCornerShape
{
	if (_window == None || _shapeEmpty || (_cornerRadius <= 0 && !_roundedShapeSet))
		return;
	CGSize device = [self _toplevelDeviceSize];
	if (X11WindowSetRoundedCorners(_display, _window, (int) device.width, (int) device.height,
			_cornerRadius > 0 ? (int) lround(_cornerRadius * _toplevelScale) : 0))
		_roundedShapeSet = _cornerRadius > 0;
}

-(void) _refreshToplevelShapes
{
	[self _applyCornerShape];
	[self _applyOpaqueRegion];
}

-(CGError) setToplevelContentsOpaque:(BOOL) opaque
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	_contentsOpaque = opaque;
	[self _applyOpaqueRegion];
	return kCGSErrorSuccess;
}

-(CGError) setToplevelCornerRadius:(CGFloat) radius
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	_cornerRadius = radius;
	[self _applyCornerShape];
	return kCGSErrorSuccess;
}

-(CGError) setToplevelShapeEmpty:(BOOL) empty
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if (empty == _shapeEmpty)
		return kCGSErrorSuccess;
	if (!X11WindowSetBoundingEmpty(_display, _window, empty))
		return kCGErrorFailure;
	_shapeEmpty = empty;
	if (!empty)
		[self _applyCornerShape];
	return kCGSErrorSuccess;
}

-(BOOL) toplevelWindowSystemComposites
{
	return X11CompositorRunning(_display, DefaultScreen(_display));
}

-(CGError) setToplevelIgnoresMouseEvents:(BOOL) ignores
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if (ignores == _ignoresMouse)
		return kCGSErrorSuccess;
	if (!X11WindowSetIgnoresMouseEvents(_display, _window, ignores))
		return kCGErrorFailure;
	_ignoresMouse = ignores;
	XFlush(_display);
	return kCGSErrorSuccess;
}

// The frame of the window manager (the Motif hints' decorations; no hint leaves the choice to the manager).
-(CGError) setToplevelDecorated:(BOOL) decorated
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	Atom motif = XInternAtom(_display, "_MOTIF_WM_HINTS", False);
	if (decorated)
	{
		XDeleteProperty(_display, _window, motif);
		return kCGSErrorSuccess;
	}
	// flags 2: the decorations are given, and there are none
	long hints[5] = {2, 0, 0, 0, 0};
	XChangeProperty(_display, _window, motif, motif, 32, PropModeReplace, (const unsigned char*) hints, 5);
	return kCGSErrorSuccess;
}

// Atoms KDE reads to find the menu of a window.
#define APPMENU_SERVICE_NAME_PROPERTY "_KDE_NET_WM_APPMENU_SERVICE_NAME"
#define APPMENU_OBJECT_PATH_PROPERTY "_KDE_NET_WM_APPMENU_OBJECT_PATH"

-(void) _applyApplicationMenu
{
	if (!_toplevel || _window == None)
		return;
	Atom serviceAtom = XInternAtom(_display, APPMENU_SERVICE_NAME_PROPERTY, False);
	Atom pathAtom = XInternAtom(_display, APPMENU_OBJECT_PATH_PROPERTY, False);
	if (_menuService == nil || _menuPath == nil)
	{
		XDeleteProperty(_display, _window, serviceAtom);
		XDeleteProperty(_display, _window, pathAtom);
	}
	else
	{
		NSData* service = [_menuService dataUsingEncoding: NSUTF8StringEncoding];
		NSData* path = [_menuPath dataUsingEncoding: NSUTF8StringEncoding];
		XChangeProperty(_display, _window, serviceAtom, XA_STRING, 8, PropModeReplace, (const unsigned char*) [service bytes],
			(int) [service length]);
		XChangeProperty(_display, _window, pathAtom, XA_STRING, 8, PropModeReplace, (const unsigned char*) [path bytes],
			(int) [path length]);
	}
	XFlush(_display);
}

-(CGError) setToplevelApplicationMenuServiceName:(NSString*) service objectPath:(NSString*) path
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	[_menuService release];
	[_menuPath release];
	_menuService = [service copy];
	_menuPath = [path copy];
	[self _applyApplicationMenu];
	return kCGSErrorSuccess;
}

// The menu's window holds the pointer and the keyboard of the connection while it is shown (see
// -[CGSConnectionX11 menuWindowShown:]).
-(CGError) setToplevelHoldsInputForMenu:(BOOL) holds
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	if (holds == _holdsMenuInput)
		return kCGSErrorSuccess;
	_holdsMenuInput = holds;
	if (_toplevelShown)
	{
		if (holds)
			[(CGSConnectionX11*) _connection menuWindowShown: self];
		else
			[(CGSConnectionX11*) _connection menuWindowHidden: self];
	}
	return kCGSErrorSuccess;
}

// The title bar the window shows (see CGSToplevelTitlebarKind): the manager's frame for a standard one, none for the
// others, and the rounded corners of a window that has no frame because it shows no title bar of its own.
// QUIRK: macOS draws a titled window that shows no title bar of its own with rounded corners of about 5 points; the window
// manager draws none of that for a window it was asked not to decorate, so the corners are cut with the SHAPE extension,
// which needs no compositor. Evidence: black-box observation of such windows on macOS 10.14.4 (tier 2).
// Test: tests/coregraphics-x11-toplevel-decorations.sh (the corners of a hidden title bar are cut, those of the other kinds
// are not).
-(CGError) setToplevelTitlebarKind:(CGSToplevelTitlebarKind) kind
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;
	_titlebarKind = kind;
	CGError error = [self setToplevelDecorated: kind == kCGSToplevelTitlebarStandard];
	if (error == kCGSErrorSuccess)
		error = [self setToplevelCornerRadius: kind == kCGSToplevelTitlebarHidden ? kCGSToplevelHiddenTitlebarCornerRadius : 0];
	XFlush(_display);
	return error;
}

-(CGSToplevelTitlebarKind) toplevelTitlebarKind
{
	return _titlebarKind;
}

// The window manager frames a window the way the UI layer asked, whatever the preference.
-(CGError) setToplevelPrefersClientDecoration:(BOOL) prefers
{
	return _toplevel ? kCGSErrorSuccess : kCGErrorIllegalArgument;
}

// Whether the manager lists the atom in _NET_SUPPORTED on the root window (EWMH).
static BOOL X11ManagerSupports(Display* display, const char* name)
{
	Atom wanted = XInternAtom(display, name, False);
	Atom type;
	int format;
	unsigned long count, after;
	unsigned char* data = NULL;
	BOOL found = NO;
	if (XGetWindowProperty(display, DefaultRootWindow(display), XInternAtom(display, "_NET_SUPPORTED", False), 0, 4096, False,
						   XA_ATOM, &type, &format, &count, &after, &data) == Success &&
		data != NULL && type == XA_ATOM && format == 32)
	{
		Atom* atoms = (Atom*) data;
		for (unsigned long i = 0; i < count && !found; i++)
			found = atoms[i] == wanted;
	}
	if (data != NULL)
		XFree(data);
	return found;
}

// EWMH _NET_WM_MOVERESIZE. The pointer grab the press gave this client is released first, as EWMH asks, so that the
// button's release goes to the window manager.
-(CGError) beginToplevelMoveByWindowSystem
{
	if (!_toplevel || _window == None || _toplevelUnmanaged || !X11ManagerSupports(_display, "_NET_WM_MOVERESIZE"))
		return kCGErrorFailure;

	Window root, child;
	int rootX, rootY, winX, winY;
	unsigned int mask = 0;
	if (!XQueryPointer(_display, _window, &root, &child, &rootX, &rootY, &winX, &winY, &mask) || !(mask & Button1Mask))
		return kCGErrorFailure;

	XUngrabPointer(_display, CurrentTime);
	XEvent message = {0};
	message.xclient.type = ClientMessage;
	message.xclient.window = _window;
	message.xclient.message_type = XInternAtom(_display, "_NET_WM_MOVERESIZE", False);
	message.xclient.format = 32;
	message.xclient.data.l[0] = rootX;
	message.xclient.data.l[1] = rootY;
	message.xclient.data.l[2] = 8; // _NET_WM_MOVERESIZE_MOVE
	message.xclient.data.l[3] = Button1;
	message.xclient.data.l[4] = 1; // source indication: application
	XSendEvent(_display, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &message);
	XFlush(_display);
	return kCGSErrorSuccess;
}

// _NET_WM_ICON: for each icon its width and height and then its pixels, one long each, not premultiplied.
-(CGError) setToplevelIcons:(NSArray<NSData*>*) icons
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;

	NSMutableData* property = nil;
	for (NSData* icon in icons)
	{
		size_t count = [icon length] / sizeof(uint32_t);
		size_t side = (size_t) lround(sqrt((double) count));
		if (side == 0 || side * side != count)
			continue;
		if (property == nil)
			property = [NSMutableData data];

		long header[2] = {(long) side, (long) side};
		[property appendBytes: header length: sizeof(header)];
		NSMutableData* pixels = [NSMutableData dataWithLength: count * sizeof(long)];
		long* out = (long*) [pixels mutableBytes];
		const uint32_t* in = (const uint32_t*) [icon bytes];
		for (size_t p = 0; p < count; p++)
		{
			uint32_t argb = in[p];
			uint32_t alpha = argb >> 24;
			if (alpha != 0 && alpha != 255)
			{
				uint32_t red = MIN(255u, ((argb >> 16) & 0xff) * 255 / alpha);
				uint32_t green = MIN(255u, ((argb >> 8) & 0xff) * 255 / alpha);
				uint32_t blue = MIN(255u, (argb & 0xff) * 255 / alpha);
				argb = (alpha << 24) | (red << 16) | (green << 8) | blue;
			}
			out[p] = argb;
		}
		[property appendData: pixels];
	}

	Atom icon = XInternAtom(_display, "_NET_WM_ICON", False);
	if (property == nil)
		XDeleteProperty(_display, _window, icon);
	else
		XChangeProperty(_display, _window, icon, XInternAtom(_display, "CARDINAL", False), 32, PropModeReplace,
			(const unsigned char*) [property bytes], [property length] / sizeof(long));
	return kCGSErrorSuccess;
}

// What the window manager is told about the window: its type, its input hint and whether showing it gives it
// the focus (the user time 0 says no user action caused it, EWMH _NET_WM_USER_TIME), which window it belongs to,
// and whether it is in the task lists. A manager reads these when the window is mapped, and a window whose
// properties change while it is mapped is not asked to move or restack.
-(CGError) setToplevelHints:(const CGSToplevelHints*) hints
{
	if (!_toplevel || hints == NULL)
		return kCGErrorIllegalArgument;

	_toplevelKind = hints->kind;
	const char* windowType = "_NET_WM_WINDOW_TYPE_NORMAL";
	switch (hints->kind)
	{
		case kCGSToplevelKindUtility: windowType = "_NET_WM_WINDOW_TYPE_UTILITY"; break;
		case kCGSToplevelKindDialog: windowType = "_NET_WM_WINDOW_TYPE_DIALOG"; break;
		case kCGSToplevelKindDropdownMenu: windowType = "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU"; break;
		case kCGSToplevelKindPopupMenu: windowType = "_NET_WM_WINDOW_TYPE_POPUP_MENU"; break;
		case kCGSToplevelKindTooltip: windowType = "_NET_WM_WINDOW_TYPE_TOOLTIP"; break;
		case kCGSToplevelKindDock: windowType = "_NET_WM_WINDOW_TYPE_DOCK"; break;
		case kCGSToplevelKindNormal: break;
	}
	long windowTypeAtom = (long) XInternAtom(_display, windowType, False);
	XChangeProperty(_display, _window, XInternAtom(_display, "_NET_WM_WINDOW_TYPE", False), XA_ATOM, 32,
		PropModeReplace, (const unsigned char*) &windowTypeAtom, 1);

	CGSWindow* parent = hints->transientFor;
	if (parent != nil && [parent isKindOfClass: [CGSWindowX11 class]] && ((CGSWindowX11*) parent)->_window != None)
		XSetTransientForHint(_display, _window, ((CGSWindowX11*) parent)->_window);
	else
		XDeleteProperty(_display, _window, XA_WM_TRANSIENT_FOR);

	XWMHints wmHints = {0};
	wmHints.flags = InputHint;
	wmHints.input = hints->acceptsKeyboardInput ? True : False;
	XSetWMHints(_display, _window, &wmHints);

	Atom userTime = XInternAtom(_display, "_NET_WM_USER_TIME", False);
	if (!hints->takesFocusWhenShown)
	{
		unsigned long zero = 0;
		XChangeProperty(_display, _window, userTime, XA_CARDINAL, 32, PropModeReplace, (const unsigned char*) &zero, 1);
	}
	else
	{
		XDeleteProperty(_display, _window, userTime);
	}

	// The state of a window that is not shown yet is the UI layer's to write; the manager is asked to change
	// the state of a shown one.
	BOOL skip = hints->skipsTaskList;
	if (_toplevelShown && skip != _skipsTaskList && hints->kind != kCGSToplevelKindDock)
	{
		XEvent event = {0};
		event.xclient.type = ClientMessage;
		event.xclient.window = _window;
		event.xclient.message_type = XInternAtom(_display, "_NET_WM_STATE", False);
		event.xclient.format = 32;
		event.xclient.data.l[0] = skip ? 1 : 0; // add or remove
		event.xclient.data.l[1] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_TASKBAR", False);
		event.xclient.data.l[2] = (long) XInternAtom(_display, "_NET_WM_STATE_SKIP_PAGER", False);
		event.xclient.data.l[3] = 1; // source indication: application
		XSendEvent(_display, DefaultRootWindow(_display), False, SubstructureRedirectMask | SubstructureNotifyMask, &event);
	}
	_skipsTaskList = skip;
	XFlush(_display);
	return kCGSErrorSuccess;
}

// What a dock window tells the window manager before it is mapped: it is on every desktop, outside the
// taskbar and pager, above other windows, and reserves the strip it covers along the top edge of the screen
// (EWMH _NET_WM_STRUT_PARTIAL, and _NET_WM_STRUT for older managers).
-(CGError) reserveToplevelDockStrip
{
	if (!_toplevel)
		return kCGErrorIllegalArgument;

	long state[4] = {
		(long) XInternAtom(_display, "_NET_WM_STATE_STICKY", False),
		(long) XInternAtom(_display, "_NET_WM_STATE_ABOVE", False),
		(long) XInternAtom(_display, "_NET_WM_STATE_SKIP_TASKBAR", False),
		(long) XInternAtom(_display, "_NET_WM_STATE_SKIP_PAGER", False)};
	long desktop = (long) 0xFFFFFFFFul;
	long top = (long) (_toplevelRoot.origin.y + _toplevelRoot.size.height);
	long left = (long) _toplevelRoot.origin.x;
	long right = (long) (_toplevelRoot.origin.x + _toplevelRoot.size.width) - 1;
	long partial[12] = {0, 0, top, 0, 0, 0, 0, 0, left, right, 0, 0};
	long strut[4] = {0, 0, top, 0};

	XChangeProperty(_display, _window, XInternAtom(_display, "_NET_WM_STATE", False), XA_ATOM, 32, PropModeReplace,
		(const unsigned char*) state, 4);
	XChangeProperty(_display, _window, XInternAtom(_display, "_NET_WM_DESKTOP", False), XA_CARDINAL, 32,
		PropModeReplace, (const unsigned char*) &desktop, 1);
	XChangeProperty(_display, _window, XInternAtom(_display, "_NET_WM_STRUT_PARTIAL", False), XA_CARDINAL, 32,
		PropModeReplace, (const unsigned char*) partial, 12);
	XChangeProperty(_display, _window, XInternAtom(_display, "_NET_WM_STRUT", False), XA_CARDINAL, 32,
		PropModeReplace, (const unsigned char*) strut, 4);
	return kCGSErrorSuccess;
}

// The UI layer ends the window: the native window goes with its children, at once rather than when the last
// reference to this object is gone.
-(void) invalidate
{
	if (_holdsMenuInput)
		[(CGSConnectionX11*) _connection menuWindowHidden: self];
	if (_toplevel && _window != None)
	{
		@synchronized (_surfaces)
		{
			[_surfaces removeAllObjects];
		}
		[_inputContext destroy];
		XDestroyWindow(_display, _window);
		_window = None;
	}
	[super invalidate];
}

@end
