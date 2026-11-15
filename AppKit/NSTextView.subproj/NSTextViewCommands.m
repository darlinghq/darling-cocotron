/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// Commands, conveniences and text checking of NSTextView that sit beside the
// editing core in NSTextView.m: character attribute commands of the Font menu,
// colour commands, smart insert and delete, substitutions (quotes, dashes,
// links), the pasteboard type lists, factory methods and a few geometry
// helpers. Behaviour that the documentation does not pin down was read off
// macOS 10.14.4 and 26.7.3 (black-box observation, the project's Mac evidence
// notes, V613); where an observation is relied on, a comment says so and names
// the test.

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSTextCheckingResult.h>
#import <Foundation/NSURL.h>

#include <math.h>
#include <string.h>

typedef id (^_NSTextViewAttributeChange)(id old, NSFont *font);

@interface NSTextView ()
- (void) _changeCharacterAttribute: (NSString *) key with: (_NSTextViewAttributeChange) change;
- (void) _addAttributes: (NSDictionary *) attributes range: (NSRange) range;
- (void) _addAttribute: (NSString *) key value: (id) value range: (NSRange) range;
- (void) _removeAttribute: (NSString *) key range: (NSRange) range;
- (void) _setAlignment: (NSTextAlignment) alignment range: (NSRange) range;
- (void) _updateTypingAttributes;
- (NSUInteger) glyphIndexForPoint: (NSPoint) point
        fractionOfDistanceThroughGlyph: (CGFloat *) fraction;
- (void) _pasteRestrictedToTypes: (NSArray *) types;
- (void) _applyTypedTextSubstitutionsForRange: (NSRange) typed;
- (void) _replaceCharactersInRange: (NSRange) range
                        withString: (id) string
               useTypingAttributes: (BOOL) useTypingAttributes;
- (void) _stepSuperscriptBy: (int) delta;
- (void) _raiseIfRange: (NSRange) range beyondTextForSelector: (SEL) selector;
- (void) _checkAllTextInRange: (NSRange) range;
- (void) _addQuoteResultsTo: (NSMutableArray *) results forRange: (NSRange) range;
- (void) _addDashResultsTo: (NSMutableArray *) results forRange: (NSRange) range;
- (void) _addLinkResultsTo: (NSMutableArray *) results forRange: (NSRange) range;
+ (NSScrollView *) _scrollableTextViewRich: (BOOL) rich findBar: (BOOL) findBar fullFeature: (BOOL) fullFeature;
@end

// The pasteboard type that marks text as having been copied with word
// boundaries (the paste adds or removes spaces around a word). Not a public
// constant; the spelling was read off a pasteboard that macOS pastes smartly.
static NSString *const _NSTextViewSmartPastePboardType = @"NeXT smart paste pasteboard type";

static const CGFloat _NSTextViewLargeNumberForText = 1.0e7;

@implementation NSTextView (NSTextViewCommands)

#pragma mark - Initializing

- (instancetype) initUsingTextLayoutManager: (BOOL) usingTextLayoutManager {
    // Only TextKit 1 text views exist here (see +textViewUsingTextLayoutManager:).
    return [self initWithFrame: NSZeroRect];
}

#pragma mark - Character attributes of the Font menu

// Changes one character attribute over the ranges the user may change. With an
// insertion point (rich text) only the typing attributes change. The change is
// asked of the delegate as an attribute-only change (nil replacement strings),
// as macOS does. A nil result removes the attribute.
// Test: appkit-textview-font-commands.m
- (void) _changeCharacterAttribute: (NSString *) key with: (_NSTextViewAttributeChange) change {
    NSArray *ranges = [self rangesForUserCharacterAttributeChange];
    if (ranges == nil)
        return;

    NSRange range = [[ranges objectAtIndex: 0] rangeValue];
    NSTextStorage *storage = [self textStorage];

    if (range.length > 0) {
        if (![self shouldChangeTextInRanges: ranges replacementStrings: nil])
            return;

        // Collect the runs first: changing attributes while walking would
        // invalidate the effective ranges. The font handed to the change is
        // the one at the start of the selection for every run (the kerning
        // step of a selection that mixes sizes is the first run's on macOS,
        // 10.14.4 and 26.7.3).
        NSMutableArray *runs = [NSMutableArray array];
        NSFont *font = [storage attribute: NSFontAttributeName atIndex: range.location effectiveRange: NULL];
        NSUInteger location = range.location;
        while (location < NSMaxRange(range)) {
            NSRange run;
            id value = [storage attribute: key atIndex: location longestEffectiveRange: &run inRange: range];
            [runs addObject: [NSArray arrayWithObjects: [NSValue valueWithRange: run],
                                                        value != nil ? value : (id) [NSNull null],
                                                        font != nil ? font : (id) [NSNull null], nil]];
            location = NSMaxRange(run);
            if (run.length == 0)
                break;
        }

        [storage beginEditing];
        for (NSArray *entry in runs) {
            NSRange run = [[entry objectAtIndex: 0] rangeValue];
            id value = [entry objectAtIndex: 1];
            id font = [entry objectAtIndex: 2];
            id result = change(value == [NSNull null] ? nil : value, font == [NSNull null] ? nil : font);
            if (result != nil)
                [self _addAttribute: key value: result range: run];
            else
                [self _removeAttribute: key range: run];
        }
        [storage endEditing];
        [self didChangeText];
        [self _updateTypingAttributes];
        return;
    }

    NSMutableDictionary *typing = [[[self typingAttributes] mutableCopy] autorelease];
    if (typing == nil)
        typing = [NSMutableDictionary dictionary];
    id result = change([typing objectForKey: key], [typing objectForKey: NSFontAttributeName]);
    if (result != nil)
        [typing setObject: result forKey: key];
    else
        [typing removeObjectForKey: key];
    [self setTypingAttributes: typing];
}

// One step of tightening or loosening: the point size over 72, cut to two
// decimals (measured at 6, 12, 24 and 48 points on macOS 10.14.4 and 26.7.3).
static CGFloat _NSTextViewKernStep(NSFont *font) {
    CGFloat size = font != nil ? [font pointSize] : 12.0;
    return floor(size / 72.0 * 100.0) / 100.0;
}

- (void) turnOffKerning: (id) sender {
    [self _changeCharacterAttribute: NSKernAttributeName
                               with: ^id(id old, NSFont *font) { return [NSNumber numberWithDouble: 0]; }];
}

- (void) tightenKerning: (id) sender {
    [self _changeCharacterAttribute: NSKernAttributeName
                               with: ^id(id old, NSFont *font) {
        return [NSNumber numberWithDouble: [old doubleValue] - _NSTextViewKernStep(font)];
    }];
}

- (void) loosenKerning: (id) sender {
    [self _changeCharacterAttribute: NSKernAttributeName
                               with: ^id(id old, NSFont *font) {
        return [NSNumber numberWithDouble: [old doubleValue] + _NSTextViewKernStep(font)];
    }];
}

- (void) useStandardKerning: (id) sender {
    [self _changeCharacterAttribute: NSKernAttributeName
                               with: ^id(id old, NSFont *font) { return nil; }];
}

- (void) turnOffLigatures: (id) sender {
    [self _changeCharacterAttribute: NSLigatureAttributeName
                               with: ^id(id old, NSFont *font) { return [NSNumber numberWithInt: 0]; }];
}

- (void) useStandardLigatures: (id) sender {
    [self _changeCharacterAttribute: NSLigatureAttributeName
                               with: ^id(id old, NSFont *font) { return nil; }];
}

- (void) useAllLigatures: (id) sender {
    [self _changeCharacterAttribute: NSLigatureAttributeName
                               with: ^id(id old, NSFont *font) { return [NSNumber numberWithInt: 2]; }];
}

// Raising and lowering moves one point per command regardless of the font
// size and keeps a resulting 0; superscript and subscript step the
// superscript attribute by one and drop it at 0 (observed on macOS 10.14.4
// and 26.7.3).
- (void) raiseBaseline: (id) sender {
    [self _changeCharacterAttribute: NSBaselineOffsetAttributeName
                               with: ^id(id old, NSFont *font) {
        return [NSNumber numberWithDouble: [old doubleValue] + 1.0];
    }];
}

- (void) lowerBaseline: (id) sender {
    [self _changeCharacterAttribute: NSBaselineOffsetAttributeName
                               with: ^id(id old, NSFont *font) {
        return [NSNumber numberWithDouble: [old doubleValue] - 1.0];
    }];
}

- (void) _stepSuperscriptBy: (int) delta {
    [self _changeCharacterAttribute: NSSuperscriptAttributeName
                               with: ^id(id old, NSFont *font) {
        int value = [old intValue] + delta;
        return value != 0 ? [NSNumber numberWithInt: value] : nil;
    }];
}

- (void) superscript: (id) sender {
    [self _stepSuperscriptBy: 1];
}

- (void) subscript: (id) sender {
    [self _stepSuperscriptBy: -1];
}

- (void) unscript: (id) sender {
    [self _changeCharacterAttribute: NSSuperscriptAttributeName
                               with: ^id(id old, NSFont *font) { return nil; }];
}

// Outline toggles a stroke width of 3 when there is none (or 0), and removes
// any other stroke width.
- (void) outline: (id) sender {
    [self _changeCharacterAttribute: NSStrokeWidthAttributeName
                               with: ^id(id old, NSFont *font) {
        return [old doubleValue] == 0 ? (id) [NSNumber numberWithDouble: 3.0] : nil;
    }];
}

// Deprecated since 10.6; the traditional character shapes are in Unicode.
- (void) toggleTraditionalCharacterShape: (id) sender {
}

#pragma mark - Colour commands

// Colours the user's selection with the colour of the sender (the colour
// panel); a plain text view takes the colour for all its text.
- (void) changeColor: (id) sender {
    NSColor *color = [sender color];
    if (color == nil)
        return;
    [self _changeCharacterAttribute: NSForegroundColorAttributeName
                               with: ^id(id old, NSFont *font) { return color; }];
    if (![self isRichText] && [self isEditable])
        [self setTextColor: color];
}

// Lets a font manager rewrite the attributes of each run (the Font panel's
// attribute-changing commands).
- (void) changeAttributes: (id) sender {
    NSArray *ranges = [self rangesForUserCharacterAttributeChange];
    if (ranges == nil)
        return;
    NSRange range = [[ranges objectAtIndex: 0] rangeValue];
    NSTextStorage *storage = [self textStorage];

    if (range.length == 0) {
        NSDictionary *converted = [sender convertAttributes: [self typingAttributes]];
        if (converted != nil)
            [self setTypingAttributes: converted];
        return;
    }
    if (![self shouldChangeTextInRanges: ranges replacementStrings: nil])
        return;

    NSMutableArray *runs = [NSMutableArray array];
    NSUInteger location = range.location;
    while (location < NSMaxRange(range)) {
        NSRange run;
        NSDictionary *attributes = [storage attributesAtIndex: location
                                        longestEffectiveRange: &run
                                                      inRange: range];
        [runs addObject: [NSArray arrayWithObjects: [NSValue valueWithRange: run], attributes, nil]];
        location = NSMaxRange(run);
        if (run.length == 0)
            break;
    }

    [storage beginEditing];
    for (NSArray *entry in runs) {
        NSRange run = [[entry objectAtIndex: 0] rangeValue];
        NSDictionary *attributes = [entry objectAtIndex: 1];
        NSDictionary *converted = [sender convertAttributes: attributes];
        if (converted == nil)
            continue;
        for (NSString *key in attributes)
            if ([converted objectForKey: key] == nil)
                [self _removeAttribute: key range: run];
        [self _addAttributes: converted range: run];
    }
    [storage endEditing];
    [self didChangeText];
    [self _updateTypingAttributes];
}

// Takes the colour of the colour panel as the background when the application
// allows that (allowsDocumentBackgroundColorChange).
- (void) changeDocumentBackgroundColor: (id) sender {
    if (![self allowsDocumentBackgroundColorChange])
        return;
    NSColor *color = [sender color];
    if (color != nil)
        [self setBackgroundColor: color];
}

// There are no panels for these.
- (void) orderFrontSpacingPanel: (id) sender {
}

- (void) orderFrontListPanel: (id) sender {
}

- (void) orderFrontTablePanel: (id) sender {
}

- (void) orderFrontSubstitutionsPanel: (id) sender {
}

#pragma mark - Copying the font

// The font pasteboard holds the character attributes in effect for typing at the
// selection (the typing attributes: those of the first selected character as
// the selection last moved, not necessarily what the text holds now), as RTF
// of a space with them (observed on macOS 10.14.4 and 26.7.3: attributes
// added to the text after the selection was set are not copied).
// Test: appkit-textview-font-commands.m (copyFont:)
- (void) copyFont: (id) sender {
    NSAttributedString *sample = [[[NSAttributedString alloc] initWithString: @" "
                                                                  attributes: [self typingAttributes]] autorelease];
    NSData *data = [sample RTFFromRange: NSMakeRange(0, [sample length]) documentAttributes: nil];
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName: NSFontPboard];
    [pasteboard declareTypes: [NSArray arrayWithObject: NSFontPboardType] owner: nil];
    [pasteboard setData: data forType: NSFontPboardType];
}

- (void) pasteFont: (id) sender {
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName: NSFontPboard];
    NSData *data = [pasteboard dataForType: NSFontPboardType];
    if (data == nil)
        return;
    NSAttributedString *sample = [[[NSAttributedString alloc] initWithRTF: data
                                                       documentAttributes: NULL] autorelease];
    if ([sample length] == 0)
        return;

    NSMutableDictionary *attributes = [[[sample attributesAtIndex: 0 effectiveRange: NULL] mutableCopy] autorelease];
    // The paragraph style belongs to the ruler, not the font.
    [attributes removeObjectForKey: NSParagraphStyleAttributeName];

    NSArray *ranges = [self rangesForUserCharacterAttributeChange];
    if (ranges == nil)
        return;
    NSRange range = [[ranges objectAtIndex: 0] rangeValue];
    if (range.length > 0) {
        if (![self shouldChangeTextInRanges: ranges replacementStrings: nil])
            return;
        [self _addAttributes: attributes range: range];
        [self didChangeText];
        [self _updateTypingAttributes];
    } else {
        NSMutableDictionary *typing = [[[self typingAttributes] mutableCopy] autorelease];
        [typing addEntriesFromDictionary: attributes];
        [self setTypingAttributes: typing];
    }
}

#pragma mark - Base writing direction

// The writing direction of the whole text: the direction of the first
// paragraph, natural when no paragraph style says otherwise. Setting it changes
// every paragraph and the typing attributes, whatever the selection and
// whether or not the view is editable (observed on macOS 10.14.4 and 26.7.3).
// Test: appkit-textview-editing-api.m (base writing direction)
- (NSWritingDirection) baseWritingDirection {
    NSTextStorage *storage = [self textStorage];
    NSParagraphStyle *style = [storage length] > 0
            ? [storage attribute: NSParagraphStyleAttributeName atIndex: 0 effectiveRange: NULL]
            : [[self typingAttributes] objectForKey: NSParagraphStyleAttributeName];
    return style != nil ? [style baseWritingDirection] : NSWritingDirectionNatural;
}

- (void) setBaseWritingDirection: (NSWritingDirection) direction {
    NSTextStorage *storage = [self textStorage];
    if ([storage length] > 0)
        [storage setBaseWritingDirection: direction range: NSMakeRange(0, [storage length])];

    NSMutableDictionary *typing = [[[self typingAttributes] mutableCopy] autorelease];
    if (typing == nil)
        typing = [NSMutableDictionary dictionary];
    NSParagraphStyle *style = [typing objectForKey: NSParagraphStyleAttributeName];
    NSMutableParagraphStyle *changed = [[(style != nil ? style : [NSParagraphStyle defaultParagraphStyle]) mutableCopy] autorelease];
    [changed setBaseWritingDirection: direction];
    [typing setObject: changed forKey: NSParagraphStyleAttributeName];
    [self setTypingAttributes: typing];
}

#pragma mark - Toggles

- (void) toggleGrammarChecking: (id) sender {
    [self setGrammarCheckingEnabled: ![self isGrammarCheckingEnabled]];
}

- (void) toggleSmartInsertDelete: (id) sender {
    [self setSmartInsertDeleteEnabled: ![self smartInsertDeleteEnabled]];
}

- (void) toggleAutomaticQuoteSubstitution: (id) sender {
    [self setAutomaticQuoteSubstitutionEnabled: ![self isAutomaticQuoteSubstitutionEnabled]];
}

- (void) toggleAutomaticDashSubstitution: (id) sender {
    [self setAutomaticDashSubstitutionEnabled: ![self isAutomaticDashSubstitutionEnabled]];
}

- (void) toggleAutomaticLinkDetection: (id) sender {
    [self setAutomaticLinkDetectionEnabled: ![self isAutomaticLinkDetectionEnabled]];
}

- (void) toggleAutomaticDataDetection: (id) sender {
    [self setAutomaticDataDetectionEnabled: ![self isAutomaticDataDetectionEnabled]];
}

- (void) toggleAutomaticTextReplacement: (id) sender {
    [self setAutomaticTextReplacementEnabled: ![self isAutomaticTextReplacementEnabled]];
}

#pragma mark - Smart insert and delete

static BOOL _NSTextViewIsSpace(unichar c) {
    return [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: c];
}

// Hangul, kana and CJK ideographs do not take spaces between words.
static BOOL _NSTextViewIsUnspacedScript(unichar c) {
    return (c >= 0x1100 && c <= 0x11FF) || (c >= 0x2E80 && c <= 0x9FFF) ||
           (c >= 0xA960 && c <= 0xA97F) || (c >= 0xAC00 && c <= 0xD7FF) ||
           (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF66 && c <= 0xFF9F);
}

static BOOL _NSTextViewIsWordCharacter(unichar c) {
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember: c] &&
           !_NSTextViewIsUnspacedScript(c);
}

// Which characters want a space between them and an inserted word was read off
// macOS 10.14.4 and 26.7.3 by inserting next to each of about 100 characters
// (identical on both); it is not derived from a rule. A space is wanted after
// a word character, after a closing bracket and after most punctuation and
// symbols; it is not wanted after white space, opening brackets, quotes, a
// hyphen, a slash, a number sign, a dollar or currency sign, a backtick.
// Test: appkit-textview-smart-insert.m
static BOOL _NSTextViewSpaceWantedAfter(unichar c) {
    if (_NSTextViewIsWordCharacter(c))
        return YES;
    if (c < 128)
        return strchr(")]}>.,;:!?@%&*_+=|\\^~", c) != NULL && c != 0;
    return NO;
}

// ... and which want a space before the following character: word characters,
// and < $ + = | ^ ~ ` and the currency signs and the copyright sign.
static BOOL _NSTextViewSpaceWantedBefore(unichar c) {
    if (_NSTextViewIsWordCharacter(c))
        return YES;
    if (c < 128)
        return strchr("<$+=|^~`", c) != NULL && c != 0;
    return (c >= 0xA2 && c <= 0xA5) || c == 0xA9 || (c >= 0x20A0 && c <= 0x20CF);
}

- (void) _raiseIfRange: (NSRange) range beyondTextForSelector: (SEL) selector {
    if (NSMaxRange(range) > [[self string] length])
        [NSException raise: NSRangeException
                    format: @"-[%@ %@]: range %@ beyond the text of length %lu",
                            [self class], NSStringFromSelector(selector),
                            NSStringFromRange(range), (unsigned long) [[self string] length]];
}

// Removes the space that separates a deleted word from its neighbours when
// the neighbours do not need it: the space before the range when the next
// character does not want one, otherwise the space after the range when the
// character before does not want one (the characters on the far side of the
// space do not matter). The selection itself does not matter either. Read
// off macOS 10.14.4 and 26.7.3. The deletion commands do not use this by
// themselves there, nor do they here.
// Test: appkit-textview-smart-insert.m
- (NSRange) smartDeleteRangeForProposedRange: (NSRange) range {
    [self _raiseIfRange: range beyondTextForSelector: _cmd];
    if (![self smartInsertDeleteEnabled])
        return range;

    NSString *string = [self string];
    NSUInteger length = [string length];
    BOOL hasBefore = range.location > 0;
    BOOL hasAfter = NSMaxRange(range) < length;
    unichar before = hasBefore ? [string characterAtIndex: range.location - 1] : 0;
    unichar after = hasAfter ? [string characterAtIndex: NSMaxRange(range)] : 0;

    if (hasBefore && before == ' ' && (!hasAfter || !_NSTextViewSpaceWantedBefore(after))) {
        range.location -= 1;
        range.length += 1;
    } else if (hasAfter && after == ' ' && (!hasBefore || !_NSTextViewSpaceWantedAfter(before))) {
        range.length += 1;
    }
    return range;
}

// The spaces to put around inserted text: before it when the character before
// the replaced range wants one and the text does not start with white space,
// after it likewise. Nothing with smart insert and delete off. A range that
// starts beyond the text raises NSRangeException.
- (void) smartInsertForString: (NSString *) pasteString
               replacingRange: (NSRange) range
                 beforeString: (NSString **) beforeString
                  afterString: (NSString **) afterString
{
    NSString *before = nil;
    NSString *after = nil;

    // Only a start beyond the text raises; an end beyond the text is taken
    // as the end of the text (observed on macOS 10.14.4 and 26.7.3), unlike
    // smartDeleteRangeForProposedRange:, which raises for both.
    if (range.location > [[self string] length])
        [NSException raise: NSRangeException
                    format: @"-[%@ %@]: range %@ beyond the text of length %lu",
                            [self class], NSStringFromSelector(_cmd), NSStringFromRange(range),
                            (unsigned long) [[self string] length]];
    if ([self smartInsertDeleteEnabled]) {
        NSString *string = [self string];
        NSUInteger length = [string length];
        if (NSMaxRange(range) > length)
            range.length = length - range.location;
        BOOL startsWithSpace = [pasteString length] > 0 && _NSTextViewIsSpace([pasteString characterAtIndex: 0]);
        BOOL endsWithSpace = [pasteString length] > 0 &&
                _NSTextViewIsSpace([pasteString characterAtIndex: [pasteString length] - 1]);

        if (range.location > 0 && !startsWithSpace &&
            _NSTextViewSpaceWantedAfter([string characterAtIndex: range.location - 1]))
            before = @" ";
        if (NSMaxRange(range) < length && !endsWithSpace &&
            _NSTextViewSpaceWantedBefore([string characterAtIndex: NSMaxRange(range)]))
            after = @" ";
    }

    if (beforeString != NULL)
        *beforeString = before;
    if (afterString != NULL)
        *afterString = after;
}

- (NSString *) smartInsertBeforeStringForString: (NSString *) pasteString
                                 replacingRange: (NSRange) range
{
    NSString *before = nil;
    [self smartInsertForString: pasteString replacingRange: range beforeString: &before afterString: NULL];
    return before;
}

- (NSString *) smartInsertAfterStringForString: (NSString *) pasteString
                                replacingRange: (NSRange) range
{
    NSString *after = nil;
    [self smartInsertForString: pasteString replacingRange: range beforeString: NULL afterString: &after];
    return after;
}

#pragma mark - Pasteboard

// Types that can be read, best first: RTF, RTFD, plain text. None when the
// view is not editable (observed on macOS 10.14.4 and 26.7.3). Only the types
// that readSelectionFromPasteboard:type: handles are listed, which is fewer
// than on macOS (no HTML, URLs, file names, colours, fonts, rulers).
- (NSArray *) readablePasteboardTypes {
    if (![self isEditable])
        return [NSArray array];
    return [NSArray arrayWithObjects: NSRTFPboardType, NSRTFDPboardType, NSStringPboardType, nil];
}

// The most preferred readable type that is among the available types (and
// among the allowed ones when given); nil when there is none.
- (NSString *) preferredPasteboardTypeFromArray: (NSArray *) availableTypes
                     restrictedToTypesFromArray: (NSArray *) allowedTypes
{
    for (NSString *type in [self readablePasteboardTypes]) {
        if (![availableTypes containsObject: type])
            continue;
        if (allowedTypes != nil && ![allowedTypes containsObject: type])
            continue;
        return type;
    }
    return nil;
}

- (BOOL) readSelectionFromPasteboard: (NSPasteboard *) pasteboard {
    NSString *type = [self preferredPasteboardTypeFromArray: [pasteboard types]
                                 restrictedToTypesFromArray: nil];
    if (type == nil)
        return NO;
    return [self readSelectionFromPasteboard: pasteboard type: type];
}

// The services mechanism does not exist here, so there is nothing to register.
+ (void) registerForServices {
}

- (id) validRequestorForSendType: (NSString *) sendType returnType: (NSString *) returnType {
    BOOL sendable = sendType == nil ||
            ([[self writablePasteboardTypes] containsObject: sendType] && [self selectedRange].length > 0);
    BOOL returnable = returnType == nil ||
            ([self isEditable] && [[self readablePasteboardTypes] containsObject: returnType]);
    if (sendable && returnable)
        return self;
    return [super validRequestorForSendType: sendType returnType: returnType];
}

// Pastes the pasteboard like paste: but only types in the list. With smart
// insert and delete on and text that was copied with word boundaries (the
// smart paste type is on the pasteboard), spaces are added around it.
// Test: appkit-textview-smart-insert.m, appkit-textview-editing-api.m
- (void) _pasteRestrictedToTypes: (NSArray *) allowedTypes {
    if (![self isEditable])
        return;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSString *type = [self preferredPasteboardTypeFromArray: [pasteboard types]
                                 restrictedToTypesFromArray: allowedTypes];
    if (type == nil)
        return;

    id string = nil;
    if ([type isEqualToString: NSRTFPboardType] || [type isEqualToString: NSRTFDPboardType]) {
        NSData *data = [pasteboard dataForType: type];
        if (data != nil && [data length] > 0) {
            NSAttributedString *attributed = [type isEqualToString: NSRTFDPboardType]
                    ? [[[NSAttributedString alloc] initWithRTFD: data documentAttributes: NULL] autorelease]
                    : [[[NSAttributedString alloc] initWithRTF: data documentAttributes: NULL] autorelease];
            // A plain text view takes rich text as plain text.
            string = [self isRichText] ? (id) attributed : (id) [attributed string];
        }
    } else {
        string = [pasteboard stringForType: type];
    }
    if ([string length] == 0)
        return;

    NSRange selection = [self selectedRange];
    NSString *plain = [string isKindOfClass: [NSAttributedString class]] ? [string string] : string;

    if ([self smartInsertDeleteEnabled] &&
        [[pasteboard types] containsObject: _NSTextViewSmartPastePboardType] &&
        selection.location != NSNotFound && NSMaxRange(selection) <= [[self string] length]) {
        NSString *before = nil;
        NSString *after = nil;
        [self smartInsertForString: plain replacingRange: selection beforeString: &before afterString: &after];
        if (before != nil || after != nil) {
            NSMutableAttributedString *padded = [[[NSMutableAttributedString alloc] init] autorelease];
            NSDictionary *plainAttributes = [self typingAttributes];
            if (before != nil)
                [padded appendAttributedString: [[[NSAttributedString alloc] initWithString: before
                                                                                  attributes: plainAttributes] autorelease]];
            if ([string isKindOfClass: [NSAttributedString class]])
                [padded appendAttributedString: string];
            else
                [padded appendAttributedString: [[[NSAttributedString alloc] initWithString: string
                                                                                  attributes: plainAttributes] autorelease]];
            if (after != nil)
                [padded appendAttributedString: [[[NSAttributedString alloc] initWithString: after
                                                                                  attributes: plainAttributes] autorelease]];
            string = padded;
            plain = [padded string];
        }
    }

    if (![self shouldChangeTextInRange: selection replacementString: plain])
        return;
    [self _replaceCharactersInRange: selection
                         withString: string
                useTypingAttributes: NO];
    [self didChangeText];
}

- (void) pasteAsPlainText: (id) sender {
    [self _pasteRestrictedToTypes: [NSArray arrayWithObject: NSStringPboardType]];
}

- (void) pasteAsRichText: (id) sender {
    [self _pasteRestrictedToTypes: [NSArray arrayWithObjects: NSRTFPboardType, NSRTFDPboardType, nil]];
}

#pragma mark - Dragging

// The types a drop on the view is taken from: rich text and plain text.
// (macOS lists many more, and lists them whether or not the view is editable;
// observed on 10.14.4 and 26.7.3. Only these are handled here.)
- (NSArray *) acceptableDragTypes {
    return [NSArray arrayWithObjects: NSRTFPboardType, NSStringPboardType, nil];
}

// Registers for the acceptable types, or for nothing when the view cannot
// accept a drop.
- (void) updateDragTypeRegistration {
    if ([self isEditable])
        [self registerForDraggedTypes: [self acceptableDragTypes]];
    else
        [self unregisterDraggedTypes];
}

#pragma mark - Text checking

// Substitutions by checking. The results are made by the text view itself:
// quote and dash substitution and link detection. Spelling and grammar have
// their own path (continuous spell checking); replacement from the user's text
// replacement table, correction and data detection other than links have no
// source of results here.
- (void) checkTextInRange: (NSRange) range
                    types: (NSTextCheckingTypes) types
                  options: (NSDictionary *) options
{
    // A range beyond the text is cut to the text (it does not raise on macOS
    // 10.14.4 and 26.7.3).
    NSString *string = [self string];
    range = NSIntersectionRange(range, NSMakeRange(0, [string length]));

    id delegate = [self delegate];
    if ([delegate respondsToSelector: @selector(textView:willCheckTextInRange:options:types:)]) {
        NSDictionary *changed = [delegate textView: self
                              willCheckTextInRange: range
                                           options: options
                                             types: &types];
        if (changed != nil)
            options = changed;
    }

    NSMutableArray *results = [NSMutableArray array];

    if (types & NSTextCheckingTypeQuote)
        [self _addQuoteResultsTo: results forRange: range];
    if (types & NSTextCheckingTypeDash)
        [self _addDashResultsTo: results forRange: range];
    if (types & NSTextCheckingTypeLink)
        [self _addLinkResultsTo: results forRange: range];

    [self handleTextCheckingResults: results
                           forRange: range
                              types: types
                            options: options
                        orthography: nil
                          wordCount: 0];
}

// Applies results: replacements (quotes, dashes, text replacement, correction)
// only to text the user typed, or to everything while a whole-selection or
// whole-document check runs; links are set wherever they were found. The
// delegate sees and may change the results first.
- (void) handleTextCheckingResults: (NSArray *) results
                          forRange: (NSRange) range
                             types: (NSTextCheckingTypes) types
                           options: (NSDictionary *) options
                       orthography: (NSOrthography *) orthography
                         wordCount: (NSInteger) wordCount
{
    id delegate = [self delegate];
    if ([delegate respondsToSelector: @selector
                  (textView:didCheckTextInRange:types:options:results:orthography:wordCount:)]) {
        NSArray *changed = [delegate textView: self
                          didCheckTextInRange: range
                                        types: types
                                      options: options
                                      results: results
                                  orthography: orthography
                                    wordCount: wordCount];
        if (changed != nil)
            results = changed;
    }

    BOOL everything = NS_EXTRA(NSTextView, self)->_applyAllTextCheckingResults;
    BOOL typedKnown = NS_EXTRA(NSTextView, self)->_pendingTypedRangeValid;
    NSRange typed = NS_EXTRA(NSTextView, self)->_pendingTypedRange;
    NSTextStorage *storage = [self textStorage];

    // Back to front so that a replacement does not move the ranges still to
    // be applied.
    for (NSTextCheckingResult *result in [results reverseObjectEnumerator]) {
        NSRange resultRange = [result range];
        if (NSMaxRange(resultRange) > [storage length])
            continue;

        if ([result resultType] == NSTextCheckingTypeLink) {
            [self _addAttribute: NSLinkAttributeName value: [result URL] range: resultRange];
            continue;
        }

        NSString *replacement = [result replacementString];
        if (replacement == nil)
            continue;
        BOOL allowed = everything ||
                (typedKnown && resultRange.location >= typed.location &&
                 NSMaxRange(resultRange) <= NSMaxRange(typed));
        if (!allowed)
            continue;
        if (![self shouldChangeTextInRange: resultRange replacementString: replacement])
            continue;

        NSRange selection = [self selectedRange];
        NSDictionary *attributes = [storage attributesAtIndex: resultRange.location effectiveRange: NULL];
        [storage replaceCharactersInRange: resultRange
                     withAttributedString: [[[NSAttributedString alloc] initWithString: replacement
                                                                            attributes: attributes] autorelease]];
        // keep the insertion point where it was relative to the text
        NSInteger delta = (NSInteger) [replacement length] - (NSInteger) resultRange.length;
        if (selection.location >= NSMaxRange(resultRange))
            selection.location += delta;
        [self setSelectedRange: selection];
        [self didChangeText];
    }
}

// Applies the enabled substitutions to all of the selection, replacing text
// whatever its origin.
- (void) checkTextInSelection: (id) sender {
    NSRange range = [self selectedRange];
    if (range.length == 0)
        return;
    [self _checkAllTextInRange: range];
}

- (void) checkTextInDocument: (id) sender {
    [self _checkAllTextInRange: NSMakeRange(0, [[self string] length])];
}

- (void) _checkAllTextInRange: (NSRange) range {
    NS_EXTRA(NSTextView, self)->_applyAllTextCheckingResults = YES;
    @try {
        NSTextCheckingTypes types = [self enabledTextCheckingTypes] &
                (NSTextCheckingTypeQuote | NSTextCheckingTypeDash | NSTextCheckingTypeLink);
        [self checkTextInRange: range types: types options: [NSDictionary dictionary]];
    } @finally {
        NS_EXTRA(NSTextView, self)->_applyAllTextCheckingResults = NO;
    }
}

// Typed text goes through the enabled substitutions as it is typed. macOS
// checks in the background after the keystroke; here the check runs right
// away, over the paragraph, and may replace text from two characters before
// the typed text on (enough for a typed run of hyphens).
- (void) _applyTypedTextSubstitutionsForRange: (NSRange) typed {
    NSTextCheckingTypes types = [self enabledTextCheckingTypes] &
            (NSTextCheckingTypeQuote | NSTextCheckingTypeDash | NSTextCheckingTypeLink);
    if (types == 0 || typed.length == 0 || NSMaxRange(typed) > [[self string] length])
        return;

    NSUInteger start = typed.location >= 2 ? typed.location - 2 : 0;
    NSRange window = NSMakeRange(start, NSMaxRange(typed) - start);
    NS_EXTRA(NSTextView, self)->_pendingTypedRange = window;
    NS_EXTRA(NSTextView, self)->_pendingTypedRangeValid = YES;
    @try {
        NSRange paragraph = [[self string] paragraphRangeForRange: typed];
        [self checkTextInRange: paragraph types: types options: [NSDictionary dictionary]];
    } @finally {
        NS_EXTRA(NSTextView, self)->_pendingTypedRangeValid = NO;
    }
}

// Straight quotes become curly: a quote that starts the text, follows white
// space or an opening bracket opens, every other one closes (an apostrophe
// inside a word is a closing single quote). Observed on macOS 10.14.4 and
// 26.7.3 with pairs, nested quotes, apostrophes and an empty pair.
// Test: appkit-textview-text-checking.m
- (void) _addQuoteResultsTo: (NSMutableArray *) results forRange: (NSRange) range {
    NSString *string = [self string];
    for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
        unichar c = [string characterAtIndex: i];
        if (c != '"' && c != '\'')
            continue;
        BOOL opens = i == 0;
        if (!opens) {
            unichar before = [string characterAtIndex: i - 1];
            opens = _NSTextViewIsSpace(before) || before == '(' || before == '[' || before == '{';
        }
        unichar replacement = c == '"' ? (opens ? 0x201C : 0x201D) : (opens ? 0x2018 : 0x2019);
        [results addObject: [NSTextCheckingResult
                                    quoteCheckingResultWithRange: NSMakeRange(i, 1)
                                               replacementString: [NSString stringWithCharacters: &replacement
                                                                                           length: 1]]];
    }
}

// Two or more hyphens become one em dash and three dots one ellipsis (both
// under dash substitution on macOS 10.14.4 and 26.7.3; a single spaced hyphen
// and an en dash are left alone).
// Test: appkit-textview-text-checking.m
- (void) _addDashResultsTo: (NSMutableArray *) results forRange: (NSRange) range {
    NSString *string = [self string];
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        unichar c = [string characterAtIndex: i];
        if (c == '-' || c == '.') {
            NSUInteger end = i;
            while (end < NSMaxRange(range) && [string characterAtIndex: end] == c)
                end++;
            NSUInteger count = end - i;
            if (c == '-' && count >= 2) {
                unichar dash = 0x2014;
                [results addObject: [NSTextCheckingResult
                                            dashCheckingResultWithRange: NSMakeRange(i, count)
                                                      replacementString: [NSString stringWithCharacters: &dash length: 1]]];
            } else if (c == '.' && count == 3) {
                unichar ellipsis = 0x2026;
                [results addObject: [NSTextCheckingResult
                                            dashCheckingResultWithRange: NSMakeRange(i, count)
                                                      replacementString: [NSString stringWithCharacters: &ellipsis length: 1]]];
            }
            i = end;
        } else {
            i++;
        }
    }
}

// Links: a word with a scheme (xyz://, mailto:), starting with www., or shaped
// like an e-mail address, without the punctuation that ends a sentence.
// Observed on macOS 26.7.3 (www. gets http://, an address gets mailto:).
// Test: appkit-textview-text-checking.m
- (void) _addLinkResultsTo: (NSMutableArray *) results forRange: (NSRange) range {
    NSString *string = [self string];
    NSCharacterSet *separators = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trailing = @".,;:!?)]}'\"";
    NSUInteger i = range.location;

    while (i < NSMaxRange(range)) {
        while (i < NSMaxRange(range) && [separators characterIsMember: [string characterAtIndex: i]])
            i++;
        NSUInteger start = i;
        while (i < NSMaxRange(range) && ![separators characterIsMember: [string characterAtIndex: i]])
            i++;
        NSUInteger end = i;
        // a word cut by the range is not a whole word
        if (start == end || (start == range.location && start > 0 &&
                             ![separators characterIsMember: [string characterAtIndex: start - 1]]))
            continue;
        while (end > start && [trailing rangeOfString: [string substringWithRange: NSMakeRange(end - 1, 1)]].location != NSNotFound)
            end--;
        if (end == start)
            continue;

        NSString *word = [string substringWithRange: NSMakeRange(start, end - start)];
        NSString *urlString = nil;
        NSRange scheme = [word rangeOfString: @"://"];
        if (scheme.location != NSNotFound && scheme.location > 0 && NSMaxRange(scheme) < [word length])
            urlString = word;
        else if ([word hasPrefix: @"mailto:"] && [word length] > 7)
            urlString = word;
        else if ([[word lowercaseString] hasPrefix: @"www."] && [word length] > 4)
            urlString = [@"http://" stringByAppendingString: word];
        else {
            NSRange at = [word rangeOfString: @"@"];
            NSRange dot = [word rangeOfString: @"." options: NSBackwardsSearch];
            if (at.location != NSNotFound && at.location > 0 && at.location == [word rangeOfString: @"@" options: NSBackwardsSearch].location &&
                dot.location != NSNotFound && dot.location > NSMaxRange(at) && dot.location + 1 < [word length])
                urlString = [@"mailto:" stringByAppendingString: word];
        }

        NSURL *url = urlString != nil ? [NSURL URLWithString: urlString] : nil;
        if (url != nil)
            [results addObject: [NSTextCheckingResult linkCheckingResultWithRange: NSMakeRange(start, end - start)
                                                                              URL: url]];
    }
}

#pragma mark - Geometry and text container

- (void) invalidateTextContainerOrigin {
    [self updateRuler];
    [self setNeedsDisplay: YES];
}

// Gives the view another text container, keeping the layout manager and the
// text storage (and so the text): the new container takes the old one's place
// in the layout manager.
- (void) replaceTextContainer: (NSTextContainer *) newContainer {
    NSTextContainer *old = NS_EXTRA(NSTextView, self)->_textContainer;
    if (newContainer == old)
        return;

    [[self retain] autorelease];
    [[old retain] autorelease];

    NSLayoutManager *layoutManager = [old layoutManager];
    NSTextStorage *storage = NS_EXTRA(NSTextView, self)->_textStorage;
    BOOL ownsStorage = NS_EXTRA(NSTextView, self)->_ownsTextStorage;
    // setTextContainer: lets go of the storage the view owns; hold it across
    if (ownsStorage)
        [storage retain];

    if (layoutManager != nil && newContainer != nil) {
        NSUInteger index = [[layoutManager textContainers] indexOfObjectIdenticalTo: old];
        if (index != NSNotFound) {
            [layoutManager insertTextContainer: newContainer atIndex: index];
            [layoutManager removeTextContainerAtIndex: index + 1];
        } else {
            [layoutManager addTextContainer: newContainer];
        }
    }

    [old setTextView: nil];
    [old setLayoutManager: nil];
    [newContainer setTextView: self];

    if (ownsStorage) {
        NS_EXTRA(NSTextView, self)->_textStorage = storage;
        NS_EXTRA(NSTextView, self)->_ownsTextStorage = YES;
    }
    [self invalidateTextContainerOrigin];
}

// The frame size of the view, limited by minSize and maxSize in the directions
// the view resizes in; the other direction keeps its size. (On macOS a view
// that resizes both ways also shrinks to the text it holds afterwards; that is
// not done here.)
// Test: appkit-textview-editing-api.m
- (void) setConstrainedFrameSize: (NSSize) size {
    NSSize current = [self frame].size;
    NSSize minimum = [self minSize];
    NSSize maximum = [self maxSize];

    if ([self isHorizontallyResizable])
        size.width = MIN(MAX(size.width, minimum.width), maximum.width);
    else
        size.width = current.width;
    if ([self isVerticallyResizable])
        size.height = MIN(MAX(size.height, minimum.height), maximum.height);
    else
        size.height = current.height;

    [self setFrameSize: size];
}

// The index at which an insertion point goes for a mouse position: the nearest
// boundary between characters, the start of the text above it and the end
// below it (and to the right of the last line).
// Test: appkit-textview-editing-api.m
- (NSUInteger) characterIndexForInsertionAtPoint: (NSPoint) point {
    NSTextStorage *storage = [self textStorage];
    NSUInteger length = [storage length];
    if (length == 0)
        return 0;

    CGFloat fraction = 0;
    NSUInteger glyph = [self glyphIndexForPoint: point fractionOfDistanceThroughGlyph: &fraction];
    if (glyph == NSNotFound)
        return point.y < 0 ? 0 : length;

    NSUInteger index = [[self layoutManager] characterIndexForGlyphAtIndex: glyph];
    if (fraction >= 0.5)
        index++;
    return MIN(index, length);
}

- (void) drawViewBackgroundInRect: (NSRect) rect {
    if ([self drawsBackground]) {
        [[self backgroundColor] setFill];
        NSRectFill(rect);
    }
}

// Alignment of the paragraphs the range touches (an insertion point inside the
// range changes the typing attributes too).
- (void) setAlignment: (NSTextAlignment) alignment range: (NSRange) range {
    NSTextStorage *storage = [self textStorage];
    if (NSMaxRange(range) > [storage length])
        [NSException raise: NSRangeException
                    format: @"-[%@ %@]: range %@ beyond the text of length %lu",
                            [self class], NSStringFromSelector(_cmd), NSStringFromRange(range),
                            (unsigned long) [storage length]];

    NSRange paragraphs = [[storage string] paragraphRangeForRange: range];
    if (paragraphs.length > 0 && ![self shouldChangeTextInRange: paragraphs replacementString: nil])
        return;
    [self _setAlignment: alignment range: paragraphs];
    if (paragraphs.length > 0)
        [self didChangeText];
}

// Replaces the range with the attributed string, after the delegate agreed,
// with the attributes of the text at the start of the range filling in what
// the string does not set. Returns whether the replacement happened.
- (BOOL) performValidatedReplacementInRange: (NSRange) range
                       withAttributedString: (NSAttributedString *) attributedString
{
    NSTextStorage *storage = [self textStorage];
    if (NSMaxRange(range) > [storage length])
        [NSException raise: NSRangeException
                    format: @"-[%@ %@]: range %@ beyond the text of length %lu",
                            [self class], NSStringFromSelector(_cmd), NSStringFromRange(range),
                            (unsigned long) [storage length]];

    if (![self shouldChangeTextInRange: range replacementString: [attributedString string]])
        return NO;

    NSMutableAttributedString *complete = [[attributedString mutableCopy] autorelease];
    if ([storage length] > 0) {
        NSUInteger at = range.location < [storage length] ? range.location : [storage length] - 1;
        NSDictionary *base = [storage attributesAtIndex: at effectiveRange: NULL];
        NSUInteger location = 0;
        while (location < [complete length]) {
            NSRange run;
            NSDictionary *own = [complete attributesAtIndex: location effectiveRange: &run];
            NSMutableDictionary *merged = [[base mutableCopy] autorelease];
            [merged addEntriesFromDictionary: own];
            [complete setAttributes: merged range: run];
            location = NSMaxRange(run);
        }
    }

    [self _replaceCharactersInRange: range
                         withString: complete
                useTypingAttributes: NO];
    [self didChangeText];
    return YES;
}

// The ownership policy that macOS 10.12 introduced (the text view keeps its
// text storage alive and the text container does not keep the view alive) is
// not implemented: applications that create the pieces of the text system
// themselves must keep the storage as they did before.
+ (BOOL) stronglyReferencesTextStorage {
    return NO;
}

#pragma mark - Factory methods

// The text views the 10.14 factory methods make: a text view inside a scroll
// view that has a vertical scroller only and no border, the text view growing
// downwards with the width of its container following the view. Values read
// off macOS 10.14.4 and 26.7.3 (identical): the rich document view has a
// ruler, a find bar, graphics import and the font panel; the plain one has a
// find bar only; the plain "scrollableTextView" has none of those.
// Test: appkit-textview-api-defaults.m
+ (NSScrollView *) _scrollableTextViewRich: (BOOL) rich
                                  findBar: (BOOL) findBar
                              fullFeature: (BOOL) fullFeature
{
    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame: NSZeroRect] autorelease];
    [scrollView setHasVerticalScroller: YES];
    [scrollView setHasHorizontalScroller: NO];
    [scrollView setAutohidesScrollers: NO];
    [scrollView setBorderType: NSNoBorder];
    [scrollView setDrawsBackground: NO];

    NSTextView *textView = [[[self alloc] initWithFrame: NSZeroRect] autorelease];
    [textView setRichText: rich];
    [textView setUsesFontPanel: fullFeature];
    [textView setImportsGraphics: fullFeature];
    [textView setUsesFindBar: findBar];
    [textView setMinSize: NSMakeSize(0, 0)];
    [textView setMaxSize: NSMakeSize(NSWidth([textView frame]), _NSTextViewLargeNumberForText)];
    [textView setVerticallyResizable: YES];
    [textView setHorizontallyResizable: NO];
    [textView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [[textView textContainer] setWidthTracksTextView: YES];
    [[textView textContainer] setHeightTracksTextView: NO];
    [[textView textContainer] setContainerSize: NSMakeSize(NSWidth([textView frame]), _NSTextViewLargeNumberForText)];

    [scrollView setDocumentView: textView];
    return scrollView;
}

+ (NSScrollView *) scrollableTextView {
    return [self _scrollableTextViewRich: NO findBar: NO fullFeature: NO];
}

+ (NSScrollView *) scrollableDocumentContentTextView {
    return [self _scrollableTextViewRich: YES findBar: YES fullFeature: YES];
}

+ (NSScrollView *) scrollablePlainDocumentContentTextView {
    return [self _scrollableTextViewRich: NO findBar: YES fullFeature: NO];
}

// A field editor: rich text, not resizing horizontally, a container that does
// not follow the view's width (observed on macOS 10.14.4 and 26.7.3).
+ (instancetype) fieldEditor {
    NSTextView *textView = [[[self alloc] initWithFrame: NSZeroRect] autorelease];
    [textView setFieldEditor: YES];
    [textView setVerticallyResizable: YES];
    [textView setHorizontallyResizable: NO];
    [[textView textContainer] setWidthTracksTextView: NO];
    [[textView textContainer] setContainerSize: NSMakeSize(9.0e6, _NSTextViewLargeNumberForText)];
    return textView;
}

@end
