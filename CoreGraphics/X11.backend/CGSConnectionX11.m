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
#import "../DarlingUnicodeKeyLayout.h"
#import "../DarlingUnicodeKeyLayoutCompose.h"
#import <CoreGraphics/CGSKeySymToUnicodePrivate.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>
#include <stdlib.h>
#include <time.h>
#include <stdatomic.h>
#include <poll.h>
#import <X11/Xutil.h>
#import <X11/extensions/Xrandr.h>
#import <X11/XKBlib.h>
#import <X11/extensions/XKBrules.h>
// The main-monitor model and conversions shared with AppKit's X11 backend.
#import "X11Monitors.h"
#import "X11RandR.h"
#import "X11WindowOwner.h"
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
		XkbSelectEvents(_display, XkbUseCoreKbd, XkbMapNotifyMask | XkbNewKeyboardNotifyMask | XkbStateNotifyMask, 1);
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
	// Closing the display releases the grabs
	[_hotKeys release];
	[_grabbedHotKeys release];
	[_pressedHotKeys release];

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
			[self _deliverHotKeyEvent: &event->xkey];
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

		if (event->type == _xkbEventBase)
		{
			// All XKB events share one event type; xkb_type tells them apart.
			XkbEvent* xkbevt = (XkbEvent*) event;
			BOOL keymapChanged = xkbevt->any.xkb_type == XkbMapNotify || xkbevt->any.xkb_type == XkbNewKeyboardNotify;
			BOOL groupChanged = xkbevt->any.xkb_type == XkbStateNotify && _keyboardLayoutGroup != xkbevt->state.group;

			// Invalidate cached keyboard layout information
			if (keymapChanged || groupChanged)
			{
				// TODO: Emit kTISNotifySelectedKeyboardInputSourceChanged via NSDistributedNotificationCenter

				@synchronized (self)
				{
					[_keyboardLayout release];
					_keyboardLayout = nil;
				}
				if (groupChanged)
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
			if (pressed ? ([self _hotKeyIsActive: entry] && X11HotKeyMatches(event->state, entry->modifiers))
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

	X11Point point = X11CGPointFromRoot([self _primaryRoot], (X11Point){event->x_root, event->y_root});
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
	// A connection of its own: this class method does not need a CGS connection, and the
	// events of that one are consumed elsewhere.
	Display* display = XOpenDisplay(NULL);
	if (display == NULL)
		return kCGErrorCannotComplete;

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
		XCloseDisplay(display);
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
	XCloseDisplay(display);
	return kCGErrorSuccess;
}

+(CGError) copyFrontProcessID:(pid_t*)pid
{
	Display* display = XOpenDisplay(NULL);
	if (display == NULL)
		return kCGErrorCannotComplete;

	// EWMH: the window manager names the focused top-level window in _NET_ACTIVE_WINDOW of the
	// root window (None when there is none, or without a window manager that supports it).
	NSArray<NSNumber*>* active = rootWindowList(display, "_NET_ACTIVE_WINDOW");
	pid_t owner = 0;
	if ([active count] > 0 && [active[0] unsignedLongValue] != None)
		owner = X11WindowOwnerPID(display, (Window) [active[0] unsignedLongValue]);
	XCloseDisplay(display);

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
