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

#import <AppKit/AppKitExport.h>
#import <Foundation/NSString.h>

// Item identifiers of the inspector bar, which AppKit exports but no public
// header declares. The value of each is its own name.

APPKIT_EXPORT NSString *const NSInspectorBarFontFamilyItemIdentifier;
APPKIT_EXPORT NSString *const NSInspectorBarFontSizeItemIdentifier;
APPKIT_EXPORT NSString *const NSInspectorBarFontStyleItemIdentifier;
APPKIT_EXPORT NSString *const NSInspectorBarSpaceItemIdentifier;
APPKIT_EXPORT NSString *const NSInspectorBarTextAlignmentItemIdentifier;
APPKIT_EXPORT NSString *const NSInspectorBarTextBackgroundColorItemIdentifier;
APPKIT_EXPORT NSString *const NSInspectorBarTextForegroundColorItemIdentifier;
APPKIT_EXPORT NSString *const NSInspectorBarTextListItemIdentifier;

NSString *const NSInspectorBarFontFamilyItemIdentifier =
        @"NSInspectorBarFontFamilyItemIdentifier";
NSString *const NSInspectorBarFontSizeItemIdentifier =
        @"NSInspectorBarFontSizeItemIdentifier";
NSString *const NSInspectorBarFontStyleItemIdentifier =
        @"NSInspectorBarFontStyleItemIdentifier";
NSString *const NSInspectorBarSpaceItemIdentifier =
        @"NSInspectorBarSpaceItemIdentifier";
NSString *const NSInspectorBarTextAlignmentItemIdentifier =
        @"NSInspectorBarTextAlignmentItemIdentifier";
NSString *const NSInspectorBarTextBackgroundColorItemIdentifier =
        @"NSInspectorBarTextBackgroundColorItemIdentifier";
NSString *const NSInspectorBarTextForegroundColorItemIdentifier =
        @"NSInspectorBarTextForegroundColorItemIdentifier";
NSString *const NSInspectorBarTextListItemIdentifier =
        @"NSInspectorBarTextListItemIdentifier";
