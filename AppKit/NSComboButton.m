/* Copyright (c) 2026 Darling Developers

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

#import <AppKit/NSComboButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <Foundation/NSString.h>

// The width of the part of a split button that shows the menu.
static const CGFloat kMenuSegmentWidth = 20.0;

@implementation NSComboButton

+ (Class) cellClass
{
    return [NSButtonCell class];
}

- (instancetype) initWithFrame: (NSRect) frame
{
    self = [super initWithFrame: frame];
    if (self == nil)
        return nil;

    NSButtonCell *cell = [[NSButtonCell alloc] initTextCell: @""];
    [cell setBezelStyle: NSBezelStyleRounded];
    [cell setButtonType: NSButtonTypeMomentaryPushIn];
    [cell setImageScaling: NSImageScaleProportionallyDown];
    [self setCell: cell];
    [cell release];
    _comboStyle = NSComboButtonStyleSplit;
    _comboMenu = [[NSMenu alloc] initWithTitle: @""];
    return self;
}

+ (instancetype) comboButtonWithTitle: (NSString *) title
                                 menu: (NSMenu *) menu
                               target: (id) target
                               action: (SEL) action
{
    NSComboButton *button = [[[self alloc] initWithFrame: NSMakeRect(0, 0, 80, 24)] autorelease];
    [button setTitle: title];
    if (menu != nil)
        [button setMenu: menu];
    [button setTarget: target];
    [button setAction: action];
    return button;
}

+ (instancetype) comboButtonWithImage: (NSImage *) image
                                 menu: (NSMenu *) menu
                               target: (id) target
                               action: (SEL) action
{
    NSComboButton *button = [[[self alloc] initWithFrame: NSMakeRect(0, 0, 42, 24)] autorelease];
    [button setImage: image];
    if (menu != nil)
        [button setMenu: menu];
    [button setTarget: target];
    [button setAction: action];
    return button;
}

+ (instancetype) comboButtonWithTitle: (NSString *) title
                                image: (NSImage *) image
                                 menu: (NSMenu *) menu
                               target: (id) target
                               action: (SEL) action
{
    NSComboButton *button = [self comboButtonWithTitle: title
                                                  menu: menu
                                                target: target
                                                action: action];
    [button setImage: image];
    return button;
}

- (void) dealloc
{
    [_comboMenu release];
    [super dealloc];
}

- (NSString *) title
{
    return [[self cell] title];
}

- (void) setTitle: (NSString *) title
{
    [[self cell] setTitle: title != nil ? title : @""];
    [self setNeedsDisplay: YES];
}

- (NSImage *) image
{
    return [[self cell] image];
}

- (void) setImage: (NSImage *) image
{
    [[self cell] setImage: image];
    [self setNeedsDisplay: YES];
}

- (NSImageScaling) imageScaling
{
    return [[self cell] imageScaling];
}

- (void) setImageScaling: (NSImageScaling) scaling
{
    [[self cell] setImageScaling: scaling];
    [self setNeedsDisplay: YES];
}

- (NSMenu *) menu
{
    return _comboMenu;
}

- (void) setMenu: (NSMenu *) menu
{
    [menu retain];
    [_comboMenu release];
    _comboMenu = menu;
}

- (NSComboButtonStyle) style
{
    return _comboStyle;
}

- (void) setStyle: (NSComboButtonStyle) style
{
    _comboStyle = style;
    [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) rect
{
    [super drawRect: rect];

    // The disclosure triangle of the menu part.
    NSRect bounds = [self bounds];
    NSRect segment = NSMakeRect(NSMaxX(bounds) - kMenuSegmentWidth, NSMinY(bounds),
                                kMenuSegmentWidth, NSHeight(bounds));
    NSBezierPath *triangle = [NSBezierPath bezierPath];
    CGFloat midX = NSMidX(segment), midY = NSMidY(segment);
    [triangle moveToPoint: NSMakePoint(midX - 3.5, midY + 1.5)];
    [triangle lineToPoint: NSMakePoint(midX + 3.5, midY + 1.5)];
    [triangle lineToPoint: NSMakePoint(midX, midY - 2.5)];
    [triangle closePath];
    [([self isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]) set];
    [triangle fill];
}

// The unified style shows the menu wherever it is clicked; the split style only in its menu part.
- (void) mouseDown: (NSEvent *) event
{
    if (![self isEnabled])
        return;

    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    BOOL inMenuPart = point.x >= NSMaxX([self bounds]) - kMenuSegmentWidth;
    if ((_comboStyle == NSComboButtonStyleUnified || inMenuPart) && [_comboMenu numberOfItems] > 0) {
        [NSMenu popUpContextMenu: _comboMenu withEvent: event forView: self];
        return;
    }
    [super mouseDown: event];
}

@end
