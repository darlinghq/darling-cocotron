#ifndef COREGRAPHICS_CGPDFSTREAM_H
#define COREGRAPHICS_CGPDFSTREAM_H

typedef struct CGPDFStream *CGPDFStreamRef;

#include <CoreFoundation/CFData.h>
#include <CoreGraphics/CGPDFDictionary.h>
#include <CoreGraphics/CoreGraphicsExport.h>

// The numeric values are GUESS: the documentation names the constants and
// their order but not their values.
typedef CF_ENUM(int32_t, CGPDFDataFormat) {
    CGPDFDataFormatRaw,
    CGPDFDataFormatJPEGEncoded,
    CGPDFDataFormatJPEG2000
};

COREGRAPHICS_EXPORT CGPDFDictionaryRef CGPDFStreamGetDictionary(CGPDFStreamRef stream);
COREGRAPHICS_EXPORT CFDataRef CGPDFStreamCopyData(CGPDFStreamRef stream, CGPDFDataFormat *format);

#endif // COREGRAPHICS_CGPDFSTREAM_H
