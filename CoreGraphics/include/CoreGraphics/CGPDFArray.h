#ifndef COREGRAPHICS_CGPDFARRAY_H
#define COREGRAPHICS_CGPDFARRAY_H

#include <stdbool.h>
#include <stddef.h>

typedef struct CGPDFArray *CGPDFArrayRef;

// Each header declares its own reference type before including the others, so the
// three headers can be included in any order.
#include <CoreGraphics/CGPDFDictionary.h>
#include <CoreGraphics/CGPDFObject.h>
#include <CoreGraphics/CGPDFStream.h>
#include <CoreGraphics/CGPDFString.h>
#include <CoreGraphics/CoreGraphicsExport.h>

COREGRAPHICS_EXPORT size_t CGPDFArrayGetCount(CGPDFArrayRef array);
COREGRAPHICS_EXPORT bool CGPDFArrayGetObject(CGPDFArrayRef array, size_t index, CGPDFObjectRef *value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetNull(CGPDFArrayRef array, size_t index);
COREGRAPHICS_EXPORT bool CGPDFArrayGetBoolean(CGPDFArrayRef array, size_t index, CGPDFBoolean *value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetInteger(CGPDFArrayRef array, size_t index, CGPDFInteger *value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetNumber(CGPDFArrayRef array, size_t index, CGPDFReal *value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetName(CGPDFArrayRef array, size_t index, const char **value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetString(CGPDFArrayRef array, size_t index, CGPDFStringRef *value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetArray(CGPDFArrayRef array, size_t index, CGPDFArrayRef *value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetDictionary(CGPDFArrayRef array, size_t index, CGPDFDictionaryRef *value);
COREGRAPHICS_EXPORT bool CGPDFArrayGetStream(CGPDFArrayRef array, size_t index, CGPDFStreamRef *value);

#endif // COREGRAPHICS_CGPDFARRAY_H
