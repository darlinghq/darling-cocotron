#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Font_freetype.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2Paint_color.h>
#include <stdint.h>
#include <stdlib.h>

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
                    releaseInfo: (void *) releaseInfo
{

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
    if ([super initWithSurface: surface flipped: flipped] == nil)
        return nil;

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

    if (count == 2)
        return [[O2Paint_color alloc] initWithGray: components[0]
                                             alpha: components[1]
                           surfaceToPaintTransform: O2AffineTransformIdentity];
    if (count == 4)
        return [[O2Paint_color alloc] initWithRed: components[0]
                                            green: components[1]
                                             blue: components[2]
                                            alpha: components[3]
                          surfaceToPaintTransform: O2AffineTransformIdentity];

    return [[O2Paint_color alloc] initWithGray: 0
                                         alpha: 1
                       surfaceToPaintTransform: O2AffineTransformIdentity];
}

static void applyCoverageToSpan_lRGBA8888_PRE(O2argb8u *dst,
                                              unsigned char *coverageSpan,
                                              O2argb8u *src, int length)
{
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

/* The AppleFontSmoothing default: 0 turns smoothing off, 1 light, 2 medium and
 * 3 strong. Not set means medium, as on macOS. */
static unsigned O2ContextFontSmoothingLevel(void) {
    unsigned level = 2;
    CFPropertyListRef value = CFPreferencesCopyValue(
            CFSTR("AppleFontSmoothing"), kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    if (value != NULL) {
        int number;
        if (CFGetTypeID(value) == CFNumberGetTypeID() &&
            CFNumberGetValue(value, kCFNumberIntType, &number) && number >= 0) {
            level = number > 3 ? 3 : (unsigned) number;
        }
        CFRelease(value);
    }
    return level;
}

static void renderFreeTypeBitmap(O2Context_builtin_FT *self, O2Surface *surface,
                                 FT_Bitmap *bitmap, NSInteger x, NSInteger y,
                                 O2Paint *paint)
{
    if (bitmap == NULL || bitmap->buffer == NULL || surface == NULL || paint == NULL)
        return;

    // Glyphs are blended with the destination, which needs a span reader.
    if (!surface->_read_argb8u)
        return;
    // Size of the bitmap.
    NSInteger fullWidth = bitmap->width;
    NSInteger fullHeight = bitmap->rows;
    NSInteger pitch = bitmap->pitch;

    if (fullWidth <= 0 || fullHeight <= 0 || pitch == 0)
        return;

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
        NSInteger rowInBitmap = curY - y;
        NSInteger rowOffset = (pitch >= 0) ? (rowInBitmap * pitch) : ((fullHeight - 1 - rowInBitmap) * (-pitch));
        unsigned char *coverage = bitmap->buffer + rowOffset + (curX - x);
        O2argb8u *src = srcBuffer;
        O2argb8u *dst = dstBuffer;

        // Try to get direct access to the surface data.
        O2argb8u *direct = surface->_read_argb8u(surface, curX, curY, dst,
                                                 remainingLength);
        // If that succeeded, write there directly with no temporary buffer.
        if (direct != NULL)
            dst = direct;

        while (remainingLength > 0) {
            // Read next chunk into src.
            int chunk = O2PaintReadSpan_argb8u_PRE(paint, curX, curY, src,
                                                   remainingLength);

            if (chunk < 0) {
                chunk = -chunk;
                // Skip this much pixels.
            } else {
                if (self->_blend_argb8u_PRE != NULL) {
                    self->_blend_argb8u_PRE(src, dst, chunk);
                } else {
                    O2BlendSpanNormal_8888(src, dst, chunk);
                }

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
              count: (NSUInteger) count
{
    if (count == 0 || glyphs == NULL)
        return;

    if (_surface == NULL)
        return;

    O2Size *defaultAdvances = NULL;
    if (advances == NULL) {
        if (count > SIZE_MAX / sizeof(*defaultAdvances))
            return;
        defaultAdvances = malloc(count * sizeof(*defaultAdvances));
        if (defaultAdvances == NULL)
            return;
    }

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
    /* FT_Load_Glyph replaces the shared face glyph slot and bitmap.
     * Hold the same font lock used by metric queries through rasterization. */
    @synchronized(font) {
        FT_Face face = [font face];

        NSUInteger i;
        FT_Error ftError;

        if (face == NULL) {
            NSLog(@"face is NULL");
            O2PaintRelease(paint);
            O2SurfaceUnlock(_surface);
            free(defaultAdvances);
            return;
        }

        if ((ftError =
                     FT_Set_Char_Size(face, 0, fontSize.height * 64, 72.0, 72.0))) {
            NSLog(@"FT_Set_Char_Size returned %d", ftError);
            O2PaintRelease(paint);
            O2SurfaceUnlock(_surface);
            free(defaultAdvances);
            return;
        }

        if (advances == NULL)
            O2ContextGetDefaultAdvances(self, glyphs, defaultAdvances, count);

        const O2Size *useAdvances = (advances != NULL) ? advances : defaultAdvances;

        // Text settings of the context and graphics state.
        BOOL antialias = gState->_shouldAntialias && _allowsAntialiasing;
        unsigned smoothing = (antialias && gState->_shouldSmoothFonts && _allowsFontSmoothing)
                ? O2ContextFontSmoothingLevel() : 0;
        BOOL subpixel = _allowsFontSubpixelPositioning && _shouldSubpixelPositionFonts;
        BOOL quantize = _allowsFontSubpixelQuantization && _shouldSubpixelQuantizeFonts;
        NSUInteger steps = O2FreeTypeSubpixelSteps(quantize);

        // Rotation and shear of the text rendering matrix are applied to the
        // glyph outlines; plain scaling is already folded into the size.
        O2FreeTypeGlyphMatrix glyphMatrix = { 0x10000, 0, 0, 0x10000 };
        const O2FreeTypeGlyphMatrix *matrix = NULL;
        O2Float scale = scaleY;
        if (scale > 0 && (fabs(Trm.b) > 1e-6 || fabs(Trm.c) > 1e-6)) {
            // Device y points down while FreeType's y points up; the upright
            // rendering corresponds to a negative d.
            O2Float flip = Trm.d < 0 || (Trm.d == 0 && Trm.b > 0) ? 1 : -1;
            glyphMatrix.xx = (FT_Fixed) lround(Trm.a / scale * 0x10000);
            glyphMatrix.xy = (FT_Fixed) lround(Trm.c / scale * 0x10000);
            glyphMatrix.yx = (FT_Fixed) lround(flip * -Trm.b / scale * 0x10000);
            glyphMatrix.yy = (FT_Fixed) lround(flip * -Trm.d / scale * 0x10000);
            matrix = &glyphMatrix;
        }

        // The blend function left by the last fill may be a plain copy (opaque paint): pick it for this paint.
        O2ContextSetupPaintAndBlendMode(self, paint, gState->_blendMode);

        for (i = 0; i < count; i++) {
            // Glyph origin on the pixel grid plus the fractional offset the
            // bitmap is rendered at; without subpixel positioning the origin
            // is rounded to a whole pixel.
            NSInteger originX;
            unsigned subpixelIndex = 0;
            if (subpixel) {
                O2Float quantized = floor(point.x * steps + 0.5);
                O2Float whole = floor(quantized / steps);
                originX = (NSInteger) whole;
                subpixelIndex = (unsigned) (quantized - whole * steps);
            } else {
                originX = (NSInteger) floor(point.x + 0.5);
            }
            NSInteger originY = (NSInteger) floor(point.y + 0.5);

            O2FreeTypeCachedGlyph *cached =
                    [font rasterizeGlyph: glyphs[i]
                               pointSize: fontSize.height
                                  matrix: matrix
                                 options: antialias ? O2FreeTypeGlyphAntialiased : 0
                               smoothing: smoothing
                           subpixelIndex: subpixelIndex
                           subpixelSteps: (unsigned) steps];

            if (cached != nil)
                renderFreeTypeBitmap(self, _surface, &cached->bitmap,
                                     originX + cached->left,
                                     originY - cached->top, paint);

            if (advances != NULL) {
                // Advances are in text space, so only the linear part of Trm
                // applies; that is also what carries the device y-flip.
                O2Size step = O2SizeApplyAffineTransform(advances[i], Trm);

                point.x += step.width;
                point.y += step.height;
            } else {
                // The same unhinted fractional advances that the text matrix
                // update below applies, so chained runs do not drift.
                O2Size step = O2SizeApplyAffineTransform(defaultAdvances[i], Trm);

                point.x += step.width;
                point.y += step.height;
            }
        }

        O2ContextSetPaint(self, nil);
        O2PaintRelease(paint);
        O2ContextConcatAdvancesToTextMatrix(self, useAdvances, count);
        free(defaultAdvances);

    } /* font lock */
    O2SurfaceUnlock(_surface);
}

@end
