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

#import <AppKit/NSSplitView.h>
#import <AppKit/NSSplitViewController.h>
#import <AppKit/NSSplitViewItem.h>

@implementation NSSplitViewController

- (void) dealloc {
    [_splitView release];
    [_splitViewItems release];
    [super dealloc];
}

- (NSSplitView *) splitView {
    if (_splitView == nil)
        _splitView = [[NSSplitView alloc] initWithFrame: NSZeroRect];
    return _splitView;
}

- (void) setSplitView: (NSSplitView *) splitView {
    splitView = [splitView retain];
    [_splitView release];
    _splitView = splitView;
}

- (NSArray *) splitViewItems {
    return _splitViewItems ? _splitViewItems : [NSArray array];
}

- (void) _addItemViewsToSplitView {
    NSSplitView *splitView = [self splitView];
    for (NSSplitViewItem *item in _splitViewItems) {
        NSView *view = [[item viewController] view];
        if (view != nil && [view superview] != splitView)
            [splitView addSubview: view];
    }
    [splitView adjustSubviews];
}

- (void) setSplitViewItems: (NSArray *) items {
    if (_view != nil) {
        for (NSSplitViewItem *item in _splitViewItems)
            if (![items containsObject: item])
                [[[item viewController] view] removeFromSuperview];
    }
    items = [items copy];
    [_splitViewItems release];
    _splitViewItems = items;
    if (_view != nil)
        [self _addItemViewsToSplitView];
}

- (NSSplitViewItem *) splitViewItemForViewController: (NSViewController *) viewController {
    for (NSSplitViewItem *item in _splitViewItems)
        if ([item viewController] == viewController)
            return item;
    return nil;
}

- (void) loadView {
    [self setView: [self splitView]];
    [self _addItemViewsToSplitView];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
