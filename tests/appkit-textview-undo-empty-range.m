/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Changing the attributes of an empty range of a text view that allows undo
// registers nothing for undo and leaves no undo group open, also when the
// text is empty.
// Run with -p to print what was observed instead of checking it (that is how
// the expected lines were read on macOS 26.7.3).
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

@interface Delegate : NSObject <NSTextViewDelegate> {
@public
    NSUndoManager *undoManager;
}
@end

@implementation Delegate
- (NSUndoManager *) undoManagerForTextView: (NSTextView *) textView {
    return undoManager;
}
@end

static NSString *attempt(NSString *text, NSRange range, BOOL useFont) {
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    Delegate *delegate = [[Delegate alloc] init];
    delegate->undoManager = [[NSUndoManager alloc] init];
    [view setString: text];
    [view setDelegate: delegate];
    [view setAllowsUndo: YES];
    NSUInteger before = [delegate->undoManager groupingLevel];
    if (useFont)
        [view setFont: [NSFont systemFontOfSize: 12] range: range];
    else
        [view setTextColor: [NSColor redColor] range: range];
    return [NSString stringWithFormat: @"%s: opened %d group(s)\n", useFont ? "font" : "color",
            (int) ([delegate->undoManager groupingLevel] - before)];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL print = argc > 1 && strcmp(argv[1], "-p") == 0;
        [NSApplication sharedApplication];
        NSMutableString *log = [NSMutableString string];
        [log appendString: @"empty text, empty range\n"];
        [log appendString: attempt(@"", NSMakeRange(0, 0), YES)];
        [log appendString: attempt(@"", NSMakeRange(0, 0), NO)];
        [log appendString: @"text, empty range\n"];
        [log appendString: attempt(@"abc", NSMakeRange(1, 0), YES)];
        [log appendString: attempt(@"abc", NSMakeRange(1, 0), NO)];
        if (print) {
            printf("%s", [log UTF8String]);
            return 0;
        }
        NSString *expected =
            @"empty text, empty range\n"
             "font: opened 0 group(s)\n"
             "color: opened 0 group(s)\n"
             "text, empty range\n"
             "font: opened 0 group(s)\n"
             "color: opened 0 group(s)\n";
        if (![log isEqualToString: expected]) {
            printf("FAIL: got\n%swanted\n%s", [log UTF8String], [expected UTF8String]);
            return 1;
        }
        printf("PASS\n");
        return 0;
    }
}
