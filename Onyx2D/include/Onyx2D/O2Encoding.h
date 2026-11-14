#import <Foundation/NSObject.h>
#import <Onyx2D/O2Font.h>

@class NSData;

@interface O2Encoding : NSObject <NSCopying, NSMutableCopying> {
    O2Glyph _glyphs[256];
    unichar _unicode[256];
    // Two-byte CID encoding (Identity-H/V of a Type0 font): each pair of bytes
    // is a CID, mapped to a glyph through _cidToGID (nil: the CID is the glyph).
    BOOL _isCID;
    NSData *_cidToGID;
}

- initWithGlyphs: (const O2Glyph *) glyphs unicode: (uint16_t *) unicode;
// cidToGIDMap: the CIDToGIDMap stream data (big-endian glyph per CID), nil for Identity.
- initWithCIDToGIDMap: (NSData *) cidToGIDMap;

- (void) getGlyphs: (O2Glyph *) glyphs;
- (void) getUnicode: (uint16_t *) unicode;

void O2EncodingGetGlyphsForBytes(O2Encoding *self, O2Glyph *glyphs,
                                 const uint8_t *bytes, unsigned length);
void O2EncodingGetUnicodeForBytes(O2Encoding *self, uint16_t *unicode,
                                  const uint8_t *bytes, unsigned length);
// Glyphs in length bytes of text: the number of entries the two functions
// above write. A trailing odd byte of a CID string is ignored.
unsigned O2EncodingGetGlyphCountForBytes(O2Encoding *self, unsigned length);

void O2EncodingGetMacRomanUnicode(unichar *codes);
void O2EncodingGetMacExpertUnicode(unichar *codes);
void O2EncodingGetWinAnsiUnicode(unichar *codes);

@end

@interface O2MutableEncoding : O2Encoding

- (void) setGlyph: (O2Glyph) glyph
          unicode: (uint16_t) code
          atIndex: (int) index;

@end
