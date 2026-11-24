/* Copyright (C) 2026 Lubos Dolezel

   Licensed under the MIT license, the same as the rest of this project. */

// Key bindings of the Tab key. On macOS 26.7.3 and 10.14.4 (x86_64, i386; black-box observation) a key down
// event for Tab without modifiers has the characters U+0009 and is interpreted as insertTab:, with Shift
// the characters are NSBackTabCharacter (U+0019) and it is interpreted as insertBacktab:, with Control
// as selectNextKeyView: and with Option as insertTabIgnoringFieldEditor: (not checked here). Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static NSString *recorded;

@interface Recorder : NSView
@end

@implementation Recorder
- (BOOL)acceptsFirstResponder { return YES; }
- (void)doCommandBySelector:(SEL)selector { recorded = NSStringFromSelector(selector); }
- (void)insertText:(id)text { recorded = [NSString stringWithFormat:@"insertText:%@", text]; }
@end

static int failures;

static void checkTab(unichar character, NSEventModifierFlags flags, NSString *expected, const char *what)
{
    Recorder *view = [[[Recorder alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
    recorded = nil;
    NSString *characters = [NSString stringWithCharacters:&character length:1];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags
        timestamp:0 windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:characters
        isARepeat:NO keyCode:48];
    [view interpretKeyEvents:@[ event ]];
    if (![recorded isEqual:expected]) {
        printf("FAIL: %s: got %s, expected %s\n", what, [recorded UTF8String], [expected UTF8String]);
        failures++;
    } else {
        printf("PASS: %s\n", what);
    }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        checkTab('\t', 0, @"insertTab:", "Tab");
        checkTab(NSBackTabCharacter, NSEventModifierFlagShift, @"insertBacktab:", "Shift-Tab with the back tab character");
        checkTab('\t', NSEventModifierFlagShift, @"insertBacktab:", "Shift-Tab with the tab character");
    }
    return failures ? 1 : 0;
}
