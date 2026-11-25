/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * -[NSSpellChecker requestCandidatesForSelectedRange:inString:types:options:
 * inSpellDocumentWithTag:completionHandler:], as observed on macOS 26.7.3:
 *  - each request returns a new sequence number, larger than the last, and
 *    the completion handler gets the same number;
 *  - the handler is called on another thread than the main one;
 *  - the candidates replace the word the selection is in or touches, and the
 *    first of them is that word as typed;
 *  - quirk (see the QUIRK comment in NSSpellChecker.m): each candidate's
 *    replacement string ends with a space;
 *  - with no word at the selection, every candidate (macOS offers some to
 *    start a sentence with; Darling offers none) replaces the empty range there.
 * No window server needed.
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

typedef struct {
    NSInteger returned;
    NSInteger handled;
    BOOL onMainThread;
    NSArray<NSTextCheckingResult *> *candidates;
} Request;

static Request request(NSString *string, NSRange selection)
{
    __block Request result = { 0, 0, NO, nil };
    __block BOOL done = NO;
    NSTextCheckingTypes types = NSTextCheckingTypeSpelling | NSTextCheckingTypeReplacement
        | NSTextCheckingTypeCorrection;
    result.returned = [[NSSpellChecker sharedSpellChecker]
        requestCandidatesForSelectedRange: selection
                                 inString: string
                                    types: types
                                  options: nil
                   inSpellDocumentWithTag: [NSSpellChecker uniqueSpellDocumentTag]
                        completionHandler: ^(NSInteger sequenceNumber, NSArray<NSTextCheckingResult *> *candidates) {
        // macOS may call a handler again later; the first call is the answer
        if (done)
            return;
        result.handled = sequenceNumber;
        result.onMainThread = [NSThread isMainThread];
        result.candidates = [candidates copy];
        done = YES;
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 5];
    while (!done && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    expect(done, "the completion handler is called");
    return result;
}

static BOOL allEndWithSpace(NSArray<NSTextCheckingResult *> *candidates)
{
    for (NSTextCheckingResult *candidate in candidates)
        if (![candidate.replacementString hasSuffix: @" "])
            return NO;
    return YES;
}

static BOOL allReplace(NSArray<NSTextCheckingResult *> *candidates, NSRange range)
{
    for (NSTextCheckingResult *candidate in candidates)
        if (!NSEqualRanges(candidate.range, range))
            return NO;
    return YES;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        Request misspelled = request(@"I like teh", NSMakeRange(10, 0));
        expect(misspelled.handled == misspelled.returned, "the handler gets the returned sequence number");
        expect(!misspelled.onMainThread, "the handler is not called on the main thread");
        expect(misspelled.candidates.count > 0, "a word has candidates");
        expect(allReplace(misspelled.candidates, NSMakeRange(7, 3)), "the candidates replace the word before the insertion point");
        expect([misspelled.candidates.firstObject.replacementString isEqualToString: @"teh "], "the first candidate is the word as typed");
        expect(allEndWithSpace(misspelled.candidates), "quirk: a candidate ends with a space");

        Request selected = request(@"I like teh", NSMakeRange(7, 3));
        expect(selected.returned > misspelled.returned, "each request has a larger sequence number");
        expect(allReplace(selected.candidates, NSMakeRange(7, 3)), "the candidates replace the selected word");

        Request partial = request(@"Hello wor", NSMakeRange(9, 0));
        expect(partial.candidates.count > 0
            && [partial.candidates.firstObject.replacementString isEqualToString: @"wor "], "a partial word is the first candidate");
        expect(allReplace(partial.candidates, NSMakeRange(6, 3)), "the candidates replace the partial word");

        Request empty = request(@"", NSMakeRange(0, 0));
        expect(allReplace(empty.candidates, NSMakeRange(0, 0)), "without a word, the candidates replace the empty selection");
    }

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
