#ifndef COREGRAPHICS_CGPDFSCANNER_H
#define COREGRAPHICS_CGPDFSCANNER_H

#include <stdbool.h>

typedef struct CGPDFScanner *CGPDFScannerRef;

// Each header declares its own reference type before including the others, so the
// headers can be included in any order.
#include <CoreGraphics/CGPDFArray.h>
#include <CoreGraphics/CGPDFContentStream.h>
#include <CoreGraphics/CGPDFDictionary.h>
#include <CoreGraphics/CGPDFObject.h>
#include <CoreGraphics/CGPDFOperatorTable.h>
#include <CoreGraphics/CGPDFStream.h>
#include <CoreGraphics/CGPDFString.h>
#include <CoreGraphics/CoreGraphicsExport.h>

COREGRAPHICS_EXPORT CGPDFScannerRef CGPDFScannerCreate(CGPDFContentStreamRef cs, CGPDFOperatorTableRef table, void *info);
COREGRAPHICS_EXPORT CGPDFScannerRef CGPDFScannerRetain(CGPDFScannerRef scanner);
COREGRAPHICS_EXPORT void CGPDFScannerRelease(CGPDFScannerRef scanner);
COREGRAPHICS_EXPORT bool CGPDFScannerScan(CGPDFScannerRef scanner);
COREGRAPHICS_EXPORT CGPDFContentStreamRef CGPDFScannerGetContentStream(CGPDFScannerRef scanner);

COREGRAPHICS_EXPORT bool CGPDFScannerPopObject(CGPDFScannerRef scanner, CGPDFObjectRef *value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopBoolean(CGPDFScannerRef scanner, CGPDFBoolean *value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopInteger(CGPDFScannerRef scanner, CGPDFInteger *value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopNumber(CGPDFScannerRef scanner, CGPDFReal *value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopName(CGPDFScannerRef scanner, const char **value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopString(CGPDFScannerRef scanner, CGPDFStringRef *value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopArray(CGPDFScannerRef scanner, CGPDFArrayRef *value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopDictionary(CGPDFScannerRef scanner, CGPDFDictionaryRef *value);
COREGRAPHICS_EXPORT bool CGPDFScannerPopStream(CGPDFScannerRef scanner, CGPDFStreamRef *value);

#endif // COREGRAPHICS_CGPDFSCANNER_H
