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

#import <AppKit/NSControl.h>
#import <AppKit/NSDatePickerCell.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSCalendar;

NS_ASSUME_NONNULL_BEGIN

#define _NS_SIDE_NSDatePicker 0, 1,
// Legacy ObjC ABI (i386): Apple's NSDatePicker adds no instance variable to NSControl and an application's
// subclass sits right after it. New state goes to the side struct, never to an ivar of its own.
@interface NSDatePicker : NSControl {
    NS_EXTRA_IVARS_BEGIN(NSDatePicker)
        BOOL _presentsCalendarOverlay;
    NS_SIDE_IVARS_END(NSDatePicker)
}

@property(nonatomic, getter=isBezeled) BOOL bezeled;
@property(nonatomic, getter=isBordered) BOOL bordered;

- (null_unspecified id) delegate;

@property(nonatomic) NSDatePickerElementFlags datePickerElements;
@property(nonatomic) NSDatePickerMode datePickerMode;
@property(nonatomic) NSDatePickerStyle datePickerStyle;
// Switch for a pop-up calendar that can appear while a text-field style picker's calendar part is being
// edited (macOS 10.15.4); stored only, no pop-up exists here. Documented to start as NO.
@property(nonatomic) BOOL presentsCalendarOverlay API_AVAILABLE(macos(10.15.4));

@property(nullable, nonatomic, retain) NSCalendar *calendar;
@property(nullable, nonatomic, retain) NSLocale *locale;
@property(nullable, nonatomic, retain) NSDate *minDate;
@property(nullable, nonatomic, retain) NSDate *maxDate;

@property(nonatomic, retain) NSDate *dateValue;
@property(nonatomic) NSTimeInterval timeInterval;
@property(nullable, nonatomic, retain) NSTimeZone *timeZone;

@property(nonatomic) BOOL drawsBackground;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *textColor;


- (void) setDelegate: (null_unspecified id) delegate;





@end

NS_ASSUME_NONNULL_END
