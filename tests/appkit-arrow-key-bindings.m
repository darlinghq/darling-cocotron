// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// The standard key bindings for the arrow keys, through -interpretKeyEvents:,
// and that shift-left and shift-right extend a text view's selection. As on
// macOS 26.7.3 and 10.14.4 (darling's tests/collection-view.md); the program
// passes unchanged on both.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void expect(BOOL ok, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    printf("%s ", ok ? "PASS" : "FAIL");
    vprintf(format, ap);
    printf("\n");
    va_end(ap);
    if (!ok)
        failures++;
}

static NSString *lastCommand;

@interface CommandView : NSView
@end
@implementation CommandView
- (BOOL) acceptsFirstResponder {
    return YES;
}
- (void) keyDown: (NSEvent *) event {
    [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}
- (void) doCommandBySelector: (SEL) selector {
    [lastCommand release];
    lastCommand = [NSStringFromSelector(selector) retain];
}
- (void) insertText: (id) text {
}
@end

static NSEvent *arrow(NSWindow *window, unichar key, NSEventModifierFlags flags)
{
    NSString *string = [NSString stringWithCharacters: &key length: 1];
    return [NSEvent keyEventWithType: NSEventTypeKeyDown
                            location: NSZeroPoint
                       modifierFlags: flags | NSEventModifierFlagFunction | NSEventModifierFlagNumericPad
                           timestamp: 0
                        windowNumber: [window windowNumber]
                             context: nil
                          characters: string
         charactersIgnoringModifiers: string
                           isARepeat: NO
                             keyCode: 0];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                                   styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    CommandView *view = [[[CommandView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    [window.contentView addSubview: view];
    [window makeKeyAndOrderFront: nil];
    [window makeFirstResponder: view];

    struct {
        unichar key;
        NSEventModifierFlags flags;
        NSString *selector;
    } cases[] = {
        {NSLeftArrowFunctionKey, 0, @"moveLeft:"},
        {NSRightArrowFunctionKey, 0, @"moveRight:"},
        {NSUpArrowFunctionKey, 0, @"moveUp:"},
        {NSDownArrowFunctionKey, 0, @"moveDown:"},
        {NSLeftArrowFunctionKey, NSEventModifierFlagShift, @"moveLeftAndModifySelection:"},
        {NSRightArrowFunctionKey, NSEventModifierFlagShift, @"moveRightAndModifySelection:"},
        {NSUpArrowFunctionKey, NSEventModifierFlagShift, @"moveUpAndModifySelection:"},
        {NSDownArrowFunctionKey, NSEventModifierFlagShift, @"moveDownAndModifySelection:"},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        [lastCommand release];
        lastCommand = nil;
        [window sendEvent: arrow(window, cases[i].key, cases[i].flags)];
        expect([lastCommand isEqual: cases[i].selector], "%s%s arrow 0x%x sends %s (%s)",
               cases[i].flags ? "shift-" : "", "", cases[i].key, [cases[i].selector UTF8String],
               lastCommand ? [lastCommand UTF8String] : "nothing");
    }

    // A text view extends its selection by a character with shift-right and shrinks it with shift-left
    NSTextView *text = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    [text setString: @"abcdef"];
    [window.contentView addSubview: text];
    [window makeFirstResponder: text];
    [text setSelectedRange: NSMakeRange(2, 0)];
    [window sendEvent: arrow(window, NSRightArrowFunctionKey, NSEventModifierFlagShift)];
    [window sendEvent: arrow(window, NSRightArrowFunctionKey, NSEventModifierFlagShift)];
    NSRange range = [text selectedRange];
    expect(range.location == 2 && range.length == 2, "shift-right twice selects two characters ({%lu, %lu})",
           (unsigned long) range.location, (unsigned long) range.length);
    [window sendEvent: arrow(window, NSLeftArrowFunctionKey, NSEventModifierFlagShift)];
    range = [text selectedRange];
    expect(range.location == 2 && range.length == 1, "then shift-left leaves one ({%lu, %lu})",
           (unsigned long) range.location, (unsigned long) range.length);

    [window release];
    [lastCommand release];
    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
