// Copyright (C) 2026 Lubos Dolezel
#import <Onyx2D/O2Encoder_BMP.h>
#import <Onyx2D/O2EncoderPixels.h>

O2BMPEncoderRef O2BMPEncoderCreate(O2DataConsumerRef consumer) {
    O2BMPEncoderRef self = NSZoneCalloc(NULL, 1, sizeof(struct O2BMPEncoder));
    self->_consumer = (id) CFRetain(consumer);
    return self;
}

void O2BMPEncoderDealloc(O2BMPEncoderRef self) {
    if (self->_consumer != NULL)
        CFRelease(self->_consumer);
    NSZoneFree(NULL, self);
}

static void put16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t) v;
    p[1] = (uint8_t) (v >> 8);
}

static void put32(uint8_t *p, uint32_t v) {
    put16(p, (uint16_t) v);
    put16(p + 2, (uint16_t) (v >> 16));
}

void O2BMPEncoderWriteImage(O2BMPEncoderRef self, O2ImageRef image,
                            CFDictionaryRef properties)
{
    size_t width = O2ImageGetWidth(image);
    size_t height = O2ImageGetHeight(image);
    bool hasAlpha = false;
    uint8_t *rgba = O2ImageCreateStraightRGBA8(image, &hasAlpha);

    if (rgba == NULL)
        return;

    // 24-bit rows are padded to a multiple of four bytes.
    size_t bytesPerPixel = hasAlpha ? 4 : 3;
    size_t rowBytes = (width * bytesPerPixel + 3) & ~(size_t) 3;
    size_t headerSize = hasAlpha ? 124 : 40;
    size_t offset = 14 + headerSize;

    if (width > INT32_MAX || height > INT32_MAX ||
        rowBytes > (UINT32_MAX - offset) / height)
    {
        NSZoneFree(NULL, rgba);
        return;
    }

    size_t total = offset + rowBytes * height;
    uint8_t *file = NSZoneCalloc(NULL, 1, total);

    if (file == NULL) {
        NSZoneFree(NULL, rgba);
        return;
    }

    file[0] = 'B';
    file[1] = 'M';
    put32(file + 2, (uint32_t) total);
    put32(file + 10, (uint32_t) offset);

    uint8_t *dib = file + 14;
    put32(dib + 0, (uint32_t) headerSize);
    put32(dib + 4, (uint32_t) width);
    put32(dib + 8, (uint32_t) -(int32_t) height); // negative: top-down rows
    put16(dib + 12, 1);
    put16(dib + 14, hasAlpha ? 32 : 24);
    // The size field of the pixel data counts unpadded rows.
    put32(dib + 20, (uint32_t) (width * height * bytesPerPixel));
    if (hasAlpha) {
        put32(dib + 16, 3); // BI_BITFIELDS: the masks below
        put32(dib + 40, 0x00FF0000);
        put32(dib + 44, 0x0000FF00);
        put32(dib + 48, 0x000000FF);
        put32(dib + 52, 0xFF000000);
        put32(dib + 56, 0x73524742); // LCS_sRGB
    }

    for (size_t y = 0; y < height; y++) {
        const uint8_t *in = rgba + y * width * 4;
        uint8_t *out = file + offset + y * rowBytes;

        for (size_t x = 0; x < width; x++) {
            out[x * bytesPerPixel + 0] = in[x * 4 + 2];
            out[x * bytesPerPixel + 1] = in[x * 4 + 1];
            out[x * bytesPerPixel + 2] = in[x * 4 + 0];
            if (hasAlpha)
                out[x * bytesPerPixel + 3] = in[x * 4 + 3];
        }
    }

    O2DataConsumerPutBytes(self->_consumer, file, total);
    NSZoneFree(NULL, file);
    NSZoneFree(NULL, rgba);
}
