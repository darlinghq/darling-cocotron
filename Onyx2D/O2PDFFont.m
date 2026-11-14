#import <Onyx2D/O2Encoding.h>
#import <Onyx2D/O2Font.h>
#import <Onyx2D/O2PDFCharWidths.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFFont.h>
#import <Onyx2D/O2PDFObject_Name.h>

@implementation O2PDFFont

// The font program embedded in a font descriptor (FontFile, FontFile2 or
// FontFile3), or nil.
static O2Font *createFontFromDescriptor(O2PDFDictionary *fontDescriptor) {
    O2PDFStream *fontStream = NULL;
    const char *key;

    if ([fontDescriptor getStreamForKey: "FontFile" value: &fontStream])
        key = "FontFile";
    else if ([fontDescriptor getStreamForKey: "FontFile2" value: &fontStream])
        key = "FontFile2";
    else if ([fontDescriptor getStreamForKey: "FontFile3" value: &fontStream]) {
        const char *name;

        key = "FontFile3";
        if (![[fontStream dictionary] getNameForKey: "Subtype" value: &name])
            O2PDFError(__FILE__, __LINE__, @"No Subtype on FontFile3 stream");
    } else
        return nil;

    NSData *data = [fontStream data];

    if (data == nil) {
        O2PDFError(__FILE__, __LINE__, @"No data on %s stream", key);
        return nil;
    }

    O2DataProviderRef provider = O2DataProviderCreateWithCFData((CFDataRef) data);
    O2Font *font = O2FontCreateWithDataProvider(provider);

    O2DataProviderRelease(provider);
    return font;
}

// A Type0 (composite) font: its glyphs and widths come from its CIDFont, the
// single entry of DescendantFonts. Supported: the Identity-H CMap (each pair of
// bytes is a CID) with a CIDFontType2 (TrueType) font program, the CIDs mapped
// to glyphs by CIDToGIDMap. Returns NO for anything else.
- (BOOL) loadType0Font: (O2PDFDictionary *) dictionary {
    const char *cmap;
    const char *subtype = NULL;
    O2PDFArray *descendants;
    O2PDFDictionary *cidFont;
    O2PDFDictionary *fontDescriptor;
    O2PDFArray *widths = NULL;
    O2PDFReal defaultWidth = 1000;
    O2PDFObject *map;
    NSData *cidToGID = nil;

    if (![dictionary getNameForKey: "Encoding" value: &cmap] ||
        strcmp(cmap, "Identity-H") != 0) {
        O2PDFError(__FILE__, __LINE__, @"Type0 font: only the Identity-H CMap is implemented");
        return NO;
    }
    if (![dictionary getArrayForKey: "DescendantFonts" value: &descendants] ||
        ![descendants getDictionaryAtIndex: 0 value: &cidFont]) {
        O2PDFError(__FILE__, __LINE__, @"Type0 font without DescendantFonts");
        return NO;
    }
    if (![cidFont getNameForKey: "Subtype" value: &subtype] ||
        strcmp(subtype, "CIDFontType2") != 0) {
        O2PDFError(__FILE__, __LINE__, @"Type0 font: CIDFont subtype %s unimplemented",
                   subtype ? subtype : "(none)");
        return NO;
    }
    // The glyph numbers belong to the embedded TrueType program: without it
    // there is nothing they could index.
    if (![cidFont getDictionaryForKey: "FontDescriptor" value: &fontDescriptor] ||
        (_resourceFont = createFontFromDescriptor(fontDescriptor)) == nil) {
        O2PDFError(__FILE__, __LINE__, @"Type0 font: CIDFontType2 is not embedded");
        return NO;
    }

    [cidFont getNumberForKey: "DW" value: &defaultWidth];
    [cidFont getArrayForKey: "W" value: &widths];
    if ([cidFont getObjectForKey: "CIDToGIDMap" value: &map]) {
        O2PDFStream *stream;

        if ([map checkForType: kO2PDFObjectTypeStream value: &stream])
            cidToGID = [stream data];
        // Otherwise the name Identity: the CID is the glyph.
    }

    _encoding = [[O2Encoding alloc] initWithCIDToGIDMap: cidToGID];
    _pdfCharWidths = [[O2PDFCharWidths alloc] initWithCIDWidths: widths
                                                   defaultWidth: defaultWidth];
    return YES;
}

static inline O2TextEncoding textEncodingWithName(const char *name) {
    if (strcmp(name, "MacRomanEncoding") == 0)
        return kO2EncodingMacRoman;
    else if (strcmp(name, "MacExpertEncoding") == 0)
        return kO2EncodingMacExpert;
    else if (strcmp(name, "WinAnsiEncoding") == 0)
        return kO2EncodingWinAnsi;
    else {
        O2PDFError(__FILE__, __LINE__, @"Unknown encoding %s", name);
        return kO2EncodingMacRoman;
    }
}

- initWithPDFDictionary: (O2PDFDictionary *) dictionary {
    const char *name;
    const char *subtype;
    O2PDFInteger firstChar = -1;
    O2PDFInteger lastChar = -1;
    O2PDFArray *widthsArray = NULL;
    O2PDFDictionary *fontDescriptor = NULL;
    O2PDFObject *encoding = NULL;
    O2PDFStream *toUnicode = NULL;
    O2TextEncoding textEncoding = 0;
    O2Float missingWidth = 0;
    const char *fontName = NULL;
    O2PDFArray *differences = NULL;

    _baseFont = "Arial";

    if ([dictionary getNameForKey: "Type" value: &name])
        if (strcmp(name, "Font") != 0) {
            O2PDFError(__FILE__, __LINE__,
                       @"Type dictionary in Font resource is wrong %s", name);
            return nil;
        }

    if (![dictionary getNameForKey: "Subtype" value: &subtype]) {
        O2PDFError(__FILE__, __LINE__,
                   @"Font dictionary does not contain Subtype");
        return nil;
    }

    if (![dictionary getIntegerForKey: "FirstChar" value: &firstChar]) {
    }
    if (![dictionary getIntegerForKey: "LastChar" value: &lastChar]) {
    }

    if ([dictionary getDictionaryForKey: "FontDescriptor"
                                  value: &fontDescriptor]) {
        [fontDescriptor getNumberForKey: "MissingWidth" value: &missingWidth];

        [fontDescriptor getNameForKey: "FontName" value: &fontName];

        _resourceFont = createFontFromDescriptor(fontDescriptor);
    }

    if ([dictionary getArrayForKey: "Widths" value: &widthsArray])
        _pdfCharWidths = [[O2PDFCharWidths alloc] initWithArray: widthsArray
                                                      firstChar: firstChar
                                                       lastChar: lastChar
                                                   missingWidth: missingWidth];

    if (strcmp(subtype, "Type0") != 0 &&
        [dictionary getObjectForKey: "Encoding" value: &encoding]) {
        if ([encoding objectType] == kO2PDFObjectTypeName) {
            const char *name = [(O2PDFObject_Name *) encoding name];

            textEncoding = textEncodingWithName(name);
        } else if ([encoding objectType] == kO2PDFObjectTypeDictionary) {
            O2PDFDictionary *encodingDictionary = (O2PDFDictionary *) encoding;
            const char *baseEncoding = NULL;

            if ([encodingDictionary getNameForKey: "BaseEncoding"
                                            value: &baseEncoding])
                textEncoding = textEncodingWithName(baseEncoding);

            [encodingDictionary getArrayForKey: "Differences"
                                         value: &differences];
        } else {
            O2PDFError(__FILE__, __LINE__,
                       @"encoding dictionary is wrong type = %d",
                       [encoding objectType]);
        }
    }

    if (![dictionary getStreamForKey: "ToUnicode" value: &toUnicode]) {
    }

    if (strcmp(subtype, "Type0") == 0) {
        [self loadType0Font: dictionary];
    } else if (strcmp(subtype, "Type1") == 0) {

        if (![dictionary getNameForKey: "BaseFont" value: &_baseFont]) {
            O2PDFError(__FILE__, __LINE__, @"No BaseFont present");
            return nil;
        }
    } else if (strcmp(subtype, "MMType1") == 0) {
        O2PDFError(__FILE__, __LINE__, @"Font subtype %s unimplemented",
                   subtype);
    } else if (strcmp(subtype, "Type3") == 0) {
        O2PDFError(__FILE__, __LINE__, @"Font subtype %s unimplemented",
                   subtype);
    } else if (strcmp(subtype, "TrueType") == 0) {

        if (![dictionary getNameForKey: "BaseFont" value: &_baseFont]) {
            O2PDFError(__FILE__, __LINE__,
                       @"TrueType font dictionary does not have BaseFont");
            return nil;
        }
    } else if (strcmp(subtype, "CIDFontType0") == 0) {
        O2PDFError(__FILE__, __LINE__, @"Font subtype %s unimplemented",
                   subtype);
    } else if (strcmp(subtype, "CIDFontType2") == 0) {
        O2PDFError(__FILE__, __LINE__, @"Font subtype %s unimplemented",
                   subtype);
    } else {
        O2PDFError(__FILE__, __LINE__, @"Font subtype %s unimplemented",
                   subtype);
    }

    if (_resourceFont != nil)
        _graphicsFont = [_resourceFont retain];
    else
        _graphicsFont = O2FontCreateWithFontName([NSString
                stringWithCString: _baseFont
                         encoding: NSUTF8StringEncoding]);

    if (_encoding == nil)
        _encoding = [_graphicsFont createEncodingForTextEncoding: textEncoding];

    if (differences != NULL) {
        O2MutableEncoding *newEncoding = [_encoding mutableCopy];
        int i, count = [differences count];
        O2PDFInteger currentIndex = 0;

        for (i = 0; i < count; i++) {
            O2PDFObject *check = [differences objectAtIndex: i];
            const char *name;

            if ([check checkForType: kO2PDFObjectTypeInteger
                              value: &currentIndex])
                ;
            else if ([check checkForType: kO2PDFObjectTypeName value: &name]) {
                NSString *string = [[NSString alloc] initWithCString: name];

                O2Glyph glyph = O2FontGetGlyphWithGlyphName(
                        _graphicsFont, (CFStringRef) string);
                uint16_t unicode =
                        O2FontUnicodeForGlyphName((CFStringRef) string);

                [newEncoding setGlyph: glyph
                              unicode: unicode
                              atIndex: currentIndex];

                currentIndex++;
            } else {
                O2PDFError(__FILE__, __LINE__,
                           @"Invalid type (%d) in PDF font differences array",
                           [check objectType]);
            }
        }
        [_encoding release];
        _encoding = newEncoding;
    }

    return self;
}

- (void) dealloc {
    [_info release];
    [_resourceFont release];
    [_graphicsFont release];
    [_encoding release];
    [_pdfCharWidths release];
    [super dealloc];
}

+ (O2PDFFont *) createWithPDFDictionary: (O2PDFDictionary *) info {
    return [[self alloc] initWithPDFDictionary: info];
}

- (O2PDFObject *) realObject {
    return self;
}

- (O2PDFObjectType) objectType {
    return O2PDFObjectTypeCached;
}

- (O2Encoding *) encoding {
    return _encoding;
}

- (O2PDFCharWidths *) pdfCharWidths {
    return _pdfCharWidths;
}

- (O2Font *) graphicsFont {
    return _graphicsFont;
}

@end
