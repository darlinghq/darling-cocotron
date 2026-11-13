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

typedef NSString *CAShapeLayerFillRule NS_TYPED_ENUM;
typedef NSString *CAShapeLayerLineJoin NS_TYPED_ENUM;
typedef NSString *CAShapeLayerLineCap NS_TYPED_ENUM;

CA_EXPORT CAShapeLayerFillRule const kCAFillRuleNonZero NS_SWIFT_NAME(CAShapeLayerFillRule.nonZero);
CA_EXPORT CAShapeLayerFillRule const kCAFillRuleEvenOdd NS_SWIFT_NAME(CAShapeLayerFillRule.evenOdd);
CA_EXPORT CAShapeLayerLineJoin const kCALineJoinMiter NS_SWIFT_NAME(CAShapeLayerLineJoin.miter);
CA_EXPORT CAShapeLayerLineJoin const kCALineJoinRound NS_SWIFT_NAME(CAShapeLayerLineJoin.round);
CA_EXPORT CAShapeLayerLineJoin const kCALineJoinBevel NS_SWIFT_NAME(CAShapeLayerLineJoin.bevel);
CA_EXPORT CAShapeLayerLineCap const kCALineCapButt NS_SWIFT_NAME(CAShapeLayerLineCap.butt);
CA_EXPORT CAShapeLayerLineCap const kCALineCapRound NS_SWIFT_NAME(CAShapeLayerLineCap.round);
CA_EXPORT CAShapeLayerLineCap const kCALineCapSquare NS_SWIFT_NAME(CAShapeLayerLineCap.square);

// Draws a path with an optional fill and stroke into the layer's contents.
@interface CAShapeLayer : CALayer {
    CGPathRef _path;
    CGColorRef _fillColor;
    NSString *_fillRule;
    CGColorRef _strokeColor;
    CGFloat _strokeStart;
    CGFloat _strokeEnd;
    CGFloat _lineWidth;
    CGFloat _miterLimit;
    NSString *_lineCap;
    NSString *_lineJoin;
    CGFloat _lineDashPhase;
    NSArray *_lineDashPattern;
}

@property CGPathRef path;
@property CGColorRef fillColor;     // default opaque black; NULL for no fill
@property(copy) CAShapeLayerFillRule fillRule; // kCAFillRuleNonZero (default) or kCAFillRuleEvenOdd
@property CGColorRef strokeColor;   // default NULL (no stroke)
@property CGFloat strokeStart;
@property CGFloat strokeEnd;
@property CGFloat lineWidth;        // default 1
@property CGFloat miterLimit;       // default 10
@property(copy) CAShapeLayerLineCap lineCap;   // default kCALineCapButt
@property(copy) CAShapeLayerLineJoin lineJoin; // default kCALineJoinMiter
@property CGFloat lineDashPhase;
@property(copy) NSArray *lineDashPattern;

@end
