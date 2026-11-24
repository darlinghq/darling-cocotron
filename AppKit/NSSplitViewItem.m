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

const CGFloat NSSplitViewItemUnspecifiedDimension = -1.0;

// The thickness limits an item starts with. The inspector's 270 is documented for macOS 14 and later;
// the others are the system standards observed on macOS 26.7.3 and Mac OS X 10.14.4 (identical where
// both have the item; black-box, probe splititem.m): a sidebar has a minimum of 140, a content list of 200,
// neither has a maximum.
static const CGFloat inspectorThickness = 270;

static CGFloat defaultMinimumThickness(NSSplitViewItemBehavior behavior) {
    switch (behavior) {
    case NSSplitViewItemBehaviorInspector:
        return inspectorThickness;
    case NSSplitViewItemBehaviorSidebar:
        return 140;
    case NSSplitViewItemBehaviorContentList:
        return 200;
    default:
        return NSSplitViewItemUnspecifiedDimension;
    }
}

static CGFloat defaultMaximumThickness(NSSplitViewItemBehavior behavior) {
    return behavior == NSSplitViewItemBehaviorInspector ? inspectorThickness
                                                        : NSSplitViewItemUnspecifiedDimension;
}

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

- (CGFloat) minimumThickness {
    return NS_EXTRA(NSSplitViewItem, self)->_minimumThickness;
}

- (void) setMinimumThickness: (CGFloat) minimumThickness {
    NS_EXTRA(NSSplitViewItem, self)->_minimumThickness = minimumThickness;
}

- (CGFloat) maximumThickness {
    return NS_EXTRA(NSSplitViewItem, self)->_maximumThickness;
}

- (void) setMaximumThickness: (CGFloat) maximumThickness {
    NS_EXTRA(NSSplitViewItem, self)->_maximumThickness = maximumThickness;
}

- (NSSplitViewItemCollapseBehavior) collapseBehavior {
    return NS_EXTRA(NSSplitViewItem, self)->_collapseBehavior;
}

- (void) setCollapseBehavior: (NSSplitViewItemCollapseBehavior) collapseBehavior {
    NS_EXTRA(NSSplitViewItem, self)->_collapseBehavior = collapseBehavior;
}

- (BOOL) isSpringLoaded {
    return NS_EXTRA(NSSplitViewItem, self)->_springLoaded;
}

- (void) setSpringLoaded: (BOOL) springLoaded {
    NS_EXTRA(NSSplitViewItem, self)->_springLoaded = springLoaded;
}

- (BOOL) allowsFullHeightLayout {
    return NS_EXTRA(NSSplitViewItem, self)->_allowsFullHeightLayout;
}

- (void) setAllowsFullHeightLayout: (BOOL) allowsFullHeightLayout {
    NS_EXTRA(NSSplitViewItem, self)->_allowsFullHeightLayout = allowsFullHeightLayout;
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
    NS_EXTRA(NSSplitViewItem, item)->_minimumThickness = defaultMinimumThickness(NSSplitViewItemBehaviorSidebar);
    NS_EXTRA(NSSplitViewItem, item)->_springLoaded = YES;
    return item;
}

+ (instancetype) contentListWithViewController: (NSViewController *) viewController {
    NSSplitViewItem *item = [self splitViewItemWithViewController: viewController];
    NS_EXTRA(NSSplitViewItem, item)->_behavior = NSSplitViewItemBehaviorContentList;
    NS_EXTRA(NSSplitViewItem, item)->_holdingPriority = NSLayoutPriorityDefaultLow + 5;
    NS_EXTRA(NSSplitViewItem, item)->_minimumThickness = defaultMinimumThickness(NSSplitViewItemBehaviorContentList);
    return item;
}

+ (instancetype) inspectorWithViewController: (NSViewController *) viewController {
    NSSplitViewItem *item = [self splitViewItemWithViewController: viewController];
    NS_EXTRA(NSSplitViewItem, item)->_behavior = NSSplitViewItemBehaviorInspector;
    NS_EXTRA(NSSplitViewItem, item)->_canCollapse = YES;
    NS_EXTRA(NSSplitViewItem, item)->_holdingPriority = NSLayoutPriorityDefaultLow + 11;
    NS_EXTRA(NSSplitViewItem, item)->_minimumThickness = inspectorThickness;
    NS_EXTRA(NSSplitViewItem, item)->_maximumThickness = inspectorThickness;
    return item;
}

- (instancetype) init {
    if ((self = [super init])) {
        NS_EXTRA(NSSplitViewItem, self)->_holdingPriority = NSLayoutPriorityDefaultLow;
        NS_EXTRA(NSSplitViewItem, self)->_minimumThickness = NSSplitViewItemUnspecifiedDimension;
        NS_EXTRA(NSSplitViewItem, self)->_maximumThickness = NSSplitViewItemUnspecifiedDimension;
        NS_EXTRA(NSSplitViewItem, self)->_allowsFullHeightLayout = YES;
    }
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
    // The limits of a decoded item start from those of its behavior; they are not decoded (their keys are
    // not documented).
    NSSplitViewItemBehavior behavior = NS_EXTRA(NSSplitViewItem, self)->_behavior;
    NS_EXTRA(NSSplitViewItem, self)->_minimumThickness = defaultMinimumThickness(behavior);
    NS_EXTRA(NSSplitViewItem, self)->_maximumThickness = defaultMaximumThickness(behavior);
    NS_EXTRA(NSSplitViewItem, self)->_springLoaded = behavior == NSSplitViewItemBehaviorSidebar;
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
