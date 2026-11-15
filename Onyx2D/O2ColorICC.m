/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/


// ICC.1 profile synthesis from the colorimetric parameters of a named space.
// The structure follows the published ICC specification (header, tag table,
// XYZType, curveType, parametricCurveType, textDescriptionType, textType,
// multiLocalizedUnicodeType); the sRGB transfer function parameters are those
// of IEC 61966-2-1. No profile data of any vendor is used.

#include <Onyx2D/O2ColorICC.h>
#include <CoreFoundation/CFString.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned char *bytes;
    size_t length;
    size_t capacity;
} Buffer;

static void put(Buffer *b, const void *data, size_t n) {
    if (b->length + n > b->capacity) {
        size_t cap = b->capacity ? b->capacity * 2 : 1024;
        while (cap < b->length + n)
            cap *= 2;
        b->bytes = realloc(b->bytes, cap);
        b->capacity = cap;
    }
    memcpy(b->bytes + b->length, data, n);
    b->length += n;
}

static void put32(Buffer *b, uint32_t v) {
    unsigned char c[4] = {v >> 24, v >> 16, v >> 8, v};
    put(b, c, 4);
}

static void put16(Buffer *b, uint16_t v) {
    unsigned char c[2] = {v >> 8, v};
    put(b, c, 2);
}

static void putSig(Buffer *b, const char *s) {
    put(b, s, 4);
}

static void pad4(Buffer *b) {
    static const unsigned char zero[4] = {0};
    put(b, zero, (4 - (b->length & 3)) & 3);
}

// s15Fixed16Number
static uint32_t fixed(double v) {
    return (uint32_t)(int32_t)lround(v * 65536.0);
}

typedef struct {
    char sig[4];
    size_t offset;
    size_t size;
} TagEntry;

typedef struct {
    Buffer data; // tag data, offsets relative to the start of the data area
    TagEntry tags[16];
    int count;
} Tags;

static void beginTag(Tags *t, const char *sig, size_t *start) {
    pad4(&t->data);
    *start = t->data.length;
    memcpy(t->tags[t->count].sig, sig, 4);
    t->tags[t->count].offset = *start;
}

static void endTag(Tags *t, size_t start) {
    t->tags[t->count].size = t->data.length - start;
    t->count++;
}

static void addXYZ(Tags *t, const char *sig, double x, double y, double z) {
    size_t s;
    beginTag(t, sig, &s);
    putSig(&t->data, "XYZ ");
    put32(&t->data, 0);
    put32(&t->data, fixed(x));
    put32(&t->data, fixed(y));
    put32(&t->data, fixed(z));
    endTag(t, s);
}

static void addTextV2(Tags *t, const char *sig, const char *text) {
    size_t s;
    beginTag(t, sig, &s);
    putSig(&t->data, "text");
    put32(&t->data, 0);
    put(&t->data, text, strlen(text) + 1);
    endTag(t, s);
}

static void addDescV2(Tags *t, const char *text) {
    size_t s, n = strlen(text) + 1;
    unsigned char zeros[67] = {0};
    beginTag(t, "desc", &s);
    putSig(&t->data, "desc");
    put32(&t->data, 0);
    put32(&t->data, (uint32_t)n);
    put(&t->data, text, n);
    put32(&t->data, 0); // Unicode language code
    put32(&t->data, 0); // Unicode count
    put16(&t->data, 0); // ScriptCode code
    put(&t->data, zeros, 1); // ScriptCode count
    put(&t->data, zeros, 67);
    endTag(t, s);
}

// multiLocalizedUnicodeType with one en-US record (UTF-16BE; ASCII input).
static void addMluc(Tags *t, const char *sig, const char *text) {
    size_t s, n = strlen(text);
    beginTag(t, sig, &s);
    putSig(&t->data, "mluc");
    put32(&t->data, 0);
    put32(&t->data, 1);
    put32(&t->data, 12);
    put(&t->data, "enUS", 4);
    put32(&t->data, (uint32_t)(n * 2));
    put32(&t->data, 28);
    for (size_t i = 0; i < n; i++)
        put16(&t->data, (unsigned char)text[i]);
    endTag(t, s);
}

static bool gammaFitsV2(double gamma) {
    // curveType carries the exponent as u8Fixed8Number.
    double scaled = gamma * 256.0;
    return fabs(scaled - round(scaled)) < 1e-6 && scaled < 65536.0;
}

// Writes the TRC tag(s); the tag table lets several signatures share one
// curve element, which is used for the three RGB curves.
static void addCurve(Tags *t, const char *const *sigs, int nsigs,
                     const O2ColorProfile *p, bool v4) {
    size_t s;
    beginTag(t, sigs[0], &s);
    if (p->transfer == O2ColorTransferSRGB) {
        // parametricCurveType 3: Y = (aX + b)^g for X >= d, cX otherwise,
        // with the IEC 61966-2-1 constants.
        putSig(&t->data, "para");
        put32(&t->data, 0);
        put16(&t->data, 3);
        put16(&t->data, 0);
        put32(&t->data, fixed(2.4));
        put32(&t->data, fixed(1.0 / 1.055));
        put32(&t->data, fixed(0.055 / 1.055));
        put32(&t->data, fixed(1.0 / 12.92));
        put32(&t->data, fixed(0.04045));
    } else {
        double gamma = p->transfer == O2ColorTransferGamma ? p->gamma : 1.0;
        if (v4 && !gammaFitsV2(gamma)) {
            putSig(&t->data, "para");
            put32(&t->data, 0);
            put16(&t->data, 0);
            put16(&t->data, 0);
            put32(&t->data, fixed(gamma));
        } else {
            putSig(&t->data, "curv");
            put32(&t->data, 0);
            put32(&t->data, 1);
            put16(&t->data, (uint16_t)lround(gamma * 256.0));
        }
    }
    endTag(t, s);
    for (int i = 1; i < nsigs; i++) {
        memcpy(t->tags[t->count].sig, sigs[i], 4);
        t->tags[t->count].offset = t->tags[t->count - 1].offset;
        t->tags[t->count].size = t->tags[t->count - 1].size;
        t->count++;
    }
}

CFDataRef O2ColorProfileCopyICCData(const O2ColorProfile *p,
                                    const char *description)
{
    if (p == NULL || description == NULL)
        return NULL;

    double gamma = p->transfer == O2ColorTransferGamma ? p->gamma : 1.0;
    // Version 4 for anything version 2 cannot represent exactly.
    bool v4 = p->transfer == O2ColorTransferSRGB || !gammaFitsV2(gamma);
    if (p->transfer == O2ColorTransferITU709)
        return NULL; // no name uses it; its curve has no exact form here

    Tags t;
    memset(&t, 0, sizeof t);

    if (v4) {
        addMluc(&t, "desc", description);
        addMluc(&t, "cprt", "No copyright, use freely");
    } else {
        addDescV2(&t, description);
        addTextV2(&t, "cprt", "No copyright, use freely");
    }

    // The media white point is the profile connection space white (D50).
    double wx = p->toXYZ[0] + p->toXYZ[1] + p->toXYZ[2];
    double wy = p->toXYZ[3] + p->toXYZ[4] + p->toXYZ[5];
    double wz = p->toXYZ[6] + p->toXYZ[7] + p->toXYZ[8];
    addXYZ(&t, "wtpt", wx, wy, wz);

    if (p->isGray) {
        static const char *const sigs[] = {"kTRC"};
        addCurve(&t, sigs, 1, p, v4);
    } else {
        addXYZ(&t, "rXYZ", p->toXYZ[0], p->toXYZ[3], p->toXYZ[6]);
        addXYZ(&t, "gXYZ", p->toXYZ[1], p->toXYZ[4], p->toXYZ[7]);
        addXYZ(&t, "bXYZ", p->toXYZ[2], p->toXYZ[5], p->toXYZ[8]);
        static const char *const sigs[] = {"rTRC", "gTRC", "bTRC"};
        addCurve(&t, sigs, 3, p, v4);
    }

    size_t tableSize = 4 + 12 * (size_t)t.count;
    size_t dataStart = 128 + tableSize;
    pad4(&t.data);

    Buffer out = {0};
    // Header
    put32(&out, (uint32_t)(dataStart + t.data.length));
    put32(&out, 0);                                  // preferred CMM
    put32(&out, v4 ? 0x04000000 : 0x02100000);       // version 4.0 or 2.1
    putSig(&out, "mntr");                            // display device profile
    putSig(&out, p->isGray ? "GRAY" : "RGB ");
    putSig(&out, "XYZ ");
    put16(&out, 2026); put16(&out, 1); put16(&out, 1);
    put16(&out, 0); put16(&out, 0); put16(&out, 0);  // creation date
    putSig(&out, "acsp");
    put32(&out, 0);                                  // primary platform
    put32(&out, 0);                                  // flags
    put32(&out, 0);                                  // device manufacturer
    put32(&out, 0);                                  // device model
    put32(&out, 0); put32(&out, 0);                  // device attributes
    put32(&out, 0);                                  // rendering intent
    put32(&out, 0x0000F6D6);                         // illuminant D50
    put32(&out, 0x00010000);
    put32(&out, 0x0000D32D);
    put32(&out, 0);                                  // creator
    for (int i = 0; i < 44; i += 4)
        put32(&out, 0);                              // profile ID, reserved

    put32(&out, (uint32_t)t.count);
    for (int i = 0; i < t.count; i++) {
        put(&out, t.tags[i].sig, 4);
        put32(&out, (uint32_t)(dataStart + t.tags[i].offset));
        put32(&out, (uint32_t)t.tags[i].size);
    }
    put(&out, t.data.bytes, t.data.length);

    CFDataRef data = CFDataCreate(NULL, out.bytes, (CFIndex)out.length);
    free(out.bytes);
    free(t.data.bytes);
    return data;
}
