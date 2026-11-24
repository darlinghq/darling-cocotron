// Copyright (C) 2026 Lubos Dolezel
//
// NSDatePicker presentsCalendarOverlay. The documentation (macOS 10.15.4) lists it as a settable
// Boolean on NSDatePicker that switches a pop-up calendar on for editing the calendar part of a
// text-field style picker, and says it starts as NO. The pop-up itself is not implemented and
// not tested. Observed on macOS 26.7.3 (mac-probes/cristim/batch12a/p768.m; the property is newer than 10.14.4):
// the value stays as set when the picker's style, mode, elements and bezel change, and an archive carries it
// under the key presentsCalendarOverlay (no NS prefix).
// Build: clang -fobjc-arc -framework AppKit appkit-datepicker-presents-calendar-overlay.m
// On master the selectors do not exist: with ARC the test does not compile against master's
// header, without ARC the first call raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>

// Stands in for the object in a keyed archive: it writes only the one key (as an archive of a program that
// does not know the property would not have it, and as macOS writes it), and is decoded as the class under test.
static NSString *standInKey;
static BOOL standInValue;
@interface ArchivedStandIn : NSObject <NSCoding>
@end
@implementation ArchivedStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    if (standInKey != nil)
        [coder encodeBool:standInValue forKey:standInKey];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static id decodedAs(Class cls, NSString *key, BOOL value) {
    standInKey = key;
    standInValue = value;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:[ArchivedStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:cls forClassName:@"ArchivedStandIn"];
    return [unarchiver decodeObjectForKey:@"root"];
}

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
    CHECK([picker presentsCalendarOverlay]);                // not reset by the style
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
        // the archive key (the key is absent from an archive that never had it)
        CHECK(![(NSDatePicker *)decodedAs([NSDatePicker class], nil, NO) presentsCalendarOverlay]);
        CHECK(![(NSDatePicker *)decodedAs([NSDatePicker class], @"presentsCalendarOverlay", NO) presentsCalendarOverlay]);
        CHECK([(NSDatePicker *)decodedAs([NSDatePicker class], @"presentsCalendarOverlay", YES) presentsCalendarOverlay]);

        // the picker made with -initWithFrame: has a date picker cell with the macOS defaults (26.7.3, 10.14.4)
        NSDatePicker *fresh = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
        CHECK([[fresh cell] isKindOfClass:[NSDatePickerCell class]]);
        CHECK([fresh datePickerElements] == (NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinuteSecond));
        CHECK([fresh datePickerMode] == NSDatePickerModeSingle);
        CHECK([fresh datePickerStyle] == NSDatePickerStyleTextFieldAndStepper);
        CHECK([fresh isBezeled] && ![fresh isBordered]);

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
