#import <Onyx2D/O2Font_freetype.h>
#ifdef FREETYPE_PRESENT
#import <Onyx2D/O2Encoding.h>
#import <string.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>
#import FT_TRUETYPE_TABLES_H

@implementation O2Font_freetype

#ifdef DARLING

O2FontRef O2FontCreateWithFontName_platform(NSString *name) {
    return [[O2Font_freetype alloc] initWithFontName: name];
}

O2FontRef O2FontCreateWithDataProvider_platform(O2DataProviderRef provider) {
    return [[O2Font_freetype alloc] initWithDataProvider: provider];
}

#endif

FT_Library O2FontSharedFreeTypeLibrary() {
    static FT_Library library = NULL;

    if (library == NULL) {
        if (FT_Init_FreeType(&library) != 0) {
            NSLog(@"FT_Init_FreeType failed");
        }
    }

    return library;
}

#ifdef DARLING
// FreeType and fontconfig are host libraries: they take and report host
// paths, while guest code sees the host file system under the vchroot's exit
// directory and its own root at the prefix. libsystem_kernel resolves guest
// paths to host paths; the reverse mapping follows from where the guest root
// resolves to.
extern int __darling_vchroot_expand(const char *path, char *out)
        __attribute__((weak_import));

static const char hostRootInGuest[] = "/Volumes/SystemRoot";

static NSString *hostPathFromGuestPath(NSString *path) {
    char host[PATH_MAX];

    if (path == nil || __darling_vchroot_expand == NULL)
        return path;
    if (__darling_vchroot_expand([path fileSystemRepresentation], host) != 0)
        return path;
    return [NSString stringWithUTF8String: host];
}

static NSString *guestPathFromHostPath(const char *path) {
    static char prefix[PATH_MAX];
    static size_t prefixLength;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        if (__darling_vchroot_expand != NULL &&
            __darling_vchroot_expand("/", prefix) == 0) {
            prefixLength = strlen(prefix);
            while (prefixLength > 0 && prefix[prefixLength - 1] == '/')
                prefix[--prefixLength] = '\0';
        }
    });

    if (prefixLength == 0 || path[0] != '/')
        return [NSString stringWithUTF8String: path];
    if (strncmp(path, prefix, prefixLength) == 0 &&
        (path[prefixLength] == '/' || path[prefixLength] == '\0'))
        return [NSString stringWithUTF8String:
                path[prefixLength] ? path + prefixLength : "/"];
    return [NSString stringWithFormat: @"%s%s", hostRootInGuest, path];
}
#else
static NSString *hostPathFromGuestPath(NSString *path) {
    return path;
}

static NSString *guestPathFromHostPath(const char *path) {
    return [NSString stringWithUTF8String: path];
}
#endif

static void addAppFont(FcConfig *config, NSString *path) {
    path = [[NSBundle mainBundle] pathForResource: path ofType: nil];
    if (path == nil) {
        NSLog(@"Cannot find font %@ in resources", path);
        return;
    }
    BOOL isDirectory;
    [[NSFileManager defaultManager] fileExistsAtPath: path
                                         isDirectory: &isDirectory];
    path = hostPathFromGuestPath(path);
    if (isDirectory) {
        FcConfigAppFontAddDir(config, (const FcChar8 *) [path UTF8String]);
    } else {
        FcConfigAppFontAddFile(config, (const FcChar8 *) [path UTF8String]);
    }
}

FcConfig *O2FontSharedFontConfig() {
    static FcConfig *fontConfig = NULL;

    if (fontConfig == NULL) {
        fontConfig = FcInitLoadConfigAndFonts();

        id appFontsPath = [[NSBundle mainBundle]
                objectForInfoDictionaryKey: @"ATSApplicationFontsPath"];
        if ([appFontsPath isKindOfClass: [NSString class]]) {
            addAppFont(fontConfig, appFontsPath);
        } else if ([appFontsPath isKindOfClass: [NSArray class]]) {
            for (NSString *path in appFontsPath) {
                addAppFont(fontConfig, path);
            }
        }
    }

    return fontConfig;
}

NSArray *O2FontCopyInstalledFaces(NSString *family, NSString *postScriptName,
                                  NSString *style, NSString *fullName)
{
    const char *properties[] = { FC_FAMILY, FC_POSTSCRIPT_NAME, FC_STYLE,
                                 FC_FULLNAME, FC_FILE };
    NSString *keys[] = { @"family", @"postScriptName", @"style", @"fullName",
                         @"path" };
    NSString *values[] = { family, postScriptName, style, fullName };
    const int count = sizeof(properties) / sizeof(properties[0]);

    NSMutableArray *result = [[NSMutableArray alloc] init];
    FcPattern *pattern = FcPatternCreate();
    // Not the variadic FcObjectSetBuild(): fontconfig is a native library,
    // and Darwin and Linux pass variadic arguments differently on arm64.
    FcObjectSet *objects = FcObjectSetCreate();
    if (pattern == NULL || objects == NULL)
        goto out;
    for (int i = 0; i < count; i++)
        FcObjectSetAdd(objects, properties[i]);

    for (int i = 0; i < count - 1; i++) {
        if (values[i] != nil)
            FcPatternAddString(pattern, properties[i],
                               (const FcChar8 *) [values[i] UTF8String]);
    }

    FcFontSet *fonts = FcFontList(O2FontSharedFontConfig(), pattern, objects);
    for (int i = 0; fonts != NULL && i < fonts->nfont; i++) {
        NSMutableDictionary *face = [[NSMutableDictionary alloc] init];
        for (int j = 0; j < count; j++) {
            FcChar8 *text = NULL;
            if (FcPatternGetString(fonts->fonts[i], properties[j], 0, &text) !=
                FcResultMatch)
                continue;
            NSString *value =
                    (strcmp(properties[j], FC_FILE) == 0)
                            ? guestPathFromHostPath((const char *) text)
                            : [NSString stringWithUTF8String: (const char *) text];
            if (value != nil)
                [face setObject: value forKey: keys[j]];
        }
        [result addObject: face];
        [face release];
    }
    if (fonts != NULL)
        FcFontSetDestroy(fonts);

out:
    if (objects != NULL)
        FcObjectSetDestroy(objects);
    if (pattern != NULL)
        FcPatternDestroy(pattern);
    return result;
}

/* fontconfig ranks bitmap faces (the X11 .pcf fonts) above outline fonts for some generic
 * families, and a bitmap face has units_per_EM == 0, so every metric derived from it divides
 * by zero. Return the first scalable face of the sorted set, or the first face if none is. */
static NSString *filenameOfFirstScalableFace(FcFontSet *set) {
    NSString *fallback = nil;
    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *filename = NULL;
        if (FcPatternGetString(set->fonts[i], FC_FILE, 0, &filename) != FcResultMatch) {
            continue;
        }
        NSString *path = [NSString stringWithUTF8String: (char *) filename];
        if (path == nil) {
            continue;
        }
        FcBool scalable = FcTrue; /* left untouched when the pattern has no FC_SCALABLE */
        FcPatternGetBool(set->fonts[i], FC_SCALABLE, 0, &scalable);
        if (scalable) {
            return path;
        }
        if (fallback == nil) {
            fallback = path;
        }
    }
    return fallback;
}

+ (NSString *) filenameForPattern: (NSString *) pattern {
    FcConfig *config = O2FontSharedFontConfig();

    FcPattern *pat = FcNameParse((unsigned char *) [pattern UTF8String]);
    FcConfigSubstitute(config, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    FcResult fcResult;
    FcFontSet *set = FcFontSort(config, pat, FcFalse, NULL, &fcResult);
    FcPatternDestroy(pat);
    if (set == NULL) {
        return nil;
    }

    NSString *res = filenameOfFirstScalableFace(set);
    FcFontSetDestroy(set);
    return res;
}

- (instancetype) initWithDataProvider: (O2DataProviderRef) provider {
    self = [super initWithDataProvider: provider];
    if (self == nil) {
        return nil;
    }

    const void *bytes = [provider bytes];
    size_t length = [provider length];

    FT_Face face;
    int error = FT_New_Memory_Face(O2FontSharedFreeTypeLibrary(), bytes, length,
                                   0, &face);

    if (error != 0) {
        NSLog(@"FT_New_Memory_Face() = %d", error);
        [self release];
        return nil;
    }

    return [self initWithFace: face];
}

- (instancetype) initWithFontName: (NSString *) name {
    self = [super initWithFontName: name];

    NSString *filename = [[self class] filenameForPattern: name];
    if (filename == nil) {
        filename = [[self class] filenameForPattern: @""];
    }
    if (filename == nil) {
        NSLog(@"No font found for name %@", name);
        [self release];
        return nil;
    }

    FT_Face face;
    FT_Error error = FT_New_Face(O2FontSharedFreeTypeLibrary(),
                                 [filename fileSystemRepresentation], 0, &face);

    if (error != 0) {
        NSLog(@"FT_New_Face() = %d", error);
        [self release];
        return nil;
    }

    return [self initWithFace: face];
}

- (instancetype) initWithFace: (FT_Face) face {
    _face = face;
    _platformType = O2FontPlatformTypeFreeType;

    int i, numberOfCharMaps = face->num_charmaps;
    BOOL hasUnicode = FALSE;
    BOOL hasMacRoman = FALSE;

    for (i = 0; i < numberOfCharMaps; i++) {

        if (face->charmaps[i]->encoding == FT_ENCODING_UNICODE) {
            hasUnicode = TRUE;
        }
        if (face->charmaps[i]->encoding == FT_ENCODING_APPLE_ROMAN) {
            hasMacRoman = TRUE;
        }
    }
    if (hasUnicode) {
        _ftEncoding = FT_ENCODING_UNICODE;
    } else if (hasMacRoman) {
        _ftEncoding = FT_ENCODING_APPLE_ROMAN;
    } else {
        _ftEncoding = face->charmaps[0]->encoding;
    }

    if (FT_Select_Charmap(face, _ftEncoding) != 0) {
        NSLog(@"FT_Select_Charmap(%d) failed", _ftEncoding);
    }

    if (!(face->face_flags & FT_FACE_FLAG_SCALABLE)) {
        NSLog(@"FreeType font face %s is not scalable",
              face->family_name != NULL ? face->family_name : "(unknown)");
    }

    // Bitmap-only faces have no design units; keep derived metrics finite.
    _unitsPerEm = face->units_per_EM != 0 ? (O2Float) face->units_per_EM
                                          : 1000.0f;
    _ascent = face->ascender;
    _descent = face->descender;
    _leading = 0;
    _capHeight = face->height;
    _xHeight = face->height;
    _italicAngle = 0;
    _stemV = 0;
    _bbox.origin.x = face->bbox.xMin;
    _bbox.origin.y = face->bbox.yMin;
    _bbox.size.width = face->bbox.xMax - face->bbox.xMin;
    _bbox.size.height = face->bbox.yMax - face->bbox.yMin;
    _numberOfGlyphs = face->num_glyphs;
    _advances = NULL;
    return self;
}

- (void) dealloc {
    FT_Done_Face(_face);
    [_macRomanEncoding release];
    [_macExpertEncoding release];
    [_winAnsiEncoding release];
    [super dealloc];
}

- (FT_Face) face {
    return _face;
}

- (NSString *) copyPostScriptName {
    const char *name = FT_Get_Postscript_Name(_face);
    if (name == NULL)
        return [super copyPostScriptName];
    return [[NSString alloc] initWithUTF8String: name];
}

- (NSString *) copyFamilyName {
    if (_face->family_name == NULL)
        return [super copyFamilyName];
    return [[NSString alloc] initWithUTF8String: _face->family_name];
}

- (NSString *) copyStyleName {
    if (_face->style_name == NULL)
        return [super copyStyleName];
    return [[NSString alloc] initWithUTF8String: _face->style_name];
}

// The face has a single glyph slot, so every FT_Load_Glyph on it is
// serialized on the font object (see O2Context_builtin_FT and KTFont_FT).
- (O2Rect) boundingRectForGlyph: (O2Glyph) glyph {
    @synchronized(self) {
        if (FT_Load_Glyph(_face, glyph,
                          FT_LOAD_NO_SCALE | FT_LOAD_IGNORE_TRANSFORM) != 0)
            return O2RectMake(0, 0, 0, 0);
        FT_Glyph_Metrics metrics = _face->glyph->metrics;
        return O2RectMake(metrics.horiBearingX,
                          metrics.horiBearingY - metrics.height,
                          metrics.width, metrics.height);
    }
}

- (CFArrayRef) copyTableTags {
    FT_ULong count = 0;
    if (!_face || FT_Sfnt_Table_Info(_face, 0, NULL, &count) != 0 ||
        count > UINT_MAX || count > LONG_MAX || count > SIZE_MAX / sizeof(void *))
        return NULL;
    const void **tags = count ? malloc((size_t)count * sizeof(*tags)) : NULL;
    if (count && !tags) return NULL;
    CFIndex used = 0;
    for (FT_UInt index = 0; index < count; ++index) {
        FT_ULong tag = 0, length = 0;
        if (FT_Sfnt_Table_Info(_face, index, &tag, &length) != 0 || tag > UINT32_MAX) {
            free(tags);
            return NULL;
        }
        if (length != 0)
            tags[used++] = (const void *)(uintptr_t)tag;
    }
    CFArrayRef result = CFArrayCreate(kCFAllocatorDefault, tags, used, NULL);
    free(tags);
    return result;
}

- (NSData *) copyTableForTag: (uint32_t) requestedTag {
    FT_ULong count = 0, length = 0;
    if (!_face || FT_Sfnt_Table_Info(_face, 0, NULL, &count) != 0 || count > UINT_MAX)
        return nil;
    for (FT_UInt index = 0; index < count; ++index) {
        FT_ULong tag = 0, tableLength = 0;
        if (FT_Sfnt_Table_Info(_face, index, &tag, &tableLength) != 0)
            return nil;
        if (tag == requestedTag) {
            length = tableLength;
            break;
        }
    }
    if (!length || length > SIZE_MAX || length > NSUIntegerMax || length > LONG_MAX ||
        requestedTag == 0 || requestedTag == 1)
        return nil;
    void *bytes = malloc((size_t)length);
    if (!bytes) return nil;
    FT_ULong loaded = length;
    if (FT_Load_Sfnt_Table(_face, requestedTag, 0, bytes, &loaded) != 0 || loaded != length) {
        free(bytes);
        return nil;
    }
    CFDataRef result = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, bytes,
            (CFIndex)length, kCFAllocatorMalloc);
    if (!result) free(bytes);
    return (NSData *)result;
}

- (NSCharacterSet *) coveredCharacterSet {
    if (_coveredCharSet == nil && _face != NULL) {
        @synchronized(self) {
            if (_coveredCharSet == nil && _face != NULL) {
                CFMutableCharacterSetRef set = CFCharacterSetCreateMutable(kCFAllocatorDefault);
                FT_UInt gindex = 0;
                FT_ULong charcode = FT_Get_First_Char(_face, &gindex);
                FT_ULong rangeStart = 0;
                FT_ULong rangeLength = 0;

                while (gindex != 0) {
                    if (charcode <= 0x10FFFF) {
                        if (rangeLength > 0 && charcode == rangeStart + rangeLength) {
                            rangeLength++;
                        } else {
                            if (rangeLength > 0) {
                                CFCharacterSetAddCharactersInRange(set, CFRangeMake(rangeStart, rangeLength));
                            }
                            rangeStart = charcode;
                            rangeLength = 1;
                        }
                    }
                    charcode = FT_Get_Next_Char(_face, charcode, &gindex);
                }
                if (rangeLength > 0) {
                    CFCharacterSetAddCharactersInRange(set, CFRangeMake(rangeStart, rangeLength));
                }
                _coveredCharSet = (NSCharacterSet *) set;
            }
        }
    }
    return _coveredCharSet;
}

FT_Face O2FontFreeTypeFace(O2Font_freetype *self) {
    return self->_face;
}

- (void) fetchAdvances {
    @synchronized(self) {
        FT_Set_Char_Size(_face, 0, _unitsPerEm * 64, 72, 72);

        _advances = NSZoneMalloc(NULL, sizeof(NSInteger) * _numberOfGlyphs);

        for (O2Glyph glyph = 0; glyph < _numberOfGlyphs; glyph++) {
            FT_Load_Glyph(_face, glyph, FT_LOAD_DEFAULT);

            _advances[glyph] = _face->glyph->advance.x / (O2Float)(2 << 5);
        }
    }
}

- (O2Glyph) glyphWithGlyphName: (NSString *) name {
    return FT_Get_Name_Index(_face, (char *) [name cString]);
}

- (NSString *) copyGlyphNameForGlyph: (O2Glyph) glyph {
    unsigned char buffer[100];
    if (FT_Get_Glyph_Name(_face, glyph, buffer, sizeof(buffer)) != 0) {
        return nil;
    }
    return [[NSString alloc] initWithUTF8String: (const char *) buffer];
}

- (void) getGlyphs: (O2Glyph *) glyphs
        forCodePoints: (uint16_t *) codes
               length: (NSInteger) length
{
    for (int i = 0; i < length; i++) {
        glyphs[i] = FT_Get_Char_Index(_face, codes[i]);
    }
}

- (O2Encoding *) unicode_createEncodingForTextEncoding:
        (O2TextEncoding) encoding
{
    unichar unicode[256];
    O2Glyph glyphs[256];

    switch (encoding) {
    case kO2EncodingFontSpecific:
    case kO2EncodingMacRoman:
        if (_macRomanEncoding == nil) {
            O2EncodingGetMacRomanUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _macRomanEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                           unicode: unicode];
        }
        return [_macRomanEncoding retain];

    case kO2EncodingMacExpert:
        if (_macExpertEncoding == nil) {
            O2EncodingGetMacExpertUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _macExpertEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                            unicode: unicode];
        }
        return [_macExpertEncoding retain];

    case kO2EncodingWinAnsi:
        if (_winAnsiEncoding == nil) {
            O2EncodingGetWinAnsiUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _winAnsiEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                          unicode: unicode];
        }
        return [_winAnsiEncoding retain];

    default:
        return nil;
    }
    return nil;
}

- (O2Encoding *) MacRoman_createEncodingForTextEncoding:
        (O2TextEncoding) encoding
{

    uint16_t codes[256];
    O2Glyph glyphs[256];
    unichar unicode[256];

    if (_macRomanEncoding == nil) {

        if (encoding != kO2EncodingMacRoman &&
            encoding != kO2EncodingFontSpecific) {
            NSLog(@"font encoding is MacRoman, requesting encoding %d failed",
                  encoding);
        }

        for (int i = 0; i < 256; i++) {
            codes[i] = i;
        }

        [self getGlyphs: glyphs forCodePoints: codes length: 256];

        O2EncodingGetMacExpertUnicode(unicode);

        _macRomanEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                       unicode: unicode];
    }

    return [_macRomanEncoding retain];
}

- (O2Encoding *) createEncodingForTextEncoding: (O2TextEncoding) encoding {
    if (_ftEncoding == FT_ENCODING_APPLE_ROMAN) {
        return [self MacRoman_createEncodingForTextEncoding: encoding];
    }

    return [self unicode_createEncodingForTextEncoding: encoding];
}

@end
#endif
