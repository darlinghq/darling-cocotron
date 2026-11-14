#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// PDF 1.5 files whose cross-reference information is a stream (PDF 32000-1
// 7.5.8) and whose objects are stored in object streams (7.5.7) open and draw:
// with an uncompressed cross-reference stream, with one compressed by
// FlateDecode with the PNG Up predictor (7.4.4.4, what PDF producers write),
// and in a hybrid file, whose classic table leaves out the objects listed in
// the cross-reference stream named by the trailer's XRefStm (7.5.8.4). A
// cross-reference section whose Prev names itself does not keep the reader
// looping. The page dictionary is in the object stream: its MediaBox and the
// blue square its content draws show that it was found.
// Exits non-zero on failure.

#define WIDTH 20
#define HEIGHT 30

static int failures;

static void append(CFMutableDataRef data, const char *format, ...) {
    char buffer[1024];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    CFDataAppendBytes(data, (const UInt8 *)buffer, length);
}

// zlib data (RFC 1950) holding `length` bytes in stored deflate blocks (RFC 1951).
static void appendZlibStored(CFMutableDataRef data, const uint8_t *bytes, size_t length) {
    uint8_t header[2] = {0x78, 0x01};
    uint32_t a = 1, b = 0;
    CFDataAppendBytes(data, header, 2);
    size_t done = 0;
    do {
        size_t n = length - done > 65535 ? 65535 : length - done;
        uint8_t block[5] = {done + n == length, n & 0xFF, n >> 8, ~n & 0xFF, (~n >> 8) & 0xFF};
        CFDataAppendBytes(data, block, 5);
        CFDataAppendBytes(data, bytes + done, n);
        done += n;
    } while (done < length);
    for (size_t i = 0; i < length; i++) {
        a = (a + bytes[i]) % 65521;
        b = (b + a) % 65521;
    }
    uint32_t adler = (b << 16) | a;
    uint8_t trailer[4] = {adler >> 24, adler >> 16, adler >> 8, adler};
    CFDataAppendBytes(data, trailer, 4);
}

enum layout { plainStream, predictorStream, hybrid };

// Objects: 1 catalog, 2 pages, 3 page (in object stream 5, with 1 and 2),
// 4 content, 5 the object stream, 6 the cross-reference stream.
static CFDataRef buildPDF(enum layout layout) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    const char *content = "0 0 1 rg 0 0 10 10 re f\n";
    char objects[512], header[64];

    snprintf(objects, sizeof(objects),
             "<< /Type /Catalog /Pages 2 0 R >>\n"
             "<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n"
             "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R >>\n",
             WIDTH, HEIGHT);
    size_t first = strchr(objects, '\n') - objects + 1;
    size_t second = first + (strchr(objects + first, '\n') - (objects + first)) + 1;
    snprintf(header, sizeof(header), "1 0 2 %zu 3 %zu\n", first, second);

    append(data, "%%PDF-1.5\n");
    CFIndex contentOffset = CFDataGetLength(data);
    append(data, "4 0 obj\n<< /Length %zu >>\nstream\n%s\nendstream\nendobj\n", strlen(content), content);
    CFIndex objectStreamOffset = CFDataGetLength(data);
    append(data, "5 0 obj\n<< /Type /ObjStm /N 3 /First %zu /Length %zu >>\nstream\n%s%s\nendstream\nendobj\n",
           strlen(header), strlen(header) + strlen(objects), header, objects);

    // Entries for objects 0-6: W [1 4 2]: type, then offset and generation
    // (type 1) or object stream number and index (type 2).
    uint8_t entries[7][7];
    memset(entries, 0, sizeof(entries));
    entries[0][5] = 0xFF;
    entries[0][6] = 0xFF; // free, generation 65535
    for (int i = 1; i <= 3; i++) {
        entries[i][0] = 2;
        entries[i][4] = 5;
        entries[i][6] = i - 1;
    }
    CFIndex xrefStream = CFDataGetLength(data);
    CFIndex positions[3] = {contentOffset, objectStreamOffset, xrefStream};
    for (int i = 4; i <= 6; i++) {
        entries[i][0] = 1;
        for (int j = 0; j < 4; j++)
            entries[i][1 + j] = positions[i - 4] >> (24 - 8 * j);
    }

    if (layout == predictorStream) {
        // PNG Up: each row is preceded by filter type 2 and holds its
        // difference from the row above.
        uint8_t rows[7][8];
        for (int i = 0; i < 7; i++) {
            rows[i][0] = 2;
            for (int j = 0; j < 7; j++)
                rows[i][1 + j] = entries[i][j] - (i ? entries[i - 1][j] : 0);
        }
        CFMutableDataRef compressed = CFDataCreateMutable(NULL, 0);
        appendZlibStored(compressed, &rows[0][0], sizeof(rows));
        append(data, "6 0 obj\n<< /Type /XRef /Size 7 /W [1 4 2] /Root 1 0 R /Filter /FlateDecode "
                     "/DecodeParms << /Predictor 12 /Columns 7 >> /Length %ld >>\nstream\n",
               (long)CFDataGetLength(compressed));
        CFDataAppendBytes(data, CFDataGetBytePtr(compressed), CFDataGetLength(compressed));
        CFRelease(compressed);
    } else {
        append(data, "6 0 obj\n<< /Type /XRef /Size 7 /W [1 4 2] /Index [0 7] /Root 1 0 R /Length %zu >>\nstream\n",
               sizeof(entries));
        CFDataAppendBytes(data, &entries[0][0], sizeof(entries));
    }
    append(data, "\nendstream\nendobj\n");

    if (layout == hybrid) {
        // The classic table lists only the content and the object stream; a
        // PDF 1.4 reader would see objects 1-3 as free.
        CFIndex table = CFDataGetLength(data);
        append(data, "xref\n0 6\n0000000000 65535 f \n0000000000 65535 f \n0000000000 65535 f \n"
                     "0000000000 65535 f \n%010ld 00000 n \n%010ld 00000 n \n",
               (long)contentOffset, (long)objectStreamOffset);
        append(data, "trailer\n<< /Size 7 /Root 1 0 R /XRefStm %ld >>\nstartxref\n%ld\n%%%%EOF\n",
               (long)xrefStream, (long)table);
    } else
        append(data, "startxref\n%ld\n%%%%EOF\n", (long)xrefStream);
    return data;
}

static CGPDFDocumentRef documentFromData(CFDataRef data) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    return document;
}

static void check(const char *what, enum layout layout) {
    CFDataRef data = buildPDF(layout);
    CGPDFDocumentRef document = documentFromData(data);
    CFRelease(data);
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    if (page == NULL) {
        printf("FAIL: %s: no page\n", what);
        failures++;
        if (document)
            CGPDFDocumentRelease(document);
        return;
    }
    CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    if (box.size.width != WIDTH || box.size.height != HEIGHT) {
        printf("FAIL: %s: MediaBox is %gx%g, expected %dx%d\n", what, box.size.width, box.size.height, WIDTH, HEIGHT);
        failures++;
    }

    unsigned char pixels[WIDTH * HEIGHT * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, WIDTH, HEIGHT, 8, WIDTH * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, WIDTH, HEIGHT));
    CGContextDrawPDFPage(context, page);
    CGContextRelease(context);
    CGPDFDocumentRelease(document);

    const unsigned char *p = pixels + ((HEIGHT - 1 - 5) * WIDTH + 5) * 4;
    if (p[0] > 2 || p[1] > 2 || p[2] < 253) {
        printf("FAIL: %s: the page content was not drawn (pixel %u %u %u)\n", what, p[0], p[1], p[2]);
        failures++;
    }
}

static void timeout(int signal) {
    (void)signal;
    static const char message[] = "FAIL: a Prev that names its own section keeps the reader looping\n";
    write(1, message, sizeof(message) - 1);
    _exit(1);
}

// A classic table whose trailer's Prev names the table itself.
static void checkPrevLoop(void) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CFIndex offsets[4];
    append(data, "%%PDF-1.4\n");
    offsets[0] = CFDataGetLength(data);
    append(data, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[1] = CFDataGetLength(data);
    append(data, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[2] = CFDataGetLength(data);
    append(data, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] >>\nendobj\n", WIDTH, HEIGHT);
    CFIndex xref = CFDataGetLength(data);
    append(data, "xref\n0 4\n0000000000 65535 f \n");
    for (int i = 0; i < 3; i++)
        append(data, "%010ld 00000 n \n", (long)offsets[i]);
    append(data, "trailer\n<< /Size 4 /Root 1 0 R /Prev %ld >>\nstartxref\n%ld\n%%%%EOF\n", (long)xref, (long)xref);

    signal(SIGALRM, timeout);
    alarm(20);
    CGPDFDocumentRef document = documentFromData(data);
    alarm(0);
    CFRelease(data);
    if (document)
        CGPDFDocumentRelease(document);
}

int main(void) {
    // Unbuffered: the time-out ends the process with _exit.
    setvbuf(stdout, NULL, _IONBF, 0);
    check("uncompressed cross-reference stream", plainStream);
    check("cross-reference stream with FlateDecode and the PNG Up predictor", predictorStream);
    check("hybrid file (XRefStm)", hybrid);
    checkPrevLoop();
    if (failures)
        return failures;
    puts("PDF cross-reference streams passed");
    return 0;
}
