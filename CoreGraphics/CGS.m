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
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CGSSurface.h>
#include <pthread.h>
#include <math.h>

static NSMutableDictionary<NSNumber*, CGSConnection*>* g_connections = nil;
static Boolean g_denyConnections = FALSE;

static CGSConnectionID g_defaultConnection = -1;
static pthread_mutex_t g_defaultConnectionMutex = PTHREAD_MUTEX_INITIALIZER;

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

void CGSShutdownServerConnections(void)
{
	@synchronized(g_connections)
	{
		[g_connections removeAllObjects];
	}
	g_defaultConnection = -1;
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

CGError CGSNewConnection(CGSDictionaryObj attribs, CGSConnectionID* connId)
{
	*connId = -1;

	if (g_denyConnections)
		return kCGErrorCannotComplete;

	static dispatch_once_t once;
	dispatch_once(&once, ^{
		_CGSLoadBackend();
	});

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

CGSConnectionID CGSMainConnectionID(void)
{
	if (g_defaultConnection == -1)
	{
		pthread_mutex_lock(&g_defaultConnectionMutex);
		if (g_defaultConnection == -1)
			CGSNewConnection(NULL, &g_defaultConnection);
		pthread_mutex_unlock(&g_defaultConnectionMutex);
	}
	return g_defaultConnection;
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
extern CGError CGSSetWindowAlpha(CGSConnectionID cid, CGSWindowID wid, float alpha);
extern CGError CGSSetWindowLevel(CGSConnectionID cid, CGSWindowID wid, CGWindowLevel level);

CGError CGSSetWindowAlpha(CGSConnectionID cid, CGSWindowID wid, float alpha)
{
	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);

	if (err != kCGSErrorSuccess)
		return err;
	if (isnan(alpha))
		return kCGErrorIllegalArgument;

	return [window setAlpha: fminf(fmaxf(alpha, 0.0f), 1.0f)];
}

// Windows are not composited, so they cannot be transformed or warped. The
// identity transform and removing a warp (a NULL mesh) leave a window as it
// is and succeed; anything else is not implemented.
CGError CGSSetWindowTransform(CGSConnectionID cid, CGSWindowID wid, CGAffineTransform transform)
{
	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);

	if (err != kCGSErrorSuccess)
		return err;
	return CGAffineTransformIsIdentity(transform) ? kCGSErrorSuccess : kCGErrorNotImplemented;
}

CGError CGSSetWindowWarp(CGSConnectionID cid, CGSWindowID wid, int w, int h, float *mesh)
{
	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);

	if (err != kCGSErrorSuccess)
		return err;
	return (mesh == NULL) ? kCGSErrorSuccess : kCGErrorNotImplemented;
}

// Window contents are never captured (see CGDisplayStream), so any shape is
// already excluded from capture.
CGError CGSSetWindowCaptureExcludeShape(CGSConnectionID cid, CGSWindowID wid, CGRegionRef shape)
{
	CGSWindow* window;
	return getWindow(cid, wid, &window);
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
