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

#import <QuartzCore/CALayer.h>
#import <QuartzCore/LegacyIvarLayout.h>

typedef NSString *CAGradientLayerType NS_TYPED_ENUM;

CA_EXPORT CAGradientLayerType const kCAGradientLayerAxial;
CA_EXPORT CAGradientLayerType const kCAGradientLayerRadial;
CA_EXPORT CAGradientLayerType const kCAGradientLayerConic;

// Draws a color gradient into the layer's contents.
#define _NS_SIDE_CAGradientLayer 0, 1,
@interface CAGradientLayer : CALayer {
    NS_EXTRA_IVARS_BEGIN(CAGradientLayer)
        NSArray *_colors;
        NSArray *_locations;
        CGPoint _startPoint;
        CGPoint _endPoint;
        CAGradientLayerType _type;
    NS_SIDE_IVARS_END(CAGradientLayer)
}

@property(copy) NSArray *colors;                 // CGColorRefs; default nil (nothing is drawn)
@property(copy) NSArray<NSNumber *> *locations;  // optional; the colors are evenly spaced when nil
@property CGPoint startPoint;                    // unit coordinates of the layer, default (0.5, 0)
@property CGPoint endPoint;                      // default (0.5, 1)
@property(copy) CAGradientLayerType type;        // kCAGradientLayerAxial (default)

@end
