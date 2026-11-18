/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSControl.h>

NS_ASSUME_NONNULL_BEGIN

#define _NS_SIDE_NSButton 0, 1,
// Legacy ObjC ABI (i386): instance size must stay 0x5c, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSButton : NSControl {
    NS_EXTRA_IVARS_BEGIN(NSButton)
        NSColor *_contentTintColor;
        BOOL _hasDestructiveAction;
    NS_SIDE_IVARS_END(NSButton)
}

+ (instancetype) buttonWithTitle: (NSString *) title image: (NSImage *) image target: (nullable id) target action: (nullable SEL) action;
+ (instancetype) checkboxWithTitle: (NSString *) title target: (nullable id) target action: (nullable SEL) action;
+ (instancetype) radioButtonWithTitle: (NSString *) title target: (nullable id) target action: (nullable SEL) action;

@property(nonatomic, getter=isTransparent) BOOL transparent;
@property(nonatomic, copy) NSString *keyEquivalent;
@property(nonatomic) NSEventModifierFlags keyEquivalentModifierMask;
@property(nullable, nonatomic, retain) NSImage *image;
@property(nonatomic) NSCellImagePosition imagePosition;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) NSControlStateValue state;
@property(nonatomic) BOOL allowsMixedState;
@property(nullable, nonatomic, retain) NSSound *sound;

@property(nonatomic) NSBezelStyle bezelStyle;
@property(nonatomic, copy) NSString *alternateTitle;
@property(nullable, nonatomic, retain) NSImage *alternateImage;
@property(nonatomic, copy) NSAttributedString *attributedTitle;
@property(nonatomic, copy) NSAttributedString *attributedAlternateTitle;
@property(nonatomic) BOOL showsBorderOnlyWhileMouseInside;
- (void) getPeriodicDelay: (float *) delay interval: (float *) interval;

@property(nonatomic) NSImageScaling imageScaling;
- (void) setNextState;

- (void) setPeriodicDelay: (float) delay interval: (float) interval;

- (void) setButtonType: (NSButtonType) value;
- (void) setTitleWithMnemonic: (null_unspecified NSString *) value;

- (void) highlight: (BOOL) value;
- (BOOL) performKeyEquivalent: (NSEvent *) event;
- (void) performClick: (nullable id) sender;

// Convenience constructors (10.12)
+ (instancetype) buttonWithTitle: (NSString *) title
                          target: (nullable id) target
                          action: (nullable SEL) action;
+ (instancetype) buttonWithImage: (NSImage *) image
                          target: (nullable id) target
                          action: (nullable SEL) action;

@end

@interface NSButton (NSButtonContentTint)
// Stored only: the image and title aren't tinted.
@property(nullable, copy) NSColor *contentTintColor;
@end

@interface NSButton (NSDestructiveAction)
// macOS 11: marks a button whose action is destructive (stored; not drawn differently).
@property(nonatomic) BOOL hasDestructiveAction;
@end

NS_ASSUME_NONNULL_END
