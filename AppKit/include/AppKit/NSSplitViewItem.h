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
#import <Foundation/Foundation.h>
#import <AppKit/NSLayoutConstraint.h>

@class NSViewController;

typedef NS_ENUM(NSInteger, NSSplitViewItemBehavior) {
    NSSplitViewItemBehaviorDefault,
    NSSplitViewItemBehaviorSidebar,
    NSSplitViewItemBehaviorContentList,
};

@interface NSSplitViewItem : NSObject <NSCoding> {
    NSViewController *_viewController;
    NSSplitViewItemBehavior _behavior;
    BOOL _collapsed;
    BOOL _canCollapse;
    NSLayoutPriority _holdingPriority;
}

+ (instancetype) splitViewItemWithViewController: (NSViewController *) viewController;
// A collapsible item whose holding priority is NSLayoutPriorityDefaultLow + 10.
+ (instancetype) sidebarWithViewController: (NSViewController *) viewController;
+ (instancetype) contentListWithViewController: (NSViewController *) viewController;

@property(readonly) NSSplitViewItemBehavior behavior;

@property(retain) NSViewController *viewController;
// Stored only: the split view doesn't hide or resize a collapsed item's view.
@property(getter=isCollapsed) BOOL collapsed;
@property BOOL canCollapse;
@property NSLayoutPriority holdingPriority;

// Changes apply immediately; there are no animations.
- (instancetype) animator;

@end
