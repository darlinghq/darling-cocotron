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

// The NSAccessibility protocol (macOS 10.10) for NSView, NSControl, NSCell and its
// control cells, NSWindow and NSApplication, and the legacy attribute methods
// (accessibilityAttributeValue: and friends) on top of it. NSAccessibilityElement.m
// uses the same storage and methods.
//
// Every property can be set; a set value replaces the computed default and is kept
// per object. The defaults are those of macOS 10.14 and 26: views are not elements
// and stand for their unignored descendants, controls stand for their cells, cells
// and windows are elements, and parents are the nearest unignored ancestor.
//
// Nothing here talks to an assistive-technology service: there is no such backend.

#import <AppKit/NSAccessibility.h>
#import <AppKit/NSAccessibilityConstants.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageCell.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <objc/runtime.h>
#import "NSAccessibilityStorage.h"

static char storedValuesKey;

BOOL _NSAccessibilityStoredValue(id element, NSString *key, id *value) {
    NSDictionary *values = objc_getAssociatedObject(element, &storedValuesKey);
    id stored = [values objectForKey: key];

    if (stored == nil)
        return NO;
    *value = (stored == [NSNull null]) ? nil : stored;
    return YES;
}

void _NSAccessibilitySetStoredValue(id element, NSString *key, id value) {
    NSMutableDictionary *values = objc_getAssociatedObject(element, &storedValuesKey);

    if (values == nil) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(element, &storedValuesKey, values,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [values setObject: value ? value : [NSNull null] forKey: key];
}

void _NSAccessibilityRemoveStoredValue(id element, NSString *key) {
    [objc_getAssociatedObject(element, &storedValuesKey) removeObjectForKey: key];
}

id _NSAccessibilityStoredObject(id element, NSString *key, id fallback) {
    id value;
    return _NSAccessibilityStoredValue(element, key, &value) ? value : fallback;
}

BOOL _NSAccessibilityStoredBool(id element, NSString *key, BOOL fallback) {
    id value;
    return _NSAccessibilityStoredValue(element, key, &value) ? [value boolValue] : fallback;
}

NSRect _NSAccessibilityStoredRect(id element, NSString *key, NSRect fallback) {
    id value;
    return _NSAccessibilityStoredValue(element, key, &value) ? [value rectValue] : fallback;
}

NSArray *_NSAccessibilityLegacyAttributeNames(void) {
    return [NSArray arrayWithObjects:
        NSAccessibilityRoleAttribute, NSAccessibilityRoleDescriptionAttribute,
        NSAccessibilitySubroleAttribute, NSAccessibilityParentAttribute,
        NSAccessibilityChildrenAttribute, NSAccessibilityWindowAttribute,
        NSAccessibilityTopLevelUIElementAttribute, NSAccessibilityEnabledAttribute,
        NSAccessibilityFocusedAttribute, NSAccessibilityDescriptionAttribute,
        NSAccessibilityTitleAttribute, NSAccessibilityValueAttribute,
        NSAccessibilityHelpAttribute, NSAccessibilityIdentifierAttribute, nil];
}

id _NSAccessibilityLegacyAttributeValue(id element, NSString *attribute) {
    if ([attribute isEqualToString: NSAccessibilityRoleAttribute])
        return [element accessibilityRole];
    if ([attribute isEqualToString: NSAccessibilityRoleDescriptionAttribute])
        return [element accessibilityRoleDescription];
    if ([attribute isEqualToString: NSAccessibilitySubroleAttribute])
        return [element accessibilitySubrole];
    if ([attribute isEqualToString: NSAccessibilityParentAttribute])
        return [element accessibilityParent];
    if ([attribute isEqualToString: NSAccessibilityChildrenAttribute])
        return [element accessibilityChildren];
    if ([attribute isEqualToString: NSAccessibilityWindowAttribute])
        return [element accessibilityWindow];
    if ([attribute isEqualToString: NSAccessibilityTopLevelUIElementAttribute])
        return [element accessibilityTopLevelUIElement];
    if ([attribute isEqualToString: NSAccessibilityEnabledAttribute])
        return [NSNumber numberWithBool: [element isAccessibilityEnabled]];
    if ([attribute isEqualToString: NSAccessibilityFocusedAttribute])
        return [NSNumber numberWithBool: [element isAccessibilityFocused]];
    if ([attribute isEqualToString: NSAccessibilityDescriptionAttribute])
        return [element accessibilityLabel];
    if ([attribute isEqualToString: NSAccessibilityTitleAttribute])
        return [element accessibilityTitle];
    if ([attribute isEqualToString: NSAccessibilityValueAttribute])
        return [element accessibilityValue];
    if ([attribute isEqualToString: NSAccessibilityHelpAttribute])
        return [element accessibilityHelp];
    if ([attribute isEqualToString: NSAccessibilityIdentifierAttribute])
        return [element accessibilityIdentifier];
    return nil;
}

void _NSAccessibilityLegacySetAttributeValue(id element, NSString *attribute, id value) {
    if ([attribute isEqualToString: NSAccessibilityFocusedAttribute])
        [element setAccessibilityFocused: [value boolValue]];
    else if ([attribute isEqualToString: NSAccessibilityValueAttribute])
        [element setAccessibilityValue: value];
}

// The children of a view: its shown subviews, each ignored one replaced by its own
// unignored children.
static NSArray *viewChildren(NSView *view) {
    NSMutableArray *shown = [NSMutableArray array];

    for (NSView *subview in [view subviews]) {
        if (![subview isHidden])
            [shown addObject: subview];
    }
    return NSAccessibilityUnignoredChildren(shown);
}

@implementation NSView (NSAccessibility)

ACCESSIBILITY_COMMON_METHODS

- (BOOL) isAccessibilityElement {
    return _NSAccessibilityStoredBool(self, _NSAccessibilityElementKey, NO);
}

- (void) setAccessibilityElement: (BOOL) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityElementKey, [NSNumber numberWithBool: value]);
}

- (void) setAccessibilityFrame: (NSRect) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityFrameKey, [NSValue valueWithRect: value]);
}

- (NSAccessibilityRole) accessibilityRole {
    return _NSAccessibilityStoredObject(self, NSAccessibilityRoleAttribute, NSAccessibilityUnknownRole);
}

- (NSArray *) accessibilityChildren {
    id value;
    if (_NSAccessibilityStoredValue(self, NSAccessibilityChildrenAttribute, &value))
        return value;
    return viewChildren(self);
}

- (id) accessibilityParent {
    id value;
    if (_NSAccessibilityStoredValue(self, NSAccessibilityParentAttribute, &value))
        return value;

    NSWindow *window = [self window];
    NSView *superview = [self superview];

    // The content view, and the views of the window frame around it, belong to the window.
    if (superview == nil || superview == [[window contentView] superview])
        return window;
    return NSAccessibilityUnignoredAncestor(superview);
}

- (id) accessibilityWindow {
    return _NSAccessibilityStoredObject(self, NSAccessibilityWindowAttribute, [self window]);
}

- (id) accessibilityTopLevelUIElement {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTopLevelUIElementAttribute, [self window]);
}

- (NSRect) accessibilityFrame {
    return _NSAccessibilityStoredRect(self, _NSAccessibilityFrameKey, NSAccessibilityFrameInView(self, [self bounds]));
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

@implementation NSControl (NSAccessibility)

// A control stands for its cell, which is the element.
- (NSArray *) accessibilityChildren {
    id value;
    if (_NSAccessibilityStoredValue(self, NSAccessibilityChildrenAttribute, &value))
        return value;

    NSCell *cell = [self cell];
    NSArray *children = viewChildren(self);

    return cell ? [[NSArray arrayWithObject: cell] arrayByAddingObjectsFromArray: children] : children;
}

- (NSString *) accessibilityLabel {
    return _NSAccessibilityStoredObject(self, NSAccessibilityDescriptionAttribute, [[self cell] accessibilityLabel]);
}

- (NSString *) accessibilityTitle {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTitleAttribute, [[self cell] accessibilityTitle]);
}

- (id) accessibilityValue {
    return _NSAccessibilityStoredObject(self, NSAccessibilityValueAttribute, [[self cell] accessibilityValue]);
}

- (BOOL) isAccessibilityEnabled {
    return _NSAccessibilityStoredBool(self, NSAccessibilityEnabledAttribute, [self isEnabled]);
}

@end

@implementation NSCell (NSAccessibility)

ACCESSIBILITY_COMMON_METHODS

- (BOOL) isAccessibilityElement {
    return _NSAccessibilityStoredBool(self, _NSAccessibilityElementKey, YES);
}

- (void) setAccessibilityElement: (BOOL) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityElementKey, [NSNumber numberWithBool: value]);
}

- (void) setAccessibilityFrame: (NSRect) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityFrameKey, [NSValue valueWithRect: value]);
}

- (NSAccessibilityRole) accessibilityRole {
    return _NSAccessibilityStoredObject(self, NSAccessibilityRoleAttribute, [self _accessibilityDefaultRole]);
}

- (NSAccessibilityRole) _accessibilityDefaultRole {
    return NSAccessibilityUnknownRole;
}

- (NSArray *) accessibilityChildren {
    return _NSAccessibilityStoredObject(self, NSAccessibilityChildrenAttribute, nil);
}

- (id) accessibilityParent {
    return _NSAccessibilityStoredObject(self, NSAccessibilityParentAttribute,
                        NSAccessibilityUnignoredAncestor([self controlView]));
}

- (id) accessibilityWindow {
    return _NSAccessibilityStoredObject(self, NSAccessibilityWindowAttribute, [[self controlView] window]);
}

- (id) accessibilityTopLevelUIElement {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTopLevelUIElementAttribute,
                        [[self controlView] window]);
}

- (NSRect) accessibilityFrame {
    NSView *controlView = [self controlView];
    return _NSAccessibilityStoredRect(self, _NSAccessibilityFrameKey, controlView ? [controlView accessibilityFrame] : NSZeroRect);
}

- (NSString *) accessibilityLabel {
    return _NSAccessibilityStoredObject(self, NSAccessibilityDescriptionAttribute, [self _accessibilityDefaultTitle]);
}

- (NSString *) accessibilityTitle {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTitleAttribute, [self _accessibilityDefaultTitle]);
}

- (NSString *) _accessibilityDefaultTitle {
    return nil;
}

- (id) accessibilityValue {
    return _NSAccessibilityStoredObject(self, NSAccessibilityValueAttribute, [self _accessibilityDefaultValue]);
}

- (id) _accessibilityDefaultValue {
    return nil;
}

- (BOOL) isAccessibilityEnabled {
    return _NSAccessibilityStoredBool(self, NSAccessibilityEnabledAttribute, [self isEnabled]);
}

@end

@implementation NSButtonCell (NSAccessibility)

static BOOL imageIsNamed(NSImage *image, NSString *name, NSString *highlightedName) {
    NSString *imageName = [image name];
    return [imageName isEqualToString: name] || [imageName isEqualToString: highlightedName];
}

// Check boxes and radio buttons are the button types that draw the stock toggle images.
- (NSAccessibilityRole) _accessibilityDefaultRole {
    if (imageIsNamed([self image], @"NSSwitch", @"NSHighlightedSwitch"))
        return NSAccessibilityCheckBoxRole;
    if (imageIsNamed([self image], @"NSRadioButton", @"NSHighlightedRadioButton"))
        return NSAccessibilityRadioButtonRole;
    return NSAccessibilityButtonRole;
}

- (NSString *) _accessibilityDefaultTitle {
    return [self title];
}

- (id) _accessibilityDefaultValue {
    NSAccessibilityRole role = [self _accessibilityDefaultRole];

    if (role == NSAccessibilityCheckBoxRole || role == NSAccessibilityRadioButtonRole)
        return [NSNumber numberWithInteger: [self state]];
    return nil;
}

@end

@implementation NSPopUpButtonCell (NSAccessibility)

- (NSAccessibilityRole) _accessibilityDefaultRole {
    return NSAccessibilityPopUpButtonRole;
}

- (id) _accessibilityDefaultValue {
    return [self titleOfSelectedItem];
}

@end

@implementation NSTextFieldCell (NSAccessibility)

- (NSAccessibilityRole) _accessibilityDefaultRole {
    return [self isEditable] ? NSAccessibilityTextFieldRole : NSAccessibilityStaticTextRole;
}

- (id) _accessibilityDefaultValue {
    return [self stringValue];
}

@end

@implementation NSSliderCell (NSAccessibility)

- (NSAccessibilityRole) _accessibilityDefaultRole {
    return NSAccessibilitySliderRole;
}

- (id) _accessibilityDefaultValue {
    return [NSNumber numberWithDouble: [self doubleValue]];
}

- (id) accessibilityMinValue {
    return _NSAccessibilityStoredObject(self, NSAccessibilityMinValueAttribute,
                        [NSNumber numberWithDouble: [self minValue]]);
}

- (id) accessibilityMaxValue {
    return _NSAccessibilityStoredObject(self, NSAccessibilityMaxValueAttribute,
                        [NSNumber numberWithDouble: [self maxValue]]);
}

@end

@implementation NSImageCell (NSAccessibility)

- (NSAccessibilityRole) _accessibilityDefaultRole {
    return NSAccessibilityImageRole;
}

@end

@implementation NSWindow (NSAccessibility)

ACCESSIBILITY_COMMON_METHODS

- (BOOL) isAccessibilityElement {
    return _NSAccessibilityStoredBool(self, _NSAccessibilityElementKey, YES);
}

- (void) setAccessibilityElement: (BOOL) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityElementKey, [NSNumber numberWithBool: value]);
}

- (void) setAccessibilityFrame: (NSRect) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityFrameKey, [NSValue valueWithRect: value]);
}

- (NSAccessibilityRole) accessibilityRole {
    return _NSAccessibilityStoredObject(self, NSAccessibilityRoleAttribute, NSAccessibilityWindowRole);
}

- (NSArray *) accessibilityChildren {
    id value;
    if (_NSAccessibilityStoredValue(self, NSAccessibilityChildrenAttribute, &value))
        return value;

    NSView *contentView = [self contentView];
    return NSAccessibilityUnignoredChildrenForOnlyChild(contentView);
}

- (id) accessibilityParent {
    return _NSAccessibilityStoredObject(self, NSAccessibilityParentAttribute, NSApp);
}

- (id) accessibilityWindow {
    return _NSAccessibilityStoredObject(self, NSAccessibilityWindowAttribute, nil);
}

- (id) accessibilityTopLevelUIElement {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTopLevelUIElementAttribute, nil);
}

// The window's frame in screen coordinates.
- (NSRect) accessibilityFrame {
    return _NSAccessibilityStoredRect(self, _NSAccessibilityFrameKey, [self frame]);
}

- (NSString *) accessibilityLabel {
    return _NSAccessibilityStoredObject(self, NSAccessibilityDescriptionAttribute, [self title]);
}

- (NSString *) accessibilityTitle {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTitleAttribute, [self title]);
}

- (id) accessibilityValue {
    return _NSAccessibilityStoredObject(self, NSAccessibilityValueAttribute, nil);
}

- (BOOL) isAccessibilityEnabled {
    return _NSAccessibilityStoredBool(self, NSAccessibilityEnabledAttribute, NO);
}

@end

@implementation NSApplication (NSAccessibility)

ACCESSIBILITY_COMMON_METHODS

- (BOOL) isAccessibilityElement {
    return _NSAccessibilityStoredBool(self, _NSAccessibilityElementKey, YES);
}

- (void) setAccessibilityElement: (BOOL) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityElementKey, [NSNumber numberWithBool: value]);
}

- (void) setAccessibilityFrame: (NSRect) value {
    _NSAccessibilitySetStoredValue(self, _NSAccessibilityFrameKey, [NSValue valueWithRect: value]);
}

- (NSAccessibilityRole) accessibilityRole {
    return _NSAccessibilityStoredObject(self, NSAccessibilityRoleAttribute, NSAccessibilityApplicationRole);
}

- (NSArray *) accessibilityChildren {
    id value;
    if (_NSAccessibilityStoredValue(self, NSAccessibilityChildrenAttribute, &value))
        return value;

    NSMutableArray *visible = [NSMutableArray array];
    for (NSWindow *window in [self windows]) {
        if ([window isVisible])
            [visible addObject: window];
    }
    return NSAccessibilityUnignoredChildren(visible);
}

- (id) accessibilityParent {
    return _NSAccessibilityStoredObject(self, NSAccessibilityParentAttribute, nil);
}

- (id) accessibilityWindow {
    return _NSAccessibilityStoredObject(self, NSAccessibilityWindowAttribute, nil);
}

- (id) accessibilityTopLevelUIElement {
    return _NSAccessibilityStoredObject(self, NSAccessibilityTopLevelUIElementAttribute, nil);
}

- (NSRect) accessibilityFrame {
    return _NSAccessibilityStoredRect(self, _NSAccessibilityFrameKey, NSZeroRect);
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
