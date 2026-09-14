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
#import <AppKit/NSViewController.h>

@class NSSplitView, NSSplitViewItem;

@interface NSSplitViewController : NSViewController {
    NSSplitView *_splitView;
    NSArray *_splitViewItems;
}

// The controller's view; a new NSSplitView unless one was set before the view
// loaded.
@property(retain) NSSplitView *splitView;
// Each item's view controller view becomes a subview of splitView once the
// controller's view is loaded.
@property(copy) NSArray *splitViewItems;

- (NSSplitViewItem *) splitViewItemForViewController: (NSViewController *) viewController;

@end
