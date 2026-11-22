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

#import "NSImage+TemplateDrawing.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <objc/runtime.h>
#import <AppKit/NSButtonImageSource.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSSound.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>

@implementation NSButtonCell

// Margin between an image and the Button interior borders
static const CGFloat kImageMargin = 2.;

// The button flags of a keyed archive, the inverse of
// -_applyButtonCellAppleFlags:flags2:.
- (unsigned) _buttonCellAppleFlags {
    unsigned flags = 0;
    NSInteger highlightsBy = NS_EXTRA(NSButtonCell, self)->_highlightsBy;
    NSInteger showsStateBy = NS_EXTRA(NSButtonCell, self)->_showsStateBy;

    switch (NS_EXTRA(NSButtonCell, self)->_imagePosition) {
    case NSImageOnly:
        flags |= 0x00400000;
        break;
    case NSImageOverlaps:
        flags |= 0x00480000;
        break;
    case NSImageLeft:
        flags |= 0x00380000;
        break;
    case NSImageRight:
        flags |= 0x00280000;
        break;
    case NSImageBelow:
        flags |= 0x00180000;
        break;
    case NSImageAbove:
        flags |= 0x00080000;
        break;
    default:
        break;
    }

    if (highlightsBy & NSPushInCellMask)
        flags |= 0x80000000;
    if (showsStateBy & NSContentsCellMask)
        flags |= 0x40000000;
    if (showsStateBy & NSChangeBackgroundCellMask)
        flags |= 0x20000000;
    if (showsStateBy & NSChangeGrayCellMask)
        flags |= 0x10000000;
    if (highlightsBy & NSContentsCellMask)
        flags |= 0x08000000;
    if (highlightsBy & NSChangeBackgroundCellMask)
        flags |= 0x04000000;
    if (highlightsBy & NSChangeGrayCellMask)
        flags |= 0x02000000;
    if (NS_EXTRA(NSCell, self)->_isBordered)
        flags |= 0x00800000;
    if (NS_EXTRA(NSButtonCell, self)->_isTransparent)
        flags |= 0x00008000;
    if (!NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled)
        flags |= 0x00002000;
    return flags;
}

- (unsigned) _buttonCellAppleFlags2 {
    NSUInteger bezel = NS_EXTRA(NSButtonCell, self)->_bezelStyle;
    unsigned flags2 = (bezel & 0x7) | ((bezel & 0x8) << 2);

    if (NS_EXTRA(NSButtonCell, self)->_showsBorderOnlyWhileMouseInside)
        flags2 |= 0x8;
    switch (NS_EXTRA(NSButtonCell, self)->_imageScaling) {
    case NSImageScaleProportionallyUpOrDown:
        flags2 |= 1 << 6;
        break;
    case NSImageScaleProportionallyDown:
        flags2 |= 2 << 6;
        break;
    case NSImageScaleAxesIndependently:
        flags2 |= 3 << 6;
        break;
    default:
        break;
    }
    flags2 |= (unsigned) NS_EXTRA(NSButtonCell, self)->_keyEquivalentModifierMask << 8;
    return flags2;
}

// The archived contents of a button cell are its title.
- (id) _archivedContents {
    return NS_EXTRA(NSCell, self)->_titleOrAttributedTitle;
}

// Writes the keys that -initWithCoder: reads, as macOS writes them: the
// button flags, the title as the contents, the alternate title and image and
// the key equivalent.
- (void) encodeWithCoder: (NSCoder *) coder {
    [super encodeWithCoder: coder];
    [coder encodeInt: (int) [self _buttonCellAppleFlags] forKey: @"NSButtonFlags"];
    [coder encodeInt: (int) [self _buttonCellAppleFlags2] forKey: @"NSButtonFlags2"];
    // in milliseconds, as macOS writes them
    [coder encodeInt: (int) lroundf(NS_EXTRA(NSButtonCell, self)->_periodicDelay * 1000) forKey: @"NSPeriodicDelay"];
    [coder encodeInt: (int) lroundf(NS_EXTRA(NSButtonCell, self)->_periodicInterval * 1000) forKey: @"NSPeriodicInterval"];
    if (_alternateTitle != nil)
        [coder encodeObject: _alternateTitle forKey: @"NSAlternateContents"];
    if (NS_EXTRA(NSButtonCell, self)->_alternateImage != nil)
        [coder encodeObject: NS_EXTRA(NSButtonCell, self)->_alternateImage forKey: @"NSAlternateImage"];
    [coder encodeObject: _keyEquivalent != nil ? _keyEquivalent : @"" forKey: @"NSKeyEquivalent"];
}

- (void) _applyButtonCellAppleFlags: (unsigned) flags flags2: (unsigned) flags2 {
    NS_EXTRA(NSButtonCell, self)->_imagePosition = NSNoImage;
    if ((flags & 0x00480000) == 0x00400000)
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageOnly;
    else if ((flags & 0x00480000) == 0x00480000)
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageOverlaps;
    else if ((flags & 0x00380000) == 0x00380000)
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageLeft;
    else if ((flags & 0x00380000) == 0x00280000)
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageRight;
    else if ((flags & 0x00380000) == 0x00180000)
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageBelow;
    else if ((flags & 0x00380000) == 0x00080000)
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageAbove;

    //  bits 6 and 7 in flags2, but not in order
    switch ((flags2 >> 6) & 0x3) {

    case 0:
        NS_EXTRA(NSButtonCell, self)->_imageScaling = NSImageScaleNone;
        break;

    case 1:
        NS_EXTRA(NSButtonCell, self)->_imageScaling = NSImageScaleProportionallyUpOrDown;
        break;

    case 2:
        NS_EXTRA(NSButtonCell, self)->_imageScaling = NSImageScaleProportionallyDown;
        break;

    case 3:
        NS_EXTRA(NSButtonCell, self)->_imageScaling = NSImageScaleAxesIndependently;
        break;
    }

    NS_EXTRA(NSButtonCell, self)->_highlightsBy = 0;
    NS_EXTRA(NSButtonCell, self)->_showsStateBy = 0;

    if (flags & 0x80000000)
        NS_EXTRA(NSButtonCell, self)->_highlightsBy |= NSPushInCellMask;
    if (flags & 0x40000000)
        NS_EXTRA(NSButtonCell, self)->_showsStateBy |= NSContentsCellMask;
    if (flags & 0x20000000)
        NS_EXTRA(NSButtonCell, self)->_showsStateBy |= NSChangeBackgroundCellMask;
    if (flags & 0x10000000)
        NS_EXTRA(NSButtonCell, self)->_showsStateBy |= NSChangeGrayCellMask;
    if (flags & 0x08000000)
        NS_EXTRA(NSButtonCell, self)->_highlightsBy |= NSContentsCellMask;
    if (flags & 0x04000000)
        NS_EXTRA(NSButtonCell, self)->_highlightsBy |= NSChangeBackgroundCellMask;
    if (flags & 0x02000000)
        NS_EXTRA(NSButtonCell, self)->_highlightsBy |= NSChangeGrayCellMask;

    NS_EXTRA(NSCell, self)->_isBordered =
            (flags & 0x00800000) ? YES : NO; // err, this flag is in NSCell too

    // The archive stores the style in the low three bits of the second flag word and, for the styles
    // from 8 up (textured, round rect, recessed, inline and so on), the fourth bit in bit 5.
    NS_EXTRA(NSButtonCell, self)->_bezelStyle = (flags2 & 0x7) | ((flags2 & 0x20) >> 2);

    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == 0) // no style at all: how older archives encode textured buttons
        NS_EXTRA(NSButtonCell, self)->_bezelStyle = NSTexturedSquareBezelStyle;

    NS_EXTRA(NSButtonCell, self)->_isTransparent = (flags & 0x00008000) ? YES : NO;
    NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = (flags & 0x00002000) ? NO : YES;

    NS_EXTRA(NSButtonCell, self)->_showsBorderOnlyWhileMouseInside = (flags2 & 0x8) ? YES : NO;

    // The highlight and state masks above are kept as they are; only a cell
    // that shows and highlights by its contents is checked for the switch and
    // radio images.
    if ((flags & 0x7e800000) == 0x48000000) {
        if (flags & 0x100) {
            id altImageSource = NS_EXTRA(NSButtonCell, self)->_alternateImage;
            if ([[altImageSource name] isEqualToString: @"NSSwitch"])
                [self setButtonType: NSSwitchButton];
            if ([[altImageSource name] isEqualToString: @"NSRadioButton"])
                [self setButtonType: NSRadioButton];
        } else {
            if (([[[self image] name] isEqualToString: @"NSRadioButton"] &&
                 [[[self alternateImage] name]
                         isEqualToString: @"NSHighlightedRadioButton"]) &&
                (flags & 0x20000) == 0) {
                [self setButtonType: NSRadioButton];
            } else if (([[[self image] name] isEqualToString: @"NSSwitch"] &&
                        [[[self alternateImage] name]
                                isEqualToString: @"NSHighlightedSwitch"]) &&
                       (flags & 0x20000) == 0) {
                [self setButtonType: NSMomentaryPushInButton];
            }
        }
    }
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    unsigned flags = 0, flags2 = 0;

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        flags = [keyed decodeIntForKey: @"NSButtonFlags"];
        flags2 = [keyed decodeIntForKey: @"NSButtonFlags2"];
        [self _applyDefaultHighlightingAndRepeat]; // for archives that have no repeat keys
        if ([keyed containsValueForKey: @"NSPeriodicDelay"] && [keyed containsValueForKey: @"NSPeriodicInterval"])
            [self setPeriodicDelay: [keyed decodeIntForKey: @"NSPeriodicDelay"] / 1000.0f
                          interval: [keyed decodeIntForKey: @"NSPeriodicInterval"] / 1000.0f];
        id check;

        NS_EXTRA(NSCell, self)->_titleOrAttributedTitle =
                [[keyed decodeObjectForKey: @"NSContents"] retain];
        _alternateTitle =
                [[keyed decodeObjectForKey: @"NSAlternateContents"] retain];

        [self _applyButtonCellAppleFlags: flags flags2: flags2];

        check = [keyed decodeObjectForKey: @"NSAlternateImage"];
        if ([check isKindOfClass: [NSImage class]])
            NS_EXTRA(NSButtonCell, self)->_alternateImage = [check retain];
        else if ([check isKindOfClass: [NSButtonImageSource class]]) {
            [NS_EXTRA(NSCell, self)->_image release];
            NS_EXTRA(NSCell, self)->_image = [[check normalImage] retain];
            NS_EXTRA(NSButtonCell, self)->_alternateImage = [[check alternateImage] retain];
        } else
            NS_EXTRA(NSButtonCell, self)->_alternateImage = nil;

        /* _normalImage is a private ivar in Apple's AppKit. Third party library
           BGHUDAppKit uses it to figure out what kind of standard button is
           being drawn. We emulate it for BGHUDAppKit. */
        _normalImage = [NS_EXTRA(NSCell, self)->_image retain];

        _keyEquivalent =
                [[keyed decodeObjectForKey: @"NSKeyEquivalent"] retain];
        NS_EXTRA(NSButtonCell, self)->_keyEquivalentModifierMask = flags2 >> 8;
        [self setIntValue: NS_EXTRA(NSCell, self)->_state]; // make the int value of NSButtonCell to be
                                    // in synch with the bare _state of NSCell
    } else {
        NSInteger version = [coder versionForClassName: @"NSButtonCell"];
        unsigned int keyEquivModMask = 0;
        id altContents = nil, keyEquivalent = nil, keyEquivalentFont = nil, normalImage = nil;
        id alternateImageOrFont = nil, sound = nil;

        // Read layout per class version: only the sequence of public decode calls is
        // dictated by the archive; what the unknown values mean is not known.
        if (version <= 16) {
            if ([coder systemVersion] > 82) {
                short periodicDelay, periodicInterval;
                [coder decodeValuesOfObjCTypes: "ss", &periodicDelay, &periodicInterval];

                [self setPeriodicDelay: periodicDelay / 1000.0f interval: periodicInterval / 1000.0f];
            }

            char *altContentsString = NULL;
            unsigned short inFlags1, inFlags2;
            [coder decodeValuesOfObjCTypes: "*@ss", &altContentsString, &sound, &inFlags1, &inFlags2];

            flags = (((unsigned) inFlags1) << 16) & 0xFEF80000;
            flags |= (((unsigned) inFlags1) & 0x3) << 17;
            flags |= (((unsigned) inFlags2) << 8) & 0x8000;
            flags |= (((unsigned) inFlags2) & 0x6) << 12;

            unichar keyEquivalentChar = inFlags2 >> 8;
            if (keyEquivalentChar != 0) {
                keyEquivalent = [[NSString alloc] initWithCharacters: &keyEquivalentChar length: 1];
            }

            if (altContentsString) {
                altContents = [[NSString alloc] initWithBytesNoCopy: altContentsString
                                                             length: strlen(altContentsString)
                                                           encoding: NSUTF8StringEncoding
                                                       freeWhenDone: YES];
            }

            // Two objects follow whatever the flags say. The first is the normal image
            // when bit 17 is set, else the alternate image; the second is only kept
            // as the alternate image when bit 17 is set.
            id first = nil, second = nil;
            [coder decodeValuesOfObjCTypes: "@@", &first, &second];
            if (flags & 0x20000) {
                normalImage = first;
                alternateImageOrFont = second;
            } else {
                alternateImageOrFont = first;
                [second release];
            }

            if (version >= 2)
                [coder decodeValuesOfObjCTypes: "I", &keyEquivModMask];
        } else if (version <= 40) {
            short periodicDelay, periodicInterval;
            [coder decodeValuesOfObjCTypes: "ss", &periodicDelay, &periodicInterval];

            [self setPeriodicDelay: periodicDelay / 1000.0f interval: periodicInterval / 1000.0f];

            [coder decodeValuesOfObjCTypes: "I", &keyEquivModMask];

            // Eighteen separate flag bytes. Seventeen are mapped to the flag word; the
            // eighth (index 7) is read and ignored (its meaning is unknown).
            static const struct {
                int shift;
                unsigned mask;
            } bytes[18] = {
                { 31, 1 }, { 30, 1 }, { 29, 1 }, { 28, 1 }, { 27, 1 }, { 26, 1 },
                { 25, 1 },    { 0, 0 },  { 23, 1 }, { 22, 1 }, { 21, 1 }, { 20, 1 },
                { 19, 1 },    { 18, 1 }, { 17, 1 }, { 15, 1 }, { 13, 3 }, { 12, 1 },
            };
            int i;
            for (i = 0; i < 18; i++) {
                char c = 0;
                [coder decodeValuesOfObjCTypes: "c", &c];
                if (bytes[i].mask != 0) {
                    flags |= (((unsigned) (unsigned char) c) & bytes[i].mask) << bytes[i].shift;
                }
            }

            altContents = [[coder decodeObject] retain];
            keyEquivalent = [[coder decodeObject] retain];
            keyEquivalentFont = [[coder decodeObject] retain];
            normalImage = [[coder decodeObject] retain];
            alternateImageOrFont = [[coder decodeObject] retain];
            sound = [[coder decodeObject] retain];

            // Values of unknown meaning, kept in the archive layout and dropped:
            // two words from version 19 (the second from 21) up to 26, a byte at 26 and
            // a further byte from 26 on; versions 27 and later have two bytes only.
            unsigned int unknownWord;
            char unknownByte;
            if (version >= 19 && version <= 26)
                [coder decodeValuesOfObjCTypes: "I", &unknownWord];
            if (version >= 21 && version <= 26)
                [coder decodeValuesOfObjCTypes: "I", &unknownWord];
            if (version >= 26)
                [coder decodeValuesOfObjCTypes: "c", &unknownByte];
            if (version >= 27)
                [coder decodeValuesOfObjCTypes: "c", &unknownByte];
        } else if (version <= 57) {
            short periodicDelay, periodicInterval;
            [coder decodeValuesOfObjCTypes: "ssIi@@@@@", &periodicDelay, &periodicInterval, &keyEquivModMask, &flags,
                                            &altContents, &keyEquivalent, &normalImage, &alternateImageOrFont, &sound];

            [self setPeriodicDelay: periodicDelay / 1000.0f interval: periodicInterval / 1000.0f];

            flags &= 0xfeffffff;
            flags2 &= 0xFFFFFFD8;
        } else {
            short periodicDelay, periodicInterval;
            [coder decodeValuesOfObjCTypes: "ssii@@@@@", &periodicDelay, &periodicInterval, &flags2, &flags, &altContents,
                                            &keyEquivalent, &normalImage, &alternateImageOrFont, &sound];

            [self setPeriodicDelay: periodicDelay / 1000.0f interval: periodicInterval / 1000.0f];

            // As in the keyed form, the key equivalent's modifier mask sits above the
            // low byte of the second flag word.
            keyEquivModMask = flags2 >> 8;
            flags &= 0xfeffffff;
        }

        [_alternateTitle release];
        _alternateTitle = [altContents isKindOfClass: [NSString class]] ? altContents : nil;
        if (_alternateTitle == nil)
            [altContents release];

        [_keyEquivalent release];
        _keyEquivalent = [keyEquivalent isKindOfClass: [NSString class]] ? keyEquivalent : nil;
        if (_keyEquivalent == nil) {
            [keyEquivalent release];
            _keyEquivalent = [@"" retain];
        }

        [NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont release];
        NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont = [keyEquivalentFont isKindOfClass: [NSFont class]] ? keyEquivalentFont : nil;
        if (NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont == nil)
            [keyEquivalentFont release];

        [_sound release];
        _sound = sound;

        // The normal image is also the cell's own image, as in the keyed form.
        if (normalImage != nil) {
            if ([normalImage isKindOfClass: [NSImage class]]) {
                [NS_EXTRA(NSCell, self)->_image release];
                NS_EXTRA(NSCell, self)->_image = normalImage;
            } else {
                [normalImage release];
            }
        }
        _normalImage = [NS_EXTRA(NSCell, self)->_image retain];

        // The slot after the key equivalent and image holds the alternate image, a
        // button image source standing for both images, or the key equivalent font.
        [NS_EXTRA(NSButtonCell, self)->_alternateImage release];
        NS_EXTRA(NSButtonCell, self)->_alternateImage = nil;
        if ([alternateImageOrFont isKindOfClass: [NSButtonImageSource class]]) {
            [NS_EXTRA(NSCell, self)->_image release];
            NS_EXTRA(NSCell, self)->_image = [[alternateImageOrFont normalImage] retain];
            [_normalImage release];
            _normalImage = [NS_EXTRA(NSCell, self)->_image retain];
            NS_EXTRA(NSButtonCell, self)->_alternateImage = [[alternateImageOrFont alternateImage] retain];
        } else if ([alternateImageOrFont isKindOfClass: [NSImage class]]) {
            NS_EXTRA(NSButtonCell, self)->_alternateImage = [alternateImageOrFont retain];
        } else if ([alternateImageOrFont isKindOfClass: [NSFont class]] && NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont == nil) {
            NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont = [alternateImageOrFont retain];
        }
        [alternateImageOrFont release];

        // The title is the object value decoded by NSCell.
        NSString *stringValue = [self stringValue];
        if ([stringValue length] > 0) {
            [self setTitle: stringValue];
        }

        if (version <= 36) {
            const unsigned int bits = (flags >> 13 & 3);
            if (bits == 2)
                flags &= 0x0FFFF9FFF;
            else if (bits == 0) {
                flags &= 0xFFFF9FFF;
                flags |= 0x4000;
            }
        }

        if (version <= 40) {
            if (([[self image]
                         isEqual: [NSImage imageNamed: @"NSRadioButton"]] &&
                 [[self alternateImage]
                         isEqual: [NSImage imageNamed: @"NSHighlightedRadioButt"
                                                       @"on"]]) ||
                ([[self image] isEqual: [NSImage imageNamed: @"NSSwitch"]] &&
                 [[self alternateImage]
                         isEqual: [NSImage imageNamed:
                                                   @"NSHighlightedSwitch"]])) {
                flags |= 0x1000;
            }
        }

        if ([[self keyEquivalent] isEqualToString: @"\n"])
            [self setKeyEquivalent: @"\r"];

        if (version <= 53) {
            if ([[self keyEquivalent] isEqualToString: @"\r"]) {
                if ([[[self image] name] isEqualToString: @"NSReturnSign"] ||
                    [[[self alternateImage] name]
                            isEqualToString: @"NXreturnSignH"]) {
                    [self setImage: nil];
                    [self setAlternateImage: nil];
                    flags &= 0xB70000;
                }
            }
        }

        [self _applyButtonCellAppleFlags: flags flags2: flags2];
        [self setKeyEquivalentModifierMask: keyEquivModMask];

        // The object value holds the state (NSCell decoded the title there), as after
        // keyed decoding.
        [self setIntValue: NS_EXTRA(NSCell, self)->_state];
    }
    return self;
}

// QUIRK: a new button cell highlights by pushing in, changing its gray and changing its background (highlightsBy
// 14) whichever initializer made it, and repeats (for continuous buttons) after 0.4 seconds every 0.075 seconds.
// Not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2) of cells made with -init,
// -initTextCell:, -initImageCell: and by NSButton, and of an archived cell's NSPeriodicDelay and
// NSPeriodicInterval keys (400 and 75, in milliseconds); vd-upstream/mac-probes/aqua-leftovers-buttoncell.m.
// Test: test_quirk_button_cell_highlight_defaults in tests/appkit-button-cell-highlights.m
- (void) _applyDefaultHighlightingAndRepeat {
    NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSPushInCellMask | NSChangeGrayCellMask | NSChangeBackgroundCellMask;
    NS_EXTRA(NSButtonCell, self)->_periodicDelay = 0.4f;
    NS_EXTRA(NSButtonCell, self)->_periodicInterval = 0.075f;
}

- initTextCell: (NSString *) string {
    [super initTextCell: string];
    NS_EXTRA(NSCell, self)->_titleOrAttributedTitle = [string copy];
    _alternateTitle = @"";
    NS_EXTRA(NSButtonCell, self)->_imagePosition = NSNoImage;
    [self _applyDefaultHighlightingAndRepeat];
    NS_EXTRA(NSButtonCell, self)->_showsStateBy = 0;
    NS_EXTRA(NSButtonCell, self)->_isTransparent = NO;
    NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = NO;
    NS_EXTRA(NSButtonCell, self)->_alternateImage = nil;
    _keyEquivalent = @"";
    NS_EXTRA(NSButtonCell, self)->_keyEquivalentModifierMask = 0;
    NS_EXTRA(NSButtonCell, self)->_showsBorderOnlyWhileMouseInside = NO;

    [self setBordered: YES];
    [self setBezeled: YES];
    [self setAlignment: NSCenterTextAlignment];
    [self setObjectValue: [NSNumber numberWithBool: NO]];

    return self;
}

- initImageCell: (NSImage *) image {
    [super initImageCell: image];
    NS_EXTRA(NSCell, self)->_titleOrAttributedTitle = @""; // empty string, not nil
    NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageOnly;
    [self _applyDefaultHighlightingAndRepeat];
    [self setObjectValue: [NSNumber numberWithBool: NO]];

    return self;
}

- init {
    return [self initTextCell: @"Button"];
}

- (void) dealloc {
    [NS_EXTRA(NSCell, self)->_titleOrAttributedTitle release];
    [_normalImage release];
    [_alternateTitle release];
    [NS_EXTRA(NSButtonCell, self)->_alternateImage release];
    [_keyEquivalent release];
    [_sound release];
    [NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont release];
    [NS_EXTRA(NSButtonCell, self)->_backgroundColor release];
    NS_EXTRA_FREE(NSButtonCell, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSButtonCell *result = [super copyWithZone: zone];
    NS_EXTRA_COPY(NSButtonCell, result, self);

    NS_EXTRA(NSCell, result)->_titleOrAttributedTitle = [NS_EXTRA(NSCell, self)->_titleOrAttributedTitle copy];
    result->_alternateTitle = [_alternateTitle copy];
    NS_EXTRA(NSButtonCell, result)->_alternateImage = [NS_EXTRA(NSButtonCell, self)->_alternateImage retain];
    result->_keyEquivalent = [_keyEquivalent copy];
    result->_sound = [_sound retain];
    NS_EXTRA(NSButtonCell, result)->_keyEquivalentFont = [NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont retain];
    NS_EXTRA(NSButtonCell, result)->_backgroundColor = [NS_EXTRA(NSButtonCell, self)->_backgroundColor retain];

    return result;
}

- (BOOL) isTransparent {
    return NS_EXTRA(NSButtonCell, self)->_isTransparent;
}

- (NSString *) keyEquivalent {
    return _keyEquivalent;
}

- (NSCellImagePosition) imagePosition {
    return NS_EXTRA(NSButtonCell, self)->_imagePosition;
}

- (NSString *) title {
    if ([NS_EXTRA(NSCell, self)->_titleOrAttributedTitle isKindOfClass: [NSAttributedString class]])
        return [NS_EXTRA(NSCell, self)->_titleOrAttributedTitle string];
    else
        return NS_EXTRA(NSCell, self)->_titleOrAttributedTitle;
}

- (NSString *) alternateTitle {
    return _alternateTitle;
}

- (NSImage *) alternateImage {
    return NS_EXTRA(NSButtonCell, self)->_alternateImage;
}

- (NSAttributedString *) attributedTitle {
    if (NS_EXTRA(NSCell, self)->_titleOrAttributedTitle == nil) {
        // attributedTitle is explicitly documented to return an empty
        // attributed string when title is nil
        return [[NSAttributedString alloc] initWithString: @""];
    } else if ([NS_EXTRA(NSCell, self)->_titleOrAttributedTitle
                       isKindOfClass: [NSAttributedString class]])
        return NS_EXTRA(NSCell, self)->_titleOrAttributedTitle;
    else {
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        NSMutableParagraphStyle *paraStyle =
                [[[NSParagraphStyle defaultParagraphStyle] mutableCopy]
                        autorelease];
        NSFont *font = [self font];

        if (font != nil)
            [attributes setObject: font forKey: NSFontAttributeName];

        [paraStyle setLineBreakMode: NS_EXTRA(NSCell, self)->_lineBreakMode];
        [paraStyle setAlignment: NS_EXTRA(NSCell, self)->_textAlignment];
        [attributes setObject: paraStyle forKey: NSParagraphStyleAttributeName];

        if ([self isEnabled])
            [attributes setObject: [NSColor controlTextColor]
                           forKey: NSForegroundColorAttributeName];
        else
            [attributes setObject: [NSColor disabledControlTextColor]
                           forKey: NSForegroundColorAttributeName];

        return [[[NSAttributedString alloc] initWithString: [self title]
                                                attributes: attributes]
                autorelease];
    }
}

- (NSAttributedString *) attributedAlternateTitle {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSMutableParagraphStyle *paraStyle =
            [[[NSParagraphStyle defaultParagraphStyle] mutableCopy]
                    autorelease];
    NSFont *font = [self font];

    if (font != nil)
        [attributes setObject: font forKey: NSFontAttributeName];

    [paraStyle setLineBreakMode: NS_EXTRA(NSCell, self)->_lineBreakMode];
    [paraStyle setAlignment: NS_EXTRA(NSCell, self)->_textAlignment];
    [attributes setObject: paraStyle forKey: NSParagraphStyleAttributeName];

    if ([self isEnabled])
        [attributes setObject: [NSColor controlTextColor]
                       forKey: NSForegroundColorAttributeName];
    else
        [attributes setObject: [NSColor disabledControlTextColor]
                       forKey: NSForegroundColorAttributeName];

    return [[[NSAttributedString alloc] initWithString: [self alternateTitle]
                                            attributes: attributes]
            autorelease];
}

- (int) highlightsBy {
    return NS_EXTRA(NSButtonCell, self)->_highlightsBy;
}

- (int) showsStateBy {
    return NS_EXTRA(NSButtonCell, self)->_showsStateBy;
}

- (BOOL) imageDimsWhenDisabled {
    return NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled;
}

- (unsigned) keyEquivalentModifierMask {
    return NS_EXTRA(NSButtonCell, self)->_keyEquivalentModifierMask;
}

- (NSBezelStyle) bezelStyle {
    return NS_EXTRA(NSButtonCell, self)->_bezelStyle;
}

- (BOOL) showsBorderOnlyWhileMouseInside {
    return NS_EXTRA(NSButtonCell, self)->_showsBorderOnlyWhileMouseInside;
}

- (NSSound *) sound {
    return _sound;
}

- (NSGradientType) gradientType {
    return NS_EXTRA(NSButtonCell, self)->_gradientType;
}

- (NSImageScaling) imageScaling {
    return NS_EXTRA(NSButtonCell, self)->_imageScaling;
}

- (BOOL) isOpaque {
    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSDisclosureBezelStyle)
        return NO;
    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSTexturedSquareBezelStyle)
        return NO;
    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSTexturedRoundedBezelStyle)
        return NO;
    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSShadowlessSquareBezelStyle)
        return NO;
    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSRecessedBezelStyle)
        return NO;

    return ![self isTransparent] && [self isBordered];
}

- (NSFont *) keyEquivalentFont {
    return NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont;
}

- (NSColor *) backgroundColor {
    return NS_EXTRA(NSButtonCell, self)->_backgroundColor;
}

- (void) getPeriodicDelay: (float *) delay interval: (float *) interval {
    *delay = NS_EXTRA(NSButtonCell, self)->_periodicDelay;
    *interval = NS_EXTRA(NSButtonCell, self)->_periodicInterval;
}

- (NSControlStateValue) state {
    return [self intValue];
}

- (void) setTransparent: (BOOL) flag {
    NS_EXTRA(NSButtonCell, self)->_isTransparent = flag;
}

- (void) setKeyEquivalent: (NSString *) keyEquivalent {
    keyEquivalent = [keyEquivalent copy];
    [_keyEquivalent release];
    _keyEquivalent = keyEquivalent;
}

- (void) setImagePosition: (NSCellImagePosition) position {
    NS_EXTRA(NSButtonCell, self)->_imagePosition = position;
}

- (void) setImage: (NSImage *) image {
    [super setImage: image];
    // QUIRK: giving a button cell an image while its image position is
    // NSNoImage changes the position to NSImageOnly, so the image shows; a
    // position set before is kept. Not documented. Evidence: black-box
    // observation on macOS 10.14.4 and 26.7.3 (tier 2), e.g. a new
    // -[NSButton initWithFrame:] button reports NSImageOnly after -setImage:.
    // macOS 26 does not do it again once NSNoImage was set explicitly;
    // 10.14.4 does, which is followed here.
    // Test: tests/appkit-button-image-position.m (test_quirk_set_image_shows_image)
    if (image != nil && NS_EXTRA(NSButtonCell, self)->_imagePosition == NSNoImage)
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageOnly;
}

- (void) setTitle: (NSString *) title {
    title = [title copy];
    [NS_EXTRA(NSCell, self)->_titleOrAttributedTitle release];
    NS_EXTRA(NSCell, self)->_titleOrAttributedTitle = title;
}

- (void) setAlternateTitle: (NSString *) title {
    title = [title copy];
    [_alternateTitle release];
    _alternateTitle = title;
}

- (void) setAlternateImage: (NSImage *) image {
    image = [image retain];
    [NS_EXTRA(NSButtonCell, self)->_alternateImage release];
    NS_EXTRA(NSButtonCell, self)->_alternateImage = image;
}

- (void) setAttributedTitle: (NSAttributedString *) title {
    title = [title copy];
    [NS_EXTRA(NSCell, self)->_titleOrAttributedTitle release];
    NS_EXTRA(NSCell, self)->_titleOrAttributedTitle = title;
}

- (void) setAttributedAlternateTitle: (NSAttributedString *) title {
    NSUnimplementedMethod();
}

- (void) setHighlightsBy: (int) type {
    NS_EXTRA(NSButtonCell, self)->_highlightsBy = type;
}

- (void) setShowsStateBy: (int) type {
    NS_EXTRA(NSButtonCell, self)->_showsStateBy = type;
}

- (void) setImageDimsWhenDisabled: (BOOL) flag {
    NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = flag;
}

- (void) setKeyEquivalentModifierMask: (unsigned) mask {
    NS_EXTRA(NSButtonCell, self)->_keyEquivalentModifierMask = mask;
}

- (void) setState: (NSControlStateValue) value {
    [self setIntValue: value];
}

- (void) setNextState {
    [self setIntValue: [self nextState]];
}

- (void) setObjectValue: (id<NSCopying>) value {
    if ([(id) value respondsToSelector: @selector(intValue)])
        [super setState: [(NSNumber *) value intValue]];
    else
        [super setState: 0];

    [[self controlView] willChangeValueForKey: @"objectValue"];
    [NS_EXTRA(NSCell, self)->_objectValue release];
    NS_EXTRA(NSCell, self)->_objectValue = [[NSNumber numberWithInt: [super state]] retain];
    [[self controlView] didChangeValueForKey: @"objectValue"];

    if ([[self controlView] respondsToSelector: @selector(updateCell:)])
        [(NSControl *) [self controlView] updateCell: self];
}

- (void) setBezelStyle: (NSBezelStyle) bezelStyle {
    NS_EXTRA(NSButtonCell, self)->_bezelStyle = bezelStyle;
}

- (void) setButtonType: (NSButtonType) buttonType {
    switch (buttonType) {
    // QUIRK: highlightsBy and showsStateBy per button type are 12 and 0 for momentary light, 14 and 0 for momentary
    // push in, 14 and 12 for push on push off (the others as before: momentary change 1 and 0, on off 12 and 12,
    // toggle 3 and 1, switch and radio 1 and 1). Not documented. Evidence: black-box observation on macOS 10.14.4
    // (tier 2), vd-upstream/mac-probes/aqua-leftovers-buttoncell.m. Test:
    // test_quirk_button_cell_highlight_defaults in tests/appkit-button-cell-highlights.m
    case NSMomentaryLightButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSChangeBackgroundCellMask | NSChangeGrayCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSNoCellMask;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = YES;
        break;

    case NSMomentaryPushInButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSPushInCellMask | NSChangeGrayCellMask | NSChangeBackgroundCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSNoCellMask;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = YES;
        break;

    case NSMomentaryChangeButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSContentsCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSNoCellMask;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = YES;
        break;

    case NSPushOnPushOffButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSPushInCellMask | NSChangeGrayCellMask | NSChangeBackgroundCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSChangeBackgroundCellMask | NSChangeGrayCellMask;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = YES;
        break;

    case NSOnOffButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSChangeBackgroundCellMask | NSChangeGrayCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSChangeBackgroundCellMask | NSChangeGrayCellMask;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = YES;
        break;

    case NSToggleButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSPushInCellMask | NSContentsCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSContentsCellMask;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = YES;
        break;

    case NSSwitchButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSContentsCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSContentsCellMask;
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageLeft;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = NO;
        [self setImage: [NSImage imageNamed: @"NSSwitch"]];
        [self setAlternateImage: [NSImage imageNamed: @"NSHighlightedSwitch"]];
        [self setAlignment: NSLeftTextAlignment];
        [self setBordered: NO];
        [self setBezeled: NO];
        break;

    case NSRadioButton:
        NS_EXTRA(NSButtonCell, self)->_highlightsBy = NSContentsCellMask;
        NS_EXTRA(NSButtonCell, self)->_showsStateBy = NSContentsCellMask;
        NS_EXTRA(NSButtonCell, self)->_imagePosition = NSImageLeft;
        NS_EXTRA(NSButtonCell, self)->_imageDimsWhenDisabled = NO;
        [self setImage: [NSImage imageNamed: @"NSRadioButton"]];
        [self setAlternateImage:
                        [NSImage imageNamed: @"NSHighlightedRadioButton"]];
        [self setAlignment: NSLeftTextAlignment];
        [self setBordered: NO];
        [self setBezeled: NO];
        break;
    }

    [(NSControl *) [self controlView] updateCell: self];
}

- (void) setShowsBorderOnlyWhileMouseInside: (BOOL) show {
    NS_EXTRA(NSButtonCell, self)->_showsBorderOnlyWhileMouseInside = show;
    NS_EXTRA(NSButtonCell, self)->_mouseInside = NO;
    // The button is the one that watches the pointer (and works out where it is now), so it is told
    // when the cell it draws changes; a cell the button does not draw is not watched at all.
    NSView *control = [self controlView];
    if ([control isKindOfClass: [NSButton class]] && [(NSButton *) control cell] == self)
        [control updateTrackingAreas];
}

- (void) setSound: (NSSound *) sound {
    sound = [sound retain];
    [_sound release];
    _sound = sound;
}

- (void) setGradientType: (NSGradientType) value {
    NS_EXTRA(NSButtonCell, self)->_gradientType = value;
}

- (void) setBackgroundColor: (NSColor *) value {
    value = [value copy];
    [NS_EXTRA(NSButtonCell, self)->_backgroundColor release];
    NS_EXTRA(NSButtonCell, self)->_backgroundColor = value;
}

- (void) setImageScaling: (NSImageScaling) value {
    NS_EXTRA(NSButtonCell, self)->_imageScaling = value;
}

- (void) setKeyEquivalentFont: (NSFont *) value {
    value = [value retain];
    [NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont release];
    NS_EXTRA(NSButtonCell, self)->_keyEquivalentFont = value;
}

- (void) setKeyEquivalentFont: (NSString *) value size: (CGFloat) size {
    NSFont *font = [NSFont fontWithName: value size: size];
    [self setKeyEquivalentFont: font];
}

- (void) setPeriodicDelay: (float) delay interval: (float) interval {
    NS_EXTRA(NSButtonCell, self)->_periodicDelay = delay;
    NS_EXTRA(NSButtonCell, self)->_periodicInterval = interval;
}

- (NSAttributedString *) titleForHighlight {
    if ((([self highlightsBy] & NSContentsCellMask) && [self isHighlighted]) ||
        (([self showsStateBy] & NSContentsCellMask) && [self state])) {
        NSAttributedString *result = [self attributedAlternateTitle];

        if ([result length] > 0)
            return result;
    }

    return [self attributedTitle];
}

- (NSImage *) imageForHighlight {
    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSDisclosureBezelStyle) {

        if ((([self highlightsBy] & NSContentsCellMask) &&
             [self isHighlighted]))
            return [NSImage imageNamed: @"NSButtonCell_disclosure_highlighted"];
        else if ([self state])
            return [NSImage imageNamed: @"NSButtonCell_disclosure_selected"];
        else
            return [NSImage imageNamed: @"NSButtonCell_disclosure_normal"];

        return nil;
    } else {
        if ((([self highlightsBy] & NSContentsCellMask) &&
             [self isHighlighted]) ||
            (([self showsStateBy] & NSContentsCellMask) && [self state]))
            return [self alternateImage];

        return [self image];
    }
}

- (BOOL) _isStockToggleImage: (NSImage *) image {
    NSString *name = [image name];

    return [name isEqualToString: @"NSSwitch"] || [name isEqualToString: @"NSHighlightedSwitch"] ||
           [name isEqualToString: @"NSRadioButton"] || [name isEqualToString: @"NSHighlightedRadioButton"];
}

- (NSRect) imageRectForBounds: (NSRect) rect {
    // Make sure we use the same image as will be drawn!
    NSImage *image = [self imageForHighlight];

    NSSize imageSize = NSMakeSize(0, 0);
    if (image != nil) {
        BOOL enabled = [self isEnabled] ? YES : ![self imageDimsWhenDisabled];
        BOOL mixed = [self state] == NSMixedState;
        imageSize =
                [[[self controlView] graphicsStyle] sizeOfButtonImage: image
                                                              enabled: enabled
                                                                mixed: mixed];
    }
    NSString *name = [image name];

    if ([name isEqualToString: @"NSSwitch"] || [name isEqualToString: @"NSHighlightedSwitch"] ||
        [name isEqualToString: @"NSRadioButton"] || [name isEqualToString: @"NSHighlightedRadioButton"]) {
        // QUIRK: the title of a check box or radio button starts 18 points from the left edge of the cell
        // (15 at the mini size), clear of the box; its ink starts 20 points from the edge on macOS, with
        // the glyph's own margin (a title that started further right would not fit the cell, which is as
        // wide as the title and 18 points). Not documented. Evidence: black-box renders on macOS 10.14.4 (tier 2),
        // regular, small and mini, equal for check boxes and radio buttons.
        // The width of the image area is what the title is placed after.
        // Test: appkit-button-aqua.m
        imageSize.width = [self controlSize] == NSMiniControlSize ? 11 : 14;
    }
    return NSMakeRect(rect.origin.x, rect.origin.y, imageSize.width,
                      imageSize.height);
}

- (BOOL) isVisuallyHighlighted {
    return ((([self highlightsBy] & NSChangeGrayCellMask) &&
             [self isHighlighted]) ||
            (([self showsStateBy] & NSChangeGrayCellMask) && [self state]));
}

// A push button of the rounded style that highlights by pushing in, as the buttons of a nib mostly are.
- (BOOL) _hasStockRoundedPushBezel {
    return ![self isKindOfClass: [NSPopUpButtonCell class]] &&
           NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSRoundedBezelStyle &&
           (NS_EXTRA(NSButtonCell, self)->_highlightsBy & NSPushInCellMask) &&
           (NS_EXTRA(NSButtonCell, self)->_highlightsBy & NSChangeGrayCellMask) &&
           NS_EXTRA(NSButtonCell, self)->_showsStateBy == NSNoCellMask;
}

// QUIRK: a stock rounded push button's alignment insets (the frame minus the alignment rectangle, which is also
// where its bezel is drawn) are (top, left, bottom, right) = (4, 6, 7, 6) regular, (3, 5, 6, 5) small and
// (0, 1, 1, 1) mini, in a view that is not flipped with the top and bottom shares swapped. Not documented.
// Evidence: black-box observation on macOS 10.14.4 (tier 2): -alignmentRectInsets of the button and the ink
// of a bitmap of the button's frame, at the three control sizes. Large buttons use the regular insets.
// Test: tests/appkit-push-button-alignment-insets.m
- (NSEdgeInsets) _roundedPushAlignmentInsets {
    switch (NS_EXTRA(NSCell, self)->_controlSize) {
    case NSSmallControlSize:
        return NSEdgeInsetsMake(3, 5, 6, 5);
    case NSMiniControlSize:
        return NSEdgeInsetsMake(0, 1, 1, 1);
    default:
        return NSEdgeInsetsMake(4, 6, 7, 6);
    }
}

- (NSRect) getControlSizeAdjustment: (BOOL) flipped {
    /*
    Aqua Push Buttons actually have a frame much larger than told by IB to make
    room for shadows and whatnot So we have to compensate for this when drawing
    simpler buttons. There is probably a way to streamline this, make
    NSPopUpButtonCell draw itself for starters NSGraphicsStyle should probably
    do this adjustment too
    */
    NSRect frame = {{0, 0}, {0, 0}};

    if ([self isKindOfClass: [NSComboBoxCell class]]) {
        switch (NS_EXTRA(NSCell, self)->_controlSize) {
        case NSRegularControlSize:
        case NSControlSizeLarge:
            frame.size.width = 2;
            frame.size.height = 1;
            frame.origin.x = 1;
            break;

        case NSSmallControlSize:
            frame.size.width = 4;
            frame.size.height = 8;
            frame.origin.x = 2;
            frame.origin.y = 6;
            break;

        case NSMiniControlSize:
            frame.size.width = 6;
            frame.size.height = 4;
            frame.origin.x = 3;
            frame.origin.y = 4;
            break;
        }
    } else if ([self isKindOfClass: [NSPopUpButtonCell class]]) {
        switch (NS_EXTRA(NSCell, self)->_controlSize) {
        case NSRegularControlSize:
        case NSControlSizeLarge:
            frame.size.width = 2;
            frame.size.height = 1;
            frame.origin.x = 1;
            break;

        case NSSmallControlSize:
            frame.size.width = 4;
            frame.size.height = 3;
            frame.origin.x = 2;
            frame.origin.y = 3;
            break;

        case NSMiniControlSize:
            // Mini controls don't need adjusting they're small enough already.
            break;
        }
    } else if ([self _hasStockRoundedPushBezel]) {
        // The bezel is the frame without the alignment insets: the frame is larger than the bezel by the room for
        // the shadow, which is below the bezel (the insets' bottom share), so the space above is the top share.
        NSEdgeInsets insets = [self _roundedPushAlignmentInsets];
        frame.size.width = insets.left + insets.right;
        frame.size.height = insets.top + insets.bottom;
        frame.origin.x = insets.left;
        frame.origin.y = flipped ? insets.top : insets.bottom;
    } else if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSRegularSquareBezelStyle) {
    }

    return frame;
}

- (void) _drawTexturedBezelWithFrame: (NSRect) frame {
    BOOL highlighted = [self isHighlighted];
    BOOL pressed =
            [self state] && ([self showsStateBy] & NSChangeBackgroundCellMask);

    BOOL renderDarkenBg = NO, renderOutlineShadow = NO;
    // CGFloat topGray=0.76, bottomGray=0.98, strokeGray=0.4;
    CGFloat topGray = 0.98, bottomGray = 0.76, strokeGray = 0.4;
    if (pressed) {
        topGray = 0.4;
        bottomGray = 0.30;
    }
    renderDarkenBg = highlighted;
    renderOutlineShadow = highlighted || pressed;

    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ctx);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextSetFillColorSpace(ctx, colorSpace);
    CGContextSetStrokeColorSpace(ctx, colorSpace);
    CGColorSpaceRelease(colorSpace);

    frame = NSInsetRect(frame, 1.5, 1.5);
    const CGFloat rounding = 1.5;

    const CGFloat baseY = floor(frame.origin.y);
    const CGFloat maxY = baseY + frame.size.height - 1.0;
    CGRect r = CGRectMake(floor(frame.origin.x), baseY, ceil(frame.size.width),
                          1.0);
    while (r.origin.y <= maxY) {
        CGFloat g =
                bottomGray + (topGray - bottomGray) *
                                     ((r.origin.y - baseY) / (maxY - baseY));
        CGFloat components[4] = {g, g, g, 1.0};
        CGContextSetFillColor(ctx, components);

        if (r.origin.y < baseY + 1.0f || r.origin.y > maxY - 1.0f) {
            CGContextFillRect(ctx,
                              CGRectMake(r.origin.x + 1.0f, r.origin.y,
                                         r.size.width - 2.0f, r.size.height));
        } else {
            CGContextFillRect(ctx, r);
        }
        r.origin.y += 1.0f;
    }

    const CGFloat lx = floor(frame.origin.x) + 0.5f;
    const CGFloat rx = floor(frame.origin.x + frame.size.width) + 0.5f;
    const CGFloat ty = floor(frame.origin.y) + 0.5f;
    const CGFloat by = floor(frame.origin.y + frame.size.height) + 0.5f;
    const CGFloat rlx = lx + rounding;
    const CGFloat rrx = rx - rounding;
    const CGFloat rty = ty + rounding;
    const CGFloat rby = by - rounding;
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, rlx, ty);
    CGContextAddLineToPoint(ctx, rrx, ty);
    CGContextAddLineToPoint(ctx, rx, rty);
    CGContextAddLineToPoint(ctx, rx, rby);
    CGContextAddLineToPoint(ctx, rrx, by);
    CGContextAddLineToPoint(ctx, rlx, by);
    CGContextAddLineToPoint(ctx, lx, rby);
    CGContextAddLineToPoint(ctx, lx, rty);
    CGContextClosePath(ctx);

    CGFloat components[4] = {strokeGray, strokeGray, strokeGray, 1.0};
    CGContextSetStrokeColor(ctx, components);
    CGContextSetLineWidth(ctx, 1.0);

    if (renderDarkenBg) {
        components[0] = components[1] = components[2] = 0.0;
        components[3] = 0.15;
        CGContextSetFillColor(ctx, components);
        CGContextDrawPath(ctx, kCGPathFillStroke);
    } else {
        CGContextStrokePath(ctx);
    }

    if (renderOutlineShadow) { // a small interior shadow within the button's
                               // outline
        const CGFloat ins = 0.4f;
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, lx + ins, ty + ins);
        CGContextAddLineToPoint(ctx, rx - ins, ty + ins);
        CGContextAddLineToPoint(ctx, rx - ins, by - ins);
        CGContextAddLineToPoint(ctx, lx + ins, by - ins);
        CGContextClosePath(ctx);

        components[0] = components[1] = components[2] = 0.0;
        components[3] = 0.3;
        CGContextSetStrokeColor(ctx, components);
        CGContextSetLineWidth(ctx, 0.9);
        CGContextStrokePath(ctx);
    }

    CGContextRestoreGState(ctx);
}

/* Pop-up and pull-down buttons with a rounded bezel and an arrow are drawn whole by the graphics style (the
   arrows are part of the end cap). Answers NO for every other button. */
- (BOOL) _drawsPopUpBezelInRect: (NSRect) frame {
    if (![self isKindOfClass: [NSPopUpButtonCell class]] ||
        NS_EXTRA(NSButtonCell, self)->_bezelStyle != NSRoundedBezelStyle ||
        [(NSPopUpButtonCell *) self arrowPosition] == NSPopUpNoArrow)
        return NO;

    BOOL pressed = ([self highlightsBy] & NSPushInCellMask) && [self isHighlighted];

    [[_controlView graphicsStyle] drawPopUpButtonInRect: frame
                                              pullsDown: [(NSPopUpButtonCell *) self pullsDown]
                                                pressed: pressed
                                                enabled: [self isEnabled]
                                                 active: [[_controlView window] isKeyWindow]
                                            controlSize: [self controlSize]];
    return YES;
}

// The bezel styles drawn with the Aqua artwork of textured, recessed and round-rect buttons.
- (BOOL) _hasAquaToolbarBezel {
    switch (NS_EXTRA(NSButtonCell, self)->_bezelStyle) {
    case NSTexturedRoundedBezelStyle:
    case NSTexturedSquareBezelStyle:
    case NSRecessedBezelStyle:
    case NSRoundRectBezelStyle:
        return [self isBordered];
    default:
        return NO;
    }
}

// Pressed: highlighted by a click, for buttons that show highlighting with their bezel. On: the on (or mixed)
// state of a button that shows its state with its bezel.
- (BOOL) _aquaBezelPressed {
    return [self isHighlighted] &&
           ([self highlightsBy] & (NSPushInCellMask | NSChangeGrayCellMask | NSChangeBackgroundCellMask));
}

- (BOOL) _aquaBezelOn {
    // a pop-up button has no on state of its own (its state is that of the selected item)
    if ([self isKindOfClass: [NSPopUpButtonCell class]])
        return NO;
    return [self state] != NSOffState && ([self showsStateBy] & (NSChangeGrayCellMask | NSChangeBackgroundCellMask));
}

// QUIRK: the textured rounded, recessed and round-rect bezels have a fixed height for each control size (with the
// point below the bezel: 23, 19 and 16 points textured; 19, 17 and 15 recessed and round-rect) and are centred
// vertically in a frame of another height, the odd point going above; the textured square bezel follows the
// frame. Not documented. Evidence: black-box renders of NSButton in frames 14 to 32 points high on macOS 10.14.4
// (tier 2), probe mac-probes/aqua-toolbar-2.m of the research notes.
// Test: appkit-toolbar-controls-aqua.m (test_quirk_bezel_heights)
- (NSRect) _aquaBezelArtworkRectForFrame: (NSRect) frame inView: (NSView *) controlView {
    static const CGFloat textured[3] = {23, 19, 16}, recessed[3] = {19, 17, 15};
    NSControlSize size = [self controlSize];
    int index = size == NSSmallControlSize ? 1 : (size == NSMiniControlSize ? 2 : 0);
    CGFloat height;

    switch (NS_EXTRA(NSButtonCell, self)->_bezelStyle) {
    case NSTexturedRoundedBezelStyle:
        height = textured[index];
        break;
    case NSRecessedBezelStyle:
    case NSRoundRectBezelStyle:
        height = recessed[index];
        break;
    default:
        return frame;
    }

    CGFloat above = ceil((NSHeight(frame) - height) / 2);

    frame.origin.y += [controlView isFlipped] ? above : NSHeight(frame) - height - above;
    frame.size.height = height;
    return frame;
}

- (void) _drawAquaToolbarBezelInFrame: (NSRect) frame inView: (NSView *) controlView {
    NSBezelStyle bezel = NS_EXTRA(NSButtonCell, self)->_bezelStyle;
    NSGraphicsStyle *style = [controlView graphicsStyle];
    NSRect art = [self _aquaBezelArtworkRectForFrame: frame inView: controlView];
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    BOOL pressed = [self _aquaBezelPressed], on = [self _aquaBezelOn];

    // the style draws for a view that is not flipped; in a flipped view the drawing is mirrored about the artwork
    CGContextSaveGState(context);
    if ([controlView isFlipped]) {
        CGContextTranslateCTM(context, 0, 2 * art.origin.y + art.size.height);
        CGContextScaleCTM(context, 1, -1);
    }
    switch (bezel) {
    case NSTexturedRoundedBezelStyle:
    case NSTexturedSquareBezelStyle:
        [style drawTexturedBezelInRect: art
                                square: bezel == NSTexturedSquareBezelStyle
                               pressed: pressed
                                    on: on
                           controlSize: [self controlSize]];
        break;
    case NSRecessedBezelStyle:
        // a disabled recessed button shows no bezel
        if ([self isEnabled])
            [style drawRecessedBezelInRect: art pressed: pressed on: on controlSize: [self controlSize]];
        break;
    default:
        [style drawRoundRectBezelInRect: art filled: pressed || on enabled: [self isEnabled]];
        break;
    }
    CGContextRestoreGState(context);
}

- (void) drawBezelWithFrame: (NSRect) frame inView: (NSView *) controlView {
    // The border is not drawn until the pointer is reported over the cell (see -[NSButton updateTrackingAreas]).
    // Observed on macOS 26.7.3: a button of a bordered style draws exactly what a button without a border does
    // there, and a cell drawn by a view that is not its button, which never hears of the pointer, differs from
    // what it draws without the flag (taken to be the same hiding).
    if (NS_EXTRA(NSButtonCell, self)->_showsBorderOnlyWhileMouseInside &&
        !NS_EXTRA(NSButtonCell, self)->_mouseInside)
        return;

    BOOL defaulted = ([[controlView window] defaultButtonCell] == self);

    if ([self _hasAquaToolbarBezel]) {
        [self _drawAquaToolbarBezelInFrame: frame inView: controlView];
        return;
    }

    NSRect adjustment =
            [self getControlSizeAdjustment: [controlView isFlipped]];
    frame.size.width -= adjustment.size.width;
    frame.size.height -= adjustment.size.height;
    frame.origin.x += adjustment.origin.x;
    frame.origin.y += adjustment.origin.y;

    switch (NS_EXTRA(NSButtonCell, self)->_bezelStyle) {

    case NSDisclosureBezelStyle:
        break;

    case NSRegularSquareBezelStyle:
        if ([self isBordered]) {
            BOOL highlighted = (([self highlightsBy] & NSPushInCellMask) &&
                                [self isHighlighted]);
            CGFloat topGray = highlighted ? 0.8 : 0.9;
            CGFloat bottomGray = highlighted ? 0.7 : 0.8;

            NSRect top = frame, bottom = frame;
            top.size.height = floor(frame.size.height / 2);
            bottom.size.height = ceil(frame.size.height / 2);
            if ([controlView isFlipped])
                bottom.origin.y += top.size.height;
            else
                top.origin.y += bottom.size.height;

            [[NSColor colorWithCalibratedWhite: topGray alpha: 1] set];
            NSRectFill(top);
            [[NSColor colorWithCalibratedWhite: bottomGray alpha: 1] set];
            NSRectFill(bottom);
            [[NSColor lightGrayColor] set];
            NSFrameRectWithWidth(frame, 1);
        }
        break;

    case NSTexturedSquareBezelStyle:
    case NSTexturedRoundedBezelStyle:
    case NSShadowlessSquareBezelStyle:

        if ([self isBordered]) {
            [self _drawTexturedBezelWithFrame: frame];
        }
        break;

    case NSRecessedBezelStyle:
        // drawn above when bordered
        break;

    default: {
        // The graphics style draws its images for a view that is not flipped; in a flipped view they
        // are mirrored about the frame so that they come out the right way up.
        CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
        BOOL mirror = [controlView isFlipped];

        if (mirror) {
            CGContextSaveGState(context);
            CGContextTranslateCTM(context, 0, 2 * frame.origin.y + frame.size.height);
            CGContextScaleCTM(context, 1, -1);
        }
        if (![self isBordered]) {
            [[_controlView graphicsStyle]
                    drawUnborderedButtonInRect: frame
                                     defaulted: defaulted];
        } else {
            // pressed push-in buttons and default buttons are blue when drawn by the style
            BOOL pressed = ([self highlightsBy] & NSPushInCellMask) && [self isHighlighted];

            if (![self _drawsPopUpBezelInRect: frame])
                [[_controlView graphicsStyle] drawPushButtonInRect: frame
                                                         defaulted: defaulted
                                                           pressed: pressed || [self isVisuallyHighlighted]
                                                           enabled: [self isEnabled]
                                                            active: [[controlView window] isKeyWindow]];
        }
        if (mirror)
            CGContextRestoreGState(context);
        break;
    }
    }
}

- (void) drawImage: (NSImage *) image
         withFrame: (NSRect) rect
            inView: (NSView *) controlView
{
    BOOL enabled = [self isEnabled] ? YES : ![self imageDimsWhenDisabled];
    BOOL mixed = ([self state] == NSMixedState) ? YES : NO;

    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, rect.origin.x, rect.origin.y);
    if ([controlView isFlipped]) {
        CGContextTranslateCTM(ctx, 0, rect.size.height);
        CGContextScaleCTM(ctx, 1, -1);
    }
    NSString *name = [image name];
    BOOL isSwitch = [name isEqualToString: @"NSSwitch"] || [name isEqualToString: @"NSHighlightedSwitch"];
    BOOL isRadio = [name isEqualToString: @"NSRadioButton"] || [name isEqualToString: @"NSHighlightedRadioButton"];
    NSRect local = NSMakeRect(0, 0, rect.size.width, rect.size.height);

    if (isSwitch || isRadio) {
        // the stock check box and radio button are drawn for the cell's state and size, whichever of
        // the images the cell's state selected. The style places the box relative to the left edge of the
        // cell, which is where the image margin starts.
        local.origin.x -= kImageMargin;
        local.size.width += kImageMargin;
        NSInteger state = [self state];
        BOOL active = [[controlView window] isKeyWindow];

        if (isSwitch)
            [[controlView graphicsStyle] drawCheckBoxInRect: local
                                                      state: state
                                                highlighted: [self isHighlighted]
                                                    enabled: [self isEnabled]
                                                     active: active
                                                controlSize: [self controlSize]];
        else
            [[controlView graphicsStyle] drawRadioButtonInRect: local
                                                         state: state
                                                   highlighted: [self isHighlighted]
                                                       enabled: [self isEnabled]
                                                        active: active
                                                   controlSize: [self controlSize]];
        // the box, in the coordinates of the control (the drawing is translated to the image's rectangle and mirrored
        // in a flipped control)
        NSBezierPath *box = [[[controlView graphicsStyle] toggleBoxPathInRect: local
                                                                         radio: isRadio
                                                                   controlSize: [self controlSize]] copy];
        NSAffineTransform *toControl = [NSAffineTransform transform];

        [toControl translateXBy: NSMinX(rect) yBy: [controlView isFlipped] ? NSMaxY(rect) : NSMinY(rect)];
        if ([controlView isFlipped])
            [toControl scaleXBy: 1 yBy: -1];
        [box transformUsingAffineTransform: toControl];
        objc_setAssociatedObject(self, &toggleFocusRingPathKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [box release];
    } else if ([image isTemplate])
        [image _drawTemplateInRect: local color: [self _templateImageColor] fraction: enabled ? 1.0 : 0.5];
    else
        [[controlView graphicsStyle]
                drawButtonImage: image
                         inRect: local
                        enabled: enabled
                          mixed: mixed];
    CGContextRestoreGState(ctx);
}

// QUIRK: the title colour of textured, recessed and round-rect buttons with the light appearance. Textured: black
// at 65% opacity, 85% while pressed, 25% disabled, and white (60% disabled) on the dark bezel of the on state.
// Recessed: white while pressed or on, otherwise the control text colours. Round-rect: the control text colours.
// nil means the colours of the title's attributes. Not documented. Evidence: black-box renders of NSButton on
// macOS 10.14.4 at 1x (tier 2), the darkest title pixel over the bezel in each state, probe
// mac-probes/aqua-toolbar.m of the research notes. Test: appkit-toolbar-controls-aqua.m (test_quirk_title_colours)
- (NSColor *) _aquaBezelTitleColor {
    if (![self _hasAquaToolbarBezel])
        return nil;

    BOOL enabled = [self isEnabled], pressed = [self _aquaBezelPressed], on = [self _aquaBezelOn];

    switch (NS_EXTRA(NSButtonCell, self)->_bezelStyle) {
    case NSTexturedRoundedBezelStyle:
    case NSTexturedSquareBezelStyle:
        if (on)
            return [NSColor colorWithCalibratedWhite: 1 alpha: enabled ? 1 : 0.6];
        return [NSColor colorWithCalibratedWhite: 0 alpha: enabled ? (pressed ? 0.85 : 0.65) : 0.25];
    case NSRecessedBezelStyle:
        return (enabled && (pressed || on)) ? [NSColor whiteColor] : nil;
    default:
        return nil;
    }
}

// QUIRK: the colour a template image is drawn in depends on the button. With the light appearance, black at
// 80 % opacity on a bordered button, 60 % on a textured one (white when a textured button shows its on state
// on its dark bezel) and 50 % without a border; half as opaque when the button is disabled. The image's own
// colours are not used, only its coverage. Not documented beyond "template images are drawn by the control in
// a suitable colour". Evidence: black-box renders of buttons with a template image on macOS 10.14.4 (tier 2).
// Test: tests/appkit-template-image-tint.m (test_quirk_template_image_colours)
- (NSColor *) _templateImageColor {
    NSBezelStyle bezel = NS_EXTRA(NSButtonCell, self)->_bezelStyle;
    BOOL textured = bezel == NSTexturedSquareBezelStyle || bezel == NSTexturedRoundedBezelStyle;

    if (![self isBordered])
        return [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.5];
    if (textured) {
        if ([self state] && ([self showsStateBy] & NSChangeBackgroundCellMask))
            return [NSColor whiteColor];
        return [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.6];
    }
    return [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.8];
}

- (NSRect) drawTitle: (NSAttributedString *) title
           withFrame: (NSRect) titleRect
              inView: (NSView *) controlView
{

    // The title is centered vertically in the frame it is given, which may be taller than the text; the
    // rectangle it was drawn in is returned.
    // QUIRK: not documented. Evidence: black-box observation on macOS 10.14.4 (flipped view) and 26.7.3
    // (flipped and unflipped view) of a 40 point frame with a 13 point title: the returned rectangle is the
    // height of the text and centered in the frame, and the ink lies in the middle rows. Mojave puts the
    // title at the top edge in a view that is not flipped; that is not followed because buttons are views
    // that are flipped there. Test: tests/appkit-button-cell-draw-title-centered.m
    // (test_quirk_button_cell_title_centered)
    NSSize textSize = [title size];
    CGFloat textHeight = MIN(ceil(textSize.height), titleRect.size.height);
    titleRect.origin.y += floor((titleRect.size.height - textHeight) / 2 + 0.5);
    titleRect.size.height = textHeight;

    [title _clipAndDrawInRect: titleRect];

    return titleRect; // FIXME: wrong value
}

// This function is duplicated in NSImageCell, consolidate
static NSSize scaledImageSizeInFrameSize(NSSize imageSize, NSSize frameSize,
                                         NSImageScaling scaling)
{

    switch (scaling) {
    case NSImageScaleProportionallyDown: {
        CGFloat xscale = frameSize.width / imageSize.width;
        CGFloat yscale = frameSize.height / imageSize.height;
        CGFloat scale = MIN(1.0, MIN(xscale, yscale));

        imageSize.width *= scale;
        imageSize.height *= scale;

        return imageSize;
    }

    case NSImageScaleAxesIndependently:
        return frameSize;

    case NSImageScaleProportionallyUpOrDown: {
        CGFloat xscale = frameSize.width / imageSize.width;
        CGFloat yscale = frameSize.height / imageSize.height;
        CGFloat scale = MIN(xscale, yscale);

        imageSize.width *= scale;
        imageSize.height *= scale;

        return imageSize;
    }

    default:
    case NSImageScaleNone:
        return imageSize;
    }
}

- (void) drawInteriorWithFrame: (NSRect) frame inView: (NSView *) controlView {
    /* This method gets the original button frame. We have to compensate for
       borders. There is some duplication of rect calculation which can be split
       out
     */
    BOOL defaulted = ([[controlView window] defaultButtonCell] == self);
    // The title area of a pop-up button is measured from the whole frame, not from the bezel's.
    NSRect wholeFrame = frame;
    NSRect adjustment =
            [self getControlSizeAdjustment: [controlView isFlipped]];
    frame.size.width -= adjustment.size.width;
    frame.size.height -= adjustment.size.height;
    frame.origin.x += adjustment.origin.x;
    frame.origin.y += adjustment.origin.y;

    if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSDisclosureBezelStyle)
        ;
    else if (![self isBordered]) {
        if (defaulted)
            frame = NSInsetRect(frame, 1, 1);
    } else {
        frame = NSInsetRect(frame, 2, 2);
    }

    NSAttributedString *title = [self titleForHighlight];
    NSImage *image = [self imageForHighlight];

    // QUIRK: the title of a plain-text rounded push button is white on the blue bezel of a default button in an
    // active window or of a pressed button. Evidence: black-box renders on macOS 10.14.4 (tier 2).
    // Test: appkit-button-aqua.m
    if ([self isBordered] && image == nil && [title length] > 0 &&
        NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSRoundedBezelStyle &&
        [NS_EXTRA(NSCell, self)->_titleOrAttributedTitle isKindOfClass: [NSString class]] && [self isEnabled]) {
        BOOL pressed = ([self highlightsBy] & NSPushInCellMask) && [self isHighlighted];

        if (pressed || (defaulted && [[controlView window] isKeyWindow])) {
            NSMutableAttributedString *white = [[title mutableCopy] autorelease];

            [white addAttribute: NSForegroundColorAttributeName
                          value: [NSColor whiteColor]
                          range: NSMakeRange(0, [white length])];
            title = white;
        }
    }
    NSColor *aquaTitleColor = [self _aquaBezelTitleColor];
    if (aquaTitleColor != nil && [title length] > 0 &&
        [NS_EXTRA(NSCell, self)->_titleOrAttributedTitle isKindOfClass: [NSString class]]) {
        NSMutableAttributedString *colored = [[title mutableCopy] autorelease];

        [colored addAttribute: NSForegroundColorAttributeName value: aquaTitleColor range: NSMakeRange(0, [colored length])];
        title = colored;
    }
    BOOL enabled = [self isEnabled] ? YES : ![self imageDimsWhenDisabled];
    BOOL mixed = ([self state] == NSMixedState) ? YES : NO;
    NSRect imageRect = [self imageRectForBounds: frame];
    NSSize imageSize = imageRect.size;
    NSPoint imageOrigin = imageRect.origin;
    NSSize titleSize = [title size];
    NSRect titleRect = [self titleRectForBounds: frame];
    if ([self isKindOfClass: [NSPopUpButtonCell class]]) {
        NSRect whole = [self titleRectForBounds: wholeFrame];

        titleRect.origin.x = whole.origin.x;
        titleRect.size.width = whole.size.width;
    }
    BOOL drawImage = YES, drawTitle = YES;
    NSCellImagePosition imagePosition = [self imagePosition];

    if ([self isTransparent])
        return;

    // it doesnt actually change the image pos in the button but it draws like
    // this
    if ([self bezelStyle] == NSDisclosureBezelStyle)
        imagePosition = NSImageOnly;

    imageSize = scaledImageSizeInFrameSize(imageSize, frame.size,
                                           [self imageScaling]);

    imageOrigin.x += floor((frame.size.width - imageSize.width) / 2);
    imageOrigin.y += floor((frame.size.height - imageSize.height) / 2);

    titleRect.origin.y += floor((titleRect.size.height - titleSize.height) / 2);
    titleRect.size.height = titleSize.height;

    switch (imagePosition) {

    case NSNoImage:
        drawImage = NO;
        break;

    case NSImageOnly:
        drawTitle = NO;
        break;

    case NSImageLeft:
        imageOrigin.x = frame.origin.x + kImageMargin;
        // a pop-up button without an image has no image area: its title area is already placed (see
        // -[NSPopUpButtonCell titleRectForBounds:])
        if (image == nil && [self isKindOfClass: [NSPopUpButtonCell class]])
            break;
        titleRect.origin.x += imageSize.width + 4;
        titleRect.size.width -= imageSize.width + 4;
        if ([self _isStockToggleImage: image])
            // a cell is as wide as its title and 18 points; the title may use the room the margin to the
            // right of it leaves, so that it is not truncated by the width of the image area
            titleRect.size.width += 4;
        break;

    case NSImageRight:
        imageOrigin.x = frame.origin.x + (frame.size.width - imageSize.width) -
                        kImageMargin;
        titleRect.size.width -= (imageSize.width + 4);
        break;

    case NSImageBelow:
        imageOrigin.y = frame.origin.y;
        titleRect.origin.y += imageSize.height;
        imageOrigin.y = MAX(frame.origin.y, imageOrigin.y);
        titleRect.origin.y =
                MIN(frame.origin.y + frame.size.height - titleRect.size.height,
                    titleRect.origin.y);
        break;

    case NSImageAbove:
        imageOrigin.y = frame.origin.y + (frame.size.height - imageSize.height);
        titleRect.origin.y -= imageSize.height;
        imageOrigin.y =
                MIN(frame.origin.y + frame.size.height - imageSize.height,
                    imageOrigin.y);
        titleRect.origin.y = MAX(frame.origin.y, titleRect.origin.y);
        break;

    case NSImageOverlaps:
        break;
    }

    if (![self isBordered]) {
        if ([self isVisuallyHighlighted]) {
            [[NSColor whiteColor] setFill];
            NSRectFill(frame);
        }
    }

    // the textured, recessed and round-rect bezels do not move their content while pressed
    if ([self isBordered] && ![self _hasAquaToolbarBezel]) {
        if (([self highlightsBy] & NSPushInCellMask) && [self isHighlighted]) {
            imageOrigin.x += 1;
            imageOrigin.y += [controlView isFlipped] ? 1 : -1;
            titleRect.origin.x += 1;
            titleRect.origin.y += [controlView isFlipped] ? 1 : -1;
        }
    }

    if (drawImage) {
        NSRect rect = NSMakeRect(imageOrigin.x, imageOrigin.y, imageSize.width,
                                 imageSize.height);
        [self drawImage: image withFrame: rect inView: controlView];
    }

    if (drawTitle) {
        [self drawTitle: title withFrame: titleRect inView: controlView];
    }
}

- (NSSize) cellSize {
    NSSize result = NSMakeSize(0, 0);
    NSAttributedString *title = [self attributedTitle];
    // Disclosure buttons draw a built-in glyph even when image is nil.
    // Measure that glyph, keeping the size independent of the current state.
    NSImage *image = NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSDisclosureBezelStyle
            ? [NSImage imageNamed: @"NSButtonCell_disclosure_normal"]
            : [self image];
    BOOL enabled = [self isEnabled] ? YES : ![self imageDimsWhenDisabled];
    BOOL mixed = ([self state] == NSMixedState) ? YES : NO;
    NSSize imageSize, titleSize;

    if (image == nil)
        imageSize = NSMakeSize(0, 0);
    else if (_controlView)
        imageSize = [[_controlView graphicsStyle] sizeOfButtonImage: image
                                                            enabled: enabled
                                                              mixed: mixed];
    else
        imageSize = [image size];

    if (title == nil) {
        titleSize = NSMakeSize(0, 0);
    } else {
        titleSize = [title size];
    }
    switch (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSDisclosureBezelStyle ? NSImageOnly : [self imagePosition]) {

    case NSNoImage:
        result = titleSize;
        break;

    case NSImageOnly:
        result = imageSize;
        break;

    case NSImageLeft:
    case NSImageRight:
        result.width = imageSize.width + 4 + titleSize.width;
        result.height = MAX(imageSize.height, titleSize.height);
        break;

    case NSImageBelow:
    case NSImageAbove:
        result.width = MAX(imageSize.width, titleSize.width);
        result.height = imageSize.height + 4 + titleSize.height;
        break;

    case NSImageOverlaps:
        result.width = MAX(imageSize.width, titleSize.width);
        result.height = MAX(imageSize.height, titleSize.height);
        break;
    }

    // Add some margin
    result.width += 4;
    if ([self isBordered] || [self isBezeled]) {
        result.width += 4;
        result.height += 4;
    }

    [self _applyStockButtonMetricsToSize: &result titleWidth: titleSize.width];

    NSRect adjustment = [self getControlSizeAdjustment: NO];
    result.width += adjustment.size.width;
    result.height += adjustment.size.height;

    return result;
}

// QUIRK: a rounded push button, a checkbox and a radio button have a size of their own derived from the
// title width: the title width plus a fixed amount per control size, rounded up. A push button also has a
// fixed height per control size. Not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2)
// of the intrinsic content size with titles of 0 to 196 points at the three control sizes; 26.7.3 differs
// and is not followed. The amounts are 28, 16 and 22 for push buttons (regular, small, mini; heights 21, 18
// and 15), 18, 17 and 16 for checkboxes and 19, 19 and 17 for radio buttons. The heights of checkboxes and
// radio buttons are described in the QUIRK in the toggle branch below.
// Test: tests/appkit-button-stock-intrinsic-size.m (test_quirk_stock_button_widths)
- (void) _applyStockButtonMetricsToSize: (NSSize *) size titleWidth: (CGFloat) titleWidth {
    NSControlSize controlSize = NS_EXTRA(NSCell, self)->_controlSize;
    int index = controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0);
    NSImage *image = [self image];

    if (image == nil) {
        static const CGFloat pushPadding[3] = {28, 16, 22};
        static const CGFloat pushHeight[3] = {21, 18, 15};

        if (NS_EXTRA(NSButtonCell, self)->_bezelStyle != NSRoundedBezelStyle || ![self isBordered] ||
            [self imagePosition] == NSImageOnly || [self isKindOfClass: [NSPopUpButtonCell class]])
            return;
        size->width = ceil(titleWidth + pushPadding[index]);
        size->height = pushHeight[index];
        return;
    }

    static const CGFloat switchPadding[3] = {18, 17, 16};
    static const CGFloat radioPadding[3] = {19, 19, 17};
    BOOL isSwitch = [[image name] isEqualToString: @"NSSwitch"];
    BOOL isRadio = [[image name] isEqualToString: @"NSRadioButton"];

    if ((isSwitch || isRadio) && [self imagePosition] == NSImageLeft) {
        NSEdgeInsets insets = [self _toggleAlignmentInsets];

        // QUIRK: the cell of a check box or radio button is as wide as the title plus the padding above and the
        // alignment insets (so its intrinsic width stays the title width plus the padding), and 18 points high at
        // every control size; the intrinsic height is that minus the insets. Not documented. Evidence: black-box
        // observation on macOS 10.14.4 (tier 2): -cellSize of check boxes and radio buttons with titles of
        // several widths at the three control sizes (vd-upstream/mac-probes/aqua-leftovers-metrics.m); 26.7.3
        // differs and is not followed. Test: test_quirk_toggle_metrics in tests/appkit-toggle-metrics.m
        size->width = ceil(titleWidth + (isSwitch ? switchPadding[index] : radioPadding[index])) + insets.left + insets.right;
        size->height = 18;
    }
}

// 0 for a button that is not a stock check box or radio button, 1 for a check box and 2 for a radio button.
- (int) _stockToggleKind {
    NSString *name = [[self image] name];

    if ([name isEqualToString: @"NSSwitch"])
        return 1;
    if ([name isEqualToString: @"NSRadioButton"])
        return 2;
    return 0;
}

// QUIRK: the alignment insets (top, left, bottom, right) of a check box are (2, 2, 2, 2) regular, (3, 3, 3, 2)
// small and (5, 4, 3, 2) mini, those of a radio button (1, 1, 1, 2), (2, 2, 2, 1) and (4, 4, 4, 1), in a flipped
// button. They are where the box sits in the 18 point high cell. Not documented. Evidence: black-box
// observation on macOS 10.14.4 (tier 2), -alignmentRectInsets of both at the three control sizes; 26.7.3
// differs and is not followed. Test: test_quirk_toggle_metrics in tests/appkit-toggle-metrics.m
- (NSEdgeInsets) _toggleAlignmentInsets {
    static const CGFloat check[3][4] = {{2, 2, 2, 2}, {3, 3, 3, 2}, {5, 4, 3, 2}};
    static const CGFloat radio[3][4] = {{1, 1, 1, 2}, {2, 2, 2, 1}, {4, 4, 4, 1}};
    NSControlSize controlSize = NS_EXTRA(NSCell, self)->_controlSize;
    int index = controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0);
    int kind = [self _stockToggleKind];

    if (kind == 0)
        return NSEdgeInsetsMake(0, 0, 0, 0);
    const CGFloat *v = kind == 1 ? check[index] : radio[index];
    return NSEdgeInsetsMake(v[0], v[1], v[2], v[3]);
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) control {
    _controlView = control;

    if ([self isTransparent])
        return;

    [self drawBezelWithFrame: frame inView: control];
    [self drawInteriorWithFrame: frame inView: control];
}

// The ring of a bordered button follows its bezel, the one of a check box or radio button the box (recorded when
// the box is drawn, see drawImage:withFrame:inView:). The bezel of a rounded-style button is its adjusted frame
// without the row of shadow below it.
static char toggleFocusRingPathKey;

- (NSBezierPath *) _focusRingPathWithFrame: (NSRect) frame inView: (NSView *) controlView {
    NSBezierPath *toggle = objc_getAssociatedObject(self, &toggleFocusRingPathKey);

    if (toggle != nil)
        return toggle;
    if (![self isBordered])
        return nil;

    NSRect adjustment = [self getControlSizeAdjustment: [controlView isFlipped]];
    frame.size.width -= adjustment.size.width;
    frame.size.height -= adjustment.size.height;
    frame.origin.x += adjustment.origin.x;
    frame.origin.y += adjustment.origin.y;

    switch (NS_EXTRA(NSButtonCell, self)->_bezelStyle) {
    case NSDisclosureBezelStyle:
    case NSRecessedBezelStyle:
        return nil;
    case NSRegularSquareBezelStyle:
    case NSTexturedSquareBezelStyle:
    case NSTexturedRoundedBezelStyle:
    case NSShadowlessSquareBezelStyle:
        return [NSBezierPath bezierPathWithRect: frame];
    default: {
        NSRect body = frame;

        body.size.height -= 1;
        if (![controlView isFlipped])
            body.origin.y += 1;
        CGFloat radius = MIN(4.5, NSHeight(body) / 4.5);

        return [NSBezierPath bezierPathWithRoundedRect: body xRadius: radius yRadius: radius];
    }
    }
}

- (void) performClick: sender {
    if ([_controlView respondsToSelector: @selector(performClick:)])
        [_controlView performSelector: @selector(performClick:)
                           withObject: sender];
}

// The border of a cell that shows it only while the pointer is over it is drawn between these two.
- (void) _setMouseInside: (BOOL) inside {
    if (!NS_EXTRA(NSButtonCell, self)->_showsBorderOnlyWhileMouseInside ||
        NS_EXTRA(NSButtonCell, self)->_mouseInside == inside)
        return;
    NS_EXTRA(NSButtonCell, self)->_mouseInside = inside;
    [[self controlView] setNeedsDisplay: YES];
}

- (void) mouseEntered: (NSEvent *) event {
    [self _setMouseInside: YES];
}

- (void) mouseExited: (NSEvent *) event {
    [self _setMouseInside: NO];
}

@end
