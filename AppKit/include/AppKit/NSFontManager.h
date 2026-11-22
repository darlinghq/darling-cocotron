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

#import <Foundation/Foundation.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSFont, NSFontDescriptor, NSFontPanel, NSMenu;

NS_ASSUME_NONNULL_BEGIN

typedef unsigned NSFontTraitMask;

typedef enum {
    NSNoFontChangeAction = 0,
    NSViaPanelFontAction = 1,
    NSAddTraitFontAction = 2,
    NSSizeUpFontAction = 3,
    NSSizeDownFontAction = 4,
    NSHeavierFontAction = 5,
    NSLighterFontAction = 6,
    NSRemoveTraitFontAction = 7,
} NSFontAction;

enum {
    NSItalicFontMask = 0x00000001,
    NSBoldFontMask = 0x00000002,
    NSUnboldFontMask = 0x00000004,
    NSNonStandardCharacterSetFontMask = 0x00000008,
    NSNarrowFontMask = 0x00000010,
    NSExpandedFontMask = 0x00000020,
    NSCondensedFontMask = 0x00000040,
    NSSmallCapsFontMask = 0x00000080,
    NSPosterFontMask = 0x00000100,
    NSCompressedFontMask = 0x00000200,
    NSFixedPitchFontMask = 0x00000400,
    NSUnitalicFontMask = 0x01000000,
};

typedef NS_OPTIONS(NSUInteger, NSFontCollectionOptions) {
    NSFontCollectionApplicationOnlyMask = 1 << 0,
};

@interface NSFontManager : NSObject {
    NSFontPanel *_panel;
    id _delegate;
    id _target;
    SEL _action;

    NSFont *_selectedFont;
    BOOL _isMultiple;
    NSFontAction _currentFontAction;
    int _currentTrait;
    NS_LEGACY_IVAR_PAD(_NSFontManagerReserved, 12)
    NS_EXTRA_IVARS_BEGIN(NSFontManager)
        NSMenu *_fontMenu;
    NS_EXTRA_IVARS_END(NSFontManager)
}

@property(class, readonly, retain, nonnull) NSFontManager *sharedFontManager;

+ (void) setFontManagerFactory: (nullable Class) value;
+ (void) setFontPanelFactory: (nullable Class) value;

- (nullable id) delegate;
- (nullable id) target;
@property(nonatomic) SEL action;

- (void) setDelegate: (nullable id) delegate;
- (void) setTarget: (nullable id) target;

- (NSFontAction) currentFontAction;

- (NSArray *) collectionNames;
- (BOOL) addCollection: (NSString *) name options: (int) options;
- (void) addFontDescriptors: (NSArray *) descriptors
               toCollection: (NSString *) name;
- (BOOL) removeCollection: (NSString *) name;

- (nullable NSArray *) fontDescriptorsInCollection: (NSString *) name;

- (NSArray<NSString *> *) availableFonts;
- (NSArray<NSString *> *) availableFontFamilies;
- (nullable NSArray<NSArray *> *) availableMembersOfFontFamily: (NSString *) name;
- (nullable NSArray *) availableFontNamesMatchingFontDescriptor:
        (NSFontDescriptor *) descriptor;
- (nullable NSArray<NSString *> *) availableFontNamesWithTraits: (NSFontTraitMask) traits;

- (BOOL) fontNamed: (NSString *) name hasTraits: (NSFontTraitMask) traits;
- (nullable NSFont *) fontWithFamily: (NSString *) family
                     traits: (NSFontTraitMask) traits
                     weight: (int) weight
                       size: (CGFloat) size;
- (int) weightOfFont: (NSFont *) font;
- (NSFontTraitMask) traitsOfFont: (NSFont *) font;

- (NSString *) localizedNameForFamily: (NSString *) family
                                 face: (nullable NSString *) face;

- (nullable NSFontPanel *) fontPanel: (BOOL) create;

// Documented on the AppKit pages of NSFontManager setFontMenu(_:) and
// fontMenu(_:) (their external identifiers are the selectors setFontMenu: and
// fontMenu:). Darling only records the menu: it takes no part in the font-menu
// configuration of the main menu, and -fontMenu:YES does not build a default
// Font menu.
- (void) setFontMenu: (NSMenu *) newMenu;
- (nullable NSMenu *) fontMenu: (BOOL) create;

- (BOOL) sendAction;

- (BOOL) isEnabled;
- (BOOL) isMultiple;
- (nullable NSFont *) selectedFont;

- (void) setSelectedFont: (NSFont *) font isMultiple: (BOOL) isMultiple;
// Uses the NSFontAttributeName font; other attributes are ignored.
- (void) setSelectedAttributes: (NSDictionary<NSString *, id> *) attributes isMultiple: (BOOL) flag;

- (NSFont *) convertFont: (NSFont *) font;
- (NSFont *) convertFont: (NSFont *) font toSize: (CGFloat) size;
- (NSFont *) convertFont: (NSFont *) font toHaveTrait: (NSFontTraitMask) trait;
- (NSFont *) convertFont: (NSFont *) font
          toNotHaveTrait: (NSFontTraitMask) trait;

- (nullable NSFont *) convertFont: (NSFont *) font toFace: (NSString *) typeface;
- (NSFont *) convertFont: (NSFont *) font toFamily: (NSString *) family;
- (NSFont *) convertWeight: (BOOL) heavierNotLighter ofFont: (NSFont *) font;

- (NSDictionary<NSString *, id> *) convertAttributes: (NSDictionary<NSString *, id> *) attributes;

- (void) addFontTrait: (nullable id) sender;
- (void) modifyFont: (nullable id) sender;
- (void) modifyFontViaPanel: (nullable id) sender;
- (void) removeFontTrait: (nullable id) sender;

- (void) orderFrontFontPanel: (nullable id) sender;
- (void) orderFrontStylesPanel: (nullable id) sender;

@end

@interface NSObject (NSFontManager_delegate)
- (BOOL) fontManager: (id) sender willIncludeFont: (NSString *) fontName;
@end

NS_ASSUME_NONNULL_END
