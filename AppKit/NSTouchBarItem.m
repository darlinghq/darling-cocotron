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

#import <AppKit/NSTouchBarItem.h>

NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFixedSpaceLarge =
        @"NSTouchBarItemIdentifierFixedSpaceLarge";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFixedSpaceSmall =
        @"NSTouchBarItemIdentifierFixedSpaceSmall";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFlexibleSpace =
        @"NSTouchBarItemIdentifierFlexibleSpace";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierOtherItemsProxy =
        @"NSTouchBarItemIdentifierOtherItemsProxy";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierCharacterPicker =
        @"NSTouchBarItemIdentifierCharacterPicker";

@interface NSColorPickerTouchBarItem : NSTouchBarItem
@end

@interface NSSharingServicePickerTouchBarItem : NSTouchBarItem
@end

@interface NSSliderTouchBarItem : NSTouchBarItem
@end

@implementation NSTouchBarItem

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

- (instancetype) initWithIdentifier: (NSTouchBarItemIdentifier) identifier {
    if ((self = [super init]) != nil)
        _identifier = [identifier copy];
    return self;
}

- (void) dealloc {
    [_identifier release];
    [super dealloc];
}

@end

@implementation NSColorPickerTouchBarItem

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSSharingServicePickerTouchBarItem

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSSliderTouchBarItem

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
