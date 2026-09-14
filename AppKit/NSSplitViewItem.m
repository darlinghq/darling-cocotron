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

@synthesize collapsed = _collapsed;
@synthesize canCollapse = _canCollapse;
@synthesize holdingPriority = _holdingPriority;

+ (instancetype) splitViewItemWithViewController: (NSViewController *) viewController {
    NSSplitViewItem *item = [[[self alloc] init] autorelease];
    [item setViewController: viewController];
    return item;
}

- (instancetype) init {
    if ((self = [super init]))
        _holdingPriority = NSLayoutPriorityDefaultLow;
    return self;
}

- (void) dealloc {
    [_viewController release];
    [super dealloc];
}

- (NSViewController *) viewController {
    return _viewController;
}

- (void) setViewController: (NSViewController *) viewController {
    viewController = [viewController retain];
    [_viewController release];
    _viewController = viewController;
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
