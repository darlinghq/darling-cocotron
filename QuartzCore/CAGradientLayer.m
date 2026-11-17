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

#import <QuartzCore/CAGradientLayer.h>

NSString *const kCAGradientLayerAxial = @"axial";
NSString *const kCAGradientLayerRadial = @"radial";
NSString *const kCAGradientLayerConic = @"conic";

@implementation CAGradientLayer

- (void) _setGradientDefaults {
    _startPoint = CGPointMake(0.5, 0);
    _endPoint = CGPointMake(0.5, 1);
    _type = [kCAGradientLayerAxial copy];
}

- init {
    self = [super init];
    if (self != nil)
        [self _setGradientDefaults];
    return self;
}

- initWithLayer: (id) layer {
    self = [super initWithLayer: layer];
    if (self != nil) {
        [self _setGradientDefaults];
        if ([layer isKindOfClass: [CAGradientLayer class]]) {
            CAGradientLayer *other = layer;

            _colors = [other->_colors copy];
            _locations = [other->_locations copy];
            _startPoint = other->_startPoint;
            _endPoint = other->_endPoint;
            [_type release];
            _type = [other->_type copy];
        }
    }
    return self;
}

- (void) dealloc {
    [_colors release];
    [_locations release];
    [_type release];
    [super dealloc];
}

- (NSArray *) colors {
    return _colors;
}

- (void) setColors: (NSArray *) colors {
    colors = [colors copy];
    [_colors release];
    _colors = colors;
    [self setNeedsDisplay];
}

- (NSArray *) locations {
    return _locations;
}

- (void) setLocations: (NSArray *) locations {
    locations = [locations copy];
    [_locations release];
    _locations = locations;
    [self setNeedsDisplay];
}

- (CGPoint) startPoint {
    return _startPoint;
}

- (void) setStartPoint: (CGPoint) point {
    _startPoint = point;
    [self setNeedsDisplay];
}

- (CGPoint) endPoint {
    return _endPoint;
}

- (void) setEndPoint: (CGPoint) point {
    _endPoint = point;
    [self setNeedsDisplay];
}

- (CAGradientLayerType) type {
    return _type;
}

- (void) setType: (CAGradientLayerType) type {
    type = [type copy];
    [_type release];
    _type = type;
    [self setNeedsDisplay];
}

- (BOOL) _drawsOwnContent {
    return YES;
}

// Only the axial type is drawn: the radial and conic types draw nothing.
- (void) drawInContext: (CGContextRef) context {
    [super drawInContext: context];

    NSUInteger count = [_colors count];

    if (count == 0 || ![_type isEqualToString: kCAGradientLayerAxial])
        return;

    CGRect bounds = [self bounds];
    CGFloat locations[count];
    BOOL explicitLocations = [_locations count] == count;

    for (NSUInteger i = 0; i < count; i++) {
        if (explicitLocations)
            locations[i] = [[_locations objectAtIndex: i] doubleValue];
        else
            locations[i] = count == 1 ? 0 : (CGFloat) i / (count - 1);
    }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (CFArrayRef) _colors, locations);

    CGColorSpaceRelease(space);
    if (gradient == NULL)
        return;

    CGPoint start = CGPointMake(bounds.origin.x + _startPoint.x * bounds.size.width,
                                bounds.origin.y + _startPoint.y * bounds.size.height);
    CGPoint end = CGPointMake(bounds.origin.x + _endPoint.x * bounds.size.width,
                              bounds.origin.y + _endPoint.y * bounds.size.height);

    // The area before the start point and after the end point takes the first and last color.
    CGContextSaveGState(context);
    CGContextClipToRect(context, bounds);
    CGContextDrawLinearGradient(context, gradient, start, end,
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
}

@end
