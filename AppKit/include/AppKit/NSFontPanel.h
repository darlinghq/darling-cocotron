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

#import <AppKit/NSPanel.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSTextField, NSMatrix, NSButton, NSFont;

typedef NS_OPTIONS(NSUInteger, NSFontPanelModeMask) {
    NSFontPanelModeMaskFace = 1 << 0,
    NSFontPanelModeMaskSize = 1 << 1,
    NSFontPanelModeMaskCollection = 1 << 2,
    NSFontPanelModeMaskUnderlineEffect = 1<<8,
    NSFontPanelModeMaskStrikethroughEffect = 1<<9,
    NSFontPanelModeMaskTextColorEffect = 1<< 10,
    NSFontPanelModeMaskDocumentColorEffect = 1<<11,
    NSFontPanelModeMaskShadowEffect = 1<<12,
    NSFontPanelModeMaskAllEffects = 0XFFF00,
    NSFontPanelModesMaskStandardModes = 0xFFFF,
    NSFontPanelModesMaskAllModes = 0xFFFFFFFF,
};

@interface NSFontPanel : NSPanel {
    NSTextField *_sampleTextField;
    NSMatrix *_familyMatrix;
    NSMatrix *_typefaceMatrix;
    NSTextField *_sizeTextField;
    NSMatrix *_sizeMatrix;

    NSButton *_setButton;
    NSButton *_revertButton;
    NSView *_accessoryView;
    NS_LEGACY_IVAR_PAD(_NSFontPanelReserved, 448)
}

+ (BOOL) sharedFontPanelExists;
+ (NSFontPanel *) sharedFontPanel;

- (BOOL) isEnabled;
- (NSView *) accessoryView;

- (void) setEnabled: (BOOL) value;
- (void) setAccessoryView: (NSView *) view;

- (BOOL) worksWhenModal;
- (void) reloadDefaultFontFamilies;

- (void) setPanelFont: (NSFont *) font isMultiple: (BOOL) isMultiple;
- (NSFont *) panelConvertFont: (NSFont *) font;

- (void) set: sender;
- (void) revert: sender;

@end
