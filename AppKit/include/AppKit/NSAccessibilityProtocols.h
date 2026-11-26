/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free softwareyou can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http//www.gnu.org/licenses/>.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

// Role and subrole values are the NSAccessibilityRole and NSAccessibilitySubrole strings of
// NSAccessibilityConstants.h, which cannot be imported here: through NSAttributedString.h
// it leads back to NSView.h, which imports this header.
@class NSArray, NSString, NSAccessibilityCustomAction;

// The minimum an object exposed to assistive applications provides.
@protocol NSAccessibilityElement <NSObject>

@required
- (NSRect) accessibilityFrame;
- (id) accessibilityParent;

@optional
- (BOOL) isAccessibilityFocused;
- (NSString *) accessibilityIdentifier;

@end

// The property-based accessibility API (macOS 10.10). NSView, NSWindow, NSCell, NSMenuItem
// and NSApplication implement these; there is no assistive-technology backend behind them.
@protocol NSAccessibility <NSObject>

@required
@property(getter = isAccessibilityElement) BOOL accessibilityElement;
@property NSRect accessibilityFrame;
@property(getter = isAccessibilityFocused) BOOL accessibilityFocused;
@property(assign) id accessibilityParent;
@property(copy) NSString *accessibilityIdentifier;

@optional
@property(copy) NSString *accessibilityRole;
@property(copy) NSString *accessibilityRoleDescription;
@property(copy) NSString *accessibilitySubrole;
@property(copy) NSString *accessibilityLabel;
@property(copy) NSString *accessibilityTitle;
@property(strong) id accessibilityValue;
@property(copy) NSString *accessibilityValueDescription;
@property(copy) NSString *accessibilityHelp;
@property(copy) NSString *accessibilityPlaceholderValue;
// The URL of the file the element represents, as a string (macOS 10.10); stored only.
@property(copy) NSString *accessibilityDocument;
@property(strong) id accessibilityMinValue;
@property(strong) id accessibilityMaxValue;
@property(getter = isAccessibilityEnabled) BOOL accessibilityEnabled;
@property(getter = isAccessibilitySelected) BOOL accessibilitySelected;
@property(getter = isAccessibilityRequired) BOOL accessibilityRequired;
@property(getter = isAccessibilityExpanded) BOOL accessibilityExpanded;
@property(copy) NSArray *accessibilityChildren;
@property(copy) NSArray *accessibilitySelectedChildren;
@property(copy) NSArray *accessibilityVisibleChildren;
@property(copy) NSArray *accessibilityContents;
@property(copy) NSArray *accessibilityLinkedUIElements;
@property(copy) NSArray *accessibilityServesAsTitleForUIElements;
@property(assign) id accessibilityTitleUIElement;
@property(assign) id accessibilityWindow;
@property(assign) id accessibilityTopLevelUIElement;
@property(copy) NSArray<NSAccessibilityCustomAction *> *accessibilityCustomActions;

@end

// An element that groups others (the group role); it asks for nothing more.
@protocol NSAccessibilityGroup <NSAccessibilityElement>
@end
