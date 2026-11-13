/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * This file is part of Darling.
 */
#import <CoreText/CTGlyphInfo.h>
#import <CoreText/CTStringAttributes.h>
#import <Foundation/Foundation.h>

// A glyph info describes one override for a run of base characters: a glyph
// name, a glyph index, or a character identifier within a collection. It is
// immutable, so copying it returns the same object.
@interface KTGlyphInfo : NSObject <NSCopying> {
    NSString *_glyphName;
    NSString *_baseString;
    id _font;
    CGGlyph _glyph;
    CGFontIndex _cid;
    CTCharacterCollection _collection;
}
- initWithGlyphName: (NSString *) name
               font: (id) font
         baseString: (NSString *) baseString;
- initWithGlyph: (CGGlyph) glyph
           font: (id) font
     baseString: (NSString *) baseString;
- initWithCharacterIdentifier: (CGFontIndex) cid
                   collection: (CTCharacterCollection) collection
                   baseString: (NSString *) baseString;
- (NSString *) glyphName;
- (CGGlyph) glyph;
- (CGFontIndex) characterIdentifier;
- (CTCharacterCollection) characterCollection;
@end

static BOOL objectsEqual(id a, id b) {
    return a == b || (a != nil && b != nil && [a isEqual: b]);
}

@implementation KTGlyphInfo

- initWithGlyphName: (NSString *) name
               font: (id) font
         baseString: (NSString *) baseString {
    self = [super init];
    if (self == nil)
        return nil;
    _glyphName = [name copy];
    _font = [font retain];
    _baseString = [baseString copy];
    _collection = kCTCharacterCollectionIdentityMapping;
    return self;
}

- initWithGlyph: (CGGlyph) glyph
           font: (id) font
     baseString: (NSString *) baseString {
    self = [super init];
    if (self == nil)
        return nil;
    _glyph = glyph;
    _font = [font retain];
    _baseString = [baseString copy];
    _collection = kCTCharacterCollectionIdentityMapping;
    return self;
}

- initWithCharacterIdentifier: (CGFontIndex) cid
                   collection: (CTCharacterCollection) collection
                   baseString: (NSString *) baseString {
    self = [super init];
    if (self == nil)
        return nil;
    _cid = cid;
    _collection = collection;
    _baseString = [baseString copy];
    return self;
}

- (void) dealloc {
    [_glyphName release];
    [_baseString release];
    [_font release];
    [super dealloc];
}

- (CFTypeID) _cfTypeID {
    return CTGlyphInfoGetTypeID();
}

- copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (BOOL) isEqual: (id) other {
    if (other == self)
        return YES;
    if (![other isKindOfClass: [KTGlyphInfo class]])
        return NO;
    KTGlyphInfo *info = other;
    return _glyph == info->_glyph && _cid == info->_cid &&
           _collection == info->_collection &&
           objectsEqual(_glyphName, info->_glyphName) &&
           objectsEqual(_baseString, info->_baseString) &&
           objectsEqual(_font, info->_font);
}

- (NSUInteger) hash {
    return [_glyphName hash] ^ [_baseString hash] ^ _glyph ^
           ((NSUInteger) _cid << 16) ^ ((NSUInteger) _collection << 8);
}

- (NSString *) glyphName {
    return _glyphName;
}

- (CGGlyph) glyph {
    return _glyph;
}

- (CGFontIndex) characterIdentifier {
    return _cid;
}

- (CTCharacterCollection) characterCollection {
    return _collection;
}

@end

CFTypeID CTGlyphInfoGetTypeID(void) {
    return (CFTypeID) [KTGlyphInfo self];
}

// The creators reject NULL arguments. They do not look the glyph up in the
// font: macOS versions differ on that, and the widest behaviour is to accept.
CTGlyphInfoRef CTGlyphInfoCreateWithGlyphName(CFStringRef glyphName, CTFontRef font,
                                              CFStringRef baseString) {
    if (glyphName == NULL || font == NULL || baseString == NULL)
        return NULL;
    return (CTGlyphInfoRef) [[KTGlyphInfo alloc] initWithGlyphName: (NSString *) glyphName
                                                               font: (id) font
                                                         baseString: (NSString *) baseString];
}

CTGlyphInfoRef CTGlyphInfoCreateWithGlyph(CGGlyph glyph, CTFontRef font, CFStringRef baseString) {
    if (font == NULL || baseString == NULL)
        return NULL;
    return (CTGlyphInfoRef) [[KTGlyphInfo alloc] initWithGlyph: glyph
                                                           font: (id) font
                                                     baseString: (NSString *) baseString];
}

CTGlyphInfoRef CTGlyphInfoCreateWithCharacterIdentifier(CGFontIndex cid,
                                                        CTCharacterCollection collection,
                                                        CFStringRef baseString) {
    if (baseString == NULL || collection > kCTCharacterCollectionAdobeKorea1)
        return NULL;
    return (CTGlyphInfoRef) [[KTGlyphInfo alloc] initWithCharacterIdentifier: cid
                                                                   collection: collection
                                                                   baseString: (NSString *) baseString];
}

CFStringRef CTGlyphInfoGetGlyphName(CTGlyphInfoRef glyphInfo) {
    return (CFStringRef) [(KTGlyphInfo *) glyphInfo glyphName];
}

CGGlyph CTGlyphInfoGetGlyph(CTGlyphInfoRef glyphInfo) {
    return [(KTGlyphInfo *) glyphInfo glyph];
}

CGFontIndex CTGlyphInfoGetCharacterIdentifier(CTGlyphInfoRef glyphInfo) {
    return [(KTGlyphInfo *) glyphInfo characterIdentifier];
}

CTCharacterCollection CTGlyphInfoGetCharacterCollection(CTGlyphInfoRef glyphInfo) {
    return [(KTGlyphInfo *) glyphInfo characterCollection];
}
