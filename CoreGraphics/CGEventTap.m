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

// Event taps and posting.
//
// An event that is posted goes through the enabled taps whose mask has its type, in order: first
// the taps of its location (HID, then session, then annotated session; within one location in
// the order head insert and tail append made), then the taps made for a process. A tap that
// listens only is given a copy and does not hold the event up. An active tap is given the event
// and decides: the event it returns goes on, NULL removes the event. The callback is not called
// on the thread that posts: it runs when the run loop the application put the tap's run loop
// source in handles the message sent to the tap's Mach port. That message is the only message
// there is, and only for a tap. The event stream of the process takes what comes out of the
// last tap (CGEventStream.m).
//
// Events keep their order. While an active tap holds an event, every event posted after it waits
// behind it, whether or not its type is in that tap's mask, and the waiting events go on one by
// one, in the order they were posted, once the held event has left the tap (returned, dropped, or
// given up on after the timeout below). So an event the held tap is not interested in cannot reach
// the stream or the taps after it before the held one does. With no active tap holding an event
// nothing waits and an event goes through at once.
//
// Events are delivered in this process only: there is no event router between processes, so an
// event posted to another process is dropped, and the taps of other processes never see an event.

#include "CGEventObjC.h"
#include <CoreGraphics/CGEventSource.h>
#include "CGEventTapInternal.h"
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <notify.h>
#import <Foundation/NSArray.h>

// How long an active tap may keep an event before the system stops waiting for it, disables the
// tap and tells it (kCGEventTapDisabledByTimeout). The time macOS allows is not documented; this
// is a conservative guess, not an observation.
#define kTapTimeoutSeconds 1.0
#define kWatchdogIntervalMs 250

// The groups taps are ordered in: the three locations, then the taps made for one process.
#define kGroupProcess 3
#define kMachMessageId 0x43474554

static uint64_t nowNs(void)
{
	return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

@class CGEventTap;

// The journey of one event through the taps.
@interface CGEventPass : NSObject {
@public
	CGEventRef event;
	NSArray* taps;
	NSUInteger index;
	// While an active tap holds the event: that tap and when it was sent the event.
	CGEventTap* waiting;
	uint64_t sentAt;
	// Which hand-over to an active tap this is (counted from 1), and the one the system gave up
	// waiting for: the pass went on without that tap.
	uint32_t seq, timedOutSeq;
}
@end

@interface CGEventTap : NSObject {
@public
	uint32_t _tapId;
	CGEventTapLocation _location;
	CGEventTapPlacement _placement;
	CGEventTapOptions _options;
	CGEventMask _mask;
	CGEventTapCallBack _callback;
	void* _userInfo;
	// 0 for a tap of a location, else the process the tap was made for
	pid_t _pid;
	BOOL _enabled;
	// The tap was invalidated or is being destroyed.
	BOOL _removed;
	mach_port_t _machPort;
	uint32_t _callCount;
	double _totalLatency, _minLatency, _maxLatency;
}

-(instancetype) initWithLocation: (CGEventTapLocation) location
						pid: (pid_t) pid
					placement: (CGEventTapPlacement) placement
						options: (CGEventTapOptions) options
						mask: (CGEventMask) mask
					callback: (CGEventTapCallBack) callback
					userInfo: (void*) userInfo;
-(CFMachPortRef) createCFMachPort;
-(int) group;
@end

// The registry of the taps: ordered by group, so a pass is the taps from where it enters on.
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static CGEventTap** g_taps;
static size_t g_tapCount, g_tapCapacity;
static uint32_t g_nextTapId = 1;
// Active taps that hold an event now.
static NSMutableArray* g_pending;
// Events that came after an event that is held (or after one of these) and wait to go on, in order.
static NSMutableArray* g_parked;
// Objects that are released once g_lock is dropped: the last release of a tap takes g_lock.
static NSMutableArray* g_garbage;
// Events held or parked: while this is not zero a new event may not take the short way.
static size_t g_inFlight;
static dispatch_source_t g_watchdog;

@implementation CGEventPass
-(void) dealloc
{
	if (event)
		CFRelease(event);
	[taps release];
	[super dealloc];
}
@end

// Releases o, but only after the current holder of g_lock has dropped it (see unlockAndRelease).
static void deferRelease(id o)
{
	if (!g_garbage)
		g_garbage = [[NSMutableArray alloc] init];
	[g_garbage addObject: o];
	[o release];
}

static void updateInFlightLocked(void)
{
	__atomic_store_n(&g_inFlight, [g_pending count] + [g_parked count], __ATOMIC_RELAXED);
}

static void unlockAndRelease(void)
{
	NSMutableArray* garbage = g_garbage;

	g_garbage = nil;
	pthread_mutex_unlock(&g_lock);
	[garbage release];
}

static void cgEventTapCallout(CFMachPortRef mp, void* msg, CFIndex size, void* info);
static void tapInvalidated(CFMachPortRef mp, void* info);

@implementation CGEventTap

-(instancetype) initWithLocation: (CGEventTapLocation) location
						pid: (pid_t) pid
					placement: (CGEventTapPlacement) placement
						options: (CGEventTapOptions) options
						mask: (CGEventMask) mask
					callback: (CGEventTapCallBack) callback
					userInfo: (void*) userInfo
{
	_location = location;
	_pid = pid;
	_placement = placement;
	_options = options;
	_mask = mask;
	_callback = callback;
	_userInfo = userInfo;
	_enabled = YES;
	_minLatency = -1;

	kern_return_t ret = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &_machPort);
	if (KERN_SUCCESS == ret)
		ret = mach_port_insert_right(mach_task_self(), _machPort, _machPort, MACH_MSG_TYPE_MAKE_SEND);
	if (KERN_SUCCESS != ret)
	{
		if (MACH_PORT_NULL != _machPort)
			mach_port_destroy(mach_task_self(), _machPort);
		_machPort = MACH_PORT_NULL;
		[self release];
		return nil;
	}

	// Events pile up while the run loop of the tap is busy.
	mach_port_limits_t limits = { .mpl_qlimit = MACH_PORT_QLIMIT_LARGE };
	mach_port_set_attributes(mach_task_self(), _machPort, MACH_PORT_LIMITS_INFO, (mach_port_info_t) &limits, MACH_PORT_LIMITS_INFO_COUNT);

	return self;
}

-(int) group
{
	return _pid != 0 ? kGroupProcess : (int) _location;
}

static void removeFromRegistryLocked(CGEventTap* tap)
{
	for (size_t i = 0; i < g_tapCount; i++)
	{
		if (g_taps[i] == tap)
		{
			memmove(&g_taps[i], &g_taps[i + 1], (g_tapCount - i - 1) * sizeof(CGEventTap*));
			g_tapCount--;
			break;
		}
	}
}

-(void) dealloc
{
	pthread_mutex_lock(&g_lock);
	_removed = YES;
	removeFromRegistryLocked(self);
	pthread_mutex_unlock(&g_lock);

	if (_machPort != MACH_PORT_NULL)
		mach_port_destroy(mach_task_self(), _machPort);
	[super dealloc];
}

-(CFMachPortRef) createCFMachPort
{
	CFMachPortRef mp;
	CFMachPortContext ctxt = {
		.copyDescription = NULL,
		.info = self,
		.release = (void (*)(const void*)) CFRelease,
		.retain = (const void* (*)(const void*)) CFRetain,
		.version = 0,
	};

	mp = CFMachPortCreateWithPort(NULL, _machPort, cgEventTapCallout, &ctxt, NULL);
	if (mp)
		CFMachPortSetInvalidationCallBack(mp, tapInvalidated);

	return mp;
}

@end

static void registerTap(CGEventTap* tap)
{
	int group = [tap group];
	size_t pos;

	pthread_mutex_lock(&g_lock);

	if (g_tapCount == g_tapCapacity)
	{
		g_tapCapacity = g_tapCapacity ? g_tapCapacity * 2 : 8;
		g_taps = (CGEventTap**) realloc(g_taps, g_tapCapacity * sizeof(CGEventTap*));
	}

	if (tap->_placement == kCGHeadInsertEventTap)
	{
		// Before the taps of its group
		for (pos = 0; pos < g_tapCount && [g_taps[pos] group] < group; pos++)
			;
	}
	else
	{
		// After the taps of its group
		for (pos = 0; pos < g_tapCount && [g_taps[pos] group] <= group; pos++)
			;
	}
	memmove(&g_taps[pos + 1], &g_taps[pos], (g_tapCount - pos) * sizeof(CGEventTap*));
	g_taps[pos] = tap;
	g_tapCount++;
	tap->_tapId = g_nextTapId++;

	pthread_mutex_unlock(&g_lock);
}

static void advancePassLocked(CGEventPass* pass);
static void drainParkedLocked(void);

static void tapInvalidated(CFMachPortRef mp, void* info)
{
	CGEventTap* tap = (CGEventTap*) info;

	pthread_mutex_lock(&g_lock);
	tap->_removed = YES;
	removeFromRegistryLocked(tap);

	// The events the tap holds are not coming back from it: they go on.
	NSMutableArray* released = nil;

	for (NSUInteger i = 0; i < [g_pending count];)
	{
		CGEventPass* pass = [g_pending objectAtIndex: i];

		if (pass->waiting == tap)
		{
			pass->timedOutSeq = pass->seq;
			pass->waiting = nil;
			if (!released)
				released = [[NSMutableArray alloc] init];
			[released addObject: pass];
			[g_pending removeObjectAtIndex: i];
		}
		else
		{
			i++;
		}
	}
	for (CGEventPass* pass in released)
		advancePassLocked(pass);
	drainParkedLocked();
	updateInFlightLocked();
	if (released)
		deferRelease(released);
	unlockAndRelease();

	notify_post(kCGNotifyEventTapRemoved);
}

static CGEventTap* tapForPort(CFMachPortRef mp)
{
	// Called with g_lock held
	mach_port_t port = CFMachPortGetPort(mp);

	for (size_t i = 0; i < g_tapCount; i++)
	{
		if (g_taps[i]->_machPort == port)
			return g_taps[i];
	}
	return nil;
}

static inline BOOL maskHasType(CGEventMask mask, CGEventType type)
{
	if (type >= 64)
		return mask == ~(CGEventMask) 0;
	return (mask >> type) & 1;
}

// Sends the pass to the tap's port. The pass is retained for the receiver of the message.
static BOOL sendToTap(CGEventTap* tap, CGEventPass* pass, BOOL listenOnly, uint32_t seq)
{
	struct TapMachMessage msg;

	memset(&msg, 0, sizeof(msg));
	msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
	msg.header.msgh_size = sizeof(msg);
	msg.header.msgh_remote_port = tap->_machPort;
	msg.header.msgh_id = kMachMessageId;
	msg.pass = [pass retain];
	msg.listenOnly = listenOnly;
	msg.seq = seq;

	// Never wait: a tap that does not keep up must not stop the thread that posts.
	kern_return_t kr = mach_msg(&msg.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof(msg), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);

	if (kr != KERN_SUCCESS)
	{
		[pass release];
		return NO;
	}
	return YES;
}

static void armWatchdogLocked(void);

static void finishPass(CGEventPass* pass)
{
	_CGEventStreamEnqueue(pass->event);
}

// Takes the event on from where it is: through the taps that come next, to the stream. Ends when an
// active tap holds the event (it is then in g_pending and comes back by cgEventTapCallout, the
// watchdog or tapInvalidated) or when the event has been given to the stream. Holds g_lock throughout:
// nothing in here waits, and the order of events is the order in which they are taken on.
static void advancePassLocked(CGEventPass* pass)
{
	for (;;)
	{
		CGEventTap* tap = nil;
		CGEventType type = CGEventGetType(pass->event);

		while (pass->index < [pass->taps count])
		{
			CGEventTap* candidate = [pass->taps objectAtIndex: pass->index++];

			if (candidate->_removed || !candidate->_enabled || !maskHasType(candidate->_mask, type))
				continue;
			// A tap made for another process never sees an event of this one.
			if (candidate->_pid != 0 && candidate->_pid != getpid())
				continue;
			tap = candidate;
			break;
		}

		if (!tap)
		{
			finishPass(pass);
			return;
		}

		if (tap->_options & kCGEventTapOptionListenOnly)
		{
			// The tap listens: it is given a copy to look at, and the event does not wait.
			CGEventPass* listen = [[CGEventPass alloc] init];

			listen->event = CGEventCreateCopy(pass->event);
			if (!sendToTap(tap, listen, YES, 0))
			{
				// The tap does not keep up with the events.
			}
			deferRelease(listen);
			continue;
		}

		pass->waiting = tap;
		pass->sentAt = nowNs();
		uint32_t seq = ++pass->seq;
		if (!g_pending)
			g_pending = [[NSMutableArray alloc] init];
		[g_pending addObject: pass];

		if (sendToTap(tap, pass, NO, seq))
		{
			armWatchdogLocked();
			return;
		}

		// The tap cannot be reached: the event goes on without it.
		pass->waiting = nil;
		[g_pending removeObjectIdenticalTo: pass];
	}
}

// Lets the events that wait go on, one at a time and in order, while no active tap holds an event.
static void drainParkedLocked(void)
{
	while ([g_pending count] == 0 && [g_parked count] > 0)
	{
		CGEventPass* pass = [[g_parked objectAtIndex: 0] retain];

		[g_parked removeObjectAtIndex: 0];
		advancePassLocked(pass);
		deferRelease(pass);
	}
}

// Puts a new event into the pipeline. It waits behind the events that are held or already
// waiting; with none of those it goes on at once. `via` is the tap that posts the event (an event
// a tap posts from its callback goes on from that tap, in front of what waits for the event
// the tap holds).
static void submitPassLocked(CGEventPass* pass, CGEventTap* via)
{
	BOOL viaHolds = NO;

	if (via)
	{
		for (CGEventPass* held in g_pending)
		{
			if (held->waiting == via)
			{
				viaHolds = YES;
				break;
			}
		}
	}

	if (!viaHolds && ([g_pending count] > 0 || [g_parked count] > 0))
	{
		if (!g_parked)
			g_parked = [[NSMutableArray alloc] init];
		[g_parked addObject: pass];
	}
	else
	{
		advancePassLocked(pass);
		drainParkedLocked();
	}
	updateInFlightLocked();
}

// The watchdog gives up on active taps that hold an event for too long.
static void watchdogFired(void)
{
	NSMutableArray* expired = nil;
	uint64_t limit = (uint64_t) (kTapTimeoutSeconds * 1e9);
	uint64_t now = nowNs();

	pthread_mutex_lock(&g_lock);
	for (NSUInteger i = 0; i < [g_pending count];)
	{
		CGEventPass* pass = [g_pending objectAtIndex: i];

		if (now - pass->sentAt > limit)
		{
			// The tap is switched off and the event goes on as it came.
			pass->timedOutSeq = pass->seq;
			pass->waiting->_enabled = NO;
			pass->waiting = nil;
			if (!expired)
				expired = [[NSMutableArray alloc] init];
			[expired addObject: pass];
			[g_pending removeObjectAtIndex: i];
		}
		else
		{
			i++;
		}
	}
	for (CGEventPass* pass in expired)
		advancePassLocked(pass);
	drainParkedLocked();
	updateInFlightLocked();
	if (expired)
		deferRelease(expired);
	if ([g_pending count] == 0 && g_watchdog)
	{
		dispatch_source_cancel(g_watchdog);
		dispatch_release(g_watchdog);
		g_watchdog = NULL;
	}
	unlockAndRelease();
}

static void armWatchdogLocked(void)
{
	if (!g_watchdog)
	{
		g_watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		dispatch_source_set_timer(g_watchdog, dispatch_time(DISPATCH_TIME_NOW, kWatchdogIntervalMs * NSEC_PER_MSEC),
			kWatchdogIntervalMs * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
		dispatch_source_set_event_handler(g_watchdog, ^{ watchdogFired(); });
		dispatch_resume(g_watchdog);
	}
}

static void recordLatency(CGEventTap* tap, uint64_t sentAt)
{
	double micros = (nowNs() - sentAt) / 1000.0;

	pthread_mutex_lock(&g_lock);
	tap->_callCount++;
	tap->_totalLatency += micros;
	if (tap->_minLatency < 0 || micros < tap->_minLatency)
		tap->_minLatency = micros;
	if (micros > tap->_maxLatency)
		tap->_maxLatency = micros;
	pthread_mutex_unlock(&g_lock);
}

static void notifyTimeout(CGEventTap* tap)
{
	// The callback is told with a null event of the notification's type.
	CGEventRef notice = CGEventCreate(NULL);

	CGEventSetType(notice, kCGEventTapDisabledByTimeout);
	tap->_callback((CGEventTapProxy) tap, kCGEventTapDisabledByTimeout, notice, tap->_userInfo);
	CFRelease(notice);
}

// The message of a tap's port: the Mach receive of the tap's run loop source calls this on the
// thread that runs the source.
static void cgEventTapCallout(CFMachPortRef mp, void* msg, CFIndex size, void* info)
{
	CGEventTap* tap = (CGEventTap*) info;
	struct TapMachMessage* message = (struct TapMachMessage*) msg;
	CGEventPass* pass = (CGEventPass*) message->pass;

	if (size < (CFIndex) sizeof(struct TapMachMessage) || message->header.msgh_id != kMachMessageId || pass == nil)
		return;

	[tap retain];

	if (message->listenOnly)
	{
		CGEventRef event = pass->event;

		if (tap->_enabled)
		{
			CGEventRef returned = tap->_callback((CGEventTapProxy) tap, CGEventGetType(event), event, tap->_userInfo);

			if (returned != NULL && returned != event)
				CFRelease(returned);
		}
		[pass release];
		[tap release];
		return;
	}

	CGEventRef event = (CGEventRef) CFRetain(pass->event);
	CGEventRef returned = event;
	BOOL called = NO;

	pthread_mutex_lock(&g_lock);
	BOOL abandoned = (pass->timedOutSeq == message->seq);
	uint64_t sentAt = pass->sentAt;
	pthread_mutex_unlock(&g_lock);

	if (!abandoned && tap->_enabled)
	{
		// What the poster attached describes the event as it was posted: it is only kept while
		// the tap leaves the event as it is (see _CGSEventSetClientData).
		CGEvent* before = _CGSEventGetClientData(event) ? (CGEvent*) CGEventCreateCopy(event) : nil;

		called = YES;
		returned = tap->_callback((CGEventTapProxy) tap, CGEventGetType(event), event, tap->_userInfo);
		if (before != nil && (returned != event || ![(CGEvent*) event hasSameContentAs: before]))
			_CGSEventSetClientData(event, NULL);
		[before release];
	}
	if (called)
		recordLatency(tap, sentAt);

	pthread_mutex_lock(&g_lock);
	// The tap may have taken too long while it ran.
	abandoned = (pass->timedOutSeq == message->seq);
	if (abandoned)
	{
		// The pass has gone on without this tap, which is off now. Whatever the callback
		// returned is of no use.
		if (returned != NULL && returned != event)
			CFRelease(returned);
		CFRelease(event);
		BOOL told = !tap->_removed;
		unlockAndRelease();
		// The callback is told why it is not called any more.
		if (told)
			notifyTimeout(tap);
		[pass release];
		[tap release];
		return;
	}

	// The event leaves the tap: it is not held any more, and it goes on (or ends) before any
	// event that waits behind it.
	pass->waiting = nil;
	[g_pending removeObjectIdenticalTo: pass];

	if (returned == NULL)
	{
		// The tap deletes the event.
		CFRelease(event);
	}
	else
	{
		if (returned != event)
		{
			// The tap made another event: it replaces the original, and the caller of the callback
			// owns the new event until the system has taken it over.
			CGEventRef replaced = pass->event;

			pass->event = (CGEventRef) CFRetain(returned);
			CFRelease(replaced);
			CFRelease(returned);
		}
		CFRelease(event);
		advancePassLocked(pass);
	}
	drainParkedLocked();
	updateInFlightLocked();
	unlockAndRelease();

	[pass release];
	[tap release];
}

// MARK: public interface

static CGEventTap* createTap(CGEventTapLocation location, pid_t pid, CGEventTapPlacement place, CGEventTapOptions options,
	CGEventMask mask, CGEventTapCallBack callback, void* userInfo, CFMachPortRef* outPort)
{
	if (callback == NULL || location > kCGAnnotatedSessionEventTap || place > kCGTailAppendEventTap
		|| (options & ~kCGEventTapOptionListenOnly) != 0)
		return nil;

	CGEventTap* tap = [[CGEventTap alloc] initWithLocation: location
													pid: pid
												placement: place
													options: options
													mask: mask
												callback: callback
												userInfo: userInfo];
	if (!tap)
		return nil;

	CFMachPortRef mp = [tap createCFMachPort];

	// The port holds the tap now.
	[tap release];
	if (!mp)
		return nil;

	registerTap(tap);
	notify_post(kCGNotifyEventTapAdded);
	*outPort = mp;
	return tap;
}

CFMachPortRef CGEventTapCreate(CGEventTapLocation tap, CGEventTapPlacement place,
	CGEventTapOptions options, CGEventMask eventsOfInterest, CGEventTapCallBack callback, void *userInfo)
{
	CFMachPortRef mp = NULL;

	createTap(tap, 0, place, options, eventsOfInterest, callback, userInfo, &mp);
	return mp;
}

CFMachPortRef CGEventTapCreateForPid(pid_t pid, CGEventTapPlacement place,
	CGEventTapOptions options, CGEventMask eventsOfInterest, CGEventTapCallBack callback, void *userInfo)
{
	CFMachPortRef mp = NULL;

	if (pid <= 0)
		return NULL;
	createTap(kCGAnnotatedSessionEventTap, pid, place, options, eventsOfInterest, callback, userInfo, &mp);
	return mp;
}

// The process a process serial number names, as far as this layer knows: the one of the calling
// process (kCurrentProcess, or its Unix process ID as the low word). Process serial numbers of
// other processes are not resolved here.
static pid_t pidOfSerialNumber(const void* psn)
{
	const uint32_t* words = (const uint32_t*) psn;
	uint32_t high, low;

	if (!psn)
		return 0;
	high = words[0];
	low = words[1];
	if (high == 0 && (low == 2 /* kCurrentProcess */ || low == (uint32_t) getpid()))
		return getpid();
	return 0;
}

CFMachPortRef CGEventTapCreateForPSN(void *processSerialNumber, CGEventTapPlacement place,
	CGEventTapOptions options, CGEventMask eventsOfInterest, CGEventTapCallBack callback, void *userInfo)
{
	const uint32_t* words = (const uint32_t*) processSerialNumber;
	pid_t pid = pidOfSerialNumber(processSerialNumber);

	if (!processSerialNumber)
		return NULL;
	if (pid == 0)
	{
		// A tap for a process of another number: it exists, and sees nothing of this process.
		pid = (pid_t) words[1];
		if (pid <= 0)
			pid = INT32_MAX;
	}
	return CGEventTapCreateForPid(pid, place, options, eventsOfInterest, callback, userInfo);
}

void CGEventTapEnable(CFMachPortRef tap, bool enable)
{
	if (!tap)
		return;

	pthread_mutex_lock(&g_lock);

	CGEventTap* t = tapForPort(tap);

	if (t)
		t->_enabled = enable;

	pthread_mutex_unlock(&g_lock);
}

bool CGEventTapIsEnabled(CFMachPortRef tap)
{
	bool enabled = false;

	if (!tap)
		return false;

	pthread_mutex_lock(&g_lock);

	CGEventTap* t = tapForPort(tap);

	if (t)
		enabled = t->_enabled;

	pthread_mutex_unlock(&g_lock);
	return enabled;
}

void _CGEventPostToPipeline(CGEventRef event, CGEventTapLocation location, pid_t pid, bool copy)
{
	int firstGroup = location;

	if (!event)
		return;
	if (location > kCGAnnotatedSessionEventTap)
		return;
	// An event for a process: from the annotated session on, which is where the events for a
	// process are.
	if (pid != 0)
		firstGroup = kCGAnnotatedSessionEventTap;
	// Nothing is delivered to another process.
	if (pid != 0 && pid != getpid())
		return;

	CGEvent* e = copy ? (CGEvent*) CGEventCreateCopy(event) : (CGEvent*) CFRetain(event);

	if (e->_timestamp == 0)
		e->_timestamp = nowNs();

	_CGEventStateRecordEvent((CGEventRef) e);

	// Without taps (the usual case) the event goes straight on. A tap made at this very moment
	// may miss the event, which is the same as the tap having been made a moment later. Events
	// that are held or waiting come first, though.
	if (__atomic_load_n(&g_tapCount, __ATOMIC_RELAXED) == 0 && __atomic_load_n(&g_inFlight, __ATOMIC_RELAXED) == 0)
	{
		_CGEventStreamEnqueue((CGEventRef) e);
		CFRelease(e);
		return;
	}

	CGEventPass* pass = [[CGEventPass alloc] init];

	pass->event = (CGEventRef) e;

	pthread_mutex_lock(&g_lock);
	NSMutableArray* snapshot = [[NSMutableArray alloc] initWithCapacity: g_tapCount];
	size_t i = 0;

	while (i < g_tapCount && [g_taps[i] group] < firstGroup)
		i++;
	for (; i < g_tapCount; i++)
		[snapshot addObject: g_taps[i]];
	pass->taps = snapshot;
	submitPassLocked(pass, nil);
	unlockAndRelease();

	[pass release];
}

void CGEventPost(CGEventTapLocation tap, CGEventRef event)
{
	_CGEventPostToPipeline(event, tap, 0, true);
}

void CGEventPostToPid(pid_t pid, CGEventRef event)
{
	if (!event || pid <= 0)
		return;

	// The target of the event is named on the event that is delivered, not on the caller's.
	CGEvent* e = (CGEvent*) CGEventCreateCopy(event);

	e->_fields[kCGEventTargetUnixProcessID] = pid;
	_CGEventPostToPipeline((CGEventRef) e, kCGSessionEventTap, pid, false);
	CFRelease(e);
}

void CGEventPostToPSN(void *processSerialNumber, CGEventRef event)
{
	pid_t pid = pidOfSerialNumber(processSerialNumber);

	if (!event || !processSerialNumber)
		return;
	if (pid == 0)
	{
		// A process this layer cannot name is not this process: the event goes nowhere.
		return;
	}

	CGEvent* e = (CGEvent*) CGEventCreateCopy(event);

	e->_fields[kCGEventTargetProcessSerialNumber] = ((int64_t) ((const uint32_t*) processSerialNumber)[0] << 32) | ((const uint32_t*) processSerialNumber)[1];
	_CGEventPostToPipeline((CGEventRef) e, kCGSessionEventTap, pid, false);
	CFRelease(e);
}

void CGEventTapPostEvent(CGEventTapProxy proxy, CGEventRef event)
{
	CGEventTap* tap = (CGEventTap*) proxy;

	if (!event)
		return;

	CGEvent* e = (CGEvent*) CGEventCreateCopy(event);

	if (e->_timestamp == 0)
		e->_timestamp = nowNs();

	CGEventPass* pass = [[CGEventPass alloc] init];

	pass->event = (CGEventRef) e;

	_CGEventStateRecordEvent((CGEventRef) e);

	pthread_mutex_lock(&g_lock);
	// From the tap after the one of the proxy on. A proxy that is not a tap of the registry
	// starts at the first tap.
	size_t i = 0;

	for (size_t j = 0; j < g_tapCount; j++)
	{
		if (g_taps[j] == tap)
		{
			i = j + 1;
			break;
		}
	}

	NSMutableArray* snapshot = [[NSMutableArray alloc] initWithCapacity: g_tapCount];

	for (; i < g_tapCount; i++)
		[snapshot addObject: g_taps[i]];
	pass->taps = snapshot;

	submitPassLocked(pass, tap);
	unlockAndRelease();

	[pass release];
}

CGError CGGetEventTapList(uint32_t maxNumberOfTaps, CGEventTapInformation *tapList, uint32_t *eventTapCount)
{
	if (!eventTapCount)
		return kCGErrorIllegalArgument;

	pthread_mutex_lock(&g_lock);

	if (tapList == NULL)
	{
		*eventTapCount = (uint32_t) g_tapCount;
	}
	else
	{
		uint32_t n = 0;

		for (size_t i = 0; i < g_tapCount && n < maxNumberOfTaps; i++, n++)
		{
			CGEventTap* t = g_taps[i];
			CGEventTapInformation* info = &tapList[n];

			memset(info, 0, sizeof(*info));
			info->eventTapID = t->_tapId;
			info->tapPoint = t->_location;
			info->options = t->_options;
			info->eventsOfInterest = t->_mask;
			info->tappingProcess = getpid();
			info->processBeingTapped = t->_pid;
			info->enabled = t->_enabled;
			info->minUsecLatency = t->_callCount ? (float) t->_minLatency : 0;
			info->avgUsecLatency = t->_callCount ? (float) (t->_totalLatency / t->_callCount) : 0;
			info->maxUsecLatency = (float) t->_maxLatency;
		}
		*eventTapCount = n;
	}

	pthread_mutex_unlock(&g_lock);
	return kCGErrorSuccess;
}
