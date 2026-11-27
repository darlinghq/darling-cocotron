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

@interface CAPresentationModifierGroup (Internal)
- (void) _incrementCount;
- (void) _decrementCount;
@end

@implementation CAPresentationModifierGroup

+ (instancetype) groupWithCapacity: (NSUInteger) capacity {
    return [[[self alloc] initWithCapacity: capacity] autorelease];
}

- (instancetype) initWithCapacity: (NSUInteger) capacity {
    self = [super init];
    if (self != nil) {
        _capacity = capacity;
        // QUIRK: a new group updates asynchronously. Not documented (SPI). Evidence: black-box observation on
        // macOS 26.7.3 (tier 2). Test: tests/quartzcore-swiftui-layer-spis.m
        _updatesAsynchronously = YES;
    }
    return self;
}

- (NSUInteger) count {
    return _count;
}

- (NSUInteger) capacity {
    return _capacity;
}

- (BOOL) updatesAsynchronously {
    return _updatesAsynchronously;
}

- (void) setUpdatesAsynchronously: (BOOL) updatesAsynchronously {
    _updatesAsynchronously = updatesAsynchronously;
}

- (void) _incrementCount {
    _count++;
}

- (void) _decrementCount {
    if (_count > 0)
        _count--;
}

// No layer consumes modifiers yet (see the header), so there is nothing to
// send to the render tree.
- (void) flush {
}

- (void) flushWithTargetTime: (double) targetTime {
}

- (void) flushLocally {
}

- (void) flushLocallyWithTargetTime: (double) targetTime {
}

- (void) flushWithTransaction {
}

- (void) flushWithTransactionAndTargetTime: (double) targetTime {
}

@end

@implementation CAPresentationModifier

- (instancetype) initWithKeyPath: (NSString *) keyPath
                    initialValue: (id) value
                        additive: (BOOL) additive
{
    return [self initWithKeyPath: keyPath
                    initialValue: value
                 initialVelocity: nil
                        additive: additive
  preferredFrameRateRangeMaximum: 0
                           group: nil];
}

- (instancetype) initWithKeyPath: (NSString *) keyPath
                    initialValue: (id) value
                        additive: (BOOL) additive
                           group: (CAPresentationModifierGroup *) group
{
    return [self initWithKeyPath: keyPath
                    initialValue: value
                 initialVelocity: nil
                        additive: additive
  preferredFrameRateRangeMaximum: 0
                           group: group];
}

- (instancetype) initWithKeyPath: (NSString *) keyPath
                    initialValue: (id) initialValue
                 initialVelocity: (id) initialVelocity
                        additive: (BOOL) additive
  preferredFrameRateRangeMaximum: (NSInteger) preferredFrameRateRangeMaximum
                           group: (CAPresentationModifierGroup *) group
{
    self = [super init];
    if (self != nil) {
        _keyPath = [keyPath copy];
        _value = [initialValue retain];
        _velocity = [initialVelocity retain];
        _additive = additive;
        _enabled = YES;
        _group = [group retain];
        [group _incrementCount];
    }
    return self;
}

- (void) dealloc {
    [_keyPath release];
    [_value release];
    [_velocity release];
    [_group _decrementCount];
    [_group release];
    [super dealloc];
}

- (BOOL) isEnabled {
    return _enabled;
}

- (void) setEnabled: (BOOL) enabled {
    _enabled = enabled;
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
    [self setValue: value velocity: nil];
}

- (void) setValue: (id) value velocity: (id) velocity {
    id oldValue;
    id oldVelocity;
    [value retain];
    [velocity retain];
    @synchronized(self) {
        oldValue = _value;
        _value = value;
        oldVelocity = _velocity;
        _velocity = velocity;
    }
    [oldValue release];
    [oldVelocity release];
}

@end
