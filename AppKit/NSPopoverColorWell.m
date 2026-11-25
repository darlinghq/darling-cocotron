/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSPopoverColorWell.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorList.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSArray.h>

// The class hierarchy, and the controller's delegate, popover and topBarMatrixView properties,
// follow what macOS exposes (observed on macOS 26.7.3); the layout and the colors offered are
// Darling's own. Test: tests/appkit-popover-color-well.m.

static const CGFloat kSwatchBorder = 1;
static const CGFloat kMargin = 8;
static const NSUInteger kColumns = 12;

@interface NSObject (NSColorPickerMatrixViewDelegate)
- (void)_colorPickerMatrixView:(NSColorPickerMatrixView *)view didChooseColor:(NSColor *)color;
@end

@interface NSObject (NSColorPopoverControllerDelegate)
- (void)_colorPopoverController:(NSColorPopoverController *)controller didChooseColor:(NSColor *)color;
- (void)_colorPopoverControllerShowColorPanel:(NSColorPopoverController *)controller;
@end

@interface NSColorPopoverController ()
- (void)_tile;
@end

#pragma mark - NSColorPickerMatrixView

@implementation NSColorPickerMatrixView

@synthesize delegate = _delegate;

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil) {
        _numberOfColumns = kColumns;
        _swatchSize = NSMakeSize(13, 13);
        _selectedIndex = NSNotFound;
        _colors = [[NSArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_colorList release];
    [_colors release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)_sizeChanged
{
    [self setFrameSize:[self intrinsicContentSize]];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
    if ([_delegate respondsToSelector:@selector(_tile)])
        [_delegate _tile];
}

- (NSColorList *)colorList
{
    return _colorList;
}

- (void)setColorList:(NSColorList *)colorList
{
    if (colorList == _colorList)
        return;
    [_colorList release];
    _colorList = [colorList retain];

    NSMutableArray *colors = [NSMutableArray array];
    for (NSString *key in [colorList allKeys]) {
        NSColor *color = [colorList colorWithKey:key];
        if (color != nil)
            [colors addObject:color];
    }
    [_colors release];
    _colors = [colors copy];
    _selectedIndex = NSNotFound;
    [self _sizeChanged];
}

- (NSUInteger)numberOfColumns
{
    return _numberOfColumns;
}

- (void)setNumberOfColumns:(NSUInteger)columns
{
    _numberOfColumns = MAX(columns, (NSUInteger) 1);
    [self _sizeChanged];
}

- (NSSize)swatchSize
{
    return _swatchSize;
}

- (void)setSwatchSize:(NSSize)size
{
    _swatchSize = size;
    [self _sizeChanged];
}

- (NSUInteger)numberOfRows
{
    return ([_colors count] + _numberOfColumns - 1) / _numberOfColumns;
}

// Swatches sit side by side with a border between them and around them.
- (NSSize)intrinsicContentSize
{
    NSUInteger rows = [self numberOfRows];
    return NSMakeSize(_numberOfColumns * (_swatchSize.width + kSwatchBorder) + kSwatchBorder,
                      rows * (_swatchSize.height + kSwatchBorder) + (rows != 0 ? kSwatchBorder : 0));
}

- (NSColor *)colorAtIndex:(NSUInteger)index
{
    return index < [_colors count] ? [_colors objectAtIndex:index] : nil;
}

- (NSRect)rectForColorAtIndex:(NSUInteger)index
{
    if (index >= [_colors count])
        return NSZeroRect;
    NSUInteger column = index % _numberOfColumns, row = index / _numberOfColumns;
    return NSMakeRect(kSwatchBorder + column * (_swatchSize.width + kSwatchBorder),
                      kSwatchBorder + row * (_swatchSize.height + kSwatchBorder),
                      _swatchSize.width, _swatchSize.height);
}

- (NSUInteger)colorIndexAtPoint:(NSPoint)point
{
    for (NSUInteger i = 0; i < [_colors count]; i++) {
        if (NSPointInRect(point, [self rectForColorAtIndex:i]))
            return i;
    }
    return NSNotFound;
}

- (void)selectColorAtIndex:(NSUInteger)index
{
    _selectedIndex = index < [_colors count] ? (NSInteger) index : NSNotFound;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor gridColor] setFill];
    NSRectFill([self bounds]);
    for (NSUInteger i = 0; i < [_colors count]; i++)
        [[_colors objectAtIndex:i] drawSwatchInRect:[self rectForColorAtIndex:i]];
    if (_selectedIndex != NSNotFound) {
        [[NSColor selectedControlColor] setStroke];
        NSBezierPath *frame = [NSBezierPath bezierPathWithRect:NSInsetRect([self rectForColorAtIndex:_selectedIndex], -0.5, -0.5)];
        [frame setLineWidth:2];
        [frame stroke];
    }
}

// A click chooses the swatch the mouse is released over.
- (void)mouseDown:(NSEvent *)event
{
    NSEvent *current = event;
    while ([current type] != NSEventTypeLeftMouseUp) {
        NSUInteger index = [self colorIndexAtPoint:[self convertPoint:[current locationInWindow] fromView:nil]];
        [self selectColorAtIndex:index];
        current = [[self window] nextEventMatchingMask:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged];
    }
    NSUInteger index = [self colorIndexAtPoint:[self convertPoint:[current locationInWindow] fromView:nil]];
    [self selectColorAtIndex:index];
    if (index != NSNotFound && [_delegate respondsToSelector:@selector(_colorPickerMatrixView:didChooseColor:)])
        [_delegate _colorPickerMatrixView:self didChooseColor:[self colorAtIndex:index]];
}

@end

#pragma mark - NSColorPopoverController

// A row of plain colors for the top bar.
static NSColorList *topBarColors(void)
{
    NSColorList *list = [[[NSColorList alloc] initWithName:@"_NSColorPopoverTopBar"] autorelease];
    NSArray *colors = @[
        [NSColor blackColor], [NSColor darkGrayColor], [NSColor grayColor], [NSColor lightGrayColor],
        [NSColor whiteColor], [NSColor redColor], [NSColor orangeColor], [NSColor yellowColor],
        [NSColor greenColor], [NSColor cyanColor], [NSColor blueColor], [NSColor purpleColor],
    ];
    for (NSUInteger i = 0; i < [colors count]; i++)
        [list insertColor:[colors objectAtIndex:i] key:[NSString stringWithFormat:@"%lu", (unsigned long) i] atIndex:i];
    return list;
}

// A grid of hues across, from light to dark down, after a row of grays.
static NSColorList *gridColors(void)
{
    NSColorList *list = [[[NSColorList alloc] initWithName:@"_NSColorPopoverGrid"] autorelease];
    NSUInteger index = 0;
    for (NSUInteger column = 0; column < kColumns; column++) {
        CGFloat white = 1.0 - (CGFloat) column / (kColumns - 1);
        [list insertColor:[NSColor colorWithCalibratedWhite:white alpha:1] key:[NSString stringWithFormat:@"%lu", (unsigned long) index] atIndex:index];
        index++;
    }
    static const CGFloat saturation[] = { 0.25, 0.5, 0.75, 1.0, 1.0, 1.0, 1.0 };
    static const CGFloat brightness[] = { 1.0, 1.0, 1.0, 1.0, 0.75, 0.5, 0.3 };
    for (NSUInteger row = 0; row < sizeof saturation / sizeof saturation[0]; row++) {
        for (NSUInteger column = 0; column < kColumns; column++) {
            NSColor *color = [NSColor colorWithCalibratedHue:(CGFloat) column / kColumns saturation:saturation[row]
                                                   brightness:brightness[row] alpha:1];
            [list insertColor:color key:[NSString stringWithFormat:@"%lu", (unsigned long) index] atIndex:index];
            index++;
        }
    }
    return list;
}

@implementation NSColorPopoverController

@synthesize delegate = _delegate;
@synthesize popover = _popover;
@synthesize topBarMatrixView = _topBarMatrixView;

- (void)dealloc
{
    [_matrixView release];
    [_showColorsButton release];
    [super dealloc];
}

- (void)loadView
{
    NSView *view = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];

    NSColorPickerMatrixView *topBar = [[[NSColorPickerMatrixView alloc] initWithFrame:NSZeroRect] autorelease];
    [topBar setColorList:topBarColors()];
    [topBar setDelegate:self];
    [view addSubview:topBar];
    _topBarMatrixView = topBar;

    _matrixView = [[NSColorPickerMatrixView alloc] initWithFrame:NSZeroRect];
    [_matrixView setColorList:gridColors()];
    [_matrixView setDelegate:self];
    [view addSubview:_matrixView];

    _showColorsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [_showColorsButton setTitle:@"Show Colors…"];
    [_showColorsButton setBezelStyle:NSBezelStyleRounded];
    [_showColorsButton setTarget:self];
    [_showColorsButton setAction:@selector(_showColors:)];
    [_showColorsButton sizeToFit];
    [view addSubview:_showColorsButton];

    [self setView:view];
    [self _tile];
}

// Stacks the bar, the grid and the button, and sizes the view (and so the popover) to them.
- (void)_tile
{
    if (![self isViewLoaded])
        return;
    NSSize bar = [_topBarMatrixView intrinsicContentSize], grid = [_matrixView intrinsicContentSize];
    NSSize button = [_showColorsButton frame].size;
    CGFloat width = MAX(MAX(bar.width, grid.width), button.width) + 2 * kMargin;
    CGFloat height = kMargin + bar.height + kMargin + grid.height + kMargin + button.height + kMargin;

    // the view is not flipped: lay out from the top down
    CGFloat y = height - kMargin - bar.height;
    [_topBarMatrixView setFrame:NSMakeRect(floor((width - bar.width) / 2), y, bar.width, bar.height)];
    y -= kMargin + grid.height;
    [_matrixView setFrame:NSMakeRect(floor((width - grid.width) / 2), y, grid.width, grid.height)];
    y -= kMargin + button.height;
    [_showColorsButton setFrame:NSMakeRect(width - kMargin - button.width, y, button.width, button.height)];
    [[self view] setFrameSize:NSMakeSize(width, height)];
    [self setPreferredContentSize:NSMakeSize(width, height)];
}

- (void)_colorPickerMatrixView:(NSColorPickerMatrixView *)view didChooseColor:(NSColor *)color
{
    NSColorPickerMatrixView *other = view == _topBarMatrixView ? _matrixView : _topBarMatrixView;
    [other selectColorAtIndex:NSNotFound];
    if ([_delegate respondsToSelector:@selector(_colorPopoverController:didChooseColor:)])
        [_delegate _colorPopoverController:self didChooseColor:color];
}

- (void)_showColors:(id)sender
{
    if ([_delegate respondsToSelector:@selector(_colorPopoverControllerShowColorPanel:)])
        [_delegate _colorPopoverControllerShowColorPanel:self];
}

@end

#pragma mark - NSPopoverColorWell

@implementation NSPopoverColorWell

- (void)dealloc
{
    if ([_popover delegate] == (id) self)
        [_popover setDelegate:nil];
    [_popover release];
    [super dealloc];
}

- (BOOL)_activationShowsColorPanel
{
    return NO;
}

- (NSPopover *)_colorPopover
{
    if (_popover == nil) {
        _popover = [[NSPopover alloc] init];
        [_popover setBehavior:NSPopoverBehaviorTransient];
        NSColorPopoverController *controller = [[[NSColorPopoverController alloc] init] autorelease];
        [_popover setContentViewController:controller];
        [controller setPopover:_popover];
    }
    return _popover;
}

- (void)_showPopover
{
    NSPopover *popover = [self _colorPopover];
    NSColorPopoverController *controller = (NSColorPopoverController *) [popover contentViewController];
    [popover setDelegate:self];
    [controller setDelegate:self];
    NSColorWell *owner = [NSColorWell _exclusiveColorPanelOwner];
    if (owner != nil && owner != self)
        [owner deactivate];
    [self activate:YES];
    [popover showRelativeToRect:[self bounds] ofView:self preferredEdge:NSMinYEdge];
}

- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    if ([self isActive])
        [self deactivate];
    else
        [self _showPopover];
}

// A color chosen in the popover becomes the well's color, and the popover closes.
- (void)_colorPopoverController:(NSColorPopoverController *)controller didChooseColor:(NSColor *)color
{
    [self setColor:color];
    [[NSColorPanel sharedColorPanel] setColor:color];
    [self sendAction:[self action] to:[self target]];
    [[controller popover] close];
}

// The color panel replaces the popover; the well stays active, so the panel's color changes
// reach it.
- (void)_colorPopoverControllerShowColorPanel:(NSColorPopoverController *)controller
{
    [[controller popover] close];
    if (![self isActive])
        [self activate:YES];
    [NSApp orderFrontColorPanel:self];
}

// Closing the popover ends the choice, unless the color panel took over.
- (void)popoverDidClose:(NSNotification *)notification
{
    if (![[NSColorPanel sharedColorPanel] isVisible])
        [self deactivate];
}

@end
