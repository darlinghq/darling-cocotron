// Copyright (C) 2026 Lubos Dolezel
#import <Onyx2D/O2DataConsumer.h>
#import <Onyx2D/O2Image.h>
#import <stdbool.h>
#import <stdint.h>

typedef struct O2GIFEncoder {
    O2DataConsumerRef _consumer;
} * O2GIFEncoderRef;

O2GIFEncoderRef O2GIFEncoderCreate(O2DataConsumerRef consumer);
void O2GIFEncoderDealloc(O2GIFEncoderRef self);

// Writes the image as a single-frame GIF with a global palette. The palette holds the
// image's colors when there are at most 256 (padded to a power of two), otherwise a
// median-cut selection. Pixels with alpha below 64 become one transparent index.
void O2GIFEncoderWriteImage(O2GIFEncoderRef self, O2ImageRef image,
                            CFDictionaryRef properties);
