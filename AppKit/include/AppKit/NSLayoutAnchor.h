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
// Swift spells these constraint(equalToConstant:) and so on; the importer would
// otherwise derive constraintEqualToConstant(_:) and the macOS spelling would
// not resolve at all. The return is nonnull because -_constraintWithRelation:
// always builds a constraint, and because callers write the result straight
// into a non-optional; unannotated it arrives as NSLayoutConstraint? here.
- (NSLayoutConstraint *_Nonnull) constraintEqualToConstant: (CGFloat) c
        NS_SWIFT_NAME(constraint(equalToConstant:));
- (NSLayoutConstraint *_Nonnull) constraintGreaterThanOrEqualToConstant: (CGFloat) c
        NS_SWIFT_NAME(constraint(greaterThanOrEqualToConstant:));
- (NSLayoutConstraint *_Nonnull) constraintLessThanOrEqualToConstant: (CGFloat) c
        NS_SWIFT_NAME(constraint(lessThanOrEqualToConstant:));
// The ...ToAnchor: family is deliberately left unnamed. Applying the same rule
// as above gives constraint(equalToAnchor:), and macOS is understood to drop
// the "Anchor" instead - constraint(equalTo:) - which is a special case, not
// something the selector implies. No source here settles it, and a wrong
// NS_SWIFT_NAME compiles and silently binds the wrong overload, so these keep
// their derived names until someone can check against the real SDK.
- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m;
- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m;
- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m;
- (NSLayoutConstraint *) constraintEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c;
- (NSLayoutConstraint *) constraintGreaterThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c;
- (NSLayoutConstraint *) constraintLessThanOrEqualToAnchor: (NSLayoutDimension *) anchor multiplier: (CGFloat) m constant: (CGFloat) c;
@end
