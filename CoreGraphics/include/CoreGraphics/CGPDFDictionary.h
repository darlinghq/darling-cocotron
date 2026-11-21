#ifndef COREGRAPHICS_CGPDFDICTIONARY_H
#define COREGRAPHICS_CGPDFDICTIONARY_H

#include <stdbool.h>
#include <stddef.h>

typedef struct CGPDFDictionary *CGPDFDictionaryRef;

#include <CoreGraphics/CGPDFArray.h>
#include <CoreGraphics/CGPDFObject.h>
#include <CoreGraphics/CGPDFStream.h>
#include <CoreGraphics/CGPDFString.h>
#include <CoreGraphics/CoreGraphicsExport.h>

typedef void (*CGPDFDictionaryApplierFunction)(const char *key, CGPDFObjectRef value, void *info);

COREGRAPHICS_EXPORT size_t CGPDFDictionaryGetCount(CGPDFDictionaryRef dict);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetObject(CGPDFDictionaryRef dict, const char *key, CGPDFObjectRef *value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetBoolean(CGPDFDictionaryRef dict, const char *key, CGPDFBoolean *value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetInteger(CGPDFDictionaryRef dict, const char *key, CGPDFInteger *value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetNumber(CGPDFDictionaryRef dict, const char *key, CGPDFReal *value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetName(CGPDFDictionaryRef dict, const char *key, const char **value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetString(CGPDFDictionaryRef dict, const char *key, CGPDFStringRef *value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetArray(CGPDFDictionaryRef dict, const char *key, CGPDFArrayRef *value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetDictionary(CGPDFDictionaryRef dict, const char *key, CGPDFDictionaryRef *value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetStream(CGPDFDictionaryRef dict, const char *key, CGPDFStreamRef *value);
COREGRAPHICS_EXPORT void CGPDFDictionaryApplyFunction(CGPDFDictionaryRef dict, CGPDFDictionaryApplierFunction function, void *info);

#endif // COREGRAPHICS_CGPDFDICTIONARY_H
