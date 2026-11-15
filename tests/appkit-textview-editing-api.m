/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextView change delegation (single and multiple ranges, typing
 * attributes), the ranges for user changes, marked text, pasteboard types,
 * menu validation, text container replacement and geometry helpers. Expected
 * values come from macOS 10.14.4 and 26.7.3. No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSTextView (V613Test)
- (NSArray *) rangesForUserTextChange;
- (NSArray *) rangesForUserCharacterAttributeChange;
- (NSArray *) rangesForUserParagraphAttributeChange;
- (BOOL) shouldChangeTextInRanges: (NSArray *) ranges replacementStrings: (NSArray *) strings;
- (BOOL) performValidatedReplacementInRange: (NSRange) range withAttributedString: (NSAttributedString *) string;
- (void) setAlignment: (NSTextAlignment) alignment range: (NSRange) range;
- (void) setConstrainedFrameSize: (NSSize) size;
- (NSUInteger) characterIndexForInsertionAtPoint: (NSPoint) point;
- (void) replaceTextContainer: (NSTextContainer *) container;
- (void) invalidateTextContainerOrigin;
- (NSArray *) readablePasteboardTypes;
- (NSString *) preferredPasteboardTypeFromArray: (NSArray *) available restrictedToTypesFromArray: (NSArray *) allowed;
- (BOOL) readSelectionFromPasteboard: (NSPasteboard *) pasteboard;
- (void) toggleAutomaticQuoteSubstitution: (id) sender;
- (void) toggleSmartInsertDelete: (id) sender;
- (void) toggleGrammarChecking: (id) sender;
- (void) turnOffLigatures: (id) sender;
- (void) clickedOnLink: (id) link atIndex: (NSUInteger) index;
- (NSWritingDirection) baseWritingDirection;
- (void) setBaseWritingDirection: (NSWritingDirection) direction;
@end

@interface NSTextView (V613TestPrivate)
- (NSArray *) writablePasteboardTypes;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL equalRange(NSValue *value, NSUInteger location, NSUInteger length)
{
    return NSEqualRanges([value rangeValue], NSMakeRange(location, length));
}

@interface BothDelegate : NSObject <NSTextViewDelegate> {
@public
    int rangesCalls, singleCalls, typingCalls, typingNotes, linkCalls;
    NSArray *lastRanges;
    NSArray *lastStrings;
    NSRange lastSingle;
    NSString *lastSingleString;
    BOOL veto;
    NSString *lastLink;
    NSUInteger lastLinkIndex;
    BOOL linkResult;
    NSDictionary *typingReplacement;
}
@end

@implementation BothDelegate
- (BOOL) textView: (NSTextView *) textView shouldChangeTextInRanges: (NSArray *) ranges replacementStrings: (NSArray *) strings
{
    rangesCalls++;
    [lastRanges release];
    lastRanges = [ranges retain];
    [lastStrings release];
    lastStrings = [strings retain];
    return !veto;
}
- (BOOL) textView: (NSTextView *) textView shouldChangeTextInRange: (NSRange) range replacementString: (NSString *) string
{
    singleCalls++;
    lastSingle = range;
    [lastSingleString release];
    lastSingleString = [string retain];
    return YES;
}
- (NSDictionary *) textView: (NSTextView *) textView
        shouldChangeTypingAttributes: (NSDictionary *) old
                        toAttributes: (NSDictionary *) new
{
    typingCalls++;
    return typingReplacement != nil ? typingReplacement : new;
}
- (void) textViewDidChangeTypingAttributes: (NSNotification *) note
{
    typingNotes++;
}
- (BOOL) textView: (NSTextView *) textView clickedOnLink: (id) link atIndex: (NSUInteger) index
{
    linkCalls++;
    [lastLink release];
    lastLink = [[link description] retain];
    lastLinkIndex = index;
    return linkResult;
}
@end

@interface SingleDelegate : NSObject <NSTextViewDelegate> {
@public
    int singleCalls;
    NSRange lastSingle;
    NSString *lastString;
}
@end

@implementation SingleDelegate
- (BOOL) textView: (NSTextView *) textView shouldChangeTextInRange: (NSRange) range replacementString: (NSString *) string
{
    singleCalls++;
    lastSingle = range;
    lastString = string;
    return YES;
}
@end

static NSTextView *makeView(NSString *string)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
    [view setString: string];
    return view;
}

static void testRangesForUserChange(void)
{
    NSTextView *view = makeView(@"hello world");
    [view setSelectedRange: NSMakeRange(2, 3)];
    expect([[view rangesForUserTextChange] count] == 1 && equalRange([[view rangesForUserTextChange] objectAtIndex: 0], 2, 3),
           "rangesForUserTextChange is the selection");
    expect(equalRange([[view rangesForUserCharacterAttributeChange] objectAtIndex: 0], 2, 3),
           "rich text: character attribute change range is the selection");
    expect(equalRange([[view rangesForUserParagraphAttributeChange] objectAtIndex: 0], 0, 11),
           "rich text: paragraph attribute change range is the paragraph");
    [view setRichText: NO];
    expect(equalRange([[view rangesForUserCharacterAttributeChange] objectAtIndex: 0], 0, 11),
           "plain text: character attribute change range is all the text");
    [view setRichText: YES];
    [view setEditable: NO];
    expect([view rangesForUserTextChange] == nil || [[view rangesForUserTextChange] count] == 0,
           "no ranges for a change when the view is not editable");
    expect(![view shouldChangeTextInRanges: @[[NSValue valueWithRange: NSMakeRange(0, 1)]] replacementStrings: @[@"x"]],
           "shouldChangeTextInRanges: is NO when not editable");
    [view release];
}

static void testDelegateChangeRanges(void)
{
    NSTextView *view = makeView(@"abcdef");
    BothDelegate *delegate = [[BothDelegate alloc] init];
    [view setDelegate: delegate];
    [view setSelectedRange: NSMakeRange(1, 3)];

    // QUIRK test: a delegate that has both forms is asked only the ranges form.
    expect([view shouldChangeTextInRange: NSMakeRange(1, 2) replacementString: @"x"], "single-range check passes");
    expect(delegate->rangesCalls == 1 && delegate->singleCalls == 0, "the ranges form is asked, the single form is not");
    expect([delegate->lastRanges count] == 1 && equalRange([delegate->lastRanges objectAtIndex: 0], 1, 2),
           "the range is passed as a one-element array");
    expect([delegate->lastStrings isEqualToArray: @[@"x"]], "with the replacement string");

    [view shouldChangeTextInRange: NSMakeRange(1, 2) replacementString: nil];
    expect(delegate->lastStrings == nil, "an attribute-only change has nil replacement strings");

    NSArray *ranges = @[[NSValue valueWithRange: NSMakeRange(0, 1)], [NSValue valueWithRange: NSMakeRange(2, 1)]];
    NSArray *strings = @[@"a", @"b"];
    [view shouldChangeTextInRanges: ranges replacementStrings: strings];
    expect([delegate->lastRanges isEqualToArray: ranges] && [delegate->lastStrings isEqualToArray: strings],
           "several ranges and strings are passed on");

    delegate->veto = YES;
    expect(![view shouldChangeTextInRanges: ranges replacementStrings: strings], "the delegate can veto");
    delegate->veto = NO;

    // user edits ask; programmatic changes do not
    delegate->rangesCalls = 0;
    [view setString: @"zz"];
    [view replaceCharactersInRange: NSMakeRange(0, 1) withString: @"y"];
    expect(delegate->rangesCalls == 0, "setString: and replaceCharactersInRange:withString: do not ask the delegate");
    [view setSelectedRange: NSMakeRange(0, 1)];
    [view insertText: @"Q" replacementRange: NSMakeRange(NSNotFound, 0)];
    expect(delegate->rangesCalls == 1 && equalRange([delegate->lastRanges objectAtIndex: 0], 0, 1) &&
                   [delegate->lastStrings isEqualToArray: @[@"Q"]],
           "insertText: asks with the selection and the string");
    expect([[view string] isEqualToString: @"Qz"], "and inserts");

    delegate->rangesCalls = 0;
    [view setSelectedRange: NSMakeRange(0, 1)];
    [view deleteBackward: nil];
    expect(delegate->rangesCalls == 1 && [delegate->lastStrings isEqualToArray: @[@""]],
           "deleting asks with an empty replacement string");

    delegate->veto = YES;
    [view setString: @"keep"];
    [view setSelectedRange: NSMakeRange(0, 4)];
    [view insertText: @"no" replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"keep"], "a vetoed insertion does not change the text");
    delegate->veto = NO;

    // performValidatedReplacement goes through the same check
    delegate->rangesCalls = 0;
    expect([view performValidatedReplacementInRange: NSMakeRange(0, 1)
                               withAttributedString: [[[NSAttributedString alloc] initWithString: @"RR"] autorelease]] &&
                   [[view string] isEqualToString: @"RReep"] && delegate->rangesCalls == 1,
           "performValidatedReplacementInRange:withAttributedString: validates and replaces");
    delegate->veto = YES;
    expect(![view performValidatedReplacementInRange: NSMakeRange(0, 1)
                                withAttributedString: [[[NSAttributedString alloc] initWithString: @"Z"] autorelease]],
           "and returns NO when vetoed");
    delegate->veto = NO;
    BOOL raised = NO;
    @try {
        [view performValidatedReplacementInRange: NSMakeRange(100, 1)
                            withAttributedString: [[[NSAttributedString alloc] initWithString: @"Z"] autorelease]];
    } @catch (NSException *e) {
        raised = [[e name] isEqualToString: NSRangeException];
    }
    expect(raised, "a range beyond the text raises NSRangeException");

    [view setDelegate: nil];
    [delegate release];
    [view release];

    // a delegate with only the single-range method is asked that
    view = makeView(@"abcdef");
    SingleDelegate *single = [[SingleDelegate alloc] init];
    [view setDelegate: single];
    [view shouldChangeTextInRanges: @[[NSValue valueWithRange: NSMakeRange(2, 2)]] replacementStrings: @[@"w"]];
    expect(single->singleCalls == 1 && NSEqualRanges(single->lastSingle, NSMakeRange(2, 2)) &&
                   [single->lastString isEqualToString: @"w"],
           "the single-range method is used when it is the only one");
    [view setDelegate: nil];
    [single release];
    [view release];
}

static void testTypingAttributesDelegation(void)
{
    NSTextView *view = makeView(@"abcdef");
    BothDelegate *delegate = [[BothDelegate alloc] init];
    [view setDelegate: delegate];
    delegate->typingCalls = delegate->typingNotes = 0;

    NSDictionary *bold = @{NSFontAttributeName: [NSFont boldSystemFontOfSize: 20]};
    [view setTypingAttributes: bold];
    expect(delegate->typingCalls == 1 && delegate->typingNotes == 1, "a typing attributes change goes through the delegate and is announced");
    expect([[view typingAttributes] objectForKey: NSFontAttributeName] != nil, "the new attributes are in effect");

    delegate->typingReplacement = @{NSFontAttributeName: [NSFont systemFontOfSize: 9]};
    [view setTypingAttributes: @{NSFontAttributeName: [NSFont systemFontOfSize: 30]}];
    expect([[[view typingAttributes] objectForKey: NSFontAttributeName] pointSize] == 9,
           "the delegate's replacement dictionary is used");
    delegate->typingReplacement = nil;

    [view setSelectedRange: NSMakeRange(1, 3)];
    [view turnOffLigatures: nil];
    expect([[view typingAttributes] objectForKey: NSLigatureAttributeName] != nil,
           "attribute commands change the typing attributes");
    [view setDelegate: nil];
    [delegate release];
    [view release];
}

static void testMarkedText(void)
{
    NSTextView *view = makeView(@"abcdef");
    [view setSelectedRange: NSMakeRange(3, 0)];

    expect(![view hasMarkedText], "no marked text at first");
    // QUIRK test: the marked range of a view without marked text is {length, 0}.
    expect(NSEqualRanges([view markedRange], NSMakeRange(6, 0)), "marked range without marked text is {length, 0}");

    [view setMarkedText: @"XY" selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"abcXYdef"] && [view hasMarkedText] &&
                   NSEqualRanges([view markedRange], NSMakeRange(3, 2)) && NSEqualRanges([view selectedRange], NSMakeRange(4, 0)),
           "marked text is inserted at the selection, marked, and the selection is inside it");

    [view setMarkedText: @"XYZ" selectedRange: NSMakeRange(2, 1) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"abcXYZdef"] && NSEqualRanges([view markedRange], NSMakeRange(3, 3)) &&
                   NSEqualRanges([view selectedRange], NSMakeRange(5, 1)),
           "new marked text replaces the old");

    [view setMarkedText: [[[NSAttributedString alloc] initWithString: @"Q"
                                                          attributes: @{NSUnderlineStyleAttributeName: @1}] autorelease]
          selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"abcQdef"] && [view hasMarkedText], "an attributed string is accepted");
    expect([[view textStorage] attribute: NSUnderlineStyleAttributeName atIndex: 3 effectiveRange: NULL] == nil,
           "its attributes are not stored in the text");

    [view unmarkText];
    expect([[view string] isEqualToString: @"abcQdef"] && ![view hasMarkedText] &&
                   NSEqualRanges([view markedRange], NSMakeRange(7, 0)),
           "unmarkText keeps the text and ends marking");

    [view setMarkedText: @"M" selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    [view insertText: @"N" replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"abcQNdef"] && ![view hasMarkedText],
           "inserting text replaces the marked text and ends marking");

    [view setMarkedText: @"MM" selectedRange: NSMakeRange(2, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    [view setMarkedText: @"" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"abcQNdef"] && ![view hasMarkedText], "empty marked text removes the marked text");

    [view setMarkedText: @"" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"abcQNdef"], "empty marked text with none marked does nothing");

    [view setString: @"abcdef"];
    [view setSelectedRange: NSMakeRange(1, 2)];
    [view setMarkedText: @"Z" selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[view string] isEqualToString: @"aZdef"] && NSEqualRanges([view markedRange], NSMakeRange(1, 1)),
           "marked text replaces the selection");
    [view unmarkText];

    [view setString: @"abcdef"];
    [view setMarkedText: @"Z" selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(4, 2)];
    expect([[view string] isEqualToString: @"abcdZ"] && NSEqualRanges([view markedRange], NSMakeRange(4, 1)),
           "a replacement range is replaced when nothing is marked");
    [view unmarkText];

    [view setString: @"abcdef"];
    [view setSelectedRange: NSMakeRange(3, 0)];
    [view setMarkedText: @"XY" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    [view setSelectedRange: NSMakeRange(0, 0)];
    expect([[view string] isEqualToString: @"abcXYdef"] && ![view hasMarkedText],
           "moving the selection ends marking and keeps the text");

    [view setString: @"abcdef"];
    [view setSelectedRange: NSMakeRange(3, 0)];
    [view setMarkedText: @"XY" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    [view setString: @"new"];
    expect(![view hasMarkedText], "setString: ends marking");

    [view setString: @"abcdef"];
    [view setSelectedRange: NSMakeRange(3, 0)];
    [view setMarkedText: @"XY" selectedRange: NSMakeRange(2, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    [view deleteBackward: nil];
    expect([[view string] isEqualToString: @"abcXdef"] && ![view hasMarkedText],
           "deleting backward deletes before the caret and ends marking");

    NSArray *valid = [view validAttributesForMarkedText];
    expect([valid containsObject: NSUnderlineStyleAttributeName] && [valid containsObject: NSFontAttributeName] &&
                   [valid containsObject: NSBackgroundColorAttributeName] && [valid containsObject: NSForegroundColorAttributeName],
           "valid marked text attributes include underline, font and colours");
    expect([[view markedTextAttributes] objectForKey: NSBackgroundColorAttributeName] != nil &&
                   [[view markedTextAttributes] objectForKey: NSForegroundColorAttributeName] != nil,
           "default marked text attributes set a background and a foreground colour");

    // notifications: marking asks the delegate, committing announces the change
    BothDelegate *delegate = [[BothDelegate alloc] init];
    [view setDelegate: delegate];
    [view setString: @"abcdef"];
    [view setSelectedRange: NSMakeRange(3, 0)];
    delegate->rangesCalls = 0;
    [view setMarkedText: @"XY" selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect(delegate->rangesCalls >= 1 && equalRange([delegate->lastRanges lastObject], 3, 0) &&
                   [delegate->lastStrings isEqualToArray: @[@"XY"]],
           "setMarkedText: asks the delegate about the change");
    [view setDelegate: nil];
    [delegate release];

    NSTextView *fixed = makeView(@"abc");
    [fixed setEditable: NO];
    [fixed setSelectedRange: NSMakeRange(1, 0)];
    [fixed setMarkedText: @"X" selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    expect([[fixed string] isEqualToString: @"abc"] && ![fixed hasMarkedText], "marking does nothing in a view that is not editable");
    [fixed release];
    [view release];
}

static void testPasteboardTypes(void)
{
    NSTextView *view = makeView(@"hello");
    expect([[view writablePasteboardTypes] count] == 0, "nothing is writable without a selection");
    [view setSelectedRange: NSMakeRange(1, 2)];
    NSArray *writable = [view writablePasteboardTypes];
    expect([writable containsObject: NSStringPboardType] && [writable containsObject: NSRTFPboardType],
           "rich text writes RTF and a string");
    [view setRichText: NO];
    expect([[view writablePasteboardTypes] isEqualToArray: @[NSStringPboardType]], "plain text writes only a string");
    [view setRichText: YES];

    NSArray *readable = [view readablePasteboardTypes];
    expect([readable containsObject: NSStringPboardType] && [readable containsObject: NSRTFPboardType], "readable types");
    expect([readable indexOfObject: NSRTFPboardType] < [readable indexOfObject: NSStringPboardType], "rich text is preferred to plain text");
    expect([[view preferredPasteboardTypeFromArray: @[NSStringPboardType, NSRTFPboardType] restrictedToTypesFromArray: nil]
                   isEqualToString: NSRTFPboardType],
           "the preferred type comes from the readable order, not the available order");
    expect([view preferredPasteboardTypeFromArray: @[NSStringPboardType] restrictedToTypesFromArray: @[NSRTFPboardType]] == nil,
           "restricted to a type that is not available gives nil");
    expect([view preferredPasteboardTypeFromArray: @[@"foo.bar"] restrictedToTypesFromArray: nil] == nil, "an unknown type gives nil");
    expect([[view preferredPasteboardTypeFromArray: @[NSStringPboardType] restrictedToTypesFromArray: @[NSStringPboardType]]
                   isEqualToString: NSStringPboardType],
           "restricted to an available type gives that type");

    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [pasteboard declareTypes: @[NSStringPboardType] owner: nil];
    [pasteboard setString: @"rs" forType: NSStringPboardType];
    [view setString: @"ab"];
    [view setSelectedRange: NSMakeRange(1, 0)];
    expect([view readSelectionFromPasteboard: pasteboard] && [[view string] isEqualToString: @"arsb"],
           "readSelectionFromPasteboard: reads the preferred type");
    [pasteboard releaseGlobally];

    [view setEditable: NO];
    expect([[view readablePasteboardTypes] count] == 0, "nothing is readable when not editable");
    [view release];
}

static void testMenuValidation(void)
{
    NSTextView *view = makeView(@"x");
    NSMenuItem *quote = [[[NSMenuItem alloc] initWithTitle: @"q" action: @selector(toggleAutomaticQuoteSubstitution:) keyEquivalent: @""] autorelease];
    [view setAutomaticQuoteSubstitutionEnabled: NO];
    expect([view validateMenuItem: quote] && [quote state] == NSOffState, "the quote toggle is enabled and off");
    [view setAutomaticQuoteSubstitutionEnabled: YES];
    [view validateMenuItem: quote];
    expect([quote state] == NSOnState, "and on once the setting is on");
    NSMenuItem *smart = [[[NSMenuItem alloc] initWithTitle: @"s" action: @selector(toggleSmartInsertDelete:) keyEquivalent: @""] autorelease];
    [view setSmartInsertDeleteEnabled: NO];
    [view validateMenuItem: smart];
    expect([smart state] == NSOffState, "smart insert toggle shows its state");
    NSMenuItem *ligatures = [[[NSMenuItem alloc] initWithTitle: @"l" action: @selector(turnOffLigatures:) keyEquivalent: @""] autorelease];
    expect([view validateMenuItem: ligatures], "font commands are enabled in an editable view");
    [view setEditable: NO];
    expect(![view validateMenuItem: ligatures] && ![view validateMenuItem: quote], "and disabled when not editable");

    NSTextView *toggled = makeView(@"x");
    BOOL before = [toggled isAutomaticQuoteSubstitutionEnabled];
    [toggled toggleAutomaticQuoteSubstitution: nil];
    expect([toggled isAutomaticQuoteSubstitutionEnabled] == !before, "toggleAutomaticQuoteSubstitution: flips");
    before = [toggled smartInsertDeleteEnabled];
    [toggled toggleSmartInsertDelete: nil];
    expect([toggled smartInsertDeleteEnabled] == !before, "toggleSmartInsertDelete: flips");
    before = [toggled isGrammarCheckingEnabled];
    [toggled toggleGrammarChecking: nil];
    expect([toggled isGrammarCheckingEnabled] == !before, "toggleGrammarChecking: flips");
    [toggled release];
    [view release];
}

static void testGeometry(void)
{
    NSTextView *view = makeView(@"hello world");
    [view setHorizontallyResizable: NO];
    [view setVerticallyResizable: YES];
    [view setMinSize: NSMakeSize(10, 10)];
    [view setMaxSize: NSMakeSize(500, 400)];
    [view setConstrainedFrameSize: NSMakeSize(50, 2000)];
    expect([view frame].size.width == 300 && [view frame].size.height == 400,
           "setConstrainedFrameSize: keeps the width of a view that does not resize horizontally and limits the height");
    [view setConstrainedFrameSize: NSMakeSize(700, 2)];
    expect([view frame].size.width == 300 && [view frame].size.height == 10, "and raises the height to the minimum");
    [view release];

    view = makeView(@"hello world");
    NSTextContainer *old = [view textContainer];
    NSLayoutManager *layoutManager = [view layoutManager];
    NSTextStorage *storage = [view textStorage];
    NSTextContainer *replacement = [[[NSTextContainer alloc] initWithContainerSize: NSMakeSize(123, 10000000)] autorelease];
    [view replaceTextContainer: replacement];
    expect([view textContainer] == replacement, "the view has the new container");
    expect([old textView] == nil, "the old container lost the view");
    expect([view layoutManager] == layoutManager && [view textStorage] == storage, "layout manager and storage stay");
    expect([[layoutManager textContainers] count] == 1 && [[layoutManager textContainers] objectAtIndex: 0] == replacement,
           "the new container replaced the old one in the layout manager");
    expect([replacement textView] == view, "and knows the view");
    expect([[view string] isEqualToString: @"hello world"], "the text is untouched");
    [view invalidateTextContainerOrigin];
    [view release];

    view = makeView(@"hello world");
    [view setFrame: NSMakeRect(0, 0, 300, 100)];
    NSUInteger length = [[view string] length];
    expect([view characterIndexForInsertionAtPoint: NSMakePoint(-50, 5)] == 0, "left of the text is the start");
    expect([view characterIndexForInsertionAtPoint: NSMakePoint(280, 5)] == length, "right of the line is the end of the line");
    expect([view characterIndexForInsertionAtPoint: NSMakePoint(20, 900)] == length, "below the text is the end");
    expect([view characterIndexForInsertionAtPoint: NSMakePoint(30, -900)] == 0, "above the text is the start");
    [view release];

    view = makeView(@"one\ntwo");
    [view setAlignment: NSTextAlignmentCenter range: NSMakeRange(0, 2)];
    NSParagraphStyle *first = [[view textStorage] attribute: NSParagraphStyleAttributeName atIndex: 0 effectiveRange: NULL];
    NSParagraphStyle *second = [[view textStorage] attribute: NSParagraphStyleAttributeName atIndex: 5 effectiveRange: NULL];
    expect([first alignment] == NSTextAlignmentCenter, "setAlignment:range: aligns the paragraph the range touches");
    expect(second == nil || [second alignment] != NSTextAlignmentCenter, "and only that one");
    BOOL raised = NO;
    @try {
        [view setAlignment: NSTextAlignmentRight range: NSMakeRange(0, 100)];
    } @catch (NSException *e) {
        raised = [[e name] isEqualToString: NSRangeException];
    }
    expect(raised, "a range beyond the text raises NSRangeException");
    [view release];
}

static NSWritingDirection paragraphDirection(NSTextView *view, NSUInteger index)
{
    NSParagraphStyle *style = [[view textStorage] attribute: NSParagraphStyleAttributeName atIndex: index effectiveRange: NULL];
    return style != nil ? [style baseWritingDirection] : (NSWritingDirection) -99;
}

static void testBaseWritingDirection(void)
{
    NSTextView *view = makeView(@"abc\ndef\nghi");
    expect([view baseWritingDirection] == NSWritingDirectionNatural, "the base writing direction starts out natural");
    [view setSelectedRange: NSMakeRange(5, 1)];
    [view setBaseWritingDirection: NSWritingDirectionRightToLeft];
    expect(paragraphDirection(view, 0) == NSWritingDirectionRightToLeft && paragraphDirection(view, 5) == NSWritingDirectionRightToLeft &&
                   paragraphDirection(view, 10) == NSWritingDirectionRightToLeft,
           "setBaseWritingDirection: changes every paragraph, not just the selection's");
    expect([view baseWritingDirection] == NSWritingDirectionRightToLeft, "and is read back");
    [view setEditable: NO];
    [view setBaseWritingDirection: NSWritingDirectionLeftToRight];
    expect([view baseWritingDirection] == NSWritingDirectionLeftToRight, "also in a view that is not editable");
    [view release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testBaseWritingDirection();
        testRangesForUserChange();
        testDelegateChangeRanges();
        testTypingAttributesDelegation();
        testMarkedText();
        testPasteboardTypes();
        testMenuValidation();
        testGeometry();
    }
    if (failures)
        return 1;
    puts("textview editing api: PASS");
    return 0;
}
