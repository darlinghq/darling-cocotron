#import <CoreGraphics/CGPDFDictionary.h>
#import <Onyx2D/O2PDFDictionary.h>

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
