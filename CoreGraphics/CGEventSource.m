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
#include "CGEventObjC.h"
#include <CoreGraphics/CGEventSource.h>
#include <CoreGraphics/CGSConnection.h>
#include <pthread.h>
#include <stdlib.h>
#include <time.h>
#include "CGEventTapInternal.h"

// The state tables behind CGEventSourceKeyState() and friends. There is one table for the
// combined session state, one for the HID system state and one for every private source. Posted
// events change them (see _CGEventStateRecordEvent), so the state is what the events the process
// has posted would make it.

#define kTypeSlots 32
// The slot of "any input event" is after those of the types.
#define kAnySlot kTypeSlots

typedef struct {
	int32_t id;
	uint32_t flags;
	uint64_t keys[4];
	uint32_t buttons;
	uint64_t lastTime[kTypeSlots + 1];
	uint32_t counter[kTypeSlots + 1];
} StateTable;

static pthread_mutex_t g_tablesLock = PTHREAD_MUTEX_INITIALIZER;
static StateTable g_combined = { .id = kCGEventStateTableCombined };
static StateTable g_hid = { .id = kCGEventStateTableHID };
static StateTable** g_privateTables;
static size_t g_privateCount, g_privateCapacity;

static StateTable* findTableLocked(int32_t id)
{
	if (id == kCGEventStateTableCombined)
		return &g_combined;
	if (id == kCGEventStateTableHID)
		return &g_hid;
	for (size_t i = 0; i < g_privateCount; i++)
	{
		if (g_privateTables[i]->id == id)
			return g_privateTables[i];
	}
	return NULL;
}

int32_t _CGEventStateNewPrivateTable(void)
{
	StateTable* table = (StateTable*) calloc(1, sizeof(StateTable));

	pthread_mutex_lock(&g_tablesLock);
	do
	{
		table->id = (int32_t) (arc4random() & 0x7FFFFFFF);
	} while (table->id <= kCGEventStateTableHID || findTableLocked(table->id) != NULL);

	if (g_privateCount == g_privateCapacity)
	{
		g_privateCapacity = g_privateCapacity ? g_privateCapacity * 2 : 8;
		g_privateTables = (StateTable**) realloc(g_privateTables, g_privateCapacity * sizeof(StateTable*));
	}
	g_privateTables[g_privateCount++] = table;
	pthread_mutex_unlock(&g_tablesLock);

	return table->id;
}

void _CGEventStateReleasePrivateTable(int32_t tableId)
{
	pthread_mutex_lock(&g_tablesLock);
	for (size_t i = 0; i < g_privateCount; i++)
	{
		if (g_privateTables[i]->id == tableId)
		{
			free(g_privateTables[i]);
			g_privateTables[i] = g_privateTables[--g_privateCount];
			break;
		}
	}
	pthread_mutex_unlock(&g_tablesLock);
}

static void setKey(StateTable* t, CGKeyCode key, bool down)
{
	if (key >= 256)
		return;
	if (down)
		t->keys[key / 64] |= 1ULL << (key % 64);
	else
		t->keys[key / 64] &= ~(1ULL << (key % 64));
}

static void recordInTable(StateTable* t, CGEvent* e)
{
	CGEventType type = e->_type;
	CGKeyCode key = (CGKeyCode) e->_fields[kCGKeyboardEventKeycode];
	uint32_t button = (uint32_t) e->_fields[kCGMouseEventButtonNumber];

	switch (type)
	{
		case kCGEventKeyDown:
			setKey(t, key, true);
			break;
		case kCGEventKeyUp:
			setKey(t, key, false);
			break;
		case kCGEventFlagsChanged:
		{
			// A modifier key is down while its flag is set.
			uint32_t mask = _CGEventModifierMaskOfKey(key);

			if (mask)
				setKey(t, key, (e->_flags & mask) != 0);
			break;
		}
		case kCGEventLeftMouseDown:
		case kCGEventRightMouseDown:
		case kCGEventOtherMouseDown:
			if (button < 32)
				t->buttons |= 1u << button;
			break;
		case kCGEventLeftMouseUp:
		case kCGEventRightMouseUp:
		case kCGEventOtherMouseUp:
			if (button < 32)
				t->buttons &= ~(1u << button);
			break;
		default:
			break;
	}

	// The modifier flags a key, button or flags event reports are those of the state.
	if (type == kCGEventKeyDown || type == kCGEventKeyUp || type == kCGEventFlagsChanged || _CGEventClassOfType(type) == CGEventClassMouse)
		t->flags = e->_flags & 0x00FF0000u;

	if (type != kCGEventNull && type < kTypeSlots)
	{
		t->counter[type]++;
		t->lastTime[type] = e->_timestamp;
		t->counter[kAnySlot]++;
		t->lastTime[kAnySlot] = e->_timestamp;
	}
}

void _CGEventStateRecordEvent(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	int32_t id = (int32_t) e->_fields[kCGEventSourceStateID];

	pthread_mutex_lock(&g_tablesLock);

	StateTable* t = findTableLocked(id);

	if (t)
		recordInTable(t, e);
	// What the hardware does is what the session sees.
	if (id == kCGEventStateTableHID)
		recordInTable(&g_combined, e);

	pthread_mutex_unlock(&g_tablesLock);
}

bool _CGEventStateKeyDown(int32_t tableId, CGKeyCode key, bool* known)
{
	bool down = false;

	pthread_mutex_lock(&g_tablesLock);

	StateTable* t = findTableLocked(tableId);

	if (known)
		*known = (t != NULL);
	if (t && key < 256)
		down = (t->keys[key / 64] >> (key % 64)) & 1;

	pthread_mutex_unlock(&g_tablesLock);
	return down;
}

bool _CGEventStateButtonDown(int32_t tableId, CGMouseButton button, bool* known)
{
	bool down = false;

	pthread_mutex_lock(&g_tablesLock);

	StateTable* t = findTableLocked(tableId);

	if (known)
		*known = (t != NULL);
	if (t && button < 32)
		down = (t->buttons >> button) & 1;

	pthread_mutex_unlock(&g_tablesLock);
	return down;
}

bool _CGEventStateFlags(int32_t tableId, CGEventFlags* flags)
{
	pthread_mutex_lock(&g_tablesLock);

	StateTable* t = findTableLocked(tableId);

	if (t)
		*flags = t->flags;

	pthread_mutex_unlock(&g_tablesLock);
	return t != NULL;
}

static int slotOfType(CGEventType type)
{
	if (type == kCGAnyInputEventType)
		return kAnySlot;
	return type < kTypeSlots ? (int) type : -1;
}

bool _CGEventStateLastEventTime(int32_t tableId, CGEventType type, uint64_t* time)
{
	int slot = slotOfType(type);
	bool found = false;

	pthread_mutex_lock(&g_tablesLock);

	StateTable* t = findTableLocked(tableId);

	if (t && slot >= 0)
	{
		*time = t->lastTime[slot];
		found = true;
	}

	pthread_mutex_unlock(&g_tablesLock);
	return found;
}

bool _CGEventStateCounter(int32_t tableId, CGEventType type, uint32_t* count)
{
	int slot = slotOfType(type);
	bool found = false;

	pthread_mutex_lock(&g_tablesLock);

	StateTable* t = findTableLocked(tableId);

	if (t && slot >= 0)
	{
		*count = t->counter[slot];
		found = true;
	}

	pthread_mutex_unlock(&g_tablesLock);
	return found;
}

////////////////////////////////////////////////////////////////

CFTypeID CGEventSourceGetTypeID(void) {
    return (CFTypeID)[CGEventSource self];
}

CGEventSourceRef CGEventSourceCreate(CGEventSourceStateID stateID) {
    if (stateID != kCGEventSourceStatePrivate &&
        stateID != kCGEventSourceStateCombinedSessionState &&
        stateID != kCGEventSourceStateHIDSystemState)
        return NULL;
    return (CGEventSourceRef) [[CGEventSource alloc] initWithState: stateID];
}

CGEventSourceKeyboardType CGEventSourceGetKeyboardType(CGEventSourceRef source)
{
    CGEventSource *src = (CGEventSource *) source;
    return src ? src.keyboardType : kCGEventDefaultKeyboardTypeOfSource;
}

void CGEventSourceSetKeyboardType(CGEventSourceRef source,
                                  CGEventSourceKeyboardType keyboardType)
{
    CGEventSource *src = (CGEventSource *) source;
    src.keyboardType = keyboardType;
}

// The ID of the state of the source: 0 and 1 for the combined and the HID state, a number that
// belongs to the source for a private one (the state ID the state functions take).
CGEventSourceStateID CGEventSourceGetSourceStateID(CGEventSourceRef source) {
    CGEventSource *src = (CGEventSource *) source;
    return src ? src->_tableId : 0;
}

int64_t CGEventSourceGetUserData(CGEventSourceRef source) {
    CGEventSource *src = (CGEventSource *) source;
    return src.userData;
}

void CGEventSourceSetUserData(CGEventSourceRef source, int64_t userData) {
    CGEventSource *src = (CGEventSource *) source;
    src.userData = userData;
}

double CGEventSourceGetPixelsPerLine(CGEventSourceRef source) {
    CGEventSource *src = (CGEventSource *) source;
    return src.pixelsPerLine;
}

void CGEventSourceSetPixelsPerLine(CGEventSourceRef source,
                                   double pixelsPerLine)
{
    CGEventSource *src = (CGEventSource *) source;
    src.pixelsPerLine = pixelsPerLine;
}

static CGSConnection *hardwareStateConnection(CGEventSourceStateID stateID);

// The flags of the posted events, and for the combined and the HID state also the modifiers the window system
// reports as held (what the keys decoded so far say), like the key and button state.
CGEventFlags CGEventSourceFlagsState(CGEventSourceStateID stateID) {
    CGEventFlags flags = 0;

    _CGEventStateFlags(stateID, &flags);
    return flags | (CGEventFlags) [hardwareStateConnection(stateID) hardwareModifierFlags];
}

// The time the local mouse events are suppressed after CGWarpMouseCursorPosition(), for the whole session
// (documented default 0.25 seconds). A negative one is refused (observed on macOS 26.7.3 and Mojave).
static _Atomic(double) gLocalEventsSuppressionInterval = 0.25;

CGError CGSetLocalEventsSuppressionInterval(CFTimeInterval seconds) {
    if (!(seconds >= 0))
        return kCGErrorRangeCheck;
    __c11_atomic_store(&gLocalEventsSuppressionInterval, seconds, __ATOMIC_RELAXED);
    return kCGErrorSuccess;
}

double _CGSLocalEventsSuppressionInterval(void) {
    return __c11_atomic_load(&gLocalEventsSuppressionInterval, __ATOMIC_RELAXED);
}

void CGEventSourceSetLocalEventsSuppressionInterval(CGEventSourceRef source, CFTimeInterval seconds) {
    CGEventSource *src = (CGEventSource *) source;

    if (src)
        src->_suppressionInterval = seconds;
}

CFTimeInterval CGEventSourceGetLocalEventsSuppressionInterval(CGEventSourceRef source) {
    CGEventSource *src = (CGEventSource *) source;
    return src ? src->_suppressionInterval : 0;
}

void CGEventSourceSetLocalEventsFilterDuringSuppressionState(CGEventSourceRef source,
                                                             CGEventFilterMask filter,
                                                             CGEventSuppressionState state)
{
    CGEventSource *src = (CGEventSource *) source;

    if (src && state < kCGNumberOfEventSuppressionStates)
        src->_filters[state] = filter;
}

CGEventFilterMask CGEventSourceGetLocalEventsFilterDuringSuppressionState(CGEventSourceRef source,
                                                                          CGEventSuppressionState state)
{
    CGEventSource *src = (CGEventSource *) source;

    if (!src || state >= kCGNumberOfEventSuppressionStates)
        return 0;
    return src->_filters[state];
}

// The hardware state of the window system, for the states that follow it.
static CGSConnection *hardwareStateConnection(CGEventSourceStateID stateID) {
    if (stateID != kCGEventSourceStateCombinedSessionState &&
        stateID != kCGEventSourceStateHIDSystemState)
        return nil;
    return _CGSConnectionForID(CGSDefaultConnection);
}

// The posted events decide first; the combined and the HID state also follow the keys and
// buttons the window system reports as down.
bool CGEventSourceKeyState(CGEventSourceStateID stateID, CGKeyCode key) {
    if (_CGEventStateKeyDown(stateID, key, NULL))
        return true;
    return [hardwareStateConnection(stateID) isKeyDown: key];
}

bool CGEventSourceButtonState(CGEventSourceStateID stateID, CGMouseButton button) {
    if (_CGEventStateButtonDown(stateID, button, NULL))
        return true;
    return [hardwareStateConnection(stateID) isMouseButtonDown: button];
}

static CFTimeInterval secondsSince(uint64_t last, BOOL neverIsStartup)
{
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);

    if (last == 0)
    {
        // The event never happened: the time since the system started, for a private state.
        // The window system's events do not pass through the tables yet, so for the other states
        // an event "just happened", which is what this function has always reported.
        return neverIsStartup ? now / 1e9 : 0;
    }
    return now > last ? (now - last) / 1e9 : 0;
}

CFTimeInterval CGEventSourceSecondsSinceLastEventType(CGEventSourceStateID stateID,
                                                      CGEventType eventType)
{
    uint64_t last;

    if (!_CGEventStateLastEventTime(stateID, eventType, &last))
        return 0;
    return secondsSince(last, stateID != kCGEventSourceStateCombinedSessionState && stateID != kCGEventSourceStateHIDSystemState);
}

uint32_t CGEventSourceCounterForEventType(CGEventSourceStateID stateID,
                                          CGEventType eventType)
{
    uint32_t count = 0;

    _CGEventStateCounter(stateID, eventType, &count);
    return count;
}

// The user's double-click interval is the "com.apple.mouse.doubleClickThreshold" setting of the global
// domain, in seconds. Without one it is one second, which is what AppKit's NSEvent doubleClickInterval
// reported before the window system's pointer was decoded here, and what clicks were grouped by.
double _CGSDoubleClickInterval(void)
{
	double interval = 1.0;
	CFTypeRef value = CFPreferencesCopyAppValue(CFSTR("com.apple.mouse.doubleClickThreshold"), kCFPreferencesAnyApplication);

	if (value != NULL)
	{
		double number = 0;

		if (CFGetTypeID(value) == CFNumberGetTypeID() && CFNumberGetValue(value, kCFNumberDoubleType, &number) && number > 0)
			interval = number;
		CFRelease(value);
	}
	return interval;
}
