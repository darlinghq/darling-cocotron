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

#include <CoreGraphics/CGEvent.h>
#include <CoreGraphics/CGEventSource.h>
#include <stdarg.h>
#include <math.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSScreen.h>
#import "CGEventObjC.h"
#include "CGEventTapInternal.h"

CFTypeID CGEventGetTypeID(void)
{
	return (CFTypeID) [CGEvent self];
}

CGEventRef CGEventCreate(CGEventSourceRef source)
{
	return (CGEventRef) [[CGEvent alloc] initWithSource: source];
}

CGEventRef CGEventCreateCopy(CGEventRef event)
{
	if (!event)
		return NULL;
	return (CGEventRef) [(CGEvent*)event copy];
}

// The data of an event is private to this implementation: a header with a version, then the
// type, flags, time, location, every field that is not 0 and the Unicode string, all as
// little endian fixed size values.
//
// QUIRK: the user data and the state ID of the source are not kept: the event made from the data
// has the default (0) of both. Not documented. Evidence: black-box observation on macOS 26.7.3
// (tier 2): the user data of the source of an event and the state ID of a private source read back 0.
// Test: tests/coregraphics-cgevent-fields.c (test_data_round_trip, "QUIRK test")
#define kEventDataMagic 0x76454743 // "CGEv"
#define kEventDataVersion 1

static void appendU16(NSMutableData* d, uint16_t v)
{
	uint8_t b[2] = { v & 0xFF, v >> 8 };
	[d appendBytes: b length: 2];
}

static void appendU32(NSMutableData* d, uint32_t v)
{
	uint8_t b[4] = { v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24 };
	[d appendBytes: b length: 4];
}

static void appendU64(NSMutableData* d, uint64_t v)
{
	appendU32(d, (uint32_t) v);
	appendU32(d, (uint32_t) (v >> 32));
}

static uint64_t doubleBits(double v)
{
	uint64_t bits;
	memcpy(&bits, &v, sizeof(bits));
	return bits;
}

static double bitsDouble(uint64_t bits)
{
	double v;
	memcpy(&v, &bits, sizeof(v));
	return v;
}

CFDataRef CGEventCreateData(CFAllocatorRef allocator, CGEventRef event)
{
	if (!event)
		return NULL;

	CGEvent* e = (CGEvent*) event;
	NSMutableData* d = [[NSMutableData alloc] init];

	appendU32(d, kEventDataMagic);
	appendU32(d, kEventDataVersion);
	appendU32(d, e->_type);
	appendU32(d, e->_flags);
	appendU64(d, e->_timestamp);
	appendU32(d, e->_locationValid ? 1 : 0);
	appendU64(d, doubleBits(e->_location.x));
	appendU64(d, doubleBits(e->_location.y));

	uint32_t count = 0;
	for (unsigned f = 0; f < CGEVENT_FIELD_COUNT; f++)
	{
		if (e->_fields[f] != 0 && f != kCGEventSourceUserData && f != kCGEventSourceStateID)
			count++;
	}
	appendU32(d, count);
	for (unsigned f = 0; f < CGEVENT_FIELD_COUNT; f++)
	{
		if (e->_fields[f] == 0 || f == kCGEventSourceUserData || f == kCGEventSourceStateID)
			continue;

		appendU16(d, (uint16_t) f);
		appendU64(d, (uint64_t) e->_fields[f]);
	}

	appendU16(d, e->_unicodeLength);
	for (unsigned i = 0; i < e->_unicodeLength; i++)
		appendU16(d, e->_unicodeString[i]);

	CFDataRef rv = CFDataCreate(allocator, [d bytes], [d length]);
	[d release];
	return rv;
}

typedef struct {
	const uint8_t* p;
	size_t left;
	BOOL bad;
} Reader;

static uint64_t readLE(Reader* r, unsigned bytes)
{
	uint64_t v = 0;

	if (r->left < bytes)
	{
		r->bad = YES;
		return 0;
	}
	for (unsigned i = 0; i < bytes; i++)
		v |= ((uint64_t) r->p[i]) << (8 * i);
	r->p += bytes;
	r->left -= bytes;
	return v;
}

CGEventRef CGEventCreateFromData(CFAllocatorRef allocator, CFDataRef data)
{
	if (!data)
		return NULL;

	Reader r = { CFDataGetBytePtr(data), (size_t) CFDataGetLength(data), NO };

	if (readLE(&r, 4) != kEventDataMagic || readLE(&r, 4) != kEventDataVersion)
		return NULL;

	CGEvent* e = [[CGEvent alloc] initWithSource: NULL];

	e->_type = (CGEventType) readLE(&r, 4);
	e->_flags = (uint32_t) readLE(&r, 4);
	e->_timestamp = readLE(&r, 8);
	e->_locationValid = readLE(&r, 4) != 0;
	e->_location.x = bitsDouble(readLE(&r, 8));
	e->_location.y = bitsDouble(readLE(&r, 8));

	// The fields of the writer replace those the new event starts with.
	memset(e->_fields, 0, sizeof(e->_fields));

	uint32_t count = (uint32_t) readLE(&r, 4);
	for (uint32_t i = 0; i < count && !r.bad; i++)
	{
		uint16_t f = (uint16_t) readLE(&r, 2);
		int64_t v = (int64_t) readLE(&r, 8);

		if (f >= CGEVENT_FIELD_COUNT)
			r.bad = YES;
		else
			e->_fields[f] = v;
	}

	uint16_t length = (uint16_t) readLE(&r, 2);
	if (r.bad || r.left != (size_t) length * 2)
	{
		[e release];
		return NULL;
	}
	if (length > 0)
	{
		UniChar* chars = (UniChar*) malloc(length * sizeof(UniChar));
		for (unsigned i = 0; i < length; i++)
			chars[i] = (UniChar) readLE(&r, 2);
		[e setUnicodeString: chars length: length];
		free(chars);
	}

	return (CGEventRef) e;
}

CGEventType CGEventGetType(CGEventRef event)
{
	if (!event)
		return kCGEventNull;
	return ((CGEvent*) event)->_type;
}

void CGEventSetSource(CGEventRef event, CGEventSourceRef source)
{
	if (!event)
		return;
	[(CGEvent*) event takeOverSource: source];
}

CGEventSourceRef CGEventCreateSourceFromEvent(CGEventRef event)
{
	if (!event)
		return NULL;

	CGEvent* e = (CGEvent*) event;
	CGEventSource* source = [[CGEventSource alloc] initWithTableId: (int32_t) e->_fields[kCGEventSourceStateID]];

	source->_userData = e->_fields[kCGEventSourceUserData];
	return (CGEventSourceRef) source;
}

void CGEventSetType(CGEventRef event, CGEventType type)
{
	if (!event)
		return;
	[(CGEvent*) event setType: type];
}

CGEventTimestamp CGEventGetTimestamp(CGEventRef event)
{
	if (!event)
		return 0;
	return ((CGEvent*) event)->_timestamp;
}

void CGEventSetTimestamp(CGEventRef event, CGEventTimestamp timestamp)
{
	if (!event)
		return;
	((CGEvent*) event)->_timestamp = timestamp;
}

CGEventFlags CGEventGetFlags(CGEventRef event)
{
	if (!event)
		return 0;
	return ((CGEvent*) event)->_flags;
}

void CGEventSetFlags(CGEventRef event, CGEventFlags flags)
{
	if (!event)
		return;
	// QUIRK: only the low 32 bits of the flags are kept; the others read back as 0.
	// Documented as a 64 bit value. Evidence: black-box observation on macOS 26.7.3 (tier 2):
	// setting 0x1234567890 reads back 0x34567890.
	// Test: tests/coregraphics-cgevent-fields.c (quirk_flags_keep_32_bits)
	((CGEvent*) event)->_flags = (uint32_t) flags;
}

int64_t CGEventGetIntegerValueField(CGEventRef event, CGEventField field)
{
	if (!event)
		return 0;
	return [(CGEvent*) event integerValueForField: field];
}

void CGEventSetIntegerValueField(CGEventRef event, CGEventField field, int64_t value)
{
	if (!event)
		return;
	[(CGEvent*) event setIntegerValue: value forField: field];
}

double CGEventGetDoubleValueField(CGEventRef event, CGEventField field)
{
	if (!event)
		return 0;
	return [(CGEvent*) event doubleValueForField: field];
}

void CGEventSetDoubleValueField(CGEventRef event, CGEventField field, double value)
{
	if (!event)
		return;
	[(CGEvent*) event setDoubleValue: value forField: field];
}

// The flags a key event has on creation. A key event starts with the flags of the key itself,
// and a modifier key is reported as a flags changed event.
//
// QUIRK: events made with CGEventCreateKeyboardEvent() carry flag bit 0x20000000, which is not
// a documented flag, and the flags that belong to the key code itself: the modifier of a
// modifier key (with its device dependent bit, only while it is pressed), the numeric pad flag
// of the keypad keys and the function flag of the function, arrow, navigation and help keys.
// A modifier key makes a flags changed event. Not documented. Evidence: black-box observation
// on macOS 26.7.3, every key code from 0 to 127 (tier 2).
// Test: tests/coregraphics-cgevent-create.c (quirk_key_event_default_flags)
#define kKeyEventBaseFlags 0x20000000u

static BOOL isModifierKeyCode(CGKeyCode key)
{
	return key >= 54 && key <= 63;
}

static uint32_t modifierKeyFlags(CGKeyCode key)
{
	switch (key)
	{
		case 54: return kCGEventFlagMaskCommand | NX_DEVICERCMDKEYMASK;
		case 55: return kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK;
		case 56: return kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK;
		case 57: return kCGEventFlagMaskAlphaShift;
		case 58: return kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK;
		case 59: return kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK;
		case 60: return kCGEventFlagMaskShift | NX_DEVICERSHIFTKEYMASK;
		case 61: return kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK;
		case 62: return kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK;
		case 63: return kCGEventFlagMaskSecondaryFn;
	}
	return 0;
}

uint32_t _CGEventModifierMaskOfKey(CGKeyCode key)
{
	return isModifierKeyCode(key) ? (modifierKeyFlags(key) & 0xFFFF0000u) : 0;
}

static uint32_t keyClassFlags(CGKeyCode key)
{
	switch (key)
	{
		case 65: case 67: case 69: case 75: case 76: case 78:
		case 81: case 82: case 83: case 84: case 85: case 86: case 87: case 88: case 89:
		case 91: case 92:
			return kCGEventFlagMaskNumericPad;
		case 123: case 124: case 125: case 126:
			return kCGEventFlagMaskNumericPad | kCGEventFlagMaskSecondaryFn;
		case 114:
			return kCGEventFlagMaskHelp | kCGEventFlagMaskSecondaryFn;
		case 64: case 71: case 79: case 80:
		case 96: case 97: case 98: case 99: case 100: case 101: case 103:
		case 105: case 106: case 107: case 109: case 111: case 113:
		case 115: case 116: case 117: case 118: case 119: case 120: case 121: case 122:
			return kCGEventFlagMaskSecondaryFn;
	}
	return 0;
}

CGEventRef CGEventCreateKeyboardEvent(CGEventSourceRef source, CGKeyCode virtualKey, bool keyDown)
{
	CGEventType type = keyDown ? kCGEventKeyDown : kCGEventKeyUp;
	uint32_t flags = kKeyEventBaseFlags;

	if (isModifierKeyCode(virtualKey))
	{
		type = kCGEventFlagsChanged;
		if (keyDown)
			flags |= modifierKeyFlags(virtualKey);
	}
	else
	{
		flags |= keyClassFlags(virtualKey);
	}

	CGEvent* event = [[CGEvent alloc] initWithSource: source type: type];
	CGEventSource* src = (CGEventSource*) source;

	event->_flags = flags;
	event->_fields[kCGKeyboardEventKeycode] = virtualKey;
	// The events of a source nobody gave a keyboard type have type 3, not the type the source reports.
	event->_fields[kCGKeyboardEventKeyboardType] = (src && src->_keyboardTypeSet) ? src->_keyboardType : kCGEventCreatedKeyboardType;

	return (CGEventRef) event;
}

CGEventRef CGEventCreateMouseEvent(CGEventSourceRef source, CGEventType mouseType, CGPoint mouseCursorPosition, CGMouseButton mouseButton)
{
	BOOL pressing;
	int64_t button = 0;

	switch (mouseType)
	{
		case kCGEventLeftMouseDown:
		case kCGEventLeftMouseDragged:
			pressing = YES;
			break;
		case kCGEventRightMouseDown:
		case kCGEventRightMouseDragged:
			pressing = YES;
			button = 1;
			break;
		case kCGEventOtherMouseDown:
		case kCGEventOtherMouseDragged:
			pressing = YES;
			button = mouseButton;
			break;
		case kCGEventLeftMouseUp:
			pressing = NO;
			break;
		case kCGEventRightMouseUp:
			pressing = NO;
			button = 1;
			break;
		case kCGEventOtherMouseUp:
			pressing = NO;
			button = mouseButton;
			break;
		case kCGEventMouseMoved:
			pressing = NO;
			break;
		default:
			// Not a mouse event.
			return NULL;
	}

	CGEvent* event = [[CGEvent alloc] initWithSource: source type: mouseType];

	[event setLocation: mouseCursorPosition];

	// QUIRK: the button number follows the event type for the left and the right button events,
	// and the button argument is only kept for the other button events; the argument is ignored
	// for a mouse moved event. A mouse button event that presses (down, dragged) starts with a
	// click state of 1 and the full pressure (255), a button up or moved event with 0.
	// Documented only as "the button of the event". Evidence: black-box observation on
	// macOS 26.7.3 (tier 2).
	// Test: tests/coregraphics-cgevent-create.c (test_quirk_mouse_event_defaults)
	event->_fields[kCGMouseEventButtonNumber] = button;
	if (pressing)
	{
		event->_fields[kCGMouseEventClickState] = 1;
		event->_fields[kCGMouseEventPressure] = 255;
	}

	return (CGEventRef) event;
}

// The wheel deltas of a scroll event in all their forms. A pixel delta is turned into the lines
// the source says a line is worth.
//
// QUIRK: a pixel delta makes a whole number of lines that is the quotient truncated, but at least one
// line (of the sign of the delta) when there is any movement; its fixed point form is the exact
// quotient truncated, and the event is continuous. A line delta makes the pixel form from the
// source's pixels per line. Documented only as "the wheel value". Evidence: black-box observation
// on macOS 26.7.3 (tier 2). Test: tests/coregraphics-cgevent-create.c (test_scroll_event)
static void setScrollAxis(CGEvent* event, unsigned axis, CGScrollEventUnit units, int32_t wheel, double pixelsPerLine)
{
	if (units == kCGScrollEventUnitPixel)
	{
		double lines = wheel / pixelsPerLine;
		int64_t whole = (int64_t) lines;

		if (whole == 0 && wheel != 0)
			whole = wheel < 0 ? -1 : 1;

		event->_fields[kCGScrollWheelEventDeltaAxis1 + axis] = whole;
		event->_fields[kCGScrollWheelEventFixedPtDeltaAxis1 + axis] = (int64_t) (lines * 65536.0);
		event->_fields[kCGScrollWheelEventPointDeltaAxis1 + axis] = wheel;
	}
	else
	{
		event->_fields[kCGScrollWheelEventDeltaAxis1 + axis] = wheel;
		event->_fields[kCGScrollWheelEventFixedPtDeltaAxis1 + axis] = ((int64_t) wheel) * 65536;
		event->_fields[kCGScrollWheelEventPointDeltaAxis1 + axis] = (int64_t) (wheel * pixelsPerLine);
	}
}

static CGEventRef createScrollWheelEvent(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount, const int32_t* wheels)
{
	if (wheelCount < 1)
		return NULL;
	if (wheelCount > 3)
		wheelCount = 3;

	CGEventSource* src = (CGEventSource*) source;
	double pixelsPerLine = src ? src->_pixelsPerLine : 10;

	if (pixelsPerLine <= 0)
		pixelsPerLine = 10;

	CGEvent* event = [[CGEvent alloc] initWithSource: source type: kCGEventScrollWheel];

	for (uint32_t i = 0; i < wheelCount; i++)
		setScrollAxis(event, i, units, wheels[i], pixelsPerLine);
	event->_fields[kCGScrollWheelEventIsContinuous] = (units == kCGScrollEventUnitPixel);

	return (CGEventRef) event;
}

CGEventRef CGEventCreateScrollWheelEvent(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount, int32_t wheel1, ...)
{
	int32_t wheels[3] = { wheel1, 0, 0 };

	if (wheelCount > 1)
	{
		va_list vl;
		va_start(vl, wheel1);

		wheels[1] = va_arg(vl, int32_t);
		if (wheelCount > 2)
			wheels[2] = va_arg(vl, int32_t);

		va_end(vl);
	}
	return createScrollWheelEvent(source, units, wheelCount, wheels);
}

CGEventRef CGEventCreateScrollWheelEvent2(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount, int32_t wheel1, int32_t wheel2, int32_t wheel3)
{
	int32_t wheels[3] = { wheel1, wheel2, wheel3 };

	return createScrollWheelEvent(source, units, wheelCount, wheels);
}

CGPoint CGEventGetLocation(CGEventRef event)
{
	if (!event)
		return CGPointZero;
	return [(CGEvent*) event location];
}

// Returns location relative to the LOWER left corner
CGPoint CGEventGetUnflippedLocation(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	CGPoint pt = CGEventGetLocation(event);

	CGSConnection* conn = nil;

	if (e->_eventRecord)
		conn = _CGSConnectionFromEventRecord(e->_eventRecord);

	if (!conn)
		conn = _CGSConnectionForID(CGSDefaultConnection);

	// Implementaton should cache this for fast access
	NSArray<CGSScreen*>* screens = [conn createScreens];

	if (!screens)
		return CGPointMake(-1, -1);

	// And currentModeHeight is also cached to speed this up
	pt.y = [screens[0] currentModeHeight] - pt.y;
	[screens release];

	return pt;
}

void CGEventSetLocation(CGEventRef event, CGPoint location)
{
	if (!event)
		return;
	[(CGEvent*) event setLocation: location];
}

void CGEventKeyboardGetUnicodeString(CGEventRef event, UniCharCount maxStringLength, UniCharCount *actualStringLength, UniChar *unicodeString)
{
	CGEvent* e = (CGEvent*) event;
	UniCharCount length = e ? e->_unicodeLength : 0;

	// With no room (a length of 0 or no buffer) only the length is reported.
	if (maxStringLength == 0 || unicodeString == NULL)
	{
		if (actualStringLength)
			*actualStringLength = length;
		return;
	}

	if (length > maxStringLength)
		length = maxStringLength;
	if (length > 0)
		memcpy(unicodeString, e->_unicodeString, length * sizeof(UniChar));
	if (actualStringLength)
		*actualStringLength = length;
}

void CGEventKeyboardSetUnicodeString(CGEventRef event, UniCharCount stringLength, const UniChar *unicodeString)
{
	if (!event)
		return;
	[(CGEvent*) event setUnicodeString: unicodeString length: stringLength];
}

CGEventRef CGEventCreateWithEventRecord(const CGSEventRecordPtr event, uint32_t eventRecordSize)
{
	CGEvent* e = [[CGEvent alloc] initWithEventRecord: event length: eventRecordSize];
	return (CGEventRef) e;
}

CGError CGEventGetEventRecord(CGEventRef event, CGSEventRecordPtr eventRecord, uint32_t eventRecordSize)
{
	CGEvent* e = (CGEvent*) event;

	if (eventRecordSize < e.eventRecordLength)
		return kCGErrorRangeCheck;

	memcpy(eventRecord, e.eventRecord, e.eventRecordLength);
	return kCGErrorSuccess;
}

CGError CGEventSetEventRecord(CGEventRef event, CGSEventRecordPtr eventRecord, uint32_t eventRecordSize)
{
	CGEvent* e = (CGEvent*) event;
	[e setEventRecord: eventRecord length: eventRecordSize];
	return kCGErrorSuccess;
}

uint32_t CGEventGetEventRecordSize(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	return e.eventRecordLength;
}
