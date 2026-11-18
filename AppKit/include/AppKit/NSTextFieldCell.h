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
#import <AppKit/NSActionCell.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NSTextFieldBezelStyle) {
    NSTextFieldSquareBezel = 0,
    NSTextFieldRoundedBezel = 1,
};

// Legacy ObjC ABI (i386): instance size must stay 0x30, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSTextFieldCell : NSActionCell {
    NSColor *_backgroundColor;
    NSColor *_textColor;
    NS_EXTRA_IVARS_BEGIN(NSTextFieldCell)
        BOOL _drawsBackground;
        NSTextFieldBezelStyle _bezelStyle;
        id _placeholder;
        NSArray<NSString *> *_allowedInputSourceLocales;
    NS_EXTRA_IVARS_END(NSTextFieldCell)
}

@property(nullable, copy) NSArray<NSString *> *allowedInputSourceLocales;

@property(nullable, nonatomic, retain) NSColor *backgroundColor;
@property(nullable, nonatomic, retain) NSColor *textColor;
@property(nonatomic) BOOL drawsBackground;
@property(nonatomic) NSTextFieldBezelStyle bezelStyle;

@property(nullable, nonatomic, copy) NSString *placeholderString;
@property(nullable, nonatomic, copy) NSAttributedString *placeholderAttributedString;



@end

NS_ASSUME_NONNULL_END
