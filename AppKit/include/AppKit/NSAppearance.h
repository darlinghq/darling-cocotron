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

@interface NSAppearance : NSObject <NSSecureCoding>

+ (NSAppearance *) appearanceNamed: (NSAppearanceName) name;

@end

@protocol NSAppearanceCustomization <NSObject>

@required
@property (strong) NSAppearance *appearance;

@end
