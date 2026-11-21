/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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

#import "NSTargetBinder.h"
#import "NSObject+BindingSupport.h"
#import <AppKit/NSController.h>
#import <AppKit/NSKeyValueBinding.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSString.h>

static void *NSTargetBinderChangeContext;

BOOL _NSIsTargetOrArgumentBinding(NSString *binding) {
    if ([binding isEqualToString: NSTargetBinding])
        return YES;
    if (![binding hasPrefix: NSArgumentBinding])
        return NO;
    NSString *number = [binding substringFromIndex: [NSArgumentBinding length]];
    return [number rangeOfCharacterFromSet: [[NSCharacterSet decimalDigitCharacterSet]
                                                    invertedSet]]
                   .location == NSNotFound;
}

// 1 for "argument", n for "argumentn", 0 for "target".
static NSUInteger argumentNumber(NSString *binding) {
    if (![binding hasPrefix: NSArgumentBinding])
        return 0;
    NSString *number = [binding substringFromIndex: [NSArgumentBinding length]];
    return [number length] == 0 ? 1 : (NSUInteger) [number integerValue];
}

@implementation _NSTargetBinder

// The bound value; nil for no value, NSNull and the controller markers.
- (id) _boundValue {
    id value = [_destination valueForKeyPath: _keyPath];
    if (value == [NSNull null] || value == NSMultipleValuesMarker ||
        value == NSNoSelectionMarker || value == NSNotApplicableMarker)
        return nil;
    return [self transformedObject: value];
}

- (BOOL) _allowsNullArgument {
    return [[_options objectForKey: NSAllowsNullArgumentBindingOption] boolValue];
}

// NSConditionallySetsEnabled is on for these bindings unless the options
// turn it off.
- (BOOL) _setsEnabled {
    id option = [_options objectForKey: NSConditionallySetsEnabledBindingOption];
    return (option == nil || [option boolValue]) &&
           [_source respondsToSelector: @selector(setEnabled:)];
}

static NSArray *targetBinders(id source) {
    NSMutableArray *result = [NSMutableArray array];
    for (_NSBinder *binder in [source _allUsedBinders])
        if ([binder isKindOfClass: [_NSTargetBinder class]])
            [result addObject: binder];
    return result;
}

// The control is enabled while the target is there and so is every argument
// that may not be nil.
- (void) _updateEnabled {
    if (![self _setsEnabled])
        return;
    BOOL enabled = YES;
    for (_NSTargetBinder *binder in targetBinders(_source)) {
        BOOL isArgument = argumentNumber([binder binding]) != 0;
        if ([binder _boundValue] == nil && !(isArgument && [binder _allowsNullArgument]))
            enabled = NO;
    }
    [_source setEnabled: enabled];
}

- (void) startObservingChanges {
    if (!_isObserving && _destination != nil) {
        [_destination addObserver: self
                       forKeyPath: _keyPath
                          options: 0
                          context: &NSTargetBinderChangeContext];
        _isObserving = YES;
    }
}

- (void) stopObservingChanges {
    if (_isObserving) {
        [_destination removeObserver: self forKeyPath: _keyPath];
        _isObserving = NO;
    }
}

- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context
{
    if (context == &NSTargetBinderChangeContext)
        [self _updateEnabled];
    else
        [super observeValueForKeyPath: keyPath ofObject: object change: change context: context];
}

- (void) bind {
    [self _updateEnabled];
    [self startObservingChanges];
}

- (void) unbind {
    [self stopObservingChanges];
}

@end

BOOL _NSSendTargetBindingAction(id source) {
    _NSTargetBinder *targetBinder = nil;
    NSMutableDictionary *argumentBinders = [NSMutableDictionary dictionary];
    for (_NSTargetBinder *binder in targetBinders(source)) {
        NSUInteger number = argumentNumber([binder binding]);
        if (number == 0)
            targetBinder = binder;
        else
            [argumentBinders setObject: binder forKey: [NSNumber numberWithUnsignedInteger: number]];
    }
    if (targetBinder == nil)
        return NO;

    id target = [targetBinder _boundValue];
    NSString *selectorName = [[targetBinder options] objectForKey: NSSelectorNameBindingOption];
    if (target == nil || [selectorName length] == 0)
        return NO;

    SEL selector = NSSelectorFromString(selectorName);
    NSMethodSignature *signature = [target methodSignatureForSelector: selector];
    if (signature == nil) {
        [target doesNotRecognizeSelector: selector];
        return NO;
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature: signature];
    [invocation setTarget: target];
    [invocation setSelector: selector];
    for (NSUInteger i = 2; i < [signature numberOfArguments]; i++) {
        _NSTargetBinder *binder =
                [argumentBinders objectForKey: [NSNumber numberWithUnsignedInteger: i - 1]];
        id argument = [binder _boundValue];
        if (argument == nil && ![binder _allowsNullArgument])
            return NO;
        // Only object arguments can be passed.
        if ([signature getArgumentTypeAtIndex: i][0] != '@')
            return NO;
        [invocation setArgument: &argument atIndex: i];
    }
    [invocation invoke];
    return YES;
}
