// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.

#import <Foundation/NSObject.h>
#import <CoreGraphics/CGSWindow.h>

@class CGWindow;

// The window's use of the window system's input method, which CoreGraphics runs (see CGSInputMethod.h): it
// passes what the input method composes on to the text input client of the window's first responder through
// NSTextInputContext, and tells the input method where that client's caret is. Everything the window system's
// protocol needs is CoreGraphics'. A window system backend whose windows are CoreGraphics windows makes one for
// each window and gives it the window's toplevel events.
@interface NSCGSInputMethod : NSObject {
    CGWindow *_platformWindow; // not retained: it owns this
    CGSWindow *_cgsWindow;
}

- (instancetype) initWithPlatformWindow: (CGWindow *) platformWindow cgsWindow: (CGSWindow *) cgsWindow;
// Whether CoreGraphics' window system has an input method for windows at all.
+ (BOOL) available;
// Lets the window use the input method, or stops it.
- (void) setEnabled: (BOOL) enabled;
// A toplevel event of the window; returns whether it was an input method event.
- (BOOL) handleToplevelEvent: (const CGSToplevelEvent *) event;
// The window's first responder changed: the input method is enabled for a window whose first responder takes text
// (and disabled otherwise), and told where its caret is.
- (void) firstResponderChanged;
// The caret of the client moved: the input method is told where the candidates belong.
- (void) candidateRectChanged;
// The window is going away.
- (void) invalidate;

@end
