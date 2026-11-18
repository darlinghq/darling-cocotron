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
#import <AppKit/NSControl.h>
#import <AppKit/NSTextFieldCell.h>

// Legacy ObjC ABI (i386): instance size must stay 0x64, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
NS_ASSUME_NONNULL_BEGIN

@interface NSTextField : NSControl {
    id _delegate;
    NS_EXTRA_IVARS_BEGIN(NSTextField)
        SEL _errorAction;
        CGFloat _preferredMaxLayoutWidth;
        BOOL _automaticTextCompletionEnabled;
        CGFloat _layoutWidth;
    NS_EXTRA_IVARS_END(NSTextField)
}

@property CGFloat preferredMaxLayoutWidth;
@property NSTextFieldBezelStyle bezelStyle;
@property(getter=isAutomaticTextCompletionEnabled) BOOL automaticTextCompletionEnabled;

- (null_unspecified id) delegate;
- (void) setDelegate: (null_unspecified id) delegate;

@property(nullable, nonatomic, retain) NSColor *backgroundColor;
@property(nullable, nonatomic, retain) NSColor *textColor;
@property(nonatomic) BOOL drawsBackground;

- (NSTextFieldBezelStyle) bezelStyle;
- (void) setBezelStyle: (NSTextFieldBezelStyle) style;

@property(nonatomic) BOOL allowsEditingTextAttributes;

- (NSInteger) maximumNumberOfLines;
@property(nullable, copy) NSString *placeholderString;
@property(nullable, copy) NSAttributedString *placeholderAttributedString;

- (void) selectText: (nullable id) sender;

- (null_unspecified id) previousText;
- (null_unspecified id) nextText;

- (void) setPreviousText: (null_unspecified id) text;
- (void) setNextText: (null_unspecified id) text;

- (void) setTitleWithMnemonic: (null_unspecified NSString *) value;

// Convenience constructor for a non-editable, borderless label (10.12)
+ (instancetype) labelWithString: (NSString *) stringValue;
// Convenience constructors (10.12): a label that wraps and an editable,
// bezeled text field
+ (instancetype) wrappingLabelWithString: (NSString *) stringValue;
+ (instancetype) textFieldWithString: (NSString *) stringValue;
+ (instancetype) labelWithAttributedString: (NSAttributedString *) attributedStringValue;

@end

@protocol NSTextFieldDelegate <NSObject>

// TODO

@end

NS_ASSUME_NONNULL_END
