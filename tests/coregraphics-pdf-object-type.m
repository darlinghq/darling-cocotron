// Contract: Apple CoreGraphics documentation for CGPDFObject (CGPDFObjectGetType, CGPDFObjectGetValue) and
// CGPDFObjectType (https://developer.apple.com/documentation/coregraphics). Exit codes identify the failing check.
// Only the case names of CGPDFObjectType are used, never their numeric values.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

static NSData *documentData(void) {
    NSMutableData *data = [NSMutableData dataWithData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
    const char *objects[] = {
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [] /Count 0 >>",
        "<< /Title (Fixture) /Flag true /Off false /Count 7 /Ratio 2.5 /Kind /Fixture"
        " /List [1 2.5 (s) /Nm true null [3] << /K 1 >> 4 0 R 99 0 R]"
        " /Sub << /Depth 1 >> /Data 4 0 R /Nothing null /Dangling 99 0 R >>",
        "<< /Length 5 >>\nstream\nhello\nendstream"
    };
    NSUInteger offsets[4];
    for (NSUInteger i = 0; i < 4; i++) {
        offsets[i] = [data length];
        NSString *object = [NSString stringWithFormat:@"%lu 0 obj\n%s\nendobj\n",
            (unsigned long)i + 1, objects[i]];
        [data appendData:[object dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSUInteger xref = [data length];
    [data appendData:[@"xref\n0 5\n0000000000 65535 f \n" dataUsingEncoding:NSASCIIStringEncoding]];
    for (NSUInteger i = 0; i < 4; i++) {
        NSString *entry = [NSString stringWithFormat:@"%010lu 00000 n \n", (unsigned long)offsets[i]];
        [data appendData:[entry dataUsingEncoding:NSASCIIStringEncoding]];
    }
    NSString *trailer = [NSString stringWithFormat:
        @"trailer\n<< /Size 5 /Root 1 0 R /Info 3 0 R >>\nstartxref\n%lu\n%%%%EOF\n",
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
        if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeNull, NULL)) return 32;

        CGPDFArrayRef list = NULL;
        if (!CGPDFDictionaryGetArray(dict, "List", &list)) return 40;
        if (!CGPDFArrayGetObject(list, 9, &object) || CGPDFObjectGetType(object) != kCGPDFObjectTypeNull) return 41;

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

        CGPDFDocumentRelease(document);
        puts("CGPDF object type and value accessors passed");
    }
    return 0;
}
