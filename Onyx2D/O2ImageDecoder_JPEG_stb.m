#import <Onyx2D/O2ImageDecoder_JPEG_stb.h>

#include <limits.h>

/* JPEG decoding by stb_image (public domain or MIT, Sean Barrett:
 * https://github.com/nothings/stb), stb_image.h next to this file. See
 * THIRD-PARTY-NOTICES.md. Unlike the stb_image 1.14 decoder that was embedded
 * here before, it reads progressive JPEGs. */
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
// No failure strings: they live in a thread-local variable.
#define STBI_NO_FAILURE_STRINGS
#define STBI_NO_THREAD_LOCALS
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

@implementation O2ImageDecoder_JPEG_stb

- initWithDataProvider: (O2DataProviderRef) dataProvider {

    _compressionType = O2ImageCompressionJPEG;
    _dataProvider = [dataProvider retain];

    CFDataRef encodedData = O2DataProviderCopyData(dataProvider);
    if (encodedData == NULL) {
        [self release];
        return nil;
    }
    CFIndex encodedLength = CFDataGetLength(encodedData);
    const uint8_t *encodedBytes = CFDataGetBytePtr(encodedData);

    int comp;
    uint8_t *bitmap = NULL;
    int width, height;

    // stb_image takes the length as an int
    if (encodedLength > 0 && encodedLength <= INT_MAX)
        bitmap = stbi_load_from_memory(encodedBytes, (int) encodedLength,
                                       &width, &height, &comp, STBI_rgb_alpha);

    CFRelease(encodedData);

    if (bitmap == NULL) {
        [self release];
        return nil;
    }

    _width = width;
    _height = height;
    _bitsPerComponent = 8;
    _bitsPerPixel = 32;
    _bytesPerRow = (_bitsPerPixel / (sizeof(char) * 8)) * _width;
    _colorSpace = O2ColorSpaceCreateDeviceRGB();
    // JPEG has no alpha: the fourth byte of each pixel is padding
    _bitmapInfo = kO2BitmapByteOrder32Big | kO2ImageAlphaNoneSkipLast;

    // stb_image allocates the pixels with malloc, which freeWhenDone releases
    _pixelData = (CFDataRef)
            [[NSData alloc] initWithBytesNoCopy: bitmap
                                         length: _bytesPerRow * _height
                                   freeWhenDone: YES];

    return self;
}

- (void) dealloc {
    [_dataProvider release];
    [_colorSpace release];
    if (_pixelData != NULL)
        CFRelease(_pixelData);
    [super dealloc];
}

- (CFDataRef) createPixelData {
    return CFRetain(_pixelData);
}

@end
