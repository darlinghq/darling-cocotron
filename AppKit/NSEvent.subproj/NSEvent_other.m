/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSEvent_other.h"
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>

@implementation NSEvent_other
- initWithType: (NSEventType) type
             location: (NSPoint) location
        modifierFlags: (NSUInteger) modifierFlags
            timestamp: (NSTimeInterval) time
         windowNumber: (NSInteger) windowNum
              context: (NSGraphicsContext *) context
              subtype: (short) subtype
                data1: (NSInteger) data1
                data2: (NSInteger) data2
{
    _type = type;
    _locationInWindow = location;
    _modifierFlags = modifierFlags;
    _timestamp = time;
    _windowNumber = windowNum;
    _subtype = subtype;
    _data1 = data1;
    _data2 = data2;
    return self;
}

// A system-defined event as the CGEvent the window system would have made it from: the event
// record carries the subtype and the two data words (as 32-bit values, which is what the record
// has room for).
- (CGEventRef) CGEvent {
    if (_type != NSSystemDefined)
        return NULL;

    CGSEventRecord record;
    memset(&record, 0, sizeof(record));
    record.length = sizeof(record);
    record.type = NX_SYSDEFINED;

    // CGEvent locations are global, in CoreGraphics' space: origin at the top-left corner of the
    // main display, y down.
    NSPoint point = _locationInWindow;
    NSArray *screens = [NSScreen screens];
    if ([screens count] > 0)
        point.y = NSHeight([[screens objectAtIndex: 0] frame]) - point.y;
    record.location = NSPointToCGPoint(point);
    record.windowLocation = record.location;
    record.time = (CGSEventRecordTime) (_timestamp * 1e9);
    // NSEventModifierFlags and CGEventFlags use the same bits.
    record.flags = _modifierFlags;
    record.window = (CGSWindowID) _windowNumber;
    record.data.compound.subType = _subtype;
    record.data.compound.misc.L[0] = (SInt32) _data1;
    record.data.compound.misc.L[1] = (SInt32) _data2;

    CGEventRef event = CGEventCreateWithEventRecord(&record, sizeof(record));
    return event ? (CGEventRef) CFAutorelease(event) : NULL;
}

- (short) subtype {
    return _subtype;
}

- (NSInteger) data1 {
    return _data1;
}

- (NSInteger) data2 {
    return _data2;
}

@end
