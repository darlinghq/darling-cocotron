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
#import <CoreGraphics/CGSNativeConnection.h>
#include <pthread.h>
#include <stdio.h>
#include <CoreFoundation/CFNotificationCenter.h>
#include <notify.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

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
	// The framework with the windows draws on the process' native connection, so it stays.
	if ([CGSConnection nativeObserver] != nil)
		return;
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

static void registerProcessConnection(void);

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
		registerProcessConnection();
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

// The window server registry of processes that checked in: a process that opened a connection to
// the window system records itself under a libnotify name of its own pid. The state is the
// process' start time (in clock ticks since boot), so the entry of a process that ended is not
// taken for the one that got its pid afterwards. Both sides run without the window system.
static uint64_t processStartTime(pid_t pid)
{
	char path[64];
	snprintf(path, sizeof(path), "/proc/%d/stat", (int) pid);
	FILE* file = fopen(path, "r");
	if (file == NULL)
		return 0;

	char line[1024];
	size_t length = fread(line, 1, sizeof(line) - 1, file);
	fclose(file);
	line[length] = 0;

	// The process name (field 2) is in parentheses and may contain anything; the start time is
	// field 22, that is the 20th field after the closing parenthesis.
	char* cursor = strrchr(line, ')');
	if (cursor == NULL)
		return 0;
	for (int field = 0; field < 20 && cursor != NULL; field++)
	{
		cursor = strchr(cursor + 1, ' ');
		if (cursor == NULL)
			return 0;
	}
	return strtoull(cursor + 1, NULL, 10);
}

static BOOL registryName(pid_t pid, char* name, size_t size)
{
	return snprintf(name, size, kCGSProcessConnectionNotificationPrefix "%d", (int) pid) < (int) size;
}

static void registerProcessConnection(void)
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		char name[64];
		int token;
		uint64_t start = processStartTime(getpid());

		if (!registryName(getpid(), name, sizeof(name)) ||
			notify_register_check(name, &token) != NOTIFY_STATUS_OK)
			return;
		notify_set_state(token, start != 0 ? start : 1);
		// The token stays registered; the entry is replaced by the next process with this pid.
	});
}

Boolean _CGSProcessHasConnection(pid_t pid)
{
	if (pid <= 0 || (kill(pid, 0) != 0 && errno != EPERM))
		return false;

	char name[64];
	int token;
	uint64_t state = 0;

	if (!registryName(pid, name, sizeof(name)) || notify_register_check(name, &token) != NOTIFY_STATUS_OK)
		return false;
	if (notify_get_state(token, &state) != NOTIFY_STATUS_OK)
		state = 0;
	notify_cancel(token);
	if (state == 0)
		return false;

	uint64_t start = processStartTime(pid);
	return start == 0 ? state == 1 : state == start;
}

CGError _CGSActivateProcess(pid_t pid, uint32_t options)
{
	if (pid <= 0)
		return kCGErrorIllegalArgument;

	// A process that never connected to the window system has no windows to activate.
	if (pid != getpid() && !_CGSProcessHasConnection(pid))
		return kCGErrorCannotComplete;

	// The display server first, directly. Whatever it cannot do (it has no such request, or the
	// process has no window of its own kind there, as a Wayland client has none on an X server
	// that Xwayland provides) is asked of the process itself.
	_CGSLoadBackendOnce();
	if (g_backendClass != nil &&
		[g_backendClass activateWindowsOfProcess: pid options: options] == kCGErrorSuccess)
		return kCGErrorSuccess;

	// libnotify, as the other requests to a process (see _CGSSendProcessCommand): the Darwin center of
	// CFNotificationCenter does not reach other processes. The target's connection to the window system
	// receives it.
	char name[64];
	snprintf(name, sizeof(name), kCGSProcessActivationNotificationPrefix "%d", (int) pid);
	return notify_post(name) == NOTIFY_STATUS_OK ? kCGErrorSuccess : kCGErrorCannotComplete;
}

#define kCGSProcessHiddenNotificationPrefix "org.darlinghq.process-hidden."

CGError _CGSSendProcessCommand(pid_t pid, uint32_t command)
{
	const char* prefix;

	switch (command)
	{
		case kCGSProcessCommandHide: prefix = kCGSProcessHideNotificationPrefix; break;
		case kCGSProcessCommandUnhide: prefix = kCGSProcessUnhideNotificationPrefix; break;
		case kCGSProcessCommandQuit: prefix = kCGSProcessQuitNotificationPrefix; break;
		default: return kCGErrorIllegalArgument;
	}
	if (pid <= 0)
		return kCGErrorIllegalArgument;
	if (pid != getpid() && !_CGSProcessHasConnection(pid))
		return kCGErrorCannotComplete;

	// libnotify, as the registry and the hidden state: the Darwin center of CFNotificationCenter does
	// not reach other processes.
	char name[96];
	snprintf(name, sizeof(name), "%s%d", prefix, (int) pid);
	return notify_post(name) == NOTIFY_STATUS_OK ? kCGErrorSuccess : kCGErrorCannotComplete;
}

// The state of the process' libnotify name is its start time while its application is hidden, else
// 0, so a later process with the same pid does not inherit it. The process is the only writer.
void _CGSSetProcessHidden(Boolean hidden)
{
	static dispatch_once_t once;
	static int token = -1;

	dispatch_once(&once, ^{
		char name[64];

		snprintf(name, sizeof(name), kCGSProcessHiddenNotificationPrefix "%d", (int) getpid());
		if (notify_register_check(name, &token) != NOTIFY_STATUS_OK)
			token = -1;
	});
	if (token < 0)
		return;
	uint64_t start = processStartTime(getpid());
	notify_set_state(token, hidden ? (start != 0 ? start : 1) : 0);
}

Boolean _CGSProcessIsHidden(pid_t pid)
{
	if (pid <= 0 || (kill(pid, 0) != 0 && errno != EPERM))
		return false;

	char name[64];
	int token;
	uint64_t state = 0;

	snprintf(name, sizeof(name), kCGSProcessHiddenNotificationPrefix "%d", (int) pid);
	if (notify_register_check(name, &token) != NOTIFY_STATUS_OK)
		return false;
	if (notify_get_state(token, &state) != NOTIFY_STATUS_OK)
		state = 0;
	notify_cancel(token);
	if (state == 0)
		return false;

	uint64_t start = processStartTime(pid);
	return start == 0 ? state == 1 : state == start;
}

// The activation policy of the application of a process (NSApplicationActivationPolicy: 0 regular,
// 1 accessory, 2 prohibited), published by the process under a libnotify name of its own pid, with
// its start time like the other per-process state, so that other processes know what kind of
// application they deal with: a regular application takes the menu bar over when it becomes the
// front process, an accessory one does not, a prohibited one cannot be the front process.
#define kCGSProcessPolicyNotificationPrefix "org.darlinghq.process-policy."

void _CGSSetProcessActivationPolicy(int policy)
{
	static dispatch_once_t once;
	static int token = -1;

	if (policy < 0 || policy > 2)
		return;
	dispatch_once(&once, ^{
		char name[64];

		snprintf(name, sizeof(name), kCGSProcessPolicyNotificationPrefix "%d", (int) getpid());
		if (notify_register_check(name, &token) != NOTIFY_STATUS_OK)
			token = -1;
	});
	if (token < 0)
		return;
	uint64_t start = processStartTime(getpid());
	notify_set_state(token, (start != 0 ? start : 1) * 4 + (uint64_t) (policy + 1));
}

CGError _CGSGetProcessActivationPolicy(pid_t pid, int* policy)
{
	if (pid <= 0 || policy == NULL)
		return kCGErrorIllegalArgument;
	if (kill(pid, 0) != 0 && errno != EPERM)
		return kCGErrorNoneAvailable;

	char name[64];
	int token;
	uint64_t state = 0;

	snprintf(name, sizeof(name), kCGSProcessPolicyNotificationPrefix "%d", (int) pid);
	if (notify_register_check(name, &token) != NOTIFY_STATUS_OK)
		return kCGErrorCannotComplete;
	if (notify_get_state(token, &state) != NOTIFY_STATUS_OK)
		state = 0;
	notify_cancel(token);
	if ((state & 3) == 0)
		return kCGErrorNoneAvailable;

	uint64_t start = processStartTime(pid);
	if ((start != 0 ? start : 1) != state / 4)
		return kCGErrorNoneAvailable;
	*policy = (int) (state & 3) - 1;
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

// Per-process flags (the input focus, the menu bar ownership) are kept by the process itself, under
// a libnotify name of its own pid (state: its start time while the flag is set, 0 once cleared), so
// that no two processes ever write the same state.
static BOOL processFlagName(const char* prefix, pid_t pid, char* name, size_t size)
{
	return snprintf(name, size, "%s%d", prefix, (int) pid) < (int) size;
}

static CGError setProcessFlag(const char* prefix, int* token, pid_t* token_pid, pid_t pid, BOOL value)
{
	char name[64];

	@synchronized([CGSConnection class])
	{
		if (*token < 0 || *token_pid != pid)
		{
			// The names of other processes' pids are only set on their behalf; the token of the
			// previous pid is not needed any more.
			if (*token >= 0)
				notify_cancel(*token);
			*token = -1;
			if (!processFlagName(prefix, pid, name, sizeof(name)) ||
				notify_register_check(name, token) != NOTIFY_STATUS_OK)
			{
				*token = -1;
				return kCGErrorCannotComplete;
			}
			*token_pid = pid;
		}
		uint64_t start = processStartTime(pid);
		if (notify_set_state(*token, value ? (start != 0 ? start : 1) : 0) != NOTIFY_STATUS_OK)
			return kCGErrorCannotComplete;
	}
	return kCGErrorSuccess;
}

static BOOL processFlag(const char* prefix, pid_t pid)
{
	char name[64];
	int token;
	uint64_t state = 0;

	if (!processFlagName(prefix, pid, name, sizeof(name)) || notify_register_check(name, &token) != NOTIFY_STATUS_OK)
		return NO;
	if (notify_get_state(token, &state) != NOTIFY_STATUS_OK)
		state = 0;
	notify_cancel(token);
	if (state == 0)
		return NO;
	uint64_t start = processStartTime(pid);
	return start == 0 ? state == 1 : state == start;
}

#define kCGSProcessFocusPrefix "org.darlinghq.process-focus."
#define kCGSProcessMenuBarPrefix "org.darlinghq.process-menubar."

static CGError setProcessFocus(pid_t pid, BOOL focused)
{
	static pid_t token_pid;
	static int token = -1;
	return setProcessFlag(kCGSProcessFocusPrefix, &token, &token_pid, pid, focused);
}

static BOOL processHasFocus(pid_t pid)
{
	return processFlag(kCGSProcessFocusPrefix, pid);
}

// The process that reported last that it has the focus, as long as it has not resigned since; this
// is all the processes themselves know, whichever display server there is.
static CGError reportedFrontProcess(pid_t* pid)
{
	int token = frontProcessToken();
	uint64_t state = 0;
	if (token < 0 || notify_get_state(token, &state) != NOTIFY_STATUS_OK)
		return kCGErrorCannotComplete;
	if (state == 0 || state > INT32_MAX || !processHasFocus((pid_t) state))
		return kCGErrorNoneAvailable;
	*pid = (pid_t) state;
	return kCGErrorSuccess;
}

static void syncFrontObservers(void);

CGError _CGSGetFrontProcess(pid_t* pid)
{
	if (pid == NULL)
		return kCGErrorIllegalArgument;

	// The processes report their focus gains and losses (and SetFrontProcess requests, which take
	// effect at once, as on macOS), so what they reported is the answer. The display server is only
	// asked when no process has the focus, to find a client that is not a Darling process (X11)
	// or that is one that does not report.
	CGError err = reportedFrontProcess(pid);
	if (err == kCGErrorSuccess)
		return err;

	_CGSLoadBackendOnce();
	if (g_backendClass != nil)
	{
		pid_t front = 0;
		err = [g_backendClass copyFrontProcessID: &front];
		if (err == kCGErrorSuccess)
		{
			*pid = front;
			return kCGErrorSuccess;
		}
		if (err != kCGErrorNotImplemented)
			return err;
	}

	return kCGErrorNoneAvailable;
}

CGError _CGSSetFrontProcess(pid_t pid)
{
	if (pid <= 0)
		return kCGErrorIllegalArgument;

	int token = frontProcessToken();
	CGError err = setProcessFocus(pid, YES);
	if (err != kCGErrorSuccess)
		return err;
	if (token < 0 || notify_set_state(token, (uint64_t) pid) != NOTIFY_STATUS_OK)
		return kCGErrorCannotComplete;
	// Every process that follows the front process (see kCGSFrontProcessNotificationName) asks again.
	notify_post(kCGSFrontProcessNotificationName);
	syncFrontObservers();
	return kCGErrorSuccess;
}

CGError _CGSResignFrontProcess(pid_t pid)
{
	if (pid <= 0)
		return kCGErrorIllegalArgument;

	CGError err = setProcessFocus(pid, NO);
	if (err != kCGErrorSuccess)
		return err;
	notify_post(kCGSFrontProcessNotificationName);
	syncFrontObservers();
	return kCGErrorSuccess;
}

// The process that owns the menu bar: a libnotify name holds its pid, and the process has marked
// itself (the start time again protects against a reused pid).
static int menuBarOwnerToken(void)
{
	static dispatch_once_t once;
	static int token = -1;
	dispatch_once(&once, ^{
		if (notify_register_check(kCGSMenuBarOwnerNotificationName, &token) != NOTIFY_STATUS_OK)
			token = -1;
	});
	return token;
}

CGError _CGSSetMenuBarOwnerProcess(pid_t pid)
{
	static pid_t token_pid;
	static int token = -1;

	if (pid <= 0)
		return kCGErrorIllegalArgument;

	int owner = menuBarOwnerToken();
	CGError err = setProcessFlag(kCGSProcessMenuBarPrefix, &token, &token_pid, pid, YES);
	if (err != kCGErrorSuccess)
		return err;
	if (owner < 0 || notify_set_state(owner, (uint64_t) pid) != NOTIFY_STATUS_OK)
		return kCGErrorCannotComplete;
	// The processes that follow the front process follow the menu bar owner too.
	notify_post(kCGSFrontProcessNotificationName);
	return kCGErrorSuccess;
}

CGError _CGSGetMenuBarOwnerProcess(pid_t* pid)
{
	if (pid == NULL)
		return kCGErrorIllegalArgument;

	int token = menuBarOwnerToken();
	uint64_t state = 0;
	if (token < 0 || notify_get_state(token, &state) != NOTIFY_STATUS_OK)
		return kCGErrorCannotComplete;
	if (state == 0 || state > INT32_MAX || !processFlag(kCGSProcessMenuBarPrefix, (pid_t) state))
		return kCGErrorNoneAvailable;

	// The processes that have the focus report it (and their resigning). Once the last process that
	// reported has resigned, another client of the display server has the focus, and no process
	// owns the menu bar then.
	pid_t front = 0;
	if (reportedFrontProcess(&front) != kCGErrorSuccess)
		return kCGErrorNoneAvailable;
	*pid = (pid_t) state;
	return kCGErrorSuccess;
}

// Observers of the front process, in this process. The transitions are detected by comparing the
// front process with the one the observers saw last, whichever process changed it and whether it
// was by a report, a request or the focus leaving: the change is noticed when libnotify delivers
// the name of kCGSFrontProcessNotificationName, and at once, in the calling thread, when this
// process itself reports or requests, so that a caller that goes on to post its own
// notifications finds the observers have run first.
typedef struct
{
	CGSFrontProcessObserver proc;
	void* info;
} FrontObserver;

static pthread_mutex_t g_frontObserverLock = PTHREAD_MUTEX_INITIALIZER;
static FrontObserver g_frontObservers[8];
static unsigned g_frontObserverCount;
static pid_t g_lastFront;
static BOOL g_syncingFront, g_syncFrontAgain;
static int g_frontWatchToken = -1;

static pid_t currentFrontOrNone(void)
{
	pid_t front = 0;
	if (_CGSGetFrontProcess(&front) != kCGErrorSuccess || front <= 0)
		return 0;
	return front;
}

static void runFrontObservers(void)
{
	for (;;)
	{
		FrontObserver observers[8];
		unsigned count;
		pid_t previous, now = currentFrontOrNone();

		pthread_mutex_lock(&g_frontObserverLock);
		if (g_syncingFront)
		{
			// Called from an observer; the loop of the outer call looks again.
			g_syncFrontAgain = YES;
			pthread_mutex_unlock(&g_frontObserverLock);
			return;
		}
		previous = g_lastFront;
		if (previous == now || g_frontObserverCount == 0)
		{
			g_lastFront = now;
			pthread_mutex_unlock(&g_frontObserverLock);
			return;
		}
		g_lastFront = now;
		g_syncingFront = YES;
		g_syncFrontAgain = NO;
		count = g_frontObserverCount;
		memcpy(observers, g_frontObservers, sizeof(observers));
		pthread_mutex_unlock(&g_frontObserverLock);

		for (unsigned i = 0; i < count; i++)
			observers[i].proc(previous, now, observers[i].info);

		pthread_mutex_lock(&g_frontObserverLock);
		g_syncingFront = NO;
		BOOL again = g_syncFrontAgain;
		pthread_mutex_unlock(&g_frontObserverLock);
		if (!again)
			return;
	}
}

static void syncFrontObservers(void)
{
	pthread_mutex_lock(&g_frontObserverLock);
	unsigned count = g_frontObserverCount;
	pthread_mutex_unlock(&g_frontObserverLock);
	if (count == 0)
		return;

	if (pthread_main_np())
		runFrontObservers();
	else
		dispatch_async(dispatch_get_main_queue(), ^{
			runFrontObservers();
		});
}

void _CGSAddFrontProcessObserver(CGSFrontProcessObserver proc, void* info)
{
	if (proc == NULL)
		return;

	pthread_mutex_lock(&g_frontObserverLock);
	if (g_frontObserverCount == sizeof(g_frontObservers) / sizeof(g_frontObservers[0]))
	{
		pthread_mutex_unlock(&g_frontObserverLock);
		return;
	}
	BOOL first = g_frontObserverCount == 0;
	g_frontObservers[g_frontObserverCount].proc = proc;
	g_frontObservers[g_frontObserverCount].info = info;
	g_frontObserverCount++;
	pthread_mutex_unlock(&g_frontObserverLock);

	pid_t now = currentFrontOrNone();
	if (first)
	{
		pthread_mutex_lock(&g_frontObserverLock);
		g_lastFront = now;
		pthread_mutex_unlock(&g_frontObserverLock);
		notify_register_dispatch(kCGSFrontProcessNotificationName, &g_frontWatchToken, dispatch_get_main_queue(),
								 ^(int ignored) {
									 runFrontObservers();
								 });
	}
	// A process that is the front process when it starts to watch has become it just now.
	if (now == getpid())
		proc(0, now, info);
}

CGError _CGSRequestFrontProcess(pid_t pid, uint32_t options)
{
	if (pid <= 0)
		return kCGErrorIllegalArgument;

	// The state changes at once and for every process, as on macOS, where GetFrontProcess() and
	// NSWorkspace already answer with the requested process when the call returns. The window
	// system is asked to move the input focus after it; the processes report their focus as
	// before, which keeps the state right when the window system takes another decision.
	pid_t front = 0;
	if (reportedFrontProcess(&front) != kCGErrorSuccess || front != pid)
	{
		CGError err = _CGSSetFrontProcess(pid);
		if (err != kCGErrorSuccess)
			return err;
	}
	if (options & kCGSRequestFrontProcessMenuBarOwner)
	{
		CGError err = _CGSSetMenuBarOwnerProcess(pid);
		if (err != kCGErrorSuccess)
			return err;
	}

	// Whether the windows could be asked to activate is not an error of the request.
	(void) _CGSActivateProcess(pid, (options & kCGSRequestFrontProcessFrontWindowOnly) ? kCGSActivateProcessFrontWindowOnly : 0);
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

static CGSConnection* nativeConnection(void)
{
	CGSConnectionID connId = CGSMainConnectionID();
	return connId != 0 ? _CGSConnectionForID(connId) : nil;
}

CGSNativeConnectionKind _CGSNativeConnectionKind(void)
{
	CGSConnection* connection = nativeConnection();
	return connection != nil ? (CGSNativeConnectionKind) [[connection class] nativeConnectionKind] : CGSNativeConnectionKindNone;
}

void* _CGSNativeConnectionDisplay(void)
{
	CGSConnection* connection = nativeConnection();
	return connection != nil ? [connection nativeDisplay] : NULL;
}

void _CGSSetNativeConnectionObserver(id<CGSNativeConnectionObserver> observer)
{
	[CGSConnection setNativeObserver: observer];
}

void _CGSProcessNativeConnectionEvents(void)
{
	[nativeConnection() processPendingEvents];
}

void* _CGSNativeConnectionKeyboardFocus(void)
{
	return [nativeConnection() keyboardFocus];
}

uint64_t _CGSNativeConnectionModifierFlags(void)
{
	return [nativeConnection() modifierFlags];
}

BOOL _CGSNativeConnectionRelativeMouseState(BOOL* requested, CGPoint* frozenRoot)
{
	return [nativeConnection() relativeMouseState: requested frozenRoot: frozenRoot];
}

void _CGSNativeConnectionAccumulateMouseDelta(double dx, double dy)
{
	[nativeConnection() accumulateMouseDeltaX: dx y: dy];
}

void _CGSNativeConnectionPointerWindowsChanged(void)
{
	[nativeConnection() pointerWindowsChanged];
}

void _CGSNativeConnectionObjectDestroyed(void* object)
{
	[nativeConnection() nativeObjectDestroyed: object];
}

void _CGSNativeConnectionFlushPendingKeyboardEvents(void)
{
	[nativeConnection() flushPendingKeyboardEvents];
}

void* _CGSNativeConnectionPointer(void)
{
	return [nativeConnection() nativePointer];
}

void _CGSNativeConnectionSetPointerSurfacePoint(double x, double y)
{
	[nativeConnection() setPointerSurfacePointX: x y: y];
}

bool _CGSSetCursorHiddenUntilMouseMoves(bool flag)
{
	CGSConnection* connection = nativeConnection();

	if (![connection managesPointer] || ![connection cancelsHiddenUntilMouseMoves])
		return false;
	[connection setCursorHiddenUntilMouseMoves: flag];
	return true;
}

bool _CGSNativeConnectionCursorHidden(void)
{
	CGSConnection* connection = nativeConnection();

	return [connection managesPointer] && ![connection cursorIsVisible];
}

bool _CGSNativeConnectionPointerLocked(void)
{
	return [nativeConnection() pointerLocked];
}

bool _CGSNativeConnectionDisplayIdle(void)
{
	return [nativeConnection() displayIdle];
}

void _CGSNativeConnectionPointerLockTargetChanged(void)
{
	[nativeConnection() pointerLockTargetMayHaveChanged];
}

int _CGSNativeConnectionKeyboardLayoutGroup(CFStringRef* name)
{
	CGSConnection* connection = nativeConnection();
	int group = [connection keyboardLayoutGroup];

	if (name != NULL)
		*name = group >= 0 ? (CFStringRef) [[connection keyboardLayoutName] retain] : NULL;
	return group;
}

void* _CGSNativeWindowForID(CGSConnectionID connId, CGSWindowID winId)
{
	CGSConnection* conn = _CGSConnectionForID(connId);
	return [[conn windowForId: winId] nativeWindow];
}

// The surfaces of application windows (see _CGSAddWindowSurface). They are not CGSSurface
// objects: there is no CGS window behind an application window, only a native drawable, so
// the registry keeps what the window server calls need: the ids, the drawable and its size.
typedef struct WindowSurface
{
	CGSSurfaceID surfaceId;
	CGSWindowID windowId;
	void* nativeWindow;
	CGSize size;
	struct WindowSurface* next;
} WindowSurface;

static WindowSurface* g_windowSurfaces = NULL;
static pthread_mutex_t g_windowSurfacesMutex = PTHREAD_MUTEX_INITIALIZER;
// Surface ids of application windows start apart from the ones of CGS windows, which count
// up from 1 on each window.
static CGSSurfaceID g_nextWindowSurfaceId = 0x1000;

CGSSurfaceID _CGSAddWindowSurface(CGSWindowID winId, void* nativeWindow, CGSize size)
{
	WindowSurface* surface = (WindowSurface*) calloc(1, sizeof(WindowSurface));
	if (!surface)
		return 0;
	surface->windowId = winId;
	surface->nativeWindow = nativeWindow;
	surface->size = size;

	pthread_mutex_lock(&g_windowSurfacesMutex);
	surface->surfaceId = g_nextWindowSurfaceId++;
	surface->next = g_windowSurfaces;
	g_windowSurfaces = surface;
	pthread_mutex_unlock(&g_windowSurfacesMutex);
	return surface->surfaceId;
}

void _CGSSetWindowSurfaceSize(CGSSurfaceID surfaceId, CGSize size)
{
	pthread_mutex_lock(&g_windowSurfacesMutex);
	for (WindowSurface* s = g_windowSurfaces; s != NULL; s = s->next)
	{
		if (s->surfaceId == surfaceId)
		{
			s->size = size;
			break;
		}
	}
	pthread_mutex_unlock(&g_windowSurfacesMutex);
}

void _CGSRemoveWindowSurface(CGSSurfaceID surfaceId)
{
	pthread_mutex_lock(&g_windowSurfacesMutex);
	for (WindowSurface** link = &g_windowSurfaces; *link != NULL; link = &(*link)->next)
	{
		if ((*link)->surfaceId == surfaceId)
		{
			WindowSurface* gone = *link;
			*link = gone->next;
			free(gone);
			break;
		}
	}
	pthread_mutex_unlock(&g_windowSurfacesMutex);
}

bool _CGSWindowSurfaceForNativeWindow(void* nativeWindow, CGSConnectionID* connId,
                                      CGSWindowID* winId, CGSSurfaceID* surfaceId)
{
	bool found = false;
	pthread_mutex_lock(&g_windowSurfacesMutex);
	for (WindowSurface* s = g_windowSurfaces; s != NULL; s = s->next)
	{
		if (s->nativeWindow == nativeWindow)
		{
			*connId = _CGSDefaultConnection();
			*winId = s->windowId;
			*surfaceId = s->surfaceId;
			found = true;
			break;
		}
	}
	pthread_mutex_unlock(&g_windowSurfacesMutex);
	return found;
}

// The registered surface of an application window, copied out.
static bool windowSurfaceForIDs(CGSWindowID winId, CGSSurfaceID surfaceId, WindowSurface* out)
{
	bool found = false;
	pthread_mutex_lock(&g_windowSurfacesMutex);
	for (WindowSurface* s = g_windowSurfaces; s != NULL; s = s->next)
	{
		if (s->windowId == winId && s->surfaceId == surfaceId)
		{
			*out = *s;
			found = true;
			break;
		}
	}
	pthread_mutex_unlock(&g_windowSurfacesMutex);
	return found;
}

void* _CGSNativeWindowForSurfaceID(CGSConnectionID connId, CGSWindowID winId, CGSSurfaceID surfaceId)
{
	CGSConnection* conn = _CGSConnectionForID(connId);
	void* native = [[[conn windowForId: winId] surfaceForId: surfaceId] nativeWindow];
	WindowSurface surface;
	if (native == NULL && conn != nil && windowSurfaceForIDs(winId, surfaceId, &surface))
		native = surface.nativeWindow;
	return native;
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

	// The process' main connection is the one the observer's windows live on.
	if ([CGSConnection nativeObserver] != nil && connId == CGSMainConnectionID())
		return kCGSErrorSuccess;

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

// The bounds of one of the application's own windows, by window number, in global display
// coordinates (origin at the top left of the main display). An AppKit window is not a CGS
// window, but its number is a window id like any other, so the window server calls that take
// one see its frame, including the title bar.
static bool applicationWindowBounds(CGSWindowID wid, CGRect* outBounds)
{
	CGWindow* window = platformWindowForID(wid);
	if (!window)
		return false;
	CGRect frame = [window frame];
	if (CGRectIsNull(frame))
		return false;
	// The frame is in AppKit's global space, with the origin at the bottom left of the main display.
	frame.origin.y = CGDisplayBounds(CGMainDisplayID()).size.height - CGRectGetMaxY(frame);
	*outBounds = frame;
	return true;
}

// QUIRK: a failed CGSGetWindowBounds() reports kCGErrorFailure for a window
// that does not exist, and sets the result to CGRectNull. Not documented.
// Evidence: black-box observation on macOS 26.7.3 (tier 2).
// Test: coregraphics-cgs-bounds.c (test_quirk_missing_window_bounds).
CGError CGSGetWindowBounds(CGSConnectionID cid, CGSWindowID wid, CGRect *outBounds)
{
	if (outBounds == NULL)
		return kCGErrorIllegalArgument;

	CGSWindow* window;
	CGError err = getWindow(cid, wid, &window);

	if (err == kCGErrorIllegalArgument) {
		if (applicationWindowBounds(wid, outBounds))
			return kCGSErrorSuccess;
		*outBounds = CGRectNull;
		return kCGErrorFailure;
	}
	if (err != kCGSErrorSuccess)
		return err;

	return [window getRect: outBounds];
}

// The bounds last given to CGSSetSurfaceBounds(). QUIRK: until then they are
// CGRectNull. Not documented. Evidence: black-box observation on macOS 26.7.3
// (tier 2). Test: coregraphics-cgs-bounds.c (test_quirk_surface_bounds_null).
CGError CGSGetSurfaceBounds(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid, CGRect *outBounds)
{
	if (outBounds == NULL)
		return kCGErrorIllegalArgument;

	CGSSurface* surface;
	CGError err = getSurface(cid, wid, sid, &surface);

	if (err == kCGErrorIllegalArgument)
	{
		// A drawable of an application window: it covers its own area, from its origin.
		WindowSurface windowSurface;
		if (windowSurfaceForIDs(wid, sid, &windowSurface))
		{
			*outBounds = CGRectMake(0, 0, windowSurface.size.width, windowSurface.size.height);
			return kCGSErrorSuccess;
		}
	}
	if (err != kCGSErrorSuccess)
		return err;

	return [surface getBounds: outBounds];
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

// Posts a hot key press or release, as a system-defined event, to the event stream, and tells the
// procs registered for such events. Called by the backends (through -postHotKeyEventForUID:...) on the main run loop.
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

	// The hot key is an event of the process like any other: it goes through the event taps into
	// the event stream, which HIToolbox reads (and AppKit through it). The procs registered for
	// system-defined events are told about it as well.
	CGEventRef event = CGEventCreateWithEventRecord(&record, sizeof(record));

	if (event)
	{
		_CGSEventStreamPost(event);
		CFRelease(event);
	}

	for (NSData* entry in procs)
	{
		const NotifyProcEntry* e = [entry bytes];
		e->proc(e->notificationType, &record, sizeof(record), e->private);
	}
}

// The current keyboard layout of the window-system backend: a dictionary with the 'uchr' data
// (key "data", CFData) and the layout's "name" and "fullName" strings, or NULL when the backend has
// no layout (no connection, or a connection that cannot describe one). The caller releases it.
// Used by the Text Input Sources API (HIToolbox).
CFDictionaryRef _CGSCopyCurrentKeyboardLayoutInfo(void)
{
	CGSConnection* connection = _CGSConnectionForID(_CGSDefaultConnection());
	CGSKeyboardLayout* layout = [connection createKeyboardLayout];
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
