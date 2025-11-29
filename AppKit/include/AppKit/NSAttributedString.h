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

#import <AppKit/AppKitExport.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/Foundation.h>

@class NSFont, NSColor, NSParagraphStyle, NSTextAttachment, NSFileWrapper,
        NSTextList, NSTextBlock, NSTextTable;

typedef NSString *NSAttributedStringDocumentReadingOptionKey;
typedef NSString *NSAttributedStringDocumentAttributeKey;
typedef NSString *NSAttributedStringDocumentType;
typedef NSString *NSTextLayoutSectionKey;
typedef NSString *NSAttributedStringKey;

// The following constants are *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSAttributedStringKey NSFontAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSParagraphStyleAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSForegroundColorAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSBackgroundColorAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSUnderlineStyleAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSUnderlineColorAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSAttachmentAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSKernAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSLigatureAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSStrikethroughStyleAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSStrikethroughColorAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSObliquenessAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSStrokeWidthAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSStrokeColorAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSBaselineOffsetAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSSuperscriptAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSLinkAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSShadowAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSExpansionAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSCursorAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSMarkedClauseSegmentAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSToolTipAttributeName;

// The following constant is *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSAttributedStringKey NSSpellingStateAttributeName;

// The following constants are *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSDocumentTypeDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSConvertedDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSFileTypeDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSTitleDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSCompanyDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSCopyrightDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSSubjectDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSAuthorDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSKeywordsDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSCommentDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSEditorDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSCreationTimeDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSModificationTimeDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSManagerDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSCategoryDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSAppearanceDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSCharacterEncodingDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSDefaultAttributesDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSPaperSizeDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSLeftMarginDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSRightMarginDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSTopMarginDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSBottomMarginDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSViewSizeDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSViewZoomDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSViewModeDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSReadOnlyDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSBackgroundColorDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSHyphenationFactorDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSDefaultTabIntervalDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSTextLayoutSectionsAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSExcludedElementsDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSTextEncodingNameDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSPrefixSpacesDocumentAttribute;
APPKIT_EXPORT NSAttributedStringDocumentAttributeKey NSCocoaVersionDocumentAttribute;

// The following constants are *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSDocumentTypeDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSDefaultAttributesDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSCharacterEncodingDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSTextEncodingNameDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSBaseURLDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSTimeoutDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSWebPreferencesDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSWebResourceLoadDelegateDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSTextSizeMultiplierDocumentOption;
APPKIT_EXPORT NSAttributedStringDocumentReadingOptionKey NSFileTypeDocumentOption;

// The following constants are *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSAttributedStringDocumentType NSPlainTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSRTFTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSRTFDTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSHTMLTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSMacSimpleTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSDocFormatTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSWordMLTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSWebArchiveTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSOfficeOpenXMLTextDocumentType;
APPKIT_EXPORT NSAttributedStringDocumentType NSOpenDocumentTextDocumentType;

// The following constants are *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSTextLayoutSectionKey NSTextLayoutSectionOrientation;
APPKIT_EXPORT NSTextLayoutSectionKey NSTextLayoutSectionRange;

// The following constants are *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSAttributedStringKey NSCharacterShapeAttributeName;
APPKIT_EXPORT NSAttributedStringKey NSUsesScreenFontsDocumentAttribute;

APPKIT_EXPORT const NSAttributedStringKey NSTextEffectAttributeName;
// The following constant is *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSAttributedStringKey NSWritingDirectionAttributeName;

// The following constants are *not* declared as `const` in Apple's AppKit (they are located in __data)
APPKIT_EXPORT NSUInteger NSUnderlineStrikethroughMask;
APPKIT_EXPORT NSUInteger NSUnderlineByWordMask;

enum {
    NSSpellingStateSpellingFlag = 0x01,
    NSSpellingStateGrammarFlag = 0x02,
};

enum {
    NSUnderlineStyleNone,
    NSUnderlineStyleSingle,
    NSUnderlineStyleThick,
    NSUnderlineStyleDouble,
};

// Deprecated constants
enum {
    NSNoUnderlineStyle = NSUnderlineStyleNone,
    NSSingleUnderlineStyle = NSUnderlineStyleSingle,
};

enum {
    NSUnderlinePatternSolid = 0x000,
    NSUnderlinePatternDot = 0x100,
    NSUnderlinePatternDash = 0x200,
    NSUnderlinePatternDashDot = 0x300,
    NSUnderlinePatternDashDotDot = 0x400,
};

@interface NSAttributedString (NSAttributedString_AppKit)

#pragma mark -
#pragma mark Creating an NSAttributedString

+ (NSAttributedString *) attributedStringWithAttachment:
        (NSTextAttachment *) attachment;

- initWithData: (NSData *) data
                   options: (NSDictionary *) options
        documentAttributes: (NSDictionary **) attributes
                     error: (NSError **) error;
- initWithDocFormat: (NSData *) werd
        documentAttributes: (NSDictionary **) attributes;

- initWithHTML: (NSData *) html
                   baseURL: (NSURL *) url
        documentAttributes: (NSDictionary **) attributes;
- initWithHTML: (NSData *) html
        documentAttributes: (NSDictionary **) attributes;
- initWithHTML: (NSData *) html
                   options: (NSDictionary *) options
        documentAttributes: (NSDictionary **) attributes;
- initWithPath: (NSString *) path
        documentAttributes: (NSDictionary **) attributes;

- initWithRTF: (NSData *) rtf documentAttributes: (NSDictionary **) attributes;

- initWithRTFD: (NSData *) rtfd
        documentAttributes: (NSDictionary **) attributes;
- initWithRTFDFileWrapper: (NSFileWrapper *) wrapper
        documentAttributes: (NSDictionary **) attributes;

- initWithURL: (NSURL *) url documentAttributes: (NSDictionary **) attributes;
- initWithURL: (NSURL *) url
                   options: (NSDictionary *) options
        documentAttributes: (NSDictionary **) attributes
                     error: (NSError **) error;

#pragma mark -
#pragma mark Retrieving Font Attribute Information

- (BOOL) containsAttachments;
- (NSDictionary *) fontAttributesInRange: (NSRange) range;
- (NSDictionary *) rulerAttributesInRange: (NSRange) range;

#pragma mark -
#pragma mark Calculating Linguistic Units

- (NSRange) doubleClickAtIndex: (NSUInteger) index;
- (NSUInteger) lineBreakBeforeIndex: (NSUInteger) index
                        withinRange: (NSRange) range;
- (NSUInteger) lineBreakByHyphenatingBeforeIndex: (NSUInteger) index
                                     withinRange: (NSRange) range;
- (NSUInteger) nextWordFromIndex: (NSUInteger) index forward: (BOOL) forward;

#pragma mark -
#pragma mark Calculating Ranges

- (NSInteger) itemNumberInTextList: (NSTextList *) list
                           atIndex: (NSUInteger) index;
- (NSRange) rangeOfTextBlock: (NSTextBlock *) block atIndex: (NSUInteger) index;
- (NSRange) rangeOfTextList: (NSTextList *) list atIndex: (NSUInteger) index;
- (NSRange) rangeOfTextTable: (NSTextTable *) table atIndex: (NSUInteger) index;

#pragma mark -
#pragma mark Generating Data

- (NSData *) dataFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes
                     error: (NSError **) error;
- (NSFileWrapper *) fileWrapperFromRange: (NSRange) range
                      documentAttributes: (NSDictionary *) attributes
                                   error: (NSError **) error;
- (NSData *) docFormatFromRange: (NSRange) range
             documentAttributes: (NSDictionary *) attributes;
- (NSData *) RTFFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes;
- (NSData *) RTFDFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes;
- (NSFileWrapper *) RTFDFileWrapperFromRange: (NSRange) range
                          documentAttributes: (NSDictionary *) attributes;

#pragma mark -
#pragma mark Drawing the String

- (void) drawAtPoint: (NSPoint) point;
- (void) drawInRect: (NSRect) rect;
- (void) drawWithRect: (NSRect) rect options: (NSStringDrawingOptions) options;
- (NSSize) size;

#pragma mark -
#pragma mark Getting the Bounding Rectangle of Rendered Strings

- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options;

#pragma mark -
#pragma mark Getting Attribute Data
- (void)enumerateAttribute: (NSAttributedStringKey) attrName 
                   inRange: (NSRange) enumerationRange 
                   options: (NSAttributedStringEnumerationOptions) opts 
                usingBlock: (void (^)(id value, NSRange range, BOOL *stop)) block;

#pragma mark -
#pragma mark Testing String Data Sources

+ (NSArray *) textTypes;
+ (NSArray *) textUnfilteredTypes;

#pragma mark -
#pragma mark Deprecated in 10.5

+ (NSArray *) textFileTypes;
+ (NSArray *) textPasteboardTypes;

+ (NSArray *) textUnfilteredFileTypes;
+ (NSArray *) textUnfilteredPasteboardTypes;

@end

#pragma mark -
#pragma mark Private

NSFont *NSFontAttributeInDictionary(NSDictionary *dictionary);
NSColor *NSForegroundColorAttributeInDictionary(NSDictionary *dictionary);
NSParagraphStyle *
NSParagraphStyleAttributeInDictionary(NSDictionary *dictionary);

#import <AppKit/NSMutableAttributedString.h>
