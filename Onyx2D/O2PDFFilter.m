/* Copyright (c) 2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

/*  zlib decode is based on the public domain zlib decode v0.2 by Sean Barrett
 * 2006-11-18  http://www.nothings.org/stb_image.c  V 0.57 */

#include <stdlib.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Onyx2D/O2ImageSource_JPEG.h>
#import <Onyx2D/O2LZW.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFFilter.h>
#import <Onyx2D/O2PDFObject.h>
#import <Onyx2D/O2zlib.h>
#import <string.h>

// Undoes the Predictor of FlateDecode (PDF 7.4.4.4): 2 is TIFF
// predictor 2, 10-15 the PNG predictors, each row starting with its filter
// type (None, Sub, Up, Average, Paeth), applied byte-wise with the bytes per
// pixel as distance to the left and the decoded previous row above.
static NSData *O2PDFUndoPredictor(NSData *data, O2PDFDictionary *parameters,
                                  O2PDFInteger predictor, size_t *pBytesPerRow)
{
    O2PDFInteger colors, bitsPerComponent, columns;

    if (![parameters getIntegerForKey: "Colors" value: &colors])
        colors = 1;
    if (![parameters getIntegerForKey: "BitsPerComponent" value: &bitsPerComponent])
        bitsPerComponent = 8;
    if (![parameters getIntegerForKey: "Columns" value: &columns])
        columns = 1;
    if (colors < 1 || bitsPerComponent < 1 || columns < 1)
        return data;

    size_t bytesPerRow = ((colors * bitsPerComponent) * columns + 7) / 8;
    size_t bpp = (colors * bitsPerComponent + 7) / 8;
    const uint8_t *in = [data bytes];
    size_t length = [data length];

    if (pBytesPerRow != NULL)
        *pBytesPerRow = bytesPerRow;

    if (predictor == 2) {
        // TIFF predictor 2, 8-bit components: each byte adds the one a pixel
        // to its left.
        NSMutableData *result = [NSMutableData dataWithData: data];
        uint8_t *out = [result mutableBytes];

        if (bitsPerComponent != 8)
            return data;
        for (size_t row = 0; row + bytesPerRow <= length; row += bytesPerRow)
            for (size_t i = bpp; i < bytesPerRow; i++)
                out[row + i] += out[row + i - bpp];
        return result;
    }

    size_t numberOfRows = length / (bytesPerRow + 1);
    NSMutableData *result = [NSMutableData dataWithLength: numberOfRows * bytesPerRow];
    uint8_t *out = [result mutableBytes];

    for (size_t row = 0; row < numberOfRows; row++) {
        uint8_t filter = in[0];

        if (filter > 4) {
            O2PDFError(__FILE__, __LINE__, @"Unknown PNG predictor filter %d", filter);
            filter = 0;
        }
        const uint8_t *src = in + 1;
        uint8_t *cur = out + row * bytesPerRow;
        const uint8_t *prev = row > 0 ? cur - bytesPerRow : NULL;

        for (size_t i = 0; i < bytesPerRow; i++) {
            int left = i >= bpp ? cur[i - bpp] : 0;
            int up = prev ? prev[i] : 0;
            int upLeft = (prev && i >= bpp) ? prev[i - bpp] : 0;
            int value = src[i];

            switch (filter) {
            case 0:
                break;
            case 1:
                value += left;
                break;
            case 2:
                value += up;
                break;
            case 3:
                value += (left + up) / 2;
                break;
            case 4: {
                int p = left + up - upLeft;
                int pa = abs(p - left), pb = abs(p - up), pc = abs(p - upLeft);

                value += (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : upLeft);
                break;
            }
            }
            cur[i] = (uint8_t) value;
        }
        in += bytesPerRow + 1;
    }
    return result;
}

@implementation O2PDFFilter

+ (NSData *) FlateDecode_data: (NSData *) data
                   parameters: (O2PDFDictionary *) parameters
{
    int len;
    unsigned char *result =
            stbi_zlib_decode_malloc([data bytes], [data length], &len);

    if (result == NULL)
        return nil;

    return [NSData dataWithBytesNoCopy: result length: len];
}

+ (NSData *) LZWDecode_data: (NSData *) data
                 parameters: (O2PDFDictionary *) parameters
{
    return LZWDecodeWithExpectedResultLength(data, [data length] * 10);
}

+ (NSData *) decodeWithName: (const char *) name
                       data: (NSData *) data
                 parameters: (O2PDFDictionary *) parameters
                bytesPerRow: (size_t *) pBytesPerRow
{

    if ((strcmp(name, "FlateDecode") == 0) || (strcmp(name, "FL") == 0))
        data = [self FlateDecode_data: data parameters: parameters];
    else if ((strcmp(name, "DCTDecode") == 0) || (strcmp(name, "DCT") == 0)) {
        return O2DCTDecode(data, pBytesPerRow);
    } else if ((strcmp(name, "LZWDecode") == 0) || (strcmp(name, "LZW") == 0)) {
        data = LZWDecodeWithExpectedResultLength(data, [data length] * 10);
    } else {
        O2PDFError(__FILE__, __LINE__,
                   @"Unknown O2PDFFilter name = %s, parameters=%@", name,
                   parameters);
        return nil;
    }

    O2PDFInteger predictor = 0;

    if ([parameters getIntegerForKey: "Predictor" value: &predictor] &&
        predictor > 1)
        data = O2PDFUndoPredictor(data, parameters, predictor, pBytesPerRow);

    return data;
}

@end
