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
#import <Foundation/NSKeyedArchiver.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSScreen.h>
#import "CGEventObjC.h"

CFTypeID CGEventGetTypeID(void)
{
	return (CFTypeID) [CGEvent self];
}

CGEventRef CGEventCreate(CGEventSourceRef source)
{
	return (CGEventRef) [[CGEvent alloc] initWithSource: (CGEventSource*) source];
}

CGEventRef CGEventCreateCopy(CGEventRef event)
{
	return (CGEventRef) [(CGEvent*)event copy];
}

CFDataRef CGEventCreateData(CFAllocatorRef allocator, CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	NSData* data = [NSKeyedArchiver archivedDataWithRootObject: e];

	return (CFDataRef) [data retain];
}

CGEventRef CGEventCreateFromData(CFAllocatorRef allocator, CFDataRef data)
{
	NSKeyedUnarchiver* unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: (NSData*) data];
	
	CGEvent* e = [unarchiver decodeObject];

	[unarchiver finishDecoding];
	[unarchiver release];
	
	return (CGEventRef) e;
}

CGEventType CGEventGetType(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	return e.type;
}

void CGEventSetSource(CGEventRef event, CGEventSourceRef source)
{
	CGEvent* e = (CGEvent*) event;
	e.source = (CGEventSource*) source;
}

CGEventSourceRef CGEventCreateSourceFromEvent(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	return (CGEventSourceRef) [(CGEventSource*) e.source retain];
}

void CGEventSetType(CGEventRef event, CGEventType type)
{
	CGEvent* e = (CGEvent*) event;
	e.type = type;
}

CGEventTimestamp CGEventGetTimestamp(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	return e.timestamp;
}

void CGEventSetTimestamp(CGEventRef event, CGEventTimestamp timestamp)
{
	CGEvent* e = (CGEvent*) event;
	e.timestamp = timestamp;
}

CGEventFlags CGEventGetFlags(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	return e.flags;
}

void CGEventSetFlags(CGEventRef event, CGEventFlags flags)
{
	CGEvent* e = (CGEvent*) event;
	e.flags = flags;
}

int64_t CGEventGetIntegerValueField(CGEventRef event, CGEventField field)
{
	CGEvent* e = (CGEvent*) event;
	NSNumber* value = e.fields[[NSNumber numberWithInt: field]];

	if (!value)
		return 0;
	return value.longLongValue;
}

void CGEventSetIntegerValueField(CGEventRef event, CGEventField field, int64_t value)
{
	CGEvent* e = (CGEvent*) event;
	e.fields[[NSNumber numberWithInt: field]] = [NSNumber numberWithLongLong: value];
}

double CGEventGetDoubleValueField(CGEventRef event, CGEventField field)
{
	CGEvent* e = (CGEvent*) event;
	NSNumber* value = e.fields[[NSNumber numberWithInt: field]];

	if (!value)
		return 0;

	if (field == kCGScrollWheelEventFixedPtDeltaAxis1 || field == kCGScrollWheelEventFixedPtDeltaAxis2
		|| field == kCGScrollWheelEventFixedPtDeltaAxis3)
	{
		int64_t fixedPt = value.longLongValue;
		return ((double)fixedPt) / 0x00010000;
	}

	return value.doubleValue;
}

void CGEventSetDoubleValueField(CGEventRef event, CGEventField field, double value)
{
	CGEvent* e = (CGEvent*) event;

	if (field == kCGScrollWheelEventFixedPtDeltaAxis1 || field == kCGScrollWheelEventFixedPtDeltaAxis2
		|| field == kCGScrollWheelEventFixedPtDeltaAxis3)
	{
		int64_t fixedPt = (int64_t) (value * 0x00010000);
		e.fields[[NSNumber numberWithInt: field]] = [NSNumber numberWithLongLong: fixedPt];
	}
	else
	{
		e.fields[[NSNumber numberWithInt: field]] = [NSNumber numberWithDouble: value];
	}
}

CGEventRef CGEventCreateKeyboardEvent(CGEventSourceRef source, CGKeyCode virtualKey, bool keyDown)
{
	CGEventType type = keyDown ? kCGEventKeyDown : kCGEventKeyUp;
	CGEvent* event = [[CGEvent alloc] initWithSource: (CGEventSource*) source type: type];
	event.virtualKey = virtualKey;

	return (CGEventRef) event;
}

CGEventRef CGEventCreateMouseEvent(CGEventSourceRef source, CGEventType mouseType, CGPoint mouseCursorPosition, CGMouseButton mouseButton)
{
	CGEvent* event = [[CGEvent alloc] initWithSource: (CGEventSource*) source type: mouseType];
	event.location = mouseCursorPosition;
	event.mouseButton = mouseButton;
	return (CGEventRef) event;
}

CGEventRef CGEventCreateScrollWheelEvent(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount, int32_t wheel1, ...)
{
	if (!source)
		source = (CGEventSourceRef) [CGEventSource hidEventSource];

	CGEvent* event = [[CGEvent alloc] initWithSource: (CGEventSource*) source type: kCGEventScrollWheel];

	double pixelsPerLine = CGEventSourceGetPixelsPerLine(source);

	if (units == kCGScrollEventUnitPixel)
	{
		event.fields[@(kCGScrollWheelEventDeltaAxis1)] = [NSNumber numberWithInt: (int)(wheel1 / pixelsPerLine)];
		event.fields[@(kCGScrollWheelEventFixedPtDeltaAxis1)] = [NSNumber numberWithDouble: wheel1 / pixelsPerLine];
		event.fields[@(kCGScrollWheelEventPointDeltaAxis1)] = [NSNumber numberWithInt: wheel1];
	}
	else
	{
		event.fields[@(kCGScrollWheelEventDeltaAxis1)] = [NSNumber numberWithInt: wheel1];
		event.fields[@(kCGScrollWheelEventFixedPtDeltaAxis1)] = [NSNumber numberWithDouble: wheel1];
		event.fields[@(kCGScrollWheelEventPointDeltaAxis1)] = [NSNumber numberWithInt: (int)(wheel1 * pixelsPerLine)];
	}

	if (wheelCount > 1)
	{
		va_list vl;
		va_start(vl, wheel1);

		int32_t wheelN = va_arg(vl, int32_t);
		if (units == kCGScrollEventUnitPixel)
		{
			event.fields[@(kCGScrollWheelEventDeltaAxis2)] = [NSNumber numberWithInt: (int)(wheelN / pixelsPerLine)];
			event.fields[@(kCGScrollWheelEventFixedPtDeltaAxis2)] = [NSNumber numberWithDouble: wheelN / pixelsPerLine];
			event.fields[@(kCGScrollWheelEventPointDeltaAxis2)] = [NSNumber numberWithInt: wheelN];
		}
		else
		{
			event.fields[@(kCGScrollWheelEventDeltaAxis2)] = [NSNumber numberWithInt: wheelN];
			event.fields[@(kCGScrollWheelEventFixedPtDeltaAxis2)] = [NSNumber numberWithDouble: wheelN];
			event.fields[@(kCGScrollWheelEventPointDeltaAxis2)] = [NSNumber numberWithInt: (int)(wheelN * pixelsPerLine)];
		}

		if (wheelCount > 2)
		{
			wheelN = va_arg(vl, int32_t);
			if (units == kCGScrollEventUnitPixel)
			{
				event.fields[@(kCGScrollWheelEventDeltaAxis3)] = [NSNumber numberWithInt: (int)(wheelN / pixelsPerLine)];
				event.fields[@(kCGScrollWheelEventFixedPtDeltaAxis3)] = [NSNumber numberWithDouble: wheelN / pixelsPerLine];
				event.fields[@(kCGScrollWheelEventPointDeltaAxis3)] = [NSNumber numberWithInt: wheelN];
			}
			else
			{
				event.fields[@(kCGScrollWheelEventDeltaAxis3)] = [NSNumber numberWithInt: wheelN];
				event.fields[@(kCGScrollWheelEventFixedPtDeltaAxis3)] = [NSNumber numberWithDouble: wheelN];
				event.fields[@(kCGScrollWheelEventPointDeltaAxis3)] = [NSNumber numberWithInt: (int)(wheelN * pixelsPerLine)];
			}
		}

		va_end(vl);
	}
	return (CGEventRef) event;
}

CGPoint CGEventGetLocation(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	return e.location;
}

// Returns location relative to the LOWER left corner
CGPoint CGEventGetUnflippedLocation(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	CGPoint pt = CGEventGetLocation(event);

	CGSConnection* conn = nil;
	
	if (e.eventRecord)
		conn = _CGSConnectionFromEventRecord(e.eventRecord);

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
	CGEvent* e = (CGEvent*) event;
	e.location = location;
}

void CGEventKeyboardGetUnicodeString(CGEventRef event, UniCharCount maxStringLength, UniCharCount *actualStringLength, UniChar *unicodeString)
{
	CGEvent* e = (CGEvent*) event;
	UniChar* savedString = e.unicodeString;

	UniCharCount length = 0;
	while (length < 5 && savedString[length])
		length++;
	
	if (maxStringLength == 0)
	{
		*actualStringLength = length;
	}
	
	*actualStringLength = length;
	if (maxStringLength < length)
		*actualStringLength = maxStringLength;

	memcpy(unicodeString, savedString, *actualStringLength * sizeof(UniChar));
}

void CGEventKeyboardSetUnicodeString(CGEventRef event, UniCharCount stringLength, const UniChar *unicodeString)
{
	CGEvent* e = (CGEvent*) event;

	// This is the maximum CGEvent can save
	if (stringLength > 5)
		stringLength = 5;
	
	memcpy(e.unicodeString, unicodeString, stringLength * sizeof(UniChar));
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
	// TODO: should this call reset all other values in the CGEvent?
	[e setEventRecord: eventRecord length: eventRecordSize];
	return kCGErrorSuccess;
}

uint32_t CGEventGetEventRecordSize(CGEventRef event)
{
	CGEvent* e = (CGEvent*) event;
	return e.eventRecordLength;
}
