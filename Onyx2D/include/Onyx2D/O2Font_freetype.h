#import <Onyx2D/O2Defines_FreeType.h>
#import <Onyx2D/O2Font.h>

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

@interface O2Font_freetype : O2Font {
    FT_Face _face;
    FT_Encoding _ftEncoding;
    O2Encoding *_macRomanEncoding;
    O2Encoding *_macExpertEncoding;
    O2Encoding *_winAnsiEncoding;
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

// Returns an owned font covering all supplied Unicode scalar values, or nil.
O2FontRef O2FontCreateWithCodePointCoverage(const uint32_t *codePoints,
                                           size_t count);

@end

#endif
