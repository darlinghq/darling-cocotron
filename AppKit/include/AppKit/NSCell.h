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
#import <AppKit/AppKitExport.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSText.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <AppKit/NSApplication.h>
#import <Foundation/NSNotification.h>
#import <AppKit/NSAccessibilityProtocols.h>

@class NSBezierPath, NSFont, NSImage, NSView;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NSCellType) {
    NSNullCellType,
    NSTextCellType,
    NSImageCellType
};

enum : unsigned int {
    NSAnyType = 0,
    NSIntType = 1,
    NSPositiveIntType = 2,
    NSFloatType = 3,
    NSPositiveFloatType = 4,
    NSDoubleType = 6,
    NSPositiveDoubleType = 7
};

typedef NS_ENUM(NSUInteger, NSCellImagePosition) {
    NSNoImage = 0,
    NSImageOnly = 1,
    NSImageLeft = 2,
    NSImageRight = 3,
    NSImageBelow = 4,
    NSImageAbove = 5,
    NSImageOverlaps = 6,
};

typedef NS_ENUM(NSUInteger, NSImageScaling) {
    NSImageScaleProportionallyDown = 0,
    NSImageScaleAxesIndependently = 1,
    NSImageScaleNone = 2,
    NSImageScaleProportionallyUpOrDown = 3,

    // deprecated
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSScaleProportionally = NSImageScaleProportionallyDown,
    NSScaleToFit = NSImageScaleAxesIndependently,
    NSScaleNone = NSImageScaleNone,
};

typedef NS_ENUM(NSInteger, NSControlStateValue) {
    NSControlStateValueMixed = -1,
    NSControlStateValueOff = 0,
    NSControlStateValueOn = 1,
};

typedef enum {
    NSMixedState = -1,
    NSOffState = 0,
    NSOnState = 1,
} NSCellState;

typedef NS_ENUM(NSUInteger, NSControlSize) {
    NSControlSizeRegular = 0,
    NSControlSizeSmall = 1,
    NSControlSizeMini = 2,
    NSControlSizeLarge = 3,
    NSControlSizeExtraLarge = 4
} NS_SWIFT_NAME(NSControl.ControlSize);

// Macros rather than constants so they still work as case labels.
#define NSRegularControlSize NSControlSizeRegular
#define NSSmallControlSize NSControlSizeSmall
#define NSMiniControlSize NSControlSizeMini

typedef NSUInteger NSControlTint;

typedef NS_ENUM(NSInteger, NSBackgroundStyle) {
    NSBackgroundStyleNormal = 0,
    NSBackgroundStyleEmphasized = 1,
    NSBackgroundStyleRaised = 2,
    NSBackgroundStyleLowered = 3,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSBackgroundStyleLight = NSBackgroundStyleNormal,
    NSBackgroundStyleDark = NSBackgroundStyleEmphasized,
};

enum {
    NSCellHitNone = 0x00,
    NSCellHitContentArea = 0x01,
    NSCellHitEditableTextArea = 0x02,
    NSCellHitTrackableArea = 0x04,
};

APPKIT_EXPORT NSNotificationName NSControlTintDidChangeNotification;

// Legacy ObjC ABI (i386): instance size must stay 0x14, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSCell : NSObject <NSCopying, NSCoding, NSUserInterfaceItemIdentification> {
    NS_LEGACY_IVAR_PAD(_NSCellReserved1, 12)
    NS_EXTRA_IVARS_BEGIN(NSCell)
        NSControlStateValue _state;
        NSFont *_font;
        NSInteger _entryType;
        id _objectValue;
        NSImage *_image;
        int _textAlignment;
        NSWritingDirection _writingDirection;
        NSCellType _cellType;
        NSFormatter *_formatter;
        id _titleOrAttributedTitle;
        id _representedObject;
        NSControlSize _controlSize;
        NSFocusRingType _focusRingType;
        NSLineBreakMode _lineBreakMode;
        NSBackgroundStyle _backgroundStyle;
        NSUInteger _cFlags; // required for Xcode
        NSUserInterfaceItemIdentifier _identifier;

        BOOL _isEnabled;
        BOOL _isEditable;
        BOOL _isRichText;
        BOOL _isSelectable;
        BOOL _isScrollable;
        BOOL _isBordered;
        BOOL _isBezeled;
        BOOL _isHighlighted;
        BOOL _showsFirstResponder;
        BOOL _refusesFirstResponder;
        BOOL _isContinuous;
        BOOL _allowsMixedState;
        BOOL _allowsEditingTextAttributes;
        BOOL _sendsActionOnEndEditing;
        BOOL _hasValidObjectValue;
        BOOL _usesSingleLineMode;
        NSInteger _sendActionOnMask;
        BOOL _truncatesLastVisibleLine;
        BOOL _allowsUndo;
        NSUserInterfaceLayoutDirection _userInterfaceLayoutDirection;
        NSMenu *_cellMenu;
        NSControlTint _controlTint;
    NS_EXTRA_IVARS_END(NSCell)
}

@property BOOL truncatesLastVisibleLine;
@property BOOL allowsUndo;
@property NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;

// The cell's contextual menu.
@property(nullable, nonatomic, retain) NSMenu *menu;

#pragma mark -
#pragma mark Class Methods

+ (NSFocusRingType) defaultFocusRingType;
+ (nullable NSMenu *) defaultMenu;
+ (BOOL) prefersTrackingUntilMouseUp;

#pragma mark -

- (instancetype) initTextCell: (NSString *) string;
- (instancetype) initImageCell: (nullable NSImage *) image;

@property(nullable, nonatomic, retain) NSView *controlView;
@property(nonatomic) NSCellType type;
@property NSControlStateValue state;

- (nullable id) target;
@property(nonatomic) SEL action;
@property(nonatomic) NSInteger tag;
@property(nonatomic) NSInteger entryType;
@property(null_unspecified, nonatomic, retain) id formatter;
@property (nullable, retain) NSFont *font;
@property(nullable, nonatomic, retain) NSImage *image;
@property(nonatomic) NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property(nonatomic) BOOL usesSingleLineMode;
@property NSWritingDirection baseWritingDirection;
@property(nonatomic) BOOL wraps;
@property(nonatomic, copy) NSString *title;
- (NSInteger) sendActionOn: (NSInteger) mask;

@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, getter=isEditable) BOOL editable;
@property(nonatomic, getter=isSelectable) BOOL selectable;
@property(nonatomic, getter=isScrollable) BOOL scrollable;
@property(nonatomic, getter=isBordered) BOOL bordered;
@property(nonatomic, getter=isBezeled) BOOL bezeled;
@property(nonatomic, getter=isContinuous) BOOL continuous;
@property(nonatomic) BOOL showsFirstResponder;
@property(nonatomic) BOOL refusesFirstResponder;
@property(nonatomic, getter=isHighlighted) BOOL highlighted;

- (BOOL) hasValidObjectValue;
- (nullable id) objectValue;
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic) int intValue;
@property(nonatomic) float floatValue;
@property double doubleValue;
@property(nonatomic) NSInteger integerValue;
@property(nonatomic, copy) NSAttributedString *attributedStringValue;
@property(nullable, nonatomic, assign) id representedObject;
@property NSControlSize controlSize;
@property NSControlTint controlTint;
@property(nonatomic) NSFocusRingType focusRingType;

- (NSRect) focusRingMaskBoundsForFrame: (NSRect) cellFrame inView: (NSView *) controlView;
- (void) drawFocusRingMaskWithFrame: (NSRect) cellFrame inView: (NSView *) controlView;

// Private: whether the cell is the one of the control that has the keyboard focus in a key window.
- (BOOL) _hasKeyboardFocusInView: (null_unspecified NSView *) controlView;
// Private: the shape of the ring the control draws for the cell's keyboard focus when the cell has the focus, in
// the coordinates of the control; nil for a cell that has no shape of its own.
- (null_unspecified NSBezierPath *) _focusRingPathWithFrame: (NSRect) frame inView: (null_unspecified NSView *) controlView;
@property(nonatomic) NSBackgroundStyle backgroundStyle;

// The background style the cell draws its interior for (read-only).
- (NSBackgroundStyle) interiorBackgroundStyle;


- (NSControlStateValue) nextState;
- (void) setNextState;
@property(nonatomic) BOOL allowsMixedState;
@property(nonatomic) BOOL allowsEditingTextAttributes;

- (void) setTarget: (nullable id) target;


- (void) setFloatingPointFormat: (BOOL) fpp
                           left: (NSUInteger) left
                          right: (NSUInteger) right;

- (void) setObjectValue: (null_unspecified id<NSCopying>) value;

- (void) takeObjectValueFrom: (nullable id) sender;
- (void) takeStringValueFrom: (nullable id) sender;
- (void) takeIntValueFrom: (nullable id) sender;
- (void) takeFloatValueFrom: (nullable id) sender;
- (void) takeDoubleValueFrom: (nullable id) sender;
- (void) takeIntegerValueFrom: (nullable id) sender;

- (NSSize) cellSize;
- (NSSize) cellSizeForBounds: (NSRect) rect;

- (NSRect) imageRectForBounds: (NSRect) rect;
- (NSRect) titleRectForBounds: (NSRect) rect;
- (NSRect) drawingRectForBounds: (NSRect) rect;

- (void) drawInteriorWithFrame: (NSRect) frame inView: (NSView *) view;
- (void) drawWithFrame: (NSRect) frame inView: (NSView *) view;

- (void) highlight: (BOOL) highlight
         withFrame: (NSRect) frame
            inView: (NSView *) view;

- (BOOL) startTrackingAt: (NSPoint) startPoint inView: (NSView *) view;
- (BOOL) continueTracking: (NSPoint) lastPoint
                       at: (NSPoint) currentPoint
                   inView: (NSView *) view;
- (void) stopTracking: (NSPoint) lastPoint
                   at: (NSPoint) stopPoint
               inView: (NSView *) view
            mouseIsUp: (BOOL) flag;
- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) frame
              ofView: (NSView *) view
        untilMouseUp: (BOOL) flag;

- (NSText *) setUpFieldEditorAttributes: (NSText *) editor;

- (void) editWithFrame: (NSRect) frame
                inView: (NSView *) view
                editor: (NSText *) editor
              delegate: (nullable id) delegate
                 event: (nullable NSEvent *) event;
- (void) selectWithFrame: (NSRect) frame
                  inView: (NSView *) view
                  editor: (NSText *) editor
                delegate: (nullable id) delegate
                   start: (NSInteger) location
                  length: (NSInteger) length;
- (void) endEditing: (NSText *) editor;

- (void) resetCursorRect: (NSRect) rect inView: (NSView *) view;

@property(nonatomic) BOOL sendsActionOnEndEditing;

// The cell's menu, whatever the event and position.
- (nullable NSMenu *) menuForEvent: (NSEvent *) event
                   inRect: (NSRect) rect
                   ofView: (NSView *) view;

@end

@interface NSCell (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end

void NSDrawThreePartImage(NSRect frame, NSImage *startCap, NSImage *centerFill,
                          NSImage *endCap, BOOL vertical,
                          NSCompositingOperation operation, CGFloat alpha,
                          BOOL flipped);

NS_ASSUME_NONNULL_END
