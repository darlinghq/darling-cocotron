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
#import "CGSConnectionX11.h"
#import "CGSWindowX11.h"
#import <CoreGraphics/CGSKeyboardLayout.h>
#import <CoreGraphics/CGSScreen.h>
#include "CarbonKeys.h"
#import "X11KeySymToUCS.h"
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>
#include <stdlib.h>
#include <stdatomic.h>
#import <X11/Xutil.h>
#import <X11/extensions/Xrandr.h>
#import <X11/XKBlib.h>
#import <X11/extensions/XKBrules.h>
// The main-monitor model and conversions shared with AppKit's X11 backend.
#import "X11Monitors.h"
#import "X11RandR.h"
#import "X11WindowOwner.h"
#import <CoreGraphics/CGWindowPrivate.h>
#import <CoreGraphics/CGWindowLevel.h>

// TODO: Use XInput2:
// https://stackoverflow.com/questions/44095001/getting-double-rawkeypress-events-using-xinput2
// https://github.com/openbsd/xenocara/blob/master/app/xinput/src/test_xi2.c

@implementation CGSConnectionX11

static int errorHandler(Display* display, XErrorEvent* errorEvent)
{
	NSLog(@"************** X11 ERROR!");
	NSLog(@"Request code: %d:%d", errorEvent->request_code, errorEvent->minor_code);
	NSLog(@"Error code: %d", errorEvent->error_code);
	return 0;
}

static void socketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address,
    const void *data, void *info)
{
    CGSConnectionX11* self = (CGSConnectionX11*) info;
    [self processPendingEvents];
}

-(instancetype) initWithConnectionID:(CGSConnectionID)connId
{
	// EGL and the run loop may use this Display from other threads, so Xlib
	// has to be made thread-safe before the first Xlib call. This connection
	// can be opened before AppKit opens its own.
	if (!XInitThreads())
	{
		NSLog(@"CGSConnectionX11: XInitThreads() failed\n");

		[self release];
		return nil;
	}

	// The server named by DISPLAY; with DISPLAY unset there is none.
	_display = XOpenDisplay(NULL);
	
	if (!_display)
	{
		NSLog(@"CGSConnectionX11: XOpenDisplay() failed\n");

		[self release];
		return nil;
	}
	self = [super initWithConnectionID: connId];

	if (NSDebugEnabled)
		XSynchronize(_display, True);

	XSetErrorHandler(errorHandler);

	int fd = ConnectionNumber(_display);

	// There's no need to retain/release the display,
    // because the display is guaranteed to outlive
    // the socket.
    CFSocketContext context = {
        .version = 0,
        .info = self,
        .retain = NULL,
        .release = NULL,
        .copyDescription = NULL
    };

    _cfSocket = CFSocketCreateWithNative(kCFAllocatorDefault, fd, kCFSocketReadCallBack, socketCallback, &context);
    _source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _cfSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

	int errorBase;
	if (XRRQueryExtension(_display, &_xrrEventBase, &errorBase))
	{
		// Sign up for XRandR events
		// TODO: Do we need all these?
		XRRSelectInput(_display, DefaultRootWindow(_display), RRScreenChangeNotifyMask | RROutputChangeNotifyMask | RRCrtcChangeNotifyMask);
	}

	int major = XkbMajorVersion, minor = XkbMinorVersion;

	if (XkbLibraryVersion(&major, &minor) && XkbQueryExtension(_display, NULL, &_xkbEventBase, &major, &minor, NULL))
	{
		XkbSelectEvents(_display, XkbUseCoreKbd, /*XkbMapNotifyMask |*/ XkbStateNotifyMask, 1);
	}

	return self;
}

-(void) dealloc
{
	// The windows destroy X11 windows on our display, so they have to go first.
	// -[CGSConnection dealloc] would only release _windows after this body.
	@synchronized (_windows)
	{
		[_windows removeAllObjects];
	}

	if (_display)
		XCloseDisplay(_display);

	CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

	if (_source != NULL)
		CFRelease(_source);
	if (_cfSocket != NULL)
		CFRelease(_cfSocket);

	[_keyboardLayout release];
	[_screens release];

	[super dealloc];
}

-(CGSKeyboardLayout*) createKeyboardLayout
{
	@synchronized (self)
	{
		if (!_keyboardLayout)
			[self _doCreateKeyboardLayout];
		return [_keyboardLayout retain];
	}
}

- (void) _doCreateKeyboardLayout
{
	int major = XkbMajorVersion, minor = XkbMinorVersion;
	XkbDescPtr pKBDesc;
	unsigned char group = 0;
	XkbStateRec state;

	struct MyLayout
	{
		UCKeyboardLayout layout;
		UCKeyModifiersToTableNum modifierVariants;
		UInt8 secondTableNum, thirdTableNum;
		UCKeyToCharTableIndex tableIndex;
		UInt32 secontTableOffset;
		UCKeyOutput table1[128];
		UCKeyOutput table2[128];
	};

	if (!XkbLibraryVersion(&major, &minor))
		return;
	if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
		return;

	pKBDesc = XkbGetMap(_display, XkbAllClientInfoMask, XkbUseCoreKbd);
	if (!pKBDesc)
		return;

	XkbDescPtr desc = XkbGetKeyboard(_display, XkbAllComponentsMask, XkbUseCoreKbd);
	if (!desc)
		return;

	if (XkbGetState(_display, XkbUseCoreKbd, &state) == Success)
		group = state.group;

	struct MyLayout* layout = (struct MyLayout*) malloc(sizeof(struct MyLayout));

	layout->layout.keyLayoutHeaderFormat = kUCKeyLayoutHeaderFormat;
	layout->layout.keyLayoutDataVersion = 0;
	layout->layout.keyLayoutFeatureInfoOffset = 0;
	layout->layout.keyboardTypeCount = 1;

	memset(layout->layout.keyboardTypeList, 0, sizeof(UCKeyboardTypeHeader));

	layout->layout.keyboardTypeList[0].keyModifiersToTableNumOffset = offsetof(struct MyLayout, modifierVariants);
	layout->layout.keyboardTypeList[0].keyToCharTableIndexOffset = offsetof(struct MyLayout, tableIndex);

	layout->modifierVariants.keyModifiersToTableNumFormat = kUCKeyModifiersToTableNumFormat;
	layout->modifierVariants.defaultTableNum = 0;
	layout->modifierVariants.modifiersCount = 3;
	layout->modifierVariants.tableNum[0] = 0;
	layout->modifierVariants.tableNum[1] = 0; // cmd key bit
	layout->modifierVariants.tableNum[2] = 1; // shift key bit

	layout->tableIndex.keyToCharTableIndexFormat = kUCKeyToCharTableIndexFormat;
	layout->tableIndex.keyToCharTableSize = 128;
	layout->tableIndex.keyToCharTableCount = 2;
	layout->tableIndex.keyToCharTableOffsets[0] = offsetof(struct MyLayout, table1);
	layout->tableIndex.keyToCharTableOffsets[1] = offsetof(struct MyLayout, table2);

	for (int shift = 0; shift <= 1; shift++)
	{
		UCKeyOutput* outTable = (shift == 0) ? layout->table1 : layout->table2;
		for (int i = 0; i < 128; i++)
		{
			// Reverse the operation we do in -postXEvent:
			const int x11KeyCode = carbonToX11[i];

			if (!x11KeyCode)
			{
				outTable[i] = 0;
				continue;
			}

			// NOTE: Not using the group here. It just works with 0 instead...
			KeySym sym = XkbKeycodeToKeysym(_display, x11KeyCode, 0, shift);

			if (sym != NoSymbol)
				outTable[i] = X11KeySymToUCS(sym);
			else
				outTable[i] = 0;
		}
	}

	XkbFreeClientMap(pKBDesc, XkbAllClientInfoMask, true);
	NSString *name = @"?", *fullName = @"?";

	if (fullName != NULL)
	{
		char *group = XGetAtomName(_display, desc->names->groups[state.group]);

		if (group != NULL)
		{
			fullName = [NSString stringWithUTF8String: group];
			XFree(group);
		}
	}

	XkbRF_VarDefsRec vd;
	if (name != NULL && XkbRF_GetNamesProp(_display, NULL, &vd))
	{
		char* saveptr;
		char *tok = strtok_r(vd.layout, ",", &saveptr);

		for (int i = 0; i < state.group; i++)
		{
			tok = strtok_r(NULL, ",", &saveptr);
			if (tok == NULL)
				break;
		}

		if (tok != NULL)
		{
			name = [NSString stringWithUTF8String: tok];
		}
	}

	CGSKeyboardLayout* cgsLayout = [CGSKeyboardLayout new];

	[cgsLayout setLayout: &layout->layout length: sizeof(struct MyLayout)];
	cgsLayout.name = name;
	cgsLayout.fullName = fullName;

	_keyboardLayout = cgsLayout;
	_keyboardLayoutGroup = state.group;
}

// The main monitor's rectangle in root coordinates. Without RandR, or with no
// active output, the root window stands in, as in AppKit's X11 backend.
-(X11Frame) _primaryRoot
{
	@synchronized (self)
	{
		if (!_primaryRootValid)
		{
			int screen = DefaultScreen(_display);
			_primaryRoot = (X11Frame){0, 0, DisplayWidth(_display, screen), DisplayHeight(_display, screen)};

			int count, mainIndex;
			X11Monitor* monitors = X11MonitorsCopy(_display, &count, &mainIndex);
			if (monitors != NULL && mainIndex >= 0)
				_primaryRoot = (X11Frame){monitors[mainIndex].x, monitors[mainIndex].y,
					monitors[mainIndex].width, monitors[mainIndex].height};
			free(monitors);

			_primaryRootValid = YES;
		}
		return _primaryRoot;
	}
}

// CoreGraphics' global space: origin at the main monitor's top-left corner, y
// down. It is the space of CGDisplayBounds() and CGWarpMouseCursorPosition(), so the
// pointer at a monitor's corner equals that corner of its bounds. X11 reports the pointer
// from the top-left of the root window; the main monitor's rectangle, which AppKit's
// X11 backend also reads, turns that into this space without using AppKit's Xlib
// connection from another thread.
// The window of an application inside a top-level window: the window itself
// unless a window manager has put it into a frame. ICCCM window managers mark
// application windows with WM_STATE.
static Window clientWindow(Display* display, Window window, Atom wmState, Atom netWmPid, int depth)
{
	Atom type;
	int format;
	unsigned long count, remaining;
	unsigned char* data = NULL;

	for (int i = 0; i < 2; i++)
	{
		Atom property = i == 0 ? wmState : netWmPid;
		if (property == None)
			continue;
		if (XGetWindowProperty(display, window, property, 0, 0, False, AnyPropertyType,
				&type, &format, &count, &remaining, &data) == Success)
		{
			if (data != NULL)
				XFree(data);
			data = NULL;
			if (type != None)
				return window;
		}
	}

	if (depth == 0)
		return None;

	Window root, parent, *children = NULL, result = None;
	unsigned int childCount = 0;
	if (!XQueryTree(display, window, &root, &parent, &children, &childCount))
		return None;
	for (int i = (int) childCount - 1; i >= 0 && result == None; i--)
		result = clientWindow(display, children[i], wmState, netWmPid, depth - 1);
	if (children != NULL)
		XFree(children);
	return result;
}

static NSString* copyWindowTitle(Display* display, Window window)
{
	Atom netWmName = XInternAtom(display, "_NET_WM_NAME", True);
	Atom utf8String = XInternAtom(display, "UTF8_STRING", True);
	Atom type;
	int format;
	unsigned long count, remaining;
	unsigned char* data = NULL;
	NSString* title = nil;

	if (netWmName != None && utf8String != None &&
		XGetWindowProperty(display, window, netWmName, 0, 1024, False, utf8String,
			&type, &format, &count, &remaining, &data) == Success &&
		data != NULL && type == utf8String && format == 8)
	{
		title = [[NSString alloc] initWithBytes: data length: count encoding: NSUTF8StringEncoding];
	}
	if (data != NULL)
		XFree(data);

	if (title == nil)
	{
		char* name = NULL;
		if (XFetchName(display, window, &name) && name != NULL)
		{
			title = [[NSString alloc] initWithUTF8String: name];
			XFree(name);
		}
	}
	return title;
}

static double windowOpacity(Display* display, Window window)
{
	Atom opacityAtom = XInternAtom(display, "_NET_WM_WINDOW_OPACITY", True);
	Atom type;
	int format;
	unsigned long count, remaining;
	unsigned char* data = NULL;
	double opacity = 1.0;

	if (opacityAtom != None &&
		XGetWindowProperty(display, window, opacityAtom, 0, 1, False, XA_CARDINAL,
			&type, &format, &count, &remaining, &data) == Success &&
		data != NULL && type == XA_CARDINAL && format == 32 && count == 1)
	{
		opacity = (double) (*(unsigned long*) data & 0xffffffffUL) / 0xffffffffUL;
	}
	if (data != NULL)
		XFree(data);
	return opacity;
}

-(NSArray<NSDictionary*>*) copyWindowDescriptions
{
	NSMutableArray<NSDictionary*>* result = [[NSMutableArray alloc] init];
	Window root = DefaultRootWindow(_display), rootReturn, parentReturn, *children = NULL;
	unsigned int count = 0;

	if (!XQueryTree(_display, root, &rootReturn, &parentReturn, &children, &count))
		return result;

	Atom wmState = XInternAtom(_display, "WM_STATE", True);
	Atom netWmPid = XInternAtom(_display, "_NET_WM_PID", True);
	X11Frame primary = [self _primaryRoot];
	pid_t self_pid = getpid();

	// XQueryTree lists the children bottom to top; the list is front to back.
	for (int i = (int) count - 1; i >= 0; i--)
	{
		Window client = clientWindow(_display, children[i], wmState, netWmPid, 2);
		if (client == None)
			continue;

		pid_t owner = X11WindowOwnerPID(_display, client);
		if (owner <= 0)
			continue;

		XWindowAttributes attributes;
		Window ignored;
		int x, y;
		if (!XGetWindowAttributes(_display, client, &attributes) ||
			!XTranslateCoordinates(_display, client, root, 0, 0, &x, &y, &ignored))
			continue;

		X11Point origin = X11CGPointFromRoot(primary, (X11Point){x, y});
		CGRect bounds = CGRectMake(origin.x, origin.y, attributes.width, attributes.height);
		CFDictionaryRef boundsDictionary = CGRectCreateDictionaryRepresentation(bounds);
		BOOL own = owner == self_pid;

		NSInteger number = own ? [CGWindow windowNumberForPlatformWindowID: client] : 0;
		if (number == 0)
			number = (NSInteger) client;

		NSMutableDictionary* description = [NSMutableDictionary dictionary];
		description[(NSString*) kCGWindowNumber] = @(number);
		description[(NSString*) kCGWindowOwnerPID] = @(owner);
		description[(NSString*) kCGWindowLayer] = @(attributes.override_redirect ? kCGPopUpMenuWindowLevel : kCGNormalWindowLevel);
		description[(NSString*) kCGWindowAlpha] = @(windowOpacity(_display, client));
		description[(NSString*) kCGWindowIsOnscreen] = @(attributes.map_state == IsViewable);
		description[(NSString*) kCGWindowStoreType] = @(kCGBackingStoreBuffered);
		// Capturing windows is not supported, so no window can be read.
		description[(NSString*) kCGWindowSharingState] = @(kCGWindowSharingNone);
		description[(NSString*) kCGWindowMemoryUsage] = @((long long) attributes.width * attributes.height * 4);
		if (boundsDictionary != NULL)
		{
			description[(NSString*) kCGWindowBounds] = (NSDictionary*) boundsDictionary;
			CFRelease(boundsDictionary);
		}

		XClassHint classHint = {NULL, NULL};
		if (XGetClassHint(_display, client, &classHint))
		{
			if (classHint.res_class != NULL)
				description[(NSString*) kCGWindowOwnerName] = [NSString stringWithUTF8String: classHint.res_class];
			XFree(classHint.res_name);
			XFree(classHint.res_class);
		}

		// Since macOS 10.15, the titles of other processes' windows are only
		// given to applications allowed to record the screen, which no
		// application is here.
		if (own)
		{
			NSString* title = copyWindowTitle(_display, client);
			if (title != nil)
				description[(NSString*) kCGWindowName] = title;
			[title release];
		}

		[result addObject: description];
	}

	if (children != NULL)
		XFree(children);
	return result;
}

-(void*) nativeDisplay
{
	// EGLNativeDisplayType on X11 is the Display itself.
	return _display;
}

-(CGPoint) mouseLocation
{
	Window child, root = DefaultRootWindow(_display);

    int root_x, root_y;
    int win_x, win_y;
    unsigned int mask;

    XQueryPointer(_display, root, &root, &child, &root_x, &root_y, &win_x, &win_y, &mask);

	X11Point point = X11CGPointFromRoot([self _primaryRoot], (X11Point){root_x, root_y});
	return CGPointMake(point.x, point.y);
}

-(BOOL) isKeyDown:(CGKeyCode)keyCode
{
	if (keyCode >= sizeof(carbonToX11) / sizeof(carbonToX11[0]))
		return NO;
	// Unmapped virtual key codes have no X key code (X key codes start at 8).
	const int x11KeyCode = carbonToX11[keyCode];
	if (x11KeyCode == 0)
		return NO;

	char keys[32];
	XQueryKeymap(_display, keys);
	return (keys[x11KeyCode / 8] & (1 << (x11KeyCode % 8))) != 0;
}

-(BOOL) isMouseButtonDown:(CGMouseButton)button
{
	unsigned int buttonMask;
	switch (button)
	{
		case kCGMouseButtonLeft:
			buttonMask = Button1Mask;
			break;
		case kCGMouseButtonCenter:
			buttonMask = Button2Mask;
			break;
		case kCGMouseButtonRight:
			buttonMask = Button3Mask;
			break;
		default:
			// X11 reports the state of the first five buttons only, and
			// buttons 4 and 5 are the scroll wheel.
			return NO;
	}

	Window child, root = DefaultRootWindow(_display);
	int root_x, root_y, win_x, win_y;
	unsigned int mask = 0;
	if (!XQueryPointer(_display, root, &root, &child, &root_x, &root_y, &win_x, &win_y, &mask))
		return NO;
	return (mask & buttonMask) != 0;
}

-(void) processXEvent:(XEvent*) event
{
	switch (event->type)
	{
		case KeyPress:
		case KeyRelease:
			break;
		case ButtonPress:
			break;
		case ButtonRelease:
			break;
		case MotionNotify:
			break;
		case EnterNotify:
			break;
		case FocusIn:
			break;
		case FocusOut:
			break;
		case KeymapNotify:
			break;
		case Expose:
			break;
		case ConfigureNotify:
			break;
		case ClientMessage:
		{
			static Atom wmDeleteWindowAtom;
			if (!wmDeleteWindowAtom)
				wmDeleteWindowAtom = XInternAtom(_display, "WM_DELETE_WINDOW", False);

			if (event->xclient.format == 32 && event->xclient.data.l[0] == wmDeleteWindowAtom)
				; // platformWindowWillClose
			break;
		}
		default:

		if (/*event->type == _xkbEventBase + XkbMapNotify ||*/ event->type == _xkbEventBase + XkbStateNotify)
		{
			XkbEvent* xkbevt = (XkbEvent*) event;
			// Invalidate cached keyboard layout information
			if (_keyboardLayout && _keyboardLayoutGroup != xkbevt->state.group)
			{
				// TODO: Emit kTISNotifySelectedKeyboardInputSourceChanged via NSDistributedNotificationCenter

				@synchronized (self)
				{
					[_keyboardLayout release];
					_keyboardLayout = nil;
				}
				_keyboardLayoutGroup = xkbevt->state.group;
			}

			break;
		}
		else if (X11RandRHandleLayoutChange(event, _xrrEventBase))
		{
			// Nothing is posted to the procs CGSRegisterNotifyProc() collected:
			// they live in g_cgsNotifyProc, which CGS.m keeps hidden, so a backend
			// bundle cannot reach them.
			// Invalidate cached information
			@synchronized (self)
			{
				[_screens release];
				_screens = nil;
				_primaryRootValid = NO;
			}
		}
	}
}

-(void) processPendingEvents
{
	while (XPending(_display) > 0)
	{
		XEvent event;

		if (XNextEvent(_display, &event) == Success)
			[self processXEvent: &event];
	}
}

// One CGSScreen per X11 screen. The one reader of this array,
// CGEventGetUnflippedLocation(), flips the y of -mouseLocation (CoreGraphics' global
// space, y down from the main monitor's top) against the first screen's height, so the
// default screen is described by the main monitor, and the others by their
// root window. The mode list is not rebuilt from RandR, because CGDisplayModeGet* reads
// AppKit's, which already walks it.
-(void) _doGetScreenInformation
{
	NSMutableArray* screens = [NSMutableArray array];

	for (int i = 0; i < ScreenCount(_display); i++)
	{
		Screen* screen = XScreenOfDisplay(_display, i);

		NSNumber* width = @(WidthOfScreen(screen));
		NSNumber* height = @(HeightOfScreen(screen));
		if (i == DefaultScreen(_display))
		{
			X11Frame primary = [self _primaryRoot];
			width = @(lround(primary.width));
			height = @(lround(primary.height));
		}

		CGSScreen* cgScreen = [CGSScreen new];
		cgScreen.modes = @[ @{
			@"Width": width,
			@"Height": height,
			@"Depth": @(DefaultDepthOfScreen(screen)),
			// Each X11 screen has a root window of its own, all at the origin of the
			// coordinate space -mouseLocation works in.
			@"OriginX": @0,
			@"OriginY": @0,
		}];
		cgScreen.currentMode = 0;
		[screens addObject: cgScreen];
		[cgScreen release];
	}

	// CGEventGetUnflippedLocation() reads screens[0] without checking, so an empty
	// array is worse than the nil it takes for "no answer".
	if ([screens count] > 0)
		_screens = [screens copy];
}

-(NSArray<CGSScreen*>*) createScreens
{
	@synchronized (self)
	{
		if (!_screens)
			[self _doGetScreenInformation];
		return [_screens retain];
	}
}

-(CGSWindow*) newWindow:(CGSRegionRef)region
{
	CGSWindowID windowID = _nextWindowId++;
	CGSWindowX11* window = [[CGSWindowX11 alloc] initWithRegion: region
		connection: self
		windowID: windowID];
	// A window that could not be created is reported by -[CGSWindowX11 init...];
	// CGSNewWindow() turns the nil into kCGErrorIllegalArgument.
	if (window == nil)
		return nil;

	@synchronized (_windows)
	{
		[_windows setObject: window forKey: [NSNumber numberWithInt: windowID]];
	}
	[window release];
	return window;
}

+(BOOL) isAvailable
{
	if (getenv("DISPLAY") != NULL)
		return YES;
	// TODO: we could be a little smarter here
	return NO;
}
@end
