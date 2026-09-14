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

- init {
    self = [super init];
    if (self != nil) {
        _fillColor = CGColorCreateGenericRGB(0, 0, 0, 1);
        _fillRule = [kCAFillRuleNonZero copy];
        _strokeEnd = 1;
        _lineWidth = 1;
        _miterLimit = 10;
        _lineCap = [kCALineCapButt copy];
        _lineJoin = [kCALineJoinMiter copy];
        _needsDisplay = YES;
    }
    return self;
}

- (void) dealloc {
    if (_path)
        CGPathRelease(_path);
    if (_fillColor)
        CGColorRelease(_fillColor);
    if (_strokeColor)
        CGColorRelease(_strokeColor);
    [_fillRule release];
    [_lineCap release];
    [_lineJoin release];
    [_lineDashPattern release];
    [super dealloc];
}

- (CGPathRef) path {
    return _path;
}

- (void) setPath: (CGPathRef) path {
    CGPathRef copy = path ? CGPathCreateCopy(path) : NULL;
    if (_path)
        CGPathRelease(_path);
    _path = copy;
    [self setNeedsDisplay];
}

- (CGColorRef) fillColor {
    return _fillColor;
}

- (void) setFillColor: (CGColorRef) color {
    replaceColor(&_fillColor, color);
    [self setNeedsDisplay];
}

- (NSString *) fillRule {
    return _fillRule;
}

- (void) setFillRule: (NSString *) rule {
    rule = [rule copy];
    [_fillRule release];
    _fillRule = rule;
    [self setNeedsDisplay];
}

- (CGColorRef) strokeColor {
    return _strokeColor;
}

- (void) setStrokeColor: (CGColorRef) color {
    replaceColor(&_strokeColor, color);
    [self setNeedsDisplay];
}

- (CGFloat) strokeStart {
    return _strokeStart;
}

- (void) setStrokeStart: (CGFloat) value {
    _strokeStart = value;
    [self setNeedsDisplay];
}

- (CGFloat) strokeEnd {
    return _strokeEnd;
}

- (void) setStrokeEnd: (CGFloat) value {
    _strokeEnd = value;
    [self setNeedsDisplay];
}

- (CGFloat) lineWidth {
    return _lineWidth;
}

- (void) setLineWidth: (CGFloat) value {
    _lineWidth = value;
    [self setNeedsDisplay];
}

- (CGFloat) miterLimit {
    return _miterLimit;
}

- (void) setMiterLimit: (CGFloat) value {
    _miterLimit = value;
    [self setNeedsDisplay];
}

- (NSString *) lineCap {
    return _lineCap;
}

- (void) setLineCap: (NSString *) cap {
    cap = [cap copy];
    [_lineCap release];
    _lineCap = cap;
    [self setNeedsDisplay];
}

- (NSString *) lineJoin {
    return _lineJoin;
}

- (void) setLineJoin: (NSString *) join {
    join = [join copy];
    [_lineJoin release];
    _lineJoin = join;
    [self setNeedsDisplay];
}

- (CGFloat) lineDashPhase {
    return _lineDashPhase;
}

- (void) setLineDashPhase: (CGFloat) value {
    _lineDashPhase = value;
    [self setNeedsDisplay];
}

- (NSArray *) lineDashPattern {
    return _lineDashPattern;
}

- (void) setLineDashPattern: (NSArray *) pattern {
    pattern = [pattern copy];
    [_lineDashPattern release];
    _lineDashPattern = pattern;
    [self setNeedsDisplay];
}

// The path is in layer coordinates. Fill first, then stroke on top.
- (void) drawInContext: (CGContextRef) context {
    [super drawInContext: context];

    if (_path == NULL)
        return;

    CGContextSaveGState(context);

    if (_fillColor != NULL) {
        CGContextAddPath(context, _path);
        CGContextSetFillColorWithColor(context, _fillColor);
        if ([_fillRule isEqualToString: kCAFillRuleEvenOdd])
            CGContextEOFillPath(context);
        else
            CGContextFillPath(context);
    }

    // Trimming to strokeStart/strokeEnd isn't implemented, but an empty range
    // (e.g. the 0/0 start of a "draw the outline" animation) strokes nothing.
    if (_strokeColor != NULL && _lineWidth > 0 &&
        MIN(_strokeEnd, 1) > MAX(_strokeStart, 0)) {
        CGLineCap cap = kCGLineCapButt;
        if ([_lineCap isEqualToString: kCALineCapRound])
            cap = kCGLineCapRound;
        else if ([_lineCap isEqualToString: kCALineCapSquare])
            cap = kCGLineCapSquare;

        CGLineJoin join = kCGLineJoinMiter;
        if ([_lineJoin isEqualToString: kCALineJoinRound])
            join = kCGLineJoinRound;
        else if ([_lineJoin isEqualToString: kCALineJoinBevel])
            join = kCGLineJoinBevel;

        CGContextAddPath(context, _path);
        CGContextSetStrokeColorWithColor(context, _strokeColor);
        CGContextSetLineWidth(context, _lineWidth);
        CGContextSetMiterLimit(context, _miterLimit);
        CGContextSetLineCap(context, cap);
        CGContextSetLineJoin(context, join);

        NSUInteger count = [_lineDashPattern count];
        if (count > 0) {
            CGFloat lengths[count];
            for (NSUInteger i = 0; i < count; i++)
                lengths[i] = [[_lineDashPattern objectAtIndex: i] doubleValue];
            CGContextSetLineDash(context, _lineDashPhase, lengths, count);
        }

        CGContextStrokePath(context);
    }

    CGContextRestoreGState(context);
}

@end
