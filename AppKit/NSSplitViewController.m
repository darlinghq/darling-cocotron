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

// Key names follow GNUstep's NSSplitViewController (libs-gui, LGPL-2.1+).
- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) == nil)
        return nil;

    if ([coder allowsKeyedCoding]) {
        [self setSplitView: [coder decodeObjectForKey: @"NSSplitView"]];
        [self setSplitViewItems: [coder decodeObjectForKey: @"NSSplitViewItems"]];
    }
    return self;
}

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
    return _splitViewItems ? [[_splitViewItems copy] autorelease]
                           : [NSArray array];
}

- (void) setSplitViewItems: (NSArray *) items {
    items = [items copy];
    while ([_splitViewItems count] > 0)
        [self removeSplitViewItem: [_splitViewItems lastObject]];
    for (NSSplitViewItem *item in items)
        [self addSplitViewItem: item];
    [items release];
}

- (void) addSplitViewItem: (NSSplitViewItem *) item {
    [self insertSplitViewItem: item atIndex: [_splitViewItems count]];
}

- (void) _addViewOfItemAtIndex: (NSUInteger) index {
    NSSplitView *splitView = [self splitView];
    NSView *view = [[[_splitViewItems objectAtIndex: index] viewController] view];
    NSView *previous = index == 0 ? nil
            : [[[_splitViewItems objectAtIndex: index - 1] viewController] view];

    if (view == nil)
        return;
    [view removeFromSuperview];
    [splitView addSubview: view
               positioned: previous ? NSWindowAbove : NSWindowBelow
               relativeTo: previous];
    [splitView adjustSubviews];
}

- (void) insertSplitViewItem: (NSSplitViewItem *) item
                     atIndex: (NSInteger) index
{
    NSViewController *viewController = [item viewController];

    if (viewController == nil || index < 0 ||
        index > (NSInteger) [_splitViewItems count])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@] invalid item %@ or index %ld",
                            [self class], NSStringFromSelector(_cmd), item,
                            (long) index];

    [item retain];
    // Detach from a previous parent first, which may shift our own indices.
    if ([viewController parentViewController] != nil)
        [viewController removeFromParentViewController];
    if (index > (NSInteger) [_splitViewItems count])
        index = [_splitViewItems count];

    if (_splitViewItems == nil)
        _splitViewItems = [[NSMutableArray alloc] init];
    [_splitViewItems insertObject: item atIndex: index];
    [super insertChildViewController: viewController atIndex: index];
    if (_view != nil)
        [self _addViewOfItemAtIndex: index];
    [item release];
}

- (void) removeSplitViewItem: (NSSplitViewItem *) item {
    NSUInteger index = [_splitViewItems indexOfObjectIdenticalTo: item];

    if (index == NSNotFound)
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@] %@ is not an item of this controller",
                            [self class], NSStringFromSelector(_cmd), item];

    [item retain];
    if (_view != nil) {
        [[[item viewController] view] removeFromSuperview];
        [[self splitView] adjustSubviews];
    }
    [_splitViewItems removeObjectAtIndex: index];
    [super removeChildViewControllerAtIndex: index];
    [item release];
}

- (void) insertChildViewController: (NSViewController *) child
                           atIndex: (NSInteger) index
{
    [self insertSplitViewItem:
                  [NSSplitViewItem splitViewItemWithViewController: child]
                      atIndex: index];
}

- (void) removeChildViewControllerAtIndex: (NSInteger) index {
    [self removeSplitViewItem: [_splitViewItems objectAtIndex: index]];
}

- (NSSplitViewItem *) splitViewItemForViewController: (NSViewController *) viewController {
    for (NSSplitViewItem *item in _splitViewItems)
        if ([item viewController] == viewController)
            return item;
    return nil;
}

- (void) loadView {
    [self setView: [self splitView]];
    for (NSUInteger i = 0; i < [_splitViewItems count]; i++)
        [self _addViewOfItemAtIndex: i];
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
