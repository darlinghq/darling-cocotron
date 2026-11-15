// Copyright (C) 2026 Lubos Dolezel
//
// The {GPS} dictionary of a JPEG as ImageIO presents it: labels equal to the
// kCGImagePropertyGPS* strings, coordinates and other rationals as doubles,
// TimeStamp as "HH:MM:SS", AltitudeRef as an integer, GPSVersion as an array.
// Expected values were observed on macOS 26.7.3 with the same hand-built files
// (see the QUIRK comment in O2EXIFDecoder.m). The key strings are written out
// so the test does not depend on the ImageIO constants.
#include <ImageIO/ImageIO.h>
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

typedef struct {
    int tag, type, count, size;
    unsigned char bytes[32];
} Entry;

static size_t put(unsigned char *out, size_t at, unsigned long value, int bytes) {
    for (int i = bytes - 1; i >= 0; i--)
        out[at++] = (value >> (8 * i)) & 0xff;
    return at;
}

static Entry ascii(int tag, const char *s) {
    Entry e = { tag, 2, (int)strlen(s) + 1, (int)strlen(s) + 1, {0} };
    memcpy(e.bytes, s, e.size);
    return e;
}

static Entry byteValue(int tag, int count, const unsigned char *values) {
    Entry e = { tag, 1, count, count, {0} };
    memcpy(e.bytes, values, count);
    return e;
}

// Rationals given as numerator/denominator pairs.
static Entry rationals(int tag, int count, const unsigned (*pairs)[2]) {
    Entry e = { tag, 5, count, count * 8, {0} };
    for (int i = 0; i < count; i++) {
        put(e.bytes, i * 8, pairs[i][0], 4);
        put(e.bytes, i * 8 + 4, pairs[i][1], 4);
    }
    return e;
}

// An APP1 Exif segment (big-endian) whose IFD0 holds only the GPS IFD pointer.
static size_t makeApp1(const Entry *entries, int n, unsigned char *out) {
    unsigned char *tiff = out + 10;
    size_t at = 0;
    at = put(tiff, at, 0x4d4d, 2);
    at = put(tiff, at, 42, 2);
    at = put(tiff, at, 8, 4);
    at = put(tiff, at, 1, 2);
    at = put(tiff, at, 0x8825, 2);
    at = put(tiff, at, 4, 2);
    at = put(tiff, at, 1, 4);
    at = put(tiff, at, 26, 4);
    at = put(tiff, at, 0, 4);
    at = put(tiff, at, n, 2);
    size_t data = at + n * 12 + 4;
    for (int i = 0; i < n; i++) {
        const Entry *e = &entries[i];
        at = put(tiff, at, e->tag, 2);
        at = put(tiff, at, e->type, 2);
        at = put(tiff, at, e->count, 4);
        if (e->size <= 4) {
            memset(tiff + at, 0, 4);
            memcpy(tiff + at, e->bytes, e->size);
            at += 4;
        } else {
            at = put(tiff, at, data, 4);
            memcpy(tiff + data, e->bytes, e->size);
            data += e->size;
        }
    }
    at = put(tiff, at, 0, 4);
    size_t length = 2 + 6 + data;
    put(out, 0, 0xffe1, 2);
    put(out, 2, length, 2);
    memcpy(out + 4, "Exif\0\0", 6);
    return 2 + length;
}

static CFDictionaryRef gpsOf(CFDataRef jpeg, const Entry *entries, int n, CFDictionaryRef *properties) {
    unsigned char app1[1024];
    size_t length = makeApp1(entries, n, app1);
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CFDataAppendBytes(data, CFDataGetBytePtr(jpeg), 2);
    CFDataAppendBytes(data, app1, length);
    CFDataAppendBytes(data, CFDataGetBytePtr(jpeg) + 2, CFDataGetLength(jpeg) - 2);
    CGImageSourceRef source = CGImageSourceCreateWithData(data, NULL);
    CFRelease(data);
    if (source == NULL)
        return NULL;
    *properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    CFRelease(source);
    return *properties ? CFDictionaryGetValue(*properties, CFSTR("{GPS}")) : NULL;
}

static CFTypeRef at(CFDictionaryRef d, const char *key) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFDictionaryGetValue(d, k);
    CFRelease(k);
    return v;
}

static int isDouble(CFTypeRef v, double expected) {
    double actual;
    return v != NULL && CFGetTypeID(v) == CFNumberGetTypeID() && CFNumberIsFloatType(v) &&
           CFNumberGetByteSize(v) == 8 && CFNumberGetValue(v, kCFNumberDoubleType, &actual) &&
           fabs(actual - expected) < 1e-9;
}

static int isInt(CFTypeRef v, int expected) {
    int actual;
    return v != NULL && CFGetTypeID(v) == CFNumberGetTypeID() && !CFNumberIsFloatType(v) &&
           CFNumberGetValue(v, kCFNumberIntType, &actual) && actual == expected;
}

static int isString(CFTypeRef v, const char *expected) {
    char buffer[32];
    return v != NULL && CFGetTypeID(v) == CFStringGetTypeID() &&
           CFStringGetCString(v, buffer, sizeof buffer, kCFStringEncodingUTF8) && strcmp(buffer, expected) == 0;
}

int main(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 8, 8, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 8, 8));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CFMutableDataRef plain = CFDataCreateMutable(NULL, 0);
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(plain, CFSTR("public.jpeg"), 1, NULL);
    if (destination == NULL) {
        fprintf(stderr, "FAIL: no JPEG destination\n");
        return 1;
    }
    CGImageDestinationAddImage(destination, image, NULL);
    CHECK(CGImageDestinationFinalize(destination), "the JPEG is encoded");
    CFRelease(destination);

    // A full set of tags.
    static const unsigned lat[3][2] = {{33, 1}, {48, 1}, {18, 1}};
    static const unsigned lon[3][2] = {{122, 1}, {15, 1}, {36, 1}};
    static const unsigned alt[1][2] = {{100, 1}};
    static const unsigned time[3][2] = {{1, 1}, {2, 1}, {3, 1}};
    static const unsigned speed[1][2] = {{5, 3}};
    static const unsigned dlat[3][2] = {{10, 1}, {20, 1}, {30, 1}};
    static const unsigned char version[4] = {2, 3, 0, 0};
    static const unsigned char altRef[1] = {1};
    Entry full[] = {
        byteValue(0, 4, version),
        ascii(1, "S"), rationals(2, 3, lat), ascii(3, "W"), rationals(4, 3, lon),
        byteValue(5, 1, altRef), rationals(6, 1, alt), rationals(7, 3, time),
        ascii(8, "SAT"), ascii(9, "A"), rationals(13, 1, speed), ascii(18, "WGS-84"),
        rationals(20, 3, dlat), ascii(29, "2020:01:02"),
    };
    CFDictionaryRef properties = NULL;
    CFDictionaryRef gps = gpsOf(plain, full, sizeof full / sizeof full[0], &properties);
    CHECK(gps != NULL, "the {GPS} dictionary exists");
    if (gps == NULL)
        return 1;
    CHECK(isDouble(at(gps, "Latitude"), 33.805), "Latitude 33 48 18 is 33.805, positive");
    CHECK(isString(at(gps, "LatitudeRef"), "S"), "LatitudeRef");
    CHECK(isDouble(at(gps, "Longitude"), 122.26), "Longitude 122 15 36 is 122.26, positive");
    CHECK(isString(at(gps, "LongitudeRef"), "W"), "LongitudeRef");
    CHECK(isInt(at(gps, "AltitudeRef"), 1), "AltitudeRef is the integer 1");
    CHECK(isDouble(at(gps, "Altitude"), 100), "Altitude is a double");
    CHECK(isString(at(gps, "TimeStamp"), "01:02:03"), "TimeStamp is zero padded HH:MM:SS");
    CHECK(isString(at(gps, "Satellites"), "SAT"), "Satellites");
    CHECK(isString(at(gps, "Status"), "A"), "Status");
    CHECK(isDouble(at(gps, "Speed"), 5.0 / 3.0), "Speed is a double");
    CHECK(isString(at(gps, "MapDatum"), "WGS-84"), "MapDatum");
    CHECK(isDouble(at(gps, "DestLatitude"), 10 + 20.0 / 60 + 30.0 / 3600), "DestLatitude is decimal degrees");
    CHECK(isString(at(gps, "DateStamp"), "2020:01:02"), "DateStamp");
    CFTypeRef v = at(gps, "GPSVersion");
    CHECK(v != NULL && CFGetTypeID(v) == CFArrayGetTypeID() && CFArrayGetCount(v) == 4 &&
          isInt(CFArrayGetValueAtIndex(v, 0), 2) && isInt(CFArrayGetValueAtIndex(v, 1), 3),
          "GPSVersion is an array of four numbers");
    CHECK(at(gps, "GPSLatitude") == NULL && at(gps, "GPSAltitude") == NULL, "the raw tag names are not used");
    CFRelease(properties);

    // A zero denominator reads as 0; the Refs default to N and E when the file has none.
    static const unsigned lat0[3][2] = {{37, 1}, {30, 1}, {7, 0}};
    static const unsigned lon0[3][2] = {{122, 1}, {15, 1}, {0, 1}};
    Entry defaults[] = { rationals(2, 3, lat0), rationals(4, 3, lon0) };
    gps = gpsOf(plain, defaults, 2, &properties);
    CHECK(gps != NULL, "the second {GPS} dictionary exists");
    if (gps != NULL) {
        CHECK(isDouble(at(gps, "Latitude"), 37.5), "a zero denominator component counts as 0");
        CHECK(isDouble(at(gps, "Longitude"), 122.25), "Longitude 122 15 0");
        CHECK(isString(at(gps, "LatitudeRef"), "N"), "LatitudeRef defaults to N");
        CHECK(isString(at(gps, "LongitudeRef"), "E"), "LongitudeRef defaults to E");
        CFRelease(properties);
    }

    // A Latitude that does not have three rationals is dropped, and then so is the default Ref.
    static const unsigned lat1[1][2] = {{40, 1}};
    static const unsigned alt0[1][2] = {{100, 0}};
    Entry dropped[] = { rationals(2, 1, lat1), rationals(6, 1, alt0), byteValue(5, 1, (const unsigned char[]){2}) };
    gps = gpsOf(plain, dropped, 3, &properties);
    CHECK(gps != NULL, "the third {GPS} dictionary exists");
    if (gps != NULL) {
        CHECK(at(gps, "Latitude") == NULL && at(gps, "LatitudeRef") == NULL, "Latitude with one rational is dropped");
        CHECK(isDouble(at(gps, "Altitude"), 0), "Altitude 100/0 is 0");
        CHECK(isInt(at(gps, "AltitudeRef"), 2), "AltitudeRef 2 stays 2");
        CFRelease(properties);
    }

    if (failures == 0)
        printf("PASS: JPEG GPS dictionary labels and values\n");
    return failures ? 1 : 0;
}
