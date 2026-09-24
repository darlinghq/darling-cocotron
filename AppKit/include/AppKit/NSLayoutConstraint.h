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
#import <Foundation/NSString.h>

// Guarded so that a Foundation header declaring the same shared types does not
// conflict: Swift nests them only into a class of their own module.
#if !__NSLAYOUT_PRIORITY_SHARED_SECTION__
#define __NSLAYOUT_PRIORITY_SHARED_SECTION__ 1
typedef float NSLayoutPriority NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSLayoutConstraint.Priority);

static const NSLayoutPriority NSLayoutPriorityRequired NS_SWIFT_NAME(required) = 1000;
static const NSLayoutPriority NSLayoutPriorityDefaultHigh NS_SWIFT_NAME(defaultHigh) = 750;
static const NSLayoutPriority NSLayoutPriorityDefaultLow NS_SWIFT_NAME(defaultLow) = 250;
static const NSLayoutPriority NSLayoutPriorityFittingSizeCompression NS_SWIFT_NAME(fittingSizeCompression) = 50;
#endif

#if !__NSLAYOUT_ORIENTATION_SHARED_SECTION__
#define __NSLAYOUT_ORIENTATION_SHARED_SECTION__ 1
typedef NS_ENUM(NSInteger, NSLayoutConstraintOrientation) {
	NSLayoutConstraintOrientationHorizontal = 0,
	NSLayoutConstraintOrientationVertical = 1,
} NS_SWIFT_NAME(NSLayoutConstraint.Orientation);
#endif

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
