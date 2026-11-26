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

#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSStatusItem+Private.h>
#import <AppKit/NSStatusItem.h>
#import <AppKit/NSWindow.h>
#import "NSStatusItemNotifier.h"

@implementation NSStatusBarButton

- (BOOL) appearsDisabled {
    return _appearsDisabled;
}

- (void) setAppearsDisabled: (BOOL) flag {
    _appearsDisabled = flag;
    [self setNeedsDisplay: YES];
}

// What the button shows is what the item shows in the system tray, whoever
// changes it, the item or the application through its button.
- (void) setImage: (NSImage *) image {
    [super setImage: image];
    [_statusItem _contentChanged: NSStatusItemNotifierIcon];
}

- (void) setTitle: (NSString *) title {
    [super setTitle: title];
    [_statusItem _contentChanged: NSStatusItemNotifierTitle];
}

- (void) setAttributedTitle: (NSAttributedString *) title {
    [super setAttributedTitle: title];
    [_statusItem _contentChanged: NSStatusItemNotifierTitle];
}

- (void) setToolTip: (NSString *) toolTip {
    [super setToolTip: toolTip];
    [_statusItem _contentChanged: NSStatusItemNotifierToolTip];
}

- (void) _setStatusItem: (NSStatusItem *) item {
    _statusItem = item;
}

@end

@implementation NSStatusItem

#pragma mark Private Methods


#pragma mark Public Methods

- (id) init {
    self = [super init];
    if (self) {
        // Items are visible until the application hides them, highlight on click and send
        // their action when the left button goes up (as observed on macOS 10.14 and 26).
        _visible = YES;
        _highlightMode = YES;
        _actionMask = NSLeftMouseUpMask;
        // The item's image, title, target and action live in its button, which exists from the start.
        _button = [[NSStatusBarButton alloc] initWithFrame: NSMakeRect(0, 0, 16, 22)];
        // A status item shows nothing until the application gives it a title or an image, unlike a plain NSButton.
        [_button setTitle: @""];
        [_button _setStatusItem: self];
    }
    return self;
}

- (void) _attachToStatusBar {
    if (_notifier == nil)
        _notifier = [[NSStatusItemNotifier alloc] initWithStatusItem: self];
}

- (void) _detachFromStatusBar {
    [_notifier invalidate];
    [_notifier release];
    _notifier = nil;
}

- (void) _contentChanged: (NSUInteger) aspects {
    [_notifier itemChanged: aspects];
}

// The click that the system tray calls the primary one is the left click, the
// secondary one is the right click; the action goes out when the item is set
// to send it on that kind of click (the left button going up, unless
// sendActionOn: says otherwise).
- (void) _sendActionForClick: (BOOL) secondary {
    NSInteger mask = _actionMask;
    NSInteger wanted = secondary ? (NSRightMouseDownMask | NSRightMouseUpMask)
                                 : (NSLeftMouseDownMask | NSLeftMouseUpMask);

    if ((mask & wanted) == 0 || ![_button isEnabled] || [_button action] == NULL)
        return;
    [[NSApplication sharedApplication] sendAction: [_button action]
                                               to: [_button target]
                                             from: _button];
}

- (NSStatusBar *) statusBar {
    return [NSStatusBar systemStatusBar];
}

- (SEL) action {
    return [_button action];
}
- (void) setAction: (SEL) action {
    [_button setAction: action];
}
- (SEL) doubleAction {
    return _doubleAction;
}
- (void) setDoubleAction: (SEL) action {
    _doubleAction = action;
}
- (id) target {
    return [_button target];
}
- (void) setTarget: (id) target {
    [_button setTarget: target];
}

- (NSImage *) image {
    return [_button image];
}

- (void) setImage: (NSImage *) image {
    [_button setImage: image];
}
- (NSImage *) alternateImage {
    return [_button alternateImage];
}
- (void) setAlternateImage: (NSImage *) image {
    [_button setAlternateImage: image];
}

- (NSString *) title {
    return [_button title];
}
- (void) setTitle: (NSString *) title {
    [_button setTitle: title];
}
- (NSString *) toolTip {
    return [_button toolTip];
}
- (void) setToolTip: (NSString *) toolTip {
    [_button setToolTip: toolTip];
}
- (NSAttributedString *) attributedTitle {
    return [_button attributedTitle];
}
- (void) setAttributedTitle: (NSAttributedString *) title {
    [_button setAttributedTitle: title];
}

- (NSView *) view {
    return _view;
}
- (void) setView: (NSView *) view {
    [_view release];
    _view = nil;
    _view = [view copy];
    // Start capture timer
}

- (BOOL) highlightMode {
    return _highlightMode;
}
- (void) setHighlightMode: (BOOL) flag {
    _highlightMode = flag;
}

- (BOOL) isEnabled {
    return [_button isEnabled];
}
- (void) setEnabled: (BOOL) flag {
    [_button setEnabled: flag];
}

- (CGFloat) length {
    return _length;
}
- (void) setLength: (CGFloat) len {
    _length = len;
}

- (NSMenu *) menu {
    return _menu;
}
- (void) setMenu: (NSMenu *) menu {
    if (_menu != menu) {
        [_menu release];
        _menu = [menu retain];
    }
    [self _contentChanged: NSStatusItemNotifierMenu | NSStatusItemNotifierStatus];
}

- (void) popUpStatusItemMenu: (NSMenu *) menu {
}

- (void) _showContextMenu {
}

- (NSInteger) sendActionOn: (NSInteger) mask {
    int previousMask = _actionMask;
    _actionMask = mask;
    return previousMask;
}

- (void) drawStatusBarBackgroundInRect: (NSRect) rect
                         withHighlight: (BOOL) highlight
{
    NSUnimplementedMethod();
}

- (NSStatusItemBehavior) behavior {
    return _behavior;
}

- (void) setBehavior: (NSStatusItemBehavior) behavior {
    _behavior = behavior;
}

- (NSStatusBarButton *) button {
    return _button;
}

- (NSString *) autosaveName {
    return _autosaveName != nil ? _autosaveName : _defaultAutosaveName;
}

- (void) setAutosaveName: (NSString *) name {
    // A nil name returns the item to the name the status bar gave it.
    if (_autosaveName != name) {
        [_autosaveName release];
        _autosaveName = [name copy];
    }
}

- (NSString *) _defaultAutosaveName {
    return _defaultAutosaveName;
}

- (void) _setDefaultAutosaveName: (NSString *) name {
    if (_defaultAutosaveName != name) {
        [_defaultAutosaveName release];
        _defaultAutosaveName = [name copy];
    }
}

- (BOOL) isVisible {
    return _visible;
}

- (void) setVisible: (BOOL) visible {
    _visible = visible;
    [self _contentChanged: NSStatusItemNotifierStatus];
}

- (void) dealloc {
    [self _detachFromStatusBar];
    [_button _setStatusItem: nil];
    [_view release];
    [_menu release];
    [_button release];
    [_autosaveName release];
    [_defaultAutosaveName release];
    [super dealloc];
}

@end
