#import <Onyx2D/O2ImageDecoder_JPEG_libjpeg.h>

#import <Onyx2D/O2Defines_libjpeg.h>

#ifdef LIBJPEG_PRESENT

#import <jpeglib.h>
#include <limits.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

@implementation O2ImageDecoder_JPEG_libjpeg

typedef struct o2jpg_error_mgr {
    struct jpeg_error_mgr err;
    jmp_buf jmp; // Additional info about where to go on error
} o2jpg_error_mgr;

// Use libjpeg to do the decoding
static void o2error_exit(j_common_ptr cinfo) {
    o2jpg_error_mgr *o2err = (o2jpg_error_mgr *) cinfo->err;

    // Doesn't hurt to display what went wrong
    (*cinfo->err->output_message)(cinfo);

    // Jump to our error handling code
    longjmp(o2err->jmp, 1);
}

BOOL O2JPEGGetDimensions(CFDataRef data, size_t *width, size_t *height) {
    if (data == NULL || width == NULL || height == NULL)
        return NO;
    CFIndex length = CFDataGetLength(data);
    if (length <= 0 || (uintmax_t) length > ULONG_MAX)
        return NO;
    struct jpeg_decompress_struct *cinfo = calloc(1, sizeof(*cinfo));
    if (cinfo == NULL)
        return NO;
    o2jpg_error_mgr jerr;
    cinfo->err = jpeg_std_error(&jerr.err);
    jerr.err.error_exit = o2error_exit;
    if (setjmp(jerr.jmp)) {
        jpeg_destroy_decompress(cinfo);
        free(cinfo);
        return NO;
    }
    jpeg_create_decompress(cinfo);
    jpeg_mem_src(cinfo, CFDataGetBytePtr(data), (unsigned long) length);
    if (jpeg_read_header(cinfo, TRUE) != JPEG_HEADER_OK) {
        jpeg_destroy_decompress(cinfo);
        free(cinfo);
        return NO;
    }
    size_t imageWidth = cinfo->image_width;
    size_t imageHeight = cinfo->image_height;
    jpeg_destroy_decompress(cinfo);
    free(cinfo);
    *width = imageWidth;
    *height = imageHeight;
    return YES;
}

// QUIRK: ImageIO refuses to create an image for a JPEG whose declared size is more than 100 million pixels (10000x10000
// is the largest square one it decodes; 10001x10000 and 16384x16384 give no image), and the decoded size must neither
// overflow nor force a huge allocation for a header of a few hundred bytes (up to 65500x65500 pixels).
// Evidence: black-box observation of CGImageSourceCreateImageAtIndex on macOS 26.7.3 and 10.14.4 (x86_64 and i386,
// identical), tier 2: header-only JPEGs of 8192x8192, 9000x9000, 9999x10000, 10000x9999 and 10000x10000 give an image,
// 10001x10000, 10000x10001, 11000x11000, 12000x8334 and 16384x16384 give none. macOS also refuses some narrower
// images than that (for example 20000x20 and 3x60000); only the area bound is reproduced here.
// Test: tests/imageio-jpeg-decode-limits.c
#define O2JPEG_MAX_PIXELS ((size_t) 100000000)

static unsigned char *stbi_jpeg_load_from_memory(const uint8_t const *buffer,
                                                 int len, int *x, int *y)
{
    struct jpeg_decompress_struct cinfo;
    o2jpg_error_mgr jerr;

    // Zeroed so that jpeg_destroy_decompress is safe (mem is NULL) if
    // jpeg_create_decompress fails before it initializes the struct.
    memset(&cinfo, 0, sizeof(cinfo));
    // libjpeg reports errors from jpeg_create_decompress through cinfo.err,
    // so it has to be set up first.
    cinfo.err = jpeg_std_error(&jerr.err);
    // Use our own exit routine - we don't want to exit the app when something
    // goes wrong
    jerr.err.error_exit = o2error_exit;
    // We need to use setjmp since the error exit method must no return
    // Modified after setjmp and read after longjmp, so it must live in memory
    unsigned char *volatile outputImage = NULL;
    if (setjmp(jerr.jmp)) {
        // Do some cleaning and return an empty image
        jpeg_destroy_decompress(&cinfo);
        free(outputImage);
        return 0;
    }
    jpeg_create_decompress(&cinfo);

    /// Read the data from our memory buffer
    jpeg_mem_src(&cinfo, (unsigned char *) buffer, len);

    // Setup the jpeg header and set the decompress options
    jpeg_read_header(&cinfo, TRUE);

    // Reject an image with too many pixels before libjpeg allocates anything
    // for it.
    if (cinfo.image_width == 0 || cinfo.image_height == 0 ||
        cinfo.image_width > O2JPEG_MAX_PIXELS ||
        cinfo.image_height > O2JPEG_MAX_PIXELS / cinfo.image_width) {
        jpeg_destroy_decompress(&cinfo);
        return NULL;
    }

    // We only support RGBA format for the output format
    if (cinfo.jpeg_color_space == JCS_CMYK ||
        cinfo.jpeg_color_space == JCS_YCCK) {
        // libjpeg doesn't know how to do the CMYK->RGBx conversion - we'll have
        // to do it ourself
        cinfo.out_color_space = JCS_CMYK;
    } else {
#ifdef JCS_ALPHA_EXTENSIONS
        // libjpeg turbo can convert the output data directly to the RGBA buffer
        // format we want
        cinfo.out_color_space = JCS_EXT_RGBA;
#else
        cinfo.out_color_space = JCS_RGB;
#endif
    }
    int wantedPixelSize = cinfo.output_components = cinfo.out_color_components =
            4;

    jpeg_start_decompress(&cinfo);
    *x = cinfo.output_width;
    *y = cinfo.output_height;

    // Number of bytes in a decompressed row
    size_t bytesPerRow = (size_t) cinfo.output_width * wantedPixelSize;

    // Buffer for the final decompressed data
    outputImage = (unsigned char *) malloc(bytesPerRow * cinfo.output_height);
    if (outputImage) {
#ifdef JCS_ALPHA_EXTENSIONS
        // Scanline buffers pointers - they'll point directly to the final image
        // buffer
        JSAMPROW scanlineBuffer[cinfo.rec_outbuf_height];
#else
        // Scanline buffers
        JSAMPARRAY scanlineBuffer = (*cinfo.mem->alloc_sarray)(
                (j_common_ptr) &cinfo, JPOOL_IMAGE, bytesPerRow,
                cinfo.rec_outbuf_height);
#endif

        while (cinfo.output_scanline < cinfo.image_height) {
            size_t currentLine = cinfo.output_scanline;
#ifdef JCS_ALPHA_EXTENSIONS
            // We'll decode directly into the final buffer. Only rows inside it
            // are handed to libjpeg, and only the rows it returns in linesRead
            // are converted.
            JDIMENSION rowsLeft = cinfo.output_height - cinfo.output_scanline;
            JDIMENSION rowsWanted = (JDIMENSION) cinfo.rec_outbuf_height;
            if (rowsWanted > rowsLeft)
                rowsWanted = rowsLeft;
            for (JDIMENSION i = 0; i < rowsWanted; ++i) {
                scanlineBuffer[i] =
                        outputImage + (currentLine + i) * bytesPerRow;
            }
            JDIMENSION linesRead =
                    jpeg_read_scanlines(&cinfo, scanlineBuffer, rowsWanted);
            if (cinfo.out_color_space == JCS_CMYK) {
                // Convert from CMYK to RGBA
                for (JDIMENSION i = 0; i < linesRead; ++i) {
                    unsigned char *out =
                            outputImage + (currentLine++) * bytesPerRow;
                    for (int j = 0; j < cinfo.output_width; ++j) {
                        unsigned char c = out[0];
                        unsigned char m = out[1];
                        unsigned char y = out[2];
                        unsigned char k = out[3];
                        int r = (c * k) / 255;
                        int g = (m * k) / 255;
                        int b = (y * k) / 255;

                        *out++ = r;
                        *out++ = g;
                        *out++ = b;
                        *out++ = 0xff; // add the alpha component
                    }
                }
            }
#else
            int count = jpeg_read_scanlines(&cinfo, scanlineBuffer,
                                            cinfo.rec_outbuf_height);
            for (int i = 0; i < count; ++i) {
                char *out = outputImage + (currentLine++) * bytesPerRow;
                const char *scanline = scanlineBuffer[i];
                for (int j = 0; j < cinfo.output_width; ++j) {
                    if (cinfo.out_color_space == JCS_CMYK) {
                        // Convert from CMYK to RGBA
                        unsigned char c = *scanline++;
                        unsigned char m = *scanline++;
                        unsigned char y = *scanline++;
                        unsigned char k = *scanline++;
                        int r = (c * k) / 255;
                        int g = (m * k) / 255;
                        int b = (y * k) / 255;

                        *out++ = r;
                        *out++ = g;
                        *out++ = b;
                        *out++ = 0xff; // add the alpha component
                    } else {
                        // Convert from RGB to RGBA
                        *out++ = *scanline++;
                        *out++ = *scanline++;
                        *out++ = *scanline++;
                        *out++ = 0xff; // add the alpha component
                    }
                }
            }
#endif
        }
    }
    // We're done - do some cleanup
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);

    return outputImage;
}

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
    uint8_t *bitmap;

    int width, height;

    bitmap = stbi_jpeg_load_from_memory(encodedBytes, encodedLength, &width,
                                        &height);

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

#endif
