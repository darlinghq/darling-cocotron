/* Copyright (c) 2007 Christopher J. W. Lloyd

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

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Onyx2D/O2Exceptions.h>
#import <Onyx2D/O2PDFContext.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFObject_const.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2PDFxref.h>
#import <Onyx2D/O2PDFxrefEntry.h>

@implementation O2PDFxref

- initWithData: (NSData *) data {
    _data = [data retain];
    _previous = nil;
    _numberToEntries = NSCreateMapTable(
            NSIntegerMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 0);
    _entryToObject = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks,
                                      NSObjectMapValueCallBacks, 0);
    _entriesInOrder = [NSMutableArray new];
    _trailer = nil;
    _objectStreams = NSCreateMapTable(NSIntegerMapKeyCallBacks,
                                      NSObjectMapValueCallBacks, 0);
    return self;
}

- (void) dealloc {
    [_data release];
    [_previous release];
    NSFreeMapTable(_numberToEntries);
    NSFreeMapTable(_entryToObject);
    [_entriesInOrder release];
    [_trailer release];
    NSFreeMapTable(_objectStreams);
    [super dealloc];
}

- (BOOL) isByReference {
    return NO;
}

- (NSData *) data {
    return _data;
}

- (O2PDFxref *) previous {
    return _previous;
}

- (NSArray *) allEntries {
    NSMutableArray *result = [NSMutableArray array];
    NSMapEnumerator state = NSEnumerateMapTable(_numberToEntries);
    int key;
    id value;

    while (NSNextMapEnumeratorPair(&state, (void **) &key, (void **) &value)) {
        if ([value isKindOfClass: [NSArray class]])
            [result addObjectsFromArray: value];
        else
            [result addObject: value];
    }

    return result;
}

- (O2PDFxrefEntry *) entryWithNumber: (O2PDFInteger) number
                          generation: (O2PDFInteger) generation
{
    void *key = (void *) number;
    id check = NSMapGet(_numberToEntries, key);

    if (check == nil)
        return [_previous entryWithNumber: number generation: generation];

    if ([check isKindOfClass: [NSArray class]]) {
        NSArray *array = check;
        int i, count = [check count];

        for (i = 0; i < count; i++) {
            O2PDFxrefEntry *entry = [array objectAtIndex: i];

            if ([entry generation] == generation)
                return entry;
        }
    }

    return check;
}

- (O2PDFObject *) objectAtNumber: (O2PDFInteger) number
                      generation: (O2PDFInteger) generation
{
    O2PDFxrefEntry *lookup = [self entryWithNumber: number
                                        generation: generation];

    if (lookup == nil)
        return [O2PDFObject_const pdfObjectWithNull];
    else {
        O2PDFObject *result = NSMapGet(_entryToObject, lookup);

        if (result == nil) {
            if ([lookup objectStream] >= 0)
                result = [self objectNumber: number
                             inObjectStream: [lookup objectStream]];
            else if (!O2PDFParseIndirectObject(_data, [lookup position], &result,
                                               number, generation, self))
                result = nil;
            if (result == nil)
                result = [O2PDFObject_const pdfObjectWithNull];

            NSMapInsert(_entryToObject, lookup, result);
        }

        return result;
    }
}

// Object `number` stored in the object stream `streamNumber` (PDF 7.5.7): the
// stream's data begins with N pairs "number offset", offsets counted from
// First. Returns nil if it is not there.
- (O2PDFObject *) objectNumber: (O2PDFInteger) number
                inObjectStream: (O2PDFInteger) streamNumber
{
    O2PDFStream *stream;
    O2PDFInteger count, first, i, position = 0;

    if (![[self objectAtNumber: streamNumber generation: 0]
                checkForType: kO2PDFObjectTypeStream
                       value: &stream])
        return nil;
    if (![[stream dictionary] getIntegerForKey: "N" value: &count] ||
        ![[stream dictionary] getIntegerForKey: "First" value: &first])
        return nil;

    NSData *decoded = NSMapGet(_objectStreams, (void *) streamNumber);

    if (decoded == nil) {
        if ((decoded = [stream data]) == nil)
            return nil;
        NSMapInsert(_objectStreams, (void *) streamNumber, decoded);
    }

    const char *bytes = [decoded bytes];
    unsigned length = [decoded length];

    for (i = 0; i < count; i++) {
        O2PDFInteger objectNumber, offset;
        O2PDFObject *object;
        O2PDFInteger end;

        if (!O2PDFScanInteger(bytes, length, position, &position, &objectNumber) ||
            !O2PDFScanInteger(bytes, length, position, &position, &offset))
            return nil;
        if (objectNumber != number)
            continue;
        if (first + offset >= length ||
            !O2PDFParseObject(bytes, length, first + offset, &end, &object, self))
            return nil;
        return object;
    }
    return nil;
}

- (O2PDFDictionary *) trailer {
    return _trailer;
}

- (void) setPreviousTable: (O2PDFxref *) table {
    [_previous autorelease];
    _previous = [table retain];
}

- (void) addEntry: (O2PDFxrefEntry *) entry {
    void *key = (void *) [entry number];
    id check = NSMapGet(_numberToEntries, key);

    [_entriesInOrder addObject: entry];

    if (check == nil)
        NSMapInsert(_numberToEntries, key, entry);
    if ([check isKindOfClass: [NSMutableArray class]])
        [check addObject: entry];
    else if ([check isKindOfClass: [O2PDFxrefEntry class]])
        NSMapInsert(_numberToEntries, key,
                    [NSMutableArray arrayWithObject: entry]);
}

- (void) addEntry: (O2PDFxrefEntry *) entry object: (O2PDFObject *) object {
    [self addEntry: entry];
    NSMapInsert(_entryToObject, entry, object);
}

- (void) setTrailer: (O2PDFDictionary *) trailer {
    [_trailer autorelease];
    _trailer = [trailer retain];
}

- (void) encodeWithPDFContext: (O2PDFContext *) encoder {
    unsigned startxref = [encoder length];
    int i, count = [_entriesInOrder count];

    [encoder appendCString: "xref\n"];
    [encoder appendFormat: @"%d %d\n", 1, count];
    for (i = 0; i < count; i++) {
        O2PDFxrefEntry *entry = [_entriesInOrder objectAtIndex: i];

        [encoder appendFormat: @"%010d %05d n \n", [entry position],
                               [entry generation]];
    }
    [_trailer setIntegerForKey: "Size"
                         value: [[_entriesInOrder lastObject] number] + 1];
    [encoder appendCString: "trailer\n"];
    [encoder encodePDFObject: _trailer];
    [encoder appendCString: "startxref\n"];
    [encoder appendFormat: @"%d\n", startxref];
    [encoder appendCString: "%%EOF\n"];
}

@end
