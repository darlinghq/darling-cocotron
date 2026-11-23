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

// Shared by the accessibility implementations of AppKit's classes
// (NSAccessibilityProtocols.m, NSAccessibilityElement.m); not installed.

#import <AppKit/NSAccessibility.h>
#import <AppKit/NSAccessibilityConstants.h>
#import <Foundation/NSValue.h>

// Values set through the setters, by attribute name. An explicit nil is kept as NSNull,
// so that it still replaces the default.
__attribute__((visibility("hidden"))) BOOL _NSAccessibilityStoredValue(id element, NSString *key, id *value);
__attribute__((visibility("hidden"))) void _NSAccessibilitySetStoredValue(id element, NSString *key, id value);
__attribute__((visibility("hidden"))) void _NSAccessibilityRemoveStoredValue(id element, NSString *key);
__attribute__((visibility("hidden"))) id _NSAccessibilityStoredObject(id element, NSString *key, id fallback);
__attribute__((visibility("hidden"))) BOOL _NSAccessibilityStoredBool(id element, NSString *key, BOOL fallback);
__attribute__((visibility("hidden"))) NSRect _NSAccessibilityStoredRect(id element, NSString *key, NSRect fallback);
// What -accessibilityDocument answers while nothing has been set: nil, except for a window.
__attribute__((visibility("hidden"))) NSString *_NSAccessibilityDefaultDocument(id element);

// The legacy attribute methods read and write through the protocol's methods, so that a
// subclass overriding either kind is seen by both.
__attribute__((visibility("hidden"))) NSArray *_NSAccessibilityLegacyAttributeNames(void);
__attribute__((visibility("hidden"))) id _NSAccessibilityLegacyAttributeValue(id element, NSString *attribute);
__attribute__((visibility("hidden"))) void _NSAccessibilityLegacySetAttributeValue(id element, NSString *attribute, id value);

// Keys for properties without an attribute constant of their own.
#define _NSAccessibilityElementKey @"_NSAccessibilityElement"
#define _NSAccessibilityFrameKey @"_NSAccessibilityFrame"
#define _NSAccessibilityCustomActionsKey @"_NSAccessibilityCustomActions"

// The setters, and the properties that only hold what was set, are the same for every class.
#define ACCESSIBILITY_STORED_OBJECT(type, getter, setter, key)                                      \
    - (type) getter {                                                                               \
        return _NSAccessibilityStoredObject(self, key, nil);                                        \
    }                                                                                               \
    - (void) setter (type) value {                                                                  \
        _NSAccessibilitySetStoredValue(self, key, value);                                           \
    }

#define ACCESSIBILITY_STORED_BOOL(getter, setter, key)                                              \
    - (BOOL) getter {                                                                               \
        return _NSAccessibilityStoredBool(self, key, NO);                                           \
    }                                                                                               \
    - (void) setter (BOOL) value {                                                                  \
        _NSAccessibilitySetStoredValue(self, key, [NSNumber numberWithBool: value]);                \
    }

#define ACCESSIBILITY_SETTER(type, setter, key)                                                     \
    - (void) setter (type) value {                                                                  \
        _NSAccessibilitySetStoredValue(self, key, value);                                           \
    }

#define ACCESSIBILITY_COMMON_METHODS                                                                \
    ACCESSIBILITY_STORED_OBJECT(NSAccessibilitySubrole, accessibilitySubrole,                       \
                                setAccessibilitySubrole:, NSAccessibilitySubroleAttribute)          \
    ACCESSIBILITY_STORED_OBJECT(NSString *, accessibilityIdentifier, setAccessibilityIdentifier:,   \
                                NSAccessibilityIdentifierAttribute)                                 \
    ACCESSIBILITY_STORED_OBJECT(NSString *, accessibilityHelp, setAccessibilityHelp:,               \
                                NSAccessibilityHelpAttribute)                                       \
    ACCESSIBILITY_STORED_OBJECT(NSString *, accessibilityValueDescription,                          \
                                setAccessibilityValueDescription:,                                  \
                                NSAccessibilityValueDescriptionAttribute)                           \
    ACCESSIBILITY_STORED_OBJECT(NSString *, accessibilityPlaceholderValue,                          \
                                setAccessibilityPlaceholderValue:,                                  \
                                NSAccessibilityPlaceholderValueAttribute)                           \
    - (NSString *) accessibilityDocument {                                                          \
        id value;                                                                                   \
        if (_NSAccessibilityStoredValue(self, NSAccessibilityDocumentAttribute, &value))            \
            return value;                                                                           \
        return _NSAccessibilityDefaultDocument(self);                                               \
    }                                                                                               \
    - (void) setAccessibilityDocument: (NSString *) value {                                         \
        _NSAccessibilitySetStoredValue(self, NSAccessibilityDocumentAttribute,                      \
                                       [[value copy] autorelease]);                                 \
    }                                                                                               \
    ACCESSIBILITY_STORED_OBJECT(NSArray *, accessibilitySelectedChildren,                           \
                                setAccessibilitySelectedChildren:,                                  \
                                NSAccessibilitySelectedChildrenAttribute)                           \
    ACCESSIBILITY_STORED_OBJECT(NSArray *, accessibilityVisibleChildren,                            \
                                setAccessibilityVisibleChildren:,                                   \
                                NSAccessibilityVisibleChildrenAttribute)                            \
    ACCESSIBILITY_STORED_OBJECT(NSArray *, accessibilityContents, setAccessibilityContents:,        \
                                NSAccessibilityContentsAttribute)                                   \
    ACCESSIBILITY_STORED_OBJECT(NSArray *, accessibilityLinkedUIElements,                           \
                                setAccessibilityLinkedUIElements:,                                  \
                                NSAccessibilityLinkedUIElementsAttribute)                           \
    ACCESSIBILITY_STORED_OBJECT(NSArray *, accessibilityServesAsTitleForUIElements,                 \
                                setAccessibilityServesAsTitleForUIElements:,                        \
                                NSAccessibilityServesAsTitleForUIElementsAttribute)                 \
    ACCESSIBILITY_STORED_OBJECT(id, accessibilityTitleUIElement, setAccessibilityTitleUIElement:,   \
                                NSAccessibilityTitleUIElementAttribute)                             \
    ACCESSIBILITY_STORED_OBJECT(NSArray *, accessibilityCustomActions,                              \
                                setAccessibilityCustomActions:, _NSAccessibilityCustomActionsKey)   \
    ACCESSIBILITY_STORED_BOOL(isAccessibilityFocused, setAccessibilityFocused:,                     \
                              NSAccessibilityFocusedAttribute)                                      \
    ACCESSIBILITY_STORED_BOOL(isAccessibilitySelected, setAccessibilitySelected:,                   \
                              NSAccessibilitySelectedAttribute)                                     \
    ACCESSIBILITY_STORED_BOOL(isAccessibilityRequired, setAccessibilityRequired:,                   \
                              NSAccessibilityRequiredAttribute)                                     \
    ACCESSIBILITY_STORED_BOOL(isAccessibilityExpanded, setAccessibilityExpanded:,                   \
                              NSAccessibilityExpandedAttribute)                                     \
    ACCESSIBILITY_SETTER(NSAccessibilityRole, setAccessibilityRole:, NSAccessibilityRoleAttribute)  \
    ACCESSIBILITY_SETTER(NSString *, setAccessibilityLabel:, NSAccessibilityDescriptionAttribute)   \
    ACCESSIBILITY_SETTER(NSString *, setAccessibilityTitle:, NSAccessibilityTitleAttribute)         \
    ACCESSIBILITY_SETTER(id, setAccessibilityValue:, NSAccessibilityValueAttribute)                 \
    ACCESSIBILITY_SETTER(id, setAccessibilityMinValue:, NSAccessibilityMinValueAttribute)           \
    ACCESSIBILITY_SETTER(id, setAccessibilityMaxValue:, NSAccessibilityMaxValueAttribute)           \
    ACCESSIBILITY_SETTER(NSArray *, setAccessibilityChildren:, NSAccessibilityChildrenAttribute)    \
    ACCESSIBILITY_SETTER(id, setAccessibilityParent:, NSAccessibilityParentAttribute)               \
    ACCESSIBILITY_SETTER(id, setAccessibilityWindow:, NSAccessibilityWindowAttribute)               \
    ACCESSIBILITY_SETTER(id, setAccessibilityTopLevelUIElement:,                                    \
                         NSAccessibilityTopLevelUIElementAttribute)                                 \
    ACCESSIBILITY_SETTER(NSString *, setAccessibilityRoleDescription:,                              \
                         NSAccessibilityRoleDescriptionAttribute)                                   \
    - (NSString *) accessibilityRoleDescription {                                                   \
        id value;                                                                                   \
        if (_NSAccessibilityStoredValue(self, NSAccessibilityRoleDescriptionAttribute, &value))     \
            return value;                                                                           \
        return NSAccessibilityRoleDescription([self accessibilityRole],                             \
                                              [self accessibilitySubrole]);                         \
    }                                                                                               \
    - (id) accessibilityMinValue {                                                                  \
        return _NSAccessibilityStoredObject(self, NSAccessibilityMinValueAttribute, nil);           \
    }                                                                                               \
    - (id) accessibilityMaxValue {                                                                  \
        return _NSAccessibilityStoredObject(self, NSAccessibilityMaxValueAttribute, nil);           \
    }                                                                                               \
    - (void) setAccessibilityEnabled: (BOOL) value {                                                \
        _NSAccessibilitySetStoredValue(self, NSAccessibilityEnabledAttribute, [NSNumber numberWithBool: value]); \
    }                                                                                               \
    - (BOOL) accessibilityIsIgnored {                                                               \
        return ![self isAccessibilityElement];                                                      \
    }                                                                                               \
    - (NSArray *) accessibilityAttributeNames {                                                     \
        return _NSAccessibilityLegacyAttributeNames();                                              \
    }                                                                                               \
    - (id) accessibilityAttributeValue: (NSString *) attribute {                                    \
        return _NSAccessibilityLegacyAttributeValue(self, attribute);                               \
    }                                                                                               \
    - (BOOL) accessibilityIsAttributeSettable: (NSString *) attribute {                             \
        return NO;                                                                                  \
    }                                                                                               \
    - (void) accessibilitySetValue: (id) value forAttribute: (NSString *) attribute {               \
        _NSAccessibilityLegacySetAttributeValue(self, attribute, value);                            \
    }                                                                                               \
    - (NSArray *) accessibilityParameterizedAttributeNames {                                        \
        return [NSArray array];                                                                     \
    }                                                                                               \
    - (NSArray *) accessibilityActionNames {                                                        \
        return [NSArray array];                                                                     \
    }                                                                                               \
    - (NSString *) accessibilityActionDescription: (NSString *) action {                            \
        return NSAccessibilityActionDescription(action);                                            \
    }                                                                                               \
    - (void) accessibilityPerformAction: (NSString *) action {                                      \
    }
