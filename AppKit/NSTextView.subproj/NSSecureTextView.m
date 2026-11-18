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
#import <AppKit/NSSecureLayoutManager.h>
#import <AppKit/NSSecureTextView.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSTextStorage.h>

@implementation NSSecureTextView

- initWithFrame: (NSRect) frame {
    NSLayoutManager *removeManager;
    NSSecureLayoutManager *secureManager =
            [[NSSecureLayoutManager new] autorelease];

    [super initWithFrame: frame];

    removeManager = [self layoutManager];

    [[self textStorage] addLayoutManager: secureManager];
    [secureManager addTextContainer: [self textContainer]];
    [[self textStorage] removeLayoutManager: removeManager];

    return self;
}

- (void) setEchosBullets: (BOOL) yorn {
    [(NSSecureLayoutManager *) [self layoutManager] setEchosBullets: yorn];
}

- (BOOL) writeSelectionToPasteboard: (NSPasteboard *) pboard
                               type: (NSString *) type
{
    return NO;
}

- (BOOL) writeSelectionToPasteboard: (NSPasteboard *) pboard
                              types: (NSArray *) types
{
    return NO;
}

// QUIRK: cut: deletes the selection without putting it on the pasteboard, paste: inserts the
// pasteboard text as in any text view, and copy: does nothing; the Cut and Copy menu commands
// are unavailable. Not documented. Evidence: black-box observation of the field editor of a
// secure text field on macOS 10.14.4 (tier 2): the pasteboard held its earlier text after copy:
// and cut:, the selection was removed by cut:, and the pasteboard text was inserted by paste:.
// Test: appkit-secure-text-field-cut-paste.m
- (void) cut: sender {
    if ([self selectedRange].length > 0)
        [self deleteBackward: sender];
}

- (void) copy: sender {
}

- (BOOL) validateMenuItem: (NSMenuItem *) item {
    if ([item action] == @selector(cut:) || [item action] == @selector(copy:))
        return NO;
    return [super validateMenuItem: item];
}

@end
