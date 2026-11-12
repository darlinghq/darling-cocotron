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
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

typedef NSString* NSAppearanceName;

APPKIT_EXPORT NSString *const NSAppearanceNameAqua;
APPKIT_EXPORT NSString *const NSAppearanceNameDarkAqua;
APPKIT_EXPORT NSString *const NSAppearanceNameLightContent;
APPKIT_EXPORT NSString *const NSAppearanceNameVibrantDark;
APPKIT_EXPORT NSString *const NSAppearanceNameVibrantLight;
APPKIT_EXPORT NSString *const NSAppearanceNameAccessibilityHighContrastAqua;
APPKIT_EXPORT NSString *const NSAppearanceNameAccessibilityHighContrastDarkAqua;
APPKIT_EXPORT NSString
        *const NSAppearanceNameAccessibilityHighContrastVibrantLight;
APPKIT_EXPORT NSString
        *const NSAppearanceNameAccessibilityHighContrastVibrantDark;

APPKIT_EXPORT NSString *const NSAppearanceNameControlStrip; // Undocumented

@interface NSAppearance : NSObject <NSSecureCoding> {
    NSAppearanceName _name;
}

// One shared appearance per known name; nil for any other name.
+ (NSAppearance *) appearanceNamed: (NSAppearanceName) name;

@property(readonly, copy) NSAppearanceName name;
- (NSAppearanceName) bestMatchFromAppearancesWithNames:
        (NSArray<NSAppearanceName> *) appearances;

// The appearance AppKit draws with on the calling thread: the one
// -performAsCurrentDrawingAppearance: or +setCurrentAppearance: installed,
// else the application's effective appearance.
+ (NSAppearance *) currentDrawingAppearance;
- (void) performAsCurrentDrawingAppearance: (void (^)(void)) block;
+ (NSAppearance *) currentAppearance;
+ (void) setCurrentAppearance: (NSAppearance *) appearance;

@end

@class NSColor;

@interface NSAppearance (NSAppearanceColorAdjustment)
// Private AppKit: the color blended a fixed fraction towards black (darker)
// or white.
+ (NSColor *) colorByAdjustingLightnessOfColor: (NSColor *) color darker: (BOOL) darker;
@end

@protocol NSAppearanceCustomization <NSObject>

@required
@property (strong) NSAppearance *appearance;

@end
