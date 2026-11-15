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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSView.h>

@class NSFont;

typedef NS_ENUM(NSUInteger, NSTitlePosition) {
    NSNoTitle,
    NSAboveTop,
    NSAtTop,
    NSBelowTop,
    NSAboveBottom,
    NSAtBottom,
    NSBelowBottom,
};

typedef NS_ENUM(NSUInteger, NSBoxType) {
    NSBoxPrimary,
    NSBoxSecondary,
    NSBoxSeparator,
    NSBoxOldStyle,
    NSBoxCustom
};

// Legacy ObjC ABI (i386): instance size must stay 0x88, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSBox : NSView {
    id _titleCell;
    NS_LEGACY_IVAR_PAD(_NSBoxReserved1, 4)
    NSSize _contentViewMargins;
    NS_LEGACY_IVAR_PAD(_NSBoxReserved2, 36)
    NS_EXTRA_IVARS_BEGIN(NSBox)
        NSBoxType _boxType;
        NSBorderType _borderType;
        NSTitlePosition _titlePosition;
        BOOL _isTransparent;
        id _customData;
    NS_EXTRA_IVARS_END(NSBox)
}

@property(nonatomic) NSBoxType boxType;
@property(nonatomic) NSBorderType borderType;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, retain) NSFont *titleFont;
- contentView;
@property(nonatomic) NSSize contentViewMargins;
@property(nonatomic) NSTitlePosition titlePosition;
@property(nonatomic, getter=isTransparent) BOOL transparent;

- (void) setContentView: (NSView *) view;
- (void) setTitleWithMnemonic: (NSString *) value;

- (NSRect) titleRect;
- (NSRect) borderRect;
- titleCell;

- (void) setFrameFromContentFrame: (NSRect) content;
- (void) sizeToFit;

@property(nonatomic) CGFloat borderWidth;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic, retain) NSColor *borderColor;
@property(nonatomic, retain) NSColor *fillColor;


@end
