// Contract: Apple CoreGraphics documentation pages CGPDFPage.dictionary (C name
// CGPDFPageGetDictionary: the dictionary of a PDF page, optional) and
// CGPDFStreamCopyData (a CFData copy of the stream data, released by the caller, and in
// format the kind of data returned: raw, JPEG encoded or JPEG 2000), plus the
// CGPDFDataFormat constants. The pages do not say which filters are decoded, what a
// NULL argument gives, or when the format is written, so those checks are labelled
// placeholder pins of this implementation. Exit codes identify the failing check.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

extern CGPDFDictionaryRef CGPDFPageGetDictionary(CGPDFPageRef) __attribute__((weak_import));
extern CFDataRef CGPDFStreamCopyData(CGPDFStreamRef, CGPDFDataFormat *) __attribute__((weak_import));

static void appendString(NSMutableData *data, NSString *string) {
    [data appendData:[string dataUsingEncoding:NSASCIIStringEncoding]];
}

// zlib data made of one stored (uncompressed) deflate block, so the fixture needs no compressor.
static NSData *storedZlib(NSData *plain) {
    NSMutableData *out = [NSMutableData data];
    const uint8_t header[] = {0x78, 0x01, 0x01};
    [out appendBytes:header length:sizeof header];
    uint16_t length = (uint16_t)[plain length], inverse = (uint16_t)~length;
    uint8_t sizes[] = {length & 0xff, length >> 8, inverse & 0xff, inverse >> 8};
    [out appendBytes:sizes length:sizeof sizes];
    [out appendData:plain];
    uint32_t a = 1, b = 0;
    const uint8_t *bytes = [plain bytes];
    for (NSUInteger i = 0; i < [plain length]; i++) {
        a = (a + bytes[i]) % 65521;
        b = (b + a) % 65521;
    }
    uint8_t adler[] = {b >> 8, b & 0xff, a >> 8, a & 0xff};
    [out appendBytes:adler length:sizeof adler];
    return out;
}

static NSString *streamObject(NSString *entries, NSData *body) {
    return [NSString stringWithFormat:@"<< %@ /Length %lu >>", entries, (unsigned long)[body length]];
}

static NSData *documentData(NSData *content, NSData *flateBody, NSData *jpegBody, NSData *chainBody) {
    NSMutableData *data = [NSMutableData data];
    appendString(data, @"%PDF-1.4\n");
    // Objects 1 to 3 are plain dictionaries, 4 to 10 streams; each stream is reached from
    // the page dictionary through its own key.
    NSString *plain[] = {
        @"<< /Type /Catalog /Pages 2 0 R >>",
        @"<< /Type /Pages /Kids [3 0 R] /Count 1 /Rotate 90 >>",
        @"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Contents 4 0 R"
        " /Flate 5 0 R /Jpeg 6 0 R /Jpx 7 0 R /Chain 8 0 R /Bad 9 0 R /Mid 10 0 R >>",
    };
    NSArray *streams = @[
        @[streamObject(@"", content), content],
        @[streamObject(@"/Filter /FlateDecode", flateBody), flateBody],
        @[streamObject(@"/Filter /DCTDecode", jpegBody), jpegBody],
        @[streamObject(@"/Filter /JPXDecode", jpegBody), jpegBody],
        @[streamObject(@"/Filter [/FlateDecode /DCTDecode]", chainBody), chainBody],
        @[streamObject(@"/Filter /NoSuchFilter", jpegBody), jpegBody],
        @[streamObject(@"/Filter [/DCTDecode /NoSuchFilter]", jpegBody), jpegBody],
    ];
    NSUInteger offsets[10];
    for (NSUInteger i = 0; i < 10; i++) {
        offsets[i] = [data length];
        appendString(data, [NSString stringWithFormat:@"%lu 0 obj\n", (unsigned long)i + 1]);
        if (i < 3) {
            appendString(data, plain[i]);
        } else {
            NSArray *stream = [streams objectAtIndex:i - 3];
            appendString(data, [stream objectAtIndex:0]);
            appendString(data, @"\nstream\n");
            [data appendData:[stream objectAtIndex:1]];
            appendString(data, @"\nendstream");
        }
        appendString(data, @"\nendobj\n");
    }
    NSUInteger xref = [data length];
    appendString(data, @"xref\n0 11\n0000000000 65535 f \n");
    for (NSUInteger i = 0; i < 10; i++)
        appendString(data, [NSString stringWithFormat:@"%010lu 00000 n \n", (unsigned long)offsets[i]]);
    appendString(data, [NSString stringWithFormat:
        @"trailer\n<< /Size 11 /Root 1 0 R >>\nstartxref\n%lu\n%%%%EOF\n", (unsigned long)xref]);
    return data;
}

static BOOL sameBytes(CFDataRef data, NSData *expected) {
    return data && (NSUInteger)CFDataGetLength(data) == [expected length] &&
        !memcmp(CFDataGetBytePtr(data), [expected bytes], [expected length]);
}

int main(void) {
    @autoreleasepool {
        if (&CGPDFPageGetDictionary == NULL || &CGPDFStreamCopyData == NULL) {
            fputs("CGPDFPageGetDictionary or CGPDFStreamCopyData is absent\n", stderr);
            return 5;
        }
        NSData *content = [@"0 0 1 rg 0 0 10 10 re f" dataUsingEncoding:NSASCIIStringEncoding];
        const char flateBytes[] = "flate payload \x01\x02\xff";
        const char jpegBytes[] = "\xff\xd8\xff\xe0 not a real image";
        const char chainBytes[] = "\xff\xd8 chained image data";
        NSData *flatePlain = [NSData dataWithBytes:flateBytes length:strlen(flateBytes)];
        NSData *jpeg = [NSData dataWithBytes:jpegBytes length:strlen(jpegBytes)];
        NSData *chainPlain = [NSData dataWithBytes:chainBytes length:strlen(chainBytes)];
        NSData *file = documentData(content, storedZlib(flatePlain), jpeg, storedZlib(chainPlain));
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)file);
        CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
        CGDataProviderRelease(provider);
        if (!document) return 10;
        CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
        if (!page) return 11;

        // Format constants: three distinct values, the first being 0 is a placeholder pin.
        if (CGPDFDataFormatRaw == CGPDFDataFormatJPEGEncoded ||
            CGPDFDataFormatRaw == CGPDFDataFormatJPEG2000 ||
            CGPDFDataFormatJPEGEncoded == CGPDFDataFormatJPEG2000) return 12;

        // Page dictionary.
        CGPDFDictionaryRef pageDict = CGPDFPageGetDictionary(page);
        if (!pageDict) return 20;
        const char *name = NULL;
        if (!CGPDFDictionaryGetName(pageDict, "Type", &name) || strcmp(name, "Page") != 0) return 21;
        CGPDFArrayRef mediaBox = NULL;
        if (!CGPDFDictionaryGetArray(pageDict, "MediaBox", &mediaBox) || CGPDFArrayGetCount(mediaBox) != 4) return 22;
        CGPDFDictionaryRef parent = NULL;
        if (!CGPDFDictionaryGetDictionary(pageDict, "Parent", &parent)) return 23;
        if (!CGPDFDictionaryGetName(parent, "Type", &name) || strcmp(name, "Pages") != 0) return 24;
        if (CGPDFPageGetDictionary(page) != pageDict) return 25;
        // Placeholder pin: it holds the page's own entries only. /Rotate is set on the
        // page tree node and is inherited by the page, but is not in the page dictionary.
        CGPDFInteger rotate = 0;
        if (CGPDFDictionaryGetInteger(pageDict, "Rotate", &rotate)) return 27;
        if (!CGPDFDictionaryGetInteger(parent, "Rotate", &rotate) || rotate != 90) return 28;
        // Placeholder pin: a NULL page gives NULL.
        if (CGPDFPageGetDictionary(NULL)) return 26;

        // Stream data: a plain stream is copied as it is, format Raw (placeholder pin).
        CGPDFStreamRef stream = NULL;
        if (!CGPDFDictionaryGetStream(pageDict, "Contents", &stream)) return 30;
        CGPDFDataFormat format = (CGPDFDataFormat)99;
        CFDataRef data = CGPDFStreamCopyData(stream, &format);
        if (!sameBytes(data, content)) return 31;
        if (format != CGPDFDataFormatRaw) return 32;
        CFRelease(data);
        data = CGPDFStreamCopyData(stream, &format);
        if (!sameBytes(data, content)) return 33;
        CFRelease(data);

        // Placeholder pin: a NULL format pointer is accepted.
        data = CGPDFStreamCopyData(stream, NULL);
        if (!sameBytes(data, content)) return 34;
        CFRelease(data);

        // A Flate stream is decoded, format Raw.
        if (!CGPDFDictionaryGetStream(pageDict, "Flate", &stream)) return 40;
        format = (CGPDFDataFormat)99;
        data = CGPDFStreamCopyData(stream, &format);
        if (!sameBytes(data, flatePlain)) return 41;
        if (format != CGPDFDataFormatRaw) return 42;
        CFRelease(data);

        // Observed on macOS 26.7.3 and 10.14.4: an image filter is left applied and reported by format; a
        // Flate filter before it is decoded; a filter name that is not a filter gives NULL and leaves
        // the format as it was.
        if (!CGPDFDictionaryGetStream(pageDict, "Jpeg", &stream)) return 50;
        format = (CGPDFDataFormat)99;
        data = CGPDFStreamCopyData(stream, &format);
        if (!sameBytes(data, jpeg) || format != CGPDFDataFormatJPEGEncoded) return 51;
        CFRelease(data);
        if (!CGPDFDictionaryGetStream(pageDict, "Jpx", &stream)) return 52;
        format = (CGPDFDataFormat)99;
        data = CGPDFStreamCopyData(stream, &format);
        if (!sameBytes(data, jpeg) || format != CGPDFDataFormatJPEG2000) return 53;
        CFRelease(data);
        if (!CGPDFDictionaryGetStream(pageDict, "Chain", &stream)) return 54;
        format = (CGPDFDataFormat)99;
        data = CGPDFStreamCopyData(stream, &format);
        if (!sameBytes(data, chainPlain) || format != CGPDFDataFormatJPEGEncoded) return 55;
        CFRelease(data);
        if (!CGPDFDictionaryGetStream(pageDict, "Bad", &stream)) return 56;
        format = (CGPDFDataFormat)99;
        if (CGPDFStreamCopyData(stream, &format) || format != (CGPDFDataFormat)99) return 57;
        // QUIRK test (see Onyx2D/O2PDFStream.m): an image filter before the end of the chain is not decoded,
        // so the chain [/DCTDecode /NoSuchFilter] gives NULL without reaching the image decoder. macOS also
        // writes the format in that case, which is not pinned here.
        if (!CGPDFDictionaryGetStream(pageDict, "Mid", &stream)) return 58;
        format = (CGPDFDataFormat)99;
        if (CGPDFStreamCopyData(stream, &format)) return 59;

        // Placeholder pin: a NULL stream gives NULL and leaves the format as it was.
        format = (CGPDFDataFormat)99;
        if (CGPDFStreamCopyData(NULL, &format) || format != (CGPDFDataFormat)99) return 60;

        CGPDFDocumentRelease(document);
        puts("CGPDFPageGetDictionary and CGPDFStreamCopyData passed");
    }
    return 0;
}
