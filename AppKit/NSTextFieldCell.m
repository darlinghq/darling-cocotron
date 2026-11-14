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

- initTextCell: (NSString *) string {
    [super initTextCell: string];
    // default for _isBezeled=NO;
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

- (NSAttributedString *) attributedStringValue {
    if ([NS_EXTRA(NSCell, self)->_objectValue isKindOfClass: [NSAttributedString class]]) {
        if (_textColor == nil)
            return NS_EXTRA(NSCell, self)->_objectValue;
        else {
            NSMutableAttributedString *result =
                    [[NS_EXTRA(NSCell, self)->_objectValue mutableCopy] autorelease];

            [result addAttribute: NSForegroundColorAttributeName
                           value: _textColor
                           range: NSMakeRange(0, [result length])];

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
            if (_textColor != nil)
                [attributes setObject: _textColor
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

- (NSSize) cellSize {
    NSSize size = [[self attributedStringValue] size];

    if ([self isBezeled]) {
        size.width += 6;
        size.height += 6;
    } else if ([self isBordered]) {
        size.width += 4;
        size.height += 4;
    } else {
        size.width += 4;
    }
    return size;
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
                                value: [NSColor disabledControlTextColor]
                                range: NSMakeRange(0, [placeString length])];
            drawValue = placeString;
        }
    }
    [drawValue _clipAndDrawInRect: titleRect
                   lineBreakMode: NS_EXTRA(NSCell, self)->_lineBreakMode];
}

static void drawRoundedBezel(CGContextRef context, CGRect frame) {
    CGFloat radius = frame.size.height / 2;

    CGContextBeginPath(context);
    CGContextAddArc(context, CGRectGetMaxX(frame) - radius,
                    CGRectGetMinY(frame) + radius, radius, M_PI_2, M_PI_2 * 3,
                    YES);
    CGContextAddArc(context, CGRectGetMinX(frame) + radius,
                    CGRectGetMinY(frame) + radius, radius, M_PI_2 * 3, M_PI_2,
                    YES);
    CGContextClosePath(context);
    CGContextFillPath(context);
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) control {
    NSRect backRect = [self drawingRectForBounds: frame];

    _controlView = control;

    if ([self isBezeled]) {
        switch ([self bezelStyle]) {
        default:
        case NSTextFieldSquareBezel:
            [[control graphicsStyle] drawTextFieldBorderInRect: frame
                                                bezeledNotLine: YES];
            backRect = NSInsetRect(backRect, -1, -1);
            break;

        case NSTextFieldRoundedBezel:;
            CGContextRef context =
                    [[NSGraphicsContext currentContext] graphicsPort];
            NSRect roundedFrame = frame;

            roundedFrame.size.height--;
            [[NSColor darkGrayColor] setFill];
            drawRoundedBezel(context, roundedFrame);

            roundedFrame.origin.y += 1;
            [[NSColor lightGrayColor] setFill];
            drawRoundedBezel(context, roundedFrame);

            roundedFrame = NSInsetRect(roundedFrame, 1, 1);
            [[NSColor whiteColor] setFill];
            drawRoundedBezel(context, roundedFrame);
            break;
        }

    } else {
        if ([self isBordered]) {
            [[control graphicsStyle] drawTextFieldBorderInRect: frame
                                                bezeledNotLine: NO];
            backRect = NSInsetRect(backRect, -1, -1);
        }
    }

    if ([self drawsBackground]) {
        if (!([self isBezeled] &&
              [self bezelStyle] == NSTextFieldRoundedBezel)) {
            NSColor *color = (_backgroundColor == nil) ? [NSColor controlColor]
                                                       : _backgroundColor;

            [color setFill];
            NSRectFill(backRect);
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
