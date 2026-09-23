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

#import <Foundation/Foundation.h>

@class NSLayoutConstraint;

// An anchor names one layout attribute (NSLayoutAttribute value) of an item. Constraints made from anchors
// are NSLayoutConstraint models; Darling does not solve them.
@interface NSLayoutAnchor : NSObject {
    id _item;
    NSInteger _attribute;
}

- (instancetype) initWithItem: (id) item attribute: (NSInteger) attribute;

@property(readonly, assign) id item;
@property(readonly) NSInteger attribute;
@property(readonly, copy) NSString *name;

- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutAnchor *) anchor;
- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutAnchor *) anchor;
- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutAnchor *) anchor;
- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutAnchor *) anchor constant: (CGFloat) c;
- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutAnchor *) anchor constant: (CGFloat) c;
- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutAnchor *) anchor constant: (CGFloat) c;
@end

@interface NSLayoutXAxisAnchor : NSLayoutAnchor
@end

@interface NSLayoutYAxisAnchor : NSLayoutAnchor
@end

@interface NSLayoutDimension : NSLayoutAnchor
- (NSLayoutConstraint *) constraintEqualToConstant: (CGFloat) c;
- (NSLayoutConstraint *) constraintGreaterThanOrEqualToConstant: (CGFloat) c;
- (NSLayoutConstraint *) constraintLessThanOrEqualToConstant: (CGFloat) c;
- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m;
- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m;
- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m;
- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c;
- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c;
- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c;
@end
