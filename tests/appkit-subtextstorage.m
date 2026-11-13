/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSSubTextStorage shows a range of a parent text storage and forwards edits
 * to it. No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#import <objc/runtime.h>

@interface NSSubTextStorage : NSTextStorage
- (instancetype) initWithTextStorage: (NSTextStorage *) textStorage range: (NSRange) range;
- (NSRange) range;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

// QUIRK test: the `_range` ivar of NSRange type exists and tracks the range.
static void test_quirk_range_ivar(void)
{
    NSTextStorage *parent = [[NSTextStorage alloc] initWithString: @"0123456789"];
    NSSubTextStorage *sub = [[NSSubTextStorage alloc] initWithTextStorage: parent range: NSMakeRange(2, 5)];
    Ivar ivar = class_getInstanceVariable([NSSubTextStorage class], "_range");
    expect(ivar != NULL, "_range ivar exists");
    if (ivar == NULL)
        return;
    expect(strncmp(ivar_getTypeEncoding(ivar), "{_NSRange=", 10) == 0, "_range is an NSRange");
    NSRange stored;
    memcpy(&stored, (char *) sub + ivar_getOffset(ivar), sizeof(stored));
    expect(NSEqualRanges(stored, NSMakeRange(2, 5)), "_range holds the range");
}

int main(void)
{
    @autoreleasepool {
        NSTextStorage *parent = [[NSTextStorage alloc] initWithString: @"0123456789"];
        NSSubTextStorage *sub = [[NSSubTextStorage alloc] initWithTextStorage: parent
                                                                        range: NSMakeRange(2, 5)];
        expect(NSEqualRanges([sub range], NSMakeRange(2, 5)), "range is the initial range");
        expect([[sub string] isEqualToString: @"23456"], "string is the parent's range");
        expect([sub length] == 5, "length is the range length");

        [sub replaceCharactersInRange: NSMakeRange(1, 2) withString: @"abcd"];
        expect([[parent string] isEqualToString: @"012abcd56789"],
               "an edit through the sub storage changes the parent");
        expect(NSEqualRanges([sub range], NSMakeRange(2, 7)), "the range grows with the edit");
        expect([[sub string] isEqualToString: @"2abcd56"], "string reflects the edit");

        [parent addAttribute: NSUnderlineStyleAttributeName value: @1 range: NSMakeRange(3, 2)];
        NSRange effective;
        id value = [sub attribute: NSUnderlineStyleAttributeName atIndex: 1 effectiveRange: &effective];
        expect([value intValue] == 1 && NSEqualRanges(effective, NSMakeRange(1, 2)),
               "attribute runs are reported in the sub storage's coordinates");

        BOOL raised = NO;
        @try {
            [sub replaceCharactersInRange: NSMakeRange(6, 5) withString: @"x"];
        } @catch (NSException *e) {
            raised = [[e name] isEqualToString: NSRangeException];
        }
        expect(raised, "an out-of-range edit raises NSRangeException");

        [parent replaceCharactersInRange: NSMakeRange(0, [parent length]) withString: @"ab"];
        expect(NSEqualRanges([sub range], NSMakeRange(2, 0)), "the range is clamped when the parent shrinks");

        test_quirk_range_ivar();
    }
    if (failures)
        return 1;
    puts("sub text storage: PASS");
    return 0;
}
