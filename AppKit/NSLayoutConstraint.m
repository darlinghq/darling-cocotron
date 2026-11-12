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

#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSLayoutGuide.h>
#import <AppKit/NSView.h>
#import "NSLayoutConstraintInternal.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>

// The container that holds an item: a view's superview, or a layout guide's
// owning view.
static id _NSLayoutItemParent(id item)
{
    if ([item isKindOfClass:[NSView class]])
        return [item superview];
    if ([item respondsToSelector:@selector(owningView)])
        return [item owningView];
    return nil;
}

static BOOL _NSLayoutItemIsWithin(id item, id container)
{
    for (; item != nil; item = _NSLayoutItemParent(item)) {
        if (item == container)
            return YES;
    }
    return NO;
}

// A model of a layout constraint: it stores and archives the constraint's description.
// AppKit owns the installed constraint and applies its layout equations.
@implementation NSLayoutConstraint

+ (instancetype)constraintWithItem:(id)view1
                         attribute:(NSLayoutAttribute)attr1
                         relatedBy:(NSLayoutRelation)relation
                            toItem:(id)view2
                         attribute:(NSLayoutAttribute)attr2
                        multiplier:(CGFloat)multiplier
                          constant:(CGFloat)c
{
    NSLayoutConstraint *constraint = [[self alloc] init];
    constraint->_firstItem = view1;
    constraint->_firstAttribute = attr1;
    constraint->_relation = relation;
    constraint->_secondItem = view2;
    constraint->_secondAttribute = attr2;
    constraint->_multiplier = multiplier;
    constraint->_constant = c;
    return [constraint autorelease];
}

+ (void)activateConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *constraint in constraints)
        [constraint setActive:YES];
}

+ (void)deactivateConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *constraint in constraints)
        [constraint setActive:NO];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _multiplier = 1;
        _priority = NSLayoutPriorityRequired;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (![coder allowsKeyedCoding]) {
        [self release];
        return nil;
    }

    if ((self = [self init])) {
        // Items are views or layout guides owned by the view hierarchy; don't retain them.
        _firstItem = [coder decodeObjectForKey:@"NSFirstItem"];
        _secondItem = [coder decodeObjectForKey:@"NSSecondItem"];

        _firstAttribute = [coder containsValueForKey:@"NSFirstAttributeV2"]
            ? [coder decodeIntegerForKey:@"NSFirstAttributeV2"]
            : [coder decodeIntegerForKey:@"NSFirstAttribute"];
        _secondAttribute = [coder containsValueForKey:@"NSSecondAttributeV2"]
            ? [coder decodeIntegerForKey:@"NSSecondAttributeV2"]
            : [coder decodeIntegerForKey:@"NSSecondAttribute"];
        if (_secondItem == nil)
            _secondAttribute = NSLayoutAttributeNotAnAttribute;

        _relation = [coder containsValueForKey:@"NSRelation"]
            ? [coder decodeIntegerForKey:@"NSRelation"]
            : NSLayoutRelationEqual;

        if ([coder containsValueForKey:@"NSMultiplier"])
            _multiplier = [coder decodeDoubleForKey:@"NSMultiplier"];

        if ([coder containsValueForKey:@"NSConstantV2"])
            _constant = [coder decodeDoubleForKey:@"NSConstantV2"];
        else if ([coder containsValueForKey:@"NSConstant"])
            _constant = [coder decodeDoubleForKey:@"NSConstant"];

        if ([coder containsValueForKey:@"NSPriority"])
            _priority = [coder decodeFloatForKey:@"NSPriority"];

        _symbolicConstant = [[coder decodeObjectForKey:@"NSSymbolicConstant"] retain];
        _identifier = [[coder decodeObjectForKey:@"NSLayoutIdentifier"] retain];
        _shouldBeArchived = [coder decodeBoolForKey:@"NSShouldBeArchived"];
        _active = YES;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if (![coder allowsKeyedCoding])
        return;

    [coder encodeConditionalObject:_firstItem forKey:@"NSFirstItem"];
    [coder encodeInteger:_firstAttribute forKey:@"NSFirstAttribute"];
    [coder encodeInteger:_firstAttribute forKey:@"NSFirstAttributeV2"];
    if (_relation != NSLayoutRelationEqual)
        [coder encodeInteger:_relation forKey:@"NSRelation"];
    if (_secondItem != nil) {
        [coder encodeConditionalObject:_secondItem forKey:@"NSSecondItem"];
        [coder encodeInteger:_secondAttribute forKey:@"NSSecondAttribute"];
        [coder encodeInteger:_secondAttribute forKey:@"NSSecondAttributeV2"];
    }
    if (_multiplier != 1)
        [coder encodeDouble:_multiplier forKey:@"NSMultiplier"];
    if (_constant != 0) {
        [coder encodeDouble:_constant forKey:@"NSConstant"];
        [coder encodeDouble:_constant forKey:@"NSConstantV2"];
    }
    if (_priority != NSLayoutPriorityRequired)
        [coder encodeFloat:_priority forKey:@"NSPriority"];
    if (_symbolicConstant)
        [coder encodeObject:_symbolicConstant forKey:@"NSSymbolicConstant"];
    if (_identifier)
        [coder encodeObject:_identifier forKey:@"NSLayoutIdentifier"];
    [coder encodeBool:_shouldBeArchived forKey:@"NSShouldBeArchived"];
}

- (void)dealloc
{
    [_identifier release];
    [_symbolicConstant release];
    [super dealloc];
}

- (id)firstItem { return _firstItem; }
- (id)secondItem { return _secondItem; }
- (NSLayoutAttribute)firstAttribute { return _firstAttribute; }
- (NSLayoutAttribute)secondAttribute { return _secondAttribute; }
- (NSLayoutRelation)relation { return _relation; }
- (CGFloat)multiplier { return _multiplier; }

- (CGFloat)constant { return _constant; }
- (void)setConstant:(CGFloat)constant { _constant = constant; }

- (NSLayoutPriority)priority { return _priority; }
- (void)setPriority:(NSLayoutPriority)priority { _priority = priority; }

- (NSString *)identifier { return _identifier; }
- (void)setIdentifier:(NSString *)identifier
{
    NSString *copy = [identifier copy];
    [_identifier release];
    _identifier = copy;
}

- (BOOL)isActive { return _active; }

// Activation installs the constraint on the closest common ancestor of its two
// items (the first item itself for a one-item constraint) and raises if the
// items are not in one hierarchy. The view's -addConstraint: links the
// constraint back through -_attachToOwner:.
- (void)setActive:(BOOL)active
{
    if (!active) {
        id owner = _owner;
        if (owner != nil)
            [owner removeConstraint:self];
        _active = NO;
        return;
    }
    if (_active && _owner != nil)
        return;

    id owner = _firstItem;
    if (_secondItem != nil) {
        while (owner != nil && !_NSLayoutItemIsWithin(_secondItem, owner))
            owner = _NSLayoutItemParent(owner);
    }
    if (![owner isKindOfClass:[NSView class]])
        [NSException raise:NSInvalidArgumentException
                    format:@"The items of a layout constraint must share a common ancestor view: %@", self];
    [owner addConstraint:self];
}

- (void)_attachToOwner:(id)owner
{
    if (_owner != nil && _owner != owner)
        [_owner removeConstraint:self];
    _owner = owner;
    _active = YES;
}

- (void)_detachFromOwner:(id)owner
{
    if (_owner == owner) {
        _owner = nil;
        _active = NO;
    }
}

- (BOOL)shouldBeArchived { return _shouldBeArchived; }
- (void)setShouldBeArchived:(BOOL)shouldBeArchived { _shouldBeArchived = shouldBeArchived; }

- (NSString *)description
{
    static const char *const relations[] = { "<=", "==", ">=" };
    const char *relation = (_relation >= -1 && _relation <= 1) ? relations[_relation + 1] : "?";
    return [NSString stringWithFormat:@"<%@ %p %@.%ld %s %@.%ld * %g + %g @%g>", [self class], self,
            [_firstItem class], (long)_firstAttribute, relation, [_secondItem class], (long)_secondAttribute,
            _multiplier, _constant, _priority];
}

@end

// 0xbff0000000000000 is the bit pattern of -1.0, not the value; as a CGFloat
// initialiser it yielded 1.38e19, so every "no intrinsic metric" test failed.
const CGFloat NSViewNoInstrinsicMetric = -1.0;
const CGFloat NSViewNoIntrinsicMetric = -1.0;

const NSDirectionalEdgeInsets NSDirectionalEdgeInsetsZero = {0, 0, 0, 0};
