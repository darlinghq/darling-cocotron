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

#import <QuartzCore/CAShapeLayer.h>
#import "CAKeyedCoding.h"
#import "CALayerInternal.h"

NSString *const kCAFillRuleNonZero = @"non-zero";
NSString *const kCAFillRuleEvenOdd = @"even-odd";
NSString *const kCALineJoinMiter = @"miter";
NSString *const kCALineJoinRound = @"round";
NSString *const kCALineJoinBevel = @"bevel";
NSString *const kCALineCapButt = @"butt";
NSString *const kCALineCapRound = @"round";
NSString *const kCALineCapSquare = @"square";

static void replaceColor(CGColorRef *slot, CGColorRef value) {
    if (*slot == value)
        return;
    if (value)
        CGColorRetain(value);
    if (*slot)
        CGColorRelease(*slot);
    *slot = value;
}

@implementation CAShapeLayer

- (void) _setShapeDefaults {
    NS_EXTRA(CAShapeLayer, self)->_fillColor = CGColorCreateGenericRGB(0, 0, 0, 1);
    NS_EXTRA(CAShapeLayer, self)->_fillRule = [kCAFillRuleNonZero copy];
    NS_EXTRA(CAShapeLayer, self)->_strokeEnd = 1;
    NS_EXTRA(CAShapeLayer, self)->_lineWidth = 1;
    NS_EXTRA(CAShapeLayer, self)->_miterLimit = 10;
    NS_EXTRA(CAShapeLayer, self)->_lineCap = [kCALineCapButt copy];
    NS_EXTRA(CAShapeLayer, self)->_lineJoin = [kCALineJoinMiter copy];
    NS_EXTRA(CALayer, self)->_needsDisplay = YES;
}

- init {
    self = [super init];
    if (self != nil)
        [self _setShapeDefaults];
    return self;
}

// Keys are written only when they differ from the defaults.
- (void) _encodeAttributes: (CAArchiveWriter *) w {
    [super _encodeAttributes: w];
    if (NS_EXTRA(CAShapeLayer, self)->_path != NULL)
        [w encodePath: NS_EXTRA(CAShapeLayer, self)->_path forKey: @"path"];
    if (NS_EXTRA(CAShapeLayer, self)->_fillColor != NULL && !(CGColorGetNumberOfComponents(NS_EXTRA(CAShapeLayer, self)->_fillColor) == 4 &&
                                CGColorGetComponents(NS_EXTRA(CAShapeLayer, self)->_fillColor)[0] == 0 &&
                                CGColorGetComponents(NS_EXTRA(CAShapeLayer, self)->_fillColor)[1] == 0 &&
                                CGColorGetComponents(NS_EXTRA(CAShapeLayer, self)->_fillColor)[2] == 0 &&
                                CGColorGetComponents(NS_EXTRA(CAShapeLayer, self)->_fillColor)[3] == 1))
        [w encodeColor: NS_EXTRA(CAShapeLayer, self)->_fillColor forKey: @"fillColor"];
    if (![NS_EXTRA(CAShapeLayer, self)->_fillRule isEqualToString: kCAFillRuleNonZero])
        [w encodeObject: NS_EXTRA(CAShapeLayer, self)->_fillRule forKey: @"fillRule"];
    if (NS_EXTRA(CAShapeLayer, self)->_strokeColor != NULL)
        [w encodeColor: NS_EXTRA(CAShapeLayer, self)->_strokeColor forKey: @"strokeColor"];
    if (NS_EXTRA(CAShapeLayer, self)->_strokeStart != 0)
        [w encodeDouble: NS_EXTRA(CAShapeLayer, self)->_strokeStart forKey: @"strokeStart"];
    if (NS_EXTRA(CAShapeLayer, self)->_strokeEnd != 1)
        [w encodeDouble: NS_EXTRA(CAShapeLayer, self)->_strokeEnd forKey: @"strokeEnd"];
    if (NS_EXTRA(CAShapeLayer, self)->_lineWidth != 1)
        [w encodeDouble: NS_EXTRA(CAShapeLayer, self)->_lineWidth forKey: @"lineWidth"];
    if (NS_EXTRA(CAShapeLayer, self)->_miterLimit != 10)
        [w encodeDouble: NS_EXTRA(CAShapeLayer, self)->_miterLimit forKey: @"miterLimit"];
    if (![NS_EXTRA(CAShapeLayer, self)->_lineCap isEqualToString: kCALineCapButt])
        [w encodeObject: NS_EXTRA(CAShapeLayer, self)->_lineCap forKey: @"lineCap"];
    if (![NS_EXTRA(CAShapeLayer, self)->_lineJoin isEqualToString: kCALineJoinMiter])
        [w encodeObject: NS_EXTRA(CAShapeLayer, self)->_lineJoin forKey: @"lineJoin"];
    if (NS_EXTRA(CAShapeLayer, self)->_lineDashPhase != 0)
        [w encodeDouble: NS_EXTRA(CAShapeLayer, self)->_lineDashPhase forKey: @"lineDashPhase"];
    if (NS_EXTRA(CAShapeLayer, self)->_lineDashPattern != nil)
        [w encodeArray: NS_EXTRA(CAShapeLayer, self)->_lineDashPattern forKey: @"lineDashPattern"];
}

- (void) _decodeAttributes: (CAArchiveReader *) r {
    [self _setShapeDefaults];
    [super _decodeAttributes: r];
    CGPathRef path = [r copyPathForKey: @"path"];
    if (path != NULL) {
        [self setPath: path];
        CGPathRelease(path);
    }
    CGColorRef color = [r copyColorForKey: @"fillColor"];
    if (color != NULL) {
        [self setFillColor: color];
        CGColorRelease(color);
    }
    color = [r copyColorForKey: @"strokeColor"];
    if (color != NULL) {
        [self setStrokeColor: color];
        CGColorRelease(color);
    }
    NSString *string = [r decodeStringForKey: @"fillRule"];
    if (string != nil)
        [self setFillRule: string];
    string = [r decodeStringForKey: @"lineCap"];
    if (string != nil)
        [self setLineCap: string];
    string = [r decodeStringForKey: @"lineJoin"];
    if (string != nil)
        [self setLineJoin: string];
    double real;
    if ([r decodeDouble: &real forKey: @"strokeStart"])
        NS_EXTRA(CAShapeLayer, self)->_strokeStart = real;
    if ([r decodeDouble: &real forKey: @"strokeEnd"])
        NS_EXTRA(CAShapeLayer, self)->_strokeEnd = real;
    if ([r decodeDouble: &real forKey: @"lineWidth"])
        NS_EXTRA(CAShapeLayer, self)->_lineWidth = real;
    if ([r decodeDouble: &real forKey: @"miterLimit"])
        NS_EXTRA(CAShapeLayer, self)->_miterLimit = real;
    if ([r decodeDouble: &real forKey: @"lineDashPhase"])
        NS_EXTRA(CAShapeLayer, self)->_lineDashPhase = real;
    NSArray *pattern = [r decodeArrayForKey: @"lineDashPattern"];
    if (pattern != nil)
        [self setLineDashPattern: pattern];
}

- initWithLayer: (id) layer {
    self = [super initWithLayer: layer];
    if (self != nil)
        [self _setShapeDefaults];
    return self;
}

- (void) dealloc {
    if (NS_EXTRA(CAShapeLayer, self)->_path)
        CGPathRelease(NS_EXTRA(CAShapeLayer, self)->_path);
    if (NS_EXTRA(CAShapeLayer, self)->_fillColor)
        CGColorRelease(NS_EXTRA(CAShapeLayer, self)->_fillColor);
    if (NS_EXTRA(CAShapeLayer, self)->_strokeColor)
        CGColorRelease(NS_EXTRA(CAShapeLayer, self)->_strokeColor);
    [NS_EXTRA(CAShapeLayer, self)->_fillRule release];
    [NS_EXTRA(CAShapeLayer, self)->_lineCap release];
    [NS_EXTRA(CAShapeLayer, self)->_lineJoin release];
    [NS_EXTRA(CAShapeLayer, self)->_lineDashPattern release];
    [super dealloc];
}

- (CGPathRef) path {
    return NS_EXTRA(CAShapeLayer, self)->_path;
}

- (void) setPath: (CGPathRef) path {
    CGPathRef copy = path ? CGPathCreateCopy(path) : NULL;
    if (NS_EXTRA(CAShapeLayer, self)->_path)
        CGPathRelease(NS_EXTRA(CAShapeLayer, self)->_path);
    NS_EXTRA(CAShapeLayer, self)->_path = copy;
    [self setNeedsDisplay];
}

- (CGColorRef) fillColor {
    return NS_EXTRA(CAShapeLayer, self)->_fillColor;
}

- (void) setFillColor: (CGColorRef) color {
    replaceColor(&NS_EXTRA(CAShapeLayer, self)->_fillColor, color);
    [self setNeedsDisplay];
}

- (NSString *) fillRule {
    return NS_EXTRA(CAShapeLayer, self)->_fillRule;
}

- (void) setFillRule: (NSString *) rule {
    rule = [rule copy];
    [NS_EXTRA(CAShapeLayer, self)->_fillRule release];
    NS_EXTRA(CAShapeLayer, self)->_fillRule = rule;
    [self setNeedsDisplay];
}

- (CGColorRef) strokeColor {
    return NS_EXTRA(CAShapeLayer, self)->_strokeColor;
}

- (void) setStrokeColor: (CGColorRef) color {
    replaceColor(&NS_EXTRA(CAShapeLayer, self)->_strokeColor, color);
    [self setNeedsDisplay];
}

- (CGFloat) strokeStart {
    return NS_EXTRA(CAShapeLayer, self)->_strokeStart;
}

- (void) setStrokeStart: (CGFloat) value {
    NS_EXTRA(CAShapeLayer, self)->_strokeStart = value;
    [self setNeedsDisplay];
}

- (CGFloat) strokeEnd {
    return NS_EXTRA(CAShapeLayer, self)->_strokeEnd;
}

- (void) setStrokeEnd: (CGFloat) value {
    NS_EXTRA(CAShapeLayer, self)->_strokeEnd = value;
    [self setNeedsDisplay];
}

- (CGFloat) lineWidth {
    return NS_EXTRA(CAShapeLayer, self)->_lineWidth;
}

- (void) setLineWidth: (CGFloat) value {
    NS_EXTRA(CAShapeLayer, self)->_lineWidth = value;
    [self setNeedsDisplay];
}

- (CGFloat) miterLimit {
    return NS_EXTRA(CAShapeLayer, self)->_miterLimit;
}

- (void) setMiterLimit: (CGFloat) value {
    NS_EXTRA(CAShapeLayer, self)->_miterLimit = value;
    [self setNeedsDisplay];
}

- (NSString *) lineCap {
    return NS_EXTRA(CAShapeLayer, self)->_lineCap;
}

- (void) setLineCap: (NSString *) cap {
    cap = [cap copy];
    [NS_EXTRA(CAShapeLayer, self)->_lineCap release];
    NS_EXTRA(CAShapeLayer, self)->_lineCap = cap;
    [self setNeedsDisplay];
}

- (NSString *) lineJoin {
    return NS_EXTRA(CAShapeLayer, self)->_lineJoin;
}

- (void) setLineJoin: (NSString *) join {
    join = [join copy];
    [NS_EXTRA(CAShapeLayer, self)->_lineJoin release];
    NS_EXTRA(CAShapeLayer, self)->_lineJoin = join;
    [self setNeedsDisplay];
}

- (CGFloat) lineDashPhase {
    return NS_EXTRA(CAShapeLayer, self)->_lineDashPhase;
}

- (void) setLineDashPhase: (CGFloat) value {
    NS_EXTRA(CAShapeLayer, self)->_lineDashPhase = value;
    [self setNeedsDisplay];
}

- (NSArray *) lineDashPattern {
    return NS_EXTRA(CAShapeLayer, self)->_lineDashPattern;
}

- (void) setLineDashPattern: (NSArray *) pattern {
    pattern = [pattern copy];
    [NS_EXTRA(CAShapeLayer, self)->_lineDashPattern release];
    NS_EXTRA(CAShapeLayer, self)->_lineDashPattern = pattern;
    [self setNeedsDisplay];
}

- (BOOL) _drawsOwnContent {
    return YES;
}

// The path is in layer coordinates. Fill first, then stroke on top.
- (void) drawInContext: (CGContextRef) context {
    [super drawInContext: context];

    if (NS_EXTRA(CAShapeLayer, self)->_path == NULL)
        return;

    CGContextSaveGState(context);

    if (NS_EXTRA(CAShapeLayer, self)->_fillColor != NULL) {
        CGContextAddPath(context, NS_EXTRA(CAShapeLayer, self)->_path);
        CGContextSetFillColorWithColor(context, NS_EXTRA(CAShapeLayer, self)->_fillColor);
        if ([NS_EXTRA(CAShapeLayer, self)->_fillRule isEqualToString: kCAFillRuleEvenOdd])
            CGContextEOFillPath(context);
        else
            CGContextFillPath(context);
    }

    // Trimming to strokeStart/strokeEnd isn't implemented, but an empty range
    // (e.g. the 0/0 start of a "draw the outline" animation) strokes nothing.
    if (NS_EXTRA(CAShapeLayer, self)->_strokeColor != NULL && NS_EXTRA(CAShapeLayer, self)->_lineWidth > 0 &&
        MIN(NS_EXTRA(CAShapeLayer, self)->_strokeEnd, 1) > MAX(NS_EXTRA(CAShapeLayer, self)->_strokeStart, 0)) {
        CGLineCap cap = kCGLineCapButt;
        if ([NS_EXTRA(CAShapeLayer, self)->_lineCap isEqualToString: kCALineCapRound])
            cap = kCGLineCapRound;
        else if ([NS_EXTRA(CAShapeLayer, self)->_lineCap isEqualToString: kCALineCapSquare])
            cap = kCGLineCapSquare;

        CGLineJoin join = kCGLineJoinMiter;
        if ([NS_EXTRA(CAShapeLayer, self)->_lineJoin isEqualToString: kCALineJoinRound])
            join = kCGLineJoinRound;
        else if ([NS_EXTRA(CAShapeLayer, self)->_lineJoin isEqualToString: kCALineJoinBevel])
            join = kCGLineJoinBevel;

        CGContextAddPath(context, NS_EXTRA(CAShapeLayer, self)->_path);
        CGContextSetStrokeColorWithColor(context, NS_EXTRA(CAShapeLayer, self)->_strokeColor);
        CGContextSetLineWidth(context, NS_EXTRA(CAShapeLayer, self)->_lineWidth);
        CGContextSetMiterLimit(context, NS_EXTRA(CAShapeLayer, self)->_miterLimit);
        CGContextSetLineCap(context, cap);
        CGContextSetLineJoin(context, join);

        NSUInteger count = [NS_EXTRA(CAShapeLayer, self)->_lineDashPattern count];
        if (count > 0) {
            CGFloat lengths[count];
            for (NSUInteger i = 0; i < count; i++)
                lengths[i] = [[NS_EXTRA(CAShapeLayer, self)->_lineDashPattern objectAtIndex: i] doubleValue];
            CGContextSetLineDash(context, NS_EXTRA(CAShapeLayer, self)->_lineDashPhase, lengths, count);
        }

        CGContextStrokePath(context);
    }

    CGContextRestoreGState(context);
}

@end
