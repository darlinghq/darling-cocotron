#import <Onyx2D/O2Font_freetype.h>
#ifdef FREETYPE_PRESENT
#import <Onyx2D/O2Encoding.h>

/* Font smoothing thickens the outlines: macOS renders smoothed text with about
 * 15% more coverage than the plain outline at every size, which scales with the
 * size like the stem width does. The factor is the added stem width per pixel of
 * font size at the default (medium, level 2) setting, fitted to coverage totals
 * measured on macOS 10.14.4; levels 1 and 3 scale it by 1/2 and 3/2. */
#define O2FONT_SMOOTHING_WIDENING 0.0125
#import <string.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>
#import FT_TRUETYPE_TABLES_H
#import FT_OUTLINE_H
#include <math.h>

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

// Adds a font file, or a directory of them, at a guest path to the application
// fonts of config. Returns NO when the path does not exist or fontconfig takes nothing from it.
static BOOL addFontFile(FcConfig *config, NSString *path) {
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath: path
                                              isDirectory: &isDirectory])
        return NO;
    path = hostPathFromGuestPath(path);
    if (isDirectory)
        return FcConfigAppFontAddDir(config, (const FcChar8 *) [path UTF8String]) != FcFalse;
    return FcConfigAppFontAddFile(config, (const FcChar8 *) [path UTF8String]) != FcFalse;
}

static void addAppFont(FcConfig *config, NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource: name ofType: nil];
    if (path == nil) {
        NSLog(@"Cannot find font %@ in resources", name);
        return;
    }
    addFontFile(config, path);
}

#ifdef DARLING
// fontconfig runs on the host: it expands "~" and the XDG cache directory
// from a HOME that names the guest's home directory, which does not exist on
// the host, and the system cache directory is not writable by a user. With no
// writable cache directory it reports an error on every use and rescans the
// fonts each time. Give it a cache directory in the user's Caches folder,
// which lives inside the prefix, as an additional <cachedir> (fonts.conf(5)):
// fontconfig writes to the first one that is writable.
static void addPrefixCacheDirectory(FcConfig *config) {
    NSArray *caches = NSSearchPathForDirectoriesInDomains(
            NSCachesDirectory, NSUserDomainMask, YES);
    if ([caches count] == 0)
        return;

    NSString *guestDirectory =
            [[caches objectAtIndex: 0] stringByAppendingPathComponent: @"fontconfig"];
    NSMutableString *hostDirectory =
            [hostPathFromGuestPath(guestDirectory) mutableCopy];
    // the directory goes into XML text
    [hostDirectory replaceOccurrencesOfString: @"&" withString: @"&amp;"
                                      options: 0
                                        range: NSMakeRange(0, [hostDirectory length])];
    [hostDirectory replaceOccurrencesOfString: @"<" withString: @"&lt;"
                                      options: 0
                                        range: NSMakeRange(0, [hostDirectory length])];
    [hostDirectory replaceOccurrencesOfString: @">" withString: @"&gt;"
                                      options: 0
                                        range: NSMakeRange(0, [hostDirectory length])];

    NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><fontconfig><cachedir>%@</cachedir></fontconfig>",
            hostDirectory];
    [hostDirectory release];
    FcConfigParseAndLoadFromMemory(
            config, (const FcChar8 *) [xml UTF8String], FcTrue);
}
#endif

FcConfig *O2FontSharedFontConfig() {
    static FcConfig *fontConfig = NULL;

    if (fontConfig == NULL) {
#ifdef DARLING
        fontConfig = FcInitLoadConfig();
        if (fontConfig != NULL) {
            addPrefixCacheDirectory(fontConfig);
            FcConfigBuildFonts(fontConfig);
        }
#else
        fontConfig = FcInitLoadConfigAndFonts();
#endif

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

O2FontRegistrationResult O2FontRegisterFontFile(NSString *path) {
    static NSMutableSet *registered = nil;

    if (path == nil || ![[NSFileManager defaultManager] fileExistsAtPath: path])
        return O2FontRegistrationNotFound;
    path = [path stringByStandardizingPath];
    @synchronized([O2Font_freetype class]) {
        if (registered == nil)
            registered = [[NSMutableSet alloc] init];
        if ([registered containsObject: path])
            return O2FontRegistrationAlreadyRegistered;
        FcConfig *config = O2FontSharedFontConfig();
        if (config == NULL || !addFontFile(config, path))
            return O2FontRegistrationUnrecognized;
        [registered addObject: path];
    }
    return O2FontRegistrationSucceeded;
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
static NSString *filenameOfFirstScalableFace(FcFontSet *set, int *faceIndex) {
    NSString *fallback = nil;
    int fallbackIndex = 0;
    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *filename = NULL;
        if (FcPatternGetString(set->fonts[i], FC_FILE, 0, &filename) != FcResultMatch) {
            continue;
        }
        NSString *path = [NSString stringWithUTF8String: (char *) filename];
        if (path == nil) {
            continue;
        }
        /* The face within a font collection (.ttc) file; 0 when the pattern has none. */
        int index = 0;
        FcPatternGetInteger(set->fonts[i], FC_INDEX, 0, &index);
        FcBool scalable = FcTrue; /* left untouched when the pattern has no FC_SCALABLE */
        FcPatternGetBool(set->fonts[i], FC_SCALABLE, 0, &scalable);
        if (scalable) {
            *faceIndex = index;
            return path;
        }
        if (fallback == nil) {
            fallback = path;
            fallbackIndex = index;
        }
    }
    *faceIndex = fallbackIndex;
    return fallback;
}

O2FontRef O2FontCreateWithCodePointCoverage(const uint32_t *codePoints,
                                           size_t count, FT_Face baseFace,
                                           const char *language) {
    if (codePoints == NULL || count == 0)
        return nil;

    FcPattern *pattern = FcPatternCreate();
    FcCharSet *characters = FcCharSetCreate();
    if (pattern == NULL || characters == NULL) {
        if (pattern != NULL)
            FcPatternDestroy(pattern);
        if (characters != NULL)
            FcCharSetDestroy(characters);
        return nil;
    }
    for (size_t index = 0; index < count; ++index) {
        if (codePoints[index] > 0x10FFFF ||
            (codePoints[index] >= 0xD800 && codePoints[index] <= 0xDFFF) ||
            !FcCharSetAddChar(characters, codePoints[index])) {
            FcCharSetDestroy(characters);
            FcPatternDestroy(pattern);
            return nil;
        }
    }
    FcBool added = FcPatternAddCharSet(pattern, FC_CHARSET, characters);
    FcCharSetDestroy(characters);
    if (!added) {
        FcPatternDestroy(pattern);
        return nil;
    }

    // Coverage is mandatory below; these properties rank suitable substitutes.
    // Do not add the base file/index: that would pin selection to the old face.
    if (baseFace != NULL) {
        if (baseFace->family_name != NULL)
            added = FcPatternAddString(pattern, FC_FAMILY,
                    (const FcChar8 *)baseFace->family_name);
        added = added && FcPatternAddInteger(pattern, FC_WEIGHT,
                baseFace->style_flags & FT_STYLE_FLAG_BOLD
                        ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR);
        added = added && FcPatternAddInteger(pattern, FC_SLANT,
                baseFace->style_flags & FT_STYLE_FLAG_ITALIC
                        ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
        if (FT_IS_FIXED_WIDTH(baseFace))
            added = added && FcPatternAddInteger(pattern, FC_SPACING, FC_MONO);
    }
    if (language != NULL && language[0] != '\0')
        added = added && FcPatternAddString(pattern, FC_LANG,
                                            (const FcChar8 *)language);
    if (!added) {
        FcPatternDestroy(pattern);
        return nil;
    }

    FcConfig *config = O2FontSharedFontConfig();
    if (config == NULL || !FcConfigSubstitute(config, pattern, FcMatchPattern)) {
        FcPatternDestroy(pattern);
        return nil;
    }
    FcDefaultSubstitute(pattern);
    FcResult result;
    FcPattern *match = FcFontMatch(config, pattern, &result);
    FcPatternDestroy(pattern);
    if (match == NULL)
        return nil;

    FcChar8 *filename = NULL;
    int faceIndex = 0;
    FcResult indexResult = FcPatternGetInteger(match, FC_INDEX, 0, &faceIndex);
    if (FcPatternGetString(match, FC_FILE, 0, &filename) != FcResultMatch ||
        (indexResult != FcResultMatch && indexResult != FcResultNoMatch) ||
        faceIndex < 0) {
        FcPatternDestroy(match);
        return nil;
    }
    // FC_FILE is a host path and FreeType is a host library: no guest-to-host
    // path mapping applies here (that is for paths guest code supplies).
    FT_Face face = NULL;
    FT_Error error = FT_New_Face(O2FontSharedFreeTypeLibrary(),
                                 (const char *)filename, faceIndex, &face);
    FcPatternDestroy(match);
    if (error != 0)
        return nil;
    if (FT_Select_Charmap(face, FT_ENCODING_UNICODE) != 0) {
        FT_Done_Face(face);
        return nil;
    }
    for (size_t index = 0; index < count; ++index) {
        if (FT_Get_Char_Index(face, codePoints[index]) == 0) {
            FT_Done_Face(face);
            return nil;
        }
    }
    return [[O2Font_freetype alloc] initWithFace: face];
}

/* The installed face whose PostScript name is exactly name: its file and the face index in it
 * (which selects the face within a font collection file and the instance of a variable font). */
+ (NSString *) filenameForPostScriptName: (NSString *) name faceIndex: (int *) faceIndex {
    FcConfig *config = O2FontSharedFontConfig();
    FcPattern *pattern = FcPatternCreate();
    FcObjectSet *objects = FcObjectSetCreate();
    NSString *result = nil;

    if (pattern != NULL && objects != NULL && [name length] > 0 &&
        FcPatternAddString(pattern, FC_POSTSCRIPT_NAME, (const FcChar8 *) [name UTF8String]) &&
        FcObjectSetAdd(objects, FC_FILE) && FcObjectSetAdd(objects, FC_INDEX)) {
        FcFontSet *set = FcFontList(config, pattern, objects);
        for (int i = 0; set != NULL && i < set->nfont && result == nil; i++) {
            FcChar8 *filename = NULL;
            if (FcPatternGetString(set->fonts[i], FC_FILE, 0, &filename) != FcResultMatch)
                continue;
            int index = 0;
            FcPatternGetInteger(set->fonts[i], FC_INDEX, 0, &index);
            result = [NSString stringWithUTF8String: (const char *) filename];
            *faceIndex = index;
        }
        if (set != NULL)
            FcFontSetDestroy(set);
    }
    if (objects != NULL)
        FcObjectSetDestroy(objects);
    if (pattern != NULL)
        FcPatternDestroy(pattern);
    return result;
}

+ (NSString *) filenameForPattern: (NSString *) pattern faceIndex: (int *) faceIndex {
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

    NSString *res = filenameOfFirstScalableFace(set, faceIndex);
    FcFontSetDestroy(set);
    return res;
}

- (instancetype) initWithDataProvider: (O2DataProviderRef) provider {
    self = [super initWithDataProvider: provider];
    if (self == nil) {
        return nil;
    }

    // FreeType reads the font from one block of memory that must outlive the
    // face. Direct-access providers (CFData, bytes, URL) already expose such a
    // block; a file provider is sequential and has none, so read its contents.
    const void *bytes = [provider bytes];
    size_t length = [provider length];
    if (bytes == NULL) {
        CFDataRef contents = O2DataProviderCopyData(provider);
        if (contents == NULL) {
            [self release];
            return nil;
        }
        _faceData = (NSData *) contents;
        bytes = [_faceData bytes];
        length = [_faceData length];
    }

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

    // The face is found by its PostScript name, else by fontconfig's closest match for the name. A font
    // collection file holds several faces: the face that was matched is opened, not the first.
    int faceIndex = 0;
    NSString *filename = [[self class] filenameForPostScriptName: name faceIndex: &faceIndex];
    if (filename == nil) {
        filename = [[self class] filenameForPattern: name faceIndex: &faceIndex];
    }
    if (filename == nil) {
        filename = [[self class] filenameForPattern: @"" faceIndex: &faceIndex];
    }
    if (filename == nil) {
        NSLog(@"No font found for name %@", name);
        [self release];
        return nil;
    }

    FT_Face face;
    FT_Error error = FT_New_Face(O2FontSharedFreeTypeLibrary(),
                                 [filename fileSystemRepresentation], faceIndex, &face);

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
    _glyphCache = [NSMutableDictionary new];

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
    } else if (numberOfCharMaps > 0) {
        _ftEncoding = face->charmaps[0]->encoding;
    } else {
        // No cmap at all: common in the TrueType subsets PDFs embed for
        // CIDFontType2 fonts, which address glyphs by index, not by character.
        _ftEncoding = FT_ENCODING_NONE;
    }

    if (_ftEncoding != FT_ENCODING_NONE &&
        FT_Select_Charmap(face, _ftEncoding) != 0) {
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
    _capHeight = 0;
    _xHeight = 0;
    // sCapHeight and sxHeight exist from OS/2 version 2 on.
    TT_OS2 *os2 = FT_Get_Sfnt_Table(face, FT_SFNT_OS2);
    if (os2 != NULL && os2->version >= 2) {
        _capHeight = os2->sCapHeight;
        _xHeight = os2->sxHeight;
    }
    // Older tables: take the height of the flat-topped letters instead.
    if (_capHeight <= 0 || _xHeight <= 0) {
        NSInteger *targets[2] = { &_capHeight, &_xHeight };
        FT_ULong letters[2] = { 'H', 'x' };
        for (int i = 0; i < 2; i++) {
            FT_UInt g = *targets[i] > 0 ? 0 : FT_Get_Char_Index(face, letters[i]);
            if (g != 0 &&
                FT_Load_Glyph(face, g, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING) == 0)
                *targets[i] = face->glyph->metrics.horiBearingY;
        }
    }
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
    [_faceData release];
    [_glyphCache release];
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
        _advances = NSZoneMalloc(NULL, sizeof(NSInteger) * _numberOfGlyphs);

        // Design-unit advances: unscaled and unhinted, so that scaling them to
        // any point size gives the exact fractional advance.
        for (O2Glyph glyph = 0; glyph < _numberOfGlyphs; glyph++) {
            if (FT_Load_Glyph(_face, glyph,
                              FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING |
                                      FT_LOAD_IGNORE_TRANSFORM) == 0)
                _advances[glyph] = _face->glyph->advance.x;
            else
                _advances[glyph] = 0;
        }
    }
}

- (int) verticalAdvanceForGlyph: (O2Glyph) glyph {
    @synchronized(self) {
        // With FT_LOAD_VERTICAL_LAYOUT the vertical advance is in advance.y; FreeType
        // synthesizes one for a font without vhea/vmtx tables.
        if (FT_Load_Glyph(_face, glyph,
                          FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING |
                                  FT_LOAD_IGNORE_TRANSFORM |
                                  FT_LOAD_VERTICAL_LAYOUT) != 0)
            return 0;
        return (int) _face->glyph->advance.y;
    }
}

- (O2Glyph) glyphWithGlyphName: (NSString *) name {
    return FT_Get_Name_Index(_face, (char *) [name cString]);
}

- (NSString *) copyGlyphNameForGlyph: (O2Glyph) glyph {
    char initial[100];
    char *buffer = initial;
    FT_UInt capacity = sizeof(initial);
    NSString *result = nil;
    for (;;) {
        if (FT_Get_Glyph_Name(_face, glyph, buffer, capacity) != 0)
            break;
        char *end = memchr(buffer, 0, capacity);
        if (!end) break;
        if ((size_t)(end - buffer) < capacity - 1) {
            result = [[NSString alloc] initWithUTF8String:buffer];
            break;
        }
        if (capacity > UINT_MAX / 2 || capacity > SIZE_MAX / 2 ||
            capacity > PTRDIFF_MAX / 2)
            break;
        char *grown = malloc((size_t)capacity * 2);
        if (!grown) break;
        if (buffer != initial) free(buffer);
        buffer = grown;
        capacity *= 2;
    }
    if (buffer != initial) free(buffer);
    return result;
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

/* Cache entries are keyed by everything that determines the rendered bitmap:
 * the glyph, the 26.6 pixel size handed to FT_Set_Char_Size, the glyph matrix,
 * the render options, the smoothing level and the subpixel offset. Glyphs are
 * loaded unhinted: macOS positions and sizes text exactly, and does not snap
 * outlines to the pixel grid. */
#define O2FONT_GLYPH_LOAD_FLAGS (FT_LOAD_NO_HINTING)

typedef struct {
    uint32_t glyph;
    uint32_t size64;
    uint32_t options;
    uint32_t smoothing;
    uint32_t subpixelIndex;
    uint32_t subpixelSteps;
    FT_Fixed xx, xy, yx, yy;
} O2FreeTypeGlyphKey;

NSUInteger O2FreeTypeSubpixelSteps(BOOL quantized) {
    // A quantized position is one of four offsets, as on macOS.
    return quantized ? 4 : 16;
}

- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize
                                     matrix: (const O2FreeTypeGlyphMatrix *) matrix
                                    options: (unsigned) options
                                  smoothing: (unsigned) smoothing
                              subpixelIndex: (unsigned) subpixelIndex
                              subpixelSteps: (unsigned) subpixelSteps
{
    if (_face == NULL || !(pointSize > 0) || subpixelSteps == 0) {
        return nil;
    }

    BOOL antialiased = (options & O2FreeTypeGlyphAntialiased) != 0;
    if (!antialiased) {
        smoothing = 0;
    }

    /* The size is set here, under the font lock, so a hit or a miss never
     * depends on what size the face was left at by metric queries. */
    O2Float size64 = pointSize * 64;
    BOOL cacheable = size64 < (O2Float)(1 << 24);

    @synchronized(self) {
        NSData *key = nil;

        if (cacheable) {
            O2FreeTypeGlyphKey keyValue = {
                .glyph = glyph,
                .size64 = (uint32_t)(long) size64,
                .options = options,
                .smoothing = smoothing,
                .subpixelIndex = subpixelIndex,
                .subpixelSteps = subpixelSteps,
                .xx = matrix != NULL ? matrix->xx : 0x10000,
                .xy = matrix != NULL ? matrix->xy : 0,
                .yx = matrix != NULL ? matrix->yx : 0,
                .yy = matrix != NULL ? matrix->yy : 0x10000,
            };
            key = [NSData dataWithBytes: &keyValue length: sizeof(keyValue)];

            O2FreeTypeCachedGlyph *hit = [_glyphCache objectForKey: key];
            if (hit != nil) {
                return [[hit retain] autorelease];
            }
        }

        if (FT_Set_Char_Size(_face, 0, (long) size64, 72.0, 72.0) != 0) {
            return nil;
        }

        FT_Matrix ftMatrix = {
            matrix != NULL ? matrix->xx : 0x10000, matrix != NULL ? matrix->xy : 0,
            matrix != NULL ? matrix->yx : 0, matrix != NULL ? matrix->yy : 0x10000
        };
        // The pen's fractional x as a 26.6 offset applied to the outline.
        FT_Vector delta = { (FT_Pos)(subpixelIndex * 64 / subpixelSteps), 0 };
        FT_Set_Transform(_face, &ftMatrix, &delta);

        FT_Error error = FT_Load_Glyph(_face, glyph, O2FONT_GLYPH_LOAD_FLAGS);
        if (error == 0 && smoothing > 0 &&
            _face->glyph->format == FT_GLYPH_FORMAT_OUTLINE) {
            // Widen the outline, keeping it centred on the original.
            FT_Pos strength = (FT_Pos) lround(
                    O2FONT_SMOOTHING_WIDENING * (smoothing / 2.0) * pointSize * 64);
            FT_Outline_Embolden(&_face->glyph->outline, strength);
            FT_Outline_Translate(&_face->glyph->outline, -strength / 2, -strength / 2);
        }
        if (error == 0) {
            error = FT_Render_Glyph(_face->glyph,
                                    antialiased ? FT_RENDER_MODE_NORMAL
                                                : FT_RENDER_MODE_MONO);
        }
        FT_Set_Transform(_face, NULL, NULL);
        if (error != 0) {
            return nil;
        }

        FT_GlyphSlot slot = _face->glyph;
        O2FreeTypeCachedGlyph *cached = [[O2FreeTypeCachedGlyph alloc]
                initWithBitmap: &slot->bitmap
                          left: slot->bitmap_left
                           top: slot->bitmap_top
                       advance: slot->advance.x];
        [cached autorelease];

        if (!cacheable) {
            return cached;
        }

        NSUInteger bytes = (NSUInteger) cached->bitmap.rows *
                           (NSUInteger) cached->bitmap.width;

        if (bytes > O2FONT_GLYPH_CACHE_BYTES_LIMIT) {
            return cached; /* too large to be worth keeping */
        }

        /* Bounded by entry count and by bytes; the whole cache is dropped
         * when either limit would be exceeded. Entries handed out earlier
         * stay valid because they are retained by their callers. */
        if ([_glyphCache count] >= O2FONT_GLYPH_CACHE_LIMIT ||
            _glyphCacheBytes + bytes > O2FONT_GLYPH_CACHE_BYTES_LIMIT) {
            [_glyphCache removeAllObjects];
            _glyphCacheBytes = 0;
        }

        [_glyphCache setObject: cached forKey: key];
        _glyphCacheBytes += bytes;
        return cached;
    }
}

@end

@implementation O2FreeTypeCachedGlyph

- (instancetype) initWithBitmap: (const FT_Bitmap *) srcBitmap
                            left: (NSInteger) left
                             top: (NSInteger) top
                         advance: (FT_Pos) advance
{
    bitmap.rows = srcBitmap->rows;
    bitmap.width = srcBitmap->width;
    bitmap.pitch = srcBitmap->width;
    bitmap.num_grays = 256;
    bitmap.pixel_mode = FT_PIXEL_MODE_GRAY;
    bitmap.palette_mode = 0;
    bitmap.palette = NULL;
    bitmap.buffer = NULL;

    self->left = left;
    self->top = top;
    self->advance = advance;

    if (bitmap.rows > 0 && bitmap.width > 0) {
        size_t bytes = bitmap.rows * bitmap.width;
        unsigned char *data = NSZoneMalloc(NULL, bytes);

        for (FT_Int row = 0; row < bitmap.rows; row++) {
            const unsigned char *srcRow = srcBitmap->buffer + row * srcBitmap->pitch;
            unsigned char *dstRow = data + row * bitmap.width;

            if (srcBitmap->pixel_mode == FT_PIXEL_MODE_MONO) {
                // One bit per pixel, most significant bit first: aliased
                // coverage is either 0 or 255.
                for (FT_Int x = 0; x < bitmap.width; x++) {
                    dstRow[x] = (srcRow[x >> 3] & (0x80 >> (x & 7))) ? 255 : 0;
                }
            } else {
                memcpy(dstRow, srcRow, bitmap.width);
            }
        }

        bitmap.buffer = data;
    }

    return self;
}

- (void) dealloc {
    if (bitmap.buffer != NULL) {
        NSZoneFree(NULL, bitmap.buffer);
    }
    [super dealloc];
}

@end
#endif
