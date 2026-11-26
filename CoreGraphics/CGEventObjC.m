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
#include <unistd.h>
#include <string.h>
#include <CoreGraphics/CGEventSource.h>
#include <CoreGraphics/CGSConnection.h>
#include "CGEventTapInternal.h"
#import <Foundation/NSString.h>

// QUIRK: which fields an event has depends on what kind of event it is (its type): a field that
// does not belong to the kind of the event reads as 0 and ignores writes, and an event whose
// type changes to another kind starts with none of the fields of that kind. Fields that no kind
// owns (the target and source of the event, and some the header does not name) belong to every
// event. Documented only as "the fields of an event". Evidence: black-box observation on
// macOS 26.7.3 (tier 2): every field index below 180 written with CGEventSetIntegerValueField on
// an event of each kind, and read back.
// Test: tests/coregraphics-cgevent-fields.c (test_field_defaults_and_ranges, test_mouse_fields,
// test_key_fields, test_scroll_fields, test_tablet_fields, test_set_type_changes_kind)
typedef struct {
	uint16_t first, last;
} FieldRange;

static const FieldRange commonFields[] = {
	{39, 45}, {50, 55}, {58, 59}, {85, 85}, {87, 87}, {101, 107}, {141, 141}, {146, 146}, {166, 166}, {169, 169},
	// Our own: what the window system backends attach to the input events they post (see
	// kCGSKeyboardEventUnmodifiedUnicode in CoreGraphicsPrivate.h).
	{180, 201},
};
static const FieldRange mouseFields[] = { {0, 7}, {89, 92}, {108, 108}, {170, 171} };
static const FieldRange keyFields[] = { {8, 10}, {76, 81}, {127, 128} };
static const FieldRange scrollFields[] = { {11, 14}, {88, 88}, {93, 100}, {123, 123}, {137, 137}, {173, 178} };
static const FieldRange tabletPointerFields[] = { {15, 27} };
static const FieldRange tabletProximityFields[] = { {28, 38} };
static const FieldRange otherFields[] = { {83, 83}, {99, 100}, {121, 122}, {149, 163} };

#define RANGES(a) a, (sizeof(a) / sizeof(a[0]))

static uint64_t g_fieldMasks[6][CGEVENT_FIELD_COUNT / 64];
static uint64_t g_commonMask[CGEVENT_FIELD_COUNT / 64];
static dispatch_once_t g_fieldMasksOnce;

static void addRanges(uint64_t* mask, const FieldRange* ranges, size_t count)
{
	for (size_t i = 0; i < count; i++)
	{
		for (unsigned f = ranges[i].first; f <= ranges[i].last && f < CGEVENT_FIELD_COUNT; f++)
			mask[f / 64] |= 1ULL << (f % 64);
	}
}

static void buildFieldMasks(void)
{
	addRanges(g_commonMask, RANGES(commonFields));
	for (int c = 0; c < 6; c++)
		memcpy(g_fieldMasks[c], g_commonMask, sizeof(g_commonMask));
	addRanges(g_fieldMasks[CGEventClassOther], RANGES(otherFields));
	addRanges(g_fieldMasks[CGEventClassMouse], RANGES(mouseFields));
	addRanges(g_fieldMasks[CGEventClassKey], RANGES(keyFields));
	addRanges(g_fieldMasks[CGEventClassScroll], RANGES(scrollFields));
	addRanges(g_fieldMasks[CGEventClassTabletPointer], RANGES(tabletPointerFields));
	addRanges(g_fieldMasks[CGEventClassTabletProximity], RANGES(tabletProximityFields));
}

CGEventClass _CGEventClassOfType(CGEventType type)
{
	switch (type)
	{
		case kCGEventLeftMouseDown:
		case kCGEventLeftMouseUp:
		case kCGEventRightMouseDown:
		case kCGEventRightMouseUp:
		case kCGEventMouseMoved:
		case kCGEventLeftMouseDragged:
		case kCGEventRightMouseDragged:
		case kCGEventOtherMouseDown:
		case kCGEventOtherMouseUp:
		case kCGEventOtherMouseDragged:
			return CGEventClassMouse;
		case kCGEventKeyDown:
		case kCGEventKeyUp:
		case kCGEventFlagsChanged:
			return CGEventClassKey;
		case kCGEventScrollWheel:
			return CGEventClassScroll;
		case kCGEventTabletPointer:
			return CGEventClassTabletPointer;
		case kCGEventTabletProximity:
			return CGEventClassTabletProximity;
		default:
			return CGEventClassOther;
	}
}

static inline BOOL fieldBelongsTo(CGEventClass cls, CGEventField field)
{
	if (field >= CGEVENT_FIELD_COUNT)
		return NO;
	return (g_fieldMasks[cls][field / 64] >> (field % 64)) & 1;
}

static inline BOOL fieldIsCommon(CGEventField field)
{
	return field < CGEVENT_FIELD_COUNT && ((g_commonMask[field / 64] >> (field % 64)) & 1);
}

// QUIRK: the scroll wheel deltas come in three forms that describe the same movement: whole lines
// (11..13), 16.16 fixed point lines (93..95) and pixels (96..98). Setting a whole line delta also
// sets the other two forms (the fixed point value of the lines, and 8 pixels for each line); setting
// either of the others changes only that field. Evidence: black-box observation on macOS 26.7.3
// (tier 2). Test: tests/coregraphics-cgevent-fields.c (test_scroll_fields)
static inline BOOL isScrollLineDelta(CGEventField f) { return f >= kCGScrollWheelEventDeltaAxis1 && f <= kCGScrollWheelEventDeltaAxis3; }
static inline BOOL isScrollFixedDelta(CGEventField f) { return f >= kCGScrollWheelEventFixedPtDeltaAxis1 && f <= kCGScrollWheelEventFixedPtDeltaAxis3; }

// Pixels that the system assumes for a line when it derives pixels from a whole line delta that
// the application sets.
#define kScrollDerivedPixelsPerLine 8

#define CGInvalidPoint CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX)

@implementation CGEvent

-(instancetype) initWithSource:(CGEventSourceRef) source
{
	return [self initWithSource: source
						type: kCGEventNull];
}

-(instancetype) initWithSource:(CGEventSourceRef) source
						type:(CGEventType) type
{
	dispatch_once(&g_fieldMasksOnce, ^{ buildFieldMasks(); });

	_type = type;
	_location = CGInvalidPoint;
	_fields[kCGEventSourceUnixProcessID] = getpid();
	_fields[kCGEventSourceUserID] = getuid();
	_fields[kCGEventSourceGroupID] = getgid();
	[self takeOverSource: source];
	return self;
}

-(void) takeOverSource:(CGEventSourceRef) sourceRef
{
	CGEventSource* source = (CGEventSource*) sourceRef;

	_fields[kCGEventSourceStateID] = source ? source->_tableId : 0;
	_fields[kCGEventSourceUserData] = source ? source->_userData : 0;
}

-(void) setType:(CGEventType) type
{
	CGEventClass oldClass = _CGEventClassOfType(_type);
	CGEventClass newClass = _CGEventClassOfType(type);

	if (oldClass != newClass)
	{
		// The fields of the old kind are gone, those of the new kind start at 0.
		for (unsigned f = 0; f < CGEVENT_FIELD_COUNT; f++)
		{
			if (!fieldIsCommon(f))
				_fields[f] = 0;
		}
	}
	_type = type;
}

-(CGPoint) location
{
	if (!_locationValid)
	{
		// The pointer position of the window system, as of the first time it is asked for.
		CGSConnection* conn = _CGSConnectionForID(CGSDefaultConnection);
		_location = conn ? [conn mouseLocation] : CGPointZero;
		_locationValid = YES;
	}
	return _location;
}

-(void) setLocation:(CGPoint) location
{
	_location = location;
	_locationValid = YES;
}

-(int64_t) integerValueForField:(CGEventField) field
{
	if (!fieldBelongsTo(_CGEventClassOfType(_type), field))
		return 0;
	return _fields[field];
}

// QUIRK: some fields hold a number that the double accessors scale: the fixed point scroll deltas
// by 65536, the mouse pressure (a byte) by 255, the tablet pressure (16 bits) by 65535, the tablet
// tilts and tangential pressure (signed 16 bits) by 32767 and the rotation (16 bits) by 64. Setting
// a double truncates the scaled value; the pressure, rotation and tablet pressure keep only their
// bits. Evidence: black-box observation on macOS 26.7.3 (tier 2).
// Test: tests/coregraphics-cgevent-fields.c (test_mouse_fields, test_scroll_fields, test_tablet_fields)
-(double) doubleValueForField:(CGEventField) field
{
	if (!fieldBelongsTo(_CGEventClassOfType(_type), field))
		return 0;

	int64_t v = _fields[field];

	if (isScrollFixedDelta(field))
		return v / 65536.0;

	switch (field)
	{
		case kCGMouseEventPressure:
			return v / 255.0;
		case kCGTabletEventPointPressure:
			return v / 65535.0;
		case kCGTabletEventTiltX:
		case kCGTabletEventTiltY:
		case kCGTabletEventTangentialPressure:
			return v / 32767.0;
		case kCGTabletEventRotation:
			return v / 64.0;
		default:
			return (double) v;
	}
}

-(void) setIntegerValue:(int64_t) value forField:(CGEventField) field
{
	if (!fieldBelongsTo(_CGEventClassOfType(_type), field))
		return;

	switch (field)
	{
		case kCGMouseEventPressure:
			value &= 0xFF;
			break;
		case kCGMouseEventInstantMouser:
		case kCGScrollWheelEventInstantMouser:
		case kCGScrollWheelEventIsContinuous:
			value = (value != 0);
			break;
		case kCGKeyboardEventKeycode:
			value &= 0xFFFF;
			break;
		default:
			break;
	}

	_fields[field] = value;

	if (isScrollLineDelta(field))
	{
		// The same movement in the other forms.
		unsigned axis = field - kCGScrollWheelEventDeltaAxis1;

		_fields[kCGScrollWheelEventFixedPtDeltaAxis1 + axis] = value * 65536;
		_fields[kCGScrollWheelEventPointDeltaAxis1 + axis] = value * kScrollDerivedPixelsPerLine;
	}
}

-(void) setDoubleValue:(double) value forField:(CGEventField) field
{
	if (!fieldBelongsTo(_CGEventClassOfType(_type), field))
		return;

	int64_t stored;

	if (isScrollFixedDelta(field))
		stored = (int64_t) (value * 65536.0);
	else if (field == kCGMouseEventPressure)
		stored = ((int64_t) (value * 255.0)) & 0xFF;
	else if (field == kCGTabletEventPointPressure)
		stored = ((int64_t) (value * 65535.0)) & 0xFFFF;
	else if (field == kCGTabletEventTiltX || field == kCGTabletEventTiltY || field == kCGTabletEventTangentialPressure)
		stored = (int16_t) (int64_t) (value * 32767.0);
	else if (field == kCGTabletEventRotation)
		stored = ((int64_t) (value * 64.0)) & 0xFFFF;
	else
		stored = (int64_t) value;

	if (isScrollFixedDelta(field))
		_fields[field] = stored;
	else
		[self setIntegerValue: stored forField: field];
}

-(void) setUnicodeString:(const UniChar*) string length:(UniCharCount) stringLength
{
	if (stringLength > UINT16_MAX)
		stringLength = UINT16_MAX;

	UniChar* copy = NULL;

	if (stringLength > 0 && string != NULL)
	{
		copy = (UniChar*) malloc(stringLength * sizeof(UniChar));
		memcpy(copy, string, stringLength * sizeof(UniChar));
	}
	else
	{
		stringLength = 0;
	}

	free(_unicodeString);
	_unicodeString = copy;
	_unicodeLength = (uint16_t) stringLength;
	_unicodeDerived = NO;
}

-(void) _fillFromEventRecord
{
	_location = _eventRecord->location;
	_locationValid = YES;
	_type = _eventRecord->type; // These types match!
	_timestamp = _eventRecord->time;
	_flags = (uint32_t) _eventRecord->flags;

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
			_fields[kCGMouseEventButtonNumber] = _eventRecord->data.mouse.buttonNumber;
			_fields[kCGMouseEventNumber] = _eventRecord->data.mouse.eventNum;
			_fields[kCGMouseEventPressure] = _eventRecord->data.mouse.pressure & 0xFF;
			_fields[kCGMouseEventClickState] = _eventRecord->data.mouse.click;
			_fields[kCGMouseEventSubtype] = _eventRecord->data.mouse.subType;
			break;
		}
		case NX_MOUSEMOVED:
		{
			_fields[kCGMouseEventDeltaX] = _eventRecord->data.mouseMove.dx;
			_fields[kCGMouseEventDeltaY] = _eventRecord->data.mouseMove.dy;
			_fields[kCGMouseEventSubtype] = _eventRecord->data.mouseMove.subType;
			break;
		}
		case NX_SCROLLWHEELMOVED:
		{
			_fields[kCGScrollWheelEventDeltaAxis1] = _eventRecord->data.scrollWheel.deltaAxis1;
			_fields[kCGScrollWheelEventDeltaAxis2] = _eventRecord->data.scrollWheel.deltaAxis2;
			_fields[kCGScrollWheelEventDeltaAxis3] = _eventRecord->data.scrollWheel.deltaAxis3;

			_fields[kCGScrollWheelEventFixedPtDeltaAxis1] = _eventRecord->data.scrollWheel.fixedDeltaAxis1;
			_fields[kCGScrollWheelEventFixedPtDeltaAxis2] = _eventRecord->data.scrollWheel.fixedDeltaAxis2;
			_fields[kCGScrollWheelEventFixedPtDeltaAxis3] = _eventRecord->data.scrollWheel.fixedDeltaAxis3;

			_fields[kCGScrollWheelEventPointDeltaAxis1] = _eventRecord->data.scrollWheel.pointDeltaAxis1;
			_fields[kCGScrollWheelEventPointDeltaAxis2] = _eventRecord->data.scrollWheel.pointDeltaAxis2;
			_fields[kCGScrollWheelEventPointDeltaAxis3] = _eventRecord->data.scrollWheel.pointDeltaAxis3;
			break;
		}
		case NX_KEYDOWN:
		case NX_KEYUP:
		case NX_FLAGSCHANGED:
		{
			_fields[kCGKeyboardEventKeycode] = _eventRecord->data.key.keyCode;
			_fields[kCGKeyboardEventAutorepeat] = _eventRecord->data.key.repeat != 0;
			_fields[kCGKeyboardEventKeyboardType] = _eventRecord->data.key.keyboardType;
			break;
		}
	}
}

-(void) _createEventRecord
{
	// An event record is only kept for events that came from one; making one from the fields
	// is not supported.
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
	// The events of the window system come from the hardware.
	self = [self initWithSource: (CGEventSourceRef) [CGEventSource hidEventSource]];

	_eventRecord = malloc(length);
	memcpy(_eventRecord, eventRecord, length);
	_eventRecordLength = length;

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
	free(_unicodeString);
	[_clientData release];
	[super dealloc];
}

-(BOOL) hasSameContentAs:(CGEvent*) other
{
	if (other == self)
		return YES;
	if (other == nil || _type != other->_type || _timestamp != other->_timestamp || _flags != other->_flags)
		return NO;
	if (_locationValid != other->_locationValid
		|| (_locationValid && (_location.x != other->_location.x || _location.y != other->_location.y)))
		return NO;
	if (memcmp(_fields, other->_fields, sizeof(_fields)) != 0)
		return NO;
	if (_unicodeLength != other->_unicodeLength || (_unicodeString == NULL) != (other->_unicodeString == NULL))
		return NO;
	return _unicodeLength == 0 || memcmp(_unicodeString, other->_unicodeString, _unicodeLength * sizeof(UniChar)) == 0;
}

-(id) copy
{
	CGEvent* rv = [[CGEvent alloc] initWithSource: NULL type: _type];

	rv->_timestamp = _timestamp;
	rv->_flags = _flags;
	rv->_location = _location;
	rv->_locationValid = _locationValid;
	memcpy(rv->_fields, _fields, sizeof(_fields));
	[rv setUnicodeString: _unicodeString length: _unicodeLength];
	rv->_unicodeDerived = _unicodeDerived;

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

@end

////////////////////////////////////////////////////////////////

@implementation CGEventSource
@synthesize stateID = _stateId;
@synthesize userData = _userData;
@synthesize pixelsPerLine = _pixelsPerLine;

-(instancetype) initWithState: (CGEventSourceStateID) stateId
{
	_pixelsPerLine = 10;
	_stateId = stateId;
	_suppressionInterval = 0.25;

	switch (stateId)
	{
		case kCGEventSourceStatePrivate:
			_tableId = _CGEventStateNewPrivateTable();
			_ownsTable = YES;
			break;
		case kCGEventSourceStateHIDSystemState:
			_tableId = kCGEventStateTableHID;
			break;
		default:
			_tableId = kCGEventStateTableCombined;
			break;
	}
	return self;
}

-(instancetype) initWithTableId: (int32_t) tableId
{
	// The identity of a private state is not owned by this source: the table lives as long as
	// the source it was made for.
	self = [self initWithState: tableId == kCGEventStateTableHID ? kCGEventSourceStateHIDSystemState : kCGEventSourceStateCombinedSessionState];
	if (tableId != kCGEventStateTableHID && tableId != kCGEventStateTableCombined)
	{
		_stateId = kCGEventSourceStatePrivate;
		_tableId = tableId;
		_ownsTable = NO;
	}
	return self;
}

-(void) dealloc
{
	if (_stateId == kCGEventSourceStatePrivate && _ownsTable)
		_CGEventStateReleasePrivateTable(_tableId);
	[super dealloc];
}

-(CGEventSourceKeyboardType) keyboardType
{
	// QUIRK: a source reports the keyboard type of the system whatever it was set to, and
	// asking makes that type the one the source's keyboard events get from then on. Documented
	// only as the keyboard type of the source. Evidence: black-box observation on macOS 26.7.3
	// (tier 2): after setting 7 and asking, the answer is 40 and a keyboard event made next
	// carries 40; the events made between the set and the ask carry 7.
	// Test: tests/coregraphics-cgevent-create.c (test_source_fields, "QUIRK test")
	_keyboardType = kCGEventDefaultKeyboardTypeOfSource;
	_keyboardTypeSet = YES;
	return _keyboardType;
}

-(void) setKeyboardType: (CGEventSourceKeyboardType) type
{
	_keyboardType = type;
	_keyboardTypeSet = YES;
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
