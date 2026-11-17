/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSFontDescriptor.h>

// The UIKit names for the font weights, descriptor keys and system designs. UIKit-for-Mac applications bind them to the AppKit
// install name, so AppKit exports them; they are declared in no AppKit header (UIKit's own headers declare them). They add
// symbols only: nothing that reads an NSFontDescriptor or NSFont changes. The strings and numbers are the values the exported
// constants hold on macOS 26.7.3 (black-box observation by reading the symbols; not present on macOS 10.14, which predates
// UIKit for Mac). Test: tests/appkit-ui-font-constants.m.

// The weights equal the NSFontWeight values (single-precision values widened to CGFloat; on 32-bit CGFloat is that float).
APPKIT_EXPORT const CGFloat UIFontWeightUltraLight;
APPKIT_EXPORT const CGFloat UIFontWeightThin;
APPKIT_EXPORT const CGFloat UIFontWeightLight;
APPKIT_EXPORT const CGFloat UIFontWeightRegular;
APPKIT_EXPORT const CGFloat UIFontWeightMedium;
APPKIT_EXPORT const CGFloat UIFontWeightSemibold;
APPKIT_EXPORT const CGFloat UIFontWeightBold;
APPKIT_EXPORT const CGFloat UIFontWeightHeavy;
APPKIT_EXPORT const CGFloat UIFontWeightBlack;

const CGFloat UIFontWeightUltraLight = -0.8f;
const CGFloat UIFontWeightThin = -0.6f;
const CGFloat UIFontWeightLight = -0.4f;
const CGFloat UIFontWeightRegular = 0;
const CGFloat UIFontWeightMedium = 0.23f;
const CGFloat UIFontWeightSemibold = 0.3f;
const CGFloat UIFontWeightBold = 0.4f;
const CGFloat UIFontWeightHeavy = 0.56f;
const CGFloat UIFontWeightBlack = 0.62f;

APPKIT_EXPORT NSFontDescriptorAttributeName const UIFontDescriptorFamilyAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const UIFontDescriptorNameAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const UIFontDescriptorSizeAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const UIFontDescriptorTraitsAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const UIFontDescriptorFeatureSettingsAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const UIFontDescriptorTextStyleAttribute;
APPKIT_EXPORT NSFontDescriptorFeatureKey const UIFontFeatureTypeIdentifierKey;
APPKIT_EXPORT NSFontDescriptorFeatureKey const UIFontFeatureSelectorIdentifierKey;
APPKIT_EXPORT NSFontDescriptorTraitKey const UIFontWeightTrait;
APPKIT_EXPORT NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignDefault;
APPKIT_EXPORT NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignSerif;
APPKIT_EXPORT NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignRounded;
APPKIT_EXPORT NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignMonospaced;
APPKIT_EXPORT NSString *const UIFontSystemFontDesignTrait;
APPKIT_EXPORT NSString *const UIFontSystemFontDesignDefault;
APPKIT_EXPORT NSString *const UIFontSystemFontDesignSerif;
APPKIT_EXPORT NSString *const UIFontSystemFontDesignRounded;
APPKIT_EXPORT NSString *const UIFontSystemFontDesignCompact;
APPKIT_EXPORT NSString *const UIFontSystemFontDesignCondensed;
APPKIT_EXPORT NSString *const NSFontSystemDesignRounded;

NSFontDescriptorAttributeName const UIFontDescriptorFamilyAttribute = @"NSFontFamilyAttribute";
NSFontDescriptorAttributeName const UIFontDescriptorNameAttribute = @"NSFontNameAttribute";
NSFontDescriptorAttributeName const UIFontDescriptorSizeAttribute = @"NSFontSizeAttribute";
NSFontDescriptorAttributeName const UIFontDescriptorTraitsAttribute = @"NSCTFontTraitsAttribute";
NSFontDescriptorAttributeName const UIFontDescriptorFeatureSettingsAttribute = @"NSCTFontFeatureSettingsAttribute";
NSFontDescriptorAttributeName const UIFontDescriptorTextStyleAttribute = @"NSCTFontUIUsageAttribute";
NSFontDescriptorFeatureKey const UIFontFeatureTypeIdentifierKey = @"CTFeatureTypeIdentifier";
NSFontDescriptorFeatureKey const UIFontFeatureSelectorIdentifierKey = @"CTFeatureSelectorIdentifier";
NSFontDescriptorTraitKey const UIFontWeightTrait = @"NSCTFontWeightTrait";
NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignDefault = @"NSCTFontUIFontDesignDefault";
NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignSerif = @"NSCTFontUIFontDesignSerif";
NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignRounded = @"NSCTFontUIFontDesignRounded";
NSFontDescriptorSystemDesign const UIFontDescriptorSystemDesignMonospaced = @"NSCTFontUIFontDesignMonospaced";
NSString *const UIFontSystemFontDesignTrait = @"NSCTFontUIFontDesignTrait";
NSString *const UIFontSystemFontDesignDefault = @"NSCTFontUIFontDesignDefault";
NSString *const UIFontSystemFontDesignSerif = @"NSCTFontUIFontDesignSerif";
NSString *const UIFontSystemFontDesignRounded = @"NSCTFontUIFontDesignRounded";
NSString *const UIFontSystemFontDesignCompact = @"NSCTFontUIFontDesignCompact";
NSString *const UIFontSystemFontDesignCondensed = @"NSCTFontUIFontDesignCondensed";
NSString *const NSFontSystemDesignRounded = @"NSCTFontUIFontDesignRounded";
