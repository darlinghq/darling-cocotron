#import <CoreGraphics/CGPDFArray.h>
#import <Onyx2D/O2PDFArray.h>

#import <Onyx2D/O2PDFObject_const.h>

// An indirect reference is followed when the element is read. QUIRK: one that points to an
// object that does not exist gives no object at all: CGPDFArrayGetObject returns false and
// stores NULL, and the element is not a null (CGPDFArrayGetNull is false) nor any typed value.
// A null object written in the file ("null") is a real null object. Black-box observation of
// macOS 26.7.3 (tier 2); the documentation does not cover dangling references.
// Test: the missing-object checks of tests/coregraphics-pdf-array-stream-dictionary.m
static BOOL isMissingObject(O2PDFObject *object) {
    return object == [O2PDFObject_const pdfObjectWithMissingObject];
}

size_t CGPDFArrayGetCount(CGPDFArrayRef array) {
    return [(O2PDFArray *)array count];
}

bool CGPDFArrayGetObject(CGPDFArrayRef array, size_t index, CGPDFObjectRef *value) {
    O2PDFArray *pdfArray = (O2PDFArray *)array;

    // The documentation leaves an index past the end undefined; this reports no object.
    if (index >= [pdfArray count])
        return false;
    O2PDFObject *object = [[pdfArray objectAtIndex:index] realObject];

    if (isMissingObject(object)) {
        if (value)
            *value = NULL;
        return false;
    }
    if (value)
        *value = (CGPDFObjectRef)object;
    return true;
}

bool CGPDFArrayGetNull(CGPDFArrayRef array, size_t index) {
    if (index >= [(O2PDFArray *)array count] || isMissingObject([[(O2PDFArray *)array objectAtIndex:index] realObject]))
        return false;
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
