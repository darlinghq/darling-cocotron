#import <CoreGraphics/CGPDFDictionary.h>
#import <Onyx2D/O2PDFDictionary.h>

#import <Onyx2D/O2PDFObject_const.h>

// An indirect reference is followed when the entry is read. QUIRK: one that points to an object
// that does not exist is still an entry (it is counted and visited), but reading it as an
// object gives NULL, with CGPDFDictionaryGetObject returning true, and it is not any typed
// value. Black-box observation of macOS 26.7.3 (tier 2); the documentation does not cover
// dangling references.
// Test: the missing-object checks of tests/coregraphics-pdf-array-stream-dictionary.m
static CGPDFObjectRef publicObject(O2PDFObject *object) {
    return object == [O2PDFObject_const pdfObjectWithMissingObject] ? NULL : (CGPDFObjectRef)object;
}

size_t CGPDFDictionaryGetCount(CGPDFDictionaryRef dict) {
    return [(O2PDFDictionary *)dict count];
}

bool CGPDFDictionaryGetObject(CGPDFDictionaryRef dict, const char *key, CGPDFObjectRef *value) {
    O2PDFObject *object;
    bool found = [(O2PDFDictionary *)dict getObjectForKey:key value:&object];
    if (found && value) *value = publicObject(object);
    return found;
}

bool CGPDFDictionaryGetBoolean(CGPDFDictionaryRef dict, const char *key, CGPDFBoolean *value) {
    O2PDFBoolean boolean;
    bool found = [(O2PDFDictionary *)dict getBooleanForKey:key value:&boolean];
    if (found && value) *value = (CGPDFBoolean)boolean;
    return found;
}

bool CGPDFDictionaryGetInteger(CGPDFDictionaryRef dict, const char *key, CGPDFInteger *value) {
    O2PDFInteger integer;
    bool found = [(O2PDFDictionary *)dict getIntegerForKey:key value:&integer];
    if (found && value) *value = (CGPDFInteger)integer;
    return found;
}

// An integer entry is a number too: O2PDFObject_Integer answers a request for a real.
bool CGPDFDictionaryGetNumber(CGPDFDictionaryRef dict, const char *key, CGPDFReal *value) {
    O2PDFReal real;
    bool found = [(O2PDFDictionary *)dict getNumberForKey:key value:&real];
    if (found && value) *value = (CGPDFReal)real;
    return found;
}

bool CGPDFDictionaryGetName(CGPDFDictionaryRef dict, const char *key, const char **value) {
    const char *name;
    bool found = [(O2PDFDictionary *)dict getNameForKey:key value:&name];
    if (found && value) *value = name;
    return found;
}

bool CGPDFDictionaryGetString(CGPDFDictionaryRef dict, const char *key, CGPDFStringRef *value) {
    O2PDFString *string;
    bool found = [(O2PDFDictionary *)dict getStringForKey:key value:&string];
    if (found && value) *value = (CGPDFStringRef)string;
    return found;
}

bool CGPDFDictionaryGetArray(CGPDFDictionaryRef dict, const char *key, CGPDFArrayRef *value) {
    O2PDFArray *array;
    bool found = [(O2PDFDictionary *)dict getArrayForKey:key value:&array];
    if (found && value) *value = (CGPDFArrayRef)array;
    return found;
}

bool CGPDFDictionaryGetDictionary(CGPDFDictionaryRef dict, const char *key, CGPDFDictionaryRef *value) {
    O2PDFDictionary *dictionary;
    bool found = [(O2PDFDictionary *)dict getDictionaryForKey:key value:&dictionary];
    if (found && value) *value = (CGPDFDictionaryRef)dictionary;
    return found;
}

bool CGPDFDictionaryGetStream(CGPDFDictionaryRef dict, const char *key, CGPDFStreamRef *value) {
    O2PDFStream *stream;
    bool found = [(O2PDFDictionary *)dict getStreamForKey:key value:&stream];
    if (found && value) *value = (CGPDFStreamRef)stream;
    return found;
}

struct ApplierContext {
    CGPDFDictionaryApplierFunction function;
    void *info;
};

static void applyEntry(const char *key, O2PDFObject *value, void *context) {
    struct ApplierContext *applier = context;

    applier->function(key, publicObject(value), applier->info);
}

void CGPDFDictionaryApplyFunction(CGPDFDictionaryRef dict, CGPDFDictionaryApplierFunction function, void *info) {
    struct ApplierContext applier = {function, info};

    [(O2PDFDictionary *)dict applyFunction:applyEntry info:&applier];
}
