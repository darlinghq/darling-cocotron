/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextView smart insert and delete (the spaces around inserted text and
 * around deleted words), pasting with the smart paste type, and
 * -pasteAsPlainText: / -pasteAsRichText:. Expected values were read off macOS
 * 10.14.4 and 26.7.3 by inserting next to many characters; both agree. No
 * window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSTextView (V613Test)
- (NSRange) smartDeleteRangeForProposedRange: (NSRange) range;
- (void) smartInsertForString: (NSString *) string replacingRange: (NSRange) range
                 beforeString: (NSString **) before afterString: (NSString **) after;
- (NSString *) smartInsertBeforeStringForString: (NSString *) string replacingRange: (NSRange) range;
- (NSString *) smartInsertAfterStringForString: (NSString *) string replacingRange: (NSRange) range;
- (void) pasteAsPlainText: (id) sender;
- (void) pasteAsRichText: (id) sender;
@end

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
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
    [view setString: string];
    return view;
}

// YES when text inserted at the edge gets a space; the neighbour is placed
// before (neighbour then the insertion point) or after the insertion point.
static BOOL spaceAfterNeighbour(NSTextView *view, unichar neighbour)
{
    [view setString: [NSString stringWithFormat: @"x%C", neighbour]];
    NSString *before = nil;
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(2, 0) beforeString: &before afterString: NULL];
    return before != nil;
}

static BOOL spaceBeforeNeighbour(NSTextView *view, unichar neighbour)
{
    [view setString: [NSString stringWithFormat: @"%Cx", neighbour]];
    NSString *after = nil;
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(0, 0) beforeString: NULL afterString: &after];
    return after != nil;
}

static void testSmartInsert(void)
{
    NSTextView *view = makeView(@"hello world");
    NSString *before = nil, *after = nil;

    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(5, 0) beforeString: &before afterString: &after];
    expect([before isEqualToString: @" "] && after == nil, "after a word, before a space: a space goes before");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(6, 0) beforeString: &before afterString: &after];
    expect(before == nil && [after isEqualToString: @" "], "after a space, before a word: a space goes after");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(3, 0) beforeString: &before afterString: &after];
    expect([before isEqualToString: @" "] && [after isEqualToString: @" "], "inside a word: both");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(0, 0) beforeString: &before afterString: &after];
    expect(before == nil && [after isEqualToString: @" "], "at the start: only after");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(11, 0) beforeString: &before afterString: &after];
    expect([before isEqualToString: @" "] && after == nil, "at the end: only before");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(6, 5) beforeString: &before afterString: &after];
    expect(before == nil && after == nil, "replacing a word between a space and the end: none");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(5, 1) beforeString: &before afterString: &after];
    expect([before isEqualToString: @" "] && [after isEqualToString: @" "], "replacing the space between two words: both");

    [view smartInsertForString: @" foo" replacingRange: NSMakeRange(3, 0) beforeString: &before afterString: &after];
    expect(before == nil && [after isEqualToString: @" "], "text starting with a space gets nothing before");
    [view smartInsertForString: @"foo\n" replacingRange: NSMakeRange(3, 0) beforeString: &before afterString: &after];
    expect([before isEqualToString: @" "] && after == nil, "text ending with a line break gets nothing after");
    [view smartInsertForString: @"" replacingRange: NSMakeRange(5, 0) beforeString: &before afterString: &after];
    expect([before isEqualToString: @" "] && after == nil, "empty text is treated like text without white space at the ends");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(3, 0) beforeString: NULL afterString: NULL];

    expect([[view smartInsertBeforeStringForString: @"foo" replacingRange: NSMakeRange(5, 0)] isEqualToString: @" "] &&
                   [view smartInsertAfterStringForString: @"foo" replacingRange: NSMakeRange(5, 0)] == nil &&
                   [view smartInsertBeforeStringForString: @"foo" replacingRange: NSMakeRange(6, 0)] == nil &&
                   [[view smartInsertAfterStringForString: @"foo" replacingRange: NSMakeRange(6, 0)] isEqualToString: @" "],
           "the single-string forms agree");

    // characters read off the Mac: which neighbours want a space
    expect(spaceAfterNeighbour(view, 'a') && spaceAfterNeighbour(view, '1') && spaceAfterNeighbour(view, 0xE9),
           "a space after letters and digits");
    expect(spaceAfterNeighbour(view, ')') && spaceAfterNeighbour(view, ']') && spaceAfterNeighbour(view, '}') &&
                   spaceAfterNeighbour(view, '>'),
           "a space after closing brackets");
    expect(spaceAfterNeighbour(view, '.') && spaceAfterNeighbour(view, ',') && spaceAfterNeighbour(view, ';') &&
                   spaceAfterNeighbour(view, ':') && spaceAfterNeighbour(view, '!') && spaceAfterNeighbour(view, '?'),
           "a space after sentence punctuation");
    expect(spaceAfterNeighbour(view, '@') && spaceAfterNeighbour(view, '%') && spaceAfterNeighbour(view, '&') &&
                   spaceAfterNeighbour(view, '*') && spaceAfterNeighbour(view, '_') && spaceAfterNeighbour(view, '+') &&
                   spaceAfterNeighbour(view, '='),
           "a space after @ % & * _ + =");
    expect(!spaceAfterNeighbour(view, ' ') && !spaceAfterNeighbour(view, '\n') && !spaceAfterNeighbour(view, '\t') &&
                   !spaceAfterNeighbour(view, 0xA0),
           "no space after white space");
    expect(!spaceAfterNeighbour(view, '(') && !spaceAfterNeighbour(view, '[') && !spaceAfterNeighbour(view, '{') &&
                   !spaceAfterNeighbour(view, '"') && !spaceAfterNeighbour(view, '\'') && !spaceAfterNeighbour(view, '-') &&
                   !spaceAfterNeighbour(view, '/') && !spaceAfterNeighbour(view, '#') && !spaceAfterNeighbour(view, '$') &&
                   !spaceAfterNeighbour(view, '`'),
           "no space after opening brackets, quotes, - / # $ `");
    expect(!spaceAfterNeighbour(view, 0x201C) && !spaceAfterNeighbour(view, 0x2018) && !spaceAfterNeighbour(view, 0xAB) &&
                   !spaceAfterNeighbour(view, 0x2014) && !spaceAfterNeighbour(view, 0x65E5),
           "no space after curly quotes, guillemets, an em dash or ideographs");

    expect(spaceBeforeNeighbour(view, 'a') && spaceBeforeNeighbour(view, '1') && spaceBeforeNeighbour(view, '<') &&
                   spaceBeforeNeighbour(view, '$') && spaceBeforeNeighbour(view, '+') && spaceBeforeNeighbour(view, 0x20AC),
           "a space before letters, digits, < $ + and currency signs");
    expect(!spaceBeforeNeighbour(view, ' ') && !spaceBeforeNeighbour(view, '(') && !spaceBeforeNeighbour(view, ')') &&
                   !spaceBeforeNeighbour(view, '.') && !spaceBeforeNeighbour(view, ',') && !spaceBeforeNeighbour(view, '"') &&
                   !spaceBeforeNeighbour(view, '-') && !spaceBeforeNeighbour(view, '/') && !spaceBeforeNeighbour(view, '>') &&
                   !spaceBeforeNeighbour(view, 0x65E5),
           "no space before white space, brackets, punctuation, quotes, > or ideographs");

    // smart insert and delete off: nothing
    [view setSmartInsertDeleteEnabled: NO];
    [view setString: @"hello world"];
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(5, 0) beforeString: &before afterString: &after];
    expect(before == nil && after == nil, "nothing with smart insert and delete off");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(6, 5)], NSMakeRange(6, 5)),
           "and the proposed delete range is returned unchanged");
    [view setSmartInsertDeleteEnabled: YES];

    BOOL raised = NO;
    @try {
        [view smartInsertForString: @"foo" replacingRange: NSMakeRange(12, 0) beforeString: &before afterString: &after];
    } @catch (NSException *e) {
        raised = [[e name] isEqualToString: NSRangeException];
    }
    expect(raised, "a range starting beyond the text raises NSRangeException");
    [view smartInsertForString: @"foo" replacingRange: NSMakeRange(5, 100) beforeString: &before afterString: &after];
    expect([before isEqualToString: @" "] && after == nil, "a range that only ends beyond the text is cut at the end");
    raised = NO;
    @try {
        [view smartDeleteRangeForProposedRange: NSMakeRange(10, 5)];
    } @catch (NSException *e) {
        raised = [[e name] isEqualToString: NSRangeException];
    }
    expect(raised, "the delete range raises when it ends beyond the text");
    [view release];
}

static void testSmartDelete(void)
{
    NSTextView *view = makeView(@"hello world foo bar");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(6, 5)], NSMakeRange(5, 6)),
           "deleting a word between spaces takes the space before it");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(0, 5)], NSMakeRange(0, 6)),
           "deleting the first word takes the space after it");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(16, 3)], NSMakeRange(15, 4)),
           "deleting the last word takes the space before it");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(12, 4)], NSMakeRange(12, 4)),
           "a range that already contains the space after it is left alone when a word follows");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(4, 5)], NSMakeRange(4, 5)),
           "a range inside words is left alone");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(6, 0)], NSMakeRange(6, 0)),
           "an empty range between a space and a word is left alone");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(0, 19)], NSMakeRange(0, 19)),
           "the whole text is left alone");

    [view setString: @"hello, world. (foo) bar"];
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(7, 5)], NSMakeRange(6, 6)),
           "a word followed by a full stop takes the space before it");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(15, 3)], NSMakeRange(15, 3)),
           "a word in parentheses has no space to take");
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(5, 7)], NSMakeRange(5, 7)),
           "a range between a letter and a full stop is left alone");

    // the character before the space does not matter
    [view setString: @"( wor)"];
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(2, 3)], NSMakeRange(1, 4)),
           "the space before is taken when the next character wants none");
    [view setString: @"a wor$"];
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(2, 3)], NSMakeRange(2, 3)),
           "and kept when the next character is a $");
    [view setString: @"a  wor  b"];
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(3, 3)], NSMakeRange(2, 4)),
           "with several spaces only one is taken, the one before");
    [view setString: @"a\nwor b"];
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(2, 3)], NSMakeRange(2, 4)),
           "after a line break the space after the word is taken");
    [view setString: @"a,wor b"];
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(2, 3)], NSMakeRange(2, 3)),
           "but not after a comma");
    [view setString: @"\"wor b"];
    expect(NSEqualRanges([view smartDeleteRangeForProposedRange: NSMakeRange(1, 3)], NSMakeRange(1, 4)),
           "after a quote it is taken");

    // the deletion commands do not apply it by themselves (as on macOS)
    [view setString: @"hello world foo"];
    [view setSelectedRange: NSMakeRange(6, 5)];
    [view deleteBackward: nil];
    expect([[view string] isEqualToString: @"hello  foo"], "deleteBackward: deletes exactly the selection");
    [view release];
}

static void setPasteboardString(NSString *string, BOOL smart)
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    if (smart) {
        [pasteboard declareTypes: @[NSStringPboardType, @"NeXT smart paste pasteboard type"] owner: nil];
        [pasteboard setData: [NSData data] forType: @"NeXT smart paste pasteboard type"];
    } else {
        [pasteboard declareTypes: @[NSStringPboardType] owner: nil];
    }
    [pasteboard setString: string forType: NSStringPboardType];
}

static void testPaste(void)
{
    NSTextView *view = makeView(@"hello world");

    setPasteboardString(@"XY", NO);
    [view setSelectedRange: NSMakeRange(5, 0)];
    [view paste: nil];
    expect([[view string] isEqualToString: @"helloXY world"], "plain paste adds no spaces");

    setPasteboardString(@"XY", YES);
    [view setString: @"hello world"];
    [view setSelectedRange: NSMakeRange(5, 0)];
    [view paste: nil];
    expect([[view string] isEqualToString: @"hello XY world"], "paste of smart-copied text adds the space before");
    [view setString: @"hello world"];
    [view setSelectedRange: NSMakeRange(6, 0)];
    [view paste: nil];
    expect([[view string] isEqualToString: @"hello XY world"], "or after");
    [view setString: @"hello world"];
    [view setSelectedRange: NSMakeRange(4, 0)];
    [view paste: nil];
    expect([[view string] isEqualToString: @"hell XY o world"], "or both, inside a word");
    [view setSmartInsertDeleteEnabled: NO];
    [view setString: @"hello world"];
    [view setSelectedRange: NSMakeRange(5, 0)];
    [view paste: nil];
    expect([[view string] isEqualToString: @"helloXY world"], "but not with smart insert and delete off");
    [view setSmartInsertDeleteEnabled: YES];
    [view release];
}

static void testPasteAs(void)
{
    NSTextView *view = makeView(@"ab");
    [view setSmartInsertDeleteEnabled: NO];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    NSAttributedString *rich = [[[NSAttributedString alloc] initWithString: @"rich"
                                                                attributes: @{NSFontAttributeName: [NSFont boldSystemFontOfSize: 20]}] autorelease];
    NSData *rtf = [rich RTFFromRange: NSMakeRange(0, 4) documentAttributes: @{}];
    [pasteboard declareTypes: @[NSRTFPboardType, NSStringPboardType] owner: nil];
    [pasteboard setData: rtf forType: NSRTFPboardType];
    [pasteboard setString: @"rich" forType: NSStringPboardType];

    [view setSelectedRange: NSMakeRange(1, 0)];
    [view paste: nil];
    expect([[view string] isEqualToString: @"arichb"] &&
                   [[[view textStorage] attribute: NSFontAttributeName atIndex: 1 effectiveRange: NULL] pointSize] == 20,
           "paste: takes the rich text");

    [view setString: @"ab"];
    [view setSelectedRange: NSMakeRange(1, 0)];
    [view pasteAsPlainText: nil];
    expect([[view string] isEqualToString: @"arichb"] &&
                   [[[view textStorage] attribute: NSFontAttributeName atIndex: 1 effectiveRange: NULL] pointSize] != 20,
           "pasteAsPlainText: takes the string without its formatting");

    [view setString: @"ab"];
    [view setSelectedRange: NSMakeRange(1, 0)];
    [view pasteAsRichText: nil];
    expect([[view string] isEqualToString: @"arichb"] &&
                   [[[view textStorage] attribute: NSFontAttributeName atIndex: 1 effectiveRange: NULL] pointSize] == 20,
           "pasteAsRichText: takes the rich text");

    [view setRichText: NO];
    [view setString: @"ab"];
    [view setSelectedRange: NSMakeRange(1, 0)];
    [view pasteAsRichText: nil];
    expect([[view string] isEqualToString: @"arichb"], "a plain text view takes rich text as plain text");
    [view setRichText: YES];

    [pasteboard clearContents];
    [pasteboard declareTypes: @[NSStringPboardType] owner: nil];
    [pasteboard setString: @"only string" forType: NSStringPboardType];
    [view setString: @"ab"];
    [view setSelectedRange: NSMakeRange(1, 0)];
    [view pasteAsRichText: nil];
    expect([[view string] isEqualToString: @"ab"], "pasteAsRichText: does nothing when the pasteboard has no rich text");
    [view setEditable: NO];
    [view pasteAsPlainText: nil];
    expect([[view string] isEqualToString: @"ab"], "and nothing is pasted into a view that is not editable");
    [view release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testSmartInsert();
        testSmartDelete();
        testPaste();
        testPasteAs();
    }
    if (failures)
        return 1;
    puts("textview smart insert: PASS");
    return 0;
}
