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

#import <Foundation/Foundation.h>
#import <QuartzCore/CAConstraintLayoutManager.h>
#import "CACoding.h"

static NSString *const CAConstraintSuperlayerName = @"superlayer";

@implementation CAConstraint

+ (instancetype) constraintWithAttribute: (CAConstraintAttribute) attribute
                              relativeTo: (NSString *) sourceName
                               attribute: (CAConstraintAttribute) sourceAttribute
                                   scale: (CGFloat) scale
                                  offset: (CGFloat) offset
{
    return [[[self alloc] initWithAttribute: attribute
                                 relativeTo: sourceName
                                  attribute: sourceAttribute
                                      scale: scale
                                     offset: offset] autorelease];
}

+ (instancetype) constraintWithAttribute: (CAConstraintAttribute) attribute
                              relativeTo: (NSString *) sourceName
                               attribute: (CAConstraintAttribute) sourceAttribute
                                  offset: (CGFloat) offset
{
    return [self constraintWithAttribute: attribute
                              relativeTo: sourceName
                               attribute: sourceAttribute
                                   scale: 1
                                  offset: offset];
}

+ (instancetype) constraintWithAttribute: (CAConstraintAttribute) attribute
                              relativeTo: (NSString *) sourceName
                               attribute: (CAConstraintAttribute) sourceAttribute
{
    return [self constraintWithAttribute: attribute
                              relativeTo: sourceName
                               attribute: sourceAttribute
                                   scale: 1
                                  offset: 0];
}

static BOOL isValidAttribute(CAConstraintAttribute attribute) {
    return attribute >= kCAConstraintMinX && attribute <= kCAConstraintHeight;
}

- (instancetype) initWithAttribute: (CAConstraintAttribute) attribute
                        relativeTo: (NSString *) sourceName
                         attribute: (CAConstraintAttribute) sourceAttribute
                             scale: (CGFloat) scale
                            offset: (CGFloat) offset
{
    if (!isValidAttribute(attribute) || !isValidAttribute(sourceAttribute)) {
        [self release];
        [NSException raise: NSInvalidArgumentException
                    format: @"Invalid CAConstraintAttribute %d or %d",
                            attribute, sourceAttribute];
    }
    if (sourceName == nil) {
        [self release];
        [NSException raise: NSInvalidArgumentException
                    format: @"CAConstraint needs a source layer name"];
    }
    if ((self = [super init])) {
        _attribute = attribute;
        _sourceName = [sourceName copy];
        _sourceAttribute = sourceAttribute;
        _scale = scale;
        _offset = offset;
    }
    return self;
}

+ (BOOL) supportsSecureCoding {
    return YES;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    CARequireKeyedCoder(coder);
    [coder encodeInt: _attribute forKey: @"attribute"];
    [coder encodeObject: _sourceName forKey: @"sourceName"];
    [coder encodeInt: _sourceAttribute forKey: @"sourceAttribute"];
    [coder encodeDouble: _scale forKey: @"scale"];
    [coder encodeDouble: _offset forKey: @"offset"];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    CARequireKeyedCoder(coder);
    CAConstraintAttribute attribute = [coder decodeIntForKey: @"attribute"];
    CAConstraintAttribute sourceAttribute = [coder decodeIntForKey: @"sourceAttribute"];
    NSString *sourceName = [coder decodeObjectOfClass: [NSString class] forKey: @"sourceName"];
    if (!isValidAttribute(attribute) || !isValidAttribute(sourceAttribute) || sourceName == nil) {
        [self release];
        [NSException raise: NSInvalidUnarchiveOperationException
                    format: @"Archived CAConstraint has an invalid attribute or no source name"];
    }
    return [self initWithAttribute: attribute
                        relativeTo: sourceName
                         attribute: sourceAttribute
                             scale: [coder decodeDoubleForKey: @"scale"]
                            offset: [coder decodeDoubleForKey: @"offset"]];
}

- (void) dealloc {
    [_sourceName release];
    [super dealloc];
}

- (CAConstraintAttribute) attribute {
    return _attribute;
}

- (NSString *) sourceName {
    return _sourceName;
}

- (CAConstraintAttribute) sourceAttribute {
    return _sourceAttribute;
}

- (CGFloat) scale {
    return _scale;
}

- (CGFloat) offset {
    return _offset;
}

@end

@implementation CALayer (CAConstraintLayoutManager)

- (NSArray *) constraints {
    return _constraints;
}

- (void) setConstraints: (NSArray *) value {
    value = [value copy];
    [_constraints release];
    _constraints = value;
    [_superlayer setNeedsLayout];
}

- (void) addConstraint: (CAConstraint *) constraint {
    NSArray *constraints = _constraints ? [_constraints arrayByAddingObject: constraint]
                                        : [NSArray arrayWithObject: constraint];
    [self setConstraints: constraints];
}

@end

static CGFloat attributeValue(CGRect rect, CAConstraintAttribute attribute) {
    switch (attribute) {
    case kCAConstraintMinX:
        return CGRectGetMinX(rect);
    case kCAConstraintMidX:
        return CGRectGetMidX(rect);
    case kCAConstraintMaxX:
        return CGRectGetMaxX(rect);
    case kCAConstraintWidth:
        return CGRectGetWidth(rect);
    case kCAConstraintMinY:
        return CGRectGetMinY(rect);
    case kCAConstraintMidY:
        return CGRectGetMidY(rect);
    case kCAConstraintMaxY:
        return CGRectGetMaxY(rect);
    case kCAConstraintHeight:
        return CGRectGetHeight(rect);
    }
    return 0;
}

enum { AxisMin, AxisMid, AxisMax, AxisSize };

// Resolves one axis from its min, mid, max and size values; with a single
// edge value the current size is kept, as the CAConstraint documentation says.
static void resolveAxis(const BOOL has[4], const CGFloat value[4], CGFloat *origin, CGFloat *size) {
    if (has[AxisSize])
        *size = value[AxisSize];
    else if (has[AxisMin] && has[AxisMax])
        *size = value[AxisMax] - value[AxisMin];
    else if (has[AxisMin] && has[AxisMid])
        *size = 2 * (value[AxisMid] - value[AxisMin]);
    else if (has[AxisMid] && has[AxisMax])
        *size = 2 * (value[AxisMax] - value[AxisMid]);

    if (has[AxisMin])
        *origin = value[AxisMin];
    else if (has[AxisMid])
        *origin = value[AxisMid] - *size / 2;
    else if (has[AxisMax])
        *origin = value[AxisMax] - *size;
}

enum { Unvisited, InProgress, Done };

@implementation CAConstraintLayoutManager

+ (instancetype) layoutManager {
    return [[[self alloc] init] autorelease];
}

// The manager has no state of its own.
+ (BOOL) supportsSecureCoding {
    return YES;
}

- (void) encodeWithCoder: (NSCoder *) coder {
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    return [self init];
}

static void layoutSublayer(CALayer *layer, NSArray *sublayers, NSDictionary *byName,
                           unsigned char *state, NSUInteger index)
{
    if (state[index] != Unvisited)
        return;
    state[index] = InProgress;

    CALayer *sublayer = [sublayers objectAtIndex: index];
    CGRect frame = [sublayer frame];
    BOOL has[8] = {NO};
    CGFloat value[8];

    for (CAConstraint *constraint in [sublayer constraints]) {
        NSString *sourceName = [constraint sourceName];
        CGRect source;

        if ([sourceName isEqualToString: CAConstraintSuperlayerName]) {
            source = [layer bounds];
        } else {
            NSNumber *sourceIndex = [byName objectForKey: sourceName];
            if (sourceIndex == nil)
                continue;
            // A layer that is still being resolved is part of a cycle; the
            // documentation leaves that undefined, so its current frame is used.
            layoutSublayer(layer, sublayers, byName, state, [sourceIndex unsignedIntegerValue]);
            source = [[sublayers objectAtIndex: [sourceIndex unsignedIntegerValue]] frame];
        }

        CAConstraintAttribute attribute = [constraint attribute];
        has[attribute] = YES;
        value[attribute] = attributeValue(source, [constraint sourceAttribute]) *
                                   [constraint scale] +
                           [constraint offset];
    }

    resolveAxis(has, value, &frame.origin.x, &frame.size.width);
    resolveAxis(has + kCAConstraintMinY, value + kCAConstraintMinY, &frame.origin.y,
                &frame.size.height);
    if (!CGRectEqualToRect(frame, [sublayer frame]))
        [sublayer setFrame: frame];

    state[index] = Done;
}

- (void) layoutSublayersOfLayer: (CALayer *) layer {
    NSArray *sublayers = [[layer sublayers] copy];
    NSUInteger count = [sublayers count];
    NSMutableDictionary *byName = [[NSMutableDictionary alloc] init];

    for (NSUInteger i = count; i > 0; i--) {
        NSString *name = [[sublayers objectAtIndex: i - 1] name];
        if (name != nil)
            [byName setObject: [NSNumber numberWithUnsignedInteger: i - 1] forKey: name];
    }

    unsigned char *state = calloc(count ? count : 1, 1);
    for (NSUInteger i = 0; i < count; i++)
        layoutSublayer(layer, sublayers, byName, state, i);

    free(state);
    [byName release];
    [sublayers release];
}

@end
