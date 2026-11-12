// Copyright (C) 2026 Lubos Dolezel
#import <Onyx2D/O2Encoder_GIF.h>
#import <Onyx2D/O2EncoderPixels.h>
#import <stdint.h>
#import <string.h>

O2GIFEncoderRef O2GIFEncoderCreate(O2DataConsumerRef consumer) {
    O2GIFEncoderRef self = NSZoneCalloc(NULL, 1, sizeof(struct O2GIFEncoder));
    self->_consumer = (id) CFRetain(consumer);
    return self;
}

void O2GIFEncoderDealloc(O2GIFEncoderRef self) {
    if (self->_consumer != NULL)
        CFRelease(self->_consumer);
    NSZoneFree(NULL, self);
}

enum { kMaxColors = 256, kTransparentAlphaBelow = 64 };

// ---- palette selection ----

typedef struct {
    uint8_t r, g, b;
} GIFColor;

typedef struct {
    uint32_t count;
    uint32_t sum[3];
} GIFBin;

typedef struct {
    int first, count; // range in the sorted list of used bins
} GIFBox;

static inline int binIndex(const uint8_t *rgb) {
    return ((rgb[0] >> 3) << 10) | ((rgb[1] >> 3) << 5) | (rgb[2] >> 3);
}

static int compareKeys(const void *a, const void *b) {
    uint32_t ka = *(const uint32_t *) a, kb = *(const uint32_t *) b;
    return (ka > kb) - (ka < kb);
}

// Sorts the bin indexes of a box by one color channel: each is turned into a key holding
// the channel value above the 15-bit bin index, sorted and turned back.
static void sortBinsByChannel(int *bins, int count, int channel) {
    uint32_t *keys = NSZoneMalloc(NULL, count * sizeof(uint32_t));
    if (keys == NULL)
        return;
    for (int i = 0; i < count; i++)
        keys[i] = ((uint32_t) ((bins[i] >> (10 - 5 * channel)) & 31) << 15) |
                  (uint32_t) bins[i];
    qsort(keys, count, sizeof(uint32_t), compareKeys);
    for (int i = 0; i < count; i++)
        bins[i] = (int) (keys[i] & 0x7FFF);
    NSZoneFree(NULL, keys);
}

// Picks up to maxColors representative colors with median cut over a 5-bits-per-channel
// histogram of the opaque pixels. Returns the number of palette entries written.
static int medianCut(const uint8_t *rgba, size_t pixelCount, int maxColors,
                     GIFColor *palette)
{
    GIFBin *bins = NSZoneCalloc(NULL, 32768, sizeof(GIFBin));
    int *used = NSZoneMalloc(NULL, 32768 * sizeof(int));
    int usedCount = 0;

    if (bins == NULL || used == NULL) {
        NSZoneFree(NULL, bins);
        NSZoneFree(NULL, used);
        return 0;
    }

    for (size_t i = 0; i < pixelCount; i++) {
        const uint8_t *p = rgba + i * 4;
        if (p[3] < kTransparentAlphaBelow)
            continue;
        int index = binIndex(p);
        if (bins[index].count == 0)
            used[usedCount++] = index;
        bins[index].count++;
        bins[index].sum[0] += p[0];
        bins[index].sum[1] += p[1];
        bins[index].sum[2] += p[2];
    }

    GIFBox boxes[kMaxColors];
    int boxCount = 1;
    boxes[0].first = 0;
    boxes[0].count = usedCount;

    while (boxCount < maxColors) {
        // Split the box with the widest channel range that has more than one bin.
        int best = -1, bestChannel = 0, bestRange = 0;
        for (int b = 0; b < boxCount; b++) {
            if (boxes[b].count < 2)
                continue;
            int lo[3] = {31, 31, 31}, hi[3] = {0, 0, 0};
            for (int i = 0; i < boxes[b].count; i++) {
                int index = used[boxes[b].first + i];
                for (int c = 0; c < 3; c++) {
                    int v = (index >> (10 - 5 * c)) & 31;
                    if (v < lo[c]) lo[c] = v;
                    if (v > hi[c]) hi[c] = v;
                }
            }
            for (int c = 0; c < 3; c++) {
                if (hi[c] - lo[c] > bestRange) {
                    bestRange = hi[c] - lo[c];
                    best = b;
                    bestChannel = c;
                }
            }
        }
        if (best < 0)
            break;

        sortBinsByChannel(used + boxes[best].first, boxes[best].count,
                          bestChannel);

        // Cut where half of the pixels lie on each side.
        uint64_t total = 0, running = 0;
        for (int i = 0; i < boxes[best].count; i++)
            total += bins[used[boxes[best].first + i]].count;
        int cut = 1;
        for (int i = 0; i < boxes[best].count - 1; i++) {
            running += bins[used[boxes[best].first + i]].count;
            cut = i + 1;
            if (running * 2 >= total)
                break;
        }
        boxes[boxCount].first = boxes[best].first + cut;
        boxes[boxCount].count = boxes[best].count - cut;
        boxes[best].count = cut;
        boxCount++;
    }

    for (int b = 0; b < boxCount; b++) {
        uint64_t sum[3] = {0, 0, 0}, total = 0;
        for (int i = 0; i < boxes[b].count; i++) {
            GIFBin *bin = &bins[used[boxes[b].first + i]];
            total += bin->count;
            for (int c = 0; c < 3; c++)
                sum[c] += bin->sum[c];
        }
        if (total == 0)
            total = 1;
        palette[b].r = (uint8_t) (sum[0] / total);
        palette[b].g = (uint8_t) (sum[1] / total);
        palette[b].b = (uint8_t) (sum[2] / total);
    }

    NSZoneFree(NULL, bins);
    NSZoneFree(NULL, used);
    return boxCount;
}

static int nearestColor(const GIFColor *palette, int count, const uint8_t *rgb) {
    int best = 0;
    int bestDistance = INT32_MAX;

    for (int i = 0; i < count; i++) {
        int dr = (int) palette[i].r - rgb[0];
        int dg = (int) palette[i].g - rgb[1];
        int db = (int) palette[i].b - rgb[2];
        int distance = dr * dr + dg * dg + db * db;
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

// ---- LZW ----

typedef struct {
    O2DataConsumerRef consumer;
    uint8_t block[255];
    int blockLength;
    uint32_t bits;
    int bitCount;
} GIFWriter;

static void flushBlock(GIFWriter *w) {
    if (w->blockLength > 0) {
        uint8_t length = (uint8_t) w->blockLength;
        O2DataConsumerPutBytes(w->consumer, &length, 1);
        O2DataConsumerPutBytes(w->consumer, w->block, w->blockLength);
        w->blockLength = 0;
    }
}

static void putCode(GIFWriter *w, int code, int size) {
    w->bits |= (uint32_t) code << w->bitCount;
    w->bitCount += size;
    while (w->bitCount >= 8) {
        w->block[w->blockLength++] = (uint8_t) w->bits;
        w->bits >>= 8;
        w->bitCount -= 8;
        if (w->blockLength == 255)
            flushBlock(w);
    }
}

enum { kHashSize = 8209 };

static void lzwEncode(GIFWriter *w, const uint8_t *indexes, size_t count,
                      int minCodeSize)
{
    uint32_t *keys = NSZoneMalloc(NULL, kHashSize * sizeof(uint32_t));
    uint16_t *values = NSZoneMalloc(NULL, kHashSize * sizeof(uint16_t));
    const int clear = 1 << minCodeSize, end = clear + 1;
    int next = end + 1, size = minCodeSize + 1;

    if (keys == NULL || values == NULL) {
        NSZoneFree(NULL, keys);
        NSZoneFree(NULL, values);
        return;
    }
    memset(keys, 0xFF, kHashSize * sizeof(uint32_t));

    putCode(w, clear, size);
    int prefix = indexes[0];

    for (size_t i = 1; i < count; i++) {
        int k = indexes[i];
        uint32_t key = ((uint32_t) prefix << 8) | (uint32_t) k;
        uint32_t slot = (key * 2654435761u) % kHashSize;

        while (keys[slot] != 0xFFFFFFFFu && keys[slot] != key)
            slot = (slot + 1) % kHashSize;

        if (keys[slot] == key) {
            prefix = values[slot];
            continue;
        }

        putCode(w, prefix, size);
        if (next < 4096) {
            keys[slot] = key;
            values[slot] = (uint16_t) next;
            if (next == (1 << size))
                size++;
            next++;
        } else {
            putCode(w, clear, size);
            memset(keys, 0xFF, kHashSize * sizeof(uint32_t));
            next = end + 1;
            size = minCodeSize + 1;
        }
        prefix = k;
    }

    putCode(w, prefix, size);
    if (next < 4096 && next == (1 << size))
        size++;
    putCode(w, end, size);
    if (w->bitCount > 0)
        putCode(w, 0, 8 - w->bitCount);
    flushBlock(w);

    NSZoneFree(NULL, keys);
    NSZoneFree(NULL, values);
}

static void put16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t) v;
    p[1] = (uint8_t) (v >> 8);
}

void O2GIFEncoderWriteImage(O2GIFEncoderRef self, O2ImageRef image,
                            CFDictionaryRef properties)
{
    size_t width = O2ImageGetWidth(image);
    size_t height = O2ImageGetHeight(image);
    bool hasAlpha = false;
    uint8_t *rgba = O2ImageCreateStraightRGBA8(image, &hasAlpha);

    if (rgba == NULL || width > 0xFFFF || height > 0xFFFF) {
        NSZoneFree(NULL, rgba);
        return;
    }

    size_t pixelCount = width * height;
    bool transparent = false;
    if (hasAlpha) {
        for (size_t i = 0; i < pixelCount; i++) {
            if (rgba[i * 4 + 3] < kTransparentAlphaBelow) {
                transparent = true;
                break;
            }
        }
    }
    int maxColors = kMaxColors - (transparent ? 1 : 0);

    // Collect the distinct colors, giving up beyond what the palette can hold.
    GIFColor palette[kMaxColors];
    int paletteCount = 0;
    bool exact = true;
    const uint8_t *previous = NULL;
    for (size_t i = 0; i < pixelCount && exact; i++) {
        const uint8_t *p = rgba + i * 4;
        if (p[3] < kTransparentAlphaBelow)
            continue;
        if (previous != NULL && previous[0] == p[0] && previous[1] == p[1] &&
            previous[2] == p[2])
            continue;
        previous = p;
        int j;
        for (j = 0; j < paletteCount; j++) {
            if (palette[j].r == p[0] && palette[j].g == p[1] &&
                palette[j].b == p[2])
                break;
        }
        if (j == paletteCount) {
            if (paletteCount == maxColors)
                exact = false;
            else {
                palette[paletteCount].r = p[0];
                palette[paletteCount].g = p[1];
                palette[paletteCount].b = p[2];
                paletteCount++;
            }
        }
    }
    if (!exact)
        paletteCount = medianCut(rgba, pixelCount, maxColors, palette);

    int transparentIndex = -1;
    if (transparent)
        transparentIndex = paletteCount++;
    if (paletteCount == 0)
        paletteCount = 1;

    int depth = 1;
    while ((1 << depth) < paletteCount)
        depth++;
    int tableSize = 1 << depth;
    for (int i = paletteCount; i < tableSize; i++)
        palette[i].r = palette[i].g = palette[i].b = 0;
    if (transparent)
        palette[transparentIndex].r = palette[transparentIndex].g =
                palette[transparentIndex].b = 0;

    // Map every pixel to its palette index. Quantized images look the nearest color up
    // once per 5-bit color bin.
    uint8_t *indexes = NSZoneMalloc(NULL, pixelCount);
    int16_t *cache = exact ? NULL : NSZoneMalloc(NULL, 32768 * sizeof(int16_t));
    if (indexes == NULL || (!exact && cache == NULL)) {
        NSZoneFree(NULL, indexes);
        NSZoneFree(NULL, cache);
        NSZoneFree(NULL, rgba);
        return;
    }
    if (cache != NULL)
        memset(cache, 0xFF, 32768 * sizeof(int16_t));
    int colorCount = transparent ? transparentIndex : paletteCount;
    int lastExact = -1;
    const uint8_t *lastPixel = NULL;
    for (size_t i = 0; i < pixelCount; i++) {
        const uint8_t *p = rgba + i * 4;
        if (p[3] < kTransparentAlphaBelow) {
            indexes[i] = (uint8_t) transparentIndex;
        } else if (exact) {
            if (lastPixel != NULL && lastPixel[0] == p[0] &&
                lastPixel[1] == p[1] && lastPixel[2] == p[2]) {
                indexes[i] = (uint8_t) lastExact;
                continue;
            }
            int j = 0;
            while (j < colorCount - 1 && !(palette[j].r == p[0] &&
                                           palette[j].g == p[1] &&
                                           palette[j].b == p[2]))
                j++;
            indexes[i] = (uint8_t) j;
            lastExact = j;
            lastPixel = p;
        } else {
            int bin = binIndex(p);
            if (cache[bin] < 0)
                cache[bin] = (int16_t) nearestColor(palette, colorCount, p);
            indexes[i] = (uint8_t) cache[bin];
        }
    }

    // Header, logical screen descriptor and global color table.
    uint8_t head[13];
    memcpy(head, "GIF87a", 6);
    put16(head + 6, (uint16_t) width);
    put16(head + 8, (uint16_t) height);
    head[10] = (uint8_t) (0x80 | ((depth - 1) << 4) | (depth - 1));
    head[11] = 0;
    head[12] = 0;
    O2DataConsumerPutBytes(self->_consumer, head, sizeof(head));
    for (int i = 0; i < tableSize; i++) {
        uint8_t entry[3] = {palette[i].r, palette[i].g, palette[i].b};
        O2DataConsumerPutBytes(self->_consumer, entry, 3);
    }

    // Graphic control extension, which carries the transparent index.
    uint8_t control[8] = {0x21, 0xF9, 4, (uint8_t) (transparent ? 1 : 0), 0, 0,
                          (uint8_t) (transparent ? transparentIndex : 0), 0};
    O2DataConsumerPutBytes(self->_consumer, control, sizeof(control));

    // Image descriptor, without local table or interlacing.
    uint8_t descriptor[10] = {0x2C};
    put16(descriptor + 5, (uint16_t) width);
    put16(descriptor + 7, (uint16_t) height);
    O2DataConsumerPutBytes(self->_consumer, descriptor, sizeof(descriptor));

    int minCodeSize = depth < 2 ? 2 : depth;
    uint8_t minCode = (uint8_t) minCodeSize;
    O2DataConsumerPutBytes(self->_consumer, &minCode, 1);

    GIFWriter writer = {0};
    writer.consumer = self->_consumer;
    lzwEncode(&writer, indexes, pixelCount, minCodeSize);

    uint8_t trailer[2] = {0, 0x3B}; // end of image data, end of file
    O2DataConsumerPutBytes(self->_consumer, trailer, sizeof(trailer));

    NSZoneFree(NULL, indexes);
    NSZoneFree(NULL, cache);
    NSZoneFree(NULL, rgba);
}
