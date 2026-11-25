#import <CoreGraphics/CGPDFOperatorTable.h>
#import <Onyx2D/O2PDFOperatorTable.h>

CGPDFOperatorTableRef CGPDFOperatorTableCreate(void) {
    return (CGPDFOperatorTableRef)[[O2PDFOperatorTable alloc] init];
}

CGPDFOperatorTableRef CGPDFOperatorTableRetain(CGPDFOperatorTableRef table) {
    return (CGPDFOperatorTableRef)[(O2PDFOperatorTable *)table retain];
}

void CGPDFOperatorTableRelease(CGPDFOperatorTableRef table) {
    [(O2PDFOperatorTable *)table release];
}

// CGPDFOperatorCallback and O2PDFOperatorCallback have the same shape: a scanner pointer, which is
// the O2PDFScanner itself, and the info pointer given to the scanner. The conversion goes through
// the generic function pointer type, as the two pointer types name different (opaque) classes.
//
// GUESS: a NULL table or name does nothing, and a second callback for a name replaces the first;
// the documentation states neither.
void CGPDFOperatorTableSetCallback(CGPDFOperatorTableRef table, const char *name, CGPDFOperatorCallback callback) {
    if (!table || !name)
        return;
    [(O2PDFOperatorTable *)table setCallback:(O2PDFOperatorCallback)(void (*)(void))callback forName:name];
}
