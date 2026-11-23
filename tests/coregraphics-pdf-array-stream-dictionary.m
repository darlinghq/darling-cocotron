// Contract: Apple CoreGraphics documentation for CGPDFArray, CGPDFStream and CGPDFDictionary
// (https://developer.apple.com/documentation/coregraphics). Exit codes identify the failing check.
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
        // a document needs a page to be accepted (observed on macOS 26.7.3)
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] >>"
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
    int count;
    int nullValues;
};

static void visit(const char *key, CGPDFObjectRef value, void *info) {
    struct Visit *visited = info;
    if (visited->count < 16)
        visited->keys[visited->count] = key;
    visited->count++;
    if (!value) visited->nullValues++;
}

static int timesVisited(const struct Visit *visited, const char *key) {
    int seen = 0;
    for (int i = 0; i < visited->count && i < 16; i++)
        if (strcmp(visited->keys[i], key) == 0) seen++;
    return seen;
}

int main(void) {
    @autoreleasepool {
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)documentData());
        CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
        CGDataProviderRelease(provider);
        if (!document) return 10;
        CGPDFDictionaryRef dict = CGPDFDocumentGetInfo(document);
        if (!dict) return 11;

        // Dictionary: count, scalar getters, optional out-pointers, wrong-type and missing keys.
        if (CGPDFDictionaryGetCount(dict) != 11) return 20;
        CGPDFBoolean flag = 0, off = 1;
        if (!CGPDFDictionaryGetBoolean(dict, "Flag", &flag) || flag != 1) return 21;
        if (!CGPDFDictionaryGetBoolean(dict, "Off", &off) || off != 0) return 22;
        if (!CGPDFDictionaryGetBoolean(dict, "Flag", NULL)) return 23;
        CGPDFInteger count = 0;
        if (!CGPDFDictionaryGetInteger(dict, "Count", &count) || count != 7) return 24;
        CGPDFReal real = 0;
        if (!CGPDFDictionaryGetNumber(dict, "Ratio", &real) || real != 2.5) return 26;
        if (!CGPDFDictionaryGetNumber(dict, "Count", &real) || real != 7.0) return 27;
        CGPDFObjectRef object = NULL;
        if (!CGPDFDictionaryGetObject(dict, "Nothing", &object) || !object) return 30;
        if (!CGPDFDictionaryGetObject(dict, "Nothing", NULL)) return 31;
        if (CGPDFDictionaryGetObject(dict, "Missing", &object)) return 32;
        // A failed read leaves the out value as it was.
        count = 123;
        if (CGPDFDictionaryGetInteger(dict, "Ratio", &count) || count != 123) return 33;
        if (CGPDFDictionaryGetInteger(dict, "Missing", &count) || count != 123) return 34;
        flag = 9;
        if (CGPDFDictionaryGetBoolean(dict, "Count", &flag) || flag != 9) return 35;
        real = 55;
        if (CGPDFDictionaryGetNumber(dict, "Kind", &real) || real != 55) return 36;

        // Dictionary: nested containers and a stream reached through an indirect reference.
        CGPDFDictionaryRef sub = NULL;
        if (!CGPDFDictionaryGetDictionary(dict, "Sub", &sub) || !sub || !CGPDFDictionaryGetInteger(sub, "Depth", &count) || count != 1) return 37;
        // What a failed pointer-valued read from a dictionary leaves in the out value is not
        // specified (the system stores NULL), so only the result is checked for those.
        CGPDFDictionaryRef probe = NULL;
        if (CGPDFDictionaryGetDictionary(dict, "List", &probe)) return 38;
        CGPDFArrayRef list = NULL;
        if (!CGPDFDictionaryGetArray(dict, "List", &list) || CGPDFArrayGetCount(list) != 10) return 39;
        CGPDFArrayRef arrayProbe = (CGPDFArrayRef)&sub;
        if (CGPDFDictionaryGetArray(dict, "Sub", &arrayProbe)) return 40;
        CGPDFStreamRef stream = NULL;
        if (!CGPDFDictionaryGetStream(dict, "Data", &stream) || !stream) return 41;
        CGPDFDictionaryRef streamDict = CGPDFStreamGetDictionary(stream);
        if (!streamDict || !CGPDFDictionaryGetInteger(streamDict, "Length", &count) || count != 5) return 42;
        CGPDFStreamRef streamProbe = (CGPDFStreamRef)&sub;
        if (CGPDFDictionaryGetStream(dict, "Sub", &streamProbe)) return 43;

        // Dictionary: a reference to an object that does not exist is still an entry, reads as a
        // NULL object (QUIRK observed on macOS 26.7.3), and is not a value of any type.
        object = (CGPDFObjectRef)&sub;
        if (!CGPDFDictionaryGetObject(dict, "Dangling", &object) || object != NULL) return 44;
        if (CGPDFDictionaryGetInteger(dict, "Dangling", &count) || CGPDFDictionaryGetDictionary(dict, "Dangling", &probe)) return 45;

        // Dictionary: the applier visits every entry once.
        struct Visit visited = {{0}, 0, 0};
        CGPDFDictionaryApplyFunction(dict, visit, &visited);
        if (visited.count != 11) return 50;
        // only the entry that refers to a missing object comes with a NULL value
        if (visited.nullValues != 1) return 52;
        const char *keys[] = {"Title", "Flag", "Off", "Count", "Ratio", "Kind", "List", "Sub", "Data", "Nothing", "Dangling"};
        for (unsigned i = 0; i < 11; i++)
            if (timesVisited(&visited, keys[i]) != 1) return 51;

        // Array: [1 2.5 (s) /Nm true null [3] << /K 1 >> 4 0 R 99 0 R]
        CGPDFInteger integer = 0;
        if (!CGPDFArrayGetInteger(list, 0, &integer) || integer != 1) return 60;
        integer = 123;
        if (CGPDFArrayGetInteger(list, 1, &integer) || integer != 123) return 61;
        if (!CGPDFArrayGetNumber(list, 1, &real) || real != 2.5) return 62;
        if (!CGPDFArrayGetNumber(list, 0, &real) || real != 1.0) return 63;
        CGPDFStringRef string = NULL;
        if (!CGPDFArrayGetString(list, 2, &string) || !string) return 64;
        const char *name = NULL;
        if (!CGPDFArrayGetName(list, 3, &name) || strcmp(name, "Nm")) return 65;
        const char *nameProbe = (const char *)&name;
        if (CGPDFArrayGetName(list, 2, &nameProbe) || nameProbe != (const char *)&name) return 66;
        if (!CGPDFArrayGetBoolean(list, 4, &flag) || flag != 1) return 67;
        flag = 9;
        if (CGPDFArrayGetBoolean(list, 0, &flag) || flag != 9) return 68;
        if (!CGPDFArrayGetNull(list, 5) || CGPDFArrayGetNull(list, 4)) return 69;
        CGPDFArrayRef inner = NULL;
        if (!CGPDFArrayGetArray(list, 6, &inner) || CGPDFArrayGetCount(inner) != 1) return 70;
        if (!CGPDFArrayGetInteger(inner, 0, &integer) || integer != 3) return 71;
        CGPDFDictionaryRef element = NULL;
        if (!CGPDFArrayGetDictionary(list, 7, &element) || !CGPDFDictionaryGetInteger(element, "K", &integer) || integer != 1) return 72;
        if (!CGPDFArrayGetStream(list, 8, &stream) || !CGPDFStreamGetDictionary(stream)) return 73;
        if (CGPDFArrayGetStream(list, 7, &streamProbe) || CGPDFArrayGetArray(list, 0, &arrayProbe)) return 74;
        if (!CGPDFArrayGetObject(list, 2, &object) || !object) return 75;
        if (!CGPDFArrayGetObject(list, 2, NULL)) return 76;
        if (!CGPDFArrayGetNumber(list, 0, NULL) || CGPDFArrayGetBoolean(list, 0, NULL)) return 77;

        // Array: a reference to an object that does not exist gives no object and is not a null
        // (QUIRK observed on macOS 26.7.3).
        object = (CGPDFObjectRef)&sub;
        if (CGPDFArrayGetObject(list, 9, &object) || object != NULL) return 82;
        if (CGPDFArrayGetNull(list, 9)) return 78;
        if (CGPDFArrayGetInteger(list, 9, &integer) || CGPDFArrayGetArray(list, 9, &arrayProbe)) return 79;

        // Array: no element past the end (the documentation leaves this undefined; the answer here is no).
        size_t pastEnd = CGPDFArrayGetCount(list);
        object = NULL;
        if (CGPDFArrayGetObject(list, pastEnd, &object) || object != NULL) return 80;
        integer = 123;
        if (CGPDFArrayGetInteger(list, pastEnd, &integer) || integer != 123 || CGPDFArrayGetNull(list, pastEnd)) return 81;

        CGPDFDocumentRelease(document);
        puts("CGPDF array, stream and dictionary accessors passed");
    }
    return 0;
}
