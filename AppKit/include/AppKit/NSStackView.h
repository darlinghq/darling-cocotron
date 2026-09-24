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

#import <AppKit/NSView.h>
#import <AppKit/NSLayoutConstraint.h>
#include <float.h>

@class NSMutableArray;
@protocol NSStackViewDelegate;

typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutOrientation) {
    NSUserInterfaceLayoutOrientationHorizontal = 0,
    NSUserInterfaceLayoutOrientationVertical = 1,
};

typedef NS_ENUM(NSInteger, NSStackViewGravity) {
    NSStackViewGravityTop = 1,
    NSStackViewGravityLeading = 1,
    NSStackViewGravityCenter = 2,
    NSStackViewGravityBottom = 3,
    NSStackViewGravityTrailing = 3,
};

typedef NS_ENUM(NSInteger, NSStackViewDistribution) {
    NSStackViewDistributionGravityAreas = -1,
    NSStackViewDistributionFill = 0,
    NSStackViewDistributionFillEqually,
    NSStackViewDistributionFillProportionally,
    NSStackViewDistributionEqualSpacing,
    NSStackViewDistributionEqualCentering,
};

typedef float NSStackViewVisibilityPriority;

static const NSStackViewVisibilityPriority NSStackViewVisibilityPriorityMustHold = 1000;
static const NSStackViewVisibilityPriority NSStackViewVisibilityPriorityDetachOnlyIfNecessary = 900;
static const NSStackViewVisibilityPriority NSStackViewVisibilityPriorityNotVisible = 0;

static const CGFloat NSStackViewSpacingUseDefault = FLT_MAX;

// Frame-based: there is no constraint solver, so the stack view sets its
// views' frames itself whenever its contents, settings or size change.
@interface NSStackView : NSView {
    id<NSStackViewDelegate> _delegate;
    NSUserInterfaceLayoutOrientation _orientation;
    NSLayoutAttribute _alignment;
    NSStackViewDistribution _distribution;
    CGFloat _spacing;
    NSEdgeInsets _edgeInsets;
    BOOL _detachesHiddenViews;
    BOOL _changingViews;
    NSMutableArray *_entries;
}

+ (instancetype) stackViewWithViews: (NSArray *) views;

@property(assign) id<NSStackViewDelegate> delegate;
@property NSUserInterfaceLayoutOrientation orientation;
@property NSLayoutAttribute alignment;
@property NSStackViewDistribution distribution;
@property CGFloat spacing;
@property NSEdgeInsets edgeInsets;
@property BOOL detachesHiddenViews;
@property(readonly, copy) NSArray *views;
@property(readonly, copy) NSArray *arrangedSubviews;
@property(readonly, copy) NSArray *detachedViews;

- (void) addView: (NSView *) view inGravity: (NSStackViewGravity) gravity;
- (void) insertView: (NSView *) view
            atIndex: (NSUInteger) index
          inGravity: (NSStackViewGravity) gravity;
- (void) removeView: (NSView *) view;
- (NSArray *) viewsInGravity: (NSStackViewGravity) gravity;
- (void) setViews: (NSArray *) views inGravity: (NSStackViewGravity) gravity;

- (void) addArrangedSubview: (NSView *) view;
- (void) insertArrangedSubview: (NSView *) view atIndex: (NSInteger) index;
- (void) removeArrangedSubview: (NSView *) view;

- (void) setCustomSpacing: (CGFloat) spacing afterView: (NSView *) view;
- (CGFloat) customSpacingAfterView: (NSView *) view;

- (void) setVisibilityPriority: (NSStackViewVisibilityPriority) priority
                       forView: (NSView *) view;
- (NSStackViewVisibilityPriority) visibilityPriorityForView: (NSView *) view;

@end

@protocol NSStackViewDelegate <NSObject>
@optional
- (void) stackView: (NSStackView *) stackView willDetachViews: (NSArray *) views;
- (void) stackView: (NSStackView *) stackView didReattachViews: (NSArray *) views;
@end
