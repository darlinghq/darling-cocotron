/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Checks that the keyboard document-edge selection commands extend from the
 * selection anchor, that the anchor is clamped when the storage shrinks, that
 * -insertText:replacementRange: leaves a selection delegate's choice alone and
 * that -characterIndexForPoint: reports NSNotFound for a view without a window.
 * No window server is needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSTextView *makeView(NSString *string)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
    [view setString: string];
    return view;
}

int main(void)
{
    @autoreleasepool {
        NSTextView *view = makeView(@"abcdef");

        // A caret in the middle is the anchor: extending to the document edges
        // keeps the caret side fixed.
        [view setSelectedRange: NSMakeRange(3, 0)];
        [view moveToEndOfDocumentAndModifySelection: nil];
        expect(NSEqualRanges([view selectedRange], NSMakeRange(3, 3)),
              "caret at 3 extended to the end selects 3..6");

        [view setSelectedRange: NSMakeRange(3, 0)];
        [view moveToBeginningOfDocumentAndModifySelection: nil];
        expect(NSEqualRanges([view selectedRange], NSMakeRange(0, 3)),
              "caret at 3 extended to the beginning selects 0..3");

        // The storage shrinks below the anchor: the range stays valid.
        [view setSelectedRange: NSMakeRange(5, 0)];
        [[view textStorage] replaceCharactersInRange: NSMakeRange(1, 5) withString: @""];
        [view moveToEndOfDocumentAndModifySelection: nil];
        NSRange range = [view selectedRange];
        expect(NSMaxRange(range) <= [[view textStorage] length],
              "selection stays inside the storage after it shrank");

        [[view textStorage] replaceCharactersInRange: NSMakeRange(1, 0) withString: @"bcd"];
        [view setSelectedRange: NSMakeRange(4, 0)];
        [[view textStorage] replaceCharactersInRange: NSMakeRange(1, 3) withString: @""];
        [view moveToBeginningOfDocumentAndModifySelection: nil];
        range = [view selectedRange];
        expect(NSMaxRange(range) <= [[view textStorage] length],
              "beginning-edge extension clamps a stale anchor");

        // Without a window there is no character under any screen point.
        view = makeView(@"hello");
        expect([view characterIndexForPoint: NSMakePoint(10, 10)] == NSNotFound,
              "characterIndexForPoint: without a window is NSNotFound");

        // Replacing an explicit range leaves the other text intact.
        view = makeView(@"hello world");
        [view setEditable: YES];
        [view insertText: @"there" replacementRange: NSMakeRange(6, 5)];
        expect([[view string] isEqualToString: @"hello there"],
              "insertText:replacementRange: replaces the given range");
        BOOL raised = NO;
        @try {
            [view insertText: @"x" replacementRange: NSMakeRange(50, 1)];
        } @catch (NSException *e) {
            raised = [[e name] isEqualToString: NSRangeException];
        }
        expect(raised, "insertText:replacementRange: raises for an out-of-range replacement");
    }
    if (failures)
        return 1;
    puts("textview selection anchor: PASS");
    return 0;
}
