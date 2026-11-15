/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextView substitutions by text checking (quotes, dashes, links), the
 * whole-selection and whole-document checks, checking a range, and the
 * checking delegate methods. Expected values were read off macOS 10.14.4 and
 * 26.7.3; both agree. No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSTextView (V613Test)
- (void) checkTextInRange: (NSRange) range types: (NSTextCheckingTypes) types options: (NSDictionary *) options;
- (void) checkTextInSelection: (id) sender;
- (void) checkTextInDocument: (id) sender;
- (void) handleTextCheckingResults: (NSArray *) results forRange: (NSRange) range types: (NSTextCheckingTypes) types
                           options: (NSDictionary *) options orthography: (id) orthography wordCount: (NSInteger) wordCount;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSString *U(const unichar *chars, NSUInteger count)
{
    return [NSString stringWithCharacters: chars length: count];
}

static NSTextView *makeView(NSString *string)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
    [view setEnabledTextCheckingTypes: 0];
    [view setString: string];
    return view;
}

@interface CheckDelegate : NSObject <NSTextViewDelegate> {
@public
    int willCalls, didCalls;
    NSTextCheckingTypes willTypes;
    NSRange willRange;
    NSUInteger didResultCount;
    BOOL dropResults;
}
@end

@implementation CheckDelegate
- (NSDictionary *) textView: (NSTextView *) view willCheckTextInRange: (NSRange) range options: (NSDictionary *) options
                      types: (NSTextCheckingTypes *) types
{
    willCalls++;
    willRange = range;
    willTypes = *types;
    return options;
}
- (NSArray *) textView: (NSTextView *) view didCheckTextInRange: (NSRange) range types: (NSTextCheckingTypes) types
               options: (NSDictionary *) options results: (NSArray *) results orthography: (NSOrthography *) orthography
             wordCount: (NSInteger) wordCount
{
    didCalls++;
    didResultCount = [results count];
    return dropResults ? @[] : results;
}
@end

static void testQuotes(void)
{
    NSTextView *view = makeView(@"f \"q\" g 'x' h it's i \"\"; ' \"unclosed (\"par\")");
    [view setAutomaticQuoteSubstitutionEnabled: YES];
    [view checkTextInDocument: nil];
    unichar expected[] = {'f', ' ', 0x201C, 'q', 0x201D, ' ', 'g', ' ', 0x2018, 'x', 0x2019, ' ', 'h', ' ', 'i', 't', 0x2019, 's', ' ',
                          'i', ' ', 0x201C, 0x201D, ';', ' ', 0x2018, ' ', 0x201C, 'u', 'n', 'c', 'l', 'o', 's', 'e', 'd', ' ', '(',
                          0x201C, 'p', 'a', 'r', 0x201D, ')'};
    expect([[view string] isEqualToString: U(expected, sizeof expected / sizeof *expected)],
           "quote substitution opens after white space and opening brackets and closes elsewhere");
    [view release];
}

static void testDashes(void)
{
    NSTextView *view = makeView(@"a -- b --- c ... d j -- k - l – m n--m");
    [view setAutomaticDashSubstitutionEnabled: YES];
    [view checkTextInDocument: nil];
    unichar expected[] = {'a', ' ', 0x2014, ' ', 'b', ' ', 0x2014, ' ', 'c', ' ', 0x2026, ' ', 'd', ' ', 'j', ' ', 0x2014, ' ', 'k', ' ', '-',
                          ' ', 'l', ' ', 0x2013, ' ', 'm', ' ', 'n', 0x2014, 'm'};
    expect([[view string] isEqualToString: U(expected, sizeof expected / sizeof *expected)],
           "dash substitution: two or three hyphens give an em dash, three dots an ellipsis, a lone hyphen stays");
    [view release];
}

static void testOnlyEnabledTypes(void)
{
    NSTextView *view = makeView(@"\"a\" -- b");
    [view checkTextInDocument: nil];
    expect([[view string] isEqualToString: @"\"a\" -- b"], "nothing changes with no substitution enabled");
    [view setAutomaticQuoteSubstitutionEnabled: YES];
    [view checkTextInDocument: nil];
    unichar quotes[] = {0x201C, 'a', 0x201D, ' ', '-', '-', ' ', 'b'};
    expect([[view string] isEqualToString: U(quotes, 8)], "only the enabled substitution is applied");
    [view release];
}

static void testSelectionAndRange(void)
{
    NSTextView *view = makeView(@"\"a\" \"b\"");
    [view setAutomaticQuoteSubstitutionEnabled: YES];
    [view setSelectedRange: NSMakeRange(0, 3)];
    [view checkTextInSelection: nil];
    unichar first[] = {0x201C, 'a', 0x201D, ' ', '"', 'b', '"'};
    expect([[view string] isEqualToString: U(first, 7)], "checkTextInSelection: changes only the selection");
    [view release];

    // checking a range does not replace text that was not typed
    view = makeView(@"\"a\" -- b");
    [view setAutomaticQuoteSubstitutionEnabled: YES];
    [view setAutomaticDashSubstitutionEnabled: YES];
    [view checkTextInRange: NSMakeRange(0, [[view string] length])
                     types: NSTextCheckingTypeQuote | NSTextCheckingTypeDash
                   options: @{}];
    expect([[view string] isEqualToString: @"\"a\" -- b"], "checkTextInRange:types:options: leaves text that was not typed alone");
    BOOL raised = NO;
    @try {
        [view checkTextInRange: NSMakeRange(0, 100) types: NSTextCheckingTypeQuote options: @{}];
    } @catch (NSException *e) {
        raised = YES;
    }
    expect(!raised && [[view string] isEqualToString: @"\"a\" -- b"], "a range beyond the text is cut to the text and raises nothing");
    [view release];

    // the selection of text is kept relative to its text
    view = makeView(@"a -- b");
    [view setAutomaticDashSubstitutionEnabled: YES];
    [view setSelectedRange: NSMakeRange(5, 0)];
    [view checkTextInDocument: nil];
    expect(NSEqualRanges([view selectedRange], NSMakeRange(4, 0)), "the insertion point stays behind the same text");
    [view release];
}

static void testLinks(void)
{
    NSTextView *view = makeView(@"see http://example.com/a?b=c, www.example.org and mailto:a@b.co. ftp://h/p x@y.com plain text");
    [view setAutomaticLinkDetectionEnabled: YES];
    [view checkTextInDocument: nil];
    NSString *string = [view string];

    NSRange first = [string rangeOfString: @"http://example.com/a?b=c"];
    NSURL *url = [[view textStorage] attribute: NSLinkAttributeName atIndex: first.location effectiveRange: NULL];
    expect([url isKindOfClass: [NSURL class]] && [[url absoluteString] isEqualToString: @"http://example.com/a?b=c"],
           "a URL with a scheme becomes a link");
    expect([[view textStorage] attribute: NSLinkAttributeName atIndex: NSMaxRange(first) effectiveRange: NULL] == nil,
           "the trailing comma is not part of it");

    NSRange www = [string rangeOfString: @"www.example.org"];
    url = [[view textStorage] attribute: NSLinkAttributeName atIndex: www.location effectiveRange: NULL];
    expect([[url absoluteString] isEqualToString: @"http://www.example.org"], "www. gets http://");

    NSRange mailto = [string rangeOfString: @"mailto:a@b.co"];
    url = [[view textStorage] attribute: NSLinkAttributeName atIndex: mailto.location effectiveRange: NULL];
    expect([[url absoluteString] isEqualToString: @"mailto:a@b.co"], "a mailto: URL");
    expect([[view textStorage] attribute: NSLinkAttributeName atIndex: NSMaxRange(mailto) effectiveRange: NULL] == nil,
           "without the full stop");

    NSRange ftp = [string rangeOfString: @"ftp://h/p"];
    url = [[view textStorage] attribute: NSLinkAttributeName atIndex: ftp.location effectiveRange: NULL];
    expect([[url absoluteString] isEqualToString: @"ftp://h/p"], "an ftp URL");

    NSRange address = [string rangeOfString: @"x@y.com"];
    url = [[view textStorage] attribute: NSLinkAttributeName atIndex: address.location effectiveRange: NULL];
    expect([[url absoluteString] isEqualToString: @"mailto:x@y.com"], "an e-mail address gets mailto:");

    NSRange plain = [string rangeOfString: @"plain"];
    expect([[view textStorage] attribute: NSLinkAttributeName atIndex: plain.location effectiveRange: NULL] == nil,
           "ordinary words are not links");
    [view release];
}

static void testDelegate(void)
{
    NSTextView *view = makeView(@"\"a\"");
    [view setAutomaticQuoteSubstitutionEnabled: YES];
    CheckDelegate *delegate = [[CheckDelegate alloc] init];
    [view setDelegate: delegate];
    [view checkTextInDocument: nil];
    expect(delegate->willCalls == 1 && NSEqualRanges(delegate->willRange, NSMakeRange(0, 3)) &&
                   (delegate->willTypes & NSTextCheckingTypeQuote),
           "the delegate is asked before checking, with the range and the types");
    expect(delegate->didCalls == 1 && delegate->didResultCount == 2, "and told the results afterwards (one per quote)");

    [view setString: @"\"a\""];
    delegate->dropResults = YES;
    [view checkTextInDocument: nil];
    expect([[view string] isEqualToString: @"\"a\""], "the delegate can drop the results");
    [view setDelegate: nil];
    [delegate release];
    [view release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testQuotes();
        testDashes();
        testOnlyEnabledTypes();
        testSelectionAndRange();
        testLinks();
        testDelegate();
    }
    if (failures)
        return 1;
    puts("textview text checking: PASS");
    return 0;
}
