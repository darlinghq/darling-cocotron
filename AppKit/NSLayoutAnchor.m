/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

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

#import <AppKit/NSLayoutAnchor.h>
#import <AppKit/NSLayoutConstraint.h>

// Implemented in NSLayoutConstraint.m; AppKit declares it publicly.
@interface NSLayoutConstraint (NSLayoutAnchorConstruction)
+ (instancetype) constraintWithItem: (id) view1
                          attribute: (NSInteger) attr1
                          relatedBy: (NSInteger) relation
                             toItem: (id) view2
                          attribute: (NSInteger) attr2
                         multiplier: (double) multiplier
                           constant: (double) c;
@end

// NSLayoutRelation and NSLayoutAttribute values (AppKit/NSLayoutConstraint.h)
enum {
    AnchorRelationLessThanOrEqual = -1,
    AnchorRelationEqual = 0,
    AnchorRelationGreaterThanOrEqual = 1,
};
enum {
    AnchorAttributeNotAnAttribute = 0,
};

@implementation NSLayoutAnchor

@synthesize item = _item;
@synthesize attribute = _attribute;

- (instancetype) initWithItem: (id) item attribute: (NSInteger) attribute {
    self = [super init];
    if (self) {
        _item = item;
        _attribute = attribute;
    }
    return self;
}

- (NSString *) name {
    return [NSString stringWithFormat: @"%@<%p>.attribute%ld", [_item class], _item, (long) _attribute];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ %p %@>", [self class], self, [self name]];
}

- (NSLayoutConstraint *) _constraintWithRelation: (NSInteger) relation
                                          anchor: (NSLayoutAnchor *) anchor
                                      multiplier: (CGFloat) multiplier
                                        constant: (CGFloat) c
{
    if (anchor == nil) {
        [NSException raise: NSInvalidArgumentException format: @"%@: nil anchor", NSStringFromSelector(_cmd)];
    }
    return [NSLayoutConstraint constraintWithItem: _item
                                        attribute: _attribute
                                        relatedBy: relation
                                           toItem: anchor->_item
                                        attribute: anchor->_attribute
                                       multiplier: multiplier
                                         constant: c];
}

- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutAnchor *) anchor {
    return [self _constraintWithRelation: AnchorRelationEqual anchor: anchor multiplier: 1 constant: 0];
}

- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutAnchor *) anchor {
    return [self _constraintWithRelation: AnchorRelationGreaterThanOrEqual anchor: anchor multiplier: 1 constant: 0];
}

- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutAnchor *) anchor {
    return [self _constraintWithRelation: AnchorRelationLessThanOrEqual anchor: anchor multiplier: 1 constant: 0];
}

- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutAnchor *) anchor constant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationEqual anchor: anchor multiplier: 1 constant: c];
}

- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutAnchor *) anchor constant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationGreaterThanOrEqual anchor: anchor multiplier: 1 constant: c];
}

- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutAnchor *) anchor constant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationLessThanOrEqual anchor: anchor multiplier: 1 constant: c];
}

@end

@implementation NSLayoutXAxisAnchor
@end

@implementation NSLayoutYAxisAnchor
@end

@implementation NSLayoutDimension

- (NSLayoutConstraint *) _constraintWithRelation: (NSInteger) relation constant: (CGFloat) c {
    return [NSLayoutConstraint constraintWithItem: _item
                                        attribute: _attribute
                                        relatedBy: relation
                                           toItem: nil
                                        attribute: AnchorAttributeNotAnAttribute
                                       multiplier: 1
                                         constant: c];
}

- (NSLayoutConstraint *) constraintEqualToConstant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationEqual constant: c];
}

- (NSLayoutConstraint *) constraintGreaterThanOrEqualToConstant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationGreaterThanOrEqual constant: c];
}

- (NSLayoutConstraint *) constraintLessThanOrEqualToConstant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationLessThanOrEqual constant: c];
}

- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m {
    return [self _constraintWithRelation: AnchorRelationEqual anchor: anchor multiplier: m constant: 0];
}

- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m {
    return [self _constraintWithRelation: AnchorRelationGreaterThanOrEqual anchor: anchor multiplier: m constant: 0];
}

- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m {
    return [self _constraintWithRelation: AnchorRelationLessThanOrEqual anchor: anchor multiplier: m constant: 0];
}

- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationEqual anchor: anchor multiplier: m constant: c];
}

- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationGreaterThanOrEqual anchor: anchor multiplier: m constant: c];
}

- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c {
    return [self _constraintWithRelation: AnchorRelationLessThanOrEqual anchor: anchor multiplier: m constant: c];
}

@end
