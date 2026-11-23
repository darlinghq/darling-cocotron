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
#import <AppKit/NSButton.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMainMenuView.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSThemeFrame.h>
#import <AppKit/NSToolbarView.h>
#import <AppKit/NSWindow-Private.h>
#import <AppKit/NSWindow.h>

@interface NSWindow (private)
- (BOOL) hasMainMenu;
+ (BOOL) hasMainMenuForStyleMask: (NSUInteger) styleMask;
@end

@implementation NSThemeFrame

- (BOOL) isOpaque {
    return YES;
}

- (NSWindowBorderType) windowBorderType {
    return _borderType;
}

- (void) setWindowBorderType: (NSWindowBorderType) borderType {
    _borderType = borderType;
    [self setNeedsDisplay: YES];
}

- (NSColor *) _borderColorForNSShowAllViews {
    return [NSColor yellowColor];
}

- (void) drawRect: (NSRect) rect {
    NSRect bounds = [self bounds];
    CGFloat cheatSheet = 0;

    [[[self window] backgroundColor] setFill];
    NSRectFill(bounds);

    switch (_borderType) {
    case NSNoBorder:
        break;

    case NSWindowToolTipBorderType:
        [[NSColor blackColor] setStroke];
        NSFrameRect(bounds);
        bounds = NSInsetRect(bounds, 1, 1);
        cheatSheet = 1;
        break;

    case NSWindowSheetBorderType:
        NSDrawButton(bounds, bounds);
        bounds = NSInsetRect(bounds, 2, 2);
        cheatSheet = 2;
        break;
    }

    if ([[self window] isSheet])
        bounds.size.height += cheatSheet;

    [[[self window] backgroundColor] setFill];
    NSRectFill([[[self window] contentView] frame]);
}

- (void) resizeSubviewsWithOldSize: (NSSize) oldSize {
    NSView *menuView = nil;
    NSToolbarView *toolbarView = nil;
    // The subview that holds the window's content view, which may be the
    // content view itself or a view wrapping it. Other subviews added to the
    // frame view are not the content, even when they come last.
    NSView *contentView = [[self window] contentView];
    while (contentView != nil && [contentView superview] != nil &&
           [contentView superview] != self)
        contentView = [contentView superview];
    if ([contentView superview] != self)
        contentView = nil;

    // tile the subviews, when/if we add titlebars and such do it here
    for (NSView *view in _subviews) {
        if ([view isKindOfClass: [NSMenuView class]])
            menuView = view;
        else if ([view isKindOfClass: [NSToolbarView class]])
            toolbarView = (NSToolbarView *) view;
    }

    // Any other subview follows its own autoresizing mask.
    for (NSView *view in [[_subviews copy] autorelease])
        if (view != contentView && view != menuView && view != toolbarView)
            [view resizeWithOldSuperviewSize: oldSize];

    // subtracts menu height but not toolbar height
    NSRect contentFrame = [[[self window] class]
            contentRectForFrameRect: [self bounds]
                          styleMask: [[self window] styleMask]];

    // If the class thinks there is a menu but the instance does not want an
    // instance we need to add the menu height back to the content view as
    // contentRectForFrameRect subtracts it

    if ([[[self window] class]
                hasMainMenuForStyleMask: [[self window] styleMask]]) {
        if (![[self window] hasMainMenu])
            contentFrame.size.height += [NSMainMenuView menuHeight];
    }

    NSRect menuFrame = (menuView != nil) ? [menuView frame] : NSZeroRect;
    NSRect toolbarFrame =
            (toolbarView != nil) ? [toolbarView frame] : NSZeroRect;

    menuFrame.origin.y = NSMaxY(contentFrame);
    menuFrame.origin.x = contentFrame.origin.x;
    menuFrame.size.width = contentFrame.size.width;
    [menuView setFrame: menuFrame];

    toolbarFrame.origin.y = NSMaxY(contentFrame) - toolbarFrame.size.height;
    toolbarFrame.origin.x = contentFrame.origin.x;
    toolbarFrame.size.width = contentFrame.size.width;

    [toolbarView setFrame: toolbarFrame];
    [toolbarView layoutViews];

    // A hidden toolbar takes no room
    if (toolbarView != nil && ![toolbarView isHidden])
        contentFrame.size.height -= toolbarFrame.size.height;
    [contentView setFrame: contentFrame];
}

// The standard buttons go at the top left of the title bar area, 7, 27 and 47
// points from the left edge and 3 points below the top, as on Mac OS X
// 10.14.4 (black-box: -[NSButton frame] of the window's buttons in window
// coordinates; macOS 26.7.3 puts its 14 point buttons at 9, 32 and 55, 9
// points below the top).
static NSRect standardButtonFrame(NSWindowButton kind, NSRect bounds) {
    return NSMakeRect(NSMinX(bounds) + 7 + 20 * kind, NSMaxY(bounds) - 3 - 16, 14, 16);
}

- (void) _updateStandardWindowButtons {
    NSWindow *window = [self window];
    if (window == nil)
        return;
    BOOL shown = [window _hasInvisibleTitlebarForStyleMask: [window styleMask]];

    for (NSWindowButton kind = NSWindowCloseButton; kind <= NSWindowZoomButton; kind++) {
        NSButton *button = [window standardWindowButton: kind];
        if (button == nil)
            continue;
        if (!shown) {
            if ([button superview] == self)
                [button removeFromSuperview];
        } else if ([button superview] == nil) {
            // Placed once: the application may move them afterwards.
            [button setFrame: standardButtonFrame(kind, [self bounds])];
            [button setAutoresizingMask: NSViewMaxXMargin | NSViewMinYMargin];
            [self addSubview: button positioned: NSWindowAbove relativeTo: nil];
        }
    }
}

// The buttons stay in front of the content, also of a content view set after
// they were shown.
- (void) didAddSubview: (NSView *) subview {
    [super didAddSubview: subview];

    Class buttonClass = NSClassFromString(@"NSStandardWindowButton");
    if ([subview isKindOfClass: buttonClass])
        return;
    for (NSView *view in [[_subviews copy] autorelease])
        if ([view isKindOfClass: buttonClass])
            [self addSubview: view positioned: NSWindowAbove relativeTo: nil];
}

// Height of the title bar of a titled window: 22 points on macOS 10.14
// (32 on macOS 26). Measured as the difference between the frame and the
// content rect of a titled window (+frameRectForContentRect:styleMask:) on
// macOS 10.14.4 and 26.7.3.
static const CGFloat NSThemeFrameTitlebarHeight = 22;

// Whether a press that reached the frame view moves the window. That is a
// press on the window background, or on a view that does not handle it and
// lets the window move (-mouseDownCanMoveWindow), in a window that is movable
// by its background, or in the title bar area of a window that shows no
// title bar, where the application's content covers the title bar.
- (BOOL) _mouseDownMovesWindow: (NSEvent *) event {
    NSWindow *window = [self window];
    if (![window isMovable])
        return NO;

    NSPoint location = [event locationInWindow];
    NSView *hit = [self hitTest: location];
    if (hit != nil && hit != self && ![hit mouseDownCanMoveWindow])
        return NO;

    if ([window isMovableByWindowBackground])
        return YES;

    NSPoint point = [self convertPoint: location fromView: nil];
    return [window _hasInvisibleTitlebarForStyleMask: [window styleMask]] &&
           point.y >= NSMaxY([self bounds]) - NSThemeFrameTitlebarHeight;
}

- (void) mouseDown: (NSEvent *) event {
    // A click that reaches the background either moves the window or goes
    // on up the responder chain.
    if (![self _mouseDownMovesWindow: event]) {
        [super mouseDown: event];
        return;
    }

    [[self window] performWindowDragWithEvent: event];
}

@end
