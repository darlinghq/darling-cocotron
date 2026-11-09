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

typedef float NSLayoutPriority;

typedef NS_ENUM(NSInteger, NSLayoutConstraintOrientation) {
	NSLayoutConstraintOrientationHorizontal = 0,
	NSLayoutConstraintOrientationVertical = 1,
};

APPKIT_EXPORT const CGFloat NSViewNoInstrinsicMetric;
APPKIT_EXPORT const CGFloat NSViewNoIntrinsicMetric;

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
