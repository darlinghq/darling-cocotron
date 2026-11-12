/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

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

#import <AppKit/NSPanel.h>
#import <AppKit/NSPopover.h>
#import <AppKit/NSView.h>
#import <AppKit/NSViewController.h>

NSNotificationName const NSPopoverDidCloseNotification = @"NSPopoverDidCloseNotification";
NSNotificationName const NSPopoverWillCloseNotification = @"NSPopoverWillCloseNotification";
NSNotificationName const NSPopoverWillShowNotification = @"NSPopoverWillShowNotification";
NSNotificationName const NSPopoverDidShowNotification = @"NSPopoverDidShowNotification";

@implementation NSPopover

@synthesize behavior = _behavior;
@synthesize animates = _animates;
@synthesize contentSize = _contentSize;
@synthesize contentViewController = _contentViewController;
@synthesize delegate = _delegate;
@synthesize positioningRect = _positioningRect;

- (instancetype) init {
    if ((self = [super init]))
        _animates = YES;
    return self;
}

// Keyed-archive names as GNUstep's NSPopover (LGPL, libs-gui) reads them.
- (instancetype) initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ only decodes keyed archives", [self class]];
    if ((self = [super initWithCoder: coder])) {
        _behavior = [coder decodeIntegerForKey: @"NSBehavior"];
        _animates = [coder decodeBoolForKey: @"NSAnimates"];
        _contentSize = NSMakeSize([coder decodeDoubleForKey: @"NSContentWidth"],
                                  [coder decodeDoubleForKey: @"NSContentHeight"]);
        _contentViewController = [[coder decodeObjectForKey: @"NSContentViewController"] retain];
    }
    return self;
}

- (void) dealloc {
    [_panel orderOut: nil];
    [_panel release];
    [_contentViewController release];
    [super dealloc];
}

- (BOOL) isShown {
    return [_panel isVisible];
}

- (void) _notify: (NSNotificationName) name delegateSelector: (SEL) selector {
    NSNotification *note = [NSNotification notificationWithName: name object: self];
    if ([_delegate respondsToSelector: selector])
        [_delegate performSelector: selector withObject: note];
    [[NSNotificationCenter defaultCenter] postNotification: note];
}

- (void) showRelativeToRect: (NSRect) positioningRect
                     ofView: (NSView *) positioningView
              preferredEdge: (NSRectEdge) preferredEdge
{
    NSWindow *window = [positioningView window];
    if (window == nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"NSPopover positioning view %@ is not in a window", positioningView];
    if (_contentViewController == nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"NSPopover %@ has no content view controller", self];

    NSView *content = [_contentViewController view];
    NSSize size = NSEqualSizes(_contentSize, NSZeroSize) ? [content frame].size : _contentSize;
    if (NSIsEmptyRect(positioningRect))
        positioningRect = [positioningView bounds];
    _positioningRect = positioningRect;

    // The edge is given in the positioning view's coordinates; screen coordinates are never flipped.
    if ([positioningView isFlipped] && (preferredEdge == NSMinYEdge || preferredEdge == NSMaxYEdge))
        preferredEdge = preferredEdge == NSMinYEdge ? NSMaxYEdge : NSMinYEdge;
    NSRect anchor = [window convertRectToScreen: [positioningView convertRect: positioningRect toView: nil]];
    NSPoint origin;
    switch (preferredEdge) {
    case NSMinXEdge:
        origin = NSMakePoint(NSMinX(anchor) - size.width, NSMidY(anchor) - size.height / 2);
        break;
    case NSMaxXEdge:
        origin = NSMakePoint(NSMaxX(anchor), NSMidY(anchor) - size.height / 2);
        break;
    case NSMinYEdge:
        origin = NSMakePoint(NSMidX(anchor) - size.width / 2, NSMinY(anchor) - size.height);
        break;
    default:
        origin = NSMakePoint(NSMidX(anchor) - size.width / 2, NSMaxY(anchor));
        break;
    }

    if (_panel == nil) {
        _panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, size.width, size.height)
                                            styleMask: NSWindowStyleMaskBorderless
                                              backing: NSBackingStoreBuffered
                                                defer: NO];
        [_panel setReleasedWhenClosed: NO];
        [_panel setLevel: NSPopUpMenuWindowLevel];
    }
    [_panel setContentView: content];
    [_panel setFrame: NSMakeRect(origin.x, origin.y, size.width, size.height) display: NO];

    [self _notify: NSPopoverWillShowNotification delegateSelector: @selector(popoverWillShow:)];
    [_panel orderFront: nil];
    [self _notify: NSPopoverDidShowNotification delegateSelector: @selector(popoverDidShow:)];
}

- (void) performClose: (id) sender {
    if ([_delegate respondsToSelector: @selector(popoverShouldClose:)] &&
        ![_delegate popoverShouldClose: self])
        return;
    [self close];
}

- (void) close {
    if (![self isShown])
        return;
    [self _notify: NSPopoverWillCloseNotification delegateSelector: @selector(popoverWillClose:)];
    [_panel orderOut: nil];
    [self _notify: NSPopoverDidCloseNotification delegateSelector: @selector(popoverDidClose:)];
}

@end
