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

#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFContext.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFFilter.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2PDFxref.h>
#include <string.h>

@implementation O2PDFStream

- initWithDictionary: (O2PDFDictionary *) dictionary
                xref: (O2PDFxref *) xref
            position: (O2PDFInteger) position
{
    O2PDFInteger length;

    _dictionary = [dictionary retain];

    if (![_dictionary getIntegerForKey: "Length" value: &length])
        _data = nil;

    // FIX, can do a more efficient subdata here
    _data = [[[xref data] subdataWithRange: NSMakeRange(position, length)]
            retain];
    _xref = [xref retain];
    return self;
}

- initWithDictionary: (O2PDFDictionary *) dictionary data: (NSData *) data {
    _dictionary = [dictionary retain];
    _data = [data retain];
    _xref = nil;
    return self;
}

- (void) dealloc {
    [_dictionary release];
    [_data release];
    [_resultData release];
    [_xref release];
    [super dealloc];
}

+ (O2PDFStream *) pdfStream {
    return [self pdfStreamWithData: [NSMutableData data]];
}

+ (O2PDFStream *) pdfStreamWithData: (NSData *) data {
    O2PDFDictionary *dictionary = [O2PDFDictionary pdfDictionary];

    [dictionary setIntegerForKey: "Length" value: [data length]];

    return [[[self alloc] initWithDictionary: dictionary
                                        data: data] autorelease];
}

+ (O2PDFStream *) pdfStreamWithBytes: (const void *) bytes
                              length: (unsigned) length
{
    return [self pdfStreamWithData: [NSData dataWithBytes: bytes
                                                   length: length]];
}

- (O2PDFObjectType) objectType {
    return kO2PDFObjectTypeStream;
}

- (BOOL) checkForType: (O2PDFObjectType) type value: (void *) value {
    if (type != kO2PDFObjectTypeStream)
        return NO;

    *((O2PDFStream **) value) = self;
    return YES;
}

- (O2PDFDictionary *) dictionary {
    return _dictionary;
}

- (O2PDFxref *) xref {
    return _xref;
}

- (size_t) bytesPerRow {
    // Initializes _bytesPerRow as a side effect.
    [self data];

    return _bytesPerRow;
}

static O2PDFStreamImageFilter O2PDFStreamImageFilterNamed(const char *name) {
    if (strcmp(name, "DCTDecode") == 0 || strcmp(name, "DCT") == 0)
        return kO2PDFStreamDCTImageFilter;
    if (strcmp(name, "JPXDecode") == 0)
        return kO2PDFStreamJPXImageFilter;
    return kO2PDFStreamNoImageFilter;
}

- (NSData *) resultData {
    return [self dataLeavingImageFilter: NULL];
}

// A NULL imageFilter decodes every filter, as -data always has.
- (NSData *) dataLeavingImageFilter: (O2PDFStreamImageFilter *) imageFilter {
    O2PDFInteger length;
    NSData *result;
    const char *name;
    O2PDFDictionary *parameters;
    O2PDFArray *filters;
    // -bytesPerRow describes the data -data returns, so only that path may set it.
    size_t scratchBytesPerRow = 0;
    size_t *bytesPerRow = imageFilter ? &scratchBytesPerRow : &_bytesPerRow;

    if (![_dictionary getIntegerForKey: "Length" value: &length]) {
        O2PDFError(__FILE__, __LINE__, @"stream does not contain Length");
        return nil;
    }

    result = _data;
    if (imageFilter)
        *imageFilter = kO2PDFStreamNoImageFilter;

    if ([_dictionary getNameForKey: "Filter" value: &name]) {

        if (![_dictionary getDictionaryForKey: "DecodeParms"
                                        value: &parameters])
            parameters = nil;

        if (imageFilter &&
            (*imageFilter = O2PDFStreamImageFilterNamed(name)) != kO2PDFStreamNoImageFilter)
            return result;
        result = [O2PDFFilter decodeWithName: name
                                        data: result
                                  parameters: parameters
                                 bytesPerRow: bytesPerRow];
    } else if ([_dictionary getArrayForKey: "Filter" value: &filters]) {
        O2PDFArray *parameterArray;
        int i, count = [filters count];

        if (![_dictionary getArrayForKey: "DecodeParms" value: &parameterArray])
            parameterArray = nil;

        for (i = 0; i < count; i++) {
            if (![filters getNameAtIndex: i value: &name]) {
                O2PDFError(__FILE__, __LINE__, @"expecting filter name at %d",
                           i);
                return nil;
            }
            if (![parameterArray getDictionaryAtIndex: i value: &parameters])
                parameters = nil;
            // QUIRK: with an image filter left applied, a DCT or JPX filter that is not the last one is
            // not decoded either: the data passes through it unchanged and the chain goes on (a later
            // filter that cannot be applied still gives no data). Only the last filter is reported.
            // Not documented. Evidence: black-box observation of CGPDFStreamCopyData on macOS 26.7.3 and
            // 10.14.4 (tier 2): [/DCTDecode /DCTDecode] gives the 21 input bytes, [/DCTDecode
            // /NoSuchFilter] gives NULL without decoding the image data.
            // Test: coregraphics-pdf-page-dictionary-and-stream-data ("quirk: image filter before the end")
            if (imageFilter && O2PDFStreamImageFilterNamed(name) != kO2PDFStreamNoImageFilter) {
                if (i == count - 1)
                    *imageFilter = O2PDFStreamImageFilterNamed(name);
                continue;
            }
            result = [O2PDFFilter decodeWithName: name
                                            data: result
                                      parameters: parameters
                                     bytesPerRow: bytesPerRow];
        }
    }

    return result;
}

- (NSData *) data {
    if (_resultData == nil)
        _resultData = [[self resultData] retain];

    return _resultData;
}

- (NSMutableData *) mutableData {
    return (NSMutableData *) _data;
}

- (NSString *) description {
    return [NSString stringWithFormat: @"stream %@", _dictionary];
}

- (BOOL) isByReference {
    return YES;
}

- (void) encodeWithPDFContext: (O2PDFContext *) encoder {
    [_dictionary setIntegerForKey: "Length" value: [_data length]];

    [encoder encodePDFObject: _dictionary];
    [encoder appendCString: "stream\n"];
    [encoder appendData: _data];
    [encoder appendCString: "\nendstream\n"];
}

@end
