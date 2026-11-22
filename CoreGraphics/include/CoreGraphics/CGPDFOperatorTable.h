#ifndef COREGRAPHICS_CGPDFOPERATORTABLE_H
#define COREGRAPHICS_CGPDFOPERATORTABLE_H

#include <CoreGraphics/CoreGraphicsExport.h>

typedef struct CGPDFOperatorTable *CGPDFOperatorTableRef;
typedef struct CGPDFScanner *CGPDFScannerRef;

// Called by a scanner when it reaches an operator the table has a callback for. The callback
// reads the operator's operands from the scanner and gets the info pointer given to
// CGPDFScannerCreate.
typedef void (*CGPDFOperatorCallback)(CGPDFScannerRef scanner, void *info);

COREGRAPHICS_EXPORT CGPDFOperatorTableRef CGPDFOperatorTableCreate(void);
COREGRAPHICS_EXPORT CGPDFOperatorTableRef CGPDFOperatorTableRetain(CGPDFOperatorTableRef table);
COREGRAPHICS_EXPORT void CGPDFOperatorTableRelease(CGPDFOperatorTableRef table);
COREGRAPHICS_EXPORT void CGPDFOperatorTableSetCallback(CGPDFOperatorTableRef table, const char *name, CGPDFOperatorCallback callback);

#endif // COREGRAPHICS_CGPDFOPERATORTABLE_H
