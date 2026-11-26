/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

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
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

// Darling has no Force Touch input, so a configuration only records its
// behavior.
@interface NSPressureConfiguration : NSObject {
    NSPressureBehavior _pressureBehavior;
    NS_LEGACY_IVAR_PAD(_NSPressureConfigurationReserved, 4)
}

@property(readonly) NSPressureBehavior pressureBehavior;

- (instancetype) initWithPressureBehavior: (NSPressureBehavior) pressureBehavior NS_DESIGNATED_INITIALIZER;

- (void) set;

@end
