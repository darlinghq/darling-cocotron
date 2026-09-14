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

#import <AppKit/NSStackView.h>

@implementation NSStackView

- (void) dealloc {
    [_visibilityPriorities release];
    [super dealloc];
}

- (void) setVisibilityPriority: (NSStackViewVisibilityPriority) priority
                       forView: (NSView *) view
{
    if (view == nil)
        return;
    if (_visibilityPriorities == nil)
        _visibilityPriorities = [[NSMutableDictionary alloc] init];
    [_visibilityPriorities setObject: [NSNumber numberWithFloat: priority]
                              forKey: [NSValue valueWithNonretainedObject: view]];
}

- (NSStackViewVisibilityPriority) visibilityPriorityForView: (NSView *) view {
    NSNumber *priority = [_visibilityPriorities
            objectForKey: [NSValue valueWithNonretainedObject: view]];
    return priority ? [priority floatValue] : NSStackViewVisibilityPriorityMustHold;
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
