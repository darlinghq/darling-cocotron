#ifndef COREGRAPHICS_CGPDFSTREAM_H
#define COREGRAPHICS_CGPDFSTREAM_H

typedef struct CGPDFStream *CGPDFStreamRef;

#include <CoreGraphics/CGPDFDictionary.h>
#include <CoreGraphics/CoreGraphicsExport.h>

COREGRAPHICS_EXPORT CGPDFDictionaryRef CGPDFStreamGetDictionary(CGPDFStreamRef stream);

#endif // COREGRAPHICS_CGPDFSTREAM_H
