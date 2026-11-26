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

#import <AppKit/NSTokenFieldCell.h>
#import <Foundation/NSCharacterSet.h>

@implementation NSTokenFieldCell

+ (NSTimeInterval) defaultCompletionDelay {
    return 0;
}

+ (NSCharacterSet *) defaultTokenizingCharacterSet {
    return [NSCharacterSet characterSetWithCharactersInString: @","];
}

- (NSTokenStyle) tokenStyle {
    return _style;
}

- (NSCharacterSet *) tokenizingCharacterSet {
    return _set;
}

- (NSTimeInterval) completionDelay {
    return _completionDelay;
}

- delegate {
    return _delegate;
}

- (void) setTokenStyle: (NSTokenStyle) style {
    _style = style;
}

- (void) setTokenizingCharacterSet: (NSCharacterSet *) set {
    set = [set copy];
    [_set release];
    _set = set;
}

- (void) setCompletionDelay: (NSTimeInterval) delay {
    _completionDelay = delay;
}

- (void) setDelegate: delegate {
    _delegate = delegate;
}

// The character that separates the tokens in the string of the cell: the first of the tokenizing character set
// (a comma unless the set says otherwise), looked for among the printable ASCII characters.
static NSString *tokenSeparator(NSCharacterSet *set) {
    if (set == nil)
        return @",";
    for (unichar c = 0x20; c < 0x7F; c++)
        if ([set characterIsMember: c])
            return [NSString stringWithCharacters: &c length: 1];
    return @",";
}

// The string a token shows: the delegate's display string for it, else the token itself when it is a string.
// A token that has none is left out. See tests/appkit-token-field-cell-string-value.m.
static NSString *displayStringForToken(NSTokenFieldCell *cell, id token) {
    id delegate = [cell delegate];
    if ([delegate respondsToSelector: @selector(tokenFieldCell:displayStringForRepresentedObject:)])
        return [delegate tokenFieldCell: cell displayStringForRepresentedObject: token];
    return [token isKindOfClass: [NSString class]] ? token : nil;
}

- (NSString *) stringValue {
    id value = [self objectValue];
    if (![value isKindOfClass: [NSArray class]])
        return [super stringValue];

    NSMutableArray *parts = [NSMutableArray arrayWithCapacity: [value count]];
    for (id token in (NSArray *) value) {
        NSString *display = displayStringForToken(self, token);
        if (display != nil)
            [parts addObject: display];
    }
    return [parts componentsJoinedByString: tokenSeparator([self tokenizingCharacterSet])];
}

@end
