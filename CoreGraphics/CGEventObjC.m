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
#include <time.h>
#include <CoreGraphics/CGEventSource.h>
#include <CoreGraphics/CGSConnection.h>
#include "CGEventTapInternal.h"
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSString.h>

#define CGInvalidPoint CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX)

@implementation CGEvent

@synthesize source = _source;
@synthesize type = _type;
@synthesize timestamp = _timestamp;
@synthesize flags = _flags;
@synthesize fields = _fields;
@synthesize virtualKey = _virtualKey;
@synthesize mouseButton = _mouseButton;

-(instancetype) initWithSource:(CGEventSource*) source
{
	return [self initWithSource: source
							type: kCGEventNull];
}

-(instancetype) initWithSource:(CGEventSource*) source
						type:(CGEventType) type;
{
	_source = [source retain];
	_type = type;
	_fields = [[NSMutableDictionary alloc] initWithCapacity: 0];
	_timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);

	_location = CGInvalidPoint;
	return self;
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
	NSKeyedUnarchiver* unarchiver = (NSKeyedUnarchiver*) coder;
	
	// TODO

	return self;
}

-(void) _fillFromEventRecord
{
	_location = _eventRecord->location;
	_type = _eventRecord->type; // These types match!
	_timestamp = _eventRecord->time;
	_flags = (CGEventFlags) _eventRecord->flags;

	switch (_eventRecord->type)
	{
		case NX_LMOUSEDOWN:
		case NX_LMOUSEUP:
		case NX_RMOUSEDOWN:
		case NX_RMOUSEUP:
		case NX_OMOUSEDOWN:
		case NX_OMOUSEUP:
		case NX_LMOUSEDRAGGED:
		case NX_RMOUSEDRAGGED:
		case NX_OMOUSEDRAGGED:
		{
			_fields[@(kCGMouseEventButtonNumber)] = [NSNumber numberWithInt: _eventRecord->data.mouse.buttonNumber];
			_fields[@(kCGMouseEventNumber)] = [NSNumber numberWithInt: _eventRecord->data.mouse.eventNum];
			_fields[@(kCGMouseEventPressure)] = [NSNumber numberWithDouble: _eventRecord->data.mouse.pressure / 255.0];
			_fields[@(kCGMouseEventClickState)] = [NSNumber numberWithInt: _eventRecord->data.mouse.click];
			_fields[@(kCGMouseEventSubtype)] = [NSNumber numberWithInt: _eventRecord->data.mouse.subType];
			break;
		}
		case NX_MOUSEMOVED:
		{
			_fields[@(kCGMouseEventDeltaX)] = [NSNumber numberWithInt: _eventRecord->data.mouseMove.dx];
			_fields[@(kCGMouseEventDeltaY)] = [NSNumber numberWithInt: _eventRecord->data.mouseMove.dy];
			_fields[@(kCGMouseEventSubtype)] = [NSNumber numberWithInt: _eventRecord->data.mouseMove.subType];
			break;
		}
		case NX_SCROLLWHEELMOVED:
		{
			_fields[@(kCGScrollWheelEventDeltaAxis1)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.deltaAxis1];
			_fields[@(kCGScrollWheelEventDeltaAxis2)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.deltaAxis2];
			_fields[@(kCGScrollWheelEventDeltaAxis3)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.deltaAxis3];

			_fields[@(kCGScrollWheelEventFixedPtDeltaAxis1)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.fixedDeltaAxis1];
			_fields[@(kCGScrollWheelEventFixedPtDeltaAxis2)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.fixedDeltaAxis2];
			_fields[@(kCGScrollWheelEventFixedPtDeltaAxis3)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.fixedDeltaAxis3];

			_fields[@(kCGScrollWheelEventPointDeltaAxis1)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.pointDeltaAxis1];
			_fields[@(kCGScrollWheelEventPointDeltaAxis2)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.pointDeltaAxis2];
			_fields[@(kCGScrollWheelEventPointDeltaAxis3)] = [NSNumber numberWithInt: _eventRecord->data.scrollWheel.pointDeltaAxis3];
			break;
		}
		case NX_KEYDOWN:
		case NX_KEYUP:
		{
			break;
		}
	}
}

-(void) _createEventRecord
{
	// TODO
}

-(uint32_t) eventRecordLength
{
	if (!_eventRecordLength)
		[self _createEventRecord];
	return _eventRecordLength;
}

-(CGSEventRecordPtr) eventRecord
{
	if (!_eventRecord)
		[self _createEventRecord];
	return _eventRecord;
}

-(instancetype) initWithEventRecord:(const CGSEventRecordPtr) eventRecord
							length:(uint32_t) length
{
	_eventRecord = malloc(length);
	memcpy(_eventRecord, eventRecord, length);
	_eventRecordLength = length;

	_fields = [[NSMutableDictionary alloc] initWithCapacity: 0];
	_source = [[CGEventSource hidEventSource] retain];

	[self _fillFromEventRecord];

	return self;
}

-(void) setEventRecord:(CGSEventRecordPtr) record
				length:(uint32_t) length
{
	CGSEventRecordPtr myCopy = (CGSEventRecordPtr) malloc(length);
	memcpy(myCopy, record, length);

	free(_eventRecord);
	_eventRecord = myCopy;
	_eventRecordLength = length;
}

-(void) dealloc
{
	free(_eventRecord);
	[_source release];
	[_fields release];
	[super dealloc];
}

-(id)copy
{
	CGEvent* rv = [[CGEvent alloc] initWithSource: _source type: _type];
	rv->_timestamp = self->_timestamp;
	rv->_flags = self->_flags;
	rv->_fields = [_fields copy];

	rv->_virtualKey = _virtualKey;
	memcpy(rv->_unicodeString, _unicodeString, sizeof(_unicodeString));

	rv->_location = _location;
	rv->_mouseButton = _mouseButton;

	if (_eventRecord)
	{
		rv->_eventRecordLength = _eventRecordLength;
		rv->_eventRecord = (CGSEventRecordPtr) malloc(_eventRecordLength);
		memcpy(rv->_eventRecord, _eventRecord, _eventRecordLength);
	}

	return rv;
}

- (id)copyWithZone:(NSZone *)zone
{
	return [self copy];
}

-(CFTypeID) _cfTypeID
{
	return CGEventGetTypeID();
}

-(UniChar*) unicodeString
{
	return _unicodeString;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
	NSKeyedArchiver* archiver = (NSKeyedArchiver*) coder;

	CGEventSourceStateID stateId = _source.stateID;
	[archiver encodeInt: stateId forKey:@"stateId"];

	[archiver encodeInt: _type forKey: @"type"];
	[archiver encodeInt64: _timestamp forKey: @"timestamp"];
	[archiver encodeObject: _fields forKey: @"fields"];
	[archiver encodeInt: _virtualKey forKey: @"virtualKey"];
	[archiver encodeBytes: (uint8_t*) _unicodeString length: sizeof(_unicodeString) forKey: @"unicodeString"];
	[archiver encodeDouble: _location.x forKey: @"location.x"];
	[archiver encodeDouble: _location.y forKey: @"location.y"];
	[archiver encodeInt: _mouseButton forKey: @"mouseButton"];

	if (_eventRecord)
		[archiver encodeBytes: (uint8_t*)_eventRecord length: _eventRecordLength forKey: @"eventRecord"];
}

-(CGPoint) location
{
	const CGPoint invalid = CGInvalidPoint;
	if (_location.x == invalid.x && _location.y == invalid.y)
	{
		_location = [_CGSConnectionForID(CGSDefaultConnection) mouseLocation];
	}
	return _location;
}

-(void) setLocation:(CGPoint) location
{
	_location = location;
}

@end

////////////////////////////////////////////////////////////////

@implementation CGEventSource
@synthesize keyboardType = _keyboardType;
@synthesize stateID = _stateId;
@synthesize userData = _userData;
@synthesize pixelsPerLine = _pixelsPerLine;

-(instancetype) initWithState: (CGEventSourceStateID) stateId
{
	_pixelsPerLine = 10;
	_stateId = stateId;
	return self;
}

-(CFTypeID) _cfTypeID
{
	return CGEventSourceGetTypeID();
}

+(CGEventSource*) hidEventSource
{
	static CGEventSource* instance;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		instance = [[CGEventSource alloc] initWithState: kCGEventSourceStateHIDSystemState];
	});
	return instance;
}
@end

////////////////////////////////////////////////////////////////

static void cgEventTapCallout(CFMachPortRef mp, void* msg, CFIndex size, void* info)
{
	CGEventTap* tap = (CGEventTap*) info;

	struct TapMachMessage* tapMessage = (struct TapMachMessage*) msg;
	CGEventRef event = tapMessage->event;

	CGEventType type = CGEventGetType(tapMessage->event);
	if (tap.enabled && (CGEventMaskBit(type) & tap.mask) != 0)
	{
		// Invoke callback
		CGEventRef returned = tap.callback(tapMessage->proxy, type, event, tap.userInfo);

		if (!(tap.options & kCGEventTapOptionListenOnly))
			event = returned;
	}

	// Pass the message on
	if (event != NULL)
	{
		CGEventTapPostEvent(tapMessage->proxy, event);

		if (event != tapMessage->event)
			CFRelease(event);
	}

	CFRelease(tapMessage->event);
}

@implementation CGEventTap

@synthesize machPort = _machPort;
@synthesize options = _options;
@synthesize mask = _mask;
@synthesize callback = _callback;
@synthesize userInfo = _userInfo;
@synthesize enabled = _enabled;

-(instancetype) initWithLocation: (CGEventTapLocation) location
						options: (CGEventTapOptions) options
							mask: (CGEventMask) mask
						callback: (CGEventTapCallBack) callback
						userInfo: (void*) userInfo
{
	_location = location;
	_options = options;
	_mask = mask;
	_callback = callback;
	_userInfo = userInfo;
	_enabled = TRUE;

	kern_return_t ret = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &_machPort);
    if (KERN_SUCCESS == ret) {
        ret = mach_port_insert_right(mach_task_self(), _machPort, _machPort, MACH_MSG_TYPE_MAKE_SEND);
    }
    if (KERN_SUCCESS != ret) {
        if (MACH_PORT_NULL != _machPort) mach_port_destroy(mach_task_self(), _machPort);
		[self release];
        return nil;
    }

	return self;
}

-(void) dealloc
{
	_CGEventTapDestroyed(_location, _machPort);
	mach_port_destroy(mach_task_self(), _machPort);
	[super dealloc];
}

-(CFMachPortRef) createCFMachPort
{
	CFMachPortRef mp;
	CFMachPortContext ctxt = {
		.copyDescription = NULL,
		.info = self,
		.release = CFRelease,
		.retain = CFRetain,
		.version = 0,
	};

	mp = CFMachPortCreateWithPort(NULL, _machPort, cgEventTapCallout, &ctxt, NULL);

	return mp;
}

@end
