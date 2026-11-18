/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSMutableAttributedString.h>
#import <AppKit/NSMutableParagraphStyle.h>
#import <CoreText/CoreText.h>

@implementation NSMutableAttributedString (NSMutableAttributedString_AppKit)

// The font that displays the text in the range of the characters when the
// font does not: the one CoreText picks for it, in the style and size of the
// given font. nil when no installed font covers the text.
- (NSFont *) _substituteFontForText: (NSString *) text userFont: (NSFont *) font {
    CTFontRef covering = CTFontCreateForString((CTFontRef) font, (CFStringRef) text,
                                               CFRangeMake(0, [text length]));
    if (covering == NULL)
        return nil;
    NSString *name = (NSString *) CTFontCopyPostScriptName(covering);
    NSFont *substitute = name != nil ? [NSFont fontWithName: name size: [font pointSize]] : nil;
    [name release];
    CFRelease(covering);
    return substitute;
}

- (void) fixFontAttributeInRange: (NSRange) range {
    NSString *string = [self string];
    unsigned location = range.location;
    unsigned limit = NSMaxRange(range);

    // Check that all of the chars in the range are supported by the font
    // attribute Else, change the font attribute to one supporting these chars
    NSCharacterSet *blankChars =
            [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSCharacterSet *controlChars = [NSCharacterSet controlCharacterSet];
    while (location < limit) {
        NSRange effectiveRange;
        NSFont *font = [self attribute: NSFontAttributeName
                               atIndex: location
                        effectiveRange: &effectiveRange];
        if (font == nil) {
            // We really need a font for doing font substitution
            // Use the default attribute value
            // Note that if no substitution is needed, then we'll keep the no
            // font info
            font = NSFontAttributeInDictionary(nil);
        }
        if (font) {
            NSCharacterSet *fontCharSet = nil;
            NSRange testRange = NSIntersectionRange(range, effectiveRange);
            unichar *chars = malloc(sizeof(unichar) * testRange.length);
            if (chars) {
                [string getCharacters: chars range: testRange];
                for (int i = 0; i < testRange.length; ++i) {
                    unichar charToTest = chars[i];
                    NSUInteger units = 1;
                    // A surrogate pair is one character.
                    if (charToTest >= 0xD800 && charToTest <= 0xDBFF && i + 1 < testRange.length &&
                        chars[i + 1] >= 0xDC00 && chars[i + 1] <= 0xDFFF)
                        units = 2;
                    // No need to process blanks
                    if ([blankChars characterIsMember: charToTest] == NO &&
                        [controlChars characterIsMember: charToTest] == NO) {
                        if (fontCharSet == nil) {
                            fontCharSet = [font coveredCharacterSet];
                        }
                        CGGlyph glyphs[2];
                        BOOL covered = units == 1 ? [fontCharSet characterIsMember: charToTest]
                                : CTFontGetGlyphsForCharacters((CTFontRef) font, chars + i, glyphs, 2);
                        NSFont *substitute = nil;
                        if (!covered) {
                            NSString *character = [string substringWithRange:
                                    NSMakeRange(i + testRange.location, units)];
                            substitute = [self _substituteFontForText: character userFont: font];
                        }
                        if (substitute != nil) {
                            [self addAttribute: NSFontAttributeName
                                         value: substitute
                                         range: NSMakeRange(i + testRange.location, units)];
                        }
                    }
                    i += units - 1;
                }
                free(chars);
            }
        }
        location = NSMaxRange(effectiveRange);
    }
}

- (void) fixParagraphStyleAttributeInRange: (NSRange) range {
    // TODO :
    /**
     Fixes the paragraph style attributes in aRange, assigning the first
     paragraph style attribute value in each paragraph to all characters of the
     paragraph. This method extends the range as needed to cover the last
     paragraph partially contained. A paragraph is delimited by any of these
     characters, the longest possible sequence being preferred to any shorter:
     U+000D (\r or CR)
     U+000A (\n or LF)
     U+2028 (Unicode line separator)
     U+2029 (Unicode paragraph separator) \r\n, in that order (also known as
     CRLF)
     */
}

- (void) fixAttributesInRange: (NSRange) range {
    [self fixFontAttributeInRange: range];
    [self fixParagraphStyleAttributeInRange: range];
}

- (void) invalidateAttributesInRange: (NSRange) range {
    [self fixAttributesInRange: range];
}

- (void) applyFontTraits: (NSFontTraitMask) traits range: (NSRange) range {
    unsigned location = range.location;
    unsigned limit = NSMaxRange(range);

    [self beginEditing];

    while (location < limit) {
        NSRange effectiveRange;
        NSMutableDictionary *attributes = [[[self
                attributesAtIndex: location
                   effectiveRange: &effectiveRange] mutableCopy] autorelease];
        NSFont *font = NSFontAttributeInDictionary(attributes);

        font = [[NSFontManager sharedFontManager] convertFont: font
                                                  toHaveTrait: traits];
        [attributes setObject: font forKey: NSFontAttributeName];

        if (effectiveRange.location < location) {
            effectiveRange.length = NSMaxRange(effectiveRange) - location;
            effectiveRange.location = location;
        }
        if (NSMaxRange(effectiveRange) > limit)
            effectiveRange.length = limit - effectiveRange.location;

        [self setAttributes: attributes range: effectiveRange];

        location = NSMaxRange(effectiveRange);
    }
    [self endEditing];
}

- (void) setBaseWritingDirection: (NSWritingDirection) direction
                           range: (NSRange) range
{
    NSUInteger end = NSMaxRange(range);
    if (end > [self length])
        [NSException raise: NSRangeException
                    format: @"%@: range %@ beyond length %lu",
                            NSStringFromSelector(_cmd),
                            NSStringFromRange(range),
                            (unsigned long) [self length]];

    [self beginEditing];
    NSUInteger location = range.location;
    while (location < end) {
        NSRange effectiveRange;
        NSParagraphStyle *style = [self attribute: NSParagraphStyleAttributeName
                                          atIndex: location
                                   effectiveRange: &effectiveRange];
        effectiveRange = NSIntersectionRange(
                effectiveRange, NSMakeRange(location, end - location));
        NSMutableParagraphStyle *changed =
                [(style ? style : [NSParagraphStyle defaultParagraphStyle])
                        mutableCopy];
        [changed setBaseWritingDirection: direction];
        [self addAttribute: NSParagraphStyleAttributeName
                     value: changed
                     range: effectiveRange];
        [changed release];
        location = NSMaxRange(effectiveRange);
    }
    [self endEditing];
}

- (BOOL) readFromURL: (NSURL *) url
             options: (NSDictionary<NSAttributedStringDocumentReadingOptionKey, id> *) opts
  documentAttributes: (NSDictionary<NSAttributedStringDocumentAttributeKey, id> *_Nullable *) dict
               error: (NSError *_Nullable *) error
{
    NSAttributedString *str = [NSAttributedString alloc];
    str = [str initWithURL: url
                   options: opts
        documentAttributes: dict
                     error: error];
    if (str == nil) {
        return NO;
    }
    [self setAttributedString: str];
    [str release];
    return YES;
}

@end
