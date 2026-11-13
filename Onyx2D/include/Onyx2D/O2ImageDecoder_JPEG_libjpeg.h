#import <Onyx2D/O2ImageDecoder.h>

BOOL O2JPEGGetDimensions(CFDataRef data, size_t *width, size_t *height);

@interface O2ImageDecoder_JPEG_libjpeg : O2ImageDecoder {
    CFDataRef _pixelData;
}

- initWithDataProvider: (O2DataProviderRef) dataProvider;

@end
