/* Copyright (c) 2026 Darling Developers

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

@class NSMenu, NSImage, NSString;

typedef NS_ENUM(NSInteger, NSComboButtonStyle) {
    NSComboButtonStyleSplit = 0,
    NSComboButtonStyleUnified = 1,
};

// A control combining a primary action with a pull-down menu.

APPKIT_EXPORT
@interface NSComboButton : NSControl {
    NSComboButtonStyle _style;
    NSMenu *_comboMenu;
    NSString *_comboTitle;
}

+ (instancetype) comboButtonWithTitle: (NSString *) title
                                 menu: (nullable NSMenu *) menu
                               target: (nullable id) target
                               action: (nullable SEL) action;
+ (instancetype) comboButtonWithImage: (NSImage *) image
                                 menu: (nullable NSMenu *) menu
                               target: (nullable id) target
                               action: (nullable SEL) action;
+ (instancetype) comboButtonWithTitle: (NSString *) title
                                image: (NSImage *) image
                                 menu: (nullable NSMenu *) menu
                               target: (nullable id) target
                               action: (nullable SEL) action;

@property(nonatomic) NSComboButtonStyle style;
@property(nullable, nonatomic, retain) NSMenu *menu;
@property(nullable, nonatomic, copy) NSString *comboTitle;

@end
