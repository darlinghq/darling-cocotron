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

// INFERRED, UNCONFIRMED (BLOCKED-NEEDS-VALUES): the documentation lists only the case names. The
// values are those of the matching O2PDFObjectType constants in Onyx2D, which CGPDFObject.m checks
// at compile time. They are not from a header that declares this type.
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
