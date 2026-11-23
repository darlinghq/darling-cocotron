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
#import <Foundation/Foundation.h>
#import <AppKit/NSLayoutConstraint.h>

@class NSViewController;

typedef NS_ENUM(NSInteger, NSSplitViewItemBehavior) {
    NSSplitViewItemBehaviorDefault,
    NSSplitViewItemBehaviorSidebar,
    NSSplitViewItemBehaviorContentList,
    // GUESS: the value 3 follows the order in which the documentation lists the
    // cases (the inspector comes after the content list; macOS 11.0).
    NSSplitViewItemBehaviorInspector,
};

typedef NS_ENUM(NSInteger, NSSplitViewItemCollapseBehavior) {
    NSSplitViewItemCollapseBehaviorDefault,
    NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings,
    NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView,
    NSSplitViewItemCollapseBehaviorUseConstraints,
};

// Resets a sizing property to its default. The documentation does not state the
// value (GUESS: -1).
APPKIT_EXPORT const CGFloat NSSplitViewItemUnspecifiedDimension;

@interface NSSplitViewItem : NSObject <NSCoding> {
    NS_LEGACY_IVAR_PAD(_NSSplitViewItemReserved, 4)
    NS_EXTRA_IVARS_BEGIN(NSSplitViewItem)
    NSViewController *_viewController;
    NSSplitViewItemBehavior _behavior;
    BOOL _collapsed;
    BOOL _canCollapse;
    NSLayoutPriority _holdingPriority;
    CGFloat _minimumThickness;
    CGFloat _maximumThickness;
    NSSplitViewItemCollapseBehavior _collapseBehavior;
    BOOL _springLoaded;
    BOOL _allowsFullHeightLayout;
    NS_EXTRA_IVARS_END(NSSplitViewItem)
}

+ (instancetype) splitViewItemWithViewController: (NSViewController *) viewController;
// A collapsible item whose holding priority is NSLayoutPriorityDefaultLow + 10.
+ (instancetype) sidebarWithViewController: (NSViewController *) viewController;
+ (instancetype) contentListWithViewController: (NSViewController *) viewController;
// A collapsible item whose thickness is fixed at 270 (the documented macOS 14
// inspector size).
+ (instancetype) inspectorWithViewController: (NSViewController *) viewController;

@property(readonly) NSSplitViewItemBehavior behavior;

@property(retain) NSViewController *viewController;
// Stored only: the split view doesn't hide or resize a collapsed item's view.
@property(getter=isCollapsed) BOOL collapsed;
@property BOOL canCollapse;
@property NSLayoutPriority holdingPriority;

// Stored only: the split view controller does not apply the thickness limits or the
// collapse behavior, and the spring-loaded and full-height flags have no effect.
// Both limits default to NSSplitViewItemUnspecifiedDimension (270 for an inspector);
// assigning NSSplitViewItemUnspecifiedDimension restores that default.
@property CGFloat minimumThickness;
@property CGFloat maximumThickness;
@property NSSplitViewItemCollapseBehavior collapseBehavior;
@property(getter=isSpringLoaded) BOOL springLoaded;
// Default YES.
@property BOOL allowsFullHeightLayout;

// Changes apply immediately; there are no animations.
- (instancetype) animator;

@end
