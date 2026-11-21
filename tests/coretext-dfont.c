/* Copyright (C) 2026 Lubos Dolezel */
/* A Mac OS X ".dfont" is a resource-fork font suitcase stored in the data
 * fork: a resource file whose 'sfnt' resources are TrueType/OpenType fonts.
 * CoreText and CoreGraphics load every face of it through their public APIs.
 *
 * Usage: coretext-dfont <face1.ttf> <face2.ttf> [<face3.ttf> [<face4.ttf>]]
 * The program wraps the given sfnt files into a suitcase (resource ids 128+,
 * layout per the public "Inside Macintosh: More Macintosh Toolbox", chapter
 * "Resource Manager": header, data, map, type list, reference list), writes it
 * to a temporary file and loads that file:
 *   - CTFontManagerCreateFontDescriptorsFromURL: one descriptor per face;
 *   - CTFontCreateWithFontDescriptor: usable fonts that draw glyphs;
 *   - a truncated suitcase and a non-font file are rejected.
 * The family and style names are compared with those of the plain sfnt files
 * loaded the same way; the PostScript names come from the suitcase's 'FOND'
 * resource (its style mapping table), as on macOS. */
#include <CoreText/CoreText.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void put32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static void put16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v; }

static uint8_t *readFile(const char *path, size_t *length) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *bytes = malloc(size);
    if (fread(bytes, 1, size, f) != (size_t) size) { fclose(f); free(bytes); return NULL; }
    fclose(f);
    *length = size;
    return bytes;
}

/* Appends a resource to the data section; returns its offset from the start
 * of the data section. Each resource is a 32-bit length followed by its bytes. */
static size_t addResource(uint8_t *data, size_t *used, const uint8_t *bytes, size_t length) {
    size_t offset = *used;
    put32(data + offset, length);
    memcpy(data + offset + 4, bytes, length);
    *used += 4 + length;
    return offset;
}

static const char *const styleSuffixes[4] = {"Regular", "Bold", "Italic", "BoldItalic"};

/* Builds the suitcase: a 256 byte header area, the data section, then the
 * map (header copy, type list with the types 'FOND' and 'sfnt', one reference
 * list per type, and the resource names as Pascal strings). One 'FOND'
 * resource, id 128, names the family. Its association table lists the faces
 * (size 0 = scalable, a QuickDraw style code, the id of the face's 'sfnt'), and
 * its style mapping table gives PostScript names: the base name "TestFamily-"
 * plus the suffix of the style (styles 0 to 3: Regular, Bold, Italic, and
 * BoldItalic, which is made of the strings of Bold and Italic; each style
 * names its suffix through a string of string indexes, as in system suitcases). The resource
 * attribute byte is 0x60 (purgeable, locked), as in system suitcases. */
static uint8_t *buildSuitcase(uint8_t **fonts, size_t *lengths, int count, size_t *total) {
    static const char familyName[] = "Test Family";
    static const uint8_t strings[] = {
        11, 'T', 'e', 's', 't', 'F', 'a', 'm', 'i', 'l', 'y', '-',    /* 1: base name */
        1, 6,                                                          /* 2: string 6 */
        1, 7,                                                          /* 3: string 7 */
        1, 8,                                                          /* 4: string 8 */
        2, 7, 8,                                                       /* 5: strings 7 and 8 */
        7, 'R', 'e', 'g', 'u', 'l', 'a', 'r',                          /* 6 */
        4, 'B', 'o', 'l', 'd',                                         /* 7 */
        6, 'I', 't', 'a', 'l', 'i', 'c',                               /* 8 */
    };
    size_t styleOffset = 52 + 2 + 6 * count;
    size_t styleLength = 10 + 48 + 2 + sizeof strings;
    size_t fondLength = styleOffset + styleLength;
    uint8_t *fond = calloc(1, fondLength);
    put16(fond + 2, 128);                            /* family id */
    put32(fond + 24, styleOffset);                   /* style mapping table */
    put16(fond + 52, count - 1);                     /* association table: entries minus one */
    for (int i = 0; i < count; i++) {                /* listed last face first */
        int face = count - 1 - i;
        put16(fond + 54 + 6 * i, 0);                 /* size 0: scalable */
        put16(fond + 54 + 6 * i + 2, face);          /* style code */
        put16(fond + 54 + 6 * i + 4, 129 + face);
    }
    uint8_t *table = fond + styleOffset;
    for (int style = 0; style < 48; style++)
        table[10 + style] = 2 + (style & 3);
    put16(table + 58, 8);
    memcpy(table + 60, strings, sizeof strings);

    size_t dataLength = 4 + fondLength;
    for (int i = 0; i < count; i++) dataLength += 4 + lengths[i];
    size_t typeListOffset = 28;
    size_t refListOffset = 2 + 8 * 2;
    size_t refsLength = 12 * (1 + count);
    size_t nameListOffset = typeListOffset + refListOffset + refsLength;
    size_t namesLength = (1 + sizeof familyName - 1) + count * (1 + strlen("Test Face 0"));
    size_t mapLength = nameListOffset + namesLength;
    size_t dataOffset = 256;
    size_t mapOffset = dataOffset + dataLength;
    uint8_t *file = calloc(1, mapOffset + mapLength);

    put32(file + 0, dataOffset);
    put32(file + 4, mapOffset);
    put32(file + 8, dataLength);
    put32(file + 12, mapLength);

    size_t used = 0;
    uint8_t *data = file + dataOffset;
    size_t fondOffset = addResource(data, &used, fond, fondLength);
    size_t sfntOffsets[4];
    for (int i = 0; i < count; i++) sfntOffsets[i] = addResource(data, &used, fonts[i], lengths[i]);

    uint8_t *map = file + mapOffset;
    memcpy(map, file, 16);                           /* copy of the header */
    put16(map + 24, typeListOffset);
    put16(map + 26, nameListOffset);
    uint8_t *types = map + typeListOffset;
    put16(types, 1);                                 /* number of types minus one */
    memcpy(types + 2, "FOND", 4);
    put16(types + 6, 0);
    put16(types + 8, refListOffset);
    memcpy(types + 10, "sfnt", 4);
    put16(types + 14, count - 1);
    put16(types + 16, refListOffset + 12);
    uint8_t *names = map + nameListOffset;
    size_t namePosition = 0;
    uint8_t *ref = types + refListOffset;
    put16(ref, 128);
    put16(ref + 2, namePosition);
    put32(ref + 4, 0x60000000u | fondOffset);
    names[namePosition++] = sizeof familyName - 1;
    memcpy(names + namePosition, familyName, sizeof familyName - 1);
    namePosition += sizeof familyName - 1;
    for (int i = 0; i < count; i++) {
        ref = types + refListOffset + 12 * (1 + i);
        put16(ref, 129 + i);
        put16(ref + 2, namePosition);
        put32(ref + 4, 0x60000000u | sfntOffsets[i]);
        char name[16];
        snprintf(name, sizeof name, "Test Face %d", i);
        names[namePosition++] = strlen(name);
        memcpy(names + namePosition, name, strlen(name));
        namePosition += strlen(name);
    }
    *total = mapOffset + mapLength;
    free(fond);
    return file;
}

static CFStringRef copyFileAttribute(const char *path, CFStringRef attribute) {
    CFStringRef cfpath = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, cfpath, kCFURLPOSIXPathStyle, false);
    CFArrayRef plain = CTFontManagerCreateFontDescriptorsFromURL(url);
    CFStringRef name = NULL;
    if (plain != NULL && CFArrayGetCount(plain) > 0)
        name = CTFontDescriptorCopyAttribute((CTFontDescriptorRef) CFArrayGetValueAtIndex(plain, 0), attribute);
    if (plain != NULL) CFRelease(plain);
    CFRelease(url);
    CFRelease(cfpath);
    return name;
}

/* Writes the bytes to a temporary file and returns how many descriptors the
 * file yields (-1 for NULL). */
static long descriptorCountOfBytes(const uint8_t *bytes, size_t length) {
    char name[] = "/tmp/coretext-dfont-edge.XXXXXX";
    int fd = mkstemp(name);
    if (fd < 0) return -2;
    if (write(fd, bytes, length) != (ssize_t) length) { close(fd); unlink(name); return -2; }
    close(fd);
    CFStringRef cfpath = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, cfpath, kCFURLPOSIXPathStyle, false);
    CFArrayRef array = CTFontManagerCreateFontDescriptorsFromURL(url);
    long count = array == NULL ? -1 : (long) CFArrayGetCount(array);
    if (array != NULL) CFRelease(array);
    CFRelease(url);
    CFRelease(cfpath);
    unlink(name);
    return count;
}

/* Draws "H" with the font into a small gray bitmap; returns the number of
 * pixels that were painted. */
static int paintedPixels(CTFontRef font) {
    enum { W = 48, H = 48 };
    uint8_t pixels[W * H];
    memset(pixels, 0, sizeof pixels);
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(pixels, W, H, 8, W, gray, kCGImageAlphaNone);
    CGContextSetGrayFillColor(context, 1, 1);
    UniChar character = 'H';
    CGGlyph glyph = 0;
    CTFontGetGlyphsForCharacters(font, &character, &glyph, 1);
    CGPoint origin = CGPointMake(8, 10);
    CTFontDrawGlyphs(font, &glyph, &origin, 1, context);
    int painted = 0;
    for (size_t i = 0; i < sizeof pixels; i++) if (pixels[i] != 0) painted++;
    CGContextRelease(context);
    CGColorSpaceRelease(gray);
    return painted;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc - 1 > 4) {
        fprintf(stderr, "usage: %s face.ttf face.ttf...\n", argv[0]);
        return 2;
    }
    int count = argc - 1;
    uint8_t *fonts[4];
    size_t lengths[4];
    for (int i = 0; i < count; i++) {
        fonts[i] = readFile(argv[i + 1], &lengths[i]);
        if (fonts[i] == NULL) { fprintf(stderr, "cannot read %s\n", argv[i + 1]); return 2; }
    }
    size_t total;
    uint8_t *suitcase = buildSuitcase(fonts, lengths, count, &total);

    char path[] = "/tmp/coretext-dfont.XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd < 0) return 1;
    CHECK(write(fd, suitcase, total) == (ssize_t) total);
    close(fd);

    /* Reference family and style names from the plain files. */
    CFStringRef families[4], styles[4];
    for (int i = 0; i < count; i++) {
        families[i] = copyFileAttribute(argv[i + 1], kCTFontFamilyNameAttribute);
        styles[i] = copyFileAttribute(argv[i + 1], kCTFontStyleNameAttribute);
        CHECK(families[i] != NULL && styles[i] != NULL);
    }

    /* From the file: one descriptor per face, in the order of the family record. The PostScript names come from the
     * style mapping table of the 'FOND' resource, the other names from the 'sfnt' resources. */
    CFStringRef cfpath = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, cfpath, kCFURLPOSIXPathStyle, false);
    CFArrayRef descriptors = CTFontManagerCreateFontDescriptorsFromURL(url);
    CHECK(descriptors != NULL);
    CHECK(descriptors != NULL && CFArrayGetCount(descriptors) == count);
    for (int k = 0; descriptors != NULL && k < count && k < CFArrayGetCount(descriptors); k++) {
        int i = count - 1 - k;                       /* the association table lists the last face first */
        CTFontDescriptorRef d = (CTFontDescriptorRef) CFArrayGetValueAtIndex(descriptors, k);
        char expectedName[64];
        snprintf(expectedName, sizeof expectedName, "TestFamily-%s", styleSuffixes[i]);
        CFStringRef expectedPostScript = CFStringCreateWithCString(NULL, expectedName, kCFStringEncodingUTF8);
        CFStringRef name = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute);
        CHECK(name != NULL && CFEqual(name, expectedPostScript));
        CFRelease(expectedPostScript);
        CFStringRef family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute);
        CHECK(family != NULL && CFEqual(family, families[i]));
        CFStringRef style = CTFontDescriptorCopyAttribute(d, kCTFontStyleNameAttribute);
        CHECK(style != NULL && CFEqual(style, styles[i]));
        CFURLRef fontURL = CTFontDescriptorCopyAttribute(d, kCTFontURLAttribute);
        CHECK(fontURL != NULL && CFEqual(fontURL, url));
        CTFontRef font = CTFontCreateWithFontDescriptor(d, 24, NULL);
        CHECK(font != NULL);
        if (font != NULL) {
            /* The font is that face of the file, not the first one. */
            CFStringRef fontFamily = CTFontCopyFamilyName(font);
            CHECK(fontFamily != NULL && CFEqual(fontFamily, families[i]));
            CHECK(paintedPixels(font) > 20);
            if (fontFamily != NULL) CFRelease(fontFamily);
            CFRelease(font);
        }
        if (name != NULL) CFRelease(name);
        if (family != NULL) CFRelease(family);
        if (style != NULL) CFRelease(style);
        if (fontURL != NULL) CFRelease(fontURL);
    }
    CHECK(descriptors != NULL);

    /* Observed on macOS 26 (and the files shipped with it): suitcases are
     * recognised only when read from a file; from memory they are not fonts.
     * The test does not pin that. */
    /* Edge cases: a truncated suitcase and a file that is no font at all give
     * no descriptors. */
    CHECK(descriptorCountOfBytes(suitcase, 300) <= 0);
    uint8_t garbage[512];
    memset(garbage, 0x5a, sizeof garbage);
    CHECK(descriptorCountOfBytes(garbage, sizeof garbage) <= 0);
    CHECK(descriptorCountOfBytes(suitcase, 0) <= 0);

    unlink(path);
    printf(failures == 0 ? "PASS\n" : "FAILED (%d)\n", failures);
    return failures == 0 ? 0 : 1;
}
