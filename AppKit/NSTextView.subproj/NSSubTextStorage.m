/*
 This file is part of Darling.

 Copyright (C) 2026 Darling developers

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

#import <AppKit/NSTextStorage.h>
#import <Foundation/NSException.h>
#import <objc/runtime.h>

// NSSubTextStorage is an undocumented AppKit class: a text storage that shows
// one range of another (parent) text storage. Script Editor creates one with
// -initWithTextStorage:range:, asks it for -range and reads its _range ivar by
// name through the runtime, so that ivar has to exist with this name and type.
//
// Reads and edits go to the parent: an edit through this storage changes the
// parent and grows or shrinks the range. Edits made directly to the parent
// don't move the range; it is only clamped to the parent's length.
@interface NSSubTextStorage : NSTextStorage {
    NSTextStorage *_textStorage;
    NSRange _range;
}

- (instancetype) initWithTextStorage: (NSTextStorage *) textStorage
                               range: (NSRange) range;
- (NSRange) range;

@end

@implementation NSSubTextStorage

- (instancetype) initWithTextStorage: (NSTextStorage *) textStorage
                               range: (NSRange) range
{
    // NSTextStorage's -initWithString: only sets up the layout manager list.
    self = [super initWithString: @""];
    if (self == nil)
        return nil;

    if (textStorage == nil)
        textStorage = [[[NSTextStorage alloc] init] autorelease];
    _textStorage = [textStorage retain];
    _range = range;
    [self _clampRange];
    return self;
}

// Standalone instances keep their text in a private parent storage.
- init {
    return [self initWithString: @""];
}

- initWithString: (NSString *) string {
    NSTextStorage *parent =
            [[NSTextStorage alloc] initWithString: string ? string : @""];
    self = [self initWithTextStorage: parent
                               range: NSMakeRange(0, [parent length])];
    [parent release];
    return self;
}

- initWithString: (NSString *) string attributes: (NSDictionary *) attributes {
    self = [self initWithString: string];
    if (self != nil && attributes != nil && [_textStorage length] > 0)
        [_textStorage setAttributes: attributes
                              range: NSMakeRange(0, [_textStorage length])];
    return self;
}

- initWithAttributedString: (NSAttributedString *) attributedString {
    self = [self initWithString: @""];
    if (self != nil && attributedString != nil) {
        [_textStorage replaceCharactersInRange: NSMakeRange(0, 0)
                          withAttributedString: attributedString];
        _range = NSMakeRange(0, [_textStorage length]);
    }
    return self;
}

- (void) dealloc {
    [_textStorage release];
    [super dealloc];
}

// Keeps the range inside the parent, which may have been edited directly.
- (void) _clampRange {
    NSUInteger length = [_textStorage length];

    if (_range.location > length)
        _range.location = length;
    if (_range.length > length - _range.location)
        _range.length = length - _range.location;
}

- (void) _checkRange: (NSRange) range selector: (SEL) selector {
    if (range.location > _range.length ||
        range.length > _range.length - range.location)
        [NSException raise: NSRangeException
                    format: @"-[%@ %s]: range {%lu, %lu} out of bounds; "
                            @"length %lu",
                            [self class], sel_getName(selector),
                            (unsigned long) range.location,
                            (unsigned long) range.length,
                            (unsigned long) _range.length];
}

- (NSRange) range {
    [self _clampRange];
    return _range;
}

- (NSUInteger) length {
    [self _clampRange];
    return _range.length;
}

- (NSString *) string {
    [self _clampRange];
    return [[_textStorage string] substringWithRange: _range];
}

- (NSDictionary *) attributesAtIndex: (NSUInteger) location
                      effectiveRange: (NSRangePointer) effectiveRangep
{
    NSRange parentRange;
    NSDictionary *attributes;

    [self _clampRange];
    if (location > _range.length)
        [NSException raise: NSRangeException
                    format: @"-[%@ %s]: index %lu beyond length %lu",
                            [self class], sel_getName(_cmd),
                            (unsigned long) location,
                            (unsigned long) _range.length];

    attributes = [_textStorage attributesAtIndex: _range.location + location
                                  effectiveRange: &parentRange];

    if (effectiveRangep != NULL) {
        // Clip the parent's run to this range, in this storage's coordinates.
        NSUInteger start = MAX(parentRange.location, _range.location);
        NSUInteger end = MIN(NSMaxRange(parentRange), NSMaxRange(_range));

        if (end > start)
            *effectiveRangep = NSMakeRange(start - _range.location, end - start);
        else
            *effectiveRangep = NSMakeRange(location, 0);
    }
    return attributes;
}

- (void) replaceCharactersInRange: (NSRange) range
                       withString: (NSString *) string
{
    NSInteger delta;

    [self _clampRange];
    [self _checkRange: range selector: _cmd];

    delta = (NSInteger) [string length] - (NSInteger) range.length;
    [_textStorage replaceCharactersInRange: NSMakeRange(_range.location +
                                                                range.location,
                                                        range.length)
                                withString: string];
    _range.length += delta;
    [self edited: NSTextStorageEditedAttributes | NSTextStorageEditedCharacters
                     range: range
            changeInLength: delta];
}

- (void) replaceCharactersInRange: (NSRange) range
             withAttributedString: (NSAttributedString *) attributedString
{
    NSInteger delta;

    [self _clampRange];
    [self _checkRange: range selector: _cmd];

    delta = (NSInteger) [attributedString length] - (NSInteger) range.length;
    [_textStorage replaceCharactersInRange: NSMakeRange(_range.location +
                                                                range.location,
                                                        range.length)
                      withAttributedString: attributedString];
    _range.length += delta;
    [self edited: NSTextStorageEditedAttributes | NSTextStorageEditedCharacters
                     range: range
            changeInLength: delta];
}

- (void) setAttributes: (NSDictionary *) attributes range: (NSRange) range {
    [self _clampRange];
    [self _checkRange: range selector: _cmd];

    [_textStorage setAttributes: attributes
                          range: NSMakeRange(_range.location + range.location,
                                             range.length)];
    [self edited: NSTextStorageEditedAttributes range: range changeInLength: 0];
}

- (NSMutableString *) mutableString {
    return [[[NSClassFromString(
            @"NSMutableStringProxyForMutableAttributedString")
            allocWithZone: NULL]
            performSelector: @selector(initWithMutableAttributedString:)
                 withObject: self] autorelease];
}

// The parent fixes its own attributes when it processes the forwarded edit.
- (void) fixAttributesInRange: (NSRange) range {
}

@end
