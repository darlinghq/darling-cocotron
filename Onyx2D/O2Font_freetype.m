#import <Onyx2D/O2Font_freetype.h>
#ifdef FREETYPE_PRESENT
#import <Onyx2D/O2Encoding.h>

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

static void addAppFont(FcConfig *config, NSString *path) {
    path = [[NSBundle mainBundle] pathForResource: path ofType: nil];
    if (path == nil) {
        NSLog(@"Cannot find font %@ in resources", path);
        return;
    }
    BOOL isDirectory;
    [[NSFileManager defaultManager] fileExistsAtPath: path
                                         isDirectory: &isDirectory];
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

+ (NSString *) filenameForPattern: (NSString *) pattern {
    FcConfig *config = O2FontSharedFontConfig();

    FcPattern *pat = FcNameParse((unsigned char *) [pattern UTF8String]);
    FcConfigSubstitute(config, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    FcResult fcResult;
    FcPattern *match = FcFontMatch(config, pat, &fcResult);
    FcPatternDestroy(pat);
    if (match == NULL) {
        return nil;
    }

    FcChar8 *filename = NULL;
    FcPatternGetString(match, FC_FILE, 0, &filename);

    NSString *res = nil;
    if (filename != NULL) {
        res = [NSString stringWithUTF8String: (char *) filename];
    }

    FcPatternDestroy(match);
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
        NSLog(@"encoding = %c %c %c %c", face->charmaps[i]->encoding >> 24,
              face->charmaps[i]->encoding >> 16,
              face->charmaps[i]->encoding >> 8, face->charmaps[i]->encoding);
        _ftEncoding = face->charmaps[0]->encoding;
    }

    if (FT_Select_Charmap(face, _ftEncoding) != 0) {
        NSLog(@"FT_Select_Charmap(%d) failed", _ftEncoding);
    }

    if (!(face->face_flags & FT_FACE_FLAG_SCALABLE)) {
        NSLog(@"FreeType font face is not scalable");
    }

    _unitsPerEm = (O2Float) face->units_per_EM;
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

FT_Face O2FontFreeTypeFace(O2Font_freetype *self) {
    return self->_face;
}

- (void) fetchAdvances {
    FT_Set_Char_Size(_face, 0, _unitsPerEm * 64, 72, 72);

    _advances = NSZoneMalloc(NULL, sizeof(NSInteger) * _numberOfGlyphs);

    for (O2Glyph glyph = 0; glyph < _numberOfGlyphs; glyph++) {
        FT_Load_Glyph(_face, glyph, FT_LOAD_DEFAULT);

        _advances[glyph] = _face->glyph->advance.x / (O2Float)(2 << 5);
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
            length: (NSInteger) length {
    for (int i = 0; i < length; i++) {
        glyphs[i] = FT_Get_Char_Index(_face, codes[i]);
    }
}

- (O2Encoding *) unicode_createEncodingForTextEncoding:
    (O2TextEncoding) encoding {
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
    (O2TextEncoding) encoding {
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
