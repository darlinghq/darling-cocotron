/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>

#import "NSCellUndoManager.h"
#import <AppKit/NSTextView.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSNumberFormatter.h>

typedef NS_OPTIONS(unsigned int, NSCellAppleFlags) {
    NSCellAppleFlagOnState              = 1u << 31,
    NSCellAppleFlagHighlighted          = 1u << 30,
    NSCellAppleFlagDisabled             = 1u << 29,
    NSCellAppleFlagEditable             = 1u << 28,
    NSCellAppleFlagTypeShift            = 26,
    NSCellAppleFlagTypeMask             = 0x03u << NSCellAppleFlagTypeShift,
    NSCellAppleFlagVerticallyCentered   = 1u << 25,
    NSCellAppleFlagHorizontallyCentered = 1u << 24,
    NSCellAppleFlagBordered             = 1u << 23,
    NSCellAppleFlagBezeled              = 1u << 22,
    NSCellAppleFlagSelectable           = 1u << 21,
    NSCellAppleFlagScrollable           = 1u << 20,
    NSCellAppleFlagContinuous           = 1u << 19,
    NSCellAppleFlagActOnMouseDown       = 1u << 18,
    NSCellAppleFlagLeaf                 = 1u << 17,
    NSCellAppleFlagInvalidObjectValue   = 1u << 16,
    NSCellAppleFlagInvalidFont          = 1u << 15,
    NSCellAppleFlagReserved1            = 1u << 14,
    NSCellAppleFlagReserved2            = 1u << 13,
    NSCellAppleFlagReserved3            = 1u << 12,
    NSCellAppleFlagReserved4            = 1u << 11,
    NSCellAppleFlagSingleLineMode       = 1u << 10,
    NSCellAppleFlagReserved5            = 1u << 9,
    NSCellAppleFlagActOnMouseDrag       = 1u << 8,
    NSCellAppleFlagLoaded               = 1u << 7,
    NSCellAppleFlagTruncateLastLine     = 1u << 6,
    NSCellAppleFlagDontActOnMouseUp     = 1u << 5,
    NSCellAppleFlagWhite                = 1u << 4,
    NSCellAppleFlagUserKeyEquivalent    = 1u << 3,
    NSCellAppleFlagShowsFirstResponder  = 1u << 2,
    NSCellAppleFlagFocusRingTypeShift   = 0,
    NSCellAppleFlagFocusRingTypeMask    = 0x03u << NSCellAppleFlagFocusRingTypeShift,
};

typedef NS_OPTIONS(unsigned int, NSCellAppleFlags2) {
    NSCellAppleFlag2WasSelectable         = 1u << 31,
    NSCellAppleFlag2RichText              = 1u << 30,
    NSCellAppleFlag2Reserved1             = 1u << 29,
    NSCellAppleFlag2TextAlignmentShift    = 26,
    NSCellAppleFlag2TextAlignmentMask     = 0x07u << NSCellAppleFlag2TextAlignmentShift,
    NSCellAppleFlag2RefusesFirstResponder = 1u << 25,
    NSCellAppleFlag2AllowsMixedState      = 1u << 24,
    NSCellAppleFlag2InMixedState          = 1u << 23,
    NSCellAppleFlag2ActOnEditingEnd       = 1u << 22,
    // The control tint and the control size as macOS 10.14.4 and 26.7.3 archive them.
    NSCellAppleFlag2ControlTintShift      = 19,
    NSCellAppleFlag2ControlTintMask       = 0x07u << NSCellAppleFlag2ControlTintShift,
    NSCellAppleFlag2ControlSizeShift      = 17,
    NSCellAppleFlag2ControlSizeMask       = 0x03u << NSCellAppleFlag2ControlSizeShift,
    NSCellAppleFlag2Reserved5             = 1u << 16,
    NSCellAppleFlag2Reserved6             = 1u << 15,
    NSCellAppleFlag2Reserved7             = 1u << 14,
    NSCellAppleFlag2Reserved8             = 1u << 13,
    NSCellAppleFlag2Reserved9             = 1u << 12,
    NSCellAppleFlag2Reserved10            = 1u << 11,
    NSCellAppleFlag2LineBreakModeShift    = 9,
    NSCellAppleFlag2LineBreakModeMask     = 0x07u << NSCellAppleFlag2LineBreakModeShift,
    NSCellAppleFlag2Reserved11            = 1u << 8,
    NSCellAppleFlag2Reserved12            = 1u << 7,
    NSCellAppleFlag2Reserved13            = 1u << 6,
    NSCellAppleFlag2Reserved14            = 1u << 5,
    NSCellAppleFlag2Reserved15            = 1u << 4,
    NSCellAppleFlag2Reserved16            = 1u << 3,
    NSCellAppleFlag2Reserved17            = 1u << 2,
    NSCellAppleFlag2Reserved18            = 1u << 1,
    NSCellAppleFlag2Reserved19            = 1u << 0,
};

NSNotificationName NSControlTintDidChangeNotification = @"NSControlTintDidChangeNotification";

/* Nib cell flags keep the x86_64 alignment numbering (right 1, center 2) on
 * every architecture, because one compiled nib serves both slices of a
 * universal app. NSTextAlignment swaps the two where TARGET_ABI_USES_IOS_VALUES
 * is set, so convert at that boundary in both directions. */
static NSTextAlignment NSCellAlignmentFromArchive(unsigned value) {
#if TARGET_ABI_USES_IOS_VALUES
    if (value == 1)
        return NSTextAlignmentRight;
    if (value == 2)
        return NSTextAlignmentCenter;
#endif
    return (NSTextAlignment) value;
}

static unsigned NSCellAlignmentToArchive(NSTextAlignment alignment) {
#if TARGET_ABI_USES_IOS_VALUES
    if (alignment == NSTextAlignmentRight)
        return 1;
    if (alignment == NSTextAlignmentCenter)
        return 2;
#endif
    return (unsigned) alignment;
}

@implementation NSCell

NS_EXTRA_SYNTHESIZE_COPY(NSCell, identifier, _identifier, NSUserInterfaceItemIdentifier, identifier, setIdentifier:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSCell, truncatesLastVisibleLine, _truncatesLastVisibleLine, BOOL, truncatesLastVisibleLine, setTruncatesLastVisibleLine:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSCell, allowsUndo, _allowsUndo, BOOL, allowsUndo, setAllowsUndo:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSCell, userInterfaceLayoutDirection, _userInterfaceLayoutDirection, NSUserInterfaceLayoutDirection, userInterfaceLayoutDirection, setUserInterfaceLayoutDirection:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSCell, controlTint, _controlTint, NSControlTint, controlTint, setControlTint:)

#pragma mark -
#pragma mark Class Methods

+ (NSFocusRingType) defaultFocusRingType {
    return NSFocusRingTypeExterior;
}

+ (NSMenu *) defaultMenu {
    return nil;
}

+ (BOOL) prefersTrackingUntilMouseUp {
    return NO;
}

#pragma mark -

- (void) _applyAppleFlags: (unsigned int) flags flags2: (unsigned int) flags2 {
    // These flags are big endian so the first flag is over on the left of the
    // int
    NS_EXTRA(NSCell, self)->_state = (flags & NSCellAppleFlagOnState) ? NSControlStateValueOn : NSControlStateValueOff;
    NS_EXTRA(NSCell, self)->_isHighlighted = (flags & NSCellAppleFlagHighlighted) ? YES : NO;
    NS_EXTRA(NSCell, self)->_isEnabled = (flags & NSCellAppleFlagDisabled) ? NO : YES; // "disabled" in Cocoa
    NS_EXTRA(NSCell, self)->_isEditable = (flags & NSCellAppleFlagEditable) ? YES : NO;
    NS_EXTRA(NSCell, self)->_cellType = (flags & NSCellAppleFlagTypeMask) >> NSCellAppleFlagTypeShift;

    // vCentered     = (flags & 0x02000000)
    // hCentered     = (flags & 0x01000000)

    NS_EXTRA(NSCell, self)->_isBordered = (flags & NSCellAppleFlagBordered) ? YES : NO;
    NS_EXTRA(NSCell, self)->_isBezeled = (flags & NSCellAppleFlagBezeled) ? YES : NO;
    NS_EXTRA(NSCell, self)->_isSelectable = (flags & NSCellAppleFlagSelectable) ? YES : NO;
    NS_EXTRA(NSCell, self)->_isScrollable = (flags & NSCellAppleFlagScrollable) ? YES : NO;
    // _wraps        = (flags & 0x00100000) ? NO : YES; // ! scrollable, use
    // lineBreakMode ?

    // 0x00080000 = continuous
    // 0x00040000 = action on mouse down
    // 0x00000100 = action on mouse drag
    NS_EXTRA(NSCell, self)->_isContinuous = (flags & (NSCellAppleFlagContinuous | NSCellAppleFlagActOnMouseDrag)) ? YES : NO;

    // actOnMouseDown = (flags & 0x00040000)
    // isLeaf         = (flags & 0x00020000)

    // invObjectVal  = (flags & 0x00010000)
    NS_EXTRA(NSCell, self)->_hasValidObjectValue = YES;

    // invalidFont   = (flags & 0x00008000)
    // cellReserved1 = (flags & 0x00001800)
    // singleLineMode= (flags & 0x00000400)
    // actOnMouseDrag= (flags & 0x00000100)
    // isLoaded      = (flags & 0x00000080)
    // truncLastLine = (flags & 0x00000040)
    // dontActOnMsUp = (flags & 0x00000020)
    // isWhite       = (flags & 0x00000010)
    // userKeyEquiv  = (flags & 0x00000008)
    // showsFirstResp= (flags & 0x00000004)

    NS_EXTRA(NSCell, self)->_focusRingType = (flags & NSCellAppleFlagFocusRingTypeMask) >> NSCellAppleFlagFocusRingTypeShift;

    // Now for flags2 - the layout of these flags seems to be more
    // random. So the best way to find out which bit(s) you need is
    // to diff a xib file before and after you make the change you're
    // trying to support (i.e. check a checkbox) and convert the decimal
    // NSCellFlags2 value to hex
    // wasSelectable = (flags2 & 0x80000000)

    NS_EXTRA(NSCell, self)->_isRichText = (flags2 & NSCellAppleFlag2RichText) ? YES : NO;

    // importsGraph  = (flags2 & 0x10000000)

    NS_EXTRA(NSCell, self)->_textAlignment = NSCellAlignmentFromArchive((flags2 & NSCellAppleFlag2TextAlignmentMask) >> NSCellAppleFlag2TextAlignmentShift);

    // layoutDirRTL  = (flags2 & 0x01000000)
    NS_EXTRA(NSCell, self)->_writingDirection = NSWritingDirectionNatural;

    // backgrdStyle  = (flags2 & 0x00c00000) >> 21;
    // cellReserved  = (flags2 & 0x003c0000)
    NS_EXTRA(NSCell, self)->_refusesFirstResponder = (flags2 & NSCellAppleFlag2RefusesFirstResponder) ? YES : NO;
    NS_EXTRA(NSCell, self)->_allowsMixedState = (flags2 & NSCellAppleFlag2AllowsMixedState) ? YES : NO;

    // inMixedState  = (flags2 & 0x00800000)

    NS_EXTRA(NSCell, self)->_sendsActionOnEndEditing = (flags2 & NSCellAppleFlag2ActOnEditingEnd) ? YES : NO;

    // Odd this isn't in flags - it's near other items in flags in the Cocoa
    // struct from which these are derived.
    NS_EXTRA(NSCell, self)->_lineBreakMode = (flags2 & NSCellAppleFlag2LineBreakModeMask) >> NSCellAppleFlag2LineBreakModeShift;
    NS_EXTRA(NSCell, self)->_controlSize = (flags2 & NSCellAppleFlag2ControlSizeMask) >> NSCellAppleFlag2ControlSizeShift;
    NS_EXTRA(NSCell, self)->_controlTint = (flags2 & NSCellAppleFlag2ControlTintMask) >> NSCellAppleFlag2ControlTintShift;
}

// The fields of the second flag word that NSArchiver data (non-keyed decoding) lays out
// differently from what _applyAppleFlags:flags2: reads, as seen in archives written
// on Mac OS X 10.14 and macOS 26: the mixed state in bit 23 (the on-state bit of
// the first word is set too), focus ring type in bits 15-16, base writing
// direction right-to-left in bit 14, truncation of the last visible line in
// bit 8 and right-to-left layout direction in bit 7.
- (void) _applyNonKeyedFlags2: (unsigned int) flags2 {
    if (flags2 & (1u << 23))
        NS_EXTRA(NSCell, self)->_state = NSControlStateValueMixed;
    NS_EXTRA(NSCell, self)->_focusRingType = (flags2 >> 15) & 3;
    if (flags2 & (1u << 14))
        NS_EXTRA(NSCell, self)->_writingDirection = NSWritingDirectionRightToLeft;
    NS_EXTRA(NSCell, self)->_truncatesLastVisibleLine = (flags2 & (1u << 8)) ? YES : NO;
    NS_EXTRA(NSCell, self)->_userInterfaceLayoutDirection = (flags2 & (1u << 7)) ? NSUserInterfaceLayoutDirectionRightToLeft : NSUserInterfaceLayoutDirectionLeftToRight;
}

- (void) _generateAppleFlags: (unsigned int *) flags flags2: (unsigned int *) flags2 {
    *flags = 0;
    *flags2 = 0;

    if (NS_EXTRA(NSCell, self)->_state == NSControlStateValueOn)
        *flags |= NSCellAppleFlagOnState;
    else if (NS_EXTRA(NSCell, self)->_state == NSControlStateValueMixed)
        *flags2 |= NSCellAppleFlag2InMixedState;

    if (NS_EXTRA(NSCell, self)->_isHighlighted)
        *flags |= NSCellAppleFlagHighlighted;
    if (!NS_EXTRA(NSCell, self)->_isEnabled)
        *flags |= NSCellAppleFlagDisabled;
    if (NS_EXTRA(NSCell, self)->_isEditable)
        *flags |= NSCellAppleFlagEditable;

    *flags |= (NS_EXTRA(NSCell, self)->_cellType << NSCellAppleFlagTypeShift) & NSCellAppleFlagTypeMask;

    if (NS_EXTRA(NSCell, self)->_isBordered)
        *flags |= NSCellAppleFlagBordered;
    if (NS_EXTRA(NSCell, self)->_isBezeled)
        *flags |= NSCellAppleFlagBezeled;
    if (NS_EXTRA(NSCell, self)->_isSelectable)
        *flags |= NSCellAppleFlagSelectable;
    if (NS_EXTRA(NSCell, self)->_isScrollable)
        *flags |= NSCellAppleFlagScrollable;

    // we don't really store whether it's continuous or mouse drag, so assume it's continuous
    if (NS_EXTRA(NSCell, self)->_isContinuous)
        *flags |= NSCellAppleFlagContinuous;

    *flags |= (NS_EXTRA(NSCell, self)->_focusRingType << NSCellAppleFlagFocusRingTypeShift) & NSCellAppleFlagFocusRingTypeMask;

    if (NS_EXTRA(NSCell, self)->_isRichText)
        *flags2 |= NSCellAppleFlag2RichText;

    *flags2 |= (NSCellAlignmentToArchive(NS_EXTRA(NSCell, self)->_textAlignment) << NSCellAppleFlag2TextAlignmentShift) & NSCellAppleFlag2TextAlignmentMask;

    if (NS_EXTRA(NSCell, self)->_refusesFirstResponder)
        *flags2 |= NSCellAppleFlag2RefusesFirstResponder;

    if (NS_EXTRA(NSCell, self)->_allowsMixedState)
        *flags2 |= NSCellAppleFlag2AllowsMixedState;

    if (NS_EXTRA(NSCell, self)->_sendsActionOnEndEditing)
        *flags2 |= NSCellAppleFlag2ActOnEditingEnd;

    *flags2 |= (NS_EXTRA(NSCell, self)->_lineBreakMode << NSCellAppleFlag2LineBreakModeShift) & NSCellAppleFlag2LineBreakModeMask;
    *flags2 |= (NS_EXTRA(NSCell, self)->_controlSize << NSCellAppleFlag2ControlSizeShift) & NSCellAppleFlag2ControlSizeMask;
    *flags2 |= (NS_EXTRA(NSCell, self)->_controlTint << NSCellAppleFlag2ControlTintShift) & NSCellAppleFlag2ControlTintMask;
}

- initWithCoder: (NSCoder *) coder {
    unsigned int flags = 0, flags2 = 0;
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        flags = [keyed decodeIntForKey: @"NSCellFlags"];
        flags2 = [keyed decodeIntForKey: @"NSCellFlags2"];
        id check;

        [self _applyAppleFlags: flags flags2: flags2];

        NS_EXTRA(NSCell, self)->_objectValue = [[keyed decodeObjectForKey: @"NSContents"] retain];
        check = [keyed decodeObjectForKey: @"NSNormalImage"];
        if ([check isKindOfClass: [NSImage class]])
            NS_EXTRA(NSCell, self)->_image = [check retain];
        else if ([check isKindOfClass: [NSFont class]])
            NS_EXTRA(NSCell, self)->_font = [check retain];

        check = [keyed decodeObjectForKey: @"NSSupport"];
        if ([check isKindOfClass: [NSFont class]])
            NS_EXTRA(NSCell, self)->_font = [check retain];

        [self setFormatter: [keyed decodeObjectForKey: @"NSFormatter"]];

        if (NS_EXTRA(NSCell, self)->_font == nil)
            NS_EXTRA(NSCell, self)->_font = [[NSFont userFontOfSize: [NSFont systemFontSizeForControlSize: NS_EXTRA(NSCell, self)->_controlSize]] retain];
    } else {
        NSInteger version = [coder versionForClassName: @"NSCell"];
        if (version < 55)
            [NSException raise: NSInternalInconsistencyException
                        format: @"Cannot decode very old archived cells.  Archived cell is version %ld.",
                                (long) version];

        [coder decodeValuesOfObjCTypes: "ii", &flags, &flags2];

        /*
        flags |= inFlags >> 31;
        flags |= ((inFlags >> 29) & 2);
        flags |= (inFlags >> 27) & 4;
        flags |= (inFlags >> 25) & 8;
        flags |= (inFlags >> 22) & 0x30;
        flags |= (inFlags >> 19) & 0x40;
        flags |= (inFlags >> 17) & 0x80;
        flags |= (inFlags >> 15) & 0x100;
        flags |= (inFlags >> 13) & 0x200;
        flags |= (inFlags >> 11) & 0x400;
        flags |= (inFlags >> 9) & 0x800;
        flags |= (inFlags >> 7) & 0x1000;
        flags |= (inFlags >> 5) & 0x2000;
        flags |= (inFlags >> 3) & 0x4000;

        flags |= (inFlags << 15) & 0x800000;
        flags |= (inFlags << 17) & 0x1000000;
        flags |= (inFlags & 0x40) << 12;
        flags |= (inFlags << 21) & 0x4000000;
        flags |= (inFlags << 23) & 0x8000000;

        // flags &= 0x8E271FFFF;

        flags |= (inFlags << 25) & 0x10000000;
        */

        [self _applyAppleFlags: flags flags2: flags2];
        [self _applyNonKeyedFlags2: flags2];

        id o1, o2, o3;
        [coder decodeValuesOfObjCTypes: "@@@@", &NS_EXTRA(NSCell, self)->_objectValue, &o1, &o2, &o3];
        // The second object of a classic archive is the font of a text cell and the image of an image cell.
        if ([o1 isKindOfClass: [NSImage class]])
            NS_EXTRA(NSCell, self)->_image = [o1 retain];
        else if ([o1 isKindOfClass: [NSFont class]])
            NS_EXTRA(NSCell, self)->_font = [o1 retain];

        [self setFormatter: o2];
        [self setRepresentedObject: o3];

        if (NS_EXTRA(NSCell, self)->_font == nil)
            NS_EXTRA(NSCell, self)->_font = [[NSFont userFontOfSize: [NSFont systemFontSizeForControlSize: NS_EXTRA(NSCell, self)->_controlSize]] retain];
    }
    return self;
}

// What a keyed archive stores as the cell's contents; subclasses whose
// contents are not the object value override it.
- (id) _archivedContents {
    return NS_EXTRA(NSCell, self)->_objectValue;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    unsigned int flags = 0;
    unsigned int flags2 = 0;

    [self _generateAppleFlags: &flags flags2: &flags2];

    if (coder.allowsKeyedCoding) {
        [coder encodeInt: flags forKey: @"NSCellFlags"];
        [coder encodeInt: flags2 forKey: @"NSCellFlags2"];
        [coder encodeObject: [self _archivedContents] forKey: @"NSContents"];
        if (NS_EXTRA(NSCell, self)->_image != nil) {
            [coder encodeObject: NS_EXTRA(NSCell, self)->_image forKey: @"NSNormalImage"];
            if (NS_EXTRA(NSCell, self)->_font != nil)
                [coder encodeObject: NS_EXTRA(NSCell, self)->_font forKey: @"NSSupport"];
        } else if (NS_EXTRA(NSCell, self)->_font != nil)
            [coder encodeObject: NS_EXTRA(NSCell, self)->_font forKey: @"NSNormalImage"];
        [coder encodeObject: NS_EXTRA(NSCell, self)->_formatter forKey: @"NSFormatter"];
    } else {
        [NSException raise: NSInvalidArchiveOperationException
                    format: @"TODO: support unkeyed encoding in NSCell"];
    }
}

- initTextCell: (NSString *) string {
    NS_EXTRA(NSCell, self)->_focusRingType = [[self class] defaultFocusRingType];
    NS_EXTRA(NSCell, self)->_state = NSControlStateValueOff;
    NS_EXTRA(NSCell, self)->_font = [[NSFont userFontOfSize: 0] retain];
    NS_EXTRA(NSCell, self)->_objectValue = [string copy];
    NS_EXTRA(NSCell, self)->_image = nil;
    NS_EXTRA(NSCell, self)->_cellType = NSTextCellType;
    NS_EXTRA(NSCell, self)->_isEnabled = YES;
    NS_EXTRA(NSCell, self)->_isEditable = NO;
    NS_EXTRA(NSCell, self)->_isSelectable = NO;
    NS_EXTRA(NSCell, self)->_isBordered = NO;
    NS_EXTRA(NSCell, self)->_isBezeled = NO;
    NS_EXTRA(NSCell, self)->_isHighlighted = NO;
    NS_EXTRA(NSCell, self)->_refusesFirstResponder = NO;
    NS_EXTRA(NSCell, self)->_lineBreakMode = NSLineBreakByWordWrapping;
    NS_EXTRA(NSCell, self)->_hasValidObjectValue = YES;
    return self;
}

// The state of a new image cell. -init uses it directly: on macOS -[NSCell init] does not send
// -initImageCell: or -initTextCell:, so a subclass overriding those is not entered from -init.
static void initImageCellState(NSCell *self, NSImage *image) {
    NS_EXTRA(NSCell, self)->_focusRingType = [[self class] defaultFocusRingType];
    NS_EXTRA(NSCell, self)->_state = NSControlStateValueOff;
    NS_EXTRA(NSCell, self)->_font = nil;
    NS_EXTRA(NSCell, self)->_objectValue = nil;
    NS_EXTRA(NSCell, self)->_image = [image retain];
    NS_EXTRA(NSCell, self)->_cellType = NSImageCellType;
    NS_EXTRA(NSCell, self)->_isEnabled = YES;
    NS_EXTRA(NSCell, self)->_isEditable = NO;
    NS_EXTRA(NSCell, self)->_isSelectable = NO;
    NS_EXTRA(NSCell, self)->_isBordered = NO;
    NS_EXTRA(NSCell, self)->_isBezeled = NO;
    NS_EXTRA(NSCell, self)->_isHighlighted = NO;
    NS_EXTRA(NSCell, self)->_refusesFirstResponder = NO;
    NS_EXTRA(NSCell, self)->_lineBreakMode = NSLineBreakByWordWrapping;
    NS_EXTRA(NSCell, self)->_hasValidObjectValue = YES;
}

- initImageCell: (NSImage *) image {
    initImageCellState(self, image);
    return self;
}

- init {
    initImageCellState(self, nil);
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSCell, self)->_font release];
    [NS_EXTRA(NSCell, self)->_objectValue release];
    [NS_EXTRA(NSCell, self)->_image release];
    [NS_EXTRA(NSCell, self)->_formatter release];
    [NS_EXTRA(NSCell, self)->_representedObject release];
    [NS_EXTRA(NSCell, self)->_identifier release];
    [NS_EXTRA(NSCell, self)->_cellMenu release];
    NS_EXTRA_FREE(NSCell, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSCell *copy = NSCopyObject(self, 0, zone);
    NS_EXTRA_COPY(NSCell, copy, self);
    NS_EXTRA(NSCell, copy)->_identifier =
        [NS_EXTRA(NSCell, self)->_identifier copyWithZone: zone];

    NS_EXTRA(NSCell, copy)->_font = [NS_EXTRA(NSCell, self)->_font retain];
    NS_EXTRA(NSCell, copy)->_objectValue = [NS_EXTRA(NSCell, self)->_objectValue copy];
    NS_EXTRA(NSCell, copy)->_image = [NS_EXTRA(NSCell, self)->_image retain];
    NS_EXTRA(NSCell, copy)->_formatter = [NS_EXTRA(NSCell, self)->_formatter retain];
    NS_EXTRA(NSCell, copy)->_representedObject = [NS_EXTRA(NSCell, self)->_representedObject retain];
    NS_EXTRA(NSCell, copy)->_cellMenu = [NS_EXTRA(NSCell, self)->_cellMenu retain];

    return copy;
}

- (NSMenu *) menu {
    return NS_EXTRA(NSCell, self)->_cellMenu;
}

- (void) setMenu: (NSMenu *) menu {
    menu = [menu retain];
    [NS_EXTRA(NSCell, self)->_cellMenu release];
    NS_EXTRA(NSCell, self)->_cellMenu = menu;
}

- (NSView *) controlView {
    return nil;
}

- (NSCellType) type {
    return NS_EXTRA(NSCell, self)->_cellType;
}

- (NSControlStateValue) state {
    if (NS_EXTRA(NSCell, self)->_allowsMixedState) {
        if (NS_EXTRA(NSCell, self)->_state < 0)
            return -1;
        else if (NS_EXTRA(NSCell, self)->_state > 0)
            return 1;
        else
            return 0;
    } else
        return (ABS(NS_EXTRA(NSCell, self)->_state) > 0) ? 1 : 0;
}

- target {
    return nil;
}

- (SEL) action {
    return NULL;
}

- (NSInteger) sendActionOn: (NSInteger) mask {
    NSInteger old = NS_EXTRA(NSCell, self)->_sendActionOnMask;
    NS_EXTRA(NSCell, self)->_sendActionOnMask = mask;
    return old;
}

- (NSInteger) tag {
    return -1;
}

- (NSInteger) entryType {
    return NS_EXTRA(NSCell, self)->_entryType;
}

- (id) formatter {
    return NS_EXTRA(NSCell, self)->_formatter;
}

- (NSFont *) font {
    return NS_EXTRA(NSCell, self)->_font;
}

- (NSImage *) image {
    return NS_EXTRA(NSCell, self)->_image;
}

- (NSTextAlignment) alignment {
    return NS_EXTRA(NSCell, self)->_textAlignment;
}

- (NSLineBreakMode) lineBreakMode {
    return NS_EXTRA(NSCell, self)->_lineBreakMode;
}

- (BOOL) usesSingleLineMode {
    return NS_EXTRA(NSCell, self)->_usesSingleLineMode;
}

- (NSWritingDirection) baseWritingDirection {
    return NS_EXTRA(NSCell, self)->_writingDirection;
}

- (BOOL) wraps {
    return (NS_EXTRA(NSCell, self)->_lineBreakMode == NSLineBreakByWordWrapping ||
            NS_EXTRA(NSCell, self)->_lineBreakMode == NSLineBreakByCharWrapping)
                   ? YES
                   : NO;
}

- (NSString *) title {
    return [self stringValue];
}

- (BOOL) isEnabled {
    return NS_EXTRA(NSCell, self)->_isEnabled;
}

- (BOOL) isEditable {
    return NS_EXTRA(NSCell, self)->_isEditable;
}

- (BOOL) isSelectable {
    return NS_EXTRA(NSCell, self)->_isSelectable;
}

- (BOOL) isScrollable {
    return NS_EXTRA(NSCell, self)->_isScrollable;
}

- (BOOL) isBordered {
    return NS_EXTRA(NSCell, self)->_isBordered;
}

- (BOOL) isBezeled {
    return NS_EXTRA(NSCell, self)->_isBezeled;
}

- (BOOL) isContinuous {
    return NS_EXTRA(NSCell, self)->_isContinuous;
}

- (BOOL) showsFirstResponder {
    return NS_EXTRA(NSCell, self)->_showsFirstResponder;
}

// A cell has no mask of its own by default, so the focus ring of a control is the one its view draws, or the control
// asks a cell with a look of its own for the shape of the ring (see _focusRingPathWithFrame:inView:).
- (NSRect) focusRingMaskBoundsForFrame: (NSRect) cellFrame inView: (NSView *) controlView {
    return NSZeroRect;
}

- (void) drawFocusRingMaskWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {
}

- (BOOL) _hasKeyboardFocusInView: (NSView *) controlView {
    NSWindow *window = [controlView window];

    if (window == nil || ![window isKeyWindow] || [window firstResponder] != controlView)
        return NO;
    if ([controlView isKindOfClass: [NSMatrix class]]) {
        if ([(NSMatrix *) controlView keyCell] != self)
            return NO;
    } else if ([controlView isKindOfClass: [NSControl class]]) {
        if ([(NSControl *) controlView selectedCell] != self)
            return NO;
    } else
        return NO;

    NSFocusRingType viewType = [controlView focusRingType];

    if (viewType == NSFocusRingTypeDefault)
        viewType = [[controlView class] defaultFocusRingType];
    return viewType != NSFocusRingTypeNone && NS_EXTRA(NSCell, self)->_focusRingType != NSFocusRingTypeNone;
}

- (NSBezierPath *) _focusRingPathWithFrame: (NSRect) frame inView: (NSView *) controlView {
    return nil;
}

- (BOOL) refusesFirstResponder {
    return NS_EXTRA(NSCell, self)->_refusesFirstResponder;
}

- (BOOL) isHighlighted {
    return NS_EXTRA(NSCell, self)->_isHighlighted;
}

- (BOOL) hasValidObjectValue {
    return NS_EXTRA(NSCell, self)->_hasValidObjectValue;
}

/*
 "Returns the receiver's object value, or nil if a valid object has not been
 associated with the receiver."
 */
- objectValue {
    if (NS_EXTRA(NSCell, self)->_hasValidObjectValue) {
        return NS_EXTRA(NSCell, self)->_objectValue;
    } else {
        return nil;
    }
}

- (NSString *) stringValue {
    NSString *formatted;
    if (NS_EXTRA(NSCell, self)->_formatter != nil)
        if ((formatted = [NS_EXTRA(NSCell, self)->_formatter stringForObjectValue: NS_EXTRA(NSCell, self)->_objectValue]) !=
            nil)
            return formatted;
    if ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]])
        return [NS_EXTRA(NSCell, self)->_objectValue string];
    else if ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSString class]])
        return NS_EXTRA(NSCell, self)->_objectValue;

    if ([NS_EXTRA(NSCell, self)->_objectValue respondsToSelector: @selector(descriptionWithLocale:)])
        return [NS_EXTRA(NSCell, self)->_objectValue descriptionWithLocale: [NSLocale currentLocale]];
    else if ([NS_EXTRA(NSCell, self)->_objectValue respondsToSelector: @selector(description)])
        return [NS_EXTRA(NSCell, self)->_objectValue description];
    else
        return @"";
}

- (int) intValue {
    NSString *objString =
            ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]])
                    ? [NS_EXTRA(NSCell, self)->_objectValue string]
                    : (NSString *) NS_EXTRA(NSCell, self)->_objectValue;
    if ([objString isKindOfClass: [NSString class]]) {
        int i = 0;
        [[NSScanner localizedScannerWithString: objString] scanInt: &i];
        return i;
    } else
        return [NS_EXTRA(NSCell, self)->_objectValue intValue];
}

- (float) floatValue {
    if (NS_EXTRA(NSCell, self)->_objectValue == nil) {
        // [nil someFloatMethod] doesn't return 0.f on Cocotron - tmp fix until
        // the runtime is fixed
        return 0.f;
    }
    NSString *objString =
            ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]])
                    ? [NS_EXTRA(NSCell, self)->_objectValue string]
                    : (NSString *) NS_EXTRA(NSCell, self)->_objectValue;
    if ([objString isKindOfClass: [NSString class]]) {
        float f = 0.0;
        [[NSScanner localizedScannerWithString: objString] scanFloat: &f];
        return f;
    } else {
        return [NS_EXTRA(NSCell, self)->_objectValue floatValue];
    }
}

- (double) doubleValue {
    if (NS_EXTRA(NSCell, self)->_objectValue == nil) {
        // [nil someDoubleMethod] doesn't return 0. on Cocotron - tmp fix until
        // the runtime is fixed
        return 0.;
    }

    NSString *objString =
            ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]])
                    ? [NS_EXTRA(NSCell, self)->_objectValue string]
                    : (NSString *) NS_EXTRA(NSCell, self)->_objectValue;
    if ([objString isKindOfClass: [NSString class]]) {
        double d = 0.0;
        [[NSScanner localizedScannerWithString: objString] scanDouble: &d];
        return d;
    } else
        return [NS_EXTRA(NSCell, self)->_objectValue doubleValue];
}

- (NSInteger) integerValue {
    NSString *objString =
            ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]])
                    ? [NS_EXTRA(NSCell, self)->_objectValue string]
                    : (NSString *) NS_EXTRA(NSCell, self)->_objectValue;
    if ([objString isKindOfClass: [NSString class]]) {
        NSInteger i = 0;
        [[NSScanner localizedScannerWithString: objString] scanInteger: &i];
        return i;
    } else
        return [NS_EXTRA(NSCell, self)->_objectValue integerValue];
}

- (NSAttributedString *) attributedStringValue {
    if ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]])
        return NS_EXTRA(NSCell, self)->_objectValue;
    else {
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        NSMutableParagraphStyle *paraStyle =
                [[[NSParagraphStyle defaultParagraphStyle] mutableCopy]
                        autorelease];
        NSFont *font = [self font];

        if (font != nil)
            [attributes setObject: font forKey: NSFontAttributeName];

        if ([self isEnabled]) {
            if ([self isHighlighted] || [self state])
                [attributes setObject: [NSColor whiteColor]
                               forKey: NSForegroundColorAttributeName];
            else
                [attributes setObject: [NSColor controlTextColor]
                               forKey: NSForegroundColorAttributeName];
        } else {
            [attributes setObject: [NSColor disabledControlTextColor]
                           forKey: NSForegroundColorAttributeName];
        }

        [paraStyle setLineBreakMode: NS_EXTRA(NSCell, self)->_lineBreakMode];
        [paraStyle setAlignment: NS_EXTRA(NSCell, self)->_textAlignment];
        [attributes setObject: paraStyle forKey: NSParagraphStyleAttributeName];

        return [[[NSAttributedString alloc] initWithString: [self stringValue]
                                                attributes: attributes]
                autorelease];
    }
}

- (id) representedObject {
    return NS_EXTRA(NSCell, self)->_representedObject;
}

- (NSControlSize) controlSize {
    return NS_EXTRA(NSCell, self)->_controlSize;
}

- (NSFocusRingType) focusRingType {
    return NS_EXTRA(NSCell, self)->_focusRingType;
}

- (NSBackgroundStyle) backgroundStyle {
    return NS_EXTRA(NSCell, self)->_backgroundStyle;
}

- (NSBackgroundStyle) interiorBackgroundStyle {
    return NS_EXTRA(NSCell, self)->_backgroundStyle;
}

- (void) setControlView: (NSView *) view {
    // Do nothing or raise?
}

- (void) setType: (NSCellType) type {
    if (NS_EXTRA(NSCell, self)->_cellType != type) {
        NS_EXTRA(NSCell, self)->_cellType = type;
        if (type == NSTextCellType) {
            // FIX, localization
            [self setTitle: @"Cell"]; // mostly clarified in setEntryType dox
            [self setFont: [NSFont systemFontOfSize: 12.0]];
        }
        [[[self controlView] window]
                invalidateCursorRectsForView: [self controlView]];
    }
}

- (void) setState: (NSControlStateValue) value {
    if (NS_EXTRA(NSCell, self)->_allowsMixedState) {
        if (value < 0)
            NS_EXTRA(NSCell, self)->_state = -1;
        else if (value > 0)
            NS_EXTRA(NSCell, self)->_state = 1;
        else
            NS_EXTRA(NSCell, self)->_state = 0;
    } else
        NS_EXTRA(NSCell, self)->_state = (ABS(value) > 0) ? 1 : 0;
}

- (NSControlStateValue) nextState {
    if (NS_EXTRA(NSCell, self)->_allowsMixedState) {
        NSControlStateValue value = [self state];
        return value - ((value == -1) ? -2 : 1);
    } else
        return 1 - [self state];
}

- (void) setNextState {
    NS_EXTRA(NSCell, self)->_state = [self nextState];
}

- (BOOL) allowsMixedState; {
    return NS_EXTRA(NSCell, self)->_allowsMixedState;
}

- (void) setAllowsMixedState: (BOOL) allow {
    NS_EXTRA(NSCell, self)->_allowsMixedState = allow;
}

- (BOOL) allowsEditingTextAttributes {
    return NS_EXTRA(NSCell, self)->_allowsEditingTextAttributes;
}

- (void) setAllowsEditingTextAttributes: (BOOL) allow {
    NS_EXTRA(NSCell, self)->_allowsEditingTextAttributes = allow;
}

- (void) setTarget: target {
    [NSException
             raise: NSInternalInconsistencyException
            format: @"-[%@ %s] Unimplemented", [self class], sel_getName(_cmd)];
}

- (void) setAction: (SEL) action {
    [NSException
             raise: NSInternalInconsistencyException
            format: @"-[%@ %s] Unimplemented", [self class], sel_getName(_cmd)];
}

- (void) setTag: (NSInteger) tag {
    [NSException
             raise: NSInternalInconsistencyException
            format: @"-[%@ %s] Unimplemented", [self class], sel_getName(_cmd)];
}

- (void) setEntryType: (NSInteger) type {
    NS_EXTRA(NSCell, self)->_entryType = type;
    [self setType: NSTextCellType];
}

- (void) setFormatter: (NSFormatter *) formatter {
    formatter = [formatter retain];
    [NS_EXTRA(NSCell, self)->_formatter release];
    NS_EXTRA(NSCell, self)->_formatter = formatter;
}

- (void) setFont: (NSFont *) font {
    font = [font retain];
    [NS_EXTRA(NSCell, self)->_font release];
    NS_EXTRA(NSCell, self)->_font = font;
}

// KVC accessors for the fontBold and fontItalic bindings (NSFontBoldBinding, NSFontItalicBinding), which
// a table column applies to its data cell; without them the binding raises for an undefined key. They are not
// public NSCell API, so they are left out of the header.
- (BOOL) _fontHasTrait: (NSFontTraitMask) trait {
    NSFont *font = [self font];

    return font != nil && ([[NSFontManager sharedFontManager] traitsOfFont: font] & trait) != 0;
}

// GUESS: a value of NO takes the trait off the font again (the documentation says only that YES adds it).
// The data cell of a column serves every row, so a row that is not bold must not keep the bold of the row before.
- (void) _setFont: (NSFont *) font trait: (NSFontTraitMask) trait present: (BOOL) present {
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *converted = present ? [manager convertFont: font toHaveTrait: trait]
                                : [manager convertFont: font toNotHaveTrait: trait];

    // GUESS: a cell without a font has nothing to change
    if (converted != nil && converted != font)
        [self setFont: converted];
}

// An NSNumber that is true asks for the trait; a row without the key (nil) asks for none. Taking an id keeps
// key-value coding from raising for nil, which a BOOL parameter would. NSNull raises, as the BOOL setter of
// key-value coding does on macOS 26.7.3 (black-box observation: NSInternalInconsistencyException, "Cannot
// create BOOL from object null of class NSNull"; it is not known whether 10.14.4 differs).
// Test: appkit-cell-font-bold-italic.m, test_missing_and_null_values
static BOOL bindingValueIsTrue(id value) {
    if ([value isKindOfClass: [NSNull class]])
        [NSException raise: NSInternalInconsistencyException
                    format: @"Cannot create BOOL from object %@ of class %@", value, [value class]];
    return [value isKindOfClass: [NSNumber class]] && [value boolValue];
}

- (id) fontBold {
    return [NSNumber numberWithBool: [self _fontHasTrait: NSBoldFontMask]];
}

- (void) setFontBold: (id) value {
    [self _setFont: [self font] trait: NSBoldFontMask present: bindingValueIsTrue(value)];
}

- (id) fontItalic {
    return [NSNumber numberWithBool: [self _fontHasTrait: NSItalicFontMask]];
}

- (void) setFontItalic: (id) value {
    [self _setFont: [self font] trait: NSItalicFontMask present: bindingValueIsTrue(value)];
}

- (void) setImage: (NSImage *) image {
    if (image != nil)
        [self setType: NSImageCellType];

    image = [image retain];
    [NS_EXTRA(NSCell, self)->_image release];
    NS_EXTRA(NSCell, self)->_image = image;
    if ([[self controlView] respondsToSelector: @selector(updateCell:)]) {
        [[self controlView] performSelector: @selector(updateCell:)
                                 withObject: self];
    } else {
        [[self controlView] setNeedsDisplay: YES];
    }
}

- (void) setAlignment: (NSTextAlignment) alignment {
    NS_EXTRA(NSCell, self)->_textAlignment = alignment;
}

- (void) setLineBreakMode: (NSLineBreakMode) value {
    NS_EXTRA(NSCell, self)->_lineBreakMode = value;
}

- (void) setUsesSingleLineMode: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_usesSingleLineMode = flag;
}

- (void) setBaseWritingDirection: (NSWritingDirection) value {
    NS_EXTRA(NSCell, self)->_writingDirection = value;
}

- (void) setWraps: (BOOL) wraps {
    NS_EXTRA(NSCell, self)->_lineBreakMode = wraps ? NSLineBreakByWordWrapping : NSLineBreakByClipping;
}

- (void) setTitle: (NSString *) title {
    [self setStringValue: title];
}

- (void) setEnabled: (BOOL) flag {
    if (NS_EXTRA(NSCell, self)->_isEnabled != flag) {
        NS_EXTRA(NSCell, self)->_isEnabled = flag;
        [[[self controlView] window]
                invalidateCursorRectsForView: [self controlView]];
    }
}

// An editable cell is selectable, and one that isn't selectable isn't editable, as the NSCell reference says
// (also observed on macOS 10.14.4 and 26.7.3; test: appkit-cell-editable-selectable.m)
- (void) setEditable: (BOOL) flag {
    BOOL changed = NS_EXTRA(NSCell, self)->_isEditable != flag || (flag && !NS_EXTRA(NSCell, self)->_isSelectable);
    NS_EXTRA(NSCell, self)->_isEditable = flag;
    if (flag)
        NS_EXTRA(NSCell, self)->_isSelectable = YES;
    if (changed)
        [[[self controlView] window]
                invalidateCursorRectsForView: [self controlView]];
}

- (void) setSelectable: (BOOL) flag {
    BOOL changed = NS_EXTRA(NSCell, self)->_isSelectable != flag || (!flag && NS_EXTRA(NSCell, self)->_isEditable);
    NS_EXTRA(NSCell, self)->_isSelectable = flag;
    if (!flag)
        NS_EXTRA(NSCell, self)->_isEditable = NO;
    if (changed)
        [[[self controlView] window]
                invalidateCursorRectsForView: [self controlView]];
}

- (void) setScrollable: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_isScrollable = flag;
}

- (void) setBordered: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_isBordered = flag;
    NS_EXTRA(NSCell, self)->_isBezeled = NO;
}

- (void) setBezeled: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_isBezeled = flag;
}

- (void) setContinuous: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_isContinuous = flag;
}

- (void) setShowsFirstResponder: (BOOL) value {
    NS_EXTRA(NSCell, self)->_showsFirstResponder = value;
}

- (void) setRefusesFirstResponder: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_refusesFirstResponder = flag;
}

- (void) setHighlighted: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_isHighlighted = flag;
}

// the problem with this method is that the dox specify that if autorange is
// YES, then the field becomes one big floating-point entry, but
// NSNumberFormatter doesn't work that way. - dwy
- (void) setFloatingPointFormat: (BOOL) fpp
                           left: (NSUInteger) left
                          right: (NSUInteger) right
{
    NSMutableString *format = [NSMutableString string];

    [self setFormatter: [[[NSNumberFormatter alloc] init] autorelease]];
    if (fpp == YES) { // autorange
        NSUInteger fieldWidth = left + right;
        while (fieldWidth--)
            [format appendString: @"#"];
    } else {
        while (left--)
            [format appendString: @"#"];
        [format appendString: @"."];
        while (right--)
            [format appendString: @"0"];
    }
    [(NSNumberFormatter *) NS_EXTRA(NSCell, self)->_formatter setFormat: format];
}

- (void) setObjectValue: (id<NSCopying>) value {
    value = [value copyWithZone: NULL];

    [[self controlView] willChangeValueForKey: @"objectValue"];
    [NS_EXTRA(NSCell, self)->_objectValue release];
    NS_EXTRA(NSCell, self)->_objectValue = value;
    NS_EXTRA(NSCell, self)->_hasValidObjectValue = YES;
    [[self controlView] didChangeValueForKey: @"objectValue"];

    if ([[self controlView] respondsToSelector: @selector(updateCell:)]) {
        [[self controlView] performSelector: @selector(updateCell:)
                                 withObject: self];
    } else {
        [[self controlView] setNeedsDisplay: YES];
    }
}

- (void) setStringValue: (NSString *) value {
    if (value == nil) {
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] value==nil", [self class],
                            sel_getName(_cmd)];
        return;
    }

    [self setType: NSTextCellType];

    if (NS_EXTRA(NSCell, self)->_formatter != nil) {
        id formattedValue = nil;
        if ([NS_EXTRA(NSCell, self)->_formatter getObjectValue: &formattedValue
                             forString: value
                      errorDescription: NULL]) {
            value = formattedValue;
        } else {
            // Invalid format
            NS_EXTRA(NSCell, self)->_hasValidObjectValue = NO;
            return;
        }
    }
    [self setObjectValue: value];
}

- (void) setIntValue: (int) value {
    [self setObjectValue: [NSNumber numberWithInt: value]];
}

- (void) setFloatValue: (float) value {
    [self setObjectValue: [NSNumber numberWithFloat: value]];
}

- (void) setDoubleValue: (double) value {
    [self setObjectValue: [NSNumber numberWithDouble: value]];
}

- (void) setIntegerValue: (NSInteger) value {
    [self setObjectValue: [NSNumber numberWithInteger: value]];
}

- (void) setAttributedStringValue: (NSAttributedString *) value {
    [self setObjectValue: value];
}

- (void) setRepresentedObject: (id) object {
    object = [object retain];
    [NS_EXTRA(NSCell, self)->_representedObject release];
    NS_EXTRA(NSCell, self)->_representedObject = object;
}

// Changing the control size leaves the font alone, in every cell class: the
// font for a control size is chosen separately (systemFontSizeForControlSize:
// gives its size). macOS 10.14.4 and 26.7.3 keep the font of every cell class
// across control sizes.
- (void) setControlSize: (NSControlSize) size {
    NS_EXTRA(NSCell, self)->_controlSize = size;
    if ([[self controlView] respondsToSelector: @selector(updateCell:)]) {
        [[self controlView] performSelector: @selector(updateCell:)
                                 withObject: self];
    } else {
        [[self controlView] setNeedsDisplay: YES];
    }
}

- (void) setFocusRingType: (NSFocusRingType) focusRingType {
    NS_EXTRA(NSCell, self)->_focusRingType = focusRingType;
}

- (void) setBackgroundStyle: (NSBackgroundStyle) value {
    NS_EXTRA(NSCell, self)->_backgroundStyle = value;
}

- (void) takeObjectValueFrom: sender {
    [self setObjectValue: [sender objectValue]];
}

- (void) takeStringValueFrom: sender {
    [self setStringValue: [sender stringValue]];
}

- (void) takeIntValueFrom: sender {
    [self setIntValue: [sender intValue]];
}

- (void) takeFloatValueFrom: sender {
    [self setFloatValue: [sender floatValue]];
}

- (void) takeDoubleValueFrom: sender {
    [self setDoubleValue: [sender doubleValue]];
}

- (void) takeIntegerValueFrom: sender {
    [self setIntegerValue: [sender integerValue]];
}

- (NSSize) cellSize {
    return NSMakeSize(10000, 10000);
}

- (NSSize) cellSizeForBounds: (NSRect) rect {
    NSSize result = [self cellSize];

    return NSMakeSize(MIN(rect.size.width, result.width),
                      MIN(rect.size.height, result.height));
}

- (NSRect) imageRectForBounds: (NSRect) rect {
    return rect;
}

- (NSRect) titleRectForBounds: (NSRect) rect {
    return rect;
}

- (NSRect) drawingRectForBounds: (NSRect) rect {
    return rect;
}

- (void) drawInteriorWithFrame: (NSRect) frame inView: (NSView *) view {
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) view {

    if ([self type] == NSTextCellType) {
        if ([self isBezeled])
            NSDrawWhiteBezel(frame, frame);
    }

    [self drawInteriorWithFrame: [self drawingRectForBounds: frame]
                         inView: view];
}

- (void) highlight: (BOOL) highlight
         withFrame: (NSRect) frame
            inView: (NSView *) view
{
    if (NS_EXTRA(NSCell, self)->_isHighlighted != highlight) {
        NS_EXTRA(NSCell, self)->_isHighlighted = highlight;
    }
}

- (BOOL) startTrackingAt: (NSPoint) startPoint inView: (NSView *) view {
    return YES;
}

- (BOOL) continueTracking: (NSPoint) lastPoint
                       at: (NSPoint) currentPoint
                   inView: (NSView *) view
{
    return YES;
}

- (void) stopTracking: (NSPoint) lastPoint
                   at: (NSPoint) stopPoint
               inView: (NSView *) view
            mouseIsUp: (BOOL) flag
{
}

- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) frame
              ofView: (NSView *) view
        untilMouseUp: (BOOL) untilMouseUp
{
    NSPoint lastPoint;
    BOOL result = NO;

    if (![self startTrackingAt: [event locationInWindow] inView: view])
        return NO;

    do {
        NSPoint currentPoint;
        BOOL isWithinCellFrame;

        lastPoint = [event locationInWindow];
        currentPoint = [view convertPoint: [event locationInWindow]
                                 fromView: nil];
        isWithinCellFrame =
                NSMouseInRect(currentPoint, frame, [view isFlipped]);

        if (untilMouseUp) {
            if ([event type] == NSLeftMouseUp) {
                [self stopTracking: lastPoint
                                at: [event locationInWindow]
                            inView: view
                         mouseIsUp: YES];
                result = YES;
                break;
            }
        } else if (isWithinCellFrame) {
            if ([event type] == NSLeftMouseUp) {
                [self stopTracking: lastPoint
                                at: [event locationInWindow]
                            inView: view
                         mouseIsUp: YES];
                result = YES;
                break;
            }
        } else {
            [self stopTracking: lastPoint
                            at: [event locationInWindow]
                        inView: view
                     mouseIsUp: NO];
            result = NO;
            break;
        }

        if (untilMouseUp || isWithinCellFrame) {
            if (![self continueTracking: lastPoint
                                     at: [event locationInWindow]
                                 inView: view])
                break;

            if ([self isContinuous])
                [(NSControl *) view sendAction: [(NSControl *) view action]
                                            to: [(NSControl *) view target]];
        }

        [[view window] flushWindow];

        event = [[view window] nextEventMatchingMask: NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];

    } while (YES);

    return result;
}

- (NSText *) setUpFieldEditorAttributes: (NSText *) editor {
    [editor setEditable: [self isEditable]];
    [editor setSelectable: [self isSelectable]];
    NSString *strValue = nil;
    if (NS_EXTRA(NSCell, self)->_formatter) {
        // Prioritize the editing string value over everything else
        strValue = [NS_EXTRA(NSCell, self)->_formatter editingStringForObjectValue: [self objectValue]];
    }
    if (strValue == nil) {
        strValue = [self stringValue];
    }
    [editor setRichText: NS_EXTRA(NSCell, self)->_isRichText];
    [editor setString: strValue];
    [editor setFont: [self font]];
    [editor setAlignment: [self alignment]];
    if ([self respondsToSelector: @selector(drawsBackground)])
        [editor setDrawsBackground: (BOOL)(int) [self performSelector: @selector
                                                      (drawsBackground)]];
    if ([self respondsToSelector: @selector(backgroundColor)])
        [editor setBackgroundColor: [self performSelector: @selector
                                            (backgroundColor)]];

    return editor;
}

- (void) _setupFieldEditorWithFrame: (NSRect) frame
                        controlView: (NSView *) view
                             editor: (NSText *) editor
                           delegate: delegate
{
    /* There is some funkiness here where the editor is already in the control
       and it is moving to a different cell or the same cell is being edited
       after a makeFirstResponder This needs to be straightened out
     */
    if ([self isScrollable] || [self wraps]) {
        NSClipView *clipView;

        if ([[editor superview] isKindOfClass: [NSClipView class]] &&
            [[editor superview] superview] == view) {
            clipView = (NSClipView *) [editor superview];
            [clipView setFrame: frame];
        } else {
            clipView = [[[NSClipView alloc] initWithFrame: frame] autorelease];
            [editor setFrameOrigin: NSZeroPoint];
            [editor setFrameSize: frame.size];
            [clipView setDocumentView: editor];
            [view addSubview: clipView];
        }

        [clipView
                setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        [editor setAutoresizingMask: 0];
        [editor setHorizontallyResizable: [self isScrollable]];
        [editor setVerticallyResizable: YES];
        [editor sizeToFit];
        [editor setNeedsDisplay: YES];
    } else {
        [editor setHorizontallyResizable: NO];
        [editor setVerticallyResizable: NO];
        [editor setFrame: frame];
        [view addSubview: editor];
    }
    [[view window] makeFirstResponder: editor];
    [editor setDelegate: delegate];

    if ([editor isKindOfClass: [NSTextView class]]) {
        NSCellUndoManager *undoManager = [[NSCellUndoManager alloc] init];
        [undoManager setNextUndoManager: [[view window] undoManager]];
        [(NSTextView *) editor _setFieldEditorUndoManager: undoManager];
        [undoManager release];
        [(NSTextView *) editor setAllowsUndo: YES];
    }
}

- (void) editWithFrame: (NSRect) frame
                inView: (NSView *) view
                editor: (NSText *) editor
              delegate: (id) delegate
                 event: (NSEvent *) event
{

    if (![self isEditable] && ![self isSelectable])
        return;

    if (view == nil || editor == nil || [self font] == nil ||
        NS_EXTRA(NSCell, self)->_cellType != NSTextCellType)
        return;

    [self _setupFieldEditorWithFrame: frame
                         controlView: view
                              editor: editor
                            delegate: delegate];
    [editor mouseDown: event];
}

- (void) selectWithFrame: (NSRect) frame
                  inView: (NSView *) view
                  editor: (NSText *) editor
                delegate: (id) delegate
                   start: (NSInteger) location
                  length: (NSInteger) length
{
    if (![self isEditable] && ![self isSelectable])
        return;

    if (view == nil || editor == nil || [self font] == nil ||
        NS_EXTRA(NSCell, self)->_cellType != NSTextCellType)
        return;

    [self _setupFieldEditorWithFrame: frame
                         controlView: view
                              editor: editor
                            delegate: delegate];
    NSRange range = NSMakeRange(location, length);
    NSRange maxRange = NSMakeRange(0, [[editor string] length]);
    [editor setSelectedRange: NSIntersectionRange(range, maxRange)];
}

- (void) endEditing: (NSText *) editor {
    [self setStringValue: [editor string]];
}

- (void) resetCursorRect: (NSRect) rect inView: (NSView *) view {
    if (([self type] == NSTextCellType) && [self isEnabled]) {
        if ([self isEditable] || [self isSelectable]) {
            NSRect titleRect = [self titleRectForBounds: rect];

            titleRect = NSIntersectionRect(titleRect, [view visibleRect]);

            if (!NSIsEmptyRect(titleRect))
                [view addCursorRect: titleRect cursor: [NSCursor IBeamCursor]];
        }
    }
}

- (void) setSendsActionOnEndEditing: (BOOL) flag {
    NS_EXTRA(NSCell, self)->_sendsActionOnEndEditing = flag;
}

- (BOOL) sendsActionOnEndEditing {
    return NS_EXTRA(NSCell, self)->_sendsActionOnEndEditing;
}

static NSString *NSStringFromCellType(NSCellType type) {
    switch (type) {
    case NSNullCellType:
        return @"NSNullCellType";
    case NSImageCellType:
        return @"NSImageCellType";
    case NSTextCellType:
        return @"NSTextCellType";
    default:
        break;
    }
    return [NSString stringWithFormat: @"Unknown: %lu", (unsigned long) type];
}

- (NSString *) description {
    return [NSString
            stringWithFormat: @"%@\n\ttype: %@\n\tfont: %@\n\tobjectValue: %@",
                              [super description],
                              NSStringFromCellType(NS_EXTRA(NSCell, self)->_cellType), NS_EXTRA(NSCell, self)->_font,
                              NS_EXTRA(NSCell, self)->_objectValue];
}

- (void) _validateEditing: (id)unknown
{
    // required by ibtool
}

- (NSMenu *) menuForEvent: (NSEvent *) event
                   inRect: (NSRect) rect
                   ofView: (NSView *) view
{
    return [self menu];
}

@end

void NSDrawThreePartImage(NSRect frame, NSImage *startCap, NSImage *centerFill,
                          NSImage *endCap, BOOL vertical,
                          NSCompositingOperation operation, CGFloat alpha,
                          BOOL flipped)
{
    NSUnimplementedFunction();
}

void NSDrawNinePartImage(NSRect frame, NSImage* topLeftCorner,
                          NSImage* topEdgeFill, NSImage* topRightCorner,
                          NSImage* leftEdgeFill, NSImage* centerFill,
                          NSImage* rightEdgeFill, NSImage* bottomLeftCorner,
                          NSImage* bottomEdgeFill, NSImage* bottomRightCorner,
                          NSCompositingOperation operation, CGFloat alpha,
                          BOOL flipped)
{
    NSUnimplementedFunction();
};
