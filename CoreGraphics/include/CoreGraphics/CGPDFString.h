#ifndef COREGRAPHICS_CGPDFSTRING_H
#define COREGRAPHICS_CGPDFSTRING_H

#include <CoreFoundation/CFString.h>
#include <CoreGraphics/CoreGraphicsExport.h>
#include <stddef.h>

typedef struct CGPDFString *CGPDFStringRef;

COREGRAPHICS_EXPORT CFStringRef CGPDFStringCopyTextString(CGPDFStringRef string) CF_RETURNS_RETAINED;
COREGRAPHICS_EXPORT size_t CGPDFStringGetLength(CGPDFStringRef string);
COREGRAPHICS_EXPORT const unsigned char *CGPDFStringGetBytePtr(CGPDFStringRef string);

#endif
