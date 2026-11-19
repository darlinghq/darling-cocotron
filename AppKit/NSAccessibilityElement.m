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

#import <AppKit/NSAccessibilityElement.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import "NSAccessibilityStorage.h"

// An element an application creates for a part of its interface that has no view of its
// own. It reports what was set, and takes its window and, when it was given a frame in its
// parent's space, its frame from its parent.
static NSString *const frameInParentSpaceKey = @"_NSAccessibilityFrameInParentSpace";

@implementation NSAccessibilityElement

ACCESSIBILITY_COMMON_METHODS

+ (id) accessibilityElementWithRole: (NSString *) role
                              frame: (NSRect) frame
                              label: (NSString *) label
                             parent: (id) parent
{
    NSAccessibilityElement *element = [[[self alloc] init] autorelease];

    [element setAccessibilityRole: role];
    [element setAccessibilityFrame: frame];
    [element setAccessibilityLabel: label];
    [element setAccessibilityParent: parent];
    return element;
}

- (void) accessibilityAddChildElement: (NSAccessibilityElement *) childElement {
    NSArray *children = [self accessibilityChildren];

    [self setAccessibilityChildren: children ? [children arrayByAddingObject: childElement]
                                             : [NSArray arrayWithObject: childElement]];
    [childElement setAccessibilityParent: self];
}

- (BOOL) isAccessibilityElement {
    return _NSAccessibilityStoredBool(self, _NSAccessibilityElementKey, YES);
}

- (void) setAccessibilityElement: (BOOL) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityElementKey, [NSNumber numberWithBool: value]);
}

- (NSAccessibilityRole) accessibilityRole {
    return _NSAccessibilityStoredObject(self, NSAccessibilityRoleAttribute, nil);
}

- (NSArray *) accessibilityChildren {
    return _NSAccessibilityStoredObject(self, NSAccessibilityChildrenAttribute, nil);
}

- (id) accessibilityParent {
    return _NSAccessibilityStoredObject(self, NSAccessibilityParentAttribute, nil);
}

- (id) accessibilityWindow {
    return _NSAccessibilityStoredObject(self, NSAccessibilityWindowAttribute, [[self accessibilityParent] accessibilityWindow]);
}

- (id) accessibilityTopLevelUIElement {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTopLevelUIElementAttribute,
                        [[self accessibilityParent] accessibilityTopLevelUIElement]);
}

- (NSRect) accessibilityFrameInParentSpace {
    return _NSAccessibilityStoredRect(self, frameInParentSpaceKey, NSZeroRect);
}

// The last of the two frames set is the one that counts.
- (void) setAccessibilityFrameInParentSpace: (NSRect) frame {
    _NSAccessibilitySetStoredValue(self, frameInParentSpaceKey, [NSValue valueWithRect: frame]);
    _NSAccessibilityRemoveStoredValue(self, _NSAccessibilityFrameKey);
}

- (void) setAccessibilityFrame: (NSRect) frame {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityFrameKey, [NSValue valueWithRect: frame]);
    _NSAccessibilityRemoveStoredValue(self, frameInParentSpaceKey);
}

- (NSRect) accessibilityFrame {
    id value;
    if (!_NSAccessibilityStoredValue(self, frameInParentSpaceKey, &value))
        return _NSAccessibilityStoredRect(self, _NSAccessibilityFrameKey, NSZeroRect);

    NSRect frame = [value rectValue];
    id parent = [self accessibilityParent];

    if ([parent isKindOfClass: [NSView class]])
        return NSAccessibilityFrameInView(parent, frame);

    NSPoint origin = [parent accessibilityFrame].origin;
    return NSOffsetRect(frame, origin.x, origin.y);
}

- (NSString *) accessibilityLabel {
    return _NSAccessibilityStoredObject(self, NSAccessibilityDescriptionAttribute, nil);
}

- (NSString *) accessibilityTitle {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTitleAttribute, nil);
}

- (id) accessibilityValue {
    return _NSAccessibilityStoredObject(self, NSAccessibilityValueAttribute, nil);
}

- (BOOL) isAccessibilityEnabled {
    return _NSAccessibilityStoredBool(self, NSAccessibilityEnabledAttribute, NO);
}

@end
