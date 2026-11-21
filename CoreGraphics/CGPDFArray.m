#import <CoreGraphics/CGPDFArray.h>
#import <Onyx2D/O2PDFArray.h>

// An indirect reference is followed when the element is read. One that points nowhere reads as
// a PDF null object.

size_t CGPDFArrayGetCount(CGPDFArrayRef array) {
    return [(O2PDFArray *)array count];
}

bool CGPDFArrayGetObject(CGPDFArrayRef array, size_t index, CGPDFObjectRef *value) {
    O2PDFArray *pdfArray = (O2PDFArray *)array;

    // The documentation leaves an index past the end undefined; this reports no object.
    if (index >= [pdfArray count])
        return false;
    if (value)
        *value = (CGPDFObjectRef)[[pdfArray objectAtIndex:index] realObject];
    return true;
}

bool CGPDFArrayGetNull(CGPDFArrayRef array, size_t index) {
    return [(O2PDFArray *)array getNullAtIndex:index];
}

bool CGPDFArrayGetBoolean(CGPDFArrayRef array, size_t index, CGPDFBoolean *value) {
    O2PDFBoolean boolean;
    bool found = [(O2PDFArray *)array getBooleanAtIndex:index value:&boolean];
    if (found && value) *value = (CGPDFBoolean)boolean;
    return found;
}

bool CGPDFArrayGetInteger(CGPDFArrayRef array, size_t index, CGPDFInteger *value) {
    O2PDFInteger integer;
    bool found = [(O2PDFArray *)array getIntegerAtIndex:index value:&integer];
    if (found && value) *value = (CGPDFInteger)integer;
    return found;
}

// An integer element is a number too: O2PDFObject_Integer answers a request for a real.
bool CGPDFArrayGetNumber(CGPDFArrayRef array, size_t index, CGPDFReal *value) {
    O2PDFReal real;
    bool found = [(O2PDFArray *)array getNumberAtIndex:index value:&real];
    if (found && value) *value = (CGPDFReal)real;
    return found;
}

bool CGPDFArrayGetName(CGPDFArrayRef array, size_t index, const char **value) {
    const char *name;
    bool found = [(O2PDFArray *)array getNameAtIndex:index value:&name];
    if (found && value) *value = name;
    return found;
}

bool CGPDFArrayGetString(CGPDFArrayRef array, size_t index, CGPDFStringRef *value) {
    O2PDFString *string;
    bool found = [(O2PDFArray *)array getStringAtIndex:index value:&string];
    if (found && value) *value = (CGPDFStringRef)string;
    return found;
}

bool CGPDFArrayGetArray(CGPDFArrayRef array, size_t index, CGPDFArrayRef *value) {
    O2PDFArray *inner;
    bool found = [(O2PDFArray *)array getArrayAtIndex:index value:&inner];
    if (found && value) *value = (CGPDFArrayRef)inner;
    return found;
}

bool CGPDFArrayGetDictionary(CGPDFArrayRef array, size_t index, CGPDFDictionaryRef *value) {
    O2PDFDictionary *dictionary;
    bool found = [(O2PDFArray *)array getDictionaryAtIndex:index value:&dictionary];
    if (found && value) *value = (CGPDFDictionaryRef)dictionary;
    return found;
}

bool CGPDFArrayGetStream(CGPDFArrayRef array, size_t index, CGPDFStreamRef *value) {
    O2PDFStream *stream;
    bool found = [(O2PDFArray *)array getStreamAtIndex:index value:&stream];
    if (found && value) *value = (CGPDFStreamRef)stream;
    return found;
}
