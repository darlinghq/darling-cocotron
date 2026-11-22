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
#import <AppKit/NSApplication.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBox.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSTextFieldCell.h>
#import <Foundation/NSKeyedArchiver.h>

@implementation NSBox

// The custom box properties, which a box keeps whatever its type. The defaults are those of
// macOS 10.14.4 and 26.7.3: a one point border in the secondary label color, no corner radius,
// and a clear fill.
- (NSMutableDictionary *) _customBoxProperties {
    if (NS_EXTRA(NSBox, self)->_customData == nil)
        NS_EXTRA(NSBox, self)->_customData = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                [NSNumber numberWithDouble: 1], @"NSBorderWidth2",
                [NSNumber numberWithDouble: 0], @"NSCornerRadius2",
                [NSColor secondaryLabelColor], @"NSBorderColor2",
                [NSColor colorWithCalibratedWhite: 0 alpha: 0], @"NSFillColor2", nil];
    return NS_EXTRA(NSBox, self)->_customData;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [super encodeWithCoder: coder];
    [coder encodeInt: NS_EXTRA(NSBox, self)->_borderType forKey: @"NSBox borderType"];
    [coder encodeInt: NS_EXTRA(NSBox, self)->_titlePosition forKey: @"NSBox titlePosition"];
    [coder encodeSize: _contentViewMargins forKey: @"NSBox contentViewMargins"];
    [coder encodeObject: _titleCell forKey: @"NSBox titleCell"];
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        NS_EXTRA(NSBox, self)->_boxType = [keyed decodeIntForKey: @"NSBoxType"];
        NS_EXTRA(NSBox, self)->_borderType = [keyed decodeIntForKey: @"NSBorderType"];
        NS_EXTRA(NSBox, self)->_titlePosition = [keyed decodeIntForKey: @"NSTitlePosition"];
        _contentViewMargins = [keyed decodeSizeForKey: @"NSOffsets"];
        _titleCell = [[keyed decodeObjectForKey: @"NSTitleCell"] retain];
        // There is a key NSTransparent, but as far as I can tell it is always
        // NO
        NS_EXTRA(NSBox, self)->_isTransparent = [keyed decodeBoolForKey: @"NSFullyTransparent"];

        [[_subviews lastObject]
                setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        [[_subviews lastObject] setAutoresizesSubviews: YES];

        for (NSString *key in @[ @"NSBorderWidth2", @"NSCornerRadius2", @"NSBorderColor2", @"NSFillColor2" ]) {
            id value = [keyed decodeObjectForKey: key];

            if (value != nil)
                [[self _customBoxProperties] setObject: value forKey: key];
        }
    } else {
        NSInteger version = [coder versionForClassName: @"NSBox"];
        float width = 0, height = 0;
        NSView *contentView = nil;
        char flags = 0, titlePosition = 0, unknownFlag = 0;

        // Layouts per class version as recorded; the groups of the decode calls have to
        // be the same as the archiver wrote.
        if (version <= 16) {
            short unknownShort = 0;

            [coder decodeValuesOfObjCTypes: "ff", &width, &height];
            [coder decodeValuesOfObjCTypes: "@@s", &_titleCell, &contentView, &unknownShort];
            // The short is of unknown meaning; changing it alters no accessor of the box.
        } else if (version <= 40) {
            [coder decodeValuesOfObjCTypes: "ff", &width, &height];
            _titleCell = [[coder decodeObject] retain];
            contentView = [[coder decodeObject] retain];
            [coder decodeValuesOfObjCTypes: "c", &flags];
            [coder decodeValuesOfObjCTypes: "c", &titlePosition];
            [coder decodeValuesOfObjCTypes: "c", &unknownFlag];
            if (version >= 25) {
                // One more object of unknown meaning.
                [coder decodeObject];
            }
        } else {
            [coder decodeValuesOfObjCTypes: "ff@@ccc", &width, &height, &_titleCell, &contentView, &flags, &titlePosition,
                                            &unknownFlag];
            // One more object of unknown meaning.
            [coder decodeObject];
        }

        // The content view is already a subview from NSView decoding.
        [contentView release];

        // The first flag byte holds the border type in its low two bits and, from version
        // 42, the box type in the two above them (earlier versions have no box type).
        NS_EXTRA(NSBox, self)->_borderType = flags & 3;
        NS_EXTRA(NSBox, self)->_boxType = version >= 42 ? (flags >> 2) & 3 : NSBoxPrimary;
        NS_EXTRA(NSBox, self)->_titlePosition = titlePosition;
        _contentViewMargins = CGSizeMake(width, height);
        // The third byte is of unknown meaning (it sets a transparent-background bit that
        // no public accessor of the box reports).
    }
    return self;
}

- initWithFrame: (NSRect) frame {
    NSView *contentview;

    [super initWithFrame: frame];

    // QUIRK: a new box is not transparent, has a groove border and its title at the top, and its content
    // view is inset 8 points from the left, right and bottom and 15 from the top of the view. Documented
    // for the first three; the content view frame was observed on macOS 10.14.4 (tier 2), for a 200 x 100
    // box, as (8, 8, 184, 77). Test: appkit-box-aqua.m
    NS_EXTRA(NSBox, self)->_isTransparent = NO;
    _titleCell = [[NSTextFieldCell alloc] initTextCell: @""];
    // QUIRK: the title of a new box is drawn in the 11 point system font (the small system font size), not
    // the 13 point font of a text field cell; the title rect of a box titled "Title" is 14 points high.
    // Evidence: black-box observation on macOS 10.14.4 (tier 2) of -[NSBox titleFont] and -titleRect.
    // Test: appkit-box-aqua.m
    [_titleCell setFont: [NSFont systemFontOfSize: 11]];
    NS_EXTRA(NSBox, self)->_borderType = NSGrooveBorder;
    NS_EXTRA(NSBox, self)->_titlePosition = NSAtTop;
    _contentViewMargins = NSMakeSize(5, 5);

    contentview = [[NSView alloc]
            initWithFrame: NSMakeRect(8, 8, MAX(0, NSWidth(frame) - 16), MAX(0, NSHeight(frame) - 23))];
    [contentview setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [self addSubview: contentview];
    [contentview release];
    [self setAutoresizesSubviews: YES];
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSBox, self)->_customData release];
    [_titleCell release];
    NS_EXTRA_FREE(NSBox, self);
    [super dealloc];
}

- (NSBoxType) boxType {
    return NS_EXTRA(NSBox, self)->_boxType;
}

- (NSBorderType) borderType {
    return NS_EXTRA(NSBox, self)->_borderType;
}

- (NSString *) title {
    return [_titleCell stringValue];
}

- (NSFont *) titleFont {
    return [_titleCell font];
}

- contentView {
    return [[self subviews] lastObject];
}

- (NSSize) contentViewMargins {
    return _contentViewMargins;
}

- (NSTitlePosition) titlePosition {
    return NS_EXTRA(NSBox, self)->_titlePosition;
}

- (BOOL) isTransparent {
    return NS_EXTRA(NSBox, self)->_isTransparent;
}

- (void) setBoxType: (NSBoxType) value {
    NS_EXTRA(NSBox, self)->_boxType = value;
    [self setNeedsDisplay: YES];
}

- (void) setBorderType: (NSBorderType) value {
    NS_EXTRA(NSBox, self)->_borderType = value;
    [self setNeedsDisplay: YES];
}

- (void) setTitle: (NSString *) title {
    [_titleCell setStringValue: title];
    [self setNeedsDisplay: YES];
}

- (void) setTitleFont: (NSFont *) font {
    [_titleCell setFont: font];
}

- (void) setContentView: (NSView *) view {
    if (![[self subviews] containsObject: view]) {
        [[self subviews]
                makeObjectsPerformSelector: @selector(removeFromSuperview)];
        // FIX, adjust size
        [self addSubview: view];
    }
}

- (void) setContentViewMargins: (NSSize) value {
    _contentViewMargins = value;
    [self setNeedsDisplay: YES];
}

- (void) setTitlePosition: (NSTitlePosition) value {
    NS_EXTRA(NSBox, self)->_titlePosition = value;
    [self setNeedsDisplay: YES];
}

- (void) setTransparent: (BOOL) value {
    NS_EXTRA(NSBox, self)->_isTransparent = value;
    [self setNeedsDisplay: YES];
}

- (void) setTitleWithMnemonic: (NSString *) value {
    NSUnimplementedMethod();
}

- (NSAttributedString *) _attributedTitle {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSMutableParagraphStyle *paraStyle =
            [[[NSParagraphStyle defaultParagraphStyle] mutableCopy]
                    autorelease];
    NSFont *font = [_titleCell font];

    if (font != nil)
        [attributes setObject: font forKey: NSFontAttributeName];

    [paraStyle setLineBreakMode: NSLineBreakByClipping];
    [paraStyle setAlignment: NSLeftTextAlignment];
    [attributes setObject: paraStyle forKey: NSParagraphStyleAttributeName];

    [attributes setObject: [NSColor controlTextColor]
                   forKey: NSForegroundColorAttributeName];

    [attributes setObject: [NSColor windowBackgroundColor]
                   forKey: NSBackgroundColorAttributeName];

    return [[[NSAttributedString alloc] initWithString: [_titleCell stringValue]
                                            attributes: attributes]
            autorelease];
}

#define TEXTGAP 4

- (NSRect) titleRect {
    // Obtain the size the title cell prefers
    NSSize size = [_titleCell cellSize];
    NSRect bounds = [self bounds];
    NSRect result = NSZeroRect;

    result.origin.x = 10 + TEXTGAP;
    result.size.height = ceil(size.height);

    // result.size.width=ceil(size.width); // // NSTextField cell must be bugged
    // we get too low values for the width here
    result.size.width = bounds.size.width -
                        result.origin.x; // use the whole width until the text
                                         // field cell size is fixed

    switch (NS_EXTRA(NSBox, self)->_titlePosition) {

    case NSNoTitle:
        break;

    case NSAboveTop:
        result.origin.y = bounds.size.height - result.size.height;
        break;

    case NSAtTop:
        result.origin.y = bounds.size.height - result.size.height;
        break;

    case NSBelowTop:
        result.origin.y = bounds.size.height - (result.size.height + TEXTGAP);
        break;

    case NSAboveBottom:
        result.origin.y = TEXTGAP;
        break;

    case NSAtBottom:
        break;

    case NSBelowBottom:
        result.origin.y = 0;
        break;
    }

    return result;
}

- (NSRect) borderRect {
    NSUnimplementedMethod();
    return NSMakeRect(0, 0, 0, 0);
}

- titleCell {
    return _titleCell;
}

- (void) setFrameFromContentFrame: (NSRect) content {
    // FIX, adjust content frame size to accomodate border/title
    [self setFrame: content];
}

// The content view is made to enclose its subviews (by its own -sizeToFit when it has one), then the
// box is resized around it, keeping the space it had between its edges and the content view.
- (void) sizeToFit {
    NSView *content = [self contentView];
    if (content == nil)
        return;

    NSRect bounds = [self bounds];
    NSRect contentFrame = [content frame];
    CGFloat left = NSMinX(contentFrame), bottom = NSMinY(contentFrame);
    CGFloat right = NSWidth(bounds) - NSMaxX(contentFrame), top = NSHeight(bounds) - NSMaxY(contentFrame);

    // The frames below are set one by one; no view is to be resized by autoresizing meanwhile.
    BOOL boxAutoresizes = [self autoresizesSubviews], contentAutoresizes = [content autoresizesSubviews];
    [self setAutoresizesSubviews: NO];
    [content setAutoresizesSubviews: NO];

    NSPoint originShift = NSZeroPoint;
    if ([content respondsToSelector: @selector(sizeToFit)]) {
        [content performSelector: @selector(sizeToFit)];
    } else {
        // The content view takes the size of the union of its subviews' frames (a hidden subview counts
        // too) and the subviews are shifted so the union starts at its origin. The box moves by the same
        // offset, so the subviews stay where they were on screen. A content view without subviews
        // becomes empty (zero size), and the box then wraps only the margins and the title.
        // Observed by black-box test on macOS 26.7.3 and 10.14.4; the test below pins the geometry.
        NSRect enclosing = NSZeroRect;
        BOOL first = YES;
        for (NSView *subview in [content subviews]) {
            enclosing = first ? [subview frame] : NSUnionRect(enclosing, [subview frame]);
            first = NO;
        }
        for (NSView *subview in [content subviews])
            [subview setFrameOrigin: NSMakePoint(NSMinX([subview frame]) - NSMinX(enclosing),
                                                 NSMinY([subview frame]) - NSMinY(enclosing))];
        originShift = first ? NSZeroPoint : enclosing.origin;
        [content setFrameSize: enclosing.size];
    }

    NSSize size = NSMakeSize(left + NSWidth([content frame]) + right, bottom + NSHeight([content frame]) + top);
    if (NS_EXTRA(NSBox, self)->_titlePosition != NSNoTitle && [[self title] length] > 0) {
        // The box is at least as wide as the title cell plus 10 points on either side.
        size.width = MAX(size.width, [_titleCell cellSize].width + 20);
    }

    NSPoint origin = [self frame].origin;
    [self setFrameOrigin: NSMakePoint(origin.x + originShift.x, origin.y + originShift.y)];
    [self setFrameSize: size];
    [content setFrame: NSMakeRect(left, bottom, floor(size.width - left - right), size.height - bottom - top)];
    [content setAutoresizesSubviews: contentAutoresizes];
    [self setAutoresizesSubviews: boxAutoresizes];
    [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) rect {
    NSRect grooveRect = _bounds;
    NSRect titleRect = [self titleRect];
    BOOL drawTitle = YES;

    if ([self isTransparent])
        return;

    switch (NS_EXTRA(NSBox, self)->_titlePosition) {

    case NSNoTitle:
        drawTitle = NO;
        break;

    case NSAboveTop:
        grooveRect.size.height -= titleRect.size.height + TEXTGAP;
        break;

    case NSAtTop:
        grooveRect.size.height -= floor(titleRect.size.height / 2);
        break;

    case NSBelowTop:
        break;

    case NSAboveBottom:
        break;

    case NSAtBottom:
        grooveRect.origin.y += floor(titleRect.size.height / 2);
        grooveRect.size.height -= floor(titleRect.size.height / 2);
        break;

    case NSBelowBottom:
        grooveRect.origin.y += titleRect.size.height + TEXTGAP;
        grooveRect.size.height -= titleRect.size.height + TEXTGAP;
        break;
    }

    BOOL aqua = NS_EXTRA(NSBox, self)->_boxType == NSBoxPrimary || NS_EXTRA(NSBox, self)->_boxType == NSBoxSecondary;

    if (aqua) {
        // QUIRK: the box of a titled primary or secondary box starts below the title and is inset 3 points
        // from the sides and 4 from the bottom; without a title it is inset 3 points from the sides and
        // 4 from the top and bottom. Evidence: black-box renders on macOS 10.14.4 (tier 2).
        // Test: appkit-box-aqua.m
        grooveRect = NSInsetRect(_bounds, 3, 4);
        if (drawTitle && NS_EXTRA(NSBox, self)->_titlePosition == NSAtTop) {
            CGFloat above = floor(titleRect.size.height);

            grooveRect.size.height = NSHeight(_bounds) - 4 - above;
            grooveRect.origin.y = 4;
        }
        [[self graphicsStyle] drawAquaBoxInRect: grooveRect];
    } else if (NS_EXTRA(NSBox, self)->_boxType != NSBoxSeparator && NS_EXTRA(NSBox, self)->_boxType != NSBoxCustom) {
        // Separator are transparent except for drawing a line
        [[NSColor controlColor] setFill];
        NSRectFill(grooveRect);
    }

    if (NS_EXTRA(NSBox, self)->_boxType == NSBoxCustom) {
        // The fill is drawn over what is behind the box, so a clear fill color (the default)
        // leaves it showing.
        CGFloat radius = [self cornerRadius];

        [[self fillColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect: _bounds xRadius: radius yRadius: radius] fill];

        if (NS_EXTRA(NSBox, self)->_borderType != NSNoBorder) {
            [[self borderColor] set];
            NSFrameRectWithWidth(_bounds, [self borderWidth]);
        }
    } else if (NS_EXTRA(NSBox, self)->_boxType == NSBoxSeparator) {
        // These are just the simple divider lines
        [[NSColor grayColor] set];
        NSBezierPath *line = [NSBezierPath bezierPath];
        if (NSWidth(grooveRect) > NSHeight(grooveRect)) {
            [line moveToPoint: NSMakePoint(NSMinX(grooveRect),
                                           NSMidY(grooveRect))];
            [line lineToPoint: NSMakePoint(NSMaxX(grooveRect),
                                           NSMidY(grooveRect))];
        } else {
            [line moveToPoint: NSMakePoint(NSMidX(grooveRect),
                                           NSMinY(grooveRect))];
            [line lineToPoint: NSMakePoint(NSMidX(grooveRect),
                                           NSMaxY(grooveRect))];
        }
        [line stroke];
    } else if (!aqua) {
        switch (NS_EXTRA(NSBox, self)->_borderType) {
        case NSNoBorder:
            break;

        case NSLineBorder:
            [[self graphicsStyle] drawBoxWithLineInRect: grooveRect];
            break;

        case NSBezelBorder:
            [[self graphicsStyle] drawBoxWithBezelInRect: grooveRect
                                                clipRect: rect];
            break;

        case NSGrooveBorder:
            [[self graphicsStyle] drawBoxWithGrooveInRect: grooveRect
                                                 clipRect: rect];
            break;
        }
    }
    if (drawTitle) {
#if 0
    [[NSColor windowBackgroundColor] setFill];
    titleRect.origin.x-=TEXTGAP;
    titleRect.size.width+=TEXTGAP*2;
    NSRectFill(titleRect);
#endif
        titleRect.origin.x += TEXTGAP;

        // Ask the cell to draw itself now
        // TODO: Should we be doing some sort of clipping setup here?
        [_titleCell setControlView: self];
        [_titleCell drawWithFrame: titleRect inView: self];
    }
}

- (CGFloat) borderWidth {
    return [[[self _customBoxProperties] objectForKey: @"NSBorderWidth2"] doubleValue];
}

- (CGFloat) cornerRadius; {
    return [[[self _customBoxProperties] objectForKey: @"NSCornerRadius2"] doubleValue];
}

- (NSColor *) borderColor; {
    return [[self _customBoxProperties] objectForKey: @"NSBorderColor2"];
}

- (NSColor *) fillColor; {
    return [[self _customBoxProperties] objectForKey: @"NSFillColor2"];
}

- (void) setBorderWidth: (CGFloat) value {
    [[self _customBoxProperties] setObject: [NSNumber numberWithDouble: value] forKey: @"NSBorderWidth2"];
    [self setNeedsDisplay: YES];
}

- (void) setCornerRadius: (CGFloat) value {
    [[self _customBoxProperties] setObject: [NSNumber numberWithDouble: value] forKey: @"NSCornerRadius2"];
    [self setNeedsDisplay: YES];
}

- (void) setBorderColor: (NSColor *) value {
    if (value != nil)
        [[self _customBoxProperties] setObject: value forKey: @"NSBorderColor2"];
    [self setNeedsDisplay: YES];
}

- (void) setFillColor: (NSColor *) value {
    if (value != nil)
        [[self _customBoxProperties] setObject: value forKey: @"NSFillColor2"];
    [self setNeedsDisplay: YES];
}

- (void) updateCell: (NSCell *) cell {
    [self setNeedsDisplay: YES];
}

@end
