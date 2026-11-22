#ifndef COREGRAPHICS_CGPDFCONTENTSTREAM_H
#define COREGRAPHICS_CGPDFCONTENTSTREAM_H

#include <CoreFoundation/CFArray.h>
#include <CoreGraphics/CGPDFDictionary.h>
#include <CoreGraphics/CGPDFObject.h>
#include <CoreGraphics/CGPDFPage.h>
#include <CoreGraphics/CGPDFStream.h>
#include <CoreGraphics/CoreGraphicsExport.h>

typedef struct CGPDFContentStream *CGPDFContentStreamRef;

COREGRAPHICS_EXPORT CGPDFContentStreamRef CGPDFContentStreamCreateWithPage(CGPDFPageRef page);
COREGRAPHICS_EXPORT CGPDFContentStreamRef CGPDFContentStreamCreateWithStream(CGPDFStreamRef stream, CGPDFDictionaryRef streamResources, CGPDFContentStreamRef parent);
COREGRAPHICS_EXPORT CGPDFContentStreamRef CGPDFContentStreamRetain(CGPDFContentStreamRef cs);
COREGRAPHICS_EXPORT void CGPDFContentStreamRelease(CGPDFContentStreamRef cs);
COREGRAPHICS_EXPORT CFArrayRef CGPDFContentStreamGetStreams(CGPDFContentStreamRef cs);
COREGRAPHICS_EXPORT CGPDFObjectRef CGPDFContentStreamGetResource(CGPDFContentStreamRef cs, const char *category, const char *name);

#endif // COREGRAPHICS_CGPDFCONTENTSTREAM_H
