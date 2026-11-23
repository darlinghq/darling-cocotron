#ifndef CGPDFOBJECT_H
#define CGPDFOBJECT_H

#include <CoreFoundation/CFBase.h>
#include <CoreGraphics/CGBase.h>
#include <CoreGraphics/CoreGraphicsExport.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct CGPDFObject* CGPDFObjectRef;

typedef unsigned char CGPDFBoolean;
typedef long int CGPDFInteger;
typedef CGFloat CGPDFReal;

// The values were read from the type on macOS 26.7.3 and 10.14.4 (1 to 9 in the order of the cases) and are the same
// as the matching O2PDFObjectType constants in Onyx2D, which CGPDFObject.m checks at compile time.
typedef CF_ENUM(int32_t, CGPDFObjectType) {
    kCGPDFObjectTypeNull = 1,
    kCGPDFObjectTypeBoolean,
    kCGPDFObjectTypeInteger,
    kCGPDFObjectTypeReal,
    kCGPDFObjectTypeName,
    kCGPDFObjectTypeString,
    kCGPDFObjectTypeArray,
    kCGPDFObjectTypeDictionary,
    kCGPDFObjectTypeStream,
};

COREGRAPHICS_EXPORT CGPDFObjectType CGPDFObjectGetType(CGPDFObjectRef object);
COREGRAPHICS_EXPORT bool CGPDFObjectGetValue(CGPDFObjectRef object, CGPDFObjectType type, void *value);

#endif /* CGPDFOBJECT_H */
