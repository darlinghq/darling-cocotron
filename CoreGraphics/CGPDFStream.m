#import <CoreGraphics/CGPDFStream.h>
#import <Onyx2D/O2PDFStream.h>
#import <Foundation/NSData.h>
#include <CoreFoundation/CFData.h>

CGPDFDictionaryRef CGPDFStreamGetDictionary(CGPDFStreamRef stream) {
    return (CGPDFDictionaryRef)[(O2PDFStream *)stream dictionary];
}

// GUESS: the documentation says only that the result is a copy of the stream data and
// that format reports raw, JPEG-encoded or JPEG 2000 data. Filters the Onyx2D decoder
// implements are decoded and give Raw; a DCT or JPX filter that ends the chain is left
// applied and gives JPEGEncoded or JPEG2000. NULL, with format untouched, when the
// stream cannot be decoded or stream is NULL; a NULL format is accepted and ignored.
CFDataRef CGPDFStreamCopyData(CGPDFStreamRef stream, CGPDFDataFormat *format) {
    if (!stream)
        return NULL;
    O2PDFStreamImageFilter imageFilter;
    NSData *data = [(O2PDFStream *)stream dataLeavingImageFilter: &imageFilter];
    if (!data)
        return NULL;
    if (format) {
        switch (imageFilter) {
        case kO2PDFStreamDCTImageFilter:
            *format = CGPDFDataFormatJPEGEncoded;
            break;
        case kO2PDFStreamJPXImageFilter:
            *format = CGPDFDataFormatJPEG2000;
            break;
        default:
            *format = CGPDFDataFormatRaw;
            break;
        }
    }
    return CFDataCreate(NULL, [data bytes], [data length]);
}
