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

#define O2FONT_GLYPH_CACHE_LIMIT 512

@class O2FreeTypeCachedGlyph;

@interface O2Font_freetype : O2Font {
    FT_Face _face;
    FT_Encoding _ftEncoding;
    O2Encoding *_macRomanEncoding;
    O2Encoding *_macExpertEncoding;
    O2Encoding *_winAnsiEncoding;
    NSMutableDictionary *_glyphCache;
}

- (instancetype) initWithFace: (FT_Face) face;
- (instancetype) initWithDataProvider: (O2DataProviderRef) provider;

- (FT_Face) face;

FT_Face O2FontFreeTypeFace(O2Font_freetype *self);

FT_Library O2FontSharedFreeTypeLibrary();
FcConfig *O2FontSharedFontConfig();

/* Lists the installed faces whose properties equal all of the non-nil
 * arguments; no substitution takes place. Each element is a dictionary
 * with the NSString keys @"family", @"postScriptName", @"style",
 * @"fullName" and @"path" (any of them may be missing). The path is the
 * font file as guest code sees it, not fontconfig's host path. The caller
 * owns the returned array. */
NSArray *O2FontCopyInstalledFaces(NSString *family, NSString *postScriptName,
                                  NSString *style, NSString *fullName);

- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize;

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
