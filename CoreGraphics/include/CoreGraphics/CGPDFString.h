#ifndef COREGRAPHICS_CGPDFSTRING_H
#define COREGRAPHICS_CGPDFSTRING_H

#include <CoreFoundation/CFString.h>
#include <CoreGraphics/CoreGraphicsExport.h>

typedef struct CGPDFString *CGPDFStringRef;

COREGRAPHICS_EXPORT CFStringRef CGPDFStringCopyTextString(CGPDFStringRef string) CF_RETURNS_RETAINED;

#endif
