/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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

// The event stream of the process: the events that went through the event taps and are for this
// process, in the order they arrived. The frameworks above CoreGraphics read it (HIToolbox, on
// the thread that waits for events); nothing is sent over Mach ports for an event.
//
// The stream keeps events only while a reader is registered (_CGSEventStreamSetReadySource):
// nobody would ever take them out otherwise, and a program that only posts events must not
// grow.

#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <pthread.h>
#include <stdlib.h>
#include "CGEventTapInternal.h"

// More than this many events wait for the reader: the new ones are dropped.
#define kStreamCapacityLimit 65536

static pthread_mutex_t g_streamLock = PTHREAD_MUTEX_INITIALIZER;
static CGEventRef* g_ring;
static size_t g_ringCapacity, g_ringHead, g_ringCount;
static CFRunLoopSourceRef g_readySource;
static CFRunLoopRef g_readyRunLoop;
// The reader has been told that there is something to read and has not seen the stream empty since.
static bool g_signalled;

void _CGEventStreamEnqueue(CGEventRef event)
{
	CFRunLoopSourceRef source = NULL;
	CFRunLoopRef runLoop = NULL;

	pthread_mutex_lock(&g_streamLock);

	if (g_readySource == NULL || g_ringCount >= kStreamCapacityLimit)
	{
		pthread_mutex_unlock(&g_streamLock);
		return;
	}

	if (g_ringCount == g_ringCapacity)
	{
		size_t newCapacity = g_ringCapacity ? g_ringCapacity * 2 : 64;
		CGEventRef* newRing = (CGEventRef*) malloc(newCapacity * sizeof(CGEventRef));

		for (size_t i = 0; i < g_ringCount; i++)
			newRing[i] = g_ring[(g_ringHead + i) % g_ringCapacity];
		free(g_ring);
		g_ring = newRing;
		g_ringCapacity = newCapacity;
		g_ringHead = 0;
	}

	g_ring[(g_ringHead + g_ringCount) % g_ringCapacity] = (CGEventRef) CFRetain(event);
	g_ringCount++;

	if (!g_signalled)
	{
		g_signalled = true;
		source = (CFRunLoopSourceRef) CFRetain(g_readySource);
		runLoop = (CFRunLoopRef) CFRetain(g_readyRunLoop);
	}

	pthread_mutex_unlock(&g_streamLock);

	if (source)
	{
		CFRunLoopSourceSignal(source);
		CFRunLoopWakeUp(runLoop);
		CFRelease(source);
		CFRelease(runLoop);
	}
}

void _CGSEventStreamPost(CGEventRef event)
{
	if (event)
		_CGEventPostToPipeline(event, kCGHIDEventTap, 0, false);
}

CGEventRef _CGSEventStreamCopyNextEvent(void)
{
	CGEventRef event = NULL;

	pthread_mutex_lock(&g_streamLock);

	if (g_ringCount > 0)
	{
		event = g_ring[g_ringHead];
		g_ringHead = (g_ringHead + 1) % g_ringCapacity;
		g_ringCount--;
	}
	else
	{
		g_signalled = false;
	}

	pthread_mutex_unlock(&g_streamLock);
	return event;
}

void _CGSEventStreamSetReadySource(CFRunLoopSourceRef source, CFRunLoopRef runLoop)
{
	CFRunLoopSourceRef oldSource;
	CFRunLoopRef oldRunLoop;
	bool signalNow = false;
	CGEventRef* discarded = NULL;
	size_t discardedCount = 0;

	if (source)
		CFRetain(source);
	if (runLoop)
		CFRetain(runLoop);

	pthread_mutex_lock(&g_streamLock);

	oldSource = g_readySource;
	oldRunLoop = g_readyRunLoop;
	g_readySource = runLoop ? source : NULL;
	g_readyRunLoop = source ? runLoop : NULL;

	if (g_readySource == NULL)
	{
		// Nobody reads any more: what is waiting is not wanted.
		discarded = g_ring;
		discardedCount = g_ringCount;
		if (discarded)
		{
			// Keep the order for the release loop below.
			CGEventRef* copy = (CGEventRef*) malloc(discardedCount * sizeof(CGEventRef) + 1);
			for (size_t i = 0; i < discardedCount; i++)
				copy[i] = g_ring[(g_ringHead + i) % g_ringCapacity];
			free(g_ring);
			discarded = copy;
		}
		g_ring = NULL;
		g_ringCapacity = g_ringHead = g_ringCount = 0;
		g_signalled = false;
	}
	else if (g_ringCount > 0)
	{
		g_signalled = true;
		signalNow = true;
	}
	else
	{
		g_signalled = false;
	}

	pthread_mutex_unlock(&g_streamLock);

	if (signalNow)
	{
		CFRunLoopSourceSignal(source);
		CFRunLoopWakeUp(runLoop);
	}

	for (size_t i = 0; i < discardedCount; i++)
		CFRelease(discarded[i]);
	free(discarded);

	if (oldSource)
		CFRelease(oldSource);
	if (oldRunLoop)
		CFRelease(oldRunLoop);
	// The retains taken above are the ones the stream keeps; a NULL pair keeps none.
	if (!(source && runLoop))
	{
		if (source)
			CFRelease(source);
		if (runLoop)
			CFRelease(runLoop);
	}
}
