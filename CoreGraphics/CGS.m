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
#include <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <stdatomic.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSKeyboardLayout.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CGWindowPrivate.h>
#import <CoreGraphics/CGSSurface.h>
#include <pthread.h>
#include <stdio.h>
#include <CoreFoundation/CFNotificationCenter.h>
#include <notify.h>

static NSMutableDictionary<NSNumber*, CGSConnection*>* g_connections = nil;
static Boolean g_denyConnections = FALSE;


static _Atomic CGSConnectionID g_nextConnectionID = 1;
static Class g_backendClass = nil;

__attribute__((visibility("hidden"))) CFMutableArrayRef g_cgsNotifyProc;
__attribute__((visibility("hidden"))) pthread_mutex_t g_cgsNotifyProcMutex = PTHREAD_MUTEX_INITIALIZER;

typedef struct
{
	CGSNotifyProcPtr proc;
	CGSNotificationType notificationType;
	void* private;
} NotifyProcEntry;

CGError CGSSetDenyWindowServerConnections(Boolean deny)
{
	NSUInteger connectionCount;
	@synchronized(g_connections)
	{
		connectionCount = g_connections.count;
	}

	if (deny && connectionCount > 0)
	{
		return kCGErrorFailure;
	}

	g_denyConnections = deny;
	return kCGSErrorSuccess;
}

extern void _CGSResetMainConnection(void);

void CGSShutdownServerConnections(void)
{
	@synchronized(g_connections)
	{
		[g_connections removeAllObjects];
	}
	_CGSResetMainConnection();
}

__attribute__((constructor))
void CGSInitialize(void)
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		g_connections = [[NSMutableDictionary alloc] initWithCapacity: 1];
	});
}

static void _CGSLoadBackend(void)
{
	NSBundle* cgBundle = [NSBundle bundleForClass: [CGSConnection class]];
	NSMutableArray<NSBundle*>* backends = [NSMutableArray new];

	for (NSString *path in [cgBundle pathsForResourcesOfType: @"backend" inDirectory: @"Backends"])
	{
		NSBundle* backendBundle = [NSBundle bundleWithPath: path];
		if ([backendBundle load])
			[backends addObject: backendBundle];
	}

	// Sort them according to the NSPriority key in their Info.plist files.
	[backends sortUsingComparator: ^(NSBundle *b1, NSBundle *b2) {
		NSNumber *p1 = [b1 objectForInfoDictionaryKey: @"NSPriority"];
		NSNumber *p2 = [b2 objectForInfoDictionaryKey: @"NSPriority"];
		return [p2 compare: p1];
	}];

	// Try to instantiate them in that order.
	for (NSBundle *backendBundle in backends)
	{
		Class cls = [backendBundle principalClass];
		if ([cls isAvailable])
		{
			g_backendClass = cls;
			break;
		}
	}
	[backends release];
}

static void _CGSLoadBackendOnce(void)
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		_CGSLoadBackend();
	});
}

CGError CGSNewConnection(CGSDictionaryObj attribs, CGSConnectionID* connId)
{
	*connId = -1;

	if (g_denyConnections)
		return kCGErrorCannotComplete;

	_CGSLoadBackendOnce();

	if (!g_backendClass)
		return kCGErrorCannotComplete;
	
	CGSConnectionID newConnID = g_nextConnectionID++;
	CGSConnection* conn = [[g_backendClass alloc] initWithConnectionID: newConnID];

	if (conn != nil)
	{
		*connId = newConnID;
		@synchronized(g_connections)
		{
			[g_connections setObject: conn forKey: [NSNumber numberWithInt: newConnID]];
		}
		[conn release];
		return kCGSErrorSuccess;
	}
	else
		return kCGErrorFailure;
}

CGError _CGSActivateProcess(pid_t pid, uint32_t options)
{
	if (pid <= 0)
		return kCGErrorIllegalArgument;

	// The display server first, directly. Whatever it cannot do (it has no such request, or the
	// process has no window of its own kind there, as a Wayland client has none on an X server
	// that Xwayland provides) is asked of the process itself.
	_CGSLoadBackendOnce();
	if (g_backendClass != nil &&
		[g_backendClass activateWindowsOfProcess: pid options: options] == kCGErrorSuccess)
		return kCGErrorSuccess;

	char name[64];
	snprintf(name, sizeof(name), kCGSProcessActivationNotificationPrefix "%d", (int) pid);
	CFStringRef notification = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
	if (notification == NULL)
		return kCGErrorCannotComplete;
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
		notification, NULL, NULL, true);
	CFRelease(notification);
	return kCGErrorSuccess;
}

// The process that was activated last, for a display server that cannot be asked: the state of a
// libnotify name, which is shared by all processes.
static int frontProcessToken(void)
{
	static dispatch_once_t once;
	static int token = -1;
	dispatch_once(&once, ^{
		if (notify_register_check(kCGSFrontProcessNotificationName, &token) != NOTIFY_STATUS_OK)
			token = -1;
	});
	return token;
}

CGError _CGSGetFrontProcess(pid_t* pid)
{
	if (pid == NULL)
		return kCGErrorIllegalArgument;

	_CGSLoadBackendOnce();
	if (g_backendClass != nil)
	{
		pid_t front = 0;
		CGError err = [g_backendClass copyFrontProcessID: &front];
		if (err == kCGErrorSuccess)
		{
			*pid = front;
			return kCGErrorSuccess;
		}
		if (err != kCGErrorNotImplemented)
			return err;
	}

	int token = frontProcessToken();
	uint64_t state = 0;
	if (token < 0 || notify_get_state(token, &state) != NOTIFY_STATUS_OK)
		return kCGErrorCannotComplete;
	if (state == 0 || state > INT32_MAX)
		return kCGErrorNoneAvailable;
	*pid = (pid_t) state;
	return kCGErrorSuccess;
}

CGError _CGSSetFrontProcess(pid_t pid)
{
	if (pid <= 0)
		return kCGErrorIllegalArgument;

	int token = frontProcessToken();
	if (token < 0 || notify_set_state(token, (uint64_t) pid) != NOTIFY_STATUS_OK)
		return kCGErrorCannotComplete;
	return kCGErrorSuccess;
}

CGSConnection* _CGSConnectionForID(CGSConnectionID connId)
{
	@synchronized(g_connections)
	{
		return [g_connections objectForKey:[NSNumber numberWithInt: connId]];
	}
}

void* _CGSNativeDisplay(CGSConnectionID connId)
{
	return [_CGSConnectionForID(connId) nativeDisplay];
}

void* _CGSNativeWindowForID(CGSConnectionID connId, CGSWindowID winId)
{
	CGSConnection* conn = _CGSConnectionForID(connId);
	return [[conn windowForId: winId] nativeWindow];
}

void* _CGSNativeWindowForSurfaceID(CGSConnectionID connId, CGSWindowID winId, CGSSurfaceID surfaceId)
{
	CGSConnection* conn = _CGSConnectionForID(connId);
	return [[[conn windowForId: winId] surfaceForId: surfaceId] nativeWindow];
}

CGError _CGSCreateDisplayOverlayWindow(CGSConnectionID connId, CGRect bounds,
                                       CGSWindowID* winId, void** drawable)
{
	if (winId == NULL || drawable == NULL)
		return kCGErrorIllegalArgument;

	CGSConnection* c = _CGSConnectionForID(connId);
	if (!c)
		return kCGErrorInvalidConnection;

	CGSRegionRef region = NULL;
	CGError err = CGSNewRegionWithRect(&bounds, &region);
	if (err != kCGErrorSuccess || region == NULL)
		return kCGErrorIllegalArgument;

	CGSWindow* window = [c newWindow: region];
	CGSRegionRelease(region);
	if (!window)
		return kCGErrorIllegalArgument;

	CGSWindowID wid = window.windowId;
	void* native = NULL;
	err = [window becomeDisplayOverlay: &native];
	if (err == kCGSErrorSuccess)
		err = [window orderWindow: kCGSOrderAbove relativeTo: nil];
	if (err != kCGSErrorSuccess)
	{
		[c destroyWindow: wid];
		return err;
	}

	*winId = wid;
	*drawable = native;
	[[NSNotificationCenter defaultCenter]
		postNotificationName: (NSString*) _kCGSDisplayOverlayWindowCreated
		object: nil
		userInfo: @{ @"NativeWindow": @((uintptr_t) native) }];
	return kCGSErrorSuccess;
}

void CGSSetHotKeyWithExclusion(CGSConnectionID connId, int uid, uint16_t options, uint16_t key, CGSModifierFlags modifierFlags, int exclusion)
{
	[_CGSConnectionForID(connId) setHotKeyWithUID: uid keyCode: key flags: modifierFlags exclusion: exclusion];
}

void CGSSetHotKey(CGSConnectionID connId, int uid, uint16_t options, uint16_t key, CGSModifierFlags modifierFlags)
{
	CGSSetHotKeyWithExclusion(connId, uid, options, key, modifierFlags, 0);
}

bool CGSGetHotKey(CGSConnectionID connId, int uid, uint16_t* options, uint16_t* key, CGSModifierFlags* modifierFlags)
{
	CGKeyCode code = 0;
	CGEventFlags flags = 0;

	if (![_CGSConnectionForID(connId) getHotKeyWithUID: uid keyCode: &code flags: &flags])
		return false;
	if (options)
		*options = 0;
	if (key)
		*key = code;
	if (modifierFlags)
		*modifierFlags = (CGSModifierFlags) flags;
	return true;
}

void CGSRemoveHotKey(CGSConnectionID connId, int uid)
{
	[_CGSConnectionForID(connId) removeHotKeyWithUID: uid];
}

bool CGSIsHotKeyEnabled(CGSConnectionID connId, int uid)
{
	return [_CGSConnectionForID(connId) isHotKeyEnabledWithUID: uid];
}

void CGSSetHotKeyEnabled(CGSConnectionID connId, int uid, bool enabled)
{
	[_CGSConnectionForID(connId) setHotKeyWithUID: uid enabled: enabled];
}

CGError CGSGetGlobalHotKeyOperatingMode(CGSConnectionID connId, int* mode)
{
	CGSConnection* conn = _CGSConnectionForID(connId);

	return conn ? [conn getGlobalHotKeyOperatingMode: mode] : kCGErrorInvalidConnection;
}

CGError CGSSetGlobalHotKeyOperatingMode(CGSConnectionID connId, int mode)
{
	CGSConnection* conn = _CGSConnectionForID(connId);

	return conn ? [conn setGlobalHotKeyOperatingMode: mode] : kCGErrorInvalidConnection;
}

CGError CGSReleaseConnection(CGSConnectionID connId)
{
	NSNumber* num = [NSNumber numberWithInt:connId];

	@synchronized(g_connections)
	{
		if (![g_connections objectForKey: num])
			return kCGErrorInvalidConnection;
		[g_connections removeObjectForKey: num];
	}
	return kCGSErrorSuccess;
}

CGSConnectionID _CGSDefaultConnection(void)
{
	return CGSMainConnectionID();
}

CGPoint CGSCurrentInputPointerPosition(void)
{
	return [_CGSConnectionForID(CGSMainConnectionID()) mouseLocation];
}

static CGError getWindow(CGSConnectionID cid, CGSWindowID wid, CGSWindow** out)
{
	CGSConnection* c = _CGSConnectionForID(cid);
	if (!c)
		return kCGErrorInvalidConnection;

	CGSWindow* window = [c windowForId: wid];
	if (!window)
		return kCGErrorIllegalArgument;

	*out = window;
	return kCGSErrorSuccess;
}

CGError CGSNewWindow(CGSConnectionID conn, CFIndex flags, float x_offset, float y_offset, const CGSRegionRef region, CGSWindowID* windowID)
{
	CGSConnection* c = _CGSConnectionForID(conn);
	if (!c)
		return kCGErrorInvalidConnection;

	CGSWindow* window = [c newWindow: region];
	if (!window)
		return kCGErrorIllegalArgument;
	
	*windowID = window.windowId;
	return kCGSErrorSuccess;
}

CGError CGSReleaseWindow(CGSConnectionID cid, CGSWindowID wid)
{
	CGSConnection* c = _CGSConnectionForID(cid);
	if (!c)
		return kCGErrorInvalidConnection;
	return [c destroyWindow: wid];
}

CGError CGSSetWindowShape(CGSConnectionID cid, CGSWindowID wid, float x_offset, float y_offset, const CGSRegionRef shape)
{
	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);

	if (err != kCGSErrorSuccess)
		return err;
	
	return [window setRegion: shape];
}

OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, CGSWindowOrderingMode place, CGSWindowID relativeToWindow)
{
	CGSConnection* c = _CGSConnectionForID(cid);
	if (!c)
		return kCGErrorInvalidConnection;

	CGSWindow* window = [c windowForId: wid];
	if (!window)
		return kCGErrorIllegalArgument;

	CGSWindow* relativeTo = [c windowForId: relativeToWindow];
	return [window orderWindow: place relativeTo: relativeTo];
}

CGError CGSMoveWindow(CGSConnectionID cid, CGSWindowID wid, const CGPoint *window_pos)
{
	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);
	
	if (err != kCGSErrorSuccess)
		return err;
	
	return [window moveTo: window_pos];
}

extern CGError CGSSetWindowOpacity(CGSConnectionID cid, CGSWindowID wid, bool isOpaque);
extern CGError CGSSetWindowLevel(CGSConnectionID cid, CGSWindowID wid, CGWindowLevel level);

// Window server calls on application windows. There is no separate window
// server: the window id is the AppKit window number, which maps to the
// process's platform window (CGWindow, e.g. the X11 backend window). The
// connection id isn't checked, because applications typically pass
// -[NSGraphicsContext contextID] and every window belongs to this process.

static CGWindow* platformWindowForID(CGSWindowID wid)
{
	return [CGWindow windowWithWindowNumber: wid];
}

// Transforms are recorded and reported back, but not applied: the X11 backend
// has no way to scale or rotate a top-level window. Apps use them for window
// animations, which then simply don't show.
static NSMutableDictionary<NSNumber*, NSValue*>* g_windowTransforms = nil;

CGError CGSSetWindowTransformAtPlacement(CGSConnectionID cid, CGSWindowID wid, int32_t placement, int32_t reserved, CGAffineTransform transform)
{
	if (!platformWindowForID(wid))
		return kCGErrorIllegalArgument;

	NSValue* value = [NSValue valueWithBytes: &transform objCType: @encode(CGAffineTransform)];
	@synchronized([CGWindow class])
	{
		if (!g_windowTransforms)
			g_windowTransforms = [NSMutableDictionary new];
		g_windowTransforms[@(wid)] = value;
	}
	return kCGSErrorSuccess;
}

CGError CGSGetWindowTransformAtPlacement(CGSConnectionID cid, CGSWindowID wid, int32_t placement, void *reserved, CGAffineTransform *outTransform)
{
	if (!outTransform)
		return kCGErrorIllegalArgument;
	if (!platformWindowForID(wid))
		return kCGErrorIllegalArgument;

	CGAffineTransform transform = CGAffineTransformIdentity;
	@synchronized([CGWindow class])
	{
		NSValue* value = g_windowTransforms[@(wid)];
		if (value)
			[value getValue: &transform];
	}
	*outTransform = transform;
	return kCGSErrorSuccess;
}

int CGSServerOperationState(int state)
{
	return 0;
}

// The same window lookup and transform record as the AtPlacement calls:
// CGSSetWindowTransform is CGSSetWindowTransformAtPlacement with the default
// placement.
CGError CGSSetWindowTransform(CGSConnectionID cid, CGSWindowID wid, CGAffineTransform transform)
{
	return CGSSetWindowTransformAtPlacement(cid, wid, 0, 0, transform);
}

// Windows are not composited, so they cannot be warped. Removing a warp (a
// NULL mesh) leaves a window as it is and succeeds; anything else is not
// implemented.
CGError CGSSetWindowWarp(CGSConnectionID cid, CGSWindowID wid, int w, int h, float *mesh)
{
	if (!platformWindowForID(wid))
		return kCGErrorIllegalArgument;
	return (mesh == NULL) ? kCGSErrorSuccess : kCGErrorNotImplemented;
}

// Window contents are never captured (see CGDisplayStream), so any shape is
// already excluded from capture.
CGError CGSSetWindowCaptureExcludeShape(CGSConnectionID cid, CGSWindowID wid, CGRegionRef shape)
{
	if (!platformWindowForID(wid))
		return kCGErrorIllegalArgument;
	return kCGSErrorSuccess;
}

CGError CGSGetWindowProperty(CGSConnectionID cid, CGSWindowID wid, CFStringRef key, CFTypeRef *outValue)
{
	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);
	
	if (err != kCGSErrorSuccess)
		return err;
	
	return [window getProperty: key value: outValue];
}

CGError CGSSetWindowProperty(CGSConnectionID cid, CGSWindowID wid, CFStringRef key, CFTypeRef value)
{
	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);
	
	if (err != kCGSErrorSuccess)
		return err;
	
	return [window setProperty: key value: value];
}

CGError getSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid, CGSSurface** surface)
{
	CGSWindow* window;

	CGError err = getWindow(cid, wid, &window);
	if (err != kCGSErrorSuccess)
		return err;

	*surface = [window surfaceForId: sid];
	return (*surface) ? kCGSErrorSuccess : kCGErrorIllegalArgument;
}

CGError CGSAddSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID *sid)
{
	CGSWindow* window;

	CGError err = getWindow(cid, wid, &window);
	if (err != kCGSErrorSuccess)
		return err;
	
	CGSSurface* surface = [window createSurface];
	if (!surface)
		return kCGErrorFailure;
	
	*sid = surface.surfaceId;
	return kCGSErrorSuccess;
}

CGError CGSRemoveSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid)
{
	CGSSurface* surface;

	CGError err = getSurface(cid, wid, sid, &surface);
	if (err != kCGSErrorSuccess)
		return err;

	[surface invalidate];
	return kCGSErrorSuccess;
}

CGError CGSSetSurfaceBounds(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid, CGRect rect)
{
	CGSSurface* surface;

	CGError err = getSurface(cid, wid, sid, &surface);
	if (err != kCGSErrorSuccess)
		return err;

	return [surface setBounds: rect];
}

CGSConnection* _CGSConnectionFromEventRecord(const CGSEventRecordPtr record)
{
	if (!record)
		return nil;
	return _CGSConnectionForID(record->connection);
}

static void simplyFree(CFAllocatorRef allocator, const void* mem)
{
	free((void*) mem);
}

CGError CGSRegisterNotifyProc(CGSNotifyProcPtr proc, CGSNotificationType notificationType, void* private)
{
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		CFArrayCallBacks cb = {
			.release = simplyFree,
			.version = 0,
		};
		g_cgsNotifyProc = CFArrayCreateMutable(NULL, 0, &cb);
	});

	NotifyProcEntry* e = (NotifyProcEntry*) malloc(sizeof(NotifyProcEntry));
	e->proc = proc;
	e->notificationType = notificationType;
	e->private = private;

	pthread_mutex_lock(&g_cgsNotifyProcMutex);
	CFArrayAppendValue(g_cgsNotifyProc, e);
	pthread_mutex_unlock(&g_cgsNotifyProcMutex);

	return kCGSErrorSuccess;
}

CGError CGSRemoveNotifyProc(CGSNotifyProcPtr proc, CGSNotificationType notificationType)
{
	if (!g_cgsNotifyProc)
		return kCGSErrorSuccess;

	pthread_mutex_lock(&g_cgsNotifyProcMutex);

	// This code is not too efficient, but it is called so rarely (if ever), it doesn't matter.
	for (CFIndex i = 0; i < CFArrayGetCount(g_cgsNotifyProc); i++)
	{
		NotifyProcEntry* e = (NotifyProcEntry*) CFArrayGetValueAtIndex(g_cgsNotifyProc, i);
		if (e->proc == proc && e->notificationType == notificationType)
		{
			CFArrayRemoveValueAtIndex(g_cgsNotifyProc, i);
			break;
		}
	}

	pthread_mutex_unlock(&g_cgsNotifyProcMutex);

	return kCGSErrorSuccess;
}

// Hands a hot key press or release, as a system-defined event, to the procs registered for
// such events. Called by the backends (through -postHotKeyEventForUID:...) on the main run loop.
__attribute__((visibility("hidden")))
void _CGSPostHotKeyEvent(CGSConnectionID connection, int uid, BOOL pressed, CGEventFlags flags, CGPoint location, uint64_t time)
{
	CGSEventRecord record;
	NSMutableArray* procs = [NSMutableArray array];

	memset(&record, 0, sizeof(record));
	record.length = sizeof(record);
	record.type = NX_SYSDEFINED;
	record.location = location;
	record.windowLocation = location;
	record.time = time;
	record.flags = flags;
	record.window = 0;
	record.connection = connection;
	record.data.compound.subType = pressed ? kCGSHotKeyPressedSubtype : kCGSHotKeyReleasedSubtype;
	record.data.compound.misc.L[0] = uid;

	// The procs are called outside the lock: one may register or remove procs
	pthread_mutex_lock(&g_cgsNotifyProcMutex);
	for (CFIndex i = 0; g_cgsNotifyProc && i < CFArrayGetCount(g_cgsNotifyProc); i++)
	{
		NotifyProcEntry* e = (NotifyProcEntry*) CFArrayGetValueAtIndex(g_cgsNotifyProc, i);
		if (e->notificationType == CGSNotificationSingleEventType(NX_SYSDEFINED) || e->notificationType == kCGSNotificationAllEvents)
			[procs addObject: [NSData dataWithBytes: e length: sizeof(*e)]];
	}
	pthread_mutex_unlock(&g_cgsNotifyProcMutex);

	for (NSData* entry in procs)
	{
		const NotifyProcEntry* e = [entry bytes];
		e->proc(e->notificationType, &record, sizeof(record), e->private);
	}
}

// The layout a client of the window system registered with _CGSSetProvidedKeyboardLayout, for a
// backend that cannot read the keymap itself (Wayland hands the keymap to the keyboard-owning
// client, which is AppKit).
static CGSKeyboardLayout* g_providedKeyboardLayout;
static pthread_mutex_t g_providedKeyboardLayoutMutex = PTHREAD_MUTEX_INITIALIZER;

void _CGSSetProvidedKeyboardLayout(const void* uchr, uint32_t length, CFStringRef name, CFStringRef fullName)
{
	CGSKeyboardLayout* layout = nil;
	if (uchr != NULL && length != 0)
	{
		layout = [CGSKeyboardLayout new];
		[layout setLayout: (UCKeyboardLayout*) uchr length: length];
		layout.name = (NSString*) name;
		layout.fullName = (NSString*) fullName;
	}

	pthread_mutex_lock(&g_providedKeyboardLayoutMutex);
	CGSKeyboardLayout* old = g_providedKeyboardLayout;
	g_providedKeyboardLayout = layout;
	pthread_mutex_unlock(&g_providedKeyboardLayoutMutex);
	[old release];
}

// The current keyboard layout of the window-system backend: a dictionary with the 'uchr' data
// (key "data", CFData) and the layout's "name" and "fullName" strings, or NULL when the backend has
// no layout (no connection, or a backend that does not provide one). The caller releases it.
// Used by the Text Input Sources API (HIToolbox).
CFDictionaryRef _CGSCopyCurrentKeyboardLayoutInfo(void)
{
	CGSConnection* connection = _CGSConnectionForID(_CGSDefaultConnection());
	CGSKeyboardLayout* layout = [connection createKeyboardLayout];
	if (!layout)
	{
		pthread_mutex_lock(&g_providedKeyboardLayoutMutex);
		layout = [g_providedKeyboardLayout retain];
		pthread_mutex_unlock(&g_providedKeyboardLayoutMutex);
	}
	if (!layout || !layout.layout || layout.layoutLength == 0)
	{
		[layout release];
		return NULL;
	}

	CFDataRef data = CFDataCreate(NULL, (const UInt8*) layout.layout, layout.layoutLength);
	NSDictionary* info = @{
		@"data": (id) data,
		@"name": layout.name ?: @"?",
		@"fullName": layout.fullName ?: @"?",
	};
	CFRelease(data);
	[layout release];
	return (CFDictionaryRef) [info retain];
}
