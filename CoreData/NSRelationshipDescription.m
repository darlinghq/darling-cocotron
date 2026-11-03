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
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <Foundation/NSKeyedUnarchiver.h>

#import "NSPropertyDescription-Private.h"

@implementation NSRelationshipDescription

- init {
    self = [super init];
    if (self)
        _deleteRule = NSNullifyDeleteRule;
    return self;
}

- initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ can not initWithCoder:%@", [self class],
                            [coder class]];

    [super initWithCoder: coder];

    _deleteRule = [coder decodeIntForKey: @"NSDeleteRule"];
    _destinationEntity = [coder decodeObjectForKey: @"NSDestinationEntity"];
    _inverseRelationship = [coder decodeObjectForKey: @"NSInverseRelationship"];
    _optional = [coder decodeBoolForKey: @"NSIsOptional"];
    _maxCount = [coder decodeIntForKey: @"NSMaxCount"];
    _minCount = [coder decodeIntForKey: @"NSMinCount"];

    _destinationEntityName =
            [[coder decodeObjectForKey: @"_NSDestinationEntityName"] copy];
    _inverseRelationshipName =
            [[coder decodeObjectForKey: @"_NSInverseRelationshipName"] copy];

    return self;
}

- (void)dealloc {
    [_destinationEntityName release];
    [_inverseRelationshipName release];
    [super dealloc];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<NSRelationshipDescription: %@->%@>",
                                       _propertyName, _destinationEntityName];
}

- (BOOL) isToMany {
    return _maxCount != 1;
}

- (NSUInteger) maxCount {
    return _maxCount;
}

- (NSUInteger) minCount {
    return _minCount;
}

- (NSDeleteRule) deleteRule {
    return _deleteRule;
}

- (NSEntityDescription *) destinationEntity {
    return _destinationEntity;
}

- (NSRelationshipDescription *) inverseRelationship {
    return _inverseRelationship;
}

- (void) setMaxCount: (NSUInteger) value {
    [self _checkMutable];

    _maxCount = value;
}

- (void) setMinCount: (NSUInteger) value {
    [self _checkMutable];

    _minCount = value;
}

- (void) setDeleteRule: (NSDeleteRule) value {
    [self _checkMutable];

    _deleteRule = value;
}

- (void) setDestinationEntity: (NSEntityDescription *) value {
    [self _checkMutable];

    _destinationEntity = value;
    [_destinationEntityName release];
    _destinationEntityName = [[value name] copy];
}

- (void) setInverseRelationship: (NSRelationshipDescription *) value {
    [self _checkMutable];

    _inverseRelationship = value;
    [_inverseRelationshipName release];
    _inverseRelationshipName = [[value name] copy];
}

@end
