/* Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. */

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSRichTextReader.h>
#import <AppKit/NSRichTextWriter.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSTextAttachment.h>

NSString *const NSFontAttributeName = @"NSFontAttributeName";
NSString *const NSParagraphStyleAttributeName =
    @"NSParagraphStyleAttributeName";
NSString *const NSForegroundColorAttributeName =
    @"NSForegroundColorAttributeName";
NSString *const NSBackgroundColorAttributeName =
    @"NSBackgroundColorAttributeName";
NSString *const NSUnderlineStyleAttributeName =
    @"NSUnderlineStyleAttributeName";
NSString *const NSUnderlineColorAttributeName =
    @"NSUnderlineColorAttributeName";
NSString *const NSAttachmentAttributeName = @"NSAttachmentAttributeName";
NSString *const NSKernAttributeName = @"NSKernAttributeName";
NSString *const NSLigatureAttributeName = @"NSLigatureAttributeName";
NSString *const NSStrikethroughStyleAttributeName =
    @"NSStrikethroughStyleAttributeName";
NSString *const NSStrikethroughColorAttributeName =
    @"NSStrikethroughColorAttributeName";
NSString *const NSObliquenessAttributeName = @"NSObliquenessAttributeName";
NSString *const NSStrokeWidthAttributeName = @"NSStrokeWidthAttributeName";
NSString *const NSStrokeColorAttributeName = @"NSStrokeColorAttributeName";
NSString *const NSBaselineOffsetAttributeName =
    @"NSBaselineOffsetAttributeName";
NSString *const NSSuperscriptAttributeName = @"NSSuperscriptAttributeName";
NSString *const NSLinkAttributeName = @"NSLinkAttributeName";
NSString *const NSShadowAttributeName = @"NSShadowAttributeName";
NSString *const NSExpansionAttributeName = @"NSExpansionAttributeName";
NSString *const NSCursorAttributeName = @"NSCursorAttributeName";
NSString *const NSToolTipAttributeName = @"NSToolTipAttributeName";
NSString *const NSSpellingStateAttributeName =
    @"NSSpellingStateAttributeName"; // temporary attribute

NSString *const NSDocumentTypeDocumentAttribute = @"DocumentType";
NSString *const NSConvertedDocumentAttribute = @"Converted";
NSString *const NSFileTypeDocumentAttribute = @"UTI";
NSString *const NSTitleDocumentAttribute = @"NSTitleDocumentAttribute";
NSString *const NSCompanyDocumentAttribute = @"NSCompanyDocumentAttribute";
NSString *const NSCopyrightDocumentAttribute = @"NSCopyrightDocumentAttribute";
NSString *const NSSubjectDocumentAttribute = @"NSSubjectDocumentAttribute";
NSString *const NSAuthorDocumentAttribute = @"NSAuthorDocumentAttribute";
NSString *const NSKeywordsDocumentAttribute = @"NSKeywordsDocumentAttribute";
NSString *const NSCommentDocumentAttribute = @"NSCommentDocumentAttribute";
NSString *const NSEditorDocumentAttribute = @"NSEditorDocumentAttribute";
NSString *const NSCreationTimeDocumentAttribute =
    @"NSCreationTimeDocumentAttribute";
NSString *const NSModificationTimeDocumentAttribute =
    @"NSModificationTimeDocumentAttribute";
NSString *const NSManagerDocumentAttribute = @"NSManagerDocumentAttribute";
NSString *const NSCategoryDocumentAttribute = @"NSCategoryDocumentAttribute";
NSString *const NSAppearanceDocumentAttribute =
    @"NSAppearanceDocumentAttribute";
NSString *const NSCharacterEncodingDocumentAttribute = @"CharacterEncoding";
NSString *const NSDefaultAttributesDocumentAttribute = @"DefaultAttributes";
NSString *const NSPaperSizeDocumentAttribute = @"PaperSize";
NSString *const NSLeftMarginDocumentAttribute = @"LeftMargin";
NSString *const NSRightMarginDocumentAttribute = @"RightMargin";
NSString *const NSTopMarginDocumentAttribute = @"TopMargin";
NSString *const NSBottomMarginDocumentAttribute = @"BottomMargin";
NSString *const NSViewSizeDocumentAttribute = @"ViewSize";
NSString *const NSViewZoomDocumentAttribute = @"ViewZoom";
NSString *const NSViewModeDocumentAttribute = @"ViewMode";
NSString *const NSReadOnlyDocumentAttribute = @"ReadOnly";
NSString *const NSBackgroundColorDocumentAttribute = @"BackgroundColor";
NSString *const NSHyphenationFactorDocumentAttribute = @"HyphenationFactor";
NSString *const NSDefaultTabIntervalDocumentAttribute = @"DefaultTabInterval";
NSString *const NSTextLayoutSectionsAttribute =
    @"NSTextLayoutSectionsAttribute";
NSString *const NSExcludedElementsDocumentAttribute = @"ExcludedElements";
NSString *const NSTextEncodingNameDocumentAttribute = @"TextEncodingName";
NSString *const NSPrefixSpacesDocumentAttribute = @"PrefixSpaces";

NSString *const NSDocumentTypeDocumentOption = @"DocumentType";
NSString *const NSDefaultAttributesDocumentOption = @"DefaultAttributes";
NSString *const NSCharacterEncodingDocumentOption = @"CharacterEncoding";
NSString *const NSTextEncodingNameDocumentOption = @"TextEncodingName";
NSString *const NSBaseURLDocumentOption = @"BaseURL";
NSString *const NSTimeoutDocumentOption = @"Timeout";
NSString *const NSWebPreferencesDocumentOption = @"WebPreferences";
NSString *const NSWebResourceLoadDelegateDocumentOption =
    @"WebResourceLoadDelegate";
NSString *const NSTextSizeMultiplierDocumentOption = @"TextSizeMultiplier";
NSString *const NSFileTypeDocumentOption = @"UTI";

NSString *const NSPlainTextDocumentType = @"NSPlainText";
NSString *const NSRTFTextDocumentType = @"NSRTF";
NSString *const NSRTFDTextDocumentType = @"NSRTFD";
NSString *const NSHTMLTextDocumentType = @"NSHTML";
NSString *const NSMacSimpleTextDocumentType = @"NSMacSimpleText";
NSString *const NSDocFormatTextDocumentType = @"NSDocFormat";
NSString *const NSWordMLTextDocumentType = @"NSWordML";
NSString *const NSWebArchiveTextDocumentType = @"NSWebArchive";
NSString *const NSOfficeOpenXMLTextDocumentType = @"NSOfficeOpenXML";
NSString *const NSOpenDocumentTextDocumentType = @"NSOpenDocument";

NSString *const NSTextLayoutSectionOrientation =
    @"NSTextLayoutSectionOrientation";
NSString *const NSTextLayoutSectionRange = @"NSTextLayoutSectionRange";

NSString *const NSCharacterShapeAttributeName = @"NSCharacterShape";
NSString *const NSUsesScreenFontsDocumentAttribute = @"UsesScreenFonts";

NSString *const NSTextEffectAttributeName = @"NSTextEffect";

NSUInteger NSUnderlineStrikethroughMask = 0x4000;
NSUInteger NSUnderlineByWordMask = 0x8000;

@implementation NSAttributedString (NSAttributedString_AppKit)

#pragma mark -
#pragma mark Creating an NSAttributedString

+ (NSAttributedString *) attributedStringWithAttachment:
    (NSTextAttachment *) attachment {
    unichar unicode = NSAttachmentCharacter;
    NSString *string = [NSString stringWithCharacters: &unicode length: 1];
    NSDictionary *attributes =
        [NSDictionary dictionaryWithObject: attachment
                                    forKey: NSAttachmentAttributeName];

    return [[[self alloc] initWithString: string
                              attributes: attributes] autorelease];
}

- initWithData: (NSData *) data
               options: (NSDictionary *) options
    documentAttributes: (NSDictionary **) attributes
                 error: (NSError **) error {
    NSUnimplementedMethod();
    return nil;
}

- initWithDocFormat: (NSData *) werd
    documentAttributes: (NSDictionary **) attributes {
    NSUnimplementedMethod();
    return nil;
}

- initWithHTML: (NSData *) html
               baseURL: (NSURL *) url
    documentAttributes: (NSDictionary **) attributes {
    NSUnimplementedMethod();
    return nil;
}

- initWithHTML: (NSData *) html
    documentAttributes: (NSDictionary **) attributes {
    NSUnimplementedMethod();
    return nil;
}

- initWithHTML: (NSData *) html
               options: (NSDictionary *) options
    documentAttributes: (NSDictionary **) attributes {
    NSUnimplementedMethod();
    return nil;
}

- initWithPath: (NSString *) path
    documentAttributes: (NSDictionary **) attributes {
    NSAttributedString *string =
        [NSRichTextReader attributedStringWithContentsOfFile: path];
    if (string == nil) {
        [self release];
        return nil;
    }
    return [self initWithAttributedString: string];
}

- initWithRTF: (NSData *) rtf documentAttributes: (NSDictionary **) attributes {
    NSAttributedString *string =
        [NSRichTextReader attributedStringWithData: rtf];
    if (string == nil) {
        [self release];
        return nil;
    }
    return [self initWithAttributedString: string];
}

- initWithRTFD: (NSData *) rtfd
    documentAttributes: (NSDictionary **) attributes {
    NSUnimplementedMethod();
    return nil;
}

- initWithRTFDFileWrapper: (NSFileWrapper *) wrapper
       documentAttributes: (NSDictionary **) attributes {
    NSUnimplementedMethod();
    return nil;
}

- initWithURL: (NSURL *) url documentAttributes: (NSDictionary **) attributes {
    NSUnimplementedMethod();
    return nil;
}

- initWithURL: (NSURL *) url
               options: (NSDictionary *) options
    documentAttributes: (NSDictionary **) attributes
                 error: (NSError **) error {
    NSUnimplementedMethod();
    return nil;
}

#pragma mark -
#pragma mark Retrieving Font Attribute Information

- (BOOL) containsAttachments {
    NSUnimplementedMethod();
    return NO;
}

- (NSDictionary *) fontAttributesInRange: (NSRange) range {
    NSUnimplementedMethod();
    return nil;
}

- (NSDictionary *) rulerAttributesInRange: (NSRange) range {
    NSUnimplementedMethod();
    return nil;
}

#pragma mark -
#pragma mark Calculating Linguistic Units

- (NSRange) doubleClickAtIndex: (NSUInteger) location {
    NSRange result = NSMakeRange(location, 0);
    NSString *string = [self string];
    unsigned length = [string length];

    if (length == 0) {
        return result;
    }

    unichar character = [string characterAtIndex: location];
    NSCharacterSet *set;
    BOOL expand = NO;

    set = [NSCharacterSet alphanumericCharacterSet];
    if ([set characterIsMember: character]) {
        expand = YES;
    } else {
        set = [NSCharacterSet whitespaceCharacterSet];
        if ([set characterIsMember: character]) {
            expand = YES;
        }
    }

    if (expand) {
        for (; result.location != 0; result.location--, result.length++) {
            if (![set characterIsMember: [string
                                             characterAtIndex: result.location -
                                                               1]]) {
                break;
            }
        }

        for (; NSMaxRange(result) < length; result.length++) {
            if (![set characterIsMember: [string
                                             characterAtIndex: NSMaxRange(
                                                                   result)]]) {
                break;
            }
        }
    } else if (location < length) {
        result.length = 1;
    }

    return result;
}

- (NSUInteger) lineBreakBeforeIndex: (NSUInteger) index
                        withinRange: (NSRange) range {
    NSUnimplementedMethod();
    return 0;
}

- (NSUInteger) lineBreakByHyphenatingBeforeIndex: (NSUInteger) index
                                     withinRange: (NSRange) range {
    NSUnimplementedMethod();
    return 0;
}

/* as usual, the documentation says one thing and the system behaves
 * differently, this is the way i think it should work... (dwy 5/11/2003) */
- (NSUInteger) nextWordFromIndex: (NSUInteger) location
                         forward: (BOOL) forward {
    NSCharacterSet *alpha = [NSCharacterSet alphanumericCharacterSet];
    NSString *string = [self string];
    int i = location, length = [self length];
    enum {
        STATE_INIT,  // skipping all whitespace
        STATE_ALNUM, // body of word
        STATE_SPACE  // word delimiter
    } state = STATE_ALNUM;

    if (location == 0 && forward == NO) {
        //        NSLog(@"sanity check: location == 0 && forward == NO");
        return location;
    }
    if (location >= [self length]) {
        //        NSLog(@"sanity check: location >= [self length] && forward ==
        //        YES");
        if (forward == YES) {
            return [self length];
        } else {
            location = [self length] - 1;
        }
    }

    if (forward) {
        if (![alpha characterIsMember: [string characterAtIndex: location]]) {
            state = STATE_INIT;
        }

        for (; i < length; ++i) {
            unichar ch = [string characterAtIndex: i];
            switch (state) {
            case STATE_INIT:
                if (![alpha characterIsMember: ch]) {
                    state = STATE_ALNUM;
                }
                break;
            case STATE_ALNUM:
                if ([alpha characterIsMember: ch]) {
                    state = STATE_SPACE;
                }
                break;
            case STATE_SPACE:
                if (![alpha characterIsMember: ch]) {
                    return i;
                }
            }
        }

        return length;
    } else {
        i--;
        if (![alpha characterIsMember: [string characterAtIndex: location]]) {
            state = STATE_INIT;
        }

        for (; i >= 0; i--) {
            unichar ch = [string characterAtIndex: i];
            switch (state) {
            case STATE_INIT:
                if (![alpha characterIsMember: ch]) {
                    state = STATE_ALNUM;
                }
                break;
            case STATE_ALNUM:
                if ([alpha characterIsMember: ch]) {
                    state = STATE_SPACE;
                }
                break;
            case STATE_SPACE:
                if (![alpha characterIsMember: ch]) {
                    return i + 1;
                }
            }
        }

        return 0;
    }

    return NSNotFound;
}

#pragma mark -
#pragma mark Calculating Ranges

- (NSInteger) itemNumberInTextList: (NSTextList *) list
                           atIndex: (NSUInteger) index {
    NSUnimplementedMethod();
    return 0;
}

- (NSRange) rangeOfTextBlock: (NSTextBlock *) block
                     atIndex: (NSUInteger) index {
    NSUnimplementedMethod();
    return NSMakeRange(0, 0);
}

- (NSRange) rangeOfTextList: (NSTextList *) list atIndex: (NSUInteger) index {
    NSUnimplementedMethod();
    return NSMakeRange(0, 0);
}

- (NSRange) rangeOfTextTable: (NSTextTable *) table
                     atIndex: (NSUInteger) index {
    NSUnimplementedMethod();
    return NSMakeRange(0, 0);
}

#pragma mark -
#pragma mark Generating Data

- (NSFileWrapper *) RTFDFileWrapperFromRange: (NSRange) range
                          documentAttributes: (NSDictionary *) attributes {
    NSUnimplementedMethod();
    return nil;
}

- (NSData *) RTFDFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes {
    return [NSRichTextWriter dataWithAttributedString: self range: range];
}

- (NSData *) RTFFromRange: (NSRange) range
       documentAttributes: (NSDictionary *) attributes {
    return [NSRichTextWriter dataWithAttributedString: self range: range];
}

- (NSData *) dataFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes
                     error: (NSError **) error {
    NSUnimplementedMethod();
    return 0;
}

- (NSData *) docFormatFromRange: (NSRange) range
             documentAttributes: (NSDictionary *) attributes {
    NSUnimplementedMethod();
    return 0;
}

- (NSFileWrapper *) fileWrapperFromRange: (NSRange) range
                      documentAttributes: (NSDictionary *) attributes
                                   error: (NSError **) error {
    NSUnimplementedMethod();
    return nil;
}

#pragma mark -
#pragma mark Drawing the string

- (void) drawAtPoint: (NSPoint) point {
    NSStringDrawer *drawer = [NSStringDrawer sharedStringDrawer];
    [drawer drawAttributedString: self atPoint: point inSize: NSZeroSize];
}

- (void) drawInRect: (NSRect) rect {
    NSStringDrawer *drawer = [NSStringDrawer sharedStringDrawer];
    [drawer drawAttributedString: self inRect: rect];
}

- (void) drawWithRect: (NSRect) rect options: (NSStringDrawingOptions) options {
    NSStringDrawer *drawer = [NSStringDrawer sharedStringDrawer];
    [drawer drawAttributedString: self inRect: rect];
}

- (NSSize) size {
    NSStringDrawer *drawer = [NSStringDrawer sharedStringDrawer];
    NSSize size = [drawer sizeOfAttributedString: self inSize: NSZeroSize];
    return size;
}

#pragma mark -
#pragma mark Getting the Bounding Rectangle of Rendered Strings

- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options {
    NSUnimplementedMethod();
    return NSMakeRect(0, 0, 0, 0);
}

#pragma mark -
#pragma mark Testing String Data Sources

+ (NSArray *) textTypes {
    NSUnimplementedMethod();
    return nil;
}

+ (NSArray *) textUnfilteredTypes {
    NSUnimplementedMethod();
    return nil;
}

#pragma mark -
#pragma mark Deprecated in 10.5

+ (NSArray *) textFileTypes {
    NSUnimplementedMethod();
    return nil;
}

+ (NSArray *) textPasteboardTypes {
    NSUnimplementedMethod();
    return nil;
}

+ (NSArray *) textUnfilteredFileTypes {
    NSUnimplementedMethod();
    return nil;
}

+ (NSArray *) textUnfilteredPasteboardTypes {
    NSUnimplementedMethod();
    return nil;
}

@end

#pragma mark -
#pragma mark Private

NSFont *NSFontAttributeInDictionary(NSDictionary *dictionary) {
    NSFont *font = [dictionary objectForKey: NSFontAttributeName];

    if (font == nil) {
        font = [NSFont fontWithName: @"Arial" size: 12.0];
    }

    return font;
}

NSColor *NSForegroundColorAttributeInDictionary(NSDictionary *dictionary) {
    NSColor *color = [dictionary objectForKey: NSForegroundColorAttributeName];

    if (color == nil) {
        color = [NSColor blackColor];
    }

    return color;
}

NSParagraphStyle *
NSParagraphStyleAttributeInDictionary(NSDictionary *dictionary) {
    NSParagraphStyle *style =
        [dictionary objectForKey: NSParagraphStyleAttributeName];

    if (style == nil) {
        style = [NSParagraphStyle defaultParagraphStyle];
    }

    return style;
}
