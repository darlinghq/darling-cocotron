// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.

#import "NSCGSInputMethod.h"
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputBackend.h>
#import <AppKit/NSWindow.h>
#import <CoreGraphics/CGSInputMethod.h>
#import <CoreGraphics/CGWindowPrivate.h>

@implementation NSCGSInputMethod

+ (BOOL) available {
    return _CGSInputMethodAvailable();
}

- (instancetype) initWithPlatformWindow: (CGWindow *) platformWindow cgsWindow: (CGSWindow *) cgsWindow {
    if ((self = [super init]) != nil) {
        _platformWindow = platformWindow;
        _cgsWindow = [cgsWindow retain];
    }
    return self;
}

- (void) dealloc {
    [self invalidate];
    [super dealloc];
}

- (void) invalidate {
    [_cgsWindow release];
    _cgsWindow = nil;
    _platformWindow = nil;
}

- (NSTextInputContext *) textInputContext {
    return [NSTextInputContext inputContextForWindow: [(id) _platformWindow delegate]];
}

- (void) setEnabled: (BOOL) enabled {
    if (_cgsWindow != nil)
        _CGSInputMethodSetEnabled([_cgsWindow windowId], enabled);
}

- (BOOL) handleToplevelEvent: (const CGSToplevelEvent *) event {
    switch (event->kind) {
    case kCGSToplevelEventInputMethodPreedit: {
        NSTextInputContext *context = [self textInputContext];
        NSString *text = (NSString *) event->text;

        if ([text length] == 0)
            [context cancelComposition];
        else
            [context updateComposition: text
                             selection: NSMakeRange(event->textRange.location, event->textRange.length)];
        return YES;
    }
    case kCGSToplevelEventInputMethodCommit: {
        NSTextInputContext *context = [self textInputContext];

        // The commit replaces the composition.
        [context cancelComposition];
        [context commitComposition: (NSString *) event->text];
        return YES;
    }
    case kCGSToplevelEventInputMethodDeleteSurrounding:
        // No surrounding text is told to the input method (see -candidateRectChanged), so there is nothing to delete.
        return YES;
    default:
        return NO;
    }
}

// The first responder changed: the input method is for the windows whose first responder takes text, and is given the
// rectangle of its caret.
- (void) firstResponderChanged {
    [self setEnabled: [self textInputContext] != nil];
    [self candidateRectChanged];
}

// Gives the input method the rectangle of the client's caret, in the window's points from its top left corner.
- (void) candidateRectChanged {
    NSWindow *window = [(id) _platformWindow delegate];
    NSRect rect = [[self textInputContext] candidateRectOnScreen];

    if (_cgsWindow == nil || window == nil || NSEqualRects(rect, NSZeroRect))
        return;

    rect = [window convertRectFromScreen: rect];
    CGFloat height = [window frame].size.height;
    _CGSInputMethodSetCursorRect([_cgsWindow windowId],
                                 CGRectMake(NSMinX(rect), height - NSMaxY(rect), NSWidth(rect), NSHeight(rect)));
}

@end
