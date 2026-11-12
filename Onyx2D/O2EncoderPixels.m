// Copyright (C) 2026 Lubos Dolezel
#import <Onyx2D/O2EncoderPixels.h>
#import <Onyx2D/O2argb8u.h>

uint8_t *O2ImageCreateStraightRGBA8(O2ImageRef image, bool *hasAlpha) {
    size_t width = O2ImageGetWidth(image);
    size_t height = O2ImageGetHeight(image);

    if (width == 0 || height == 0 || width > SIZE_MAX / 4 / height)
        return NULL;

    O2BitmapInfo info = O2ImageGetBitmapInfo(image);
    O2BitmapInfo alphaInfo = info & kO2BitmapAlphaInfoMask;
    bool alpha = !(alphaInfo == kO2ImageAlphaNone ||
                   alphaInfo == kO2ImageAlphaNoneSkipFirst ||
                   alphaInfo == kO2ImageAlphaNoneSkipLast);
    bool premultiplied = alphaInfo == kO2ImageAlphaPremultipliedFirst ||
                         alphaInfo == kO2ImageAlphaPremultipliedLast;

    uint8_t *result = NSZoneMalloc(NULL, width * height * 4);
    O2argb8u *rowBuffer = NSZoneMalloc(NULL, width * sizeof(O2argb8u));

    if (result == NULL || rowBuffer == NULL || image->_read_argb8u == NULL) {
        NSZoneFree(NULL, result);
        NSZoneFree(NULL, rowBuffer);
        return NULL;
    }

    for (size_t y = 0; y < height; y++) {
        O2argb8u *row = image->_read_argb8u(image, 0, (int) y, rowBuffer,
                                            (int) width);
        uint8_t *out = result + y * width * 4;

        if (row == NULL)
            row = rowBuffer;

        for (size_t x = 0; x < width; x++) {
            O2argb8u pixel = row[x];
            unsigned a = alpha ? pixel.a : 255;
            unsigned r = pixel.r, g = pixel.g, b = pixel.b;

            if (premultiplied) {
                if (a == 0) {
                    r = g = b = 0;
                } else if (a != 255) {
                    r = (r * 255 + a / 2) / a;
                    g = (g * 255 + a / 2) / a;
                    b = (b * 255 + a / 2) / a;
                    if (r > 255) r = 255;
                    if (g > 255) g = 255;
                    if (b > 255) b = 255;
                }
            }
            out[x * 4 + 0] = (uint8_t) r;
            out[x * 4 + 1] = (uint8_t) g;
            out[x * 4 + 2] = (uint8_t) b;
            out[x * 4 + 3] = (uint8_t) a;
        }
    }

    NSZoneFree(NULL, rowBuffer);
    if (hasAlpha != NULL)
        *hasAlpha = alpha;
    return result;
}
