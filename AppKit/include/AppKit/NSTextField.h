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
@interface NSTextField : NSControl {
    id _delegate;
    NS_EXTRA_IVARS_BEGIN(NSTextField)
        SEL _errorAction;
        CGFloat _preferredMaxLayoutWidth;
        BOOL _automaticTextCompletionEnabled;
    NS_EXTRA_IVARS_END(NSTextField)
}

@property CGFloat preferredMaxLayoutWidth;
@property NSTextFieldBezelStyle bezelStyle;
@property(getter=isAutomaticTextCompletionEnabled) BOOL automaticTextCompletionEnabled;

- delegate;
- (void) setDelegate: delegate;

@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *textColor;
@property(nonatomic) BOOL drawsBackground;

- (NSTextFieldBezelStyle) bezelStyle;
- (void) setBezelStyle: (NSTextFieldBezelStyle) style;

@property(nonatomic) BOOL allowsEditingTextAttributes;

- (NSInteger) maximumNumberOfLines;
@property(copy) NSString *placeholderString;
@property(copy) NSAttributedString *placeholderAttributedString;

- (void) selectText: sender;

- previousText;
- nextText;

- (void) setPreviousText: text;
- (void) setNextText: text;

- (void) setTitleWithMnemonic: (NSString *) value;

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
