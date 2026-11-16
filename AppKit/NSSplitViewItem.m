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

#import <AppKit/NSSplitViewItem.h>
#import <AppKit/NSViewController.h>

@implementation NSSplitViewItem

- (BOOL) isCollapsed {
    return NS_EXTRA(NSSplitViewItem, self)->_collapsed;
}

- (void) setCollapsed: (BOOL) collapsed {
    NS_EXTRA(NSSplitViewItem, self)->_collapsed = collapsed;
}

- (BOOL) canCollapse {
    return NS_EXTRA(NSSplitViewItem, self)->_canCollapse;
}

- (void) setCanCollapse: (BOOL) canCollapse {
    NS_EXTRA(NSSplitViewItem, self)->_canCollapse = canCollapse;
}

- (NSLayoutPriority) holdingPriority {
    return NS_EXTRA(NSSplitViewItem, self)->_holdingPriority;
}

- (void) setHoldingPriority: (NSLayoutPriority) holdingPriority {
    NS_EXTRA(NSSplitViewItem, self)->_holdingPriority = holdingPriority;
}

- (NSSplitViewItemBehavior) behavior {
    return NS_EXTRA(NSSplitViewItem, self)->_behavior;
}

+ (instancetype) splitViewItemWithViewController: (NSViewController *) viewController {
    NSSplitViewItem *item = [[[self alloc] init] autorelease];
    [item setViewController: viewController];
    return item;
}

+ (instancetype) sidebarWithViewController: (NSViewController *) viewController {
    NSSplitViewItem *item = [self splitViewItemWithViewController: viewController];
    NS_EXTRA(NSSplitViewItem, item)->_behavior = NSSplitViewItemBehaviorSidebar;
    NS_EXTRA(NSSplitViewItem, item)->_canCollapse = YES;
    NS_EXTRA(NSSplitViewItem, item)->_holdingPriority = NSLayoutPriorityDefaultLow + 10;
    return item;
}

+ (instancetype) contentListWithViewController: (NSViewController *) viewController {
    NSSplitViewItem *item = [self splitViewItemWithViewController: viewController];
    NS_EXTRA(NSSplitViewItem, item)->_behavior = NSSplitViewItemBehaviorContentList;
    return item;
}

- (instancetype) init {
    if ((self = [super init]))
        NS_EXTRA(NSSplitViewItem, self)->_holdingPriority = NSLayoutPriorityDefaultLow;
    return self;
}

// Key names follow GNUstep's NSSplitViewItem (libs-gui, LGPL-2.1+).
- (instancetype) initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@] requires a keyed coder", [self class],
                            NSStringFromSelector(_cmd)];
    if ((self = [self init]) == nil)
        return nil;

    [self setViewController: [coder decodeObjectForKey: @"NSSplitViewItemViewController"]];
    if ([coder containsValueForKey: @"NSHoldingPriority"])
        NS_EXTRA(NSSplitViewItem, self)->_holdingPriority = [coder decodeFloatForKey: @"NSHoldingPriority"];
    NS_EXTRA(NSSplitViewItem, self)->_collapsed = [coder decodeBoolForKey: @"NSCollapsed"];
    NS_EXTRA(NSSplitViewItem, self)->_behavior = [coder decodeIntegerForKey: @"NSBehavior"];
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSSplitViewItem, self)->_viewController release];
    NS_EXTRA_FREE(NSSplitViewItem, self);
    [super dealloc];
}

- (NSViewController *) viewController {
    return NS_EXTRA(NSSplitViewItem, self)->_viewController;
}

- (void) setViewController: (NSViewController *) viewController {
    viewController = [viewController retain];
    [NS_EXTRA(NSSplitViewItem, self)->_viewController release];
    NS_EXTRA(NSSplitViewItem, self)->_viewController = viewController;
}

- (instancetype) animator {
    return self;
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
