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

NSBindingInfoKey NSObservedObjectKey = @"NSObservedObject";
NSBindingInfoKey NSObservedKeyPathKey = @"NSObservedKeyPath";
NSBindingInfoKey NSOptionsKey = @"NSOptions";

NSBindingName NSAnimateBinding = @"animate";
NSBindingName NSArgumentBinding = @"argument";
NSBindingName NSContentArrayBinding = @"contentArray";
NSBindingName NSContentBinding = @"content";
NSBindingName NSContentObjectBinding = @"contentObject";
NSBindingName NSContentObjectsBinding = @"contentObjects";
NSBindingName NSContentSetBinding = @"contentSet";
NSBindingName NSContentValuesBinding = @"contentValues";
NSBindingName NSDoubleClickTargetBinding = @"doubleClickTarget";
NSBindingName NSEnabledBinding = @"enabled";
NSBindingName NSEditableBinding = @"editable";
NSBindingName NSFontBoldBinding = @"fontBold";
NSBindingName NSFontItalicBinding = @"fontItalic";
NSBindingName NSHiddenBinding = @"hidden";
NSBindingName NSImageBinding = @"image";
NSBindingName NSSelectedIndexBinding = @"selectedIndex";
NSBindingName NSSelectedObjectBinding = @"selectedObject";
NSBindingName NSSelectedObjectsBinding = @"selectedObjects";
NSBindingName NSSelectedTagBinding = @"selectedTag";
NSBindingName NSSelectedValueBinding = @"selectedValue";
NSBindingName NSSelectionIndexesBinding = @"selectionIndexes";
NSBindingName NSTargetBinding = @"target";
NSBindingName NSTitleBinding = @"title";
NSBindingName NSToolTipBinding = @"toolTip";
NSBindingName NSValueBinding = @"value";
NSBindingName NSVisibleBinding = @"visible";

NSBindingOption NSAllowsEditingMultipleValuesSelectionBindingOption = @"NSAllowsEditingMultipleValuesSelection";
NSBindingOption NSAllowsNullArgumentBindingOption = @"NSAllowsNullArgument";
NSBindingOption NSConditionallySetsEnabledBindingOption = @"NSConditionallySetsEnabled";
NSBindingOption NSConditionallySetsEditableBindingOption = @"NSConditionallySetsEditable";
NSBindingOption NSContinuouslyUpdatesValueBindingOption = @"NSContinuouslyUpdatesValue";
NSBindingOption NSCreatesSortDescriptorBindingOption = @"NSCreatesSortDescriptor";
NSBindingOption NSDisplayPatternBindingOption = @"NSDisplayPattern";
NSBindingOption NSInsertsNullPlaceholderBindingOption = @"NSInsertsNullPlaceholder";
NSBindingOption NSInvokesSeparatelyWithArrayObjectsBindingOption = @"NSInvokesSeparatelyWithArrayObjects";
NSBindingOption NSMultipleValuesPlaceholderBindingOption = @"NSMultipleValuesPlaceholder";
NSBindingOption NSNoSelectionPlaceholderBindingOption = @"NSNoSelectionPlaceholder";
NSBindingOption NSNotApplicablePlaceholderBindingOption = @"NSNotApplicablePlaceholder";
NSBindingOption NSNullPlaceholderBindingOption = @"NSNullPlaceholder";
NSBindingOption NSPredicateFormatBindingOption = @"NSPredicateFormat";
NSBindingOption NSRaisesForNotApplicableKeysBindingOption = @"NSRaisesForNotApplicableKeys";
NSBindingOption NSSelectorNameBindingOption = @"NSSelectorName";
NSBindingOption NSValidatesImmediatelyBindingOption = @"NSValidatesImmediately";
NSBindingOption NSValueTransformerBindingOption = @"NSValueTransformer";
NSBindingOption NSValueTransformerNameBindingOption = @"NSValueTransformerName";

// TODO: actually implement this stuff
@implementation NSObject (NSKeyValueBindingCreation)

- (NSArray<NSString *> *) exposedBindings
{
        return @[];
}

@end
