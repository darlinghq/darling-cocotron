#import <CoreGraphics/CGPDFObject.h>
#import <Onyx2D/O2PDFObject.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2PDFString.h>

_Static_assert((int)kCGPDFObjectTypeNull == (int)kO2PDFObjectTypeNull, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeBoolean == (int)kO2PDFObjectTypeBoolean, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeInteger == (int)kO2PDFObjectTypeInteger, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeReal == (int)kO2PDFObjectTypeReal, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeName == (int)kO2PDFObjectTypeName, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeString == (int)kO2PDFObjectTypeString, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeArray == (int)kO2PDFObjectTypeArray, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeDictionary == (int)kO2PDFObjectTypeDictionary, "CGPDFObjectType must match O2PDFObjectType");
_Static_assert((int)kCGPDFObjectTypeStream == (int)kO2PDFObjectTypeStream, "CGPDFObjectType must match O2PDFObjectType");

// A NULL object is what CGPDFDictionaryGetObject and the applier hand out for a reference to an object that does not
// exist; macOS 26.7.3 and 10.14.4 report its type as the null type, while GetValue refuses it for every type.
// Test: tests/coregraphics-pdf-object-type.m
CGPDFObjectType CGPDFObjectGetType(CGPDFObjectRef object) {
    if (object == NULL)
        return kCGPDFObjectTypeNull;
    return (CGPDFObjectType)[(O2PDFObject *)object objectType];
}

bool CGPDFObjectGetValue(CGPDFObjectRef object, CGPDFObjectType type, void *value) {
    O2PDFObject *pdfObject = (O2PDFObject *)object;
    O2PDFObjectType pdfType = (O2PDFObjectType)type;
    union {
        O2PDFBoolean boolean;
        O2PDFInteger integer;
        O2PDFReal real;
        const char *name;
        void *reference;
    } stored;

    switch (type) {
    case kCGPDFObjectTypeNull:
        return [pdfObject objectType] == kO2PDFObjectTypeNull;
    case kCGPDFObjectTypeBoolean:
    case kCGPDFObjectTypeInteger:
    case kCGPDFObjectTypeReal:
    case kCGPDFObjectTypeName:
    case kCGPDFObjectTypeString:
    case kCGPDFObjectTypeArray:
    case kCGPDFObjectTypeDictionary:
    case kCGPDFObjectTypeStream:
        break;
    default:
        return false;
    }

    // The O2PDFObject classes widen an integer to a real, the conversion CGPDFObjectGetValue is documented to make.
    if (![pdfObject checkForType:pdfType value:&stored])
        return false;
    if (value == NULL)
        return true;

    switch (type) {
    case kCGPDFObjectTypeBoolean:
        *(CGPDFBoolean *)value = (CGPDFBoolean)stored.boolean;
        break;
    case kCGPDFObjectTypeInteger:
        *(CGPDFInteger *)value = (CGPDFInteger)stored.integer;
        break;
    case kCGPDFObjectTypeReal:
        *(CGPDFReal *)value = (CGPDFReal)stored.real;
        break;
    case kCGPDFObjectTypeName:
        *(const char **)value = stored.name;
        break;
    default:
        *(void **)value = stored.reference;
        break;
    }
    return true;
}
