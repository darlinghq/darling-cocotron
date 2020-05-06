#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Font_freetype.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2Paint_color.h>

@implementation O2Context (O2BitmapContext)

+ (O2Context *) createWithBytes: (void *) bytes
                          width: (size_t) width
                         height: (size_t) height
               bitsPerComponent: (size_t) bitsPerComponent
                    bytesPerRow: (size_t) bytesPerRow
                     colorSpace: (O2ColorSpaceRef) colorSpace
                     bitmapInfo: (O2BitmapInfo) bitmapInfo
                releaseCallback:
                    (O2BitmapContextReleaseDataCallback) releaseCallback
                    releaseInfo: (void *) releaseInfo {
    return [[O2Context_builtin_FT alloc] initWithBytes: bytes
                                                 width: width
                                                height: height
                                      bitsPerComponent: bitsPerComponent
                                           bytesPerRow: bytesPerRow
                                            colorSpace: colorSpace
                                            bitmapInfo: bitmapInfo
                                       releaseCallback: releaseCallback
                                           releaseInfo: releaseInfo];
}

@end

@implementation O2Context_builtin_FT

- initWithSurface: (O2Surface *) surface flipped: (BOOL) flipped {
    if ([super initWithSurface: surface flipped: flipped] == nil) {
        return nil;
    }

    return self;
}

- (void) dealloc {
    [super dealloc];
}

- (void) establishFontStateInDeviceIfDirty {
    O2GState *gState = O2ContextCurrentGState(self);

    if (gState->_fontIsDirty) {
        O2GStateClearFontIsDirty(gState);
    }
}

static O2Paint *paintFromColor(O2ColorRef color) {
    size_t count = O2ColorGetNumberOfComponents(color);
    const O2Float *components = O2ColorGetComponents(color);

    if (count == 2) {
        return [[O2Paint_color alloc] initWithGray: components[0]
                                             alpha: components[1]
                           surfaceToPaintTransform: O2AffineTransformIdentity];
    }
    if (count == 4) {
        return [[O2Paint_color alloc] initWithRed: components[0]
                                            green: components[1]
                                             blue: components[2]
                                            alpha: components[3]
                          surfaceToPaintTransform: O2AffineTransformIdentity];
    }

    return [[O2Paint_color alloc] initWithGray: 0
                                         alpha: 1
                       surfaceToPaintTransform: O2AffineTransformIdentity];
}

static void applyCoverageToSpan_lRGBA8888_PRE(O2argb8u *dst,
                                              unsigned char *coverageSpan,
                                              O2argb8u *src, int length) {
    int i;

    for (i = 0; i < length; i++, src++, dst++) {
        int coverage = coverageSpan[i];
        int oneMinusCoverage = inverseCoverage(coverage);
        O2argb8u r = *src;
        O2argb8u d = *dst;

        *dst = O2argb8uAdd(O2argb8uMultiplyByCoverage(r, coverage),
                           O2argb8uMultiplyByCoverage(d, oneMinusCoverage));
    }
}

static void renderFreeTypeBitmap(O2Context_builtin_FT *self, O2Surface *surface,
                                 FT_Bitmap *bitmap, NSInteger x, NSInteger y,
                                 O2Paint *paint) {
    // Size of the bitmap.
    NSInteger fullWidth = bitmap->width;
    NSInteger fullHeight = bitmap->rows;

    // What we're going to render, taking clippig into account.
    NSInteger minX = MAX(x, self->_vpx);
    NSInteger maxX = MIN(x + fullWidth, self->_vpx + self->_vpwidth);
    NSInteger minY = MAX(y, self->_vpy);
    NSInteger maxY = MIN(y + fullHeight, self->_vpy + self->_vpheight);

    NSInteger renderWidth = maxX - minX;
    NSInteger renderHeight = maxY - minY;

    if (renderWidth <= 0 || renderHeight <= 0) {
        // Fully clipped.
        return;
    }

    O2argb8u *dstBuffer = __builtin_alloca(renderWidth * sizeof(O2argb8u));
    O2argb8u *srcBuffer = __builtin_alloca(renderWidth * sizeof(O2argb8u));

    for (NSInteger row = 0; row < renderHeight; row++) {
        // Geometry of this row.
        // We're going to change curX & remainingLength as we move along this
        // row.
        NSInteger curX = minX;
        NSInteger curY = minY + row;
        NSInteger remainingLength = renderWidth;

        // We're going to advance these pointers as we move along this row.
        unsigned char *coverage =
            bitmap->buffer + (curY - y) * fullWidth + (curX - x);
        O2argb8u *src = srcBuffer;
        O2argb8u *dst = dstBuffer;

        // Try to get direct access to the surface data.
        O2argb8u *direct =
            surface->_read_argb8u(surface, curX, curY, dst, remainingLength);
        // If that succeeded, write there directly with no temporary buffer.
        if (direct != NULL) {
            dst = direct;
        }

        while (remainingLength > 0) {
            // Read next chunk into src.
            int chunk = O2PaintReadSpan_argb8u_PRE(paint, curX, curY, src,
                                                   remainingLength);

            if (chunk < 0) {
                chunk = -chunk;
                // Skip this much pixels.
            } else {
                self->_blend_argb8u_PRE(src, dst, chunk);

                applyCoverageToSpan_lRGBA8888_PRE(dst, coverage, src, chunk);

                if (direct == NULL) {
                    // When direct is NULL, dst is a temporary buffer, not the
                    // surface itself, so we have to write it out to the surface
                    // explicitly.
                    O2SurfaceWriteSpan_argb8u_PRE(surface, curX, curY, dst,
                                                  chunk);
                }
            }

            coverage += chunk;
            remainingLength -= chunk;
            curX += chunk;
            src += chunk;
            dst += chunk;
        }
    }
}

- (void) showGlyphs: (const O2Glyph *) glyphs
           advances: (const O2Size *) advances
              count: (NSUInteger) count {
    // FIXME: use advances if not NULL

    O2SurfaceLock(_surface);

    O2GState *gState = O2ContextCurrentGState(self);
    O2Paint *paint = paintFromColor(gState->_fillColor);
    O2AffineTransform Trm = O2ContextGetTextRenderingMatrix(self);

    NSPoint point = O2PointApplyAffineTransform(NSMakePoint(0, 0), Trm);

    // Only use the scaling part of the current transform to scale the font size
    O2Float scaleX = sqrt((Trm.a * Trm.a) + (Trm.c * Trm.c));
    O2Float scaleY = sqrt((Trm.b * Trm.b) + (Trm.d * Trm.d));
    O2AffineTransform scalingTransform =
        O2AffineTransformMakeScale(scaleX, scaleY);
    O2Size fontSize = O2SizeApplyAffineTransform(
        O2SizeMake(0, O2GStatePointSize(gState)), scalingTransform);

    [self establishFontStateInDeviceIfDirty];

    O2Font_freetype *font = (O2Font_freetype *) gState->_font;
    FT_Face face = [font face];

    int i;
    FT_Error ftError;

    if (face == NULL) {
        NSLog(@"face is NULL");
        O2SurfaceUnlock(_surface);
        return;
    }

    FT_GlyphSlot slot = face->glyph;

    if ((ftError =
             FT_Set_Char_Size(face, 0, fontSize.height * 64, 72.0, 72.0))) {
        NSLog(@"FT_Set_Char_Size returned %d", ftError);
        O2SurfaceUnlock(_surface);
        return;
    }

    for (i = 0; i < count; i++) {
        ftError = FT_Load_Glyph(face, glyphs[i], FT_LOAD_DEFAULT);
        if (ftError) {
            continue;
        }

        ftError = FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL);
        if (ftError) {
            continue;
        }

        renderFreeTypeBitmap(self, _surface, &slot->bitmap,
                             point.x + slot->bitmap_left,
                             point.y - slot->bitmap_top, paint);

        point.x += slot->advance.x >> 6;
    }

    O2PaintRelease(paint);

    int glyphAdvances[count];
    O2Float unitsPerEm = O2FontGetUnitsPerEm(font);

    O2FontGetGlyphAdvances(font, glyphs, count, glyphAdvances);

    O2Float total = 0;

    for (i = 0; i < count; i++) {
        total += glyphAdvances[i];
    }

    total = (total / O2FontGetUnitsPerEm(font)) * gState->_pointSize;

    O2SurfaceUnlock(_surface);
}

@end
