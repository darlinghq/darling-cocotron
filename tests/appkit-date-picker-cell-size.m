// Copyright (C) 2026 Lubos Dolezel
//
// -[NSDatePickerCell cellSize]. The documentation of -[NSCell cellSize]
// (https://developer.apple.com/documentation/appkit/nscell/cellsize) says it is the minimum size needed to
// display the cell; a date picker cell shows its date, so its size is that of the formatted date elements plus
// the bezel and the stepper, and an NSControl's intrinsicContentSize follows it. It must not be the default size
// of a cell without content (10000 x 10000), which AutoLayout turns into a 10000 point wide view.
// Observed on macOS 26.7.3 (x86_64): text field and stepper style, year-month-day and time, 168 x 26 points;
// text field style 148 x 21; year-month-day only 105 x 26; NSDatePicker's intrinsic size 166 x 22. The test
// checks the range, not the points, which depend on the fonts: whatever the style and the elements, the size is
// finite and moderate (the cell of a Darling date picker always has a stepper and shows the date only, so the
// ordering of those sizes that macOS has is not checked).
// Build: clang -framework AppKit appkit-date-picker-cell-size.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSDatePickerCell *cell = [[[NSDatePickerCell alloc] init] autorelease];
    [cell setDateValue: [NSDate dateWithTimeIntervalSince1970: 1700000000]];
    [cell setDatePickerStyle: NSTextFieldAndStepperDatePickerStyle];
    [cell setDatePickerElements: NSYearMonthDayDatePickerElementFlag | NSHourMinuteSecondDatePickerElementFlag];
    NSSize full = [cell cellSize];
    CHECK(full.width > 60 && full.width < 400);
    CHECK(full.height >= 16 && full.height < 60);

    [cell setDatePickerElements: NSYearMonthDayDatePickerElementFlag];
    NSSize dateOnly = [cell cellSize];
    CHECK(dateOnly.width > 40 && dateOnly.width < 400);
    CHECK(dateOnly.height >= 16 && dateOnly.height < 60);

    [cell setDatePickerElements: NSYearMonthDayDatePickerElementFlag | NSHourMinuteSecondDatePickerElementFlag];
    [cell setDatePickerStyle: NSTextFieldDatePickerStyle];
    NSSize noStepper = [cell cellSize];
    CHECK(noStepper.width > 40 && noStepper.width < 400);
    CHECK(noStepper.height >= 16 && noStepper.height < 60);

    NSDatePicker *picker = [[[NSDatePicker alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)] autorelease];
    NSSize intrinsic = [picker intrinsicContentSize];
    CHECK(intrinsic.width > 40 && intrinsic.width < 400);
    CHECK(intrinsic.height >= 16 && intrinsic.height < 60);

    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
