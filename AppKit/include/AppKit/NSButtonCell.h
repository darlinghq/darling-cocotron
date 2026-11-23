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
#import <AppKit/NSActionCell.h>
#import <AppKit/NSImageCell.h>

@class NSSound;

NS_ASSUME_NONNULL_BEGIN

enum {
    NSNoCellMask = 0x00,
    NSContentsCellMask = 0x01,
    NSPushInCellMask = 0x02,
    NSChangeGrayCellMask = 0x04,
    NSChangeBackgroundCellMask = 0x08,
};

typedef NS_ENUM(NSUInteger, NSButtonType) {
    NSButtonTypeMomentaryLight = 0,
    NSButtonTypePushOnPushOff = 1,
    NSButtonTypeToggle = 2,
    NSButtonTypeSwitch = 3,
    NSButtonTypeRadio = 4,
    NSButtonTypeMomentaryChange = 5,
    NSButtonTypeOnOff = 6,
    NSButtonTypeMomentaryPushIn = 7,
    NSButtonTypeAccelerator = 8,
    NSButtonTypeMultiLevelAccelerator = 9,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSMomentaryLightButton = NSButtonTypeMomentaryLight,
    NSPushOnPushOffButton = NSButtonTypePushOnPushOff,
    NSToggleButton = NSButtonTypeToggle,
    NSSwitchButton = NSButtonTypeSwitch,
    NSRadioButton = NSButtonTypeRadio,
    NSMomentaryChangeButton = NSButtonTypeMomentaryChange,
    NSOnOffButton = NSButtonTypeOnOff,
    NSMomentaryPushInButton = NSButtonTypeMomentaryPushIn,
    NSMomentaryPushButton = 0,
    NSMomentaryLight = 7,
};

typedef NS_ENUM(NSUInteger, NSBezelStyle) {
    NSBezelStyleRounded = 1,
    NSBezelStyleRegularSquare = 2,
    NSBezelStyleThickSquare = 3,
    NSBezelStyleThickerSquare = 4,
    NSBezelStyleDisclosure = 5,
    NSBezelStyleShadowlessSquare = 6,
    NSBezelStyleCircular = 7,
    NSBezelStyleTexturedSquare = 8,
    NSBezelStyleHelpButton = 9,
    NSBezelStyleSmallSquare = 10,
    NSBezelStyleTexturedRounded = 11,
    NSBezelStyleRoundRect = 12,
    NSBezelStyleRecessed = 13,
    NSBezelStyleRoundedDisclosure = 14,
    NSBezelStyleInline = 15,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSRoundedBezelStyle = NSBezelStyleRounded,
    NSRegularSquareBezelStyle = NSBezelStyleRegularSquare,
    NSDisclosureBezelStyle = NSBezelStyleDisclosure,
    NSShadowlessSquareBezelStyle = NSBezelStyleShadowlessSquare,
    NSCircularBezelStyle = NSBezelStyleCircular,
    NSTexturedSquareBezelStyle = NSBezelStyleTexturedSquare,
    NSHelpButtonBezelStyle = NSBezelStyleHelpButton,
    NSSmallSquareBezelStyle = NSBezelStyleSmallSquare,
    NSTexturedRoundedBezelStyle = NSBezelStyleTexturedRounded,
    NSRoundRectBezelStyle = NSBezelStyleRoundRect,
    NSRecessedBezelStyle = NSBezelStyleRecessed,
    NSRoundedDisclosureBezelStyle = NSBezelStyleRoundedDisclosure,
    NSInlineBezelStyle = NSBezelStyleInline,
    NSThickSquareBezelStyle = NSBezelStyleThickSquare,
    NSThickerSquareBezelStyle = NSBezelStyleThickerSquare,
};

typedef NS_ENUM(NSUInteger, NSGradientType) {
    NSGradientNone = 0,
    NSGradientConcaveWeak = 1,
    NSGradientConcaveStrong = 2,
    NSGradientConvexWeak = 3,
    NSGradientConvexStrong = 4,
};

// Legacy ObjC ABI (i386): instance size must stay 0x44, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSButtonCell : NSActionCell {
    NSString *_alternateTitle;
    NSSound *_sound;
    NSString *_keyEquivalent;
    NS_LEGACY_IVAR_PAD(_NSButtonCellReserved1, 12)
    NSImage *_normalImage;
    NS_EXTRA_IVARS_BEGIN(NSButtonCell)
        NSImage *_alternateImage;
        int _imagePosition;
        unsigned _highlightsBy : 4;
        unsigned _showsStateBy : 4;
        NSBezelStyle _bezelStyle;
        BOOL _isTransparent;
        BOOL _imageDimsWhenDisabled;
        unsigned _keyEquivalentModifierMask;
        BOOL _showsBorderOnlyWhileMouseInside;
        NSGradientType _gradientType;
        NSImageScaling _imageScaling;
        NSFont *_keyEquivalentFont;
        NSColor *_backgroundColor;
        float _periodicDelay, _periodicInterval;
        NSImage *_alternateImageOrKeyEquivalentFont;
        NSUInteger _bcFlags;
        BOOL _mouseInside;
    NS_EXTRA_IVARS_END(NSButtonCell)
}

- (BOOL) isTransparent;
- (NSString *) keyEquivalent;
- (NSCellImagePosition) imagePosition;
- (NSString *) title;
- (NSString *) alternateTitle;
- (nullable NSImage *) alternateImage;
- (NSAttributedString *) attributedTitle;
- (NSAttributedString *) attributedAlternateTitle;
- (int) highlightsBy;
- (int) showsStateBy;
- (BOOL) imageDimsWhenDisabled;
- (unsigned) keyEquivalentModifierMask;
- (NSBezelStyle) bezelStyle;
- (BOOL) showsBorderOnlyWhileMouseInside;
- (nullable NSSound *) sound;
- (NSGradientType) gradientType;
- (NSImageScaling) imageScaling;
- (BOOL) isOpaque;
- (nullable NSFont *) keyEquivalentFont;
- (nullable NSColor *) backgroundColor;
- (void) getPeriodicDelay: (float *) delay interval: (float *) interval;

- (void) setTransparent: (BOOL) flag;
- (void) setKeyEquivalent: (NSString *) keyEquivalent;
- (void) setImagePosition: (NSCellImagePosition) position;
- (void) setTitle: (nullable NSString *) title;
- (void) setAlternateTitle: (NSString *) title;
- (void) setAlternateImage: (nullable NSImage *) image;
- (void) setAttributedTitle: (NSAttributedString *) title;
- (void) setAttributedAlternateTitle: (NSAttributedString *) title;
- (void) setHighlightsBy: (int) type;
- (void) setShowsStateBy: (int) type;
- (void) setImageDimsWhenDisabled: (BOOL) flag;
- (void) setKeyEquivalentModifierMask: (unsigned) mask;
- (void) setBezelStyle: (NSBezelStyle) bezelStyle;
- (void) setButtonType: (NSButtonType) buttonType;
- (void) setShowsBorderOnlyWhileMouseInside: (BOOL) show;
- (void) setSound: (nullable NSSound *) sound;
- (void) setGradientType: (NSGradientType) value;
- (void) setBackgroundColor: (nullable NSColor *) value;
- (void) setImageScaling: (NSImageScaling) value;
- (void) setKeyEquivalentFont: (nullable NSFont *) value;
- (void) setKeyEquivalentFont: (NSString *) value size: (CGFloat) size;
- (void) setPeriodicDelay: (float) delay interval: (float) interval;

- (void) performClick: (nullable id) sender;

- (void) drawBezelWithFrame: (NSRect) rect inView: (NSView *) view;
- (void) drawImage: (NSImage *) image
         withFrame: (NSRect) rect
            inView: (NSView *) view;
- (NSRect) drawTitle: (NSAttributedString *) title
           withFrame: (NSRect) rect
              inView: (NSView *) view;

- (void) mouseEntered: (NSEvent *) event;
- (void) mouseExited: (NSEvent *) event;

@end

NS_ASSUME_NONNULL_END
