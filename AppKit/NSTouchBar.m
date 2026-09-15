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

#import <AppKit/NSTouchBar.h>
#import <AppKit/NSView.h>

// i'm assuming this inherits from NSView (TODO: check this assumption)
@interface NSTouchBarView : NSView
@end

// again, i'm assuming this inherits from NSTouchBarView and this should be checked later
@interface NSTouchBarItemContainerView : NSTouchBarView
@end

@implementation NSTouchBar {
    NSMutableDictionary *_items;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

- (void) dealloc {
    [_defaultItemIdentifiers release];
    [_items release];
    [super dealloc];
}

// Without Touch Bar hardware nothing customizes the bar, so it shows the defaults.
- (NSArray *) itemIdentifiers {
    return _defaultItemIdentifiers ? _defaultItemIdentifiers : [NSArray array];
}

- (NSTouchBarItem *) itemForIdentifier: (NSTouchBarItemIdentifier) identifier {
    NSTouchBarItem *item = [_items objectForKey: identifier];
    if (item == nil &&
        [_delegate respondsToSelector: @selector(touchBar:makeItemForIdentifier:)])
    {
        item = [_delegate touchBar: self makeItemForIdentifier: identifier];
        if (item != nil) {
            if (_items == nil)
                _items = [[NSMutableDictionary alloc] init];
            [_items setObject: item forKey: identifier];
        }
    }
    return item;
}

@end

@implementation NSTouchBarView

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSTouchBarItemContainerView

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
