#import <Onyx2D/O2Defines_FreeType.h>
#import <Onyx2D/O2Font.h>
#import <Foundation/NSDictionary.h>

#ifdef FREETYPE_PRESENT

#ifdef DARLING
#define __linux__
#endif

#import <ft2build.h>
#import FT_FREETYPE_H
#import FT_RENDER_H

#import <fontconfig/fontconfig.h>

#ifdef DARLING
#undef __linux__
#endif

#define O2FONT_GLYPH_CACHE_LIMIT 2048
#define O2FONT_GLYPH_CACHE_BYTES_LIMIT (4 * 1024 * 1024)

@class O2FreeTypeCachedGlyph;

@interface O2Font_freetype : O2Font {
    FT_Face _face;
    NSData *_faceData;
    FT_Encoding _ftEncoding;
    O2Encoding *_macRomanEncoding;
    O2Encoding *_macExpertEncoding;
    O2Encoding *_winAnsiEncoding;
    NSMutableDictionary *_glyphCache;
    NSUInteger _glyphCacheBytes;
    // Where the face was opened from, so a copy with other variation settings
    // can open its own face: a font file (host path) and face index, or the
    // font data in _faceData.
    NSString *_sourcePath;
    int _sourceFaceIndex;
    // Tag (NSNumber, the four characters as a 32-bit integer) to value
    // (NSNumber) of the variation axes this font was explicitly set to.
    NSDictionary *_variation;
}

- (instancetype) initWithFace: (FT_Face) face;
- (instancetype) initWithDataProvider: (O2DataProviderRef) provider;
- (instancetype) initWithDataProvider: (O2DataProviderRef) provider
                            faceIndex: (int) faceIndex;

- (FT_Face) face;

/* Variable font support (an OpenType fvar table). The axes are described by
 * dictionaries with the keys @"tag" (NSNumber, the four characters as a 32-bit
 * integer), @"minimum", @"maximum", @"default" (NSNumber double), @"name"
 * (NSString, may be missing) and @"hidden" (NSNumber BOOL). Returns nil when
 * the font has no variation axes. The caller owns the result. */
- (NSArray *) copyVariationAxes;

/* The axes explicitly set on this font, tag to value; an empty dictionary for a
 * variable font at its defaults, nil for a font without variation axes. The
 * caller owns the result. */
- (NSDictionary *) copyVariationSettings;

/* An owned font like this one with the given axes (tag to value) set on top of
 * the current settings. Tags that are not axes of the font are ignored. A
 * setting keeps the value it was given; the face uses it clamped to the axis range. Returns nil when the font has no
 * variation axes or cannot be reopened. */
- (O2Font_freetype *) copyWithVariation: (NSDictionary *) variation;

FT_Face O2FontFreeTypeFace(O2Font_freetype *self);

/* An owned font for one face of font data that holds several: a font
 * collection (TrueType/OpenType) or a font suitcase. Returns NULL for an index
 * outside the data or data that is no font. */
O2FontRef O2FontCreateWithDataProviderAndFaceIndex(O2DataProviderRef provider, int faceIndex);

/* How many faces FreeType finds in font data (1 for a plain font file, 0 for
 * data that is no font). */
long O2FontFaceCountOfData(const void *bytes, size_t length);

FT_Library O2FontSharedFreeTypeLibrary();
FcConfig *O2FontSharedFontConfig();
typedef enum {
    O2FontRegistrationSucceeded,
    O2FontRegistrationNotFound,
    O2FontRegistrationUnrecognized,
    O2FontRegistrationAlreadyRegistered,
} O2FontRegistrationResult;

// Adds a font file (or a directory of them) at a guest path to the fonts that
// names resolve to in this process.
O2FontRegistrationResult O2FontRegisterFontFile(NSString *path);

/* Lists the installed faces whose properties equal all of the non-nil
 * arguments; no substitution takes place. Each element is a dictionary
 * with the NSString keys @"family", @"postScriptName", @"style",
 * @"fullName" and @"path" (any of them may be missing), and the NSNumber keys
 * @"symbolicTraits" (CTFontSymbolicTraits bits) and @"weight" (the scale of kCTFontWeightTrait). The path is the
 * font file as guest code sees it, not fontconfig's host path. The caller
 * owns the returned array. */
NSArray *O2FontCopyInstalledFaces(NSString *family, NSString *postScriptName,
                                  NSString *style, NSString *fullName);

/* macOS always has a set of font families (Times, Helvetica, Lucida Grande, ...) that
 * applications name without checking that they exist. When family (compared without regard
 * to case) is one of them and no installed family has that name, returns the installed
 * family that stands in for it, chosen by fontconfig as for any other font name. Returns nil
 * for every other name, including installed families and unknown names. The caller owns the
 * returned string. */
NSString *O2FontCopyInstalledFamilyForStandardFamily(NSString *family);
NSArray *O2FontCopyStandardFamilyNamesWithStandIn(void);

// Returns an owned font covering all supplied Unicode scalar values, or nil. The language (a
// BCP 47 tag such as "zh-Hant-TW", or NULL) is passed on to fontconfig, whose configuration
// decides which faces suit it.
O2FontRef O2FontCreateWithCodePointCoverage(const uint32_t *codePoints,
                                           size_t count, FT_Face baseFace,
                                           const char *language);

/* How a glyph is rendered. The fractional part of the pen position is
 * rendered into the bitmap as one of O2FreeTypeSubpixelSteps(quantized)
 * offsets, so the bitmap's left edge already includes it. */
enum {
    O2FreeTypeGlyphAntialiased = 1, /* 8-bit coverage; otherwise 0 or 255 */
};

typedef struct {
    /* Linear part of the text rendering matrix relative to the upright
     * rendering at the given size, 16.16 as FT_Matrix, y up. Identity
     * for upright text. */
    FT_Fixed xx, xy, yx, yy;
} O2FreeTypeGlyphMatrix;

/* Number of horizontal subpixel offsets a glyph is rendered at. */
NSUInteger O2FreeTypeSubpixelSteps(BOOL quantized);

/* smoothing is the AppleFontSmoothing level 0...3 (0 adds no weight);
 * it has no effect on an aliased glyph. */
- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize
                                     matrix: (const O2FreeTypeGlyphMatrix *) matrix
                                    options: (unsigned) options
                                  smoothing: (unsigned) smoothing
                              subpixelIndex: (unsigned) subpixelIndex
                              subpixelSteps: (unsigned) subpixelSteps;

@end

@interface O2FreeTypeCachedGlyph : NSObject {
@public
    FT_Bitmap bitmap;
    NSInteger left;
    NSInteger top;
    FT_Pos advance;
}

- (instancetype) initWithBitmap: (const FT_Bitmap *) bitmap
                            left: (NSInteger) left
                             top: (NSInteger) top
                         advance: (FT_Pos) advance;

@end

#endif
