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

#import <AppKit/NSControl.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSColor;

// The looks and click behaviour a color well can be given (macOS 13): a standard well, a slimmer one and one with
// an extra button. The values are those of the public header.
typedef NS_ENUM(NSInteger, NSColorWellStyle) {
    NSColorWellStyleDefault = 0,
    NSColorWellStyleMinimal = 1,
    NSColorWellStyleExpanded = 2,
};

#define _NS_SIDE_NSColorWell 0, 1,
// Legacy ObjC ABI (i386): instance size must stay 0x6c, Apple's. New state goes to the side struct, never
// to an ivar of its own.
@interface NSColorWell : NSControl {
    NSColor *_color;
    id _target;
    SEL _action;
    // six flags in one 32-bit unit, so that the class keeps its Apple size
    // (on the legacy ObjC ABI an application's subclass sits right after it)
    unsigned _isEnabled : 1;
    unsigned _isContinuous : 1;
    unsigned _isBordered : 1;
    unsigned _isActive : 1;
    unsigned _notifyingColorPanel : 1;
    unsigned _doesNotSupportAlpha : 1; // inverted, so that a zeroed well supports alpha
    NS_EXTRA_IVARS_BEGIN(NSColorWell)
        NSColorWellStyle _colorWellStyle;
    NS_SIDE_IVARS_END(NSColorWell)
}

- (NSColor *) color;
- (BOOL) isBordered;
- (BOOL) isActive;

// Which of the styles the well uses; stored only. Starts as NSColorWellStyleDefault.
@property NSColorWellStyle colorWellStyle API_AVAILABLE(macos(13.0));

- (void) setColor: (NSColor *) color;
- (void) setBordered: (BOOL) flag;

- (void) activate: (BOOL) exclusive;
- (void) deactivate;

- (void) drawWellInside: (NSRect) rect;

- (void) takeColorFrom: sender;

// Whether the color panel offers opacity while the well is active (default YES).
@property BOOL supportsAlpha;

@end
