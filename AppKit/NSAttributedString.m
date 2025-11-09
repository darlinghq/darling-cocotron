/* Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSRichTextReader.h>
#import <AppKit/NSRichTextWriter.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSTextAttachment.h>

NSAttributedStringKey NSFontAttributeName = @"NSFontAttributeName";
NSAttributedStringKey NSParagraphStyleAttributeName = @"NSParagraphStyleAttributeName";
NSAttributedStringKey NSForegroundColorAttributeName = @"NSForegroundColorAttributeName";
NSAttributedStringKey NSBackgroundColorAttributeName = @"NSBackgroundColorAttributeName";
NSAttributedStringKey NSUnderlineStyleAttributeName = @"NSUnderlineStyleAttributeName";
NSAttributedStringKey NSUnderlineColorAttributeName = @"NSUnderlineColorAttributeName";
NSAttributedStringKey NSAttachmentAttributeName = @"NSAttachmentAttributeName";
NSAttributedStringKey NSKernAttributeName = @"NSKernAttributeName";
NSAttributedStringKey NSLigatureAttributeName = @"NSLigatureAttributeName";
NSAttributedStringKey NSStrikethroughStyleAttributeName = @"NSStrikethroughStyleAttributeName";
NSAttributedStringKey NSStrikethroughColorAttributeName = @"NSStrikethroughColorAttributeName";
NSAttributedStringKey NSObliquenessAttributeName = @"NSObliquenessAttributeName";
NSAttributedStringKey NSStrokeWidthAttributeName = @"NSStrokeWidthAttributeName";
NSAttributedStringKey NSStrokeColorAttributeName = @"NSStrokeColorAttributeName";
NSAttributedStringKey NSBaselineOffsetAttributeName = @"NSBaselineOffsetAttributeName";
NSAttributedStringKey NSSuperscriptAttributeName = @"NSSuperscriptAttributeName";
NSAttributedStringKey NSLinkAttributeName = @"NSLinkAttributeName";
NSAttributedStringKey NSShadowAttributeName = @"NSShadowAttributeName";
NSAttributedStringKey NSExpansionAttributeName = @"NSExpansionAttributeName";
NSAttributedStringKey NSCursorAttributeName = @"NSCursorAttributeName";
NSAttributedStringKey NSMarkedClauseSegmentAttributeName = @"NSMarkedClauseSegment";
NSAttributedStringKey NSToolTipAttributeName = @"NSToolTipAttributeName";
NSAttributedStringKey NSSpellingStateAttributeName = @"NSSpellingStateAttributeName"; // temporary attribute

NSAttributedStringDocumentAttributeKey NSDocumentTypeDocumentAttribute = @"DocumentType";
NSAttributedStringDocumentAttributeKey NSConvertedDocumentAttribute = @"Converted";
NSAttributedStringDocumentAttributeKey NSFileTypeDocumentAttribute = @"UTI";
NSAttributedStringDocumentAttributeKey NSTitleDocumentAttribute = @"NSTitleDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSCompanyDocumentAttribute = @"NSCompanyDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSCopyrightDocumentAttribute = @"NSCopyrightDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSSubjectDocumentAttribute = @"NSSubjectDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSAuthorDocumentAttribute = @"NSAuthorDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSKeywordsDocumentAttribute = @"NSKeywordsDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSCommentDocumentAttribute = @"NSCommentDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSEditorDocumentAttribute = @"NSEditorDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSCreationTimeDocumentAttribute = @"NSCreationTimeDocumentAttribute";
NSAttributedStringKey NSModificationTimeDocumentAttribute = @"NSModificationTimeDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSManagerDocumentAttribute = @"NSManagerDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSCategoryDocumentAttribute = @"NSCategoryDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSAppearanceDocumentAttribute = @"NSAppearanceDocumentAttribute";
NSAttributedStringDocumentAttributeKey NSCharacterEncodingDocumentAttribute = @"CharacterEncoding";
NSAttributedStringDocumentAttributeKey NSDefaultAttributesDocumentAttribute = @"DefaultAttributes";
NSAttributedStringDocumentAttributeKey NSPaperSizeDocumentAttribute = @"PaperSize";
NSAttributedStringDocumentAttributeKey NSLeftMarginDocumentAttribute = @"LeftMargin";
NSAttributedStringDocumentAttributeKey NSRightMarginDocumentAttribute = @"RightMargin";
NSAttributedStringDocumentAttributeKey NSTopMarginDocumentAttribute = @"TopMargin";
NSAttributedStringDocumentAttributeKey NSBottomMarginDocumentAttribute = @"BottomMargin";
NSAttributedStringDocumentAttributeKey NSViewSizeDocumentAttribute = @"ViewSize";
NSAttributedStringDocumentAttributeKey NSViewZoomDocumentAttribute = @"ViewZoom";
NSAttributedStringDocumentAttributeKey NSViewModeDocumentAttribute = @"ViewMode";
NSAttributedStringDocumentAttributeKey NSReadOnlyDocumentAttribute = @"ReadOnly";
NSAttributedStringDocumentAttributeKey NSBackgroundColorDocumentAttribute = @"BackgroundColor";
NSAttributedStringDocumentAttributeKey NSHyphenationFactorDocumentAttribute = @"HyphenationFactor";
NSAttributedStringDocumentAttributeKey NSDefaultTabIntervalDocumentAttribute = @"DefaultTabInterval";
NSAttributedStringDocumentAttributeKey NSTextLayoutSectionsAttribute = @"NSTextLayoutSectionsAttribute";
NSAttributedStringDocumentAttributeKey NSExcludedElementsDocumentAttribute = @"ExcludedElements";
NSAttributedStringDocumentAttributeKey NSTextEncodingNameDocumentAttribute = @"TextEncodingName";
NSAttributedStringDocumentAttributeKey NSPrefixSpacesDocumentAttribute = @"PrefixSpaces";
NSAttributedStringDocumentAttributeKey NSCocoaVersionDocumentAttribute = @"NSCocoaVersionDocumentAttribute";

NSAttributedStringDocumentReadingOptionKey NSDocumentTypeDocumentOption = @"DocumentType";
NSAttributedStringDocumentReadingOptionKey NSDefaultAttributesDocumentOption = @"DefaultAttributes";
NSAttributedStringDocumentReadingOptionKey NSCharacterEncodingDocumentOption = @"CharacterEncoding";
NSAttributedStringDocumentReadingOptionKey NSTextEncodingNameDocumentOption = @"TextEncodingName";
NSAttributedStringDocumentReadingOptionKey NSBaseURLDocumentOption = @"BaseURL";
NSAttributedStringDocumentReadingOptionKey NSTimeoutDocumentOption = @"Timeout";
NSAttributedStringDocumentReadingOptionKey NSWebPreferencesDocumentOption = @"WebPreferences";
NSAttributedStringDocumentReadingOptionKey NSWebResourceLoadDelegateDocumentOption = @"WebResourceLoadDelegate";
NSAttributedStringDocumentReadingOptionKey NSTextSizeMultiplierDocumentOption = @"TextSizeMultiplier";
NSAttributedStringDocumentReadingOptionKey NSFileTypeDocumentOption = @"UTI";

NSAttributedStringDocumentType NSPlainTextDocumentType = @"NSPlainText";
NSAttributedStringDocumentType NSRTFTextDocumentType = @"NSRTF";
NSAttributedStringDocumentType NSRTFDTextDocumentType = @"NSRTFD";
NSAttributedStringDocumentType NSHTMLTextDocumentType = @"NSHTML";
NSAttributedStringDocumentType NSMacSimpleTextDocumentType = @"NSMacSimpleText";
NSAttributedStringDocumentType NSDocFormatTextDocumentType = @"NSDocFormat";
NSAttributedStringDocumentType NSWordMLTextDocumentType = @"NSWordML";
NSAttributedStringDocumentType NSWebArchiveTextDocumentType = @"NSWebArchive";
NSAttributedStringDocumentType NSOfficeOpenXMLTextDocumentType = @"NSOfficeOpenXML";
NSAttributedStringDocumentType NSOpenDocumentTextDocumentType = @"NSOpenDocument";

NSTextLayoutSectionKey NSTextLayoutSectionOrientation = @"NSTextLayoutSectionOrientation";
NSTextLayoutSectionKey NSTextLayoutSectionRange = @"NSTextLayoutSectionRange";

NSAttributedStringKey NSCharacterShapeAttributeName = @"NSCharacterShape";
NSAttributedStringKey NSUsesScreenFontsDocumentAttribute = @"UsesScreenFonts";

const NSAttributedStringKey NSTextEffectAttributeName = @"NSTextEffect";
NSAttributedStringKey NSWritingDirectionAttributeName = @"NSWritingDirectionAttribute";

NSUInteger NSUnderlineStrikethroughMask = 0x4000;
NSUInteger NSUnderlineByWordMask = 0x8000;

@implementation NSAttributedString (NSAttributedString_AppKit)

#pragma mark -
#pragma mark Creating an NSAttributedString

+ (NSAttributedString *) attributedStringWithAttachment:
        (NSTextAttachment *) attachment
{
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
                     error: (NSError **) error
{
    NSUnimplementedMethod();
    NSString *docType = [options objectForKey:NSDocumentTypeDocumentAttribute];
   
    //Infer the document format if not provided
    if(docType == nil){
        //Extract a prefix from the document to identify the type
        //FIXME: use 64 bit ready types and check encoding
        char prefix[14];
        NSUInteger dataLength = [data length];
        
        if(dataLength < sizeof(prefix))
        {
            [data getBytes: prefix length: dataLength];
            prefix[dataLength] = 0;
        }
        else
        {
            [data getBytes: prefix length: sizeof(prefix)];
        }

        //Use the prefix to determine the document format
        // FIXME extend the list
        if (strncmp(prefix, "{\\rtf", 5) == 0)
        {
            docType = NSRTFTextDocumentType;
        }
        else if (strncasecmp(prefix, "<!doctype html", 14) == 0 ||
                 strncasecmp(prefix, "<head", 5) == 0 ||
                 strncasecmp(prefix, "<title", 6) == 0 ||
                 strncasecmp(prefix, "<html", 5) == 0 ||
                 strncmp(prefix, "<!--", 4) == 0 ||
                 strncasecmp(prefix, "<h1", 3) == 0)
        {
            docType = NSHTMLTextDocumentType;
        }
        else
        {
            docType = NSPlainTextDocumentType;
        }
    }

    //Read the document based on its type
    //TODO: Implement reading for all types
    if([docType isEqual: NSDocFormatTextDocumentType]){
        return nil;
    }
    else if([docType isEqual: NSHTMLTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else if([docType isEqual: NSMacSimpleTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else if([docType isEqual: NSOfficeOpenXMLTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else if([docType isEqual: NSOpenDocumentTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else if([docType isEqual: NSPlainTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else if([docType isEqual: NSRTFTextDocumentType]){
        return [self initWithRTF: data documentAttributes: attributes];
    }
    else if([docType isEqual: NSRTFDTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else if([docType isEqual: NSWebArchiveTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else if([docType isEqual: NSWordMLTextDocumentType]){
        NSLog(@"NSAttributedString initFromData - dont know how to parse %@", docType);
        return nil;
    }
    else {
    return nil;
    }
}

- initWithDocFormat: (NSData *) werd
        documentAttributes: (NSDictionary **) attributes
{
    NSUnimplementedMethod();
    return nil;
}

- initWithHTML: (NSData *) html
                   baseURL: (NSURL *) url
        documentAttributes: (NSDictionary **) attributes
{
    NSUnimplementedMethod();
    return nil;
}

- initWithHTML: (NSData *) html
        documentAttributes: (NSDictionary **) attributes
{
    NSUnimplementedMethod();
    return nil;
}

- initWithHTML: (NSData *) html
                   options: (NSDictionary *) options
        documentAttributes: (NSDictionary **) attributes
{
    NSUnimplementedMethod();
    return nil;
}

- initWithPath: (NSString *) path
        documentAttributes: (NSDictionary **) attributes
{
    NSAttributedString *string =
            [NSRichTextReader attributedStringWithContentsOfFile: path];
    if (string == nil) {
        [self release];
        return nil;
    }
    return [self initWithAttributedString: string];
}

- initWithRTF: (NSData *) rtf documentAttributes: (NSDictionary **) attributes {
    *attributes = [NSDictionary dictionaryWithObject: NSRTFTextDocumentType 
                                              forKey: NSDocumentTypeDocumentAttribute];
    NSAttributedString *string =
            [NSRichTextReader attributedStringWithData: rtf];
    if (string == nil) {
        [self release];
        return nil;
    }
    return [self initWithAttributedString: string];
}

- initWithRTFD: (NSData *) rtfd
        documentAttributes: (NSDictionary **) attributes
{
    NSUnimplementedMethod();
    return nil;
}

- initWithRTFDFileWrapper: (NSFileWrapper *) wrapper
        documentAttributes: (NSDictionary **) attributes
{
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
                     error: (NSError **) error
{
    NSData *data = [NSData dataWithContentsOfURL: url];
    return [self initWithData: data options: options documentAttributes: attributes error: error]; 
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
    if ([set characterIsMember: character])
        expand = YES;
    else {
        set = [NSCharacterSet whitespaceCharacterSet];
        if ([set characterIsMember: character])
            expand = YES;
    }

    if (expand) {
        for (; result.location != 0; result.location--, result.length++) {
            if (![set characterIsMember:
                                [string characterAtIndex: result.location - 1]])
                break;
        }

        for (; NSMaxRange(result) < length; result.length++) {
            if (![set characterIsMember:
                                [string characterAtIndex: NSMaxRange(result)]])
                break;
        }
    } else if (location < length)
        result.length = 1;

    return result;
}

- (NSUInteger) lineBreakBeforeIndex: (NSUInteger) index
                        withinRange: (NSRange) range
{
    NSUnimplementedMethod();
    return 0;
}

- (NSUInteger) lineBreakByHyphenatingBeforeIndex: (NSUInteger) index
                                     withinRange: (NSRange) range
{
    NSUnimplementedMethod();
    return 0;
}

/* as usual, the documentation says one thing and the system behaves
 * differently, this is the way i think it should work... (dwy 5/11/2003) */
- (NSUInteger) nextWordFromIndex: (NSUInteger) location
                         forward: (BOOL) forward
{
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
        if (forward == YES)
            return [self length];
        else
            location = [self length] - 1;
    }

    if (forward) {
        if (![alpha characterIsMember: [string characterAtIndex: location]])
            state = STATE_INIT;

        for (; i < length; ++i) {
            unichar ch = [string characterAtIndex: i];
            switch (state) {
            case STATE_INIT:
                if (![alpha characterIsMember: ch])
                    state = STATE_ALNUM;
                break;
            case STATE_ALNUM:
                if ([alpha characterIsMember: ch])
                    state = STATE_SPACE;
                break;
            case STATE_SPACE:
                if (![alpha characterIsMember: ch])
                    return i;
            }
        }

        return length;
    } else {
        i--;
        if (![alpha characterIsMember: [string characterAtIndex: location]])
            state = STATE_INIT;

        for (; i >= 0; i--) {
            unichar ch = [string characterAtIndex: i];
            switch (state) {
            case STATE_INIT:
                if (![alpha characterIsMember: ch])
                    state = STATE_ALNUM;
                break;
            case STATE_ALNUM:
                if ([alpha characterIsMember: ch])
                    state = STATE_SPACE;
                break;
            case STATE_SPACE:
                if (![alpha characterIsMember: ch])
                    return i + 1;
            }
        }

        return 0;
    }

    return NSNotFound;
}

#pragma mark -
#pragma mark Calculating Ranges

- (NSInteger) itemNumberInTextList: (NSTextList *) list
                           atIndex: (NSUInteger) index
{
    NSUnimplementedMethod();
    return 0;
}

- (NSRange) rangeOfTextBlock: (NSTextBlock *) block
                     atIndex: (NSUInteger) index
{
    NSUnimplementedMethod();
    return NSMakeRange(0, 0);
}

- (NSRange) rangeOfTextList: (NSTextList *) list atIndex: (NSUInteger) index {
    NSUnimplementedMethod();
    return NSMakeRange(0, 0);
}

- (NSRange) rangeOfTextTable: (NSTextTable *) table
                     atIndex: (NSUInteger) index
{
    NSUnimplementedMethod();
    return NSMakeRange(0, 0);
}

#pragma mark -
#pragma mark Generating Data

- (NSFileWrapper *) RTFDFileWrapperFromRange: (NSRange) range
                          documentAttributes: (NSDictionary *) attributes
{
    NSUnimplementedMethod();
    return nil;
}

- (NSData *) RTFDFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes
{
    return [NSRichTextWriter dataWithAttributedString: self range: range];
}

- (NSData *) RTFFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes
{
    return [NSRichTextWriter dataWithAttributedString: self range: range];
}

- (NSData *) dataFromRange: (NSRange) range
        documentAttributes: (NSDictionary *) attributes
                     error: (NSError **) error
{
    NSUnimplementedMethod();
    return 0;
}

- (NSData *) docFormatFromRange: (NSRange) range
             documentAttributes: (NSDictionary *) attributes
{
    NSUnimplementedMethod();
    return 0;
}

- (NSFileWrapper *) fileWrapperFromRange: (NSRange) range
                      documentAttributes: (NSDictionary *) attributes
                                   error: (NSError **) error
{
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
                        options: (NSStringDrawingOptions) options
{
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

    if (font == nil)
        font = [NSFont fontWithName: @"Arial" size: 12.0];

    return font;
}

NSColor *NSForegroundColorAttributeInDictionary(NSDictionary *dictionary) {
    NSColor *color = [dictionary objectForKey: NSForegroundColorAttributeName];

    if (color == nil)
        color = [NSColor blackColor];

    return color;
}

NSParagraphStyle *
NSParagraphStyleAttributeInDictionary(NSDictionary *dictionary)
{
    NSParagraphStyle *style =
            [dictionary objectForKey: NSParagraphStyleAttributeName];

    if (style == nil)
        style = [NSParagraphStyle defaultParagraphStyle];

    return style;
}
