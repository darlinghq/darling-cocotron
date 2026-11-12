// Copyright (C) 2026 Lubos Dolezel
#import <Onyx2D/O2DataConsumer.h>
#import <Onyx2D/O2Image.h>
#import <stdbool.h>
#import <stdint.h>

typedef struct O2BMPEncoder {
    O2DataConsumerRef _consumer;
} * O2BMPEncoderRef;

O2BMPEncoderRef O2BMPEncoderCreate(O2DataConsumerRef consumer);
void O2BMPEncoderDealloc(O2BMPEncoderRef self);

// Writes the image as a top-down Windows bitmap: 24 bits per pixel (BITMAPINFOHEADER) for an
// image without alpha, 32 bits per pixel with straight alpha (BITMAPV5HEADER, bit fields)
// for an image with an alpha channel.
void O2BMPEncoderWriteImage(O2BMPEncoderRef self, O2ImageRef image,
                            CFDictionaryRef properties);
