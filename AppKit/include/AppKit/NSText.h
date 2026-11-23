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
#import <AppKit/NSSpellProtocol.h>
#import <AppKit/NSView.h>

@class NSColor, NSFont;
@protocol NSTextDelegate;

NS_ASSUME_NONNULL_BEGIN

enum {
    NSEnterCharacter = 0x0003,
    NSBackspaceCharacter = 0x0008,
    NSTabCharacter = 0x0009,
    NSNewlineCharacter = 0x000A,
    NSFormFeedCharacter = 0x000C,
    NSCarriageReturnCharacter = 0x000D,
    NSBackTabCharacter = 0x0019,
    NSDeleteCharacter = 0x007F,

    NSLineSeparatorCharacter = 0x2028,
    NSParagraphSeparatorCharacter = 0x2029
};

/* NSTextAlignment uses different values on arm64 and x86_64: center 1 and
 * right 2 on arm64, right 1 and center 2 on x86_64. Define the selector
 * macro unless the build already did. */
#ifndef TARGET_ABI_USES_IOS_VALUES
#if defined(__arm64__) || defined(__aarch64__)
#define TARGET_ABI_USES_IOS_VALUES 1
#else
#define TARGET_ABI_USES_IOS_VALUES 0
#endif
#endif

#if !__NSTEXT_ALIGNMENT_SHARED_SECTION__
#define __NSTEXT_ALIGNMENT_SHARED_SECTION__ 1
typedef NS_ENUM(NSInteger, NSTextAlignment) {
    NSTextAlignmentLeft      = 0,
#if TARGET_ABI_USES_IOS_VALUES
    NSTextAlignmentCenter    = 1,
    NSTextAlignmentRight     = 2,
#else /* !TARGET_ABI_USES_IOS_VALUES */
    NSTextAlignmentRight     = 1,
    NSTextAlignmentCenter    = 2,
#endif
    NSTextAlignmentJustified = 3,
    NSTextAlignmentNatural   = 4
};
#endif // !__NSTEXT_ALIGNMENT_SHARED_SECTION__

enum {
    NSLeftTextAlignment = NSTextAlignmentLeft,
    NSRightTextAlignment = NSTextAlignmentRight,
    NSCenterTextAlignment = NSTextAlignmentCenter,
    NSJustifiedTextAlignment = NSTextAlignmentJustified,
    NSNaturalTextAlignment = NSTextAlignmentNatural
};

enum {
    NSIllegalTextMovement = 0x00,
    NSReturnTextMovement = 0x10,
    NSTabTextMovement = 0x11,
    NSBacktabTextMovement = 0x12,
    NSLeftTextMovement = 0x13,
    NSRightTextMovement = 0x14,
    NSUpTextMovement = 0x15,
    NSDownTextMovement = 0x16,
    NSCancelTextMovement = 0x17,
    NSOtherTextMovement = 0
};

#if !__NSWRITING_DIRECTION_SHARED_SECTION__
#define __NSWRITING_DIRECTION_SHARED_SECTION__ 1
typedef NS_ENUM(NSInteger, NSWritingDirection) {
    NSWritingDirectionNatural       = -1,
    NSWritingDirectionLeftToRight   = 0,
    NSWritingDirectionRightToLeft   = 1
};
#endif // !__NSWRITING_DIRECTION_SHARED_SECTION__

APPKIT_EXPORT NSString *const NSTextDidBeginEditingNotification;
APPKIT_EXPORT NSString *const NSTextDidEndEditingNotification;
APPKIT_EXPORT NSString *const NSTextDidChangeNotification;

typedef NS_ENUM(NSInteger, NSTextMovement) {
    NSTextMovementReturn = 0x10,
    NSTextMovementTab = 0x11,
    NSTextMovementBacktab = 0x12,
    NSTextMovementLeft = 0x13,
    NSTextMovementRight = 0x14,
    NSTextMovementUp = 0x15,
    NSTextMovementDown = 0x16,
    NSTextMovementCancel = 0x17,
    NSTextMovementOther = 0,
};

// Legacy ObjC ABI (i386): instance size must stay 0x54, Apple's. The word is
// NSTextView's pointer to its extra state (Apple's NSText has a word of its
// own for what NSTextView keeps).
@interface NSText : NSView <NSChangeSpelling, NSIgnoreMisspelledWords> {
    NS_EXTRA_SLOT_FOR_SUBCLASS(NSTextView)
}

- (nullable instancetype) initWithCoder: (NSCoder *) coder;
- (instancetype) initWithFrame: (NSRect) frameRect;

- (null_unspecified id) delegate;
@property(nonatomic, copy) NSString *string;
- (nullable NSData *) RTFFromRange: (NSRange) range;
- (nullable NSData *) RTFDFromRange: (NSRange) range;

@property(nonatomic, getter=isEditable) BOOL editable;
@property(nonatomic, getter=isSelectable) BOOL selectable;
@property(nonatomic, getter=isRichText) BOOL richText;
@property(nonatomic, getter=isFieldEditor) BOOL fieldEditor;
@property(nonatomic) BOOL usesFontPanel;
@property(nonatomic) BOOL importsGraphics;

@property(nullable, nonatomic, retain) NSFont *font;
@property(nonatomic) NSTextAlignment alignment;

@property(nullable, nonatomic, retain) NSColor *textColor;

@property(nonatomic) BOOL drawsBackground;
@property(nullable, nonatomic, retain) NSColor *backgroundColor;

@property(nonatomic, getter=isHorizontallyResizable) BOOL horizontallyResizable;
@property(nonatomic, getter=isVerticallyResizable) BOOL verticallyResizable;
@property(nonatomic) NSSize maxSize;
@property(nonatomic) NSSize minSize;

@property(nonatomic) NSRange selectedRange;

- (void) setDelegate: (null_unspecified id) delegate;

- (void) replaceCharactersInRange: (NSRange) range
                       withString: (NSString *) string;

- (BOOL) readRTFDFromFile: (NSString *) path;
- (BOOL) writeRTFDToFile: (NSString *) path atomically: (BOOL) atomically;
- (void) replaceCharactersInRange: (NSRange) range withRTF: (NSData *) rtf;
- (void) replaceCharactersInRange: (NSRange) range withRTFD: (NSData *) rtfd;


- (void) setFont: (NSFont *) font range: (NSRange) range;
- (void) setBaseWritingDirection: (NSWritingDirection) direction
                           range: (NSRange) range;
@property(nonatomic) NSWritingDirection baseWritingDirection;

- (void) setTextColor: (nullable NSColor *) color range: (NSRange) range;




- (void) sizeToFit;

- (void) scrollRangeToVisible: (NSRange) range;

- (void) changeFont: (nullable id) sender;
- (void) alignCenter: (nullable id) sender;
- (void) alignLeft: (nullable id) sender;
- (void) alignRight: (nullable id) sender;
- (void) underline: (nullable id) sender;
- (void) superscript: (nullable id) sender;
- (void) subscript: (nullable id) sender;
- (void) unscript: (nullable id) sender;
- (void) copyFont: (nullable id) sender;
- (void) pasteFont: (nullable id) sender;
- (void) selectAll: (nullable id) sender;
- (void) delete: (nullable id) sender;
- (void) toggleRuler: (nullable id) sender;
- (void) copyRuler: (nullable id) sender;
- (void) pasteRuler: (nullable id) sender;

- (void) showGuessPanel: (nullable id) sender;
- (void) checkSpelling: (nullable id) sender;

@end

@interface NSObject (NSText_delegate)
- (BOOL) textShouldBeginEditing: (NSText *) text;
- (BOOL) textShouldEndEditing: (NSText *) text;

- (void) textDidBeginEditing: (NSNotification *) note;
- (void) textDidChange: (NSNotification *) note;
- (void) textDidEndEditing: (NSNotification *) note;
@end

@protocol NSTextDelegate <NSObject>
@optional

- (BOOL) textShouldBeginEditing: (NSText *) textObject;
- (BOOL) textShouldEndEditing: (NSText *) textObject;
- (void) textDidBeginEditing: (NSNotification *) notification;
- (void) textDidEndEditing: (NSNotification *) notification;
- (void) textDidChange: (NSNotification *) notification;

@end

@interface NSText (NSRTFDWriting)
- (BOOL) writeRTFDToFile: (NSString *) path atomically: (BOOL) atomically;
@end

APPKIT_EXPORT NSString * const NSTextMovementUserInfoKey;

NS_ASSUME_NONNULL_END
