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

#ifndef CGEVENT_OBJC_H
#define CGEVENT_OBJC_H
#include <CoreGraphics/CGEvent.h>
#include <CoreFoundation/CFBase.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSData.h>

// A CGEvent keeps its fields in a fixed array indexed by CGEventField: no allocation, no
// boxing and no hashing per field. Indexes at or above this limit do not exist.
#define CGEVENT_FIELD_COUNT 192

// What kind of event a type is, which decides what fields it has.
typedef enum {
	CGEventClassOther = 0,
	CGEventClassMouse,
	CGEventClassKey,
	CGEventClassScroll,
	CGEventClassTabletPointer,
	CGEventClassTabletProximity,
} CGEventClass;

extern CGEventClass _CGEventClassOfType(CGEventType type);

@interface CGEvent : NSObject <NSCopying> {
@public
	CGEventType _type;
	CGEventTimestamp _timestamp;
	// Only the low 32 bits are kept, as on macOS.
	uint32_t _flags;

	// CGEventGetLocation() of an event whose location was never set is the pointer position
	// at the time of the first query.
	CGPoint _location;
	BOOL _locationValid;

	int64_t _fields[CGEVENT_FIELD_COUNT];

	// The Unicode string of a keyboard event (up to 65535 UTF-16 units), NULL when none was set.
	UniChar* _unicodeString;
	uint16_t _unicodeLength;

	CGSEventRecordPtr _eventRecord;
	uint32_t _eventRecordLength;
}
-(instancetype) initWithSource:(CGEventSourceRef) source;
-(instancetype) initWithSource:(CGEventSourceRef) source
						type:(CGEventType) type;
-(instancetype) initWithEventRecord:(const CGSEventRecordPtr) eventRecord
							length:(uint32_t) length;

-(void) dealloc;
-(id) copy;
-(CFTypeID) _cfTypeID;

-(void) setEventRecord:(CGSEventRecordPtr) record
				length:(uint32_t) length;
@property(readonly) uint32_t eventRecordLength;
@property(readonly) CGSEventRecordPtr eventRecord;

// The state ID and the user data of the source are taken over, as they are when the event is
// made with the source.
-(void) takeOverSource:(CGEventSourceRef) source;
-(void) setType:(CGEventType) type;
-(CGPoint) location;
-(void) setLocation:(CGPoint) location;

-(int64_t) integerValueForField:(CGEventField) field;
-(void) setIntegerValue:(int64_t) value forField:(CGEventField) field;
-(double) doubleValueForField:(CGEventField) field;
-(void) setDoubleValue:(double) value forField:(CGEventField) field;

// Replaces the Unicode string; stringLength is limited to 65535.
-(void) setUnicodeString:(const UniChar*) string length:(UniCharCount) stringLength;

@end

//////////////////////////////////////////////////////////////////////

@interface CGEventSource : NSObject {
@public
	// kCGEventSourceStatePrivate, ...CombinedSessionState or ...HIDSystemState
	CGEventSourceStateID _stateId;
	// The identity of the state table of the source: that of a private source is unique to it
	// (the value CGEventSourceGetSourceStateID() reports), the others are 0 (combined) and 1 (HID).
	int32_t _tableId;
	CGEventSourceKeyboardType _keyboardType;
	BOOL _keyboardTypeSet;
	int64_t _userData;
	double _pixelsPerLine;
	CFTimeInterval _suppressionInterval;
	CGEventFilterMask _filters[kCGNumberOfEventSuppressionStates];
	BOOL _ownsTable;
}
-(instancetype) initWithState: (CGEventSourceStateID) stateId;
// A source as an event describes the one it was made with.
-(instancetype) initWithTableId: (int32_t) tableId;
-(void) dealloc;
-(CFTypeID) _cfTypeID;
+(CGEventSource*) hidEventSource;

@property CGEventSourceKeyboardType keyboardType;
@property CGEventSourceStateID stateID;
@property int64_t userData;
@property double pixelsPerLine;

@end

#endif
