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

#import <AppKit/AppKitExport.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSText.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <AppKit/NSApplication.h>
#import <Foundation/NSNotification.h>

@class NSFont, NSImage, NSView;

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
    NSRegularControlSize,
    NSSmallControlSize,
    NSMiniControlSize
};

typedef NSUInteger NSControlTint;

typedef NS_ENUM(NSInteger, NSBackgroundStyle) {
    NSBackgroundStyleLight = 0,
    NSBackgroundStyleDark = 1,
    NSBackgroundStyleRaised = 2,
    NSBackgroundStyleLowered = 3,
};

enum {
    NSCellHitNone = 0x00,
    NSCellHitContentArea = 0x01,
    NSCellHitEditableTextArea = 0x02,
    NSCellHitTrackableArea = 0x04,
};

APPKIT_EXPORT NSNotificationName NSControlTintDidChangeNotification;

@interface NSCell : NSObject <NSCopying, NSCoding, NSUserInterfaceItemIdentification> {
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
    BOOL _truncatesLastVisibleLine;
    BOOL _allowsUndo;
    NSUserInterfaceLayoutDirection _userInterfaceLayoutDirection;
}

@property BOOL truncatesLastVisibleLine;
@property BOOL allowsUndo;
@property NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;

#pragma mark -
#pragma mark Class Methods

+ (NSFocusRingType) defaultFocusRingType;
+ (NSMenu *) defaultMenu;
+ (BOOL) prefersTrackingUntilMouseUp;

#pragma mark -

- initTextCell: (NSString *) string;
- initImageCell: (NSImage *) image;

- (NSView *) controlView;
- (NSCellType) type;
- (NSControlStateValue) state;

- target;
- (SEL) action;
- (NSInteger) tag;
- (NSInteger) entryType;
- (id) formatter;
- (NSFont *) font;
- (NSImage *) image;
- (NSTextAlignment) alignment;
- (NSLineBreakMode) lineBreakMode;
- (BOOL) usesSingleLineMode;
- (NSWritingDirection) baseWritingDirection;
- (BOOL) wraps;
- (NSString *) title;

- (BOOL) isEnabled;
- (BOOL) isEditable;
- (BOOL) isSelectable;
- (BOOL) isScrollable;
- (BOOL) isBordered;
- (BOOL) isBezeled;
- (BOOL) isContinuous;
- (BOOL) showsFirstResponder;
- (BOOL) refusesFirstResponder;
- (BOOL) isHighlighted;

- (BOOL) hasValidObjectValue;
- objectValue;
- (NSString *) stringValue;
- (int) intValue;
- (float) floatValue;
- (double) doubleValue;
- (NSInteger) integerValue;
- (NSAttributedString *) attributedStringValue;
- (id) representedObject;
- (NSControlSize) controlSize;
- (NSFocusRingType) focusRingType;
- (NSBackgroundStyle) backgroundStyle;

- (void) setControlView: (NSView *) view;
- (void) setType: (NSCellType) type;

- (void) setState: (NSControlStateValue) value;
- (NSControlStateValue) nextState;
- (void) setNextState;
- (BOOL) allowsMixedState;
- (void) setAllowsMixedState: (BOOL) allow;
- (BOOL) allowsEditingTextAttributes;
- (void) setAllowsEditingTextAttributes: (BOOL) allow;

- (void) setTarget: target;
- (void) setAction: (SEL) action;
- (void) setTag: (NSInteger) tag;
- (void) setEntryType: (NSInteger) type;
- (void) setFormatter: (NSFormatter *) formatter;
- (void) setFont: (NSFont *) font;
- (void) setImage: (NSImage *) image;
- (void) setAlignment: (NSTextAlignment) alignment;
- (void) setLineBreakMode: (NSLineBreakMode) value;
- (void) setUsesSingleLineMode: (BOOL) flag;
- (void) setBaseWritingDirection: (NSWritingDirection) value;
- (void) setWraps: (BOOL) wraps;
- (void) setTitle: (NSString *) title;

- (void) setEnabled: (BOOL) flag;
- (void) setEditable: (BOOL) flag;
- (void) setSelectable: (BOOL) flag;
- (void) setScrollable: (BOOL) flag;
- (void) setBordered: (BOOL) flag;
- (void) setBezeled: (BOOL) flag;
- (void) setContinuous: (BOOL) flag;
- (void) setShowsFirstResponder: (BOOL) value;
- (void) setRefusesFirstResponder: (BOOL) flag;
- (void) setHighlighted: (BOOL) flag;

- (void) setFloatingPointFormat: (BOOL) fpp
                           left: (NSUInteger) left
                          right: (NSUInteger) right;

- (void) setObjectValue: (id<NSCopying>) value;
- (void) setStringValue: (NSString *) value;
- (void) setIntValue: (int) value;
- (void) setFloatValue: (float) value;
- (void) setDoubleValue: (double) value;
- (void) setIntegerValue: (NSInteger) value;
- (void) setAttributedStringValue: (NSAttributedString *) value;
- (void) setRepresentedObject: (id) object;
- (void) setControlSize: (NSControlSize) size;
- (void) setFocusRingType: (NSFocusRingType) focusRingType;
- (void) setBackgroundStyle: (NSBackgroundStyle) value;

- (void) takeObjectValueFrom: (id) sender;
- (void) takeStringValueFrom: (id) sender;
- (void) takeIntValueFrom: (id) sender;
- (void) takeFloatValueFrom: (id) sender;
- (void) takeDoubleValueFrom: (id) sender;
- (void) takeIntegerValueFrom: (id) sender;

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
              delegate: (id) delegate
                 event: (NSEvent *) event;
- (void) selectWithFrame: (NSRect) frame
                  inView: (NSView *) view
                  editor: (NSText *) editor
                delegate: (id) delegate
                   start: (NSInteger) location
                  length: (NSInteger) length;
- (void) endEditing: (NSText *) editor;

- (void) resetCursorRect: (NSRect) rect inView: (NSView *) view;

- (void) setSendsActionOnEndEditing: (BOOL) flag;
- (BOOL) sendsActionOnEndEditing;

@end

void NSDrawThreePartImage(NSRect frame, NSImage *startCap, NSImage *centerFill,
                          NSImage *endCap, BOOL vertical,
                          NSCompositingOperation operation, CGFloat alpha,
                          BOOL flipped);
