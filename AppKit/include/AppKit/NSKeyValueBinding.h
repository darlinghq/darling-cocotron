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
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>

typedef NSString* NSBindingName NS_TYPED_EXTENSIBLE_ENUM;
typedef NSString* NSBindingOption NS_TYPED_ENUM;

typedef NSString* NSBindingInfoKey NS_TYPED_ENUM;
APPKIT_EXPORT NSBindingInfoKey NSObservedObjectKey;
APPKIT_EXPORT NSBindingInfoKey NSObservedKeyPathKey;
APPKIT_EXPORT NSBindingInfoKey NSOptionsKey;

APPKIT_EXPORT NSBindingName NSAnimateBinding;
APPKIT_EXPORT NSBindingName NSArgumentBinding;
APPKIT_EXPORT NSBindingName NSContentArrayBinding;
APPKIT_EXPORT NSBindingName NSContentBinding;
APPKIT_EXPORT NSBindingName NSContentObjectBinding;
APPKIT_EXPORT NSBindingName NSContentObjectsBinding;
APPKIT_EXPORT NSBindingName NSContentSetBinding;
APPKIT_EXPORT NSBindingName NSContentValuesBinding;
APPKIT_EXPORT NSBindingName NSDoubleClickTargetBinding;
APPKIT_EXPORT NSBindingName NSEditableBinding;
APPKIT_EXPORT NSBindingName NSEnabledBinding;
APPKIT_EXPORT NSBindingName NSFontBoldBinding;
APPKIT_EXPORT NSBindingName NSFontItalicBinding;
APPKIT_EXPORT NSBindingName NSHiddenBinding;
APPKIT_EXPORT NSBindingName NSImageBinding;
APPKIT_EXPORT NSBindingName NSSelectedIndexBinding;
APPKIT_EXPORT NSBindingName NSSelectedObjectBinding;
APPKIT_EXPORT NSBindingName NSSelectedObjectsBinding;
APPKIT_EXPORT NSBindingName NSSelectedTagBinding;
APPKIT_EXPORT NSBindingName NSSelectedValueBinding;
APPKIT_EXPORT NSBindingName NSSelectionIndexesBinding;
APPKIT_EXPORT NSBindingName NSTargetBinding;
APPKIT_EXPORT NSBindingName NSTitleBinding;
APPKIT_EXPORT NSBindingName NSToolTipBinding;
APPKIT_EXPORT NSBindingName NSValueBinding;
APPKIT_EXPORT NSBindingName NSVisibleBinding;

APPKIT_EXPORT NSBindingOption NSAllowsEditingMultipleValuesSelectionBindingOption;
APPKIT_EXPORT NSBindingOption NSAllowsNullArgumentBindingOption;
APPKIT_EXPORT NSBindingOption NSConditionallySetsEnabledBindingOption;
APPKIT_EXPORT NSBindingOption NSConditionallySetsEditableBindingOption;
APPKIT_EXPORT NSBindingOption NSContinuouslyUpdatesValueBindingOption;
APPKIT_EXPORT NSBindingOption NSCreatesSortDescriptorBindingOption;
APPKIT_EXPORT NSBindingOption NSDisplayPatternBindingOption;
APPKIT_EXPORT NSBindingOption NSInsertsNullPlaceholderBindingOption;
APPKIT_EXPORT NSBindingOption NSInvokesSeparatelyWithArrayObjectsBindingOption;
APPKIT_EXPORT NSBindingOption NSMultipleValuesPlaceholderBindingOption;
APPKIT_EXPORT NSBindingOption NSNoSelectionPlaceholderBindingOption;
APPKIT_EXPORT NSBindingOption NSNotApplicablePlaceholderBindingOption;
APPKIT_EXPORT NSBindingOption NSNullPlaceholderBindingOption;
APPKIT_EXPORT NSBindingOption NSPredicateFormatBindingOption;
APPKIT_EXPORT NSBindingOption NSRaisesForNotApplicableKeysBindingOption;
APPKIT_EXPORT NSBindingOption NSSelectorNameBindingOption;
APPKIT_EXPORT NSBindingOption NSValidatesImmediatelyBindingOption;
APPKIT_EXPORT NSBindingOption NSValueTransformerBindingOption;
APPKIT_EXPORT NSBindingOption NSValueTransformerNameBindingOption;

@interface NSObject (NSKeyValueBindingCreation)

@property(readonly, copy) NSArray<NSString *> *exposedBindings;

@end
