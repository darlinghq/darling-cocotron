/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSWindow keyViewSelectionDirection] tells a view that becomes first
// responder which way the key view selection is moving: NSSelectingNext
// while -selectKeyViewFollowingView: / -selectNextKeyView: make the next view
// first responder, NSSelectingPrevious for the preceding variants, and
// NSDirectSelection otherwise (including after those methods return).
// Run with -p to print the observations instead of checking them (that is how
// the expected lines were read on macOS 26.7.3 and 10.14.4).
// No window server needed. Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static NSMutableString *log_;

@interface KeyView : NSView {
  @public
    const char *name;
}
@end

@implementation KeyView
- (BOOL) acceptsFirstResponder {
    return YES;
}
- (BOOL) becomeFirstResponder {
    [log_ appendFormat: @"%s becomes first responder, direction %d\n", name,
        (int) [[self window] keyViewSelectionDirection]];
    return YES;
}
@end

static KeyView *makeView(const char *name, NSView *parent) {
    KeyView *view = [[KeyView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    view->name = name;
    [parent addSubview: view];
    return view;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL print = argc > 1 && strcmp(argv[1], "-p") == 0;
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        [window setAutorecalculatesKeyViewLoop: NO];
        NSView *parent = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
        [window setContentView: parent];
        KeyView *a = makeView("a", parent), *b = makeView("b", parent), *c = makeView("c", parent);
        [a setNextKeyView: b];
        [b setNextKeyView: c];
        [c setNextKeyView: a];
        log_ = [NSMutableString string];

        [window makeFirstResponder: a];
        [window selectKeyViewFollowingView: a];
        [log_ appendFormat: @"after following: %d\n", (int) [window keyViewSelectionDirection]];
        [window selectKeyViewPrecedingView: b];
        [log_ appendFormat: @"after preceding: %d\n", (int) [window keyViewSelectionDirection]];
        [window selectNextKeyView: nil];
        [log_ appendFormat: @"after next: %d\n", (int) [window keyViewSelectionDirection]];
        [window selectPreviousKeyView: nil];
        [log_ appendFormat: @"after previous: %d\n", (int) [window keyViewSelectionDirection]];
        [window makeFirstResponder: c];
        [log_ appendFormat: @"after direct: %d\n", (int) [window keyViewSelectionDirection]];

        if (print) {
            printf("%s", [log_ UTF8String]);
            return 0;
        }
        NSString *expected = @"a becomes first responder, direction 0\n"
            "b becomes first responder, direction 1\n"
            "after following: 0\n"
            "a becomes first responder, direction 2\n"
            "after preceding: 0\n"
            "b becomes first responder, direction 1\n"
            "after next: 0\n"
            "a becomes first responder, direction 2\n"
            "after previous: 0\n"
            "c becomes first responder, direction 0\n"
            "after direct: 0\n";
        if (![log_ isEqualToString: expected]) {
            printf("FAIL: got\n%swanted\n%s", [log_ UTF8String], [expected UTF8String]);
            return 1;
        }
        puts("PASS");
    }
    return 0;
}
