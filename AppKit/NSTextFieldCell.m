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

#import "NSCoder+AppKit.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSObject+BindingSupport.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSTextFieldCell.h>
#import <Foundation/NSKeyedArchiver.h>

@implementation NSTextFieldCell

NS_EXTRA_SYNTHESIZE_COPY(NSTextFieldCell, allowedInputSourceLocales, _allowedInputSourceLocales, NSArray *, allowedInputSourceLocales, setAllowedInputSourceLocales:)

- (void) encodeWithCoder: (NSCoder *) coder {
    [super encodeWithCoder: coder];

    if (coder.allowsKeyedCoding) {
        [coder encodeBool: NS_EXTRA(NSTextFieldCell, self)->_drawsBackground forKey: @"NSDrawsBackground"];
        [coder encodeObject: _backgroundColor forKey: @"NSBackgroundColor"];
        [coder encodeObject: _textColor forKey: @"NSTextColor"];
        [coder encodeInteger: NS_EXTRA(NSTextFieldCell, self)->_bezelStyle forKey: @"NSTextBezelStyle"];
        [coder encodeObject: NS_EXTRA(NSTextFieldCell, self)->_placeholder forKey: @"NSPlaceholderString"];
    } else {
        [NSException raise: NSInvalidArchiveOperationException
                    format: @"TODO: support unkeyed encoding in NSTextFieldCell"];
    }
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        NS_EXTRA(NSTextFieldCell, self)->_drawsBackground = [keyed decodeBoolForKey: @"NSDrawsBackground"];
        _backgroundColor =
                [[keyed decodeObjectForKey: @"NSBackgroundColor"] retain];
        _textColor = [[keyed decodeObjectForKey: @"NSTextColor"] retain];
        NS_EXTRA(NSTextFieldCell, self)->_bezelStyle = [keyed decodeIntegerForKey: @"NSTextBezelStyle"];
        NS_EXTRA(NSTextFieldCell, self)->_placeholder =
                [[keyed decodeObjectForKey: @"NSPlaceholderString"] retain];
    } else {
        NSInteger version = [coder versionForClassName: @"NSTextFieldCell"];
        if (version > 40) {
            uint8_t flags;
            [coder decodeValuesOfObjCTypes: "c@@", &flags, &_backgroundColor,
                                            &_textColor];

            NS_EXTRA(NSTextFieldCell, self)->_drawsBackground = flags & 1;
            NS_EXTRA(NSTextFieldCell, self)->_bezelStyle = (flags & 0xe) >> 1;

            if (version <= 60) {
                if ([_textColor isEqual: [NSColor textColor]])
                    [self setTextColor: [NSColor controlTextColor]];
            }
        } else if (version > 16) {
            char drawsBackground = 0;
            [coder decodeValuesOfObjCTypes: "c", &drawsBackground];
            NS_EXTRA(NSTextFieldCell, self)->_drawsBackground = drawsBackground != 0;
            [self setBackgroundColor: [coder decodeObject]];
            [self setTextColor: [coder decodeObject]];
        } else if (version > 1) {
            char drawsBackground = 0;
            [coder decodeValuesOfObjCTypes: "@@c", &_backgroundColor,
                                            &_textColor, &drawsBackground];
            NS_EXTRA(NSTextFieldCell, self)->_drawsBackground = drawsBackground != 0;
        } else {
            float bgcolor, fgcolor;
            [coder decodeValuesOfObjCTypes: "ff", &bgcolor, &fgcolor];

            if (bgcolor <= 0.0f) {
                NS_EXTRA(NSTextFieldCell, self)->_drawsBackground = FALSE;
                [self setBackgroundColor: [NSColor whiteColor]];
            } else {
                NS_EXTRA(NSTextFieldCell, self)->_drawsBackground = TRUE;
                [self setBackgroundColor:
                                [NSColor colorWithCalibratedWhite: bgcolor
                                                            alpha: 1.0]];
            }
            [self setTextColor: [NSColor colorWithCalibratedWhite: fgcolor
                                                            alpha: 1.0]];

            if (version != 0) {
                NSColor *color = [coder decodeNXColor];
                if (color != nil)
                    [self setTextColor: color];

                color = [coder decodeNXColor];
                if (color != nil)
                    [self setBackgroundColor: color];
            }
        }

        if (version <= 55) {
            // Fix some hardcoded colors
            if ([_backgroundColor isEqual: [NSColor whiteColor]])
                [self setBackgroundColor: [NSColor textBackgroundColor]];
            else if ([_backgroundColor isEqual: [NSColor lightGrayColor]])
                [self setBackgroundColor: [NSColor controlColor]];

            if ([_textColor isEqual: [NSColor blackColor]])
                [self setTextColor: [NSColor controlTextColor]];
        }
    }

    return self;
}

// QUIRK: a new text field cell has textBackgroundColor as its background
// colour, although it does not draw a background (see -[NSTextField
// initWithFrame:]). Not documented. Evidence: black-box observation on macOS
// 10.14.4 and 26.7.3 (tier 2), probe mac-probes/aqua-metric-followups.m of the
// research notes. Test: appkit-text-field-defaults.m (test_quirk_cell_defaults)
- initTextCell: (NSString *) string {
    [super initTextCell: string];
    // default for _isBezeled=NO;
    _backgroundColor = [[NSColor textBackgroundColor] retain];
    return self;
}

// Override NSCell behavior of creating an image/null type cell
- init {
    return [self initTextCell: @""];
}

- (void) dealloc {
    [_backgroundColor release];
    [_textColor release];
    [NS_EXTRA(NSTextFieldCell, self)->_placeholder release];
    [NS_EXTRA(NSTextFieldCell, self)->_allowedInputSourceLocales release];
    NS_EXTRA_FREE(NSTextFieldCell, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSTextFieldCell *cell = [super copyWithZone: zone];
    NS_EXTRA_COPY(NSTextFieldCell, cell, self);
    NS_EXTRA(NSTextFieldCell, cell)->_placeholder =
        [NS_EXTRA(NSTextFieldCell, self)->_placeholder copyWithZone: zone];
    NS_EXTRA(NSTextFieldCell, cell)->_allowedInputSourceLocales =
        [NS_EXTRA(NSTextFieldCell, self)->_allowedInputSourceLocales copyWithZone: zone];

    cell->_backgroundColor = [_backgroundColor copy];
    cell->_textColor = [_textColor copy];

    return cell;
}

- (NSCellType) type {
    return NSTextCellType;
}

- (NSColor *) backgroundColor {
    return _backgroundColor;
}

- (NSColor *) textColor {
    return _textColor;
}

- (BOOL) drawsBackground {
    return NS_EXTRA(NSTextFieldCell, self)->_drawsBackground;
}

- (NSTextFieldBezelStyle) bezelStyle {
    return NS_EXTRA(NSTextFieldCell, self)->_bezelStyle;
}

- (NSString *) placeholderString {
    if ([NS_EXTRA(NSTextFieldCell, self)->_placeholder isKindOfClass: [NSString class]])
        return NS_EXTRA(NSTextFieldCell, self)->_placeholder;

    return nil;
}

- (NSAttributedString *) placeholderAttributedString {
    if ([NS_EXTRA(NSTextFieldCell, self)->_placeholder isKindOfClass: [NSAttributedString class]])
        return NS_EXTRA(NSTextFieldCell, self)->_placeholder;

    return nil;
}

- (void) setBackgroundColor: (NSColor *) color {
    color = [color retain];
    [_backgroundColor release];
    _backgroundColor = color;
}

- (void) setTextColor: (NSColor *) color {
    color = [color retain];
    [_textColor release];
    _textColor = color;
}

- (void) setDrawsBackground: (BOOL) flag {
    NS_EXTRA(NSTextFieldCell, self)->_drawsBackground = flag;
}

- (void) setBezelStyle: (NSTextFieldBezelStyle) value {
    NS_EXTRA(NSTextFieldCell, self)->_bezelStyle = value;
}

- (void) setPlaceholderString: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(NSTextFieldCell, self)->_placeholder release];
    NS_EXTRA(NSTextFieldCell, self)->_placeholder = value;
}

- (void) setPlaceholderAttributedString: (NSAttributedString *) value {
    value = [value copy];
    [NS_EXTRA(NSTextFieldCell, self)->_placeholder release];
    NS_EXTRA(NSTextFieldCell, self)->_placeholder = value;
}

// titleRectForBounds is not used for generating the value rect in a text field
- (NSRect) _valueRectForBounds: (NSRect) rect {
    if ([self isBezeled]) {

        switch ([self bezelStyle]) {
        default:
        case NSTextFieldSquareBezel:
            rect = NSInsetRect(rect, 3, 3);
            break;

        case NSTextFieldRoundedBezel:;
            CGFloat radius = rect.size.height / 2;
            rect = NSInsetRect(rect, radius, 3);
            break;
        }
    } else if ([self isBordered])
        rect = NSInsetRect(rect, 2, 2);
    else
        rect = NSInsetRect(rect, 2, 0);

    return rect;
}

- (NSRect) titleRectForBounds: (NSRect) rect {
    return [self _valueRectForBounds: rect];
}

- (NSRect) drawingRectForBounds: (NSRect) rect {
    return [self _valueRectForBounds: rect];
}

// The colours a text field takes from the system and can therefore change with the background it is on,
// unlike a colour the application picked.
static BOOL isSystemTextColor(NSColor *color) {
    if (color == nil)
        return YES;
    return [color isEqual: [NSColor controlTextColor]] || [color isEqual: [NSColor textColor]] ||
           [color isEqual: [NSColor labelColor]] || [color isEqual: [NSColor secondaryLabelColor]] ||
           [color isEqual: [NSColor alternateSelectedControlTextColor]];
}

- (NSAttributedString *) attributedStringValue {
    // On an emphasized (dark) background, as in a selected row of a table, a borderless, transparent cell
    // draws its system text colour as the selected text colour.
    BOOL onDarkBackground = [self isEnabled] && [self backgroundStyle] == NSBackgroundStyleEmphasized &&
                            ![self isBezeled] && ![self drawsBackground];
    NSColor *textColor = _textColor;

    if (onDarkBackground && isSystemTextColor(textColor))
        textColor = [NSColor alternateSelectedControlTextColor];

    if ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]]) {
        if (textColor == nil && !onDarkBackground)
            return NS_EXTRA(NSCell, self)->_objectValue;
        else {
            NSMutableAttributedString *result =
                    [[NS_EXTRA(NSCell, self)->_objectValue mutableCopy] autorelease];
            NSUInteger location = 0, length = [result length];

            // The text colour fills in where the attributed text has no
            // colour of its own: the colours of the text are kept (macOS
            // 10.14.4, tests/appkit-text-field-label-attributed.m).
            while (location < length) {
                NSRange range;
                id color = [result attribute: NSForegroundColorAttributeName
                                     atIndex: location
                       longestEffectiveRange: &range
                                     inRange: NSMakeRange(location, length - location)];
                if (color == nil) {
                    if (textColor != nil)
                        [result addAttribute: NSForegroundColorAttributeName value: textColor range: range];
                } else if (onDarkBackground && isSystemTextColor(color)) {
                    [result addAttribute: NSForegroundColorAttributeName
                                   value: [NSColor alternateSelectedControlTextColor]
                                   range: range];
                }
                location = NSMaxRange(range);
            }

            return result;
        }
    } else {
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        NSMutableParagraphStyle *paraStyle =
                [[[NSParagraphStyle defaultParagraphStyle] mutableCopy]
                        autorelease];
        NSFont *font = [self font];

        if (font != nil)
            [attributes setObject: font forKey: NSFontAttributeName];

        if ([self isEnabled]) {
            if (textColor != nil)
                [attributes setObject: textColor
                               forKey: NSForegroundColorAttributeName];
        } else {
            [attributes setObject: [NSColor disabledControlTextColor]
                           forKey: NSForegroundColorAttributeName];
        }

#if 0
    if([self drawsBackground]/* && ![self isBezeled]*/){
     NSColor *color=(_backgroundColor==nil)?[NSColor controlColor]:_backgroundColor;
     [attributes setObject:color
                    forKey:NSBackgroundColorAttributeName];
    }
#endif

        [paraStyle setLineBreakMode: NS_EXTRA(NSCell, self)->_lineBreakMode];
        [paraStyle setAlignment: NS_EXTRA(NSCell, self)->_textAlignment];
        [attributes setObject: paraStyle forKey: NSParagraphStyleAttributeName];

        return [[[NSAttributedString alloc] initWithString: [self stringValue]
                                                attributes: attributes]
                autorelease];
    }
}

// The space around the text that cellSize adds for the cell's border style.
// QUIRK: a square bezel adds 8 points across and 5 down (4 at the mini size),
// a line border 8 and 4, no border 4 across; a rounded bezel adds 21, 20 and
// 19 points across at the regular, small and mini sizes, and its height is
// that of the bezel (see -_aquaRoundedBezelHeight). The bezeled sizes are
// rounded up to whole points. Not documented. Evidence: black-box observation
// of cellSize, sizeToFit and titleRectForBounds: on macOS 10.14.4 (tier 2),
// probes mac-probes/aqua-metric-followups.m and -3.m of the research notes.
// Test: appkit-text-field-defaults.m (test_quirk_cell_size)
- (NSSize) _textInsetSize {
    NSControlSize size = [self controlSize];

    if ([self isBezeled]) {
        if ([self bezelStyle] == NSTextFieldRoundedBezel)
            return NSMakeSize(size == NSMiniControlSize ? 19 : (size == NSSmallControlSize ? 20 : 21), 0);
        return NSMakeSize(8, size == NSMiniControlSize ? 4 : 5);
    }
    if ([self isBordered])
        return NSMakeSize(8, 4);
    return NSMakeSize(4, 0);
}

- (CGFloat) _aquaRoundedBezelHeight {
    static const CGFloat heights[3] = {22, 19, 17};
    NSControlSize size = [self controlSize];

    return heights[size == NSSmallControlSize ? 1 : (size == NSMiniControlSize ? 2 : 0)];
}

// Rounds a bezeled cell's size up to whole points and gives a rounded bezel
// its fixed height.
- (NSSize) _adjustedCellSize: (NSSize) size {
    if (![self isBezeled])
        return size;
    size.width = ceil(size.width);
    size.height = [self bezelStyle] == NSTextFieldRoundedBezel ? [self _aquaRoundedBezelHeight] : ceil(size.height);
    return size;
}

// The number of lines a wrapping field shows at most; 0 means no limit. NSTextField's
// maximumNumberOfLines is kept here, where the text is laid out.
- (NSInteger) _maximumNumberOfLines {
    return NS_EXTRA(NSTextFieldCell, self)->_maximumNumberOfLines;
}

- (void) _setMaximumNumberOfLines: (NSInteger) value {
    NS_EXTRA(NSTextFieldCell, self)->_maximumNumberOfLines = value;
}

// A cell that wraps its text needs more height as the width shrinks: the width is that of the
// widest line the text breaks into (never more than offered) and the height that of all the
// lines, capped at the height offered and at the lines the field may show.
- (NSSize) cellSizeForBounds: (NSRect) rect {
    if (![self wraps])
        return [super cellSizeForBounds: rect];

    NSSize inset = [self _textInsetSize];
    NSSize room = NSMakeSize(MAX(rect.size.width - inset.width, 1), NSStringDrawerLargeDimension);
    NSInteger maximumLines = NS_EXTRA(NSTextFieldCell, self)->_maximumNumberOfLines;
    NSSize text = NSZeroSize;
    BOOL capped = NO;
    if (maximumLines > 0) {
        // Only text with more lines than the cap is measured as capped; any other is measured as
        // without a cap, so a cap above the number of lines changes nothing.
        BOOL hidden = NO;
        NSSize cappedText = [[NSStringDrawer sharedStringDrawer] sizeOfAttributedString: [self attributedStringValue]
                                                                          fittingInSize: room
                                                                   maximumNumberOfLines: maximumLines
                                                                          lastLineRange: NULL
                                                                          hasHiddenText: &hidden];
        if (hidden) {
            text = cappedText;
            capped = YES;
        }
    }
    if (!capped)
        text = [[NSStringDrawer sharedStringDrawer] sizeOfAttributedString: [self attributedStringValue]
                                                                    inSize: room];

    NSSize size = [self _adjustedCellSize: NSMakeSize(text.width + inset.width, ceil(text.height) + inset.height)];

    return NSMakeSize(MIN(rect.size.width, size.width), MIN(rect.size.height, size.height));
}

- (NSSize) cellSize {
    NSSize size = [[self attributedStringValue] size];
    NSSize inset = [self _textInsetSize];

    return [self _adjustedCellSize: NSMakeSize(size.width + inset.width, size.height + inset.height)];
}

- (void) editWithFrame: (NSRect) frame
                inView: (NSView *) view
                editor: (NSText *) editor
              delegate: (id) delegate
                 event: (NSEvent *) event
{
    frame = [self titleRectForBounds: frame];
    [super editWithFrame: frame
                  inView: view
                  editor: editor
                delegate: delegate
                   event: event];
}

- (void) selectWithFrame: (NSRect) frame
                  inView: (NSView *) view
                  editor: (NSText *) editor
                delegate: (id) delegate
                   start: (NSInteger) location
                  length: (NSInteger) length
{
    frame = [self titleRectForBounds: frame];
    [super selectWithFrame: frame
                    inView: view
                    editor: editor
                  delegate: delegate
                     start: location
                    length: length];
}

- (void) drawInteriorWithFrame: (NSRect) frame inView: (NSView *) control {
    NSRect titleRect = [self titleRectForBounds: frame];

    NSAttributedString *drawValue = [self attributedStringValue];

    if ([drawValue length] == 0 && [NS_EXTRA(NSTextFieldCell, self)->_placeholder length] > 0) {
        if ([NS_EXTRA(NSTextFieldCell, self)->_placeholder isKindOfClass: [NSAttributedString class]])
            drawValue = NS_EXTRA(NSTextFieldCell, self)->_placeholder;
        else if ([NS_EXTRA(NSTextFieldCell, self)->_placeholder isKindOfClass: [NSString class]]) {
            NSMutableAttributedString *placeString =
                    [[drawValue mutableCopy] autorelease];
            [[placeString mutableString] setString: NS_EXTRA(NSTextFieldCell, self)->_placeholder];
            [placeString addAttribute: NSForegroundColorAttributeName
                                value: [NSColor placeholderTextColor]
                                range: NSMakeRange(0, [placeString length])];
            drawValue = placeString;
        }
    }
    NSInteger maximumLines = NS_EXTRA(NSTextFieldCell, self)->_maximumNumberOfLines;
    BOOL hidden = NO;
    NSSize lines = NSZeroSize;
    if (maximumLines > 0 && [self wraps] && [drawValue length] > 0)
        lines = [[NSStringDrawer sharedStringDrawer] sizeOfAttributedString: drawValue
                                                              fittingInSize: NSMakeSize(titleRect.size.width, NSStringDrawerLargeDimension)
                                                       maximumNumberOfLines: maximumLines
                                                              lastLineRange: NULL
                                                              hasHiddenText: &hidden];
    // Text that fits the cap is drawn as without one.
    if (hidden) {
        // Show whole lines only, the first maximumLines of them, with the last one ending in an
        // ellipsis when the cell truncates its last visible line.
        NSRect textRect = titleRect;
        textRect.size.height = MIN(lines.height, titleRect.size.height);
        // GUESS: the text is anchored at the top edge of the rect it is drawn in, as the
        // -drawWithRect:options: path does for a context that is not flipped; not checked on a display.
        if (![[NSGraphicsContext currentContext] isFlipped])
            textRect.origin.y = NSMaxY(titleRect) - textRect.size.height;

        NSStringDrawingOptions options = NSStringDrawingUsesLineFragmentOrigin;
        if ([self truncatesLastVisibleLine])
            options |= NSStringDrawingTruncatesLastVisibleLine;
        [drawValue drawWithRect: textRect options: options];
        return;
    }
    [drawValue _clipAndDrawInRect: titleRect
                   lineBreakMode: NS_EXTRA(NSCell, self)->_lineBreakMode];
}

// QUIRK: the rounded bezel of a text field and the bezel of a search field are 22, 19 and 17 points high (regular,
// small and mini control sizes) and are centred vertically in a taller frame, the odd point going above. Not
// documented. Evidence: black-box renders of NSTextField and NSSearchField in frames 14 to 32 points high on macOS
// 10.14.4 (tier 2), probe mac-probes/aqua-toolbar-2.m of the research notes.
// Test: appkit-toolbar-controls-aqua.m (test_quirk_field_bezels)
- (NSRect) _aquaRoundedBezelRectForFrame: (NSRect) frame inView: (NSView *) control {
    CGFloat height = [self _aquaRoundedBezelHeight];

    if (NSHeight(frame) <= height)
        return frame;

    CGFloat above = ceil((NSHeight(frame) - height) / 2);

    frame.origin.y += [control isFlipped] ? above : NSHeight(frame) - height - above;
    frame.size.height = height;
    return frame;
}

- (void) _drawSquareBezelInRect: (NSRect) frame inView: (NSView *) control {
    [[control graphicsStyle] drawTextFieldBorderInRect: frame bezeledNotLine: YES enabled: [self isEnabled]];
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) control {
    NSRect backRect = [self drawingRectForBounds: frame];

    _controlView = control;

    if ([self isBezeled]) {
        switch ([self bezelStyle]) {
        default:
        case NSTextFieldSquareBezel:
            [self _drawSquareBezelInRect: frame inView: control];
            backRect = NSInsetRect(backRect, -1, -1);
            break;

        case NSTextFieldRoundedBezel:
            // QUIRK: the rounded bezel has a 4 point radius on macOS 10.14, not that of a capsule; see
            // -drawRoundedTextFieldBezelInRect:radius:enabled:
            [[control graphicsStyle] drawRoundedTextFieldBezelInRect: [self _aquaRoundedBezelRectForFrame: frame
                                                                                                  inView: control]
                                                              radius: 4
                                                             enabled: [self isEnabled]];
            break;
        }

    } else {
        if ([self isBordered]) {
            [[control graphicsStyle] drawTextFieldBorderInRect: frame
                                                bezeledNotLine: NO
                                                       enabled: [self isEnabled]];
            backRect = NSInsetRect(backRect, -1, -1);
        }
    }

    if ([self drawsBackground]) {
        if (!([self isBezeled] &&
              [self bezelStyle] == NSTextFieldRoundedBezel)) {
            NSColor *color = (_backgroundColor == nil) ? [NSColor controlColor]
                                                       : _backgroundColor;

            [color setFill];
            NSRectFillUsingOperation(backRect, NSCompositeSourceOver);
        }
    }

    [self drawInteriorWithFrame: frame inView: control];
}

@end

@implementation NSTextFieldCell (Bindings)

- (CGFloat) _fontSize {
    return [NS_EXTRA(NSCell, self)->_font pointSize];
}
- (void) _setFontSize: (CGFloat) fontSize {
    NSString *fontName = [NS_EXTRA(NSCell, self)->_font fontName];
    [self setFont: [NSFont fontWithName: fontName size: fontSize]];
}
- (NSString *) _fontFamilyName {
    return [NS_EXTRA(NSCell, self)->_font familyName];
}
- (void) _setFontFamilyName: (NSString *) familyName {
    if (!familyName) {
        return;
    }

    NSLog(@"_setFontFamilyName: %@", familyName);

    CGFloat currentSize = [NS_EXTRA(NSCell, self)->_font pointSize];
    [self setFont: [NSFont fontWithName: familyName size: currentSize]];
}

- (id) _replacementKeyPathForBinding: (id) binding {
    if ([binding isEqual: @"value"])
        return @"stringValue";
    return [super _replacementKeyPathForBinding: binding];
}

@end
