/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString* NSAppearanceName NS_EXTENSIBLE_STRING_ENUM;

APPKIT_EXPORT const NSAppearanceName NSAppearanceNameAqua;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameDarkAqua;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameLightContent;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameVibrantDark;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameVibrantLight;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameAccessibilityHighContrastAqua;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameAccessibilityHighContrastDarkAqua;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameAccessibilityHighContrastVibrantLight;
APPKIT_EXPORT const NSAppearanceName NSAppearanceNameAccessibilityHighContrastVibrantDark;

APPKIT_EXPORT const NSAppearanceName NSAppearanceNameControlStrip; // Undocumented

// Undocumented: whether the macOS 26 system design is in use.
APPKIT_EXPORT BOOL NSSolariumEnabled(void);

@class NSColor;

// Legacy ABI instance size: Apple's 28 bytes (see AppKitIvarLayout.h).
@interface NSAppearance : NSObject <NSSecureCoding> {
    NSAppearanceName _name;
    NS_LEGACY_IVAR_PAD(_NSAppearanceReserved, 24 - sizeof(void *))
    NS_EXTRA_IVARS_BEGIN(NSAppearance)
        BOOL _hasTintColor;
        NSColor *_tintColor;
    NS_EXTRA_IVARS_END(NSAppearance)
}

// One shared appearance per known name; nil for any other name.
+ (nullable NSAppearance *) appearanceNamed: (NSAppearanceName) name;

@property(readonly, copy) NSAppearanceName name;
- (nullable NSAppearanceName) bestMatchFromAppearancesWithNames:
        (NSArray<NSAppearanceName> *) appearances;

// The appearance AppKit draws with on the calling thread: the one
// -performAsCurrentDrawingAppearance: or +setCurrentAppearance: installed,
// else the application's effective appearance.
+ (NSAppearance *) currentDrawingAppearance;
- (void) performAsCurrentDrawingAppearance: (void (NS_NOESCAPE ^)(void)) block;
+ (NSAppearance *) currentAppearance;
+ (void) setCurrentAppearance: (nullable NSAppearance *) appearance;

@end

@class NSColor;

@interface NSAppearance (NSAppearanceColorAdjustment)
// Private AppKit: the color blended a fixed fraction towards black (darker)
// or white.
+ (null_unspecified NSColor *) colorByAdjustingLightnessOfColor: (null_unspecified NSColor *) color darker: (BOOL) darker;
@end

@protocol NSAppearanceCustomization <NSObject>

@required
@property (strong, nullable) NSAppearance *appearance;
@property (readonly, strong, nonnull) NSAppearance *effectiveAppearance;

@end

NS_ASSUME_NONNULL_END
