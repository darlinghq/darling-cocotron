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

#import <AppKit/AppKitExport.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
@class NSDictionary;
#import <Foundation/NSString.h>

typedef float NSLayoutPriority NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSLayoutConstraint.Priority);

static const NSLayoutPriority NSLayoutPriorityRequired NS_SWIFT_NAME(required) = 1000;
static const NSLayoutPriority NSLayoutPriorityDefaultHigh NS_SWIFT_NAME(defaultHigh) = 750;
static const NSLayoutPriority NSLayoutPriorityDefaultLow NS_SWIFT_NAME(defaultLow) = 250;
static const NSLayoutPriority NSLayoutPriorityFittingSizeCompression NS_SWIFT_NAME(fittingSizeCompression) = 50;

typedef NS_ENUM(NSInteger, NSLayoutAttribute) {
	NSLayoutAttributeNotAnAttribute = 0,
	NSLayoutAttributeLeft = 1,
	NSLayoutAttributeRight,
	NSLayoutAttributeTop,
	NSLayoutAttributeBottom,
	NSLayoutAttributeLeading,
	NSLayoutAttributeTrailing,
	NSLayoutAttributeWidth,
	NSLayoutAttributeHeight,
	NSLayoutAttributeCenterX,
	NSLayoutAttributeCenterY,
	NSLayoutAttributeLastBaseline,
	NSLayoutAttributeBaseline = NSLayoutAttributeLastBaseline,
	NSLayoutAttributeFirstBaseline,
};

typedef NS_ENUM(NSInteger, NSLayoutConstraintOrientation) {
	NSLayoutConstraintOrientationHorizontal = 0,
	NSLayoutConstraintOrientationVertical = 1,
} NS_SWIFT_NAME(NSLayoutConstraint.Orientation);

typedef NS_ENUM(NSInteger, NSLayoutRelation) {
	NSLayoutRelationLessThanOrEqual = -1,
	NSLayoutRelationEqual = 0,
	NSLayoutRelationGreaterThanOrEqual = 1,
};

@interface NSLayoutConstraint : NSObject
{
    id _firstItem;
    NSInteger _firstAttribute;
    NSInteger _relation;
    id _secondItem;
    NSInteger _secondAttribute;
    double _multiplier;
    double _constant;
    float _priority;
    NSString *_identifier;
    NSString *_symbolicConstant;
    BOOL _active;
    BOOL _shouldBeArchived;
    id _owner;
}

+ (instancetype) constraintWithItem: (id) view1
                          attribute: (NSLayoutAttribute) attr1
                          relatedBy: (NSLayoutRelation) relation
                             toItem: (id) view2
                          attribute: (NSLayoutAttribute) attr2
                         multiplier: (CGFloat) multiplier
                           constant: (CGFloat) c;
+ (void) activateConstraints: (NSArray<NSLayoutConstraint *> *) constraints;
+ (void) deactivateConstraints: (NSArray<NSLayoutConstraint *> *) constraints;

@property(readonly, assign) id firstItem;
@property(readonly, assign) id secondItem;
@property(readonly) NSLayoutAttribute firstAttribute;
@property(readonly) NSLayoutAttribute secondAttribute;
@property(readonly) NSLayoutRelation relation;
@property(readonly) CGFloat multiplier;
@property CGFloat constant;
@property NSLayoutPriority priority;
@property(copy) NSString *identifier;
// Setting it to YES installs the constraint on the closest common ancestor of
// its items (raising NSInvalidArgumentException when they share none); NO
// removes it from the view that holds it.
@property(getter=isActive) BOOL active;
@property BOOL shouldBeArchived;

@end

// Builds the dictionary of names to values that visual format strings refer to:
// NSDictionaryOfVariableBindings(a, b) maps @"a" to a and @"b" to b.
APPKIT_EXPORT NSDictionary *_NSDictionaryOfVariableBindings(NSString *commaSeparatedKeysString, id firstValue, ...);
#define NSDictionaryOfVariableBindings(...) _NSDictionaryOfVariableBindings(@#__VA_ARGS__, __VA_ARGS__, nil)

APPKIT_EXPORT const CGFloat NSViewNoInstrinsicMetric;
APPKIT_EXPORT const CGFloat NSViewNoIntrinsicMetric NS_SWIFT_NAME(NSView.noIntrinsicMetric);

// Insets named by writing direction rather than by side.
typedef struct NSDirectionalEdgeInsets {
	CGFloat top;
	CGFloat leading;
	CGFloat bottom;
	CGFloat trailing;
} NSDirectionalEdgeInsets;

APPKIT_EXPORT const NSDirectionalEdgeInsets NSDirectionalEdgeInsetsZero;

NS_INLINE NSDirectionalEdgeInsets NSDirectionalEdgeInsetsMake(CGFloat top, CGFloat leading,
                                                              CGFloat bottom, CGFloat trailing) {
	NSDirectionalEdgeInsets insets = {top, leading, bottom, trailing};
	return insets;
}
