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

#import <Onyx2D/O2Geometry.h>
#import <Onyx2D/O2PDFObject.h>

@class O2PDFString, O2PDFArray, O2PDFDictionary, O2PDFStream;

@interface O2PDFArray : O2PDFObject {
    NSUInteger _capacity;
    NSUInteger _count;
    O2PDFObject **_objects;
}

+ (O2PDFArray *) pdfArray;
+ (O2PDFArray *) pdfArrayWithRect: (O2Rect) rect;
+ (O2PDFArray *) pdfArrayWithNumbers: (O2PDFReal *) values
                               count: (NSUInteger) count;
+ (O2PDFArray *) pdfArrayWithIntegers: (O2PDFInteger *) values
                                count: (NSUInteger) count;

- (NSUInteger) count;

- (void) addObject: (O2PDFObject *) anObject;
- (void) addNumber: (O2PDFReal) value;
- (void) addInteger: (O2PDFInteger) value;
- (void) addBoolean: (O2PDFBoolean) value;

- (O2PDFObject *) objectAtIndex: (NSUInteger) index;

- (BOOL) getObjectAtIndex: (NSUInteger) index value: (O2PDFObject **) objectp;
- (BOOL) getNullAtIndex: (NSUInteger) index;
- (BOOL) getBooleanAtIndex: (NSUInteger) index value: (O2PDFBoolean *) valuep;
- (BOOL) getIntegerAtIndex: (NSUInteger) index value: (O2PDFInteger *) valuep;
- (BOOL) getNumberAtIndex: (NSUInteger) index value: (O2PDFReal *) valuep;
- (BOOL) getNameAtIndex: (NSUInteger) index value: (const char **) namep;
- (BOOL) getStringAtIndex: (NSUInteger) index value: (O2PDFString **) stringp;
- (BOOL) getArrayAtIndex: (NSUInteger) index value: (O2PDFArray **) arrayp;
- (BOOL) getDictionaryAtIndex: (NSUInteger) index
                        value: (O2PDFDictionary **) dictionaryp;
- (BOOL) getStreamAtIndex: (NSUInteger) index value: (O2PDFStream **) streamp;

- (BOOL) getNumbers: (O2PDFReal **) numbersp count: (NSUInteger *) count;
- (BOOL) getIntegers: (O2PDFInteger **) intsp count: (NSUInteger *) count;

@end
