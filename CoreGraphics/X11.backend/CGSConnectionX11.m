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
#import "X11DockSupport.h"
#import "CGSX11Keyboard.h"
#import "CGSX11Pointer.h"
#import "CGSX11Selection.h"
#import "CGSX11Drag.h"
#import <CoreGraphics/CGSKeyboardLayout.h>
#import <CoreGraphics/CGSScreen.h>
#import <CoreGraphics/CGSNativeConnection.h>
#include "CarbonKeys.h"
#import "../DarlingUnicodeKeyLayout.h"
#import "../DarlingUnicodeKeyLayoutCompose.h"
#import <CoreGraphics/CGSKeySymToUnicodePrivate.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>
#include <stdlib.h>
#include <time.h>
#include <stdatomic.h>
#include <poll.h>
#include <pthread.h>
#import <X11/Xutil.h>
#import "X11Xrandr.h"
#import <X11/XKBlib.h>
#import <X11/extensions/XKBrules.h>
// The main-monitor model and conversions shared with AppKit's X11 backend.
#import "X11Monitors.h"
#import "X11LevelStacking.h"
#import "X11Occlusion.h"
#import "X11WindowManager.h"
#import "X11RandR.h"
#import "X11WindowOwner.h"
#import "X11CursorTheme.h"
#import "X11HotKey.h"
#import <CoreGraphics/CGWindowPrivate.h>
#import <CoreGraphics/CGWindowLevel.h>

// TODO: Use XInput2:
// https://stackoverflow.com/questions/44095001/getting-double-rawkeypress-events-using-xinput2
// https://github.com/openbsd/xenocara/blob/master/app/xinput/src/test_xi2.c

// One registered global hot key
@interface X11HotKeyEntry : NSObject
{
@public
	int uid;
	CGKeyCode virtualKey;
	CGEventFlags flags;
	int keycode;
	unsigned modifiers;
	BOOL enabled;
}
@end

@implementation X11HotKeyEntry
@end

static NSNumber* grabKey(int keycode, unsigned modifiers)
{
	return [NSNumber numberWithUnsignedLongLong: ((unsigned long long) keycode << 32) | modifiers];
}

// The connection of this process, for the class methods that act on its behalf (not retained: it is
// cleared when the connection goes away).
static CGSConnectionX11* g_processConnection;
static pthread_mutex_t g_processConnectionLock = PTHREAD_MUTEX_INITIALIZER;

static CGSConnectionX11* processConnection(void)
{
	pthread_mutex_lock(&g_processConnectionLock);
	CGSConnectionX11* connection = [g_processConnection retain];
	pthread_mutex_unlock(&g_processConnectionLock);
	return [connection autorelease];
}

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

// Xlib reads events into its own queue whenever it waits for a reply, so events can be pending in
// Xlib while the connection has nothing left to read and the socket source never fires. Requests may
// also still sit in Xlib's output buffer. Flush and drain both before the main run loop goes to sleep;
// handling an event that posts something wakes the run loop again.
static void beforeWaitingCallback(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
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
	// The windows are judged for being covered once, when the first batch of events has been read.
	_occlusionDirty = YES;

	pthread_mutex_lock(&g_processConnectionLock);
	if (g_processConnection == nil)
		g_processConnection = self;
	pthread_mutex_unlock(&g_processConnectionLock);

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

	CFRunLoopObserverContext observerContext = { .version = 0, .info = self };
	_beforeWaitingObserver = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopBeforeWaiting, true, 0,
		beforeWaitingCallback, &observerContext);
	CFRunLoopAddObserver(CFRunLoopGetMain(), _beforeWaitingObserver, kCFRunLoopCommonModes);

	int errorBase;
	if (XRRQueryExtension(_display, &_xrrEventBase, &errorBase))
	{
		// Sign up for XRandR events
		// TODO: Do we need all these?
		XRRSelectInput(_display, DefaultRootWindow(_display), RRScreenChangeNotifyMask | RROutputChangeNotifyMask | RRCrtcChangeNotifyMask);
	}

	// The window manager names the focused window in _NET_ACTIVE_WINDOW of the root window, which is how a
	// change of the focus to another client is noticed (see -_activeWindowChanged). The framework that
	// builds windows on this connection selects nothing else on the root window and relies on this.
	XSelectInput(_display, DefaultRootWindow(_display), PropertyChangeMask);

	int major = XkbMajorVersion, minor = XkbMinorVersion;

	if (XkbLibraryVersion(&major, &minor) && XkbQueryExtension(_display, NULL, &_xkbEventBase, &major, &minor, NULL))
	{
		XkbSelectEvents(_display, XkbUseCoreKbd, XkbMapNotifyMask | XkbNewKeyboardNotifyMask | XkbStateNotifyMask, 1);

		// A held key reports its repeats as key presses without a release in between, which is what
		// tells the keyboard a press is a repeat (without it, every repeat is a release and a press).
		Bool supported = False;
		XkbSetDetectableAutoRepeat(_display, True, &supported);
		_detectableAutoRepeat = supported;
	}

	_keyboard = [[CGSX11Keyboard alloc] initWithConnection: self];
	_pointer = [[CGSX11Pointer alloc] initWithConnection: self];

	// The general pasteboard shows the CLIPBOARD selection. This goes before the process makes its first
	// pasteboard, which is why the connection does it, not the framework with the windows.
	[self _startHostClipboard];

	return self;
}

#pragma mark - Menu grabs

// Holds the pointer for the application while a menu is open, on the newest menu window. Relative mouse mode holds the
// pointer already; it is not disturbed, an open menu then only sees the pointer inside its windows. The observer's grab
// of its own (the pointer confined to a fullscreen window) is replaced, which it is told.
-(void) grabPointerForMenus
{
	if ([_openMenuWindows count] == 0 || _CGSNativeConnectionRelativeMouseState(NULL, NULL))
		return;
	Window target = ((CGSWindowX11*) [_openMenuWindows lastObject])->_window;
	if (target == None)
		return;
	id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
	if ([observer respondsToSelector: @selector(nativeConnectionMenuGrabChanged:)])
		[observer nativeConnectionMenuGrabChanged: YES];
	XGrabPointer(_display, target, True, ButtonPressMask | ButtonReleaseMask | PointerMotionMask, GrabModeAsync, GrabModeAsync,
		None, None, CurrentTime);
}

// Holds the keyboard for the application while a menu is open, so that its keys reach the menu whichever client has the
// input focus (an application that only owns the menu bar has none). The keys still go to the application's own windows
// while one has the focus (owner_events), and the focus events the grab causes are not taken for the focus moving.
-(void) grabKeyboardForMenus
{
	if ([_openMenuWindows count] == 0)
		return;
	Window target = ((CGSWindowX11*) [_openMenuWindows lastObject])->_window;
	if (target == None)
		return;
	XGrabKeyboard(_display, target, True, GrabModeAsync, GrabModeAsync, CurrentTime);
}

-(void) menuWindowShown:(CGSWindowX11*) window
{
	if (_openMenuWindows == nil)
		_openMenuWindows = [NSMutableArray new];
	[_openMenuWindows removeObjectIdenticalTo: window];
	[_openMenuWindows addObject: window];
	[self grabPointerForMenus];
	[self grabKeyboardForMenus];
	XFlush(_display);
}

-(void) menuWindowHidden:(CGSWindowX11*) window
{
	if ([_openMenuWindows indexOfObjectIdenticalTo: window] == NSNotFound)
		return;
	[_openMenuWindows removeObjectIdenticalTo: window];
	if ([_openMenuWindows count] > 0)
	{
		[self grabPointerForMenus];
		[self grabKeyboardForMenus];
		XFlush(_display);
		return;
	}
	XUngrabKeyboard(_display, CurrentTime);
	if (!_CGSNativeConnectionRelativeMouseState(NULL, NULL))
		XUngrabPointer(_display, CurrentTime);
	id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
	if ([observer respondsToSelector: @selector(nativeConnectionMenuGrabChanged:)])
		[observer nativeConnectionMenuGrabChanged: NO];
	XFlush(_display);
}

-(void) dealloc
{
	pthread_mutex_lock(&g_processConnectionLock);
	if (g_processConnection == self)
		g_processConnection = nil;
	pthread_mutex_unlock(&g_processConnectionLock);

	// The windows destroy X11 windows on our display, so they have to go first.
	// -[CGSConnection dealloc] would only release _windows after this body.
	@synchronized (_windows)
	{
		[_windows removeAllObjects];
	}
	// The input contexts of the windows are gone with them; the input method goes before XCloseDisplay().
	[_inputMethodSupport release];
	// Closing the display releases the grabs
	[_openMenuWindows release];
	[_hotKeys release];
	[_grabbedHotKeys release];
	[_pressedHotKeys release];

	// The observer uses the connection, so it goes before XCloseDisplay().
	if (_beforeWaitingObserver != NULL)
	{
		CFRunLoopObserverInvalidate(_beforeWaitingObserver);
		CFRelease(_beforeWaitingObserver);
	}

	if (_display)
	{
		if (_defaultArrow != None)
			XFreeCursor(_display, _defaultArrow);
		XCloseDisplay(_display);
	}

	CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

	if (_source != NULL)
		CFRelease(_source);
	if (_cfSocket != NULL)
		CFRelease(_cfSocket);

	[_keyboardLayout release];
	[_pointer release];
	[_keyboard release];
	[_dragSupport release];

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

// What the keyboard layout builder needs of the X server's keymap.
typedef struct {
	XkbDescPtr desc;
	unsigned group;
	unsigned optionMask; // the real modifier of the third level (ISO_Level3_Shift or Mode_switch)
} X11KeyLayoutContext;

static uint32_t X11KeyLayoutKeysym(void* context, int carbonKey, unsigned layer)
{
	X11KeyLayoutContext* keymap = context;
	const int x11KeyCode = carbonToX11[carbonKey];
	if (x11KeyCode == 0 || x11KeyCode < keymap->desc->min_key_code || x11KeyCode > keymap->desc->max_key_code)
		return 0;

	unsigned mods = 0;
	if (layer & DarlingKeyLayerShift)
		mods |= ShiftMask;
	if (layer & DarlingKeyLayerCaps)
		mods |= LockMask;
	if (layer & DarlingKeyLayerOption)
		mods |= keymap->optionMask;

	KeySym symbol = NoSymbol;
	unsigned consumed = 0;
	if (!XkbTranslateKeyCode(keymap->desc, x11KeyCode, XkbBuildCoreState(mods, keymap->group), &consumed, &symbol))
		return 0;
	return symbol == NoSymbol ? 0 : (uint32_t) symbol;
}

static uint32_t X11KeyLayoutCodepoint(void* context, uint32_t keysym)
{
	uint32_t codepoint = CGSKeySymToUnicode(keysym);
	return codepoint != 0 ? codepoint : DarlingUnicodeKeysymCharacter(keysym);
}

// The real modifier the keymap binds to the key that selects the third level (AltGr); Mod5 if none.
static unsigned X11ThirdLevelModifier(XkbDescPtr desc, unsigned group)
{
	for (int keycode = desc->min_key_code; keycode <= desc->max_key_code; keycode++)
	{
		KeySym symbol = XkbKeycodeToKeysym(desc->dpy, keycode, group, 0);
		if (symbol == XK_ISO_Level3_Shift || symbol == XK_Mode_switch)
		{
			unsigned mask = desc->map->modmap != NULL ? desc->map->modmap[keycode] : 0;
			if (mask != 0)
				return mask;
		}
	}
	return Mod5Mask;
}

- (void) _doCreateKeyboardLayout
{
	int major = XkbMajorVersion, minor = XkbMinorVersion;
	XkbStateRec state;

	if (!XkbLibraryVersion(&major, &minor))
		return;
	if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
		return;

	// The server side of the map (virtual modifiers) is what XkbTranslateKeyCode needs to pick
	// the level of a key for a modifier state.
	XkbDescPtr map = XkbGetMap(_display, XkbAllMapComponentsMask, XkbUseCoreKbd);
	if (!map)
		return;

	XkbDescPtr desc = XkbGetKeyboard(_display, XkbAllComponentsMask, XkbUseCoreKbd);
	if (!desc)
	{
		XkbFreeKeyboard(map, XkbAllMapComponentsMask, True);
		return;
	}

	memset(&state, 0, sizeof(state));
	XkbGetState(_display, XkbUseCoreKbd, &state);

	X11KeyLayoutContext keymap = { .desc = map, .group = state.group };
	keymap.optionMask = X11ThirdLevelModifier(map, keymap.group);
	DarlingKeyLayoutSource source = {
		.context = &keymap,
		.keysym = X11KeyLayoutKeysym,
		.codepoint = X11KeyLayoutCodepoint,
		.compose = DarlingComposeCharacters,
	};
	uint32_t layoutLength = 0;
	UCKeyboardLayout* layout = DarlingCreateUnicodeKeyLayout(&source, &layoutLength);
	XkbFreeKeyboard(map, XkbAllMapComponentsMask, True);
	if (layout == NULL)
	{
		XkbFreeKeyboard(desc, XkbAllComponentsMask, True);
		return;
	}

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

	[cgsLayout setLayout: layout length: layoutLength];
	free(layout);
	cgsLayout.name = name;
	cgsLayout.fullName = fullName;

	_keyboardLayout = cgsLayout;
	_keyboardLayoutGroup = state.group;
	XkbFreeKeyboard(desc, XkbAllComponentsMask, True);
}

static CGFloat backingScaleFactor(void);

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

			_primaryScale = backingScaleFactor();
			_primaryRootValid = YES;
		}
		return _primaryRoot;
	}
}

// A point in root coordinates (device pixels) in CoreGraphics' global space (points).
-(CGPoint) _cgPointFromRoot:(CGPoint)root
{
	X11Frame primary = [self _primaryRoot];
	CGFloat scale = _primaryScale;
	X11Point point = X11CGPointFromRoot(primary, (X11Point){root.x, root.y});
	return CGPointMake(point.x / scale, point.y / scale);
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

		// A window of a Darling process is listed under its CGS window id, which is the number its owner gives the
		// window (the UI layer's window number too): the owner published it on the window. A window that does not
		// say (one of the UI layer's that is not a CGS window, or of another program) has the id of its X window.
		CGSWindowX11* toplevel = own ? [self _cgsWindowForNativeWindow: client] : nil;
		NSInteger number = toplevel != nil ? (NSInteger) toplevel.windowId : (NSInteger) X11WindowOwnerWindowID(_display, client);
		if (number == 0 && own)
			number = [CGWindow windowNumberForPlatformWindowID: client];
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

+(CGSX11Pointer*) _processPointer
{
	pthread_mutex_lock(&g_processConnectionLock);
	CGSX11Pointer* pointer = g_processConnection != nil ? g_processConnection->_pointer : nil;
	pthread_mutex_unlock(&g_processConnectionLock);
	return pointer;
}

-(CGSWindowX11*) _cgsWindowForNativeWindow:(Window)native
{
	@synchronized (_windows)
	{
		for (NSNumber* key in _windows)
		{
			CGSWindow* window = [_windows objectForKey: key];

			if ([window isKindOfClass: [CGSWindowX11 class]] && ((CGSWindowX11*) window)->_window == native)
				return [[(CGSWindowX11*) window retain] autorelease];
		}
	}
	return nil;
}

// What the window system says about the CGS windows of this process: repaints (the window's own
// pixels are put on it again), and the close request, focus and bounds changes, which are reported
// to whoever asked for them (_CGSSetWindowEventProc). A toplevel window of the UI layer draws itself and
// has its own handler for the repaints, the close request and the changes of its frame (see
// -[CGSWindow setToplevelEventProc:info:]); its focus is the UI layer's.
-(void) _windowSystemEvent:(XEvent*) event
{
	switch (event->type)
	{
		case Expose:
		case ConfigureNotify:
		case ReparentNotify:
		case FocusIn:
		case FocusOut:
		case ClientMessage:
			break;
		default:
			return;
	}

	CGSWindowX11* window = [self _cgsWindowForNativeWindow: event->xany.window];
	if (window == nil)
		return;
	BOOL toplevel = [window isToplevel];

	switch (event->type)
	{
		case ReparentNotify:
			// A window manager frame has to point back at a window that takes drops through XdndProxy before a
			// drag source can find it under the pointer.
			if (_dragSupport != nil)
				[_dragSupport windowReparented: window intoParent: event->xreparent.parent];
			break;
		case Expose:
			[window windowSystemDidExpose: &event->xexpose];
			break;
		case ConfigureNotify:
			[window windowSystemDidConfigure];
			break;
		case FocusIn:
			if (!toplevel && event->xfocus.mode != NotifyGrab && event->xfocus.mode != NotifyUngrab &&
				event->xfocus.detail != NotifyPointer && event->xfocus.detail != NotifyPointerRoot &&
				event->xfocus.detail != NotifyInferior)
				_CGSPostWindowEvent(kCGSWindowEventActivated, window.windowId, CGRectNull);
			break;
		case FocusOut:
			if (!toplevel && event->xfocus.mode != NotifyGrab && event->xfocus.mode != NotifyUngrab &&
				event->xfocus.detail != NotifyPointer && event->xfocus.detail != NotifyPointerRoot &&
				event->xfocus.detail != NotifyInferior)
				_CGSPostWindowEvent(kCGSWindowEventDeactivated, window.windowId, CGRectNull);
			break;
		case ClientMessage:
		{
			Atom deleteWindow = XInternAtom(_display, "WM_DELETE_WINDOW", False);
			Atom ping = XInternAtom(_display, "_NET_WM_PING", False);
			if (event->xclient.format == 32 && (Atom) event->xclient.data.l[0] == deleteWindow)
			{
				if (toplevel)
					[window windowSystemDidRequestClose];
				else
					_CGSPostWindowEvent(kCGSWindowEventCloseRequested, window.windowId, CGRectNull);
			}
			else if (!toplevel && event->xclient.format == 32 && (Atom) event->xclient.data.l[0] == ping)
			{
				// The window manager asks whether the window is alive; it answers by getting the message
				// back on the root window. A window that does not answer is reported as not responding.
				XEvent reply = *event;
				reply.xclient.window = DefaultRootWindow(_display);
				XSendEvent(_display, DefaultRootWindow(_display), False, SubstructureNotifyMask | SubstructureRedirectMask, &reply);
				XFlush(_display);
			}
			break;
		}
	}
}

// The toplevel windows of the UI layer follow the backing scale the displays have now.
-(void) _toplevelWindowsLayoutChanged
{
	NSMutableArray* toplevels = [NSMutableArray array];
	@synchronized (_windows)
	{
		for (NSNumber* key in _windows)
		{
			CGSWindow* window = [_windows objectForKey: key];
			if ([window isKindOfClass: [CGSWindowX11 class]] && [(CGSWindowX11*) window isToplevel])
				[toplevels addObject: window];
		}
	}
	for (CGSWindowX11* window in toplevels)
		[window windowSystemLayoutChanged];
}

// The display overlay shown last, nil when there is none. Window ids grow with creation.
-(CGSWindowX11*) _displayOverlayWindow
{
	CGSWindowX11* found = nil;
	int foundID = 0;
	@synchronized (_windows)
	{
		for (NSNumber* key in _windows)
		{
			CGSWindow* window = [_windows objectForKey: key];

			if ([window isKindOfClass: [CGSWindowX11 class]] && [(CGSWindowX11*) window isDisplayOverlay] &&
				[key intValue] > foundID)
			{
				found = (CGSWindowX11*) window;
				foundID = [key intValue];
			}
		}
		return [[found retain] autorelease];
	}
}

-(BOOL) _isDisplayOverlayNativeWindow:(Window)native
{
	return [[self _cgsWindowForNativeWindow: native] isDisplayOverlay];
}

-(BOOL) isDisplayOverlayNativeWindow:(void*)nativeWindow
{
	return [self _isDisplayOverlayNativeWindow: (Window) (uintptr_t) nativeWindow];
}

-(CGSWindowID) _windowIDForNativeWindow:(Window)native
{
	@synchronized (_windows)
	{
		for (NSNumber* key in _windows)
		{
			CGSWindow* window = [_windows objectForKey: key];

			if ([window isKindOfClass: [CGSWindowX11 class]] && ((CGSWindowX11*) window)->_window == native)
				return (CGSWindowID) [key intValue];
		}
	}
	return 0;
}

-(void*) nativeDisplay
{
	// EGLNativeDisplayType on X11 is the Display itself.
	return _display;
}

-(CGPoint) mouseLocation
{
	// While the cursor is frozen (the mouse is not associated with it) that is where the cursor is.
	CGPoint frozen;
	if ([_pointer relativeMouseRequested: NULL frozenRoot: &frozen])
		return [self _cgPointFromRoot: frozen];

	int root_x = 0, root_y = 0;
	unsigned int mask;
	[_pointer getRootX: &root_x y: &root_y state: &mask];

	CGPoint point = [self _cgPointFromRoot: CGPointMake(root_x, root_y)];
	return CGPointMake(point.x, point.y);
}

-(uint64_t) modifierFlags
{
	return [_keyboard modifierFlags];
}

// The server's modifier state (the keyboard of the session, whichever client has the focus); the decoder's device
// bits are kept while it agrees with the server about which modifiers are down.
-(uint64_t) hardwareModifierFlags
{
	uint64_t decoded = [_keyboard modifierFlags];
	XkbStateRec state;
	if (XkbGetState(_display, XkbUseCoreKbd, &state) != Success)
		return decoded;
	uint64_t flags = [CGSX11Keyboard flagsForState: state.mods];
	const uint64_t modifiers = kCGEventFlagMaskShift | kCGEventFlagMaskControl | kCGEventFlagMaskAlphaShift |
		kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate | kCGEventFlagMaskSecondaryFn;
	return (decoded & modifiers) == flags ? decoded : flags;
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

	// Asked of the server every time: the buttons can change while another client has the pointer, which the
	// event stream does not report.
	Window child, root = DefaultRootWindow(_display);
	int root_x, root_y, win_x, win_y;
	unsigned int mask = 0;
	if (!XQueryPointer(_display, root, &root, &child, &root_x, &root_y, &win_x, &win_y, &mask))
		return NO;
	return (mask & buttonMask) != 0;
}

static NSArray<NSNumber*>* rootWindowList(Display* display, const char* name);

// _NET_ACTIVE_WINDOW changed: the process reports whether the focused window is one of its own, or that
// the focus went to another client (a Darling process or not). None says nothing: the focus is nowhere,
// as after the last window of a client closed.
-(void) _activeWindowChanged
{
	NSArray<NSNumber*>* active = rootWindowList(_display, "_NET_ACTIVE_WINDOW");

	if ([active count] == 0 || [active[0] unsignedLongValue] == None)
		return;
	BOOL ours = X11WindowOwnerPID(_display, (Window) [active[0] unsignedLongValue]) == getpid();
	_CGSNativeFocusReport(ours);
	// The application is no longer active when the focus is not in one of its toplevel windows (a
	// display overlay window of the process is not one).
	if ([self _toplevelForNativeWindow: (Window) [active[0] unsignedLongValue]] == nil)
	{
		id observer = [CGSConnection nativeObserver];
		if ([observer respondsToSelector: @selector(nativeConnectionFocusMovedToAnotherClient)])
			[observer nativeConnectionFocusMovedToAnotherClient];
	}
}

// Handles an event of this connection. Returns YES when the event was this connection's own business
// (a hot key, a keyboard layout or display layout change); the rest is the observer's. The keyboard also
// decodes the key events, the modifier state of the pointer events and the focus changes, and those go
// on to the observer.
-(BOOL) processXEvent:(XEvent*) event
{
	// The requests, replies and clears of the selections the process owns or reads, and the property changes
	// that pace their transfers, belong to the selections.
	if (CGSX11SelectionHandleEvent(event))
		return YES;
	// XDND is entirely ClientMessage traffic: XdndEnter, XdndPosition, XdndStatus, XdndDrop, XdndFinished and
	// XdndLeave.
	if (event->type == ClientMessage && _dragSupport != nil && [_dragSupport handleClientMessage: &event->xclient])
		return YES;
	[self _windowSystemEvent: event];
	[_pointer willHandleEvent: event];
	// Another client's window may cover one of ours; the events the judgement needs and nothing else is
	// interested in are not passed on.
	BOOL occlusionEvent = [self _noteOcclusionEvent: event];
	BOOL handled = [self _processXEvent: event];
	return handled || occlusionEvent;
}

-(BOOL) _processXEvent:(XEvent*) event
{
	switch (event->type)
	{
		case KeyPress:
		case KeyRelease:
			// The grabs of the hot keys are on the root window, and only they report key events
			// to it; the keys of the other windows are the observer's.
			if (event->xkey.window == DefaultRootWindow(_display))
			{
				[self _deliverHotKeyEvent: &event->xkey];
				return YES;
			}
			// The keyboard posts the key as a CGEvent. The observer is still told of the event: the
			// framework above keeps track of the events the server sent.
			[_keyboard keyEvent: event];
			break;
		// The events of the pointer carry the modifier state the server holds. The keyboard reports
		// a difference from what the keys said before the observer builds the pointer event, so
		// that the events keep their order. Events another client sent carry whatever state it chose.
		// The buttons and the motion are decoded into CGEvents after that (the observer is still told of
		// them: it keeps the pointer state and the crossings, and makes what it holds for itself).
		case ButtonPress:
		case ButtonRelease:
			if (!event->xany.send_event)
				[_keyboard resyncWithState: event->xbutton.state window: event->xbutton.window
					root: CGPointMake(event->xbutton.x_root, event->xbutton.y_root)];
			[_pointer pointerEvent: event];
			break;
		case MotionNotify:
			if (!event->xany.send_event)
				[_keyboard resyncWithState: event->xmotion.state window: event->xmotion.window
					root: CGPointMake(event->xmotion.x_root, event->xmotion.y_root)];
			[_pointer pointerEvent: event];
			break;
		case EnterNotify:
		case LeaveNotify:
			if (!event->xany.send_event)
				[_keyboard resyncWithState: event->xcrossing.state window: event->xcrossing.window
					root: CGPointMake(event->xcrossing.x_root, event->xcrossing.y_root)];
			[_pointer crossingEvent: event];
			break;
		case GenericEvent:
			// XInput2: the raw scroll valuators and the changes of the devices.
			if ([_pointer inputExtensionEvent: event])
				return YES;
			break;
		case FocusIn:
			// Focus changes caused by a grab, or by the pointer entering the window or one of its
			// children, do not move the keyboard focus.
			if (event->xfocus.mode != NotifyGrab && event->xfocus.mode != NotifyUngrab &&
				event->xfocus.detail != NotifyPointer && event->xfocus.detail != NotifyPointerRoot &&
				event->xfocus.detail != NotifyInferior)
			{
				[_keyboard focusGainedInWindow: event->xfocus.window];
				// The keyboard focus is in a window of the process (the framework that owns the windows is
				// told of the event after this, so the front process is up to date when it reacts).
				_CGSNativeFocusReport(YES);
			}
			[_pointer focusEvent: event];
			[self _inputMethodFocusEvent: event gained: YES];
			[self _toplevelFocusEvent: event gained: YES];
			break;
		case FocusOut:
			// Like FocusIn: grabs and the pointer entering the window do not move the keyboard focus.
			if (event->xfocus.mode != NotifyGrab && event->xfocus.mode != NotifyUngrab &&
				event->xfocus.detail != NotifyPointer && event->xfocus.detail != NotifyPointerRoot &&
				event->xfocus.detail != NotifyInferior)
				[_keyboard resetComposition];
			[_pointer focusEvent: event];
			[self _inputMethodFocusEvent: event gained: NO];
			[self _toplevelFocusEvent: event gained: NO];
			break;
		case PropertyNotify:
			if (event->xproperty.window == DefaultRootWindow(_display))
			{
				if (event->xproperty.atom == XInternAtom(_display, "_NET_ACTIVE_WINDOW", False))
					[self _activeWindowChanged];
			}
			else if (event->xproperty.atom == XInternAtom(_display, "_NET_WM_STATE", False))
			{
				// The manager hid, restored or fullscreened the window, whoever asked.
				[[self _toplevelForNativeWindow: event->xproperty.window] windowSystemStateChanged];
			}
			break;
		case MapNotify:
			// The manager has framed and stacked the window by now.
			[[self _toplevelForNativeWindow: event->xany.window] windowSystemDidMap];
			break;
		case ReparentNotify:
			// A new frame is stacked by the manager as it sees fit.
			[[self _toplevelForNativeWindow: event->xany.window] windowSystemDidReparent];
			break;
		case KeymapNotify:
			break;
		case Expose:
			break;
		case ConfigureNotify:
		case UnmapNotify:
			[_pointer windowEvent: event];
			break;
		case DestroyNotify:
			[_pointer windowDestroyed: event->xdestroywindow.window];
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

		if (event->type == _xkbEventBase)
		{
			// All XKB events share one event type; xkb_type tells them apart.
			XkbEvent* xkbevt = (XkbEvent*) event;
			BOOL keymapChanged = xkbevt->any.xkb_type == XkbMapNotify || xkbevt->any.xkb_type == XkbNewKeyboardNotify;
			BOOL groupChanged = xkbevt->any.xkb_type == XkbStateNotify && _keyboardLayoutGroup != xkbevt->state.group;

			// Invalidate cached keyboard layout information
			if (keymapChanged || groupChanged)
			{
				// A sequence in progress ends with the keymap that started it.
				[_keyboard resetComposition];
				// TODO: Emit kTISNotifySelectedKeyboardInputSourceChanged via NSDistributedNotificationCenter

				@synchronized (self)
				{
					[_keyboardLayout release];
					_keyboardLayout = nil;
				}
				if (groupChanged)
					_keyboardLayoutGroup = xkbevt->state.group;
			}

			return YES;
		}
		else if (X11RandRHandleLayoutChange(event, _xrrEventBase))
		{
			// RandR reports one change as several events; -processPendingEvents
			// looks at the layout once they are all read.
			_layoutChanged = YES;
			return YES;
		}
	}
	return NO;
}

#pragma mark - Ordering, levels and occlusion of the toplevel windows

-(NSArray<CGSWindowX11*>*) _toplevelWindows
{
	NSMutableArray<CGSWindowX11*>* toplevels = [NSMutableArray array];
	@synchronized (_windows)
	{
		for (NSNumber* key in _windows)
		{
			CGSWindow* window = [_windows objectForKey: key];
			if ([window isKindOfClass: [CGSWindowX11 class]] && [(CGSWindowX11*) window isToplevel])
				[toplevels addObject: (CGSWindowX11*) window];
		}
	}
	return toplevels;
}

-(void) _toplevelWindowCreated
{
	_occlusionDirty = YES;
}

-(CGSWindowX11*) _toplevelForNativeWindow:(Window) native
{
	CGSWindowX11* window = [self _cgsWindowForNativeWindow: native];
	return [window isToplevel] ? window : nil;
}

// The keyboard focus came to a window of the process or left it (a grab or the pointer passing over the window
// moves nothing): the window's input method follows it. Windows that are not toplevel windows have one too.
-(void) _inputMethodFocusEvent:(XEvent*) event gained:(BOOL) gained
{
	if (event->xfocus.mode == NotifyGrab || event->xfocus.mode == NotifyUngrab ||
		event->xfocus.detail == NotifyPointer || event->xfocus.detail == NotifyPointerRoot ||
		event->xfocus.detail == NotifyInferior)
		return;
	[[self _cgsWindowForNativeWindow: event->xfocus.window] inputMethodFocusChanged: gained];
}

// The window system's focus moved to or from a toplevel window; a grab or the pointer passing over the window
// moves nothing.
-(void) _toplevelFocusEvent:(XEvent*) event gained:(BOOL) gained
{
	if (event->xfocus.mode == NotifyGrab || event->xfocus.mode == NotifyUngrab ||
		event->xfocus.detail == NotifyPointer || event->xfocus.detail == NotifyPointerRoot ||
		event->xfocus.detail == NotifyInferior)
		return;
	[[self _toplevelForNativeWindow: event->xfocus.window] windowSystemFocusChanged: gained];
}

// Windows (a window manager's frame, when a window closes) can be destroyed while the tree is walked: XQueryTree
// then fails with BadWindow, which is no error there. Any other error goes to the handler that was installed
// before. The handler is swapped through the process-wide XSetErrorHandler and a file-scope variable, which is
// safe only because the connection and these methods are used from the main thread alone.
static XErrorHandler previousOrderingErrorHandler;

static int ignoreBadWindowWhileOrdering(Display* display, XErrorEvent* errorEvent)
{
	if (errorEvent->error_code == BadWindow)
		return 0;
	return previousOrderingErrorHandler != NULL ? previousOrderingErrorHandler(display, errorEvent) : 0;
}

// With a reparenting window manager the top-level windows are children of frame windows, so each root child is
// matched against our windows and their ancestors.
-(NSArray<NSNumber*>*) orderedToplevelWindowIDs
{
	NSMutableArray<NSNumber*>* result = [NSMutableArray array];
	NSMutableDictionary<NSNumber*, CGSWindowX11*>* byTopLevel = [NSMutableDictionary dictionary];
	Window root = DefaultRootWindow(_display);

	XErrorHandler previousHandler = XSetErrorHandler(ignoreBadWindowWhileOrdering);
	previousOrderingErrorHandler = previousHandler;
	@try
	{
		for (CGSWindowX11* window in [self _toplevelWindows])
		{
			Window w = window->_window;
			if (w == None)
				continue;
			Window rootRet, parent, *children = NULL;
			unsigned int count;

			// Walk up to the root's direct child that contains this window.
			while (XQueryTree(_display, w, &rootRet, &parent, &children, &count))
			{
				if (children)
					XFree(children);
				children = NULL;
				if (parent == root || parent == None)
					break;
				w = parent;
			}
			byTopLevel[@((unsigned long) w)] = window;
		}

		Window rootRet, parent, *children = NULL;
		unsigned int count = 0;
		if (XQueryTree(_display, root, &rootRet, &parent, &children, &count))
		{
			for (unsigned int i = count; i > 0; i--)
			{
				CGSWindowX11* window = byTopLevel[@((unsigned long) children[i - 1])];
				if (window != nil)
					[result addObject: @(window.windowId)];
			}
			if (children)
				XFree(children);
		}
	}
	@finally
	{
		XSetErrorHandler(previousHandler);
		previousOrderingErrorHandler = NULL;
	}
	return result;
}

// Called from the window code after it made its own request, and again when the window manager has framed and
// mapped a window (ReparentNotify, MapNotify), because it stacks a new frame by itself.
-(void) _restackToplevelWindowsForLevelsAround:(CGSWindowX11*) anchor
{
	if (![anchor takesPartInLevelStacking])
		return;

	XErrorHandler previousHandler = XSetErrorHandler(ignoreBadWindowWhileOrdering);
	previousOrderingErrorHandler = previousHandler;
	@try
	{
		BOOL anchorUnmanaged = [anchor isUnmanaged];
		Window anchorTop = X11TopLevelAncestor(_display, anchor->_window);

		for (CGSWindowX11* other in [self _toplevelWindows])
		{
			if (other == anchor || ![other takesPartInLevelStacking])
				continue;

			if (anchorUnmanaged && [other isUnmanaged])
			{
				// Two override-redirect windows (the menu bar and a borderless window that cannot become
				// key): the server stacks them in the order they were raised, so the level is applied here.
				Window otherTop = X11TopLevelAncestor(_display, other->_window);
				if (anchorTop == None || otherTop == None)
					continue;
				if (X11UnmanagedBelowUnmanaged([anchor stackingLevel], [other stackingLevel]))
					X11StackBelowIfAbove(_display, anchorTop, otherTop);
				else if (X11UnmanagedBelowUnmanaged([other stackingLevel], [anchor stackingLevel]))
					X11StackBelowIfAbove(_display, otherTop, anchorTop);
				continue;
			}
			if ([other isUnmanaged] == anchorUnmanaged)
				continue;

			CGSWindowX11* unmanaged = anchorUnmanaged ? anchor : other;
			CGSWindowX11* managed = anchorUnmanaged ? other : anchor;
			Window otherTop = X11TopLevelAncestor(_display, other->_window);
			Window unmanagedTop = anchorUnmanaged ? anchorTop : otherTop;
			Window managedTop = anchorUnmanaged ? otherTop : anchorTop;
			if (unmanagedTop == None || managedTop == None)
				continue;
			if (X11UnmanagedBelowManaged(anchorUnmanaged, [unmanaged stackingLevel], [managed stackingLevel]))
				X11StackBelowIfAbove(_display, unmanagedTop, managedTop);
			else if (!anchorUnmanaged && X11UnmanagedAboveManaged([unmanaged stackingLevel], [managed stackingLevel]))
				X11StackAboveIfBelow(_display, unmanagedTop, managedTop);
		}
	}
	@finally
	{
		XSetErrorHandler(previousHandler);
		previousOrderingErrorHandler = NULL;
	}
}

// Marks the occlusion state for a new judgement when the event can change it. Returns YES for the root window's
// and the watched foreign window's events, which nothing else is interested in. A ConfigureNotify that repeats
// the geometry of the previous one for the same window changes nothing, so it does not ask for a new judgement:
// a window manager may send one for every request that leaves the geometry as it was.
-(BOOL) _noteOcclusionEvent:(XEvent*) ev
{
	switch (ev->type)
	{
		case MapNotify:
		case UnmapNotify:
		case ConfigureNotify:
		case DestroyNotify:
		case PropertyNotify:
		case ReparentNotify:
		case GravityNotify:
		case CirculateNotify:
			break;
		default:
			return NO;
	}
	Window target = ev->xany.window;
	if (target == DefaultRootWindow(_display))
	{
		if (ev->type != PropertyNotify)
			return NO; // RandR notifications
		Atom atom = ev->xproperty.atom;
		if (atom == XInternAtom(_display, "_NET_ACTIVE_WINDOW", False))
		{
			_occlusionActiveKnown = NO;
			_occlusionDirty = YES;
		}
		else if (atom == XInternAtom(_display, "_NET_CLIENT_LIST_STACKING", False))
		{
			_occlusionDirty = YES;
		}
		return YES;
	}
	CGSWindowX11* window = [self _cgsWindowForNativeWindow: target];
	if (![window isToplevel])
		window = nil;
	if (window == nil)
	{
		if (target == None || target != _occlusionWatchWindow)
			return NO;
		if (ev->type == DestroyNotify)
		{
			_occlusionWatchWindow = None;
			_occlusionActiveKnown = NO;
		}
		if (ev->type == ConfigureNotify)
		{
			XConfigureEvent* c = &ev->xconfigure;
			if (_occlusionWatchGeometryKnown && c->x == _occlusionWatchX && c->y == _occlusionWatchY &&
				c->width == _occlusionWatchWidth && c->height == _occlusionWatchHeight)
				return YES;
			_occlusionWatchGeometryKnown = YES;
			_occlusionWatchX = c->x;
			_occlusionWatchY = c->y;
			_occlusionWatchWidth = c->width;
			_occlusionWatchHeight = c->height;
		}
		_occlusionCoverValid = NO;
		_occlusionDirty = YES;
		// A property deleted on that window may be the end of a transfer another part is waiting for.
		return !(ev->type == PropertyNotify && ev->xproperty.state == PropertyDelete);
	}
	switch (ev->type)
	{
		case MapNotify:
		case UnmapNotify:
			_occlusionDirty = YES;
			break;
		case ConfigureNotify:
			if ([window noteConfigureGeometryChanged: &ev->xconfigure])
				_occlusionDirty = YES;
			break;
	}
	return NO;
}

// Judges every toplevel window against the focused foreign window and tells the ones whose state changed.
-(void) _updateOcclusion
{
	_occlusionDirty = NO;
	Window root = DefaultRootWindow(_display);
	NSArray<CGSWindowX11*>* windows = [self _toplevelWindows];

	// The focused window and its geometry are read again only after an event that can change them.
	if (!_occlusionActiveKnown)
	{
		Window focused = X11OcclusionActiveWindow(_display);
		// The application's own windows never cover each other here. A window of the process that is none of
		// the UI layer's toplevel windows (a display overlay) is judged like another client's, but is never
		// watched (see below), which would replace its own selection of input.
		if ([self _toplevelForNativeWindow: focused] != nil)
			focused = None;
		else if ([self _cgsWindowForNativeWindow: focused] != nil && ![[self _cgsWindowForNativeWindow: focused] isDisplayOverlay])
			focused = None; // a window another framework made (CGSNewWindow)
		_occlusionActive = focused;
		_occlusionActiveKnown = YES;
		_occlusionCoverValid = NO;
		_occlusionWatchGeometryKnown = NO;
	}
	Window active = _occlusionActive;

	// Watch the focused foreign window for size, fullscreen and unmap changes. Selecting input replaces
	// this client's earlier selection on that window.
	if (active != _occlusionWatchWindow)
	{
		X11OcclusionStopWatching(_display, _occlusionWatchWindow, [self _cgsWindowForNativeWindow: _occlusionWatchWindow] != nil);
		_occlusionWatchWindow = active;
		if (active != None && [self _cgsWindowForNativeWindow: active] == nil)
			XSelectInput(_display, active, StructureNotifyMask | PropertyChangeMask);
	}

	X11FullscreenRect cover = {0};
	bool coverFullscreen = false, coverOpaque = false;
	unsigned long* stack = NULL;
	unsigned long stackCount = 0;
	if (active != None && [windows count] > 0)
	{
		if (!_occlusionCoverValid)
		{
			X11FullscreenRect info = {0};
			bool fullscreen = false, opaque = false;
			_occlusionCoverOK = X11OcclusionCoverInfo(_display, active, &info, &fullscreen, &opaque);
			_occlusionCoverX = info.x;
			_occlusionCoverY = info.y;
			_occlusionCoverWidth = info.width;
			_occlusionCoverHeight = info.height;
			_occlusionCoverFullscreen = fullscreen;
			_occlusionCoverOpaque = opaque;
			_occlusionCoverValid = YES;
		}
		cover = (X11FullscreenRect){_occlusionCoverX, _occlusionCoverY, _occlusionCoverWidth, _occlusionCoverHeight};
		coverFullscreen = _occlusionCoverFullscreen;
		coverOpaque = _occlusionCoverOpaque;
		if (_occlusionCoverOK && coverFullscreen && coverOpaque)
			stack = X11OcclusionStackingList(_display, &stackCount);
	}

	for (CGSWindowX11* window in windows)
	{
		Window handle = window->_window;
		BOOL occluded = NO;
		if (stack != NULL && handle != None)
		{
			XWindowAttributes attributes;
			Window child;
			int x, y;
			if (XGetWindowAttributes(_display, handle, &attributes) && attributes.map_state == IsViewable &&
				XTranslateCoordinates(_display, handle, root, 0, 0, &x, &y, &child))
			{
				X11FullscreenRect own = {x, y, (unsigned int) attributes.width, (unsigned int) attributes.height};
				occluded = X11OcclusionCovers(own, cover, coverFullscreen, coverOpaque,
					X11OcclusionStackIndex(stack, stackCount, handle),
					X11OcclusionStackIndex(stack, stackCount, active));
			}
		}
		[window setOccludedByWindowSystem: occluded];
	}
	if (stack != NULL)
		XFree(stack);
}

// A hot key reports while it is enabled and hot keys are not switched off
-(BOOL) _hotKeyIsActive:(X11HotKeyEntry*)entry
{
	return entry->enabled && _hotKeyOperatingMode == 0;
}

// Makes the grabs on the X server those of the active hot keys. Returns NO if a grab was
// refused. Called with the lock held.
-(BOOL) _updateHotKeyGrabs
{
	NSMutableSet* wanted = [NSMutableSet set];
	BOOL allGrabbed = YES;

	for (X11HotKeyEntry* entry in _hotKeys)
	{
		if (entry->keycode != 0 && [self _hotKeyIsActive: entry])
			[wanted addObject: grabKey(entry->keycode, entry->modifiers)];
	}
	if (!_grabbedHotKeys)
		_grabbedHotKeys = [[NSMutableSet alloc] init];

	for (NSNumber* key in [[_grabbedHotKeys copy] autorelease])
	{
		if (![wanted containsObject: key])
		{
			unsigned long long v = [key unsignedLongLongValue];
			X11HotKeyUngrab(_display, (int) (v >> 32), (unsigned) v);
			[_grabbedHotKeys removeObject: key];
		}
	}

	for (NSNumber* key in wanted)
	{
		if ([_grabbedHotKeys containsObject: key])
			continue;
		if (!_detectableAutoRepeat)
		{
			// Without it a held key reports a release and a press for every repeat
			Bool supported = False;
			XkbSetDetectableAutoRepeat(_display, True, &supported);
			_detectableAutoRepeat = supported;
		}
		unsigned long long v = [key unsignedLongLongValue];
		if (X11HotKeyGrab(_display, (int) (v >> 32), (unsigned) v) == X11HotKeyGrabbed)
			[_grabbedHotKeys addObject: key];
		else
			allGrabbed = NO;
	}
	return allGrabbed;
}

// The hot keys a grabbed key event selects are reported outside the lock, because the procs
// may set or remove hot keys. A release goes to the hot keys whose press was reported, even
// if the modifiers were let go before the key.
-(void) _deliverHotKeyEvent:(XKeyEvent*) event
{
	NSMutableArray* uids = nil;
	BOOL pressed = event->type == KeyPress;

	@synchronized (self)
	{
		for (X11HotKeyEntry* entry in _hotKeys)
		{
			if (entry->keycode == 0 || entry->keycode != (int) event->keycode)
				continue;

			NSNumber* uid = [NSNumber numberWithInt: entry->uid];
			// A press of a key already held down is its autorepeat (the detectable form), which is no new press
			if (pressed ? ([self _hotKeyIsActive: entry] && X11HotKeyMatches(event->state, entry->modifiers)
					&& ![_pressedHotKeys containsObject: uid])
				: [_pressedHotKeys containsObject: uid])
			{
				if (!uids)
					uids = [NSMutableArray array];
				[uids addObject: uid];
				if (pressed)
				{
					if (!_pressedHotKeys)
						_pressedHotKeys = [[NSMutableSet alloc] init];
					[_pressedHotKeys addObject: uid];
				}
				else
					[_pressedHotKeys removeObject: uid];
			}
		}
	}

	CGEventFlags flags = 0;
	if (event->state & ShiftMask)
		flags |= kCGEventFlagMaskShift;
	if (event->state & LockMask)
		flags |= kCGEventFlagMaskAlphaShift;
	if (event->state & ControlMask)
		flags |= kCGEventFlagMaskControl;
	if (event->state & Mod1Mask)
		flags |= kCGEventFlagMaskAlternate;
	if (event->state & Mod4Mask)
		flags |= kCGEventFlagMaskCommand;

	CGPoint point = [self _cgPointFromRoot: CGPointMake(event->x_root, event->y_root)];
	for (NSNumber* uid in uids)
	{
		[self postHotKeyEventForUID: [uid intValue] pressed: pressed flags: flags
			location: CGPointMake(point.x, point.y) time: clock_gettime_nsec_np(CLOCK_UPTIME_RAW)];
	}
}

-(X11HotKeyEntry*) _hotKeyWithUID:(int)uid
{
	for (X11HotKeyEntry* entry in _hotKeys)
	{
		if (entry->uid == uid)
			return entry;
	}
	return nil;
}

-(void) setHotKeyWithUID:(int)uid keyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags exclusion:(int)exclusion
{
	[self removeHotKeyWithUID: uid];

	X11HotKeyEntry* entry = [[X11HotKeyEntry alloc] init];
	entry->uid = uid;
	entry->virtualKey = keyCode;
	entry->flags = flags;
	// A virtual key code with no X key is kept without one: it is never grabbed and never fires
	entry->keycode = keyCode < sizeof(carbonToX11) / sizeof(carbonToX11[0]) ? carbonToX11[keyCode] : 0;
	entry->modifiers = X11HotKeyModifiers((flags & kCGEventFlagMaskShift) != 0,
		(flags & kCGEventFlagMaskControl) != 0, (flags & kCGEventFlagMaskAlternate) != 0,
		(flags & kCGEventFlagMaskCommand) != 0);
	entry->enabled = YES;

	@synchronized (self)
	{
		if (!_hotKeys)
			_hotKeys = [[NSMutableArray alloc] init];
		[_hotKeys addObject: entry];
		[self _updateHotKeyGrabs];

		// A combination the server refused (another client holds it) is not kept. With hot
		// keys switched off nothing is grabbed, and the hot key is kept.
		if (entry->keycode != 0 && [self _hotKeyIsActive: entry] && ![_grabbedHotKeys containsObject: grabKey(entry->keycode, entry->modifiers)])
		{
			[_hotKeys removeObject: entry];
			[self _updateHotKeyGrabs];
		}
	}
	[entry release];
}

-(BOOL) getHotKeyWithUID:(int)uid keyCode:(CGKeyCode*)outKeyCode flags:(CGEventFlags*)outFlags
{
	@synchronized (self)
	{
		X11HotKeyEntry* entry = [self _hotKeyWithUID: uid];
		if (!entry)
			return NO;
		if (outKeyCode)
			*outKeyCode = entry->virtualKey;
		if (outFlags)
			*outFlags = entry->flags;
		return YES;
	}
}

-(void) removeHotKeyWithUID:(int)uid
{
	@synchronized (self)
	{
		X11HotKeyEntry* entry = [self _hotKeyWithUID: uid];
		if (!entry)
			return;
		[_hotKeys removeObject: entry];
		[_pressedHotKeys removeObject: [NSNumber numberWithInt: uid]];
		// The grab is shared by all hot keys with the combination
		[self _updateHotKeyGrabs];
	}
}

-(BOOL) isHotKeyEnabledWithUID:(int)uid
{
	@synchronized (self)
	{
		X11HotKeyEntry* entry = [self _hotKeyWithUID: uid];
		return entry && entry->enabled;
	}
}

-(void) setHotKeyWithUID:(int)uid enabled:(BOOL)enabled
{
	@synchronized (self)
	{
		X11HotKeyEntry* entry = [self _hotKeyWithUID: uid];
		if (!entry || entry->enabled == enabled)
			return;
		entry->enabled = enabled;
		[self _updateHotKeyGrabs];
	}
}

// Switching hot keys off lets their keys go to the focused window again
-(void) hotKeyOperatingModeChanged
{
	@synchronized (self)
	{
		[_pressedHotKeys removeAllObjects];
		[self _updateHotKeyGrabs];
	}
}

// Reads the events of the process' one connection to the X server and handles them in order: the ones
// that are this connection's own (hot keys, keymap, display layout) here, the others by the
// observer, which is AppKit's X11 backend for the windows it creates on this display.
-(void) processPendingEvents
{
	id observer = [CGSConnection nativeObserver];
	SEL eventSelector = @selector(nativeConnectionEvent:);
	BOOL observesEvents = [observer respondsToSelector: eventSelector];

	while (XPending(_display) > 0)
	{
		XEvent event;

		if (XNextEvent(_display, &event) != Success)
			continue;
		if ([self processXEvent: &event])
			continue;
		// An input method's reply (Xlib: every event goes through XFilterEvent()); key events are filtered by
		// the keyboard, where the input method's decision is used.
		if (event.type != KeyPress && event.type != KeyRelease && XFilterEvent(&event, None))
			continue;
		if (observesEvents)
			[observer nativeConnectionEvent: &event];
	}

	if (_layoutChanged)
	{
		_layoutChanged = NO;
		// Whether the focused window covers a monitor depends on the layout.
		_occlusionCoverValid = NO;
		_occlusionDirty = YES;
		// Reports the change to the display reconfiguration callbacks.
		[self displayLayoutChanged];
		[_pointer displayLayoutChanged];
		if ([observer respondsToSelector: @selector(nativeConnectionDisplayLayoutChanged)])
			[observer nativeConnectionDisplayLayoutChanged];
		// After the observer has taken the new layout into what it derives from it: the windows report the
		// new scale to the UI layer then.
		[self _toplevelWindowsLayoutChanged];
	}
	if (_occlusionDirty)
		[self _updateOcclusion];
	if ([observer respondsToSelector: @selector(nativeConnectionDidProcessEvents)])
		[observer nativeConnectionDidProcessEvents];
}

+(int) nativeConnectionKind
{
	return CGSNativeConnectionKindX11;
}

-(void) invalidateScreens
{
	@synchronized (self)
	{
		[super invalidateScreens];
		_primaryRootValid = NO;
	}
}

// X11 has no scale protocol: the scale is the user's setting or the session's GDK_SCALE (see
// X11ScaleChoose()), read each time the displays are, so that a change of the setting is seen when the
// layout changes.
static CGFloat backingScaleFactor(void)
{
	double preferred = 0;
	CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("X11BackingScale"), CFSTR("org.darlinghq.AppKit"));
	if (value != NULL)
	{
		if (CFGetTypeID(value) == CFNumberGetTypeID())
			CFNumberGetValue(value, kCFNumberDoubleType, &preferred);
		CFRelease(value);
	}
	const char* source = NULL;
	return (CGFloat) X11ScaleChoose(preferred, &source);
}

// Width and Height are in points, like CGDisplayModeGetWidth/Height; PixelWidth and PixelHeight carry the
// mode's size in device pixels (the RandR mode size), which the points are derived from with the backing scale.
static NSDictionary* modeInfoToDictionary(const XRRModeInfo* mi, int depth, CGFloat scale)
{
	double rate = 0;

	if (mi->hTotal && mi->vTotal)
		rate = (double) mi->dotClock / ((double) mi->hTotal * (double) mi->vTotal);

	return @{
		@"Width": @((unsigned) lround(mi->width / scale)),
		@"Height": @((unsigned) lround(mi->height / scale)),
		@"Depth": @(depth),
		@"RefreshRate": @(rate),
		@"PixelWidth": @(mi->width),
		@"PixelHeight": @(mi->height),
	};
}

// A display without RandR, or an X server that lists no output: the root window stands in for
// the one display, whose ID is 1 like the first output's.
-(NSArray<CGSScreen*>*) _rootScreenWithScale:(CGFloat)scale
{
	Screen* screen = DefaultScreenOfDisplay(_display);
	int width = WidthOfScreen(screen), height = HeightOfScreen(screen);
	CGSScreen* cgScreen = [[CGSScreen new] autorelease];
	cgScreen.displayID = 1;
	cgScreen.bounds = CGRectMake(0, 0, width / scale, height / scale);
	cgScreen.backingScale = scale;
	cgScreen.nativeFrame = CGRectMake(0, 0, width, height);
	cgScreen.hasNativeFrame = YES;
	cgScreen.modes = @[ @{
		@"Width": @((unsigned) lround(width / scale)),
		@"Height": @((unsigned) lround(height / scale)),
		@"Depth": @(DefaultDepthOfScreen(screen)),
		@"PixelWidth": @(width),
		@"PixelHeight": @(height),
	} ];
	cgScreen.currentMode = 0;
	return @[ cgScreen ];
}

// The active outputs, the main one first (X11Monitors.h picks it), each described in CoreGraphics' global
// space. A display's CGDirectDisplayID stays tied to its RandR output (index + 1), whatever its place in the
// array: the mode functions address the output by that index.
-(NSArray<CGSScreen*>*) buildScreens
{
	CGFloat scale = backingScaleFactor();
	int count = 0, primary = -1;
	X11Monitor* monitors = X11MonitorsCopy(_display, &count, &primary);
	if (monitors == NULL || count == 0 || primary < 0)
	{
		free(monitors);
		return [self _rootScreenWithScale: scale];
	}

	int* order = calloc((size_t) count, sizeof *order);
	XRRScreenResources* resources = XRRGetScreenResourcesCurrent(_display, DefaultRootWindow(_display));
	if (order == NULL || resources == NULL)
	{
		free(order);
		free(monitors);
		if (resources != NULL)
			XRRFreeScreenResources(resources);
		return [self _rootScreenWithScale: scale];
	}
	X11MonitorsOrder(monitors, count, primary, order);

	const int depth = DefaultDepthOfScreen(DefaultScreenOfDisplay(_display));
	Atom edidAtom = XInternAtom(_display, "EDID", False);
	NSMutableArray<CGSScreen*>* screens = [NSMutableArray arrayWithCapacity: (NSUInteger) count];

	for (int n = 0; n < count; n++)
	{
		int i = order[n];
		// An output without a CRTC and mode (a disconnected or switched-off connector) shows nothing,
		// so it is not a display.
		if (!monitors[i].active)
			continue;

		// The origin is the main monitor's top-left corner, y down.
		CGSScreen* cgScreen = [[CGSScreen new] autorelease];
		cgScreen.displayID = X11MonitorDisplayID(i);
		cgScreen.bounds = CGRectMake((monitors[i].x - monitors[primary].x) / scale,
			(monitors[i].y - monitors[primary].y) / scale, monitors[i].width / scale, monitors[i].height / scale);
		cgScreen.backingScale = scale;
		cgScreen.nativeFrame = CGRectMake(monitors[i].x, monitors[i].y, monitors[i].width, monitors[i].height);
		cgScreen.hasNativeFrame = YES;

		NSMutableArray<NSDictionary*>* modes = [NSMutableArray array];
		CFIndex currentMode = -1;
		XRROutputInfo* output = XRRGetOutputInfo(_display, resources, monitors[i].output);
		if (output != NULL)
		{
			RRMode currentID = None;
			XRRCrtcInfo* crtc = output->crtc != None ? XRRGetCrtcInfo(_display, resources, output->crtc) : NULL;
			if (crtc != NULL)
			{
				currentID = crtc->mode;
				XRRFreeCrtcInfo(crtc);
			}
			for (int m = 0; m < output->nmode; m++)
			{
				for (int j = 0; j < resources->nmode; j++)
				{
					if (resources->modes[j].id != output->modes[m])
						continue;
					if (resources->modes[j].id == currentID)
						currentMode = (CFIndex) [modes count];
					[modes addObject: modeInfoToDictionary(&resources->modes[j], depth, scale)];
					break;
				}
			}
			XRRFreeOutputInfo(output);
		}
		cgScreen.modes = modes;
		cgScreen.currentMode = currentMode;

		Atom actualType;
		unsigned long nitems, bytesAfter;
		int actualFormat;
		unsigned char* prop = NULL;
		if (XRRGetOutputProperty(_display, monitors[i].output, edidAtom, 0, 100, False, False, AnyPropertyType,
				&actualType, &actualFormat, &nitems, &bytesAfter, &prop) == Success)
		{
			if (prop && actualFormat == 8 && nitems > 0)
				cgScreen.edid = [NSData dataWithBytes: prop length: nitems];
		}
		if (prop)
			XFree(prop);

		[screens addObject: cgScreen];
	}

	XRRFreeScreenResources(resources);
	free(order);
	free(monitors);
	return [screens count] > 0 ? [[screens copy] autorelease] : [self _rootScreenWithScale: scale];
}

static Bool isRandRLayoutEvent(Display* display, XEvent* event, XPointer arg)
{
	return X11RandRIsLayoutChange(event, *(int*) arg);
}

// Bounding box of the active CRTCs, in root coordinates, with the CRTC being changed taken at its new size.
static void crtcBoundingBox(Display* display, XRRScreenResources* resources, RRCrtc changed,
	int newWidth, int newHeight, int newX, int newY, int* width, int* height)
{
	int maxX = 0, maxY = 0;
	for (int i = 0; i < resources->ncrtc; i++)
	{
		int x, y, w, h;
		if (resources->crtcs[i] == changed)
		{
			x = newX; y = newY; w = newWidth; h = newHeight;
		}
		else
		{
			XRRCrtcInfo* info = XRRGetCrtcInfo(display, resources, resources->crtcs[i]);
			if (info == NULL)
				continue;
			x = info->x; y = info->y;
			w = info->width; h = info->height;
			if (info->mode == None)
			{
				XRRFreeCrtcInfo(info);
				continue;
			}
			if (info->rotation & (RR_Rotate_90 | RR_Rotate_270))
			{
				int t = w; w = h; h = t;
			}
			XRRFreeCrtcInfo(info);
		}
		if (x + w > maxX) maxX = x + w;
		if (y + h > maxY) maxY = y + h;
	}
	*width = maxX;
	*height = maxY;
}

// Sets the CRTC that drives the output to the RandR mode of the same size and refresh rate as mode (one of
// the display's modes), growing the screen first when the new bounding box needs it and shrinking it to the
// bounding box afterwards, as the desktop follows the mode on macOS.
-(BOOL) setMode:(NSDictionary*)mode forScreen:(int)screenIndex
{
	int eventBase, errorBase;
	if (mode == nil || !XRRQueryExtension(_display, &eventBase, &errorBase))
		return NO;

	Window root = DefaultRootWindow(_display);
	XRRScreenResources* resources = XRRGetScreenResourcesCurrent(_display, root);
	if (resources == NULL)
		return NO;
	if (screenIndex < 0 || screenIndex >= resources->noutput)
	{
		XRRFreeScreenResources(resources);
		return NO;
	}
	RROutput output = resources->outputs[screenIndex];
	XRROutputInfo* oinfo = XRRGetOutputInfo(_display, resources, output);
	XRRCrtcInfo* crtc = (oinfo && oinfo->crtc) ? XRRGetCrtcInfo(_display, resources, oinfo->crtc) : NULL;
	BOOL ok = NO;

	// The wanted RandR mode: one of the output's modes with the wanted size and the nearest rate.
	RRMode wanted = None;
	const XRRModeInfo* wantedInfo = NULL;
	if (crtc != NULL)
	{
		NSNumber* pw = [mode objectForKey: @"PixelWidth"];
		NSNumber* ph = [mode objectForKey: @"PixelHeight"];
		double rate = [[mode objectForKey: @"RefreshRate"] doubleValue], best = 0;
		for (int i = 0; i < oinfo->nmode; i++)
		{
			for (int j = 0; j < resources->nmode; j++)
			{
				const XRRModeInfo* mi = &resources->modes[j];
				if (mi->id != oinfo->modes[i])
					continue;
				if (pw == nil || ph == nil || mi->width != [pw unsignedIntValue] || mi->height != [ph unsignedIntValue])
					break;
				double r = (mi->hTotal && mi->vTotal)
					? (double) mi->dotClock / ((double) mi->hTotal * mi->vTotal) : 0;
				if (wanted == None || fabs(r - rate) < best)
				{
					wanted = mi->id;
					wantedInfo = mi;
					best = fabs(r - rate);
				}
				break;
			}
		}
	}

	if (wanted != None)
	{
		BOOL turned = (crtc->rotation & (RR_Rotate_90 | RR_Rotate_270)) != 0;
		int w = turned ? wantedInfo->height : wantedInfo->width;
		int h = turned ? wantedInfo->width : wantedInfo->height;
		int boxW, boxH, minW, minH, maxW, maxH;
		crtcBoundingBox(_display, resources, oinfo->crtc, w, h, crtc->x, crtc->y, &boxW, &boxH);
		int oldW = DisplayWidth(_display, DefaultScreen(_display));
		int oldH = DisplayHeight(_display, DefaultScreen(_display));
		if (boxW < 1) boxW = 1;
		if (boxH < 1) boxH = 1;
		BOOL sizeKnown = XRRGetScreenSizeRange(_display, root, &minW, &minH, &maxW, &maxH);
		if (sizeKnown && (boxW < minW || boxH < minH || boxW > maxW || boxH > maxH))
		{
			wanted = None;
		}
		else
		{
			// Millimetres follow the pixel size at the current density.
			int mmW = (int) lround((double) DisplayWidthMM(_display, DefaultScreen(_display)) * boxW / (oldW ? oldW : 1));
			int mmH = (int) lround((double) DisplayHeightMM(_display, DefaultScreen(_display)) * boxH / (oldH ? oldH : 1));
			if (boxW > oldW || boxH > oldH)
				XRRSetScreenSize(_display, root, MAX(boxW, oldW), MAX(boxH, oldH), MAX(mmW, 1), MAX(mmH, 1));
			Status status = XRRSetCrtcConfig(_display, resources, oinfo->crtc, CurrentTime, crtc->x, crtc->y,
				wanted, crtc->rotation, crtc->outputs, crtc->noutput);
			ok = (status == RRSetConfigSuccess);
			if (ok && (boxW < oldW || boxH < oldH))
				XRRSetScreenSize(_display, root, boxW, boxH, MAX(mmW, 1), MAX(mmH, 1));
			if (!ok && (boxW > oldW || boxH > oldH))
				XRRSetScreenSize(_display, root, oldW, oldH,
					DisplayWidthMM(_display, DefaultScreen(_display)), DisplayHeightMM(_display, DefaultScreen(_display)));
		}
	}

	if (crtc) XRRFreeCrtcInfo(crtc);
	if (oinfo) XRRFreeOutputInfo(oinfo);
	XRRFreeScreenResources(resources);

	if (ok)
	{
		// The callers read the displays right away, so apply the layout events now instead of when the
		// event loop gets to them.
		XSync(_display, False);
		XEvent event;
		int base = _xrrEventBase;
		while (XCheckIfEvent(_display, &event, isRandRLayoutEvent, (XPointer) &base))
			X11RandRHandleLayoutChange(&event, _xrrEventBase);
		[self invalidateScreens];
	}
	return ok;
}

// Moves the pointer on the X server, to a point in CoreGraphics' global space (points). The pointer
// decoder knows what a warp means for the events that follow (see CGSX11Pointer.h).
-(CGError) warpPointerToPoint:(CGPoint)point
{
	return [_pointer warpToPoint: point];
}

-(void) _getRootX:(int*)x y:(int*)y forPoint:(CGPoint)point
{
	X11Frame primary = [self _primaryRoot];
	CGFloat scale = _primaryScale;
	X11Point root = X11CGPointToRoot((X11Frame){primary.x / scale, primary.y / scale, primary.width / scale, primary.height / scale},
		(X11Point){point.x, point.y});
	*x = (int) round(root.x * scale);
	*y = (int) round(root.y * scale);
}

-(BOOL) managesPointer
{
	return YES;
}

-(void) cursorHiddenStateChanged:(BOOL)hidden
{
	[_pointer cursorHiddenChanged];
}

-(void) mouseAssociationChanged:(BOOL)associated
{
	[_pointer setMouseAssociatedWithCursor: associated];
}

-(BOOL) relativeMouseState:(BOOL*)requested frozenRoot:(CGPoint*)frozenRoot
{
	return [_pointer relativeMouseRequested: requested frozenRoot: frozenRoot];
}

// The address of an application menu is a property of the window.
-(BOOL) carriesApplicationMenuAddress
{
	return YES;
}

// The menu bar of an application is a dock window, which only a window manager that handles docks places at the top of the
// screen (see X11DockSupport.h).
-(BOOL) placesMenuBar
{
	return X11WindowManagerPlacesDocks(_display);
}

-(void) pointerWindowsChanged
{
	[_pointer windowsChanged];
}

-(void) selectTouchInputOnNativeWindow:(unsigned long)window
{
	[_pointer selectTouchInputOnWindow: (Window) window];
}

-(void) nativeObjectDestroyed:(void*)object
{
	[_pointer windowDestroyed: (Window) (uintptr_t) object];
}

// The blank cursor is made once.
-(Cursor) _blankCursorMade
{
	if (_blankCursor == None)
	{
		char zero = 0;
		XColor black = {0};
		Pixmap pixmap = XCreateBitmapFromData(_display, DefaultRootWindow(_display), &zero, 1, 1);
		_blankCursor = XCreatePixmapCursor(_display, pixmap, pixmap, &black, &black, 0, 0);
		XFreePixmap(_display, pixmap);
	}
	return _blankCursor;
}

// The cursor the process shows now: the blank one while it is hidden, else the selected cursor at the display's
// scale (the arrow when none is selected). None when the window system could not make it.
-(Cursor) _cursorToShow
{
	if (![self cursorIsVisible])
		return [self _blankCursorMade];
	CGFloat scale = backingScaleFactor();
	CGSCursor* cursor = [self cursor];
	if (cursor != nil)
		return (Cursor) (uintptr_t) [cursor nativeCursorFor: self scale: scale];
	if (_defaultArrow == None || _defaultArrowScale != scale)
	{
		if (_defaultArrow != None)
			XFreeCursor(_display, _defaultArrow);
		_defaultArrow = X11LoadThemedCursor(_display, "left_ptr", scale);
		_defaultArrowScale = scale;
	}
	return _defaultArrow;
}

-(void*) createNativeCursor:(CGSCursor*)cursor scale:(double)scale
{
	Cursor native = [cursor isImage] ? X11CreateImageCursor(_display, cursor, scale)
		: X11CreateShapeCursor(_display, cursor, scale);
	if (native == None)
		native = XcursorLibraryLoadCursor(_display, "left_ptr");
	return (void*) (uintptr_t) native;
}

-(void) destroyNativeCursor:(void*)native
{
	if (native != NULL)
		XFreeCursor(_display, (Cursor) (uintptr_t) native);
}

// Whether the window, or a window inside it (the client of a window manager's frame), is one of this process'.
static BOOL windowBelongsToProcess(Display* display, Window window, int depth)
{
	if (window == None)
		return NO;
	if (X11WindowOwnerPID(display, window) == getpid())
		return YES;
	if (depth <= 0)
		return NO;

	Window root, parent, *children = NULL;
	unsigned int count = 0;
	BOOL found = NO;
	if (XQueryTree(display, window, &root, &parent, &children, &count))
	{
		for (unsigned int i = 0; i < count && !found; i++)
			found = windowBelongsToProcess(display, children[i], depth - 1);
		if (children != NULL)
			XFree(children);
	}
	return found;
}

// The windows the connection made show the cursor; so does the process' window under the pointer that is not one of
// them (a framework above that made its own X windows; it asks again as the pointer enters one), and the cursor
// stays the process' while the pointer is over it. A window of another process is left alone.
-(void) _applyCursor
{
	Cursor cursor = [self _cursorToShow];
	if (cursor == None)
		return;
	BOOL undefine = [self cursorIsVisible] && [self cursor] == nil;

	@synchronized (_windows)
	{
		for (NSNumber* key in _windows)
		{
			CGSWindow* window = [_windows objectForKey: key];

			// A window of the UI layer shows the cursor the UI layer gives it.
			if (![window isKindOfClass: [CGSWindowX11 class]])
				continue;
			if (undefine)
				XUndefineCursor(_display, ((CGSWindowX11*) window)->_window);
			else
				XDefineCursor(_display, ((CGSWindowX11*) window)->_window, cursor);
		}
	}

	Window root = DefaultRootWindow(_display), returnedRoot = None, child = None;
	int rootX, rootY, windowX, windowY;
	unsigned int mask;
	if (XQueryPointer(_display, root, &returnedRoot, &child, &rootX, &rootY, &windowX, &windowY, &mask) &&
		child != None && windowBelongsToProcess(_display, child, 2))
		XDefineCursor(_display, child, cursor);
	XFlush(_display);
}

// A window made while the cursor is hidden shows the blank cursor like the others, and one made after a cursor
// was selected shows it.
-(void) _applyCursorToNewWindow:(CGSWindowX11*)window
{
	if ([self cursorIsVisible] && [self cursor] == nil)
		return;
	Cursor cursor = [self _cursorToShow];
	if (cursor != None)
	{
		XDefineCursor(_display, window->_window, cursor);
		XFlush(_display);
	}
}

-(void) cursorChanged
{
	if ([NSThread isMainThread])
		[self _applyCursor];
	else
		[self performSelectorOnMainThread: @selector(_applyCursor) withObject: nil waitUntilDone: NO];
}

-(CGSWindow*) newToplevelWindowWithAttributes:(const CGSToplevelAttributes*)attributes
{
	CGSWindowID windowID = [self _allocateWindowID];
	CGSWindowX11* window = [[CGSWindowX11 alloc] initToplevelWithAttributes: attributes
		connection: self
		windowID: windowID];
	if (window == nil)
		return nil;

	@synchronized (_windows)
	{
		[_windows setObject: window forKey: [NSNumber numberWithInt: windowID]];
	}
	[self _applyCursorToNewWindow: window];
	[window release];
	return window;
}

-(BOOL) supportsTranslucentToplevels
{
	return [CGSWindowX11 translucentVisualAvailableOnDisplay: _display];
}

-(CGSWindow*) newWindow:(CGSRegionRef)region
{
	CGSWindowID windowID = [self _allocateWindowID];
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
	[self _applyCursorToNewWindow: window];
	[window release];
	return window;
}

// Reads a property of 32-bit values (windows) of the root window: _NET_CLIENT_LIST and
// _NET_CLIENT_LIST_STACKING. Returns the windows in the order of the property, or an empty
// array. The Xlib 32-bit format is stored in longs.
static NSArray<NSNumber*>* rootWindowList(Display* display, const char* name)
{
	NSMutableArray<NSNumber*>* result = [NSMutableArray array];
	Atom property = XInternAtom(display, name, True);
	if (property == None)
		return result;

	Atom type;
	int format;
	unsigned long count, remaining;
	unsigned char* data = NULL;
	if (XGetWindowProperty(display, DefaultRootWindow(display), property, 0, 1 << 16, False,
			XA_WINDOW, &type, &format, &count, &remaining, &data) == Success &&
		data != NULL && type == XA_WINDOW && format == 32)
	{
		for (unsigned long i = 0; i < count; i++)
			[result addObject: @(((unsigned long*) data)[i])];
	}
	if (data != NULL)
		XFree(data);
	return result;
}

// The server's current time, from the timestamp of a property change on a window of our own
// (the server stamps every event). CurrentTime (0) when that fails.
static Time currentServerTime(Display* display)
{
	Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), -10, -10, 1, 1, 0, 0, 0);
	Time result = CurrentTime;

	XSelectInput(display, window, PropertyChangeMask);
	XChangeProperty(display, window, XA_WM_NAME, XA_STRING, 8, PropModeAppend, NULL, 0);
	XFlush(display);

	// Wait for the notification, which the server sends at once; a hung server must not hang us.
	int fd = ConnectionNumber(display);
	for (int attempts = 0; attempts < 50; attempts++)
	{
		XEvent event;
		if (XCheckTypedWindowEvent(display, window, PropertyNotify, &event))
		{
			result = event.xproperty.time;
			break;
		}
		struct pollfd pfd = {fd, POLLIN, 0};
		poll(&pfd, 1, 100);
	}
	XDestroyWindow(display, window);
	return result;
}

+(CGError) activateWindowsOfProcess:(pid_t)pid options:(uint32_t)options
{
	// The process' connection when it has one; a process that never opened one (a command line tool)
	// asks through a connection of its own, which it closes again.
	CGSConnectionX11* shared = [processConnection() retain];
	Display* display = shared != nil ? shared->_display : XOpenDisplay(NULL);
	if (display == NULL)
		return kCGErrorCannotComplete;
	BOOL owned = shared == nil;
	CGError result = kCGErrorSuccess;

	// The window manager decides, and may refuse to steal the focus; without one nothing can be activated, and
	// the properties a manager that exited left behind name windows it no longer manages.
	if (!X11WindowManagerIsRunning(display))
	{
		if (owned)
			XCloseDisplay(display);
		[shared release];
		return kCGErrorCannotComplete;
	}

	// EWMH: the clients are listed in the order of mapping, and, bottom to top, by stacking
	// order. Without a window manager that supports them there is nothing to ask.
	NSArray<NSNumber*>* clients = rootWindowList(display, "_NET_CLIENT_LIST_STACKING");
	if ([clients count] == 0)
		clients = rootWindowList(display, "_NET_CLIENT_LIST");

	NSMutableArray<NSNumber*>* targets = [NSMutableArray array];
	for (NSNumber* client in clients)
	{
		if (X11WindowOwnerPID(display, (Window) [client unsignedLongValue]) == pid)
			[targets addObject: client];
	}
	if ([targets count] == 0)
	{
		if (owned)
			XCloseDisplay(display);
		[shared release];
		return kCGErrorNoneAvailable;
	}
	// The topmost one is the front window.
	if ((options & kCGSActivateProcessFrontWindowOnly) != 0)
		targets = [NSMutableArray arrayWithObject: [targets lastObject]];

	Time now = currentServerTime(display);
	Atom activeWindow = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);

	// Activating the windows bottom to top leaves the topmost one focused and keeps their order.
	for (NSNumber* target in targets)
	{
		XEvent event;
		memset(&event, 0, sizeof(event));
		event.xclient.type = ClientMessage;
		event.xclient.window = (Window) [target unsignedLongValue];
		event.xclient.message_type = activeWindow;
		event.xclient.format = 32;
		event.xclient.data.l[0] = 2; // source indication: pager
		event.xclient.data.l[1] = (long) now;
		event.xclient.data.l[2] = 0; // we have no active window
		XSendEvent(display, DefaultRootWindow(display), False,
			SubstructureRedirectMask | SubstructureNotifyMask, &event);
	}
	XSync(display, False);
	if (owned)
		XCloseDisplay(display);
	[shared release];
	return result;
}

+(CGError) copyFrontProcessID:(pid_t*)pid
{
	// The process' connection when it has one; a process that never opened one (a command line tool)
	// asks through a connection of its own, which it closes again.
	CGSConnectionX11* shared = [processConnection() retain];
	Display* display = shared != nil ? shared->_display : XOpenDisplay(NULL);
	if (display == NULL)
		return kCGErrorCannotComplete;

	// EWMH: the window manager names the focused top-level window in _NET_ACTIVE_WINDOW of the
	// root window (None when there is none, or without a window manager that supports it).
	NSArray<NSNumber*>* active = rootWindowList(display, "_NET_ACTIVE_WINDOW");
	pid_t owner = 0;
	if ([active count] > 0 && [active[0] unsignedLongValue] != None)
		owner = X11WindowOwnerPID(display, (Window) [active[0] unsignedLongValue]);
	if (shared == nil)
		XCloseDisplay(display);
	[shared release];

	// The owner is 0 for a window of a process that is not a Darling process.
	if (owner <= 0)
		return kCGErrorNoneAvailable;
	*pid = owner;
	return kCGErrorSuccess;
}

+(BOOL) isAvailable
{
	if (getenv("DISPLAY") != NULL)
		return YES;
	// TODO: we could be a little smarter here
	return NO;
}
@end
