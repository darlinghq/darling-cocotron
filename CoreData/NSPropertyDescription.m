/* Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPropertyDescription.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSRaise.h>
#import "NSPropertyDescription-Private.h"
#import "NSEntityDescription-Private.h"

@implementation NSPropertyDescription

- init {
    if ([self class] == [NSPropertyDescription class]) {
        NSInvalidAbstractInvocation();
        return nil;
    }
    return [super init];
}

- (void)_setEntity:(NSEntityDescription *)entity {
    _entity = entity;
}

- (void)_checkMutable {
    if ([_entity _hasBeenInstantiated])
        [NSException raise:NSInvalidArgumentException format:@"The managed object model is in use."];
}

- (void)dealloc {
    [_propertyName release];
    [_userInfo release];
    [_validationPredicates release];
    [_validationWarnings release];
    [super dealloc];
}

- initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ can not initWithCoder:%@", [self class],
                            [coder class]];

    _entity = [coder decodeObjectForKey: @"NSEntity"];
    _propertyName = [[coder decodeObjectForKey: @"NSPropertyName"] copy];

    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSInvalidAbstractInvocation();
}

- (BOOL) isEqual: (id) object {
    if (![object isKindOfClass: [NSPropertyDescription class]])
        return NO;
    NSPropertyDescription *property = (NSPropertyDescription *) object;
    if ((_entity == [property entity]) &&
        [_propertyName isEqualToString: [property name]])
        return YES;
    else
        return NO;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (NSEntityDescription *) entity {
    return _entity;
}

- (NSString *) name {
    return _propertyName;
}

- (BOOL) isOptional {
    return _optional;
}

- (BOOL) isTransient {
    return _transient;
}

- (NSDictionary *) userInfo {
    return _userInfo;
}

// GUESS: the documentation does not say what the arrays are before they are set. The public
// header declares both as non-null, so an unset property returns an empty array, not nil.
- (NSArray *) validationPredicates {
    return _validationPredicates ? _validationPredicates : [NSArray array];
}

- (NSArray *) validationWarnings {
    return _validationWarnings ? _validationWarnings : [NSArray array];
}

- (void) setName: (NSString *) value {
    [self _checkMutable];
    if (![value length])
        [NSException raise:NSInvalidArgumentException format:@"A property requires a nonempty name."];
    NSString *name = [value copy];
    @try {
        [_entity _renameProperty:self from:_propertyName to:name];
    } @catch (id exception) {
        [name release];
        @throw;
    }
    [_propertyName release];
    _propertyName = name;
}

- (void) setOptional: (BOOL) value {
    [self _checkMutable];
    _optional = value;
}

- (void) setTransient: (BOOL) value {
    [self _checkMutable];
    _transient = value;
}

- (void) setUserInfo: (NSDictionary *) value {
    [self _checkMutable];
    value = [value retain];
    [_userInfo release];
    _userInfo = value;
}

// GUESS: the documentation says the arrays "should contain the same number of elements" without
// saying what happens otherwise. A length mismatch raises NSInvalidArgumentException (rejected
// alternative: store them and let the warnings run out of range when a predicate fails). The
// arrays are stored as immutable copies so a later change to the caller's array cannot break
// the pairing of predicates and warnings.
- (void) setValidationPredicates: (NSArray *) predicates
          withValidationWarnings: (NSArray *) warnings
{
    [self _checkMutable];
    if ([predicates count] != [warnings count])
        [NSException raise:NSInvalidArgumentException
                    format:@"The validation predicates and validation warnings must have the same number of elements."];
    predicates = [predicates copy];
    warnings = [warnings copy];
    [_validationPredicates release];
    [_validationWarnings release];
    _validationPredicates = predicates;
    _validationWarnings = warnings;
}

@end
