/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * -[NSTextView replaceTextStorage:], writing direction over a range, stored
 * text view flags, the automatic substitution settings of NSSpellChecker and
 * the nil-selection quirk of -setSelectedRanges:. No window server needed.
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

// QUIRK test: pins the nil-ranges behaviour in -setSelectedRanges:.
static void test_quirk_nil_selected_ranges_is_ignored(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    [view setString: @"hello world"];
    [view setSelectedRange: NSMakeRange(2, 3)];
    [view setSelectedRanges: nil];
    expect(NSEqualRanges([view selectedRange], NSMakeRange(2, 3)),
           "nil ranges leave the selection alone");
    BOOL raised = NO;
    @try {
        [view setSelectedRanges: @[]];
    } @catch (NSException *e) {
        raised = [[e name] isEqualToString: NSInvalidArgumentException];
    }
    expect(raised, "an empty array raises NSInvalidArgumentException");
}

static void testReplaceTextStorage(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    [view setString: @"first"];
    [view setSelectedRange: NSMakeRange(0, 5)];
    NSLayoutManager *manager = [view layoutManager];
    NSTextStorage *old = [view textStorage];
    NSTextStorage *replacement = [[NSTextStorage alloc] initWithString: @"hi"];
    [view replaceTextStorage: replacement];
    expect([view textStorage] == replacement, "the view uses the new storage");
    expect([manager textStorage] == replacement, "the layout manager uses the new storage");
    expect([[view string] isEqualToString: @"hi"], "the view shows the new string");
    expect([[old layoutManagers] indexOfObjectIdenticalTo: manager] == NSNotFound,
           "the old storage no longer lists the layout manager");
    expect(NSMaxRange([view selectedRange]) <= 2, "the selection is clamped to the new length");
}

static void testWritingDirectionAndFlags(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    [view setString: @"abc\ndef"];
    [view setBaseWritingDirection: NSWritingDirectionRightToLeft range: NSMakeRange(0, 3)];
    NSParagraphStyle *first = [[view textStorage] attribute: NSParagraphStyleAttributeName
                                                     atIndex: 0 effectiveRange: NULL];
    NSParagraphStyle *second = [[view textStorage] attribute: NSParagraphStyleAttributeName
                                                      atIndex: 5 effectiveRange: NULL];
    expect([first baseWritingDirection] == NSWritingDirectionRightToLeft,
           "the paragraph in the range changes direction");
    expect(second == nil || [second baseWritingDirection] != NSWritingDirectionRightToLeft,
           "the other paragraph keeps its direction");

    [view setImportsGraphics: YES];
    expect([view importsGraphics], "importsGraphics is stored");
    expect([view layoutOrientation] == NSTextLayoutOrientationHorizontal, "horizontal by default");
    [view changeLayoutOrientation: nil];
    expect([view layoutOrientation] == NSTextLayoutOrientationVertical,
           "changeLayoutOrientation: toggles to vertical");
}

static void testSpellCheckerSettings(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *keys = @[@"NSAutomaticCapitalizationEnabled", @"NSAutomaticPeriodSubstitutionEnabled",
                      @"NSAutomaticTextCompletionEnabled"];
    for (NSString *key in keys)
        [defaults removeObjectForKey: key];
    expect(![NSSpellChecker isAutomaticCapitalizationEnabled], "capitalization is off when unset");
    [defaults setBool: YES forKey: @"NSAutomaticCapitalizationEnabled"];
    [defaults setBool: YES forKey: @"NSAutomaticPeriodSubstitutionEnabled"];
    [defaults setBool: YES forKey: @"NSAutomaticTextCompletionEnabled"];
    expect([NSSpellChecker isAutomaticCapitalizationEnabled], "capitalization follows the default");
    expect([NSSpellChecker isAutomaticPeriodSubstitutionEnabled], "period substitution follows the default");
    expect([NSSpellChecker isAutomaticTextCompletionEnabled], "completion follows the default");
    for (NSString *key in keys)
        [defaults removeObjectForKey: key];
}

int main(void)
{
    @autoreleasepool {
        test_quirk_nil_selected_ranges_is_ignored();
        testReplaceTextStorage();
        testWritingDirectionAndFlags();
        testSpellCheckerSettings();
    }
    if (failures)
        return 1;
    puts("text system settings: PASS");
    return 0;
}
