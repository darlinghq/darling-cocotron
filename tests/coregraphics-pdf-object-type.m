// Contract: Apple CoreGraphics documentation for CGPDFObject (CGPDFObjectGetType, CGPDFObjectGetValue) and
// CGPDFObjectType (https://developer.apple.com/documentation/coregraphics). Exit codes identify the failing check.
// The numeric values of CGPDFObjectType (1 to 9 in the order of the cases) were read from the type on macOS 26.7.3
// and 10.14.4 and are pinned below. The document has a page because macOS refuses a document without one.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

static NSData *documentData(void) {
    NSMutableData *data = [NSMutableData dataWithData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
    const char *objects[] = {
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [5 0 R] /Count 1 >>",
        "<< /Title (Fixture) /Flag true /Off false /Count 7 /Ratio 2.5 /Kind /Fixture"
        " /List [1 2.5 (s) /Nm true null [3] << /K 1 >> 4 0 R 99 0 R]"
        " /Sub << /Depth 1 >> /Data 4 0 R /Nothing null /Dangling 99 0 R >>",
        "<< /Length 5 >>\nstream\nhello\nendstream",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>"
    };
    NSUInteger offsets[5];
    for (NSUInteger i = 0; i < 5; i++) {
        offsets[i] = [data length];
        NSString *object = [NSString stringWithFormat:@"%lu 0 obj\n%s\nendobj\n",
            (unsigned long)i + 1, objects[i]];
        [data appendData:[object dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSUInteger xref = [data length];
    [data appendData:[@"xref\n0 6\n0000000000 65535 f \n" dataUsingEncoding:NSASCIIStringEncoding]];
    for (NSUInteger i = 0; i < 5; i++) {
        NSString *entry = [NSString stringWithFormat:@"%010lu 00000 n \n", (unsigned long)offsets[i]];
        [data appendData:[entry dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSString *trailer = [NSString stringWithFormat:
        @"trailer\n<< /Size 6 /Root 1 0 R /Info 3 0 R >>\nstartxref\n%lu\n%%%%EOF\n",
        (unsigned long)xref];
    [data appendData:[trailer dataUsingEncoding:NSASCIIStringEncoding]];
    return data;
}

struct Visit {
    const char *keys[16];
    CGPDFObjectType types[16];
    int count;
};

static void visit(const char *key, CGPDFObjectRef value, void *info) {
    struct Visit *visited = info;
    if (visited->count < 16) {
        visited->keys[visited->count] = key;
        visited->types[visited->count] = CGPDFObjectGetType(value);
    }
    visited->count++;
}

static bool visitedType(const struct Visit *visited, const char *key, CGPDFObjectType type) {
    int seen = 0;
    bool match = false;
    for (int i = 0; i < visited->count && i < 16; i++) {
        if (strcmp(visited->keys[i], key) == 0) {
            seen++;
            match = visited->types[i] == type;
        }
    }
    return seen == 1 && match;
}

int main(void) {
    @autoreleasepool {
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)documentData());
        CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
        CGDataProviderRelease(provider);
        if (!document) return 10;
        CGPDFDictionaryRef dict = CGPDFDocumentGetInfo(document);
        if (!dict) return 11;

        // The applier hands over each entry's object; its type is that of the value.
        struct Visit visited = {{0}, {0}, 0};
        CGPDFDictionaryApplyFunction(dict, visit, &visited);
        if (visited.count != 11) return 20;
        if (!visitedType(&visited, "Flag", kCGPDFObjectTypeBoolean)) return 21;
        if (!visitedType(&visited, "Count", kCGPDFObjectTypeInteger)) return 22;
        if (!visitedType(&visited, "Ratio", kCGPDFObjectTypeReal)) return 23;
        if (!visitedType(&visited, "Kind", kCGPDFObjectTypeName)) return 24;
        if (!visitedType(&visited, "Title", kCGPDFObjectTypeString)) return 25;
        if (!visitedType(&visited, "List", kCGPDFObjectTypeArray)) return 26;
        if (!visitedType(&visited, "Sub", kCGPDFObjectTypeDictionary)) return 27;
        if (!visitedType(&visited, "Data", kCGPDFObjectTypeStream)) return 28;
        if (!visitedType(&visited, "Nothing", kCGPDFObjectTypeNull)) return 29;
        // A reference to an object that does not exist is a null object.
        if (!visitedType(&visited, "Dangling", kCGPDFObjectTypeNull)) return 30;

        CGPDFObjectRef object = NULL;
        if (!CGPDFDictionaryGetObject(dict, "Dangling", &object) || CGPDFObjectGetType(object) != kCGPDFObjectTypeNull) return 31;
        // (Whether the object is NULL or a null object differs between macOS 26.7.3 and 10.14.4, so no value is read from it.)

        CGPDFArrayRef list = NULL;
        if (!CGPDFDictionaryGetArray(dict, "List", &list)) return 40;
        object = NULL; CGPDFArrayGetObject(list, 9, &object); /* no object is given for it on macOS 26.7.3 */
        if (CGPDFObjectGetType(object) != kCGPDFObjectTypeNull) return 41;

        // Value copy, a NULL pointer as a type test, integer widened to real, mismatches.
        CGPDFInteger integer = 0;
        CGPDFReal real = 0;
        CGPDFStringRef string = NULL;
        if (!CGPDFArrayGetObject(list, 0, &object)) return 50;
        if (CGPDFObjectGetType(object) != kCGPDFObjectTypeInteger) return 51;
        if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeInteger, &integer) || integer != 1) return 52;
        if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeInteger, NULL)) return 53;
        if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeReal, &real) || real != 1.0) return 54;
        string = (CGPDFStringRef)&real;
        if (CGPDFObjectGetValue(object, kCGPDFObjectTypeString, &string) || string != (CGPDFStringRef)&real) return 55;
        if (CGPDFObjectGetValue(object, kCGPDFObjectTypeNull, NULL)) return 56;
        integer = 123;
        if (!CGPDFArrayGetObject(list, 1, &object) || CGPDFObjectGetType(object) != kCGPDFObjectTypeReal) return 57;
        if (CGPDFObjectGetValue(object, kCGPDFObjectTypeInteger, &integer) || integer != 123) return 58;
        if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeReal, &real) || real != 2.5) return 59;
        const char *name = NULL;
        if (!CGPDFArrayGetObject(list, 3, &object) || !CGPDFObjectGetValue(object, kCGPDFObjectTypeName, &name) || strcmp(name, "Nm")) return 60;
        CGPDFBoolean flag = 0;
        if (!CGPDFArrayGetObject(list, 4, &object) || !CGPDFObjectGetValue(object, kCGPDFObjectTypeBoolean, &flag) || flag != 1) return 61;
        CGPDFArrayRef inner = NULL;
        if (!CGPDFArrayGetObject(list, 6, &object) || !CGPDFObjectGetValue(object, kCGPDFObjectTypeArray, &inner) || CGPDFArrayGetCount(inner) != 1) return 62;
        CGPDFDictionaryRef element = NULL;
        if (!CGPDFArrayGetObject(list, 7, &object) || !CGPDFObjectGetValue(object, kCGPDFObjectTypeDictionary, &element) || !element) return 63;
        CGPDFStreamRef stream = NULL;
        if (!CGPDFArrayGetObject(list, 8, &object) || !CGPDFObjectGetValue(object, kCGPDFObjectTypeStream, &stream) || !stream) return 64;

        // The type of a NULL object is null, and no value is given for it.
        CGPDFInteger untouched = 5;
        if (CGPDFObjectGetType(NULL) != kCGPDFObjectTypeNull) return 75;
        if (CGPDFObjectGetValue(NULL, kCGPDFObjectTypeNull, NULL) || CGPDFObjectGetValue(NULL, kCGPDFObjectTypeInteger, &untouched) || untouched != 5) return 76;

        // The values of the cases, as printed by the type on macOS 26.7.3 and 10.14.4.
        if (kCGPDFObjectTypeNull != 1 || kCGPDFObjectTypeBoolean != 2 || kCGPDFObjectTypeInteger != 3 ||
            kCGPDFObjectTypeReal != 4 || kCGPDFObjectTypeName != 5 || kCGPDFObjectTypeString != 6 ||
            kCGPDFObjectTypeArray != 7 || kCGPDFObjectTypeDictionary != 8 || kCGPDFObjectTypeStream != 9 ||
            sizeof(CGPDFObjectType) != 4) return 70;

        // A value is only given for its own type: a stream is not read as a dictionary, nor a dictionary as a stream,
        // and values that are not one of the nine types are refused (same on both Macs).
        CGPDFDictionaryRef asDictionary = NULL;
        if (!CGPDFDictionaryGetObject(dict, "Data", &object) || CGPDFObjectGetValue(object, kCGPDFObjectTypeDictionary, &asDictionary) || asDictionary) return 71;
        CGPDFStreamRef asStream = NULL;
        if (!CGPDFDictionaryGetObject(dict, "Sub", &object) || CGPDFObjectGetValue(object, kCGPDFObjectTypeStream, &asStream) || asStream) return 72;
        if (!CGPDFArrayGetObject(list, 0, &object)) return 73;
        integer = 123;
        if (CGPDFObjectGetValue(object, (CGPDFObjectType)0, &integer) || CGPDFObjectGetValue(object, (CGPDFObjectType)10, &integer) ||
            CGPDFObjectGetValue(object, (CGPDFObjectType)-1, &integer) || integer != 123) return 74;

        CGPDFDocumentRelease(document);
        puts("CGPDF object type and value accessors passed");
    }
    return 0;
}
