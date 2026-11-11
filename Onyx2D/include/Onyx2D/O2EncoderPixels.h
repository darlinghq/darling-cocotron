// Copyright (C) 2026 Lubos Dolezel
#import <Onyx2D/O2Image.h>
#import <stdbool.h>
#import <stdint.h>

// Returns a newly allocated width*height*4 buffer (free with NSZoneFree(NULL, p)) holding the
// image as 8-bit R, G, B, A bytes with straight (not premultiplied) alpha, whatever the
// image's byte order, alpha position and premultiplication. *hasAlpha tells whether the image
// has an alpha channel at all; without one every alpha byte is 255. Returns NULL when the
// image cannot be read or the buffer cannot be allocated.
uint8_t *O2ImageCreateStraightRGBA8(O2ImageRef image, bool *hasAlpha);
