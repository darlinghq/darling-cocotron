#import <CoreGraphics/CGPDFScanner.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFContentStream.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFOperatorTable.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2PDFString.h>

// The scanner keeps the content stream and the table, so the caller may release them after the
// call. A NULL table is allowed by the documentation: no operator has a callback then, and the
// operators are skipped with their operands (only registered operators invoke a callback, per the
// CGPDFScannerScan documentation).
//
// GUESS: a NULL content stream gives NULL; the documentation does not say.
CGPDFScannerRef CGPDFScannerCreate(CGPDFContentStreamRef cs, CGPDFOperatorTableRef table, void *info) {
    if (!cs)
        return NULL;
    return (CGPDFScannerRef)[[O2PDFScanner alloc] initWithContentStream:(O2PDFContentStream *)cs
                                                          operatorTable:(O2PDFOperatorTable *)table
                                                                   info:info];
}

CGPDFScannerRef CGPDFScannerRetain(CGPDFScannerRef scanner) {
    return (CGPDFScannerRef)[(O2PDFScanner *)scanner retain];
}

void CGPDFScannerRelease(CGPDFScannerRef scanner) {
    [(O2PDFScanner *)scanner release];
}

// True when the whole stream was parsed; false when parsing fails. A NULL scanner reports false.
bool CGPDFScannerScan(CGPDFScannerRef scanner) {
    return scanner && [(O2PDFScanner *)scanner scan];
}

CGPDFContentStreamRef CGPDFScannerGetContentStream(CGPDFScannerRef scanner) {
    return (CGPDFContentStreamRef)[(O2PDFScanner *)scanner contentStream];
}

// The Pop functions take the operand on top of the stack, so the operands of an operator come
// out in reverse order. A pop that finds no operand, or one of another type, returns false and
// leaves the output untouched. The stack holds only the operands written before the operator being
// handled (PDF 32000-1 7.8.2): operands its callback does not pop are dropped when it returns.
//
// GUESS: an operand of the wrong type is still removed from the stack (what Onyx2D does; the
// documentation does not say whether a failed pop consumes it), and a NULL scanner returns false.
// A popped name, string, array, dictionary or stream is released to the autorelease pool when it
// leaves the stack, so it stays valid until the pool in effect at the call drains; the
// documentation gives no lifetime.
bool CGPDFScannerPopObject(CGPDFScannerRef scanner, CGPDFObjectRef *value) {
    if (!scanner)
        return false;
    O2PDFObject *object;
    bool found = O2PDFScannerPopObject((O2PDFScanner *)scanner, &object);
    if (found && value) *value = (CGPDFObjectRef)object;
    return found;
}

bool CGPDFScannerPopBoolean(CGPDFScannerRef scanner, CGPDFBoolean *value) {
    if (!scanner)
        return false;
    O2PDFBoolean boolean;
    bool found = O2PDFScannerPopBoolean((O2PDFScanner *)scanner, &boolean);
    if (found && value) *value = (CGPDFBoolean)boolean;
    return found;
}

bool CGPDFScannerPopInteger(CGPDFScannerRef scanner, CGPDFInteger *value) {
    if (!scanner)
        return false;
    O2PDFInteger integer;
    bool found = O2PDFScannerPopInteger((O2PDFScanner *)scanner, &integer);
    if (found && value) *value = (CGPDFInteger)integer;
    return found;
}

// An integer operand is a number too (the result is always a CGPDFReal), as for the array and
// dictionary readers.
bool CGPDFScannerPopNumber(CGPDFScannerRef scanner, CGPDFReal *value) {
    if (!scanner)
        return false;
    O2PDFReal real;
    bool found = O2PDFScannerPopNumber((O2PDFScanner *)scanner, &real);
    if (found && value) *value = (CGPDFReal)real;
    return found;
}

bool CGPDFScannerPopName(CGPDFScannerRef scanner, const char **value) {
    if (!scanner)
        return false;
    const char *name;
    bool found = O2PDFScannerPopName((O2PDFScanner *)scanner, &name);
    if (found && value) *value = name;
    return found;
}

bool CGPDFScannerPopString(CGPDFScannerRef scanner, CGPDFStringRef *value) {
    if (!scanner)
        return false;
    O2PDFString *string;
    bool found = O2PDFScannerPopString((O2PDFScanner *)scanner, &string);
    if (found && value) *value = (CGPDFStringRef)string;
    return found;
}

bool CGPDFScannerPopArray(CGPDFScannerRef scanner, CGPDFArrayRef *value) {
    if (!scanner)
        return false;
    O2PDFArray *array;
    bool found = O2PDFScannerPopArray((O2PDFScanner *)scanner, &array);
    if (found && value) *value = (CGPDFArrayRef)array;
    return found;
}

bool CGPDFScannerPopDictionary(CGPDFScannerRef scanner, CGPDFDictionaryRef *value) {
    if (!scanner)
        return false;
    O2PDFDictionary *dictionary;
    bool found = O2PDFScannerPopDictionary((O2PDFScanner *)scanner, &dictionary);
    if (found && value) *value = (CGPDFDictionaryRef)dictionary;
    return found;
}

bool CGPDFScannerPopStream(CGPDFScannerRef scanner, CGPDFStreamRef *value) {
    if (!scanner)
        return false;
    O2PDFStream *stream;
    bool found = O2PDFScannerPopStream((O2PDFScanner *)scanner, &stream);
    if (found && value) *value = (CGPDFStreamRef)stream;
    return found;
}
