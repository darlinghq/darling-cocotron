/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSActionCell.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSDate.h>

@class NSColor, NSCalendar, NSLocale, NSTimeZone;

typedef NS_OPTIONS(NSUInteger, NSDatePickerElementFlags) {
    NSDatePickerElementFlagHourMinute = 0x000c,
    NSDatePickerElementFlagHourMinuteSecond = 0x000e,
    NSDatePickerElementFlagTimeZone = 0x0010,
    NSDatePickerElementFlagYearMonth = 0x00c0,
    NSDatePickerElementFlagYearMonthDay = 0x00e0,
    NSDatePickerElementFlagEra = 0x0100,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSHourMinuteDatePickerElementFlag = NSDatePickerElementFlagHourMinute,
    NSHourMinuteSecondDatePickerElementFlag = NSDatePickerElementFlagHourMinuteSecond,
    NSTimeZoneDatePickerElementFlag = NSDatePickerElementFlagTimeZone,
    NSYearMonthDatePickerElementFlag = NSDatePickerElementFlagYearMonth,
    NSYearMonthDayDatePickerElementFlag = NSDatePickerElementFlagYearMonthDay,
    NSEraDatePickerElementFlag = NSDatePickerElementFlagEra,
};

typedef NS_ENUM(NSUInteger, NSDatePickerMode) {
    NSDatePickerModeSingle = 0,
    NSDatePickerModeRange = 1,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSSingleDateMode = NSDatePickerModeSingle,
    NSRangeDateMode = NSDatePickerModeRange,
};

typedef NS_ENUM(NSUInteger, NSDatePickerStyle) {
    NSDatePickerStyleTextFieldAndStepper = 0,
    NSDatePickerStyleClockAndCalendar = 1,
    NSDatePickerStyleTextField = 2
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSTextFieldAndStepperDatePickerStyle = NSDatePickerStyleTextFieldAndStepper,
    NSClockAndCalendarDatePickerStyle = NSDatePickerStyleClockAndCalendar,
    NSTextFieldDatePickerStyle = NSDatePickerStyleTextField,
};

@interface NSDatePickerCell : NSActionCell {
    id _delegate;
    NSDatePickerElementFlags _elements;
    NSDatePickerMode _mode;
    NSDatePickerStyle _style;
    NSCalendar *_calendar;
    NSLocale *_locale;
    NSDate *_minDate;
    NSDate *_maxDate;
    NSTimeZone *_timeZone;
    BOOL _drawsBackground;
    NSColor *_backgroundColor;
    NSColor *_textColor;
    NSTimeInterval _timeInterval;
    NSUInteger _selectedUnit;
    BOOL _isUpHighlighted;
    BOOL _isDownHighlighted;
    NS_LEGACY_IVAR_PAD(_NSDatePickerCellReserved, 4)
}

- delegate;

- (NSDatePickerElementFlags) datePickerElements;
- (NSDatePickerMode) datePickerMode;
- (NSDatePickerStyle) datePickerStyle;

- (NSCalendar *) calendar;
- (NSLocale *) locale;
- (NSDate *) minDate;
- (NSDate *) maxDate;

- (NSDate *) dateValue;
- (NSTimeInterval) timeInterval;
- (NSTimeZone *) timeZone;

- (BOOL) drawsBackground;
- (NSColor *) backgroundColor;
- (NSColor *) textColor;

- (void) setDelegate: delegate;

- (void) setDatePickerElements: (NSDatePickerElementFlags) elements;
- (void) setDatePickerMode: (NSDatePickerMode) mode;
- (void) setDatePickerStyle: (NSDatePickerStyle) style;

- (void) setCalendar: (NSCalendar *) calendar;
- (void) setLocale: (NSLocale *) locale;
- (void) setMinDate: (NSDate *) date;
- (void) setMaxDate: (NSDate *) date;

- (void) setDateValue: (NSDate *) date;
- (void) setTimeInterval: (NSTimeInterval) interval;
- (void) setTimeZone: (NSTimeZone *) timeZone;

- (void) setDrawsBackground: (BOOL) flag;
- (void) setBackgroundColor: (NSColor *) color;
- (void) setTextColor: (NSColor *) color;

@end

@protocol NSDatePickerCellDelegate <NSObject>
- (void) datePickerCell: (NSDatePickerCell *) datePickerCell
        validateProposedDateValue: (NSDate **) dateValue
                     timeInterval: (NSTimeInterval *) timeInterval;
@end
