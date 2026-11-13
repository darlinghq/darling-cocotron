#ifndef COREGRAPHICS_CGPDFDICTIONARY_H
#define COREGRAPHICS_CGPDFDICTIONARY_H

#include <CoreGraphics/CGPDFObject.h>
#include <CoreGraphics/CGPDFString.h>
#include <CoreGraphics/CoreGraphicsExport.h>
#include <stdbool.h>

typedef struct CGPDFDictionary *CGPDFDictionaryRef;
typedef void (*CGPDFDictionaryApplierFunction)(const char *key, CGPDFObjectRef value, void *info);

COREGRAPHICS_EXPORT bool CGPDFDictionaryGetName(CGPDFDictionaryRef dict, const char *key, const char **value);
COREGRAPHICS_EXPORT bool CGPDFDictionaryGetString(CGPDFDictionaryRef dict, const char *key, CGPDFStringRef *value);

void CGPDFDictionaryApplyFunction(CGPDFDictionaryRef dict, CGPDFDictionaryApplierFunction function, void *info);

#endif // COREGRAPHICS_CGPDFDICTIONARY_H