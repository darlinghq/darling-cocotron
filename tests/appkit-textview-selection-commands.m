/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSTextView: extending a selection to the beginning or end of the document
// keeps the caret as the other end, and the editing menu items validate
// against editability and the selection. No window is shown.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL validate(NSTextView *view, SEL action) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"x" action: action keyEquivalent: @""];
    BOOL result = [view validateMenuItem: item];
    [item release];
    return result;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
        [view setString: @"abcdef"];

        [view setSelectedRange: NSMakeRange(2, 0)];
        [view moveToEndOfDocumentAndModifySelection: nil];
        expect(NSEqualRanges([view selectedRange], NSMakeRange(2, 4)),
               "extending to the end from a caret at 2 selects 2..6");

        [view setSelectedRange: NSMakeRange(2, 0)];
        [view moveToBeginningOfDocumentAndModifySelection: nil];
        expect(NSEqualRanges([view selectedRange], NSMakeRange(0, 2)),
               "extending to the beginning from a caret at 2 selects 0..2");

        [view setSelectedRange: NSMakeRange(6, 0)];
        [view moveToEndOfDocumentAndModifySelection: nil];
        expect(NSEqualRanges([view selectedRange], NSMakeRange(6, 0)),
               "extending to the end from the end keeps the caret");

        // Edit menu validation.
        [view setEditable: YES];
        [view setSelectable: YES];
        [view setSelectedRange: NSMakeRange(1, 3)];
        expect(validate(view, @selector(cut:)), "cut is enabled with a selection in an editable view");
        expect(validate(view, @selector(copy:)), "copy is enabled with a selection");
        expect(validate(view, @selector(paste:)), "paste is enabled in an editable view");
        expect(validate(view, @selector(selectAll:)), "select all is enabled with text");

        [view setSelectedRange: NSMakeRange(1, 0)];
        expect(!validate(view, @selector(cut:)), "cut is disabled without a selection");
        expect(!validate(view, @selector(copy:)), "copy is disabled without a selection");

        [view setSelectedRange: NSMakeRange(1, 3)];
        [view setEditable: NO];
        expect(!validate(view, @selector(cut:)), "cut is disabled in a read-only view");
        expect(!validate(view, @selector(paste:)), "paste is disabled in a read-only view");
        expect(validate(view, @selector(copy:)), "copy stays enabled in a read-only view");

        [view setString: @""];
        expect(!validate(view, @selector(selectAll:)), "select all is disabled without text");
        [view release];
    }
    printf("text view selection commands: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
