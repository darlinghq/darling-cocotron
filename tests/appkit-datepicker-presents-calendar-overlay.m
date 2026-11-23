// Copyright (C) 2026 Lubos Dolezel
//
// NSDatePicker presentsCalendarOverlay. The documentation (macOS 10.15.4) lists it as a settable
// Boolean on NSDatePicker that switches a pop-up calendar on for editing the calendar part of a
// text-field style picker, and says it starts as NO. The pop-up itself is not implemented and
// not tested. Everything marked GUESS pins this
// implementation's choice: the value is independent of the picker's style, elements and mode.
// Build: clang -fobjc-arc -framework AppKit appkit-datepicker-presents-calendar-overlay.m
// On master the selectors do not exist: with ARC the test does not compile against master's
// header, without ARC the first call raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>

// the property is macOS 10.15.4 API; the guest has it whatever the build's deployment target is
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// An application subclass whose setter wraps the superclass one (the failing receiver in a real
// application was a subclass).
@interface MyDatePicker : NSDatePicker
- (void)setPresentsCalendarOverlay:(BOOL)presents;
@end
@implementation MyDatePicker
- (void)setPresentsCalendarOverlay:(BOOL)presents {
    (void)[self presentsCalendarOverlay];
    [super setPresentsCalendarOverlay:presents];
}
@end

static void checkPicker(NSDatePicker *picker) {
    CHECK([picker presentsCalendarOverlay] == NO);        // the documented default

    BOOL values[] = { YES, NO, YES, YES, NO };
    for (int i = 0; i < 5; i++) {
        [picker setPresentsCalendarOverlay:values[i]];
        CHECK([picker presentsCalendarOverlay] == values[i]);
    }

    // the value and the picker's other state do not overwrite one another
    [picker setPresentsCalendarOverlay:YES];
    [picker setDatePickerStyle:NSDatePickerStyleTextField];
    [picker setDatePickerElements:NSDatePickerElementFlagYearMonthDay];
    [picker setDatePickerMode:NSDatePickerModeRange];
    [picker setBezeled:NO];
    CHECK([picker presentsCalendarOverlay]);                // GUESS: not reset by the style
    [picker setDatePickerStyle:NSDatePickerStyleClockAndCalendar];
    CHECK([picker presentsCalendarOverlay]);
    [picker setPresentsCalendarOverlay:NO];
    CHECK([picker datePickerStyle] == NSDatePickerStyleClockAndCalendar);
    CHECK([picker datePickerElements] == NSDatePickerElementFlagYearMonthDay);
    CHECK([picker datePickerMode] == NSDatePickerModeRange);
    CHECK(![picker isBezeled]);
}

int main(void) {
    @autoreleasepool {
        CHECK([NSDatePicker instancesRespondToSelector:@selector(presentsCalendarOverlay)]);
        CHECK([NSDatePicker instancesRespondToSelector:@selector(setPresentsCalendarOverlay:)]);

        NSDatePicker *plain = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
        checkPicker(plain);
        MyDatePicker *mine = [[MyDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
        checkPicker(mine);

        // pickers do not share the value
        NSDatePicker *first = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
        NSDatePicker *second = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
        [first setPresentsCalendarOverlay:YES];
        CHECK([second presentsCalendarOverlay] == NO);
        [second setPresentsCalendarOverlay:YES];
        [first setPresentsCalendarOverlay:NO];
        CHECK([second presentsCalendarOverlay]);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
