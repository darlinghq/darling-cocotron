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
#import <AppKit/NSCell.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>

@class NSCell, NSFont, NSText, NSTextView, NSControlAuxiliary;

NS_ASSUME_NONNULL_BEGIN

APPKIT_EXPORT const NSNotificationName NSControlTextDidBeginEditingNotification;
APPKIT_EXPORT const NSNotificationName NSControlTextDidChangeNotification;
APPKIT_EXPORT const NSNotificationName NSControlTextDidEndEditingNotification;

// Legacy ObjC ABI (i386): instance size must stay 0x5c, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSControl : NSView {
    NSControlAuxiliary *_aux;
    id _cell;
    NS_EXTRA_IVARS_BEGIN(NSControl)
        NSText *_currentEditor;
        BOOL _allowsExpansionToolTips;
        BOOL _setsMaxLayoutWidthAtFirstLayout;
        BOOL _allowsLogicalLayoutDirection;
    NS_EXTRA_IVARS_END(NSControl)
}

@property BOOL allowsExpansionToolTips;
@property BOOL allowsLogicalLayoutDirection;

+ (nullable Class) cellClass;
+ (void) setCellClass: (nullable Class) aClass;

@property(null_unspecified, nonatomic, retain) id cell;

@property (assign, nullable) id target;
@property(nonatomic) SEL action;
@property(nonatomic) NSInteger tag;
@property (nullable, retain) NSFont *font;
@property(null_unspecified, nonatomic, retain) NSImage *image;
@property(nonatomic) NSTextAlignment alignment;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, getter=isEditable) BOOL editable;
@property(nonatomic, getter=isSelectable) BOOL selectable;
@property(nonatomic, getter=isScrollable) BOOL scrollable;
@property(nonatomic, getter=isBordered) BOOL bordered;
@property(nonatomic, getter=isBezeled) BOOL bezeled;
@property(nonatomic, getter=isContinuous) BOOL continuous;
@property(nonatomic) BOOL refusesFirstResponder;
@property(null_unspecified, nonatomic, retain) id formatter;
@property NSLineBreakMode lineBreakMode;
@property(nonatomic) BOOL usesSingleLineMode;
// The cell's control size.
@property(nonatomic) NSControlSize controlSize;

@property(nullable, nonatomic, retain) id objectValue;
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic, copy) NSAttributedString *attributedStringValue;
@property(nonatomic) int intValue;
@property(nonatomic) float floatValue;
@property double doubleValue;
@property(nonatomic) NSInteger integerValue;

@property(null_unspecified, nonatomic, readonly) id selectedCell;
@property(nonatomic, readonly) NSInteger selectedTag;

- (void) setFloatingPointFormat: (BOOL) fpp
                           left: (NSUInteger) left
                          right: (NSUInteger) right;


- (void) takeObjectValueFrom: (nullable id) sender;
- (void) takeStringValueFrom: (nullable id) sender;
- (void) takeIntValueFrom: (nullable id) sender;
- (void) takeFloatValueFrom: (nullable id) sender;
- (void) takeDoubleValueFrom: (nullable id) sender;
- (void) takeIntegerValueFrom: (nullable id) sender;

- (void) selectCell: (NSCell *) cell;

- (void) drawCell: (NSCell *) cell;
- (void) drawCellInside: (NSCell *) cell;
- (void) updateCell: (NSCell *) cell;
- (void) updateCellInside: (NSCell *) cell;

- (void) performClick: (nullable id) sender;
- (BOOL) sendAction: (nullable SEL) action to: (nullable id) target;
- (NSInteger) sendActionOn: (NSInteger) mask;

- (nullable NSText *) currentEditor;
- (void) validateEditing;
- (BOOL) abortEditing;

- (void) calcSize;
- (void) sizeToFit;
- (void) setNeedsDisplay;

@end

@interface NSObject (NSControl_delegate)
- (void) controlTextDidBeginEditing: (NSNotification *) note;
- (void) controlTextDidChange: (NSNotification *) note;
- (void) controlTextDidEndEditing: (NSNotification *) note;
@end

@protocol NSControlTextEditingDelegate <NSObject>
@optional
- (BOOL) control: (NSControl *) control
                   textView: (NSTextView *) textView
        doCommandBySelector: (SEL) selector;
- (BOOL) control: (NSControl *) control
        textShouldBeginEditing: (NSText *) fieldEditor;
- (BOOL) control: (NSControl *) control
        textShouldEndEditing: (NSText *) fieldEditor;
- (BOOL) control: (NSControl *) control
        didFailToFormatString: (NSString *) string
             errorDescription: (nullable NSString *) error;
- (void) control: (NSControl *) control
        didFailToValidatePartialString: (NSString *) string
                      errorDescription: (nullable NSString *) error;
- (BOOL) control: (NSControl *) control isValidObject: (nullable id) obj;
@end

NS_ASSUME_NONNULL_END
