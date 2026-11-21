/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSFont.h>
#import <AppKit/NSFontDescriptor.h>
#import <AppKit/NSFontFamily.h>
#import <AppKit/NSFontTypeface.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/NSByteOrder.h>
#import <Foundation/NSKeyedArchiver.h>

#import <Onyx2D/O2Font.h>
#import <CoreText/KTFont.h>

NSNotificationName NSFontSetChangedNotification =
        @"NSFontSetChangedNotification";
NSNotificationName NSAntialiasThresholdChangedNotification =
        @"NSAntialiasThresholdChangedNotification";

FOUNDATION_EXPORT char *NSUnicodeToSymbol(const unichar *characters,
                                          NSUInteger length, BOOL lossy,
                                          NSUInteger *resultLength,
                                          NSZone *zone);

#ifndef DARLING
@implementation NSNibFontNameTranslator
// It seems the default mapping should really go to some platform specific place
- (NSString *) translateToNibFontName: (NSString *) name {
    NSString *displayName = [O2Font displayNameForPostscriptName: name];
    if ([displayName isEqual: @"Arial"])
        return [O2Font postscriptNameForDisplayName: @"Helvetica"];
    if ([displayName isEqual: @"Arial Bold"])
        return @"Helvetica-Bold";
    if ([displayName isEqual: @"Arial Italic"])
        return @"Helvetica-Oblique";
    if ([displayName isEqual: @"Arial Bold Italic"])
        return @"Helvetica-BoldOblique";

    if ([displayName isEqual: @"Times New Roman"])
        return @"Times-Roman";
    if ([displayName isEqual: @"Courier New"])
        return @"Courier";

    return name;
}

- (NSString *) translateFromNibFontName: (NSString *) name {
    NSString *displayName = [O2Font displayNameForPostscriptName: name];

    if ([name isEqual: @"Helvetica"])
        return [O2Font postscriptNameForDisplayName: @"Arial"];
    if ([name isEqual: @"Helvetica-Bold"])
        return [O2Font postscriptNameForDisplayName: @"Arial Bold"];
    if ([name isEqual: @"Helvetica-Oblique"])
        return [O2Font postscriptNameForDisplayName: @"Arial Bold"];
    if ([name isEqual: @"Helvetica-BoldOblique"])
        return [O2Font postscriptNameForDisplayName: @"Arial Bold Italic"];

    if ([name isEqual: @"Times-Roman"])
        return [O2Font postscriptNameForDisplayName: @"Times New Roman"];
    if ([name isEqual: @"Ohlfs"])
        return [O2Font postscriptNameForDisplayName: @"Courier New"];
    if ([name isEqual: @"Courier"])
        return [O2Font postscriptNameForDisplayName: @"Courier New"];

    if ([name isEqual: @"LucidaGrande"])
        return [O2Font postscriptNameForDisplayName: @"Arial"];
    if ([name isEqual: @"LucidaGrande-Bold"])
        return [O2Font postscriptNameForDisplayName: @"Arial Bold"];

    // Special fonts used by Xcode 5 when compiling some xibs
    if ([name isEqual: @".LucidaGrandeUI"])
        return [O2Font postscriptNameForDisplayName: @"Arial"];
    if ([name isEqual: @".LucidaGrandeUI-Bold"])
        return [O2Font postscriptNameForDisplayName: @"Arial Bold"];

    if ([name isEqual: @"HelveticaNeue-CondensedBold"])
        return [O2Font postscriptNameForDisplayName: @"Arial"];
    if ([name isEqual: @"HelveticaNeue-Bold"])
        return [O2Font postscriptNameForDisplayName: @"Arial"];
    if ([name isEqual: @"HelveticaNeue-Regular"])
        return [O2Font postscriptNameForDisplayName: @"Arial"];

    return name;
}

@end
#endif

static const CGFloat identityFontMatrix[6] = { 1, 0, 0, 1, 0, 0 };
const CGFloat *NSFontIdentityMatrix = identityFontMatrix;

@implementation NSFont

#ifndef DARLING
static NSNibFontNameTranslator *_nibFontTranslator = nil;
#endif

static NSUInteger _fontCacheCapacity = 0;
static NSUInteger _fontCacheSize = 0;
static NSFont **_fontCache = NULL;

static NSLock *_cacheLock = nil;

+ (void) initialize {
    if (self == [NSFont class]) {
        _fontCacheCapacity = 4;
        _fontCacheSize = 0;
        _fontCache = NSZoneMalloc([self zone],
                                  sizeof(NSFont *) * _fontCacheCapacity);
#ifndef DARLING
        _nibFontTranslator = [[NSNibFontNameTranslator alloc] init];
#endif
        _cacheLock = [[NSLock alloc] init];
    }
}

+ (NSUInteger) _cacheIndexOfFontWithName: (NSString *) name
                                    size: (CGFloat) size
{
    NSUInteger i;

    for (i = 0; i < _fontCacheSize; i++) {
        NSFont *check = _fontCache[i];

        if (check != nil && [[check fontName] isEqualToString: name] &&
            [check pointSize] == size)
            return i;
    }

    return NSNotFound;
}

+ (NSFont *) cachedFontWithName: (NSString *) name size: (CGFloat) size {

    NSFont *font = nil;
    [_cacheLock lock];
    NSUInteger i = [self _cacheIndexOfFontWithName: name size: size];

    font = (i == NSNotFound) ? (NSFont *) nil : _fontCache[i];
    [_cacheLock unlock];
    return font;
}

+ (void) addFontToCache: (NSFont *) font {

    if (font == nil) {
        return;
    }
    NSUInteger i;

    [_cacheLock lock];
    for (i = 0; i < _fontCacheSize; i++) {
        if (_fontCache[i] == nil) {
            _fontCache[i] = font;
            [_cacheLock unlock];
            return;
        }
    }

    if (_fontCacheSize >= _fontCacheCapacity) {
        _fontCacheCapacity *= 2;
        _fontCache = NSZoneRealloc([self zone], _fontCache,
                                   sizeof(NSFont *) * _fontCacheCapacity);
    }
    _fontCache[_fontCacheSize++] = font;
    [_cacheLock unlock];
}

+ (void) removeFontFromCache: (NSFont *) font {
    [_cacheLock lock];
    NSUInteger i = [self _cacheIndexOfFontWithName: [font fontName]
                                              size: [font pointSize]];

    // Screen fonts share the name and size of the cached font without being it.
    if (i != NSNotFound && _fontCache[i] == font)
        _fontCache[i] = nil;
    [_cacheLock unlock];
}

// The sizes of the system, small system and label fonts of the Human Interface
// Guidelines (13, 11 and 10 points), as macOS 10.14.4 and 26.7.3 report them.
+ (CGFloat) systemFontSize {
    return 13.0;
}

+ (CGFloat) smallSystemFontSize {
    return 11.0;
}

+ (CGFloat) labelFontSize {
    return 10.0;
}

+ (CGFloat) systemFontSizeForControlSize: (NSControlSize) size {
    switch (size) {
    default:
    case NSRegularControlSize:
        return 13.0;

    case NSSmallControlSize:
        return 11.0;

    case NSMiniControlSize:
        return 9.0;
    }
}

// The font factory methods take 0 or a negative size to mean the default size
// of the font they return.
static CGFloat sizeOrDefault(CGFloat size, CGFloat defaultSize) {
    return size > 0 ? size : defaultSize;
}

+ (NSFont *) _uiFontOfType: (CTFontUIFontType) type
                      size: (CGFloat) size
              fallbackName: (NSString *) fallbackName
{
    NSFont *result = nil;
    CTFontRef ctFont = CTFontCreateUIFontForLanguage(type, size, nil);
    if (ctFont) {
        NSString *name = (NSString *) CTFontCopyFullName(ctFont);

        size = CTFontGetSize(ctFont);

        result = [NSFont fontWithName: name size: size];

        [ctFont release];
        [name release];
    } else {
        result = [NSFont fontWithName: [O2Font postscriptNameForDisplayName:
                                                       fallbackName]
                                 size: size];
    }
    O2FontLog(@"asked for type: %d got font: %@", type, result);
    return result;
}

+ (NSFont *) boldSystemFontOfSize: (CGFloat) size {
    NSFont *font = [self systemFontOfSize: size];
    return [[NSFontManager sharedFontManager] convertFont: font
                                              toHaveTrait: NSBoldFontMask];
}

+ (NSFont *) controlContentFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontControlContentFontType
                          size: sizeOrDefault(size, 12.0)
                  fallbackName: @"San Francisco"];
}

+ (NSFont *) labelFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontLabelFontType
                          size: sizeOrDefault(size, [self labelFontSize])
                  fallbackName: @"San Francisco"];
}

// QUIRK: menuFontOfSize: with size 0 gives 13 points, while the menu item UI font
// type of Core Text defaults to 14; menuBarFontOfSize: gives 14 on 10.14 (13 on
// macOS 26; we follow 10.14). Not documented. Evidence: black-box observation
// on macOS 10.14.4 and 26.7.3 (tier 2), probe mac-probes/aqua-metric-followups.m
// of the research notes. Test: appkit-font-default-sizes.m (test_quirk_menu_fonts)
+ (NSFont *) menuFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontMenuItemFontType
                          size: sizeOrDefault(size, 13.0)
                  fallbackName: @"San Francisco"];
}

+ (NSFont *) menuBarFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontMenuTitleFontType
                          size: sizeOrDefault(size, 14.0)
                  fallbackName: @"San Francisco"];
}

+ (NSFont *) messageFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontSystemFontType
                          size: sizeOrDefault(size, [self systemFontSize])
                  fallbackName: @"San Francisco"];
}

// QUIRK: the palette and tool tip fonts default to 11 points. Not documented.
// Evidence: black-box observation on macOS 10.14.4 and 26.7.3 (tier 2), probe
// mac-probes/aqua-metric-followups.m of the research notes.
// Test: appkit-font-default-sizes.m (test_quirk_palette_tooltip_fonts)
+ (NSFont *) paletteFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontPaletteFontType
                          size: sizeOrDefault(size, 11.0)
                  fallbackName: @"San Francisco"];
}

+ (NSFont *) systemFontOfSize: (CGFloat) size {
    return [self messageFontOfSize: size];
}

+ (NSFont *) systemFontOfSize: (CGFloat) size weight: (NSFontWeight) weight {
    // Only the regular and bold system faces are available; semibold and
    // heavier weights get the bold one.
    if (weight >= NSFontWeightSemibold)
        return [self boldSystemFontOfSize: size];
    return [self systemFontOfSize: size];
}

+ (NSFont *) monospacedSystemFontOfSize: (CGFloat) size
                                 weight: (NSFontWeight) weight {
    NSFont *font = [self userFixedPitchFontOfSize: size];

    // As with the proportional system font, only regular and bold faces are
    // looked for; semibold and heavier weights get the bold one.
    if (weight >= NSFontWeightSemibold)
        font = [[NSFontManager sharedFontManager] convertFont: font
                                                  toHaveTrait: NSBoldFontMask];
    return font;
}

+ (NSFont *) monospacedDigitSystemFontOfSize: (CGFloat) size
                                      weight: (NSFontWeight) weight {
    // No tabular-figures variant available; the proportional system font is
    // the closest faithful stand-in.
    return [self systemFontOfSize: size weight: weight];
}

// The title bar font is the window title UI font: regular, 13 points by default
// (macOS 10.14.4).
+ (NSFont *) titleBarFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontWindowTitleFontType
                          size: sizeOrDefault(size, [self systemFontSize])
                  fallbackName: @"San Francisco"];
}

+ (NSFont *) toolTipsFontOfSize: (CGFloat) size {
    return [self _uiFontOfType: kCTFontToolTipFontType
                          size: sizeOrDefault(size, 11.0)
                  fallbackName: @"San Francisco"];
}

+ (NSFont *) userFontOfSize: (CGFloat) size {
    return [NSFont fontWithName: [O2Font postscriptNameForDisplayName:
                                                 @"San Francisco"]
                           size: sizeOrDefault(size, 12.0)];
}

// QUIRK: the fixed pitch user font defaults to 10 points on 10.14 (11 on macOS
// 26; we follow 10.14), as the fixed pitch UI font type of Core Text does. Not
// documented. Evidence: black-box observation on macOS 10.14.4 and 26.7.3
// (tier 2), probe mac-probes/aqua-metric-followups.m of the research notes.
// Test: appkit-font-default-sizes.m (test_quirk_user_fonts)
+ (NSFont *) userFixedPitchFontOfSize: (CGFloat) size {
    return [NSFont
            fontWithName: [O2Font postscriptNameForDisplayName: @"Courier New"]
                    size: sizeOrDefault(size, 10.0)];
}

+ (void) setUserFont: (NSFont *) value {
    NSUnimplementedMethod();
}

+ (void) setUserFixedPitchFont: (NSFont *) value {
    NSUnimplementedMethod();
}

+ (NSArray *) preferredFontNames {
    return [O2Font preferredFontNames];
}

+ (void) setPreferredFontNames: (NSArray *) fontNames {
    [O2Font setPreferredFontNames: fontNames];
}

+ (BOOL) supportsSecureCoding {
    return YES;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
#ifndef DARLING
        [coder encodeObject: [[NSFont nibFontTranslator]
                                     translateToNibFontName: _name]
                     forKey: @"NSName"];
#else
        [coder encodeObject: _name forKey: @"NSName"];
#endif
        [coder encodeFloat: _pointSize forKey: @"NSSize"];
    } else {
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ can not encodeWithCoder:%@", [self class],
                            [coder class]];
    }
}

- initWithCoder: (NSCoder *) coder {
    NSString *name;
    CGFloat size;

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        NSString *fontName = [keyed decodeObjectOfClass: [NSString class] forKey: @"NSName"];
#ifndef DARLING
        name = [[NSFont nibFontTranslator] translateFromNibFontName: fontName];
#else
        name = fontName;
#endif
        size = [keyed decodeFloatForKey: @"NSSize"];
        // int                flags=[keyed decodeIntForKey:@"NSfFlags"]; // ?
        NSUInteger matrixLen;
        const uint32_t *matrixBytes =
                (const uint32_t *) [keyed decodeBytesForKey: @"NSMatrix"
                                             returnedLength: &matrixLen];

        if (matrixLen >= 6 * sizeof(float) && matrixBytes) {
            for (int i = 0; i < 6; i++) {
                union {
                    uint32_t dword;
                    float flt;
                } ff;

                ff.dword = NSSwapBigIntToHost(matrixBytes[i]);
                NS_EXTRA(NSFont, self)->_matrix[i] = ff.flt;
            }
        }
    } else {
        NSInteger version = [coder versionForClassName: @"NSFont"];

        unsigned int fFlags = 0;
        bool f2;
        unsigned int fx;
        if (version >= 21) {
            // The name is a property list; four separate byte reads follow the size.
            name = [coder decodePropertyList];

            float flt;
            char byteFx = 0, byteFlags = 0, byteF2 = 0, byteF3 = 0;
            [coder decodeValuesOfObjCTypes: "f", &flt];
            [coder decodeValuesOfObjCTypes: "c", &byteFx];
            fx = byteFx != 0;

            [coder decodeValuesOfObjCTypes: "c", &byteFlags];
            fFlags = (unsigned char) byteFlags;
            fFlags <<= 13;

            [coder decodeValuesOfObjCTypes: "c", &byteF2];
            f2 = byteF2 != 0;
            [coder decodeValuesOfObjCTypes: "c", &byteF3];

            fFlags |= ((unsigned char) byteF3) << 1;

            size = flt;
            if (![name isKindOfClass: [NSString class]])
                [NSException raise: NSInvalidArgumentException format: @"NSFont: the archived font has no name"];
        } else {
            char *nameStr = NULL;
            float flt;
            unsigned short flags1, flags2;

            [coder decodeValuesOfObjCTypes: (version == 2) ? "%fss" : "*fss",
                                            &nameStr, &flt, &flags1, &flags2];

            if (nameStr == NULL)
                [NSException raise: NSInvalidArgumentException format: @"NSFont: the archived font has no name"];
            name = [NSString stringWithCString: nameStr
                                      encoding: NSASCIIStringEncoding];
            free(nameStr);

            fFlags = ((unsigned) flags2 & 4) << 11;
            fFlags |= (flags2 >> 8) & 0x1E;

            fx = flags2 & 1;
            f2 = ((unsigned) flags2 >> 1) & 1;

            size = flt;
        }

        if (!(fFlags & 0x2000)) {
            if (f2) {
                // TODO: Do some transform of flt
                // D0189
            } else {
                float transform[6];
                [coder decodeArrayOfObjCType: "f" count: 6 at: transform];
                for (int i = 0; i < 6; i++)
                    NS_EXTRA(NSFont, self)->_matrix[i] = transform[i];
            }
        }

        if (fx != 0)
            [coder decodeValuesOfObjCTypes: "i", &fx];
    }

    [self release];
    NSFont *realFont = [[NSFont fontWithName: name size: size] retain];

    O2FontLog(@"coded font name: %@ translated font name: %@ rendered font: %@",
              fontName, name, realFont);
    return realFont;
}

- initWithName: (NSString *) name size: (CGFloat) size {
    _name = [name copy];
    _pointSize = size;
    NS_EXTRA(NSFont, self)->_matrix[0] = _pointSize;
    NS_EXTRA(NSFont, self)->_matrix[1] = 0;
    NS_EXTRA(NSFont, self)->_matrix[2] = 0;
    NS_EXTRA(NSFont, self)->_matrix[3] = _pointSize;
    NS_EXTRA(NSFont, self)->_matrix[4] = 0;
    NS_EXTRA(NSFont, self)->_matrix[5] = 0;

    if ([_name isEqualToString: @"Symbol"])
        NS_EXTRA(NSFont, self)->_encoding = NSSymbolStringEncoding;
    else
        NS_EXTRA(NSFont, self)->_encoding = NSUnicodeStringEncoding;

    NS_EXTRA(NSFont, self)->_cgFont = CGFontCreateWithFontName((CFStringRef) _name);
    if (NS_EXTRA(NSFont, self)->_cgFont) {
        NS_EXTRA(NSFont, self)->_ctFont = CTFontCreateWithGraphicsFont(
                NS_EXTRA(NSFont, self)->_cgFont, _pointSize, NULL, NULL);
        [[self class] addFontToCache: self];
        O2FontLog(@"name: %@ _cgFont: %@ _ctFont: %@", name, NS_EXTRA(NSFont, self)->_cgFont,
                  NS_EXTRA(NSFont, self)->_ctFont);
    } else {
        [self release];
        self = nil;
    }
    return self;
}

- (void) dealloc {
    [[self class] removeFontFromCache: self];

    [_name release];
    if (NS_EXTRA_ALLOCATED(NSFont, self)) {
        CGFontRelease(NS_EXTRA(NSFont, self)->_cgFont);
        [NS_EXTRA(NSFont, self)->_ctFont release];
        for (NSInteger i = 0; i < 4; i++)
            [NS_EXTRA(NSFont, self)->_screenFonts[i] release];
    }
    NS_EXTRA_FREE(NSFont, self);
    [super dealloc];
}

// A size of 0 or less asks for the default size, 12 points (as on macOS
// 10.14.4 and 26.7.3). Test: tests/appkit-font-default-size.m
+ (NSFont *) fontWithName: (NSString *) name size: (CGFloat) size {
    NSFont *result;

    size = sizeOrDefault(size, 12.0);

    if (name == nil)
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] name==nil", self, sel_getName(_cmd)];

    // Name can be PS name or a display name - internally we want a PS name -
    // that's what Cocoa is doing
    name = [O2Font postscriptNameForFontName: name];

    result = [self cachedFontWithName: name size: size];

    if (result == nil) {
        result = [[[NSFont alloc] initWithName: name size: size] autorelease];
    }

    return result;
}

+ (NSFont *) fontWithName: (NSString *) name matrix: (const CGFloat *) matrix {
    return [self fontWithName: name size: matrix[0]];
}

// A size of 0 or less asks for the descriptor's size, and for the default
// size when the descriptor has none (as on macOS 10.14.4 and 26.7.3).
// Test: tests/appkit-font-default-size.m
+ (NSFont *) fontWithDescriptor: (NSFontDescriptor *) descriptor
                           size: (CGFloat) size
{
    size = sizeOrDefault(size, [descriptor pointSize]);

    NSDictionary *attributes = [descriptor fontAttributes];
    NSString *fontName = [attributes objectForKey: NSFontNameAttribute];
    if (fontName) {
        return [NSFont fontWithName: fontName size: size];
    }

    NSString *fontFamily = [attributes objectForKey: NSFontFamilyAttribute];

    if (fontFamily) {
        NSFontManager *fontMgr = [NSFontManager sharedFontManager];

        NSArray *matchingFonts =
                [fontMgr availableMembersOfFontFamily: fontFamily];

        if ([matchingFonts count] == 1) {
            // won't find anything better than this
            NSArray *members = [matchingFonts objectAtIndex: 0];
            return [NSFont fontWithName: [members objectAtIndex: 0] size: size];
        } else {
            // Let's hope that we've got more to go on.
            NSString *fontFace = [attributes objectForKey: NSFontFaceAttribute];
            if (fontFace != nil) {
                NSInteger i = 0;
                for (i = 0; i < [matchingFonts count]; i++) {
                    NSArray *members = [matchingFonts objectAtIndex: i];
                    NSString *candidateFace = [members objectAtIndex: 1];
                    if ([candidateFace isEqualToString: fontFace]) {
                        return [NSFont fontWithName: [members objectAtIndex: 0]
                                               size: size];
                    }
                }
            } else {
                // just take the first one
                NSArray *members = [matchingFonts objectAtIndex: 0];
                return [NSFont fontWithName: [members objectAtIndex: 0]
                                       size: size];
            }
        }
    }
    NSLog(@"unable to match font descriptor: %@", descriptor);
    return nil;
}

+ (NSFont *) fontWithDescriptor: (NSFontDescriptor *) descriptor
                           size: (CGFloat) size
                  textTransform: (NSAffineTransform *) transform
{
    NSUnimplementedMethod();
    return 0;
}

- copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (CGFloat) pointSize {
    return _pointSize;
}

- (NSString *) fontName {
    return _name;
}

- (const CGFloat *) matrix {
    return NS_EXTRA(NSFont, self)->_matrix;
}

- (NSAffineTransform *) textTransform {
    NSAffineTransform *result = [NSAffineTransform transform];
    NSAffineTransformStruct fields = {
            NS_EXTRA(NSFont, self)->_matrix[0], NS_EXTRA(NSFont, self)->_matrix[1], NS_EXTRA(NSFont, self)->_matrix[2],
            NS_EXTRA(NSFont, self)->_matrix[3], NS_EXTRA(NSFont, self)->_matrix[4], NS_EXTRA(NSFont, self)->_matrix[5],
    };

    [result setTransformStruct: fields];

    return result;
}

- (NSFontRenderingMode) renderingMode {
    return NS_EXTRA(NSFont, self)->_isScreenFont ? NS_EXTRA(NSFont, self)->_renderingMode
                                                  : NSFontAntialiasedRenderingMode;
}

- (NSCharacterSet *) coveredCharacterSet {
    return O2FontGetCoveredCharacterSet((O2FontRef)NS_EXTRA(NSFont, self)->_cgFont);
}

- (NSStringEncoding) mostCompatibleStringEncoding {
    return NS_EXTRA(NSFont, self)->_encoding;
}

- (NSString *) familyName {
    NSString *familyName =
            [[NSFontFamily fontFamilyWithTypefaceName: _name] name];
    if (familyName == nil) {
        NSString *blank = @" ";
        NSMutableArray *nameComponents = [NSMutableArray
                arrayWithArray: [_name componentsSeparatedByString: blank]];
        while ([nameComponents count] > 1 && familyName == nil) {
            [nameComponents removeLastObject];
            familyName = [[NSFontFamily
                    installedFontFamilyWithName:
                            [nameComponents componentsJoinedByString: blank]]
                    name];
        }
    }

    // Fall back to using the font name - nil is not an option
    if (familyName == nil) {
        familyName = _name;
    }
    return familyName;
}

- (NSString *) displayName {
    NSFontTypeface *typeFace = [NSFontFamily fontTypefaceWithName: _name];
    // A name no family lists (the system font is "San Francisco") has no typeface; nil is not an option for callers.
    return [typeFace displayName] ?: _name;
}

- (NSDictionary *) _fontTraitsAsDictionary {
    NSFontManager *fm = [NSFontManager sharedFontManager];

    NSMutableDictionary *traitsDictionary =
            [NSMutableDictionary dictionaryWithCapacity: 4];
    NSFontFamily *family =
            [NSFontFamily fontFamilyWithTypefaceName: [self fontName]];
    NSFontTypeface *typeface = [family typefaceWithName: [self fontName]];
    NSFontTraitMask symbolicTraits = [typeface traits];
    [traitsDictionary setObject: [NSNumber numberWithInt: symbolicTraits]
                         forKey: NSFontSymbolicTrait];
    [traitsDictionary
            setObject: [NSNumber numberWithInt: [fm weightOfFont: self]]
               forKey: NSFontWeightTrait];
    //	[traitsDictionary setObject: [NSNumber numberWithInt: ??] forKey:
    // NSFontWidthTrait]; // not sure what's put here
    [traitsDictionary setObject: [NSNumber numberWithDouble: [self italicAngle]]
                         forKey: NSFontSlantTrait];
    return traitsDictionary;
}

- (NSFontDescriptor *) fontDescriptor {

    NSFontFamily *fontFamily =
            [NSFontFamily fontFamilyWithName: [self familyName]];
    NSFontTypeface *typeface = [fontFamily typefaceWithName: [self fontName]];

    NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys:
                    [self fontName], NSFontNameAttribute, [self familyName],
                    NSFontFamilyAttribute,
                    [[NSNumber numberWithDouble: [self pointSize]] stringValue],
                    NSFontSizeAttribute,
                    //								[self
                    // matrix], NSFontMatrixAttribute,
                    //// currently returns nil
                    // [self coveredCharacterSet], NSFontCharacterSetAttribute,
                    // // currently returns nil
                    [self _fontTraitsAsDictionary], NSFontTraitsAttribute,
                    [typeface traitName], NSFontFaceAttribute,
                    [NSNumber
                            numberWithDouble: [self maximumAdvancement].width],
                    NSFontFixedAdvanceAttribute, [self displayName],
                    NSFontVisibleNameAttribute, nil];

    NSFontDescriptor *descriptor =
            [NSFontDescriptor fontDescriptorWithFontAttributes: attributes];
    return descriptor;
}

- (NSFont *) printerFont {
    // Quartz fonts have no separate printer variant.
    return self;
}

// Whether the font lays out with whole-pixel advances.
static BOOL fontUsesIntegerAdvancements(NSFont *font) {
    return NS_EXTRA(NSFont, font)->_isScreenFont &&
           (NS_EXTRA(NSFont, font)->_renderingMode & NSFontIntegerAdvancementsRenderingMode) != 0;
}

// QUIRK: -screenFont always has whole-pixel advances (antialiased integer advancements), at every point
// size, while -screenFontWithRenderingMode: with the default mode stops rounding above 16 pt.
// Evidence and test as for NSFontDefaultScreenIntegerAdvancementsLimit (the quirk_ checks of appkit-screen-font-metrics).
- (NSFont *) screenFont {
    return [self screenFontWithRenderingMode: NSFontAntialiasedIntegerAdvancementsRenderingMode];
}

// The largest point size for which NSFontDefaultRenderingMode asks for a
// screen font with whole-pixel advances.
//
// QUIRK: the default screen font rounds the glyph advances to whole pixels up
// to 16 pt and keeps the exact advances above that; NSFontIntegerAdvancements-
// RenderingMode (without antialiasing) rounds differently from the
// antialiased variant at some sizes, and is treated like it here.
// Evidence: black-box measurements of -[NSFont screenFontWithRenderingMode:]
// and -renderingMode on macOS 10.14.4 (tier 2), sizes 9 to 20 in 0.5 pt steps,
// Helvetica, Times-Roman, Courier and DejaVu Sans.
// Test: appkit-screen-font-metrics
static const CGFloat NSFontDefaultScreenIntegerAdvancementsLimit = 16;

- (NSFont *) screenFontWithRenderingMode: (NSFontRenderingMode) mode {
    if (mode == NSFontDefaultRenderingMode)
        mode = _pointSize <= NSFontDefaultScreenIntegerAdvancementsLimit
                ? NSFontAntialiasedIntegerAdvancementsRenderingMode
                : NSFontAntialiasedRenderingMode;
    else if (mode < NSFontAntialiasedRenderingMode || mode > NSFontAntialiasedIntegerAdvancementsRenderingMode)
        return nil;

    if (NS_EXTRA(NSFont, self)->_isScreenFont && NS_EXTRA(NSFont, self)->_renderingMode == mode)
        return self;

    NSFont *result;
    @synchronized(self) {
        result = NS_EXTRA(NSFont, self)->_screenFonts[mode];
        if (result == nil) {
            // Not entered in the font cache: -fontWithName:size: keeps returning the ordinary font.
            result = [[[self class] alloc] init];
            result->_name = [_name copy];
            result->_pointSize = _pointSize;
            memcpy(NS_EXTRA(NSFont, result)->_matrix, NS_EXTRA(NSFont, self)->_matrix,
                   sizeof(NS_EXTRA(NSFont, self)->_matrix));
            NS_EXTRA(NSFont, result)->_encoding = NS_EXTRA(NSFont, self)->_encoding;
            NS_EXTRA(NSFont, result)->_cgFont = CGFontRetain(NS_EXTRA(NSFont, self)->_cgFont);
            NS_EXTRA(NSFont, result)->_ctFont = (CTFontRef) [(id) NS_EXTRA(NSFont, self)->_ctFont retain];
            NS_EXTRA(NSFont, result)->_isScreenFont = YES;
            NS_EXTRA(NSFont, result)->_renderingMode = mode;
            NS_EXTRA(NSFont, self)->_screenFonts[mode] = result;
        }
    }
    return result;
}

// The CTFont behind this font, for CoreText functions given an NSFont.
- (CTFontRef) _coreTextFont {
    return NS_EXTRA(NSFont, self)->_ctFont;
}

- (NSRect) boundingRectForFont {
    return CTFontGetBoundingBox(NS_EXTRA(NSFont, self)->_ctFont);
}

- (NSRect) boundingRectForGlyph: (NSGlyph) glyph {
    NSUnimplementedMethod();
    return NSMakeRect(0, 0, 0, 0);
}

- (NSMultibyteGlyphPacking) glyphPacking {
    return NSNativeShortGlyphPacking;
}

- (NSUInteger) numberOfGlyphs {
    return CTFontGetGlyphCount(NS_EXTRA(NSFont, self)->_ctFont);
}

- (NSGlyph) glyphWithName: (NSString *) name {
    NSUnimplementedMethod();
    return 0;
}

- (BOOL) glyphIsEncoded: (NSGlyph) glyph {
    return (glyph < CTFontGetGlyphCount(NS_EXTRA(NSFont, self)->_ctFont)) ? YES : NO;
}

- (NSSize) advancementForGlyph: (NSGlyph) glyph {
    CGSize cgSize;
    CGGlyph cgGlyphs[1] = {glyph};

    CTFontGetAdvancesForGlyphs(NS_EXTRA(NSFont, self)->_ctFont, 0, cgGlyphs, &cgSize, 1);

    if (fontUsesIntegerAdvancements(self))
        cgSize.width = floor(cgSize.width + 0.5);
    return NSMakeSize(cgSize.width, cgSize.height);
}

- (NSSize) maximumAdvancement {
    CGSize max = CGSizeZero;
    NSInteger glyph, glyphCount = CTFontGetGlyphCount(NS_EXTRA(NSFont, self)->_ctFont);
    CGGlyph glyphs[glyphCount];
    CGSize advances[glyphCount];

    for (glyph = 0; glyph < glyphCount; glyph++)
        glyphs[glyph] = glyph;

    CTFontGetAdvancesForGlyphs(NS_EXTRA(NSFont, self)->_ctFont, 0, glyphs, advances, glyphCount);

    BOOL integerAdvancements = fontUsesIntegerAdvancements(self);
    for (glyph = 0; glyph < glyphCount; glyph++) {
        if (integerAdvancements)
            advances[glyph].width = floor(advances[glyph].width + 0.5);
        max.width = MAX(max.width, advances[glyph].width);
        max.height = MAX(max.height, advances[glyph].height);
    }

    return max;
}

- (CGFloat) underlinePosition {
    return CTFontGetUnderlinePosition(NS_EXTRA(NSFont, self)->_ctFont);
}

- (CGFloat) underlineThickness {
    return CTFontGetUnderlineThickness(NS_EXTRA(NSFont, self)->_ctFont);
}

- (CGFloat) ascender {
    return CTFontGetAscent(NS_EXTRA(NSFont, self)->_ctFont);
}

// CT & NS descender value have opposite value on Cocoa
- (CGFloat) descender {
    return -CTFontGetDescent(NS_EXTRA(NSFont, self)->_ctFont);
}

- (CGFloat) leading {
    return CTFontGetLeading(NS_EXTRA(NSFont, self)->_ctFont);
}

// The line height is the sum of the individually rounded ascent, descent and
// leading, not the rounded sum.
//
// QUIRK: the rounding is applied per component; for DejaVu Sans at 11.5 pt
// (ascent 10.675, descent 2.712, no leading) the height is 14, not 13.
// Evidence: black-box measurement of -[NSLayoutManager defaultLineHeightForFont:]
// on macOS 10.14.4 (tier 2) for all 23 sizes from 9 to 20 pt in 0.5 pt steps of
// DejaVu Sans (no line gap); the screen font gives the same height. Fonts with
// a line gap (Helvetica, Times-Roman and Courier on that system) have larger
// heights than their reported ascent, descent and leading add up to; that is
// not covered here.
// Test: appkit-screen-font-metrics
- (CGFloat) defaultLineHeightForFont {
    CTFontRef font = NS_EXTRA(NSFont, self)->_ctFont;
    return floor(CTFontGetAscent(font) + 0.5) + floor(CTFontGetDescent(font) + 0.5) + floor(CTFontGetLeading(font) + 0.5);
}

- (BOOL) isFixedPitch {
    // A font that declares itself fixed-pitch is, even if it has glyphs,
    // such as combining marks, with other advances.
    if (CTFontGetSymbolicTraits(NS_EXTRA(NSFont, self)->_ctFont) & kCTFontTraitMonoSpace)
        return YES;

    CGSize current;
    NSInteger glyph, glyphCount = CTFontGetGlyphCount(NS_EXTRA(NSFont, self)->_ctFont);
    CGGlyph glyphs[glyphCount];
    CGSize advances[glyphCount];

    for (glyph = 0; glyph < glyphCount; glyph++)
        glyphs[glyph] = glyph;

    CTFontGetAdvancesForGlyphs(NS_EXTRA(NSFont, self)->_ctFont, 0, glyphs, advances, glyphCount);
    current = advances[0];

    for (glyph = 1; glyph < glyphCount; glyph++) {
        if (advances[glyph].width != current.width ||
            advances[glyph].height != current.height)
            return NO;
    }

    return YES;
}

- (CGFloat) italicAngle {
    return CTFontGetSlantAngle(NS_EXTRA(NSFont, self)->_ctFont);
}

- (CGFloat) xHeight {
    return CTFontGetXHeight(NS_EXTRA(NSFont, self)->_ctFont);
}

- (CGFloat) capHeight {
    return CTFontGetCapHeight(NS_EXTRA(NSFont, self)->_ctFont);
}

- (void) setInContext: (NSGraphicsContext *) context {
    CGContextRef cgContext = [context graphicsPort];

    CGContextSetFont(cgContext, NS_EXTRA(NSFont, self)->_cgFont);
    CGContextSetFontSize(cgContext, _pointSize);

    CGAffineTransform textMatrix;

    // FIX, should check the focusView in the context instead of NSView's
    if ([[NSGraphicsContext currentContext] isFlipped])
        textMatrix = (CGAffineTransform){1, 0, 0, -1, 0, 0};
    else
        textMatrix = CGAffineTransformIdentity;

    CGContextSetTextMatrix(cgContext, textMatrix);
}

- (void) set {
    [self setInContext: [NSGraphicsContext currentContext]];
}

- (NSPoint) positionOfGlyph: (NSGlyph) current
            precededByGlyph: (NSGlyph) previous
                  isNominal: (BOOL *) isNominalp
{
    if (fontUsesIntegerAdvancements(self)) {
        // Whole-pixel advances of a screen font are not kerned.
        *isNominalp = YES;
        if (current == 0)
            return NSZeroPoint;
        return NSMakePoint([self advancementForGlyph: current].width, 0);
    }
    return [NS_EXTRA(NSFont, self)->_ctFont positionOfGlyph: current
                    precededByGlyph: previous
                          isNominal: isNominalp];
}

- (void) getAdvancements: (NSSize *) advancements
               forGlyphs: (const NSGlyph *) glyphs
                   count: (NSUInteger) count
{
    CGGlyph cgGlyphs[count];
    NSInteger i;

    for (i = 0; i < count; i++)
        cgGlyphs[i] = glyphs[i];

    CTFontGetAdvancesForGlyphs(NS_EXTRA(NSFont, self)->_ctFont, 0, cgGlyphs, advancements, count);

    if (fontUsesIntegerAdvancements(self))
        for (i = 0; i < count; i++)
            advancements[i].width = floor(advancements[i].width + 0.5);
}

- (void) getAdvancements: (NSSize *) advancements
         forPackedGlyphs: (const void *) packed
                  length: (NSUInteger) length
{
    CTFontGetAdvancesForGlyphs(NS_EXTRA(NSFont, self)->_ctFont, 0, packed, advancements, length);

    if (fontUsesIntegerAdvancements(self))
        for (NSUInteger i = 0; i < length; i++)
            advancements[i].width = floor(advancements[i].width + 0.5);
}

- (void) getBoundingRects: (NSRect *) rects
                forGlyphs: (const NSGlyph *) glyphs
                    count: (NSUInteger) count
{
    NSUnimplementedMethod();
}

- (NSUInteger) getGlyphs: (NSGlyph *) glyphs
           forCharacters: (unichar *) characters
                  length: (NSUInteger) length
{
    CGGlyph cgGlyphs[length];
    NSInteger i;

    CTFontGetGlyphsForCharacters(NS_EXTRA(NSFont, self)->_ctFont, characters, cgGlyphs, length);

    for (i = 0; i < length; i++) {
        unichar check = characters[i];

        if (check < ' ' || (check >= 0x7F && check <= 0x9F) ||
            check == 0x200B || check == 0x2028 || check == 0x2029)
            glyphs[i] = NSControlGlyph;
        else
            glyphs[i] = cgGlyphs[i];
    }

    return length;
}

// Private AppKit method that apps call: the glyph the font maps a
// character to, or 0 (.notdef) when it has none.
- (NSGlyph) _defaultGlyphForChar: (unichar) character {
    CGGlyph glyph = 0;
    CTFontGetGlyphsForCharacters(NS_EXTRA(NSFont, self)->_ctFont, &character, &glyph, 1);
    return glyph;
}

- (NSString *) description {
    return [NSString
            stringWithFormat: @"<%@ %@ %f>", [self class], _name, _pointSize];
}

- (id) _metaType {
    NSUnimplementedMethod();
    return nil;
}

@end

// CTFontRef and NSFont are toll-free bridged, so a font made with a CoreText
// function may be used as an NSFont. CoreText's font object answers NSFont's
// metric and glyph messages itself; it sends every other NSFont message to an
// NSFont that draws with the very same CTFont, so the font keeps the
// descriptor (features, variations) it was made with.
@implementation NSFont (CoreTextFonts)

+ (NSFont *) _fontWithCoreTextFont: (CTFontRef) ctFont {
    CGFontRef cgFont = CTFontCopyGraphicsFont(ctFont, NULL);
    if (cgFont == NULL)
        return nil;
    // Not entered in the font cache, like the screen fonts.
    NSFont *font = [[self alloc] init];
    font->_name = (NSString *) CTFontCopyPostScriptName(ctFont);
    font->_pointSize = CTFontGetSize(ctFont);
    NS_EXTRA(NSFont, font)->_matrix[0] = font->_pointSize;
    NS_EXTRA(NSFont, font)->_matrix[3] = font->_pointSize;
    NS_EXTRA(NSFont, font)->_encoding = NSUnicodeStringEncoding;
    NS_EXTRA(NSFont, font)->_cgFont = cgFont;
    NS_EXTRA(NSFont, font)->_ctFont = (CTFontRef) [(id) ctFont retain];
    return [font autorelease];
}

@end

@implementation KTFont (NSFontMessages)

- (id) forwardingTargetForSelector: (SEL) selector {
    if ([NSFont instancesRespondToSelector: selector]) {
        NSFont *font = [NSFont _fontWithCoreTextFont: (CTFontRef) self];
        if (font != nil)
            return font;
    }
    return [super forwardingTargetForSelector: selector];
}

- (BOOL) respondsToSelector: (SEL) selector {
    return [super respondsToSelector: selector] ||
           [NSFont instancesRespondToSelector: selector];
}

@end

#ifndef DARLING
@implementation NSFont (PortatibilityAdditions)

+ (void) setNibFontTranslator: (NSNibFontNameTranslator *) fontTranslator {
    [fontTranslator retain];
    [_nibFontTranslator release];
    _nibFontTranslator = fontTranslator;
}

+ (NSNibFontNameTranslator *) nibFontTranslator {
    return _nibFontTranslator;
}

@end
#endif
