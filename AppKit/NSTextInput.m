#include <AppKit/NSTextInput.h>
#include <AppKit/NSTextInput_Internal.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSKeyboardBinding.h>
#import <AppKit/NSKeyboardBindingManager.h>
#import <AppKit/NSTextInputClient.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSTextInputBackend.h>
#import <AppKit/NSView.h>
#import <objc/runtime.h>

// The NSTextInputClient methods a context sends.
@interface NSObject (NSTextInputContextClient)
- (void) insertText: (id) string replacementRange: (NSRange) range;
- (void) doCommandBySelector: (SEL) selector;
- (void) unmarkText;
@end

NSString *const NSTextInputContextKeyboardSelectionDidChangeNotification = @"NSTextInputContextKeyboardSelectionDidChangeNotification";

NSString *const NSTextInputReplacementRangeAttributeName = @"NSTextInputReplacementRangeAttributeName";

// Private: marks inserted text (the value is a boolean) that the client should
// let the user undo as one insertion. The string was read from the exported constant on macOS 26.7.3 and 10.14.4 (black-box observation).
NSString *const NSTextInsertionUndoableAttributeName = @"NSTextInsertionUndoable";

@implementation NSTextInputContext

+ (NSTextInputContext *) currentInputContext {
    NSResponder *responder = [[NSApp keyWindow] firstResponder];

    if ([responder respondsToSelector: @selector(inputContext)])
        return [(id) responder inputContext];
    return nil;
}

// The client is not retained: it owns its context.
- (instancetype) initWithClient: (id<NSTextInputClient>) client {
    if ((self = [super init]) != nil)
        _client = client;
    return self;
}

- (id<NSTextInputClient>) client {
    return _client;
}

// Private: whether the system may draw its accessories (such as the input
// source indicator) next to the insertion point. It is YES until changed.
// Darling draws no cursor accessories, so the setting is only stored.
// QUIRK: there is one setting for the whole process; a value set through any
// context is what every context, also one created later, reports. Not
// documented. Evidence: black-box observation on macOS 26.7.3 x86_64 (tier 2).
// Test: appkit-text-input-context-private.m.
static BOOL hidesCursorAccessories;

- (BOOL) showsCursorAccessories {
    return !hidesCursorAccessories;
}

- (void) setShowsCursorAccessories: (BOOL) shows {
    hidesCursorAccessories = !shows;
}

- (void) activate {
}

- (void) deactivate {
}

- (void) invalidateCharacterCoordinates {
    [self notifyDisplayOfCandidateRectChange];
}

// Without an input method, the only marked text is the client's own.
- (void) discardMarkedText {
    if ([_client respondsToSelector: @selector(unmarkText)])
        [_client unmarkText];
}

static BOOL isInsertableText(NSString *text) {
    NSUInteger length = [text length];

    if (length == 0)
        return NO;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [text characterAtIndex: i];

        // Control characters and the function key range are not text.
        if (c < 0x20 || c == 0x7f || (c >= 0xf700 && c <= 0xf8ff))
            return NO;
    }
    return YES;
}

- (BOOL) handleEvent: (NSEvent *) event {
    // Command key equivalents are not text input.
    if ([event type] != NSKeyDown ||
        ([event modifierFlags] & NSCommandKeyMask))
        return NO;

    NSKeyboardBinding *binding = [[NSKeyboardBindingManager
            defaultKeyBindingManager]
            keyBindingWithString: [event charactersIgnoringModifiers]
                   modifierFlags: [event modifierFlags]];
    NSArray *selectorNames = [binding selectorNames];

    if (selectorNames != nil) {
        if (![_client respondsToSelector: @selector(doCommandBySelector:)])
            return NO;
        for (NSString *name in selectorNames)
            [_client doCommandBySelector: NSSelectorFromString(name)];
        return YES;
    }

    NSString *text = [event characters];
    if (([event modifierFlags] & NSControlKeyMask) || !isInsertableText(text))
        return NO;
    if (![_client respondsToSelector: @selector(insertText:replacementRange:)])
        return NO;
    [_client insertText: text replacementRange: NSMakeRange(NSNotFound, 0)];
    return YES;
}

// Private variants of -handleEvent:. -handleEvent: runs the input method and
// then the keyboard layout (key bindings and text insertion); these run one
// stage each, or both with the result delivered to a block. On macOS 26.7.3
// the blocks run before the methods return (test
// appkit-text-input-context-private.m).
- (void) handleEvent: (NSEvent *) event completionHandler: (void (^)(BOOL handled)) completionHandler {
    BOOL handled = [self handleEvent: event];

    if (completionHandler != nil)
        completionHandler(handled);
}

// Input methods run in the window system backend, which delivers composed
// text through -updateComposition:selection: and -commitComposition:, never
// through key events handed to the context. So the input method stage handles
// no event here, as on macOS when no input method is selected.
- (void) handleEventByInputMethod: (NSEvent *) event completionHandler: (void (^)(BOOL handled)) completionHandler {
    if (completionHandler != nil)
        completionHandler(NO);
}

- (BOOL) handleEventByKeyboardLayout: (NSEvent *) event {
    return [self handleEvent: event];
}

// Tells the window system backend, if it has an input method, that its
// candidate window belongs somewhere else now.
- (void) notifyDisplayOfCandidateRectChange {
    NSWindow *window = [(NSView *) _client isKindOfClass: [NSView class]]
            ? [(NSView *) _client window] : nil;
    NSDisplay *display = [NSDisplay currentDisplay];

    if (window != nil &&
        [display respondsToSelector: @selector(textInputCandidateRectChangedInWindow:)])
        [display textInputCandidateRectChangedInWindow: window];
}

+ (NSString *) localizedNameForInputSource: (NSTextInputSourceIdentifier) inputSourceIdentifier {
    return @"U.S.";
}

- (NSTextInputSourceIdentifier) selectedKeyboardInputSource {
    return @"com.apple.keylayout.US";
}

- (void) setSelectedKeyboardInputSource: (NSTextInputSourceIdentifier) inputSourceIdentifier {
}

- (NSArray *) keyboardInputSources {
    return [NSArray arrayWithObject: @"com.apple.keylayout.US"];
}

@end

@implementation NSTextInputContext (BackendInputMethod)

static char compositionSelectionKey;

// The caret inside the composition last sent to the client. The context has no
// instance variable for it (see AppKit/NSTextInput.h), so it is kept as an
// associated value.
- (NSRange) compositionSelection {
    NSValue *value = objc_getAssociatedObject(self, &compositionSelectionKey);

    return value != nil ? [value rangeValue] : NSMakeRange(0, 0);
}

- (void) setCompositionSelection: (NSRange) range {
    objc_setAssociatedObject(self, &compositionSelectionKey,
                             [NSValue valueWithRange: range],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (NSTextInputContext *) inputContextForWindow: (NSWindow *) window {
    NSResponder *responder = [window firstResponder];

    if ([responder respondsToSelector: @selector(inputContext)])
        return [(id) responder inputContext];
    return nil;
}

- (void) updateComposition: (NSString *) text selection: (NSRange) selection {
    if ([text length] == 0) {
        [self cancelComposition];
        return;
    }
    if (![_client respondsToSelector:
            @selector(setMarkedText:selectedRange:replacementRange:)])
        return;
    if (selection.location > [text length])
        selection.location = [text length];
    if (NSMaxRange(selection) > [text length])
        selection.length = [text length] - selection.location;
    [self setCompositionSelection: selection];
    [_client setMarkedText: text
             selectedRange: selection
          replacementRange: NSMakeRange(NSNotFound, 0)];
    [self notifyDisplayOfCandidateRectChange];
}

- (void) cancelComposition {
    if (![_client respondsToSelector: @selector(hasMarkedText)] ||
        ![_client hasMarkedText])
        return;
    // Empty marked text removes the composition from the client's text.
    [_client setMarkedText: @""
             selectedRange: NSMakeRange(0, 0)
          replacementRange: NSMakeRange(NSNotFound, 0)];
    if ([_client hasMarkedText])
        [_client unmarkText];
    [self setCompositionSelection: NSMakeRange(0, 0)];
}

- (void) commitComposition: (NSString *) text {
    if ([text length] == 0 ||
        ![_client respondsToSelector: @selector(insertText:replacementRange:)])
        return;
    [_client insertText: text replacementRange: NSMakeRange(NSNotFound, 0)];
    [self setCompositionSelection: NSMakeRange(0, 0)];
    [self notifyDisplayOfCandidateRectChange];
}

- (NSRect) candidateRectOnScreen {
    if (![_client respondsToSelector:
            @selector(firstRectForCharacterRange:actualRange:)])
        return NSZeroRect;

    NSRange range;
    if ([_client respondsToSelector: @selector(hasMarkedText)] &&
        [_client hasMarkedText]) {
        range = [_client markedRange];
        range = NSMakeRange(range.location + [self compositionSelection].location, 0);
    } else if ([_client respondsToSelector: @selector(selectedRange)]) {
        range = [_client selectedRange];
        range.length = 0;
    } else
        return NSZeroRect;
    if (range.location == NSNotFound)
        return NSZeroRect;
    return [_client firstRectForCharacterRange: range actualRange: NULL];
}

@end
