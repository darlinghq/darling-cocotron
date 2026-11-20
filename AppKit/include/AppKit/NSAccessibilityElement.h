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

#import <AppKit/NSAccessibility.h>
#import <Foundation/NSObject.h>

@interface NSAccessibilityElement : NSObject <NSAccessibility, NSAccessibilityElement>

+ (id) accessibilityElementWithRole: (NSString *) role
                              frame: (NSRect) frame
                              label: (NSString *) label
                             parent: (id) parent;

- (void) accessibilityAddChildElement: (NSAccessibilityElement *) childElement;

// The element's frame in the coordinates of its parent: a view's own coordinates, or
// relative to the origin of any other parent's accessibilityFrame. Once set,
// accessibilityFrame follows the parent.
@property NSRect accessibilityFrameInParentSpace;

@end
