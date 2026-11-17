// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.

#import <AppKit/NSTextInput.h>

@class NSWindow;

// What a window system backend, which receives composition from the platform's input method,
// sends to the text input client of the key window's first responder. The calls follow what
// NSTextInputClient documents for an input method: the composition is marked text, a commit
// replaces it with the final text, and cancelling removes it.
@interface NSTextInputContext (BackendInputMethod)
// The input context of the window's first responder, or nil when it is not a text input client.
+ (NSTextInputContext *) inputContextForWindow: (NSWindow *) window;
// The composition changed to `text`; `selection` is the caret or selected part inside it, in
// UTF-16 units. Empty text removes the composition.
- (void) updateComposition: (NSString *) text selection: (NSRange) selection;
// The composition ended without text: the marked text is removed.
- (void) cancelComposition;
// Final text from the input method; it replaces the marked text if there is any.
- (void) commitComposition: (NSString *) text;
// The rectangle of the composition's caret (or, without a composition, the insertion point) in
// screen coordinates, as the client's firstRectForCharacterRange:actualRange: reports it;
// NSZeroRect when the client cannot say.
- (NSRect) candidateRectOnScreen;
@end
