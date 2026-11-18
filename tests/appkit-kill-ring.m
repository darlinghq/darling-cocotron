/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>

// The kill ring behind NSTextView's deleteToXXX/yank commands and the
// _NSxxxKillRing functions text engines call. Written to also run unchanged
// on macOS (resolving the functions through dlsym).

static void (*InitRing)(void);
static void (*AppendRing)(NSString *);
static void (*NewSequence)(void);
static void (*SetYanked)(void);
static NSString *(*YankRing)(void);
static int failures;

#define CHECK(cond, what)                                                      \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL: %s\n", what);                                        \
            failures++;                                                        \
        }                                                                      \
    } while (0)

static BOOL isString(NSString *a, NSString *b) {
    return a != nil && [a isEqualToString: b];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        InitRing = dlsym(RTLD_DEFAULT, "_NSInitializeKillRing");
        AppendRing = dlsym(RTLD_DEFAULT, "_NSAppendToKillRing");
        NewSequence = dlsym(RTLD_DEFAULT, "_NSNewKillRingSequence");
        SetYanked = dlsym(RTLD_DEFAULT, "_NSSetKillRingToYankedState");
        YankRing = dlsym(RTLD_DEFAULT, "_NSYankFromKillRing");
        if (!InitRing || !AppendRing || !NewSequence || !SetYanked || !YankRing) {
            printf("FAIL: kill ring functions missing\n");
            return 1;
        }

        // test_quirk_*: behaviour observed on macOS, see NSKillRing.m.
        InitRing();
        InitRing(); // idempotent
        NewSequence();
        CHECK(isString(YankRing(), @""), "yank of an empty entry is the empty string");
        NewSequence();
        AppendRing(@"abc");
        AppendRing(@"def");
        AppendRing(@"ghi");
        CHECK(isString(YankRing(), @"abcdefghi"), "appends accumulate in one entry");
        CHECK(isString(YankRing(), @"abcdefghi"), "a second yank returns the same entry");
        AppendRing(@"jkl");
        CHECK(isString(YankRing(), @"jkl"), "an append after a yank starts a new entry");
        NewSequence();
        AppendRing(@"X");
        NewSequence();
        AppendRing(@"Y");
        CHECK(isString(YankRing(), @"Y"), "a new sequence starts a new entry");
        NewSequence();
        CHECK(isString(YankRing(), @""), "a new sequence entry is empty until appended to");
        NewSequence();
        AppendRing(@"W");
        SetYanked();
        AppendRing(@"V");
        CHECK(isString(YankRing(), @"V"), "an append after the yanked state starts a new entry");

        // NSTextView's own commands go through the same ring.
        NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
        [view setString: @"hello world\nsecond line"];
        [view setSelectedRange: NSMakeRange(5, 0)];
        [view deleteToEndOfLine: nil];
        CHECK([[view string] isEqualToString: @"hello\nsecond line"], "deleteToEndOfLine: kills to the line end");
        [view deleteToEndOfLine: nil];
        CHECK([[view string] isEqualToString: @"hellosecond line"], "second kill joins the next line");
        // Two kills in a row form one entry (test_quirk_line_kills_prepend).
        [view setSelectedRange: NSMakeRange(0, 0)];
        [view yank: nil];
        CHECK([[view string] isEqualToString: @"\n worldhellosecond line"], "yank inserts both kills, newest first");
        CHECK([view selectedRange].location == 7, "yank leaves the insertion point after the text");
        CHECK(isString(YankRing(), @"\n world"), "the function yields what the text view killed");

        // Each pair below is one sequence of two kills at one insertion point.
        struct {
            const char *name;
            SEL first, second;
            NSUInteger location;
            NSString *text, *remaining, *ring;
        } pairs[] = {
            {"EOL EOL", @selector(deleteToEndOfLine:), @selector(deleteToEndOfLine:), 2,
             @"ab cd\nef\ngh", @"abef\ngh", @"\n cd"},
            {"EOP EOP (test_quirk_paragraph_kills_append)", @selector(deleteToEndOfParagraph:),
             @selector(deleteToEndOfParagraph:), 2, @"ab cd\nef\ngh", @"abef\ngh", @" cd\n"},
            {"BOL EOL (test_quirk_line_kills_prepend)", @selector(deleteToBeginningOfLine:),
             @selector(deleteToEndOfLine:), 2, @"ab cd\nef", @"\nef", @" cdab"},
            {"EOL BOL", @selector(deleteToEndOfLine:), @selector(deleteToBeginningOfLine:), 2,
             @"ab cd\nef", @"\nef", @"ab cd"},
            {"EOL EOP (a different kind starts a new entry)", @selector(deleteToEndOfLine:),
             @selector(deleteToEndOfParagraph:), 2, @"ab cd\nef", @"abef", @"\n"},
            {"EOP in the last paragraph", @selector(deleteToEndOfParagraph:), @selector(deleteToEndOfParagraph:), 2,
             @"xy zw", @"xy", @" zw"},
            {"BOP BOP", @selector(deleteToBeginningOfParagraph:), @selector(deleteToBeginningOfParagraph:), 4,
             @"ab\ncd\nef", @"ab\nd\nef", @"c"},
        };
        for (size_t i = 0; i < sizeof pairs / sizeof pairs[0]; i++) {
            NewSequence();
            [view setString: pairs[i].text];
            [view setSelectedRange: NSMakeRange(pairs[i].location, 0)];
            [view performSelector: pairs[i].first withObject: nil];
            [view performSelector: pairs[i].second withObject: nil];
            if (![[view string] isEqualToString: pairs[i].remaining] || !isString(YankRing(), pairs[i].ring)) {
                printf("FAIL: %s: text [%s] ring [%s]\n", pairs[i].name, [[view string] UTF8String],
                       [[YankRing() description] UTF8String]);
                failures++;
            }
        }

        // A move between two kills starts a new entry.
        [view setString: @"aaa bbb\nccc ddd\neee"];
        [view setSelectedRange: NSMakeRange(3, 0)];
        NewSequence();
        [view deleteToEndOfLine: nil];
        [view moveRight: nil];
        [view deleteToEndOfLine: nil];
        CHECK(isString(YankRing(), @"ccc ddd"), "a move starts a new kill sequence");

        // An entry put on the ring by the functions reaches the text view.
        NewSequence();
        AppendRing(@"ring text");
        [view setString: @""];
        [view yank: nil];
        CHECK([[view string] isEqualToString: @"ring text"], "yank: inserts the ring's entry");
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures ? 1 : 0;
}
