/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

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

#import "CAPresentationModifier.h"

@implementation CAPresentationModifierGroup

+ (instancetype) groupWithCapacity: (NSUInteger) capacity {
    return [[[self alloc] initWithCapacity: capacity] autorelease];
}

- (instancetype) initWithCapacity: (NSUInteger) capacity {
    self = [super init];
    if (self != nil)
        _capacity = capacity;
    return self;
}

- (NSUInteger) capacity {
    return _capacity;
}

// No layer consumes modifiers yet (see the header), so there is nothing to
// send to the render tree.
- (void) flush {
}

- (void) flushWithTransaction {
}

@end

@implementation CAPresentationModifier

- (instancetype) initWithKeyPath: (NSString *) keyPath
                    initialValue: (id) value
                        additive: (BOOL) additive
                           group: (CAPresentationModifierGroup *) group
{
    self = [super init];
    if (self != nil) {
        _keyPath = [keyPath copy];
        _value = [value retain];
        _additive = additive;
        _group = [group retain];
    }
    return self;
}

- (void) dealloc {
    [_keyPath release];
    [_value release];
    [_group release];
    [super dealloc];
}

- (NSString *) keyPath {
    return _keyPath;
}

- (BOOL) additive {
    return _additive;
}

- (CAPresentationModifierGroup *) group {
    return _group;
}

// The value may be updated from a thread other than the one reading it.
- (id) value {
    id value;
    @synchronized(self) {
        value = [_value retain];
    }
    return [value autorelease];
}

- (void) setValue: (id) value {
    id old;
    [value retain];
    @synchronized(self) {
        old = _value;
        _value = value;
    }
    [old release];
}

@end
