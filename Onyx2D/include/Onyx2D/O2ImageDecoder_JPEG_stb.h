#import <Onyx2D/O2ImageDecoder.h>

// The pixel size of a JPEG that the stb decoder can read, from its header.
BOOL O2JPEGStbGetDimensions(CFDataRef data, size_t *width, size_t *height);

@interface O2ImageDecoder_JPEG_stb : O2ImageDecoder {
    CFDataRef _pixelData;
}

- initWithDataProvider: (O2DataProviderRef) dataProvider;

@end
