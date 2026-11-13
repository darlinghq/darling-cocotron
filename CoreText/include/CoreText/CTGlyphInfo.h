#ifndef COCORETEXT_CTGLYPHINFO_H
#define COCORETEXT_CTGLYPHINFO_H

#import <CoreText/CTFont.h>
#import <CoreText/CoreTextExport.h>
#import <CoreGraphics/CGFont.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef const struct CF_BRIDGED_TYPE(id) __CTGlyphInfo *CTGlyphInfoRef;

// Character collections: the numbering is part of the documented contract.
typedef CF_ENUM(uint16_t, CTCharacterCollection) {
    kCTCharacterCollectionIdentityMapping = 0,
    kCTCharacterCollectionAdobeCNS1 = 1,
    kCTCharacterCollectionAdobeGB1 = 2,
    kCTCharacterCollectionAdobeJapan1 = 3,
    kCTCharacterCollectionAdobeJapan2 = 4,
    kCTCharacterCollectionAdobeKorea1 = 5,
    kCTIdentityMappingCharacterCollection = kCTCharacterCollectionIdentityMapping,
    kCTAdobeCNS1CharacterCollection = kCTCharacterCollectionAdobeCNS1,
    kCTAdobeGB1CharacterCollection = kCTCharacterCollectionAdobeGB1,
    kCTAdobeJapan1CharacterCollection = kCTCharacterCollectionAdobeJapan1,
    kCTAdobeJapan2CharacterCollection = kCTCharacterCollectionAdobeJapan2,
    kCTAdobeKorea1CharacterCollection = kCTCharacterCollectionAdobeKorea1,
};

CORETEXT_EXPORT CFTypeID CTGlyphInfoGetTypeID(void);

CORETEXT_EXPORT CTGlyphInfoRef _Nullable CTGlyphInfoCreateWithGlyphName(
    CFStringRef glyphName, CTFontRef font, CFStringRef baseString);
CORETEXT_EXPORT CTGlyphInfoRef _Nullable CTGlyphInfoCreateWithGlyph(
    CGGlyph glyph, CTFontRef font, CFStringRef baseString);
CORETEXT_EXPORT CTGlyphInfoRef _Nullable CTGlyphInfoCreateWithCharacterIdentifier(
    CGFontIndex cid, CTCharacterCollection collection, CFStringRef baseString);

CORETEXT_EXPORT CFStringRef _Nullable CTGlyphInfoGetGlyphName(CTGlyphInfoRef glyphInfo);
CORETEXT_EXPORT CGGlyph CTGlyphInfoGetGlyph(CTGlyphInfoRef glyphInfo);
CORETEXT_EXPORT CGFontIndex CTGlyphInfoGetCharacterIdentifier(CTGlyphInfoRef glyphInfo);
CORETEXT_EXPORT CTCharacterCollection CTGlyphInfoGetCharacterCollection(CTGlyphInfoRef glyphInfo);

CF_IMPLICIT_BRIDGING_DISABLED

#endif
