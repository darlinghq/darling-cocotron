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

#import <AppKit/NSKeyValueBinding.h>

NSString *const NSObservedObjectKey = @"NSObservedObject";
NSString *const NSObservedKeyPathKey = @"NSObservedKeyPath";
NSString *const NSOptionsKey = @"NSOptions";

NSString *const NSAnimateBinding = @"animate";
NSString *const NSContentArrayBinding = @"contentArray";
NSString *const NSContentBinding = @"content";
NSString *const NSContentObjectBinding = @"contentObject";
NSString *const NSContentObjectsBinding = @"contentObjects";
NSString *const NSContentSetBinding = @"contentSet";
NSString *const NSContentValuesBinding = @"contentValues";
NSString *const NSDoubleClickTargetBinding = @"doubleClickTarget";
NSString *const NSEnabledBinding = @"enabled";
NSString *const NSHiddenBinding = @"hidden";
NSString *const NSImageBinding = @"image";
NSString *const NSInsertsNullPlaceholderBindingOption =
    @"NSInsertsNullPlaceholder";
NSString *const NSSelectedIndexBinding = @"selectedIndex";
NSString *const NSSelectedObjectBinding = @"selectedObject";
NSString *const NSSelectedObjectsBinding = @"selectedObjects";
NSString *const NSSelectedTagBinding = @"selectedTag";
NSString *const NSSelectionIndexesBinding = @"selectionIndexes";
NSString *const NSTitleBinding = @"title";
NSString *const NSValidatesImmediatelyBindingOption = @"NSValidatesImmediately";
NSString *const NSNotApplicablePlaceholderBindingOption =
    @"NSNotApplicablePlaceholder";
NSString *const NSValueBinding = @"value";
NSString *const NSVisibleBinding = @"visible";
NSString *const NSToolTipBinding = @"toolTip";
NSString *const NSEditableBinding = @"editable";

NSString *const NSNullPlaceholderBindingOption = @"NSNullPlaceholder";
NSString *const NSNoSelectionPlaceholderBindingOption =
    @"NSNoSelectionPlaceholder";
NSString *const NSMultipleValuesPlaceholderBindingOption =
    @"NSMultipleValuesPlaceholder";
NSString *const NSCreatesSortDescriptorBindingOption =
    @"NSCreatesSortDescriptors";
NSString *const NSRaisesForNotApplicableKeysBindingOption =
    @"NSRaisesForNotApplicableKeys";
NSString *const NSAllowsEditingMultipleValuesSelectionBindingOption =
    @"NSAllowsEditingMultipleValuesSelection";
NSString *const NSValueTransformerNameBindingOption = @"NSValueTransformerName";
NSString *const NSValueTransformerBindingOption = @"NSValueTransformerBinding";
NSString *const NSConditionallySetsEnabledBindingOption =
    @"NSConditionallySetsEnabled";
NSString *const NSConditionallySetsEditableBindingOption =
    @"NSConditionallySetsEditable";
NSString *const NSContinuouslyUpdatesValueBindingOption =
    @"NSContinuouslyUpdatesValue";
NSString *const NSDisplayPatternBindingOption = @"NSDisplayPattern";
