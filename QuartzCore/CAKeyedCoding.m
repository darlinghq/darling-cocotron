/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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

// The archive layout follows what a keyed archive of a layer looks like on
// macOS, as observed by archiving layers there and reading the property list
// (macOS 26.7.3, tier 2 evidence; probes v316-calayer-archive*.m of the
// vd-upstream notes). Key names are the property names. Values:
//   point, size, rect, transform  -> LKNSValueCodingProxy (kind 0, 1, 2, 3)
//   color                         -> LKCGColorCodingProxy, r g b a (sRGB, floats)
//   sublayers, filters, ...       -> LKNSArrayCodingProxy { array }
//   path                          -> CACGPathCodingProxy { LKCGPathSegments }
//   CGImage contents              -> LKCGImageCodingProxy { data } (PNG)
// and a __CACodingContents array lists the keys that were written. The proxy
// class names and their key names are part of the archive, which is why they
// are reproduced here.

#import "CAKeyedCoding.h"
#import <ImageIO/ImageIO.h>
#import <Onyx2D/O2Image.h>
#import <QuartzCore/CAConstraintLayoutManager.h>
#import <QuartzCore/CALayer.h>

void CAArchiveRequireKeyedCoder(NSCoder *coder) {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"Core Animation layers need a keyed coder, not %@", [coder class]];
}

static NSString *const kContentsKey = @"__CACodingContents";

#pragma mark - Proxy classes

typedef NS_ENUM(int, CAValueKind) {
    CAValueKindPoint = 0,
    CAValueKindSize = 1,
    CAValueKindRect = 2,
    CAValueKindTransform = 3,
};

static NSString *const transformKeys[16] = {
    @"m11", @"m12", @"m13", @"m14", @"m21", @"m22", @"m23", @"m24",
    @"m31", @"m32", @"m33", @"m34", @"m41", @"m42", @"m43", @"m44",
};

@interface LKNSValueCodingProxy : NSObject <NSSecureCoding> {
@public
    int kind;
    double values[16];
}
@end

@implementation LKNSValueCodingProxy
+ (BOOL) supportsSecureCoding { return YES; }

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeInt: kind forKey: @"kind"];
    switch (kind) {
    case CAValueKindPoint:
        [coder encodeDouble: values[0] forKey: @"x"];
        [coder encodeDouble: values[1] forKey: @"y"];
        break;
    case CAValueKindSize:
        [coder encodeDouble: values[0] forKey: @"width"];
        [coder encodeDouble: values[1] forKey: @"height"];
        break;
    case CAValueKindRect:
        [coder encodeDouble: values[0] forKey: @"x"];
        [coder encodeDouble: values[1] forKey: @"y"];
        [coder encodeDouble: values[2] forKey: @"width"];
        [coder encodeDouble: values[3] forKey: @"height"];
        break;
    case CAValueKindTransform:
        for (int i = 0; i < 16; i++)
            [coder encodeDouble: values[i] forKey: transformKeys[i]];
        break;
    }
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self == nil)
        return nil;
    kind = [coder decodeIntForKey: @"kind"];
    switch (kind) {
    case CAValueKindPoint:
        values[0] = [coder decodeDoubleForKey: @"x"];
        values[1] = [coder decodeDoubleForKey: @"y"];
        break;
    case CAValueKindSize:
        values[0] = [coder decodeDoubleForKey: @"width"];
        values[1] = [coder decodeDoubleForKey: @"height"];
        break;
    case CAValueKindRect:
        values[0] = [coder decodeDoubleForKey: @"x"];
        values[1] = [coder decodeDoubleForKey: @"y"];
        values[2] = [coder decodeDoubleForKey: @"width"];
        values[3] = [coder decodeDoubleForKey: @"height"];
        break;
    case CAValueKindTransform:
        for (int i = 0; i < 16; i++)
            values[i] = [coder decodeDoubleForKey: transformKeys[i]];
        break;
    default:
        [self release];
        [NSException raise: NSInvalidUnarchiveOperationException format: @"Unknown value kind %d in a layer archive", kind];
        return nil;
    }
    return self;
}
@end

@interface LKCGColorCodingProxy : NSObject <NSSecureCoding> {
@public
    float r, g, b, a;
}
@end

@implementation LKCGColorCodingProxy
+ (BOOL) supportsSecureCoding { return YES; }
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeFloat: r forKey: @"r"];
    [coder encodeFloat: g forKey: @"g"];
    [coder encodeFloat: b forKey: @"b"];
    [coder encodeFloat: a forKey: @"a"];
}
- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self != nil) {
        r = [coder decodeFloatForKey: @"r"];
        g = [coder decodeFloatForKey: @"g"];
        b = [coder decodeFloatForKey: @"b"];
        a = [coder decodeFloatForKey: @"a"];
    }
    return self;
}
@end

@interface LKNSArrayCodingProxy : NSObject <NSSecureCoding> {
@public
    NSArray *array;
}
@end

// The classes an archived array may hold: layers, constraints, filters and the
// plain values of dash patterns.
static NSSet *arrayElementClasses(void) {
    static NSSet *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *set = [NSMutableSet setWithObjects: [NSArray class], [NSMutableArray class],
                [NSNumber class], [NSString class], [NSNull class], [CALayer class], [CAConstraint class], nil];
        for (NSString *name in @[ @"CIFilter", @"CAFilter" ]) {
            Class filter = NSClassFromString(name);
            if (filter != Nil)
                [set addObject: filter];
        }
        classes = [set copy];
    });
    return classes;
}

@implementation LKNSArrayCodingProxy
+ (BOOL) supportsSecureCoding { return YES; }
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: array forKey: @"array"];
}
- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self != nil) {
        array = [[coder decodeObjectOfClasses: arrayElementClasses() forKey: @"array"] retain];
    }
    return self;
}
- (void) dealloc {
    [array release];
    [super dealloc];
}
@end

// One path element: LKCGPathType is the CGPathElementType; the points follow
// as LKCGPathPoint<n>_x and _y.
@interface CACGPathCodingSegment : NSObject <NSSecureCoding> {
@public
    int type;
    CGPoint points[3];
}
@end

static int pointsOfElement(int type) {
    switch (type) {
    case kCGPathElementMoveToPoint:
    case kCGPathElementAddLineToPoint:
        return 1;
    case kCGPathElementAddQuadCurveToPoint:
        return 2;
    case kCGPathElementAddCurveToPoint:
        return 3;
    default:
        return 0;
    }
}

@implementation CACGPathCodingSegment
+ (BOOL) supportsSecureCoding { return YES; }
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeInt: type forKey: @"LKCGPathType"];
    for (int i = 0; i < pointsOfElement(type); i++) {
        [coder encodeDouble: points[i].x forKey: [NSString stringWithFormat: @"LKCGPathPoint%d_x", i]];
        [coder encodeDouble: points[i].y forKey: [NSString stringWithFormat: @"LKCGPathPoint%d_y", i]];
    }
}
- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self == nil)
        return nil;
    type = [coder decodeIntForKey: @"LKCGPathType"];
    if (type < kCGPathElementMoveToPoint || type > kCGPathElementCloseSubpath) {
        [self release];
        [NSException raise: NSInvalidUnarchiveOperationException format: @"Bad path element type %d in a layer archive", type];
        return nil;
    }
    for (int i = 0; i < pointsOfElement(type); i++) {
        points[i].x = [coder decodeDoubleForKey: [NSString stringWithFormat: @"LKCGPathPoint%d_x", i]];
        points[i].y = [coder decodeDoubleForKey: [NSString stringWithFormat: @"LKCGPathPoint%d_y", i]];
    }
    return self;
}
@end

@interface CACGPathCodingProxy : NSObject <NSSecureCoding> {
@public
    NSArray *segments;
}
@end

@implementation CACGPathCodingProxy
+ (BOOL) supportsSecureCoding { return YES; }
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: segments forKey: @"LKCGPathSegments"];
}
- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self != nil) {
        NSSet *classes = [NSSet setWithObjects: [NSArray class], [NSMutableArray class], [CACGPathCodingSegment class], nil];
        segments = [[coder decodeObjectOfClasses: classes forKey: @"LKCGPathSegments"] retain];
    }
    return self;
}
- (void) dealloc {
    [segments release];
    [super dealloc];
}
@end

@interface LKCGImageCodingProxy : NSObject <NSSecureCoding> {
@public
    NSData *data;
}
@end

@implementation LKCGImageCodingProxy
+ (BOOL) supportsSecureCoding { return YES; }
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: data forKey: @"data"];
}
- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self != nil)
        data = [[coder decodeObjectOfClass: [NSData class] forKey: @"data"] retain];
    return self;
}
- (void) dealloc {
    [data release];
    [super dealloc];
}
@end

#pragma mark - Writer

static void appendElement(void *info, const CGPathElement *element) {
    NSMutableArray *segments = info;
    CACGPathCodingSegment *segment = [[CACGPathCodingSegment alloc] init];
    segment->type = element->type;
    for (int i = 0; i < pointsOfElement(element->type); i++)
        segment->points[i] = element->points[i];
    [segments addObject: segment];
    [segment release];
}

@implementation CAArchiveWriter

+ (instancetype) writerWithCoder: (NSCoder *) coder {
    CAArchiveRequireKeyedCoder(coder);
    CAArchiveWriter *writer = [[[self alloc] init] autorelease];
    writer->_coder = coder;
    writer->_keys = [[NSMutableArray alloc] init];
    return writer;
}

- (void) dealloc {
    [_keys release];
    [super dealloc];
}

- (void) encodeBool: (BOOL) value forKey: (NSString *) key {
    [_coder encodeObject: [NSNumber numberWithInt: value ? 1 : 0] forKey: key];
    [_keys addObject: key];
}

- (void) encodeInt: (int) value forKey: (NSString *) key {
    [_coder encodeObject: [NSNumber numberWithInt: value] forKey: key];
    [_keys addObject: key];
}

- (void) encodeFloat: (float) value forKey: (NSString *) key {
    [_coder encodeObject: [NSNumber numberWithFloat: value] forKey: key];
    [_keys addObject: key];
}

- (void) encodeDouble: (double) value forKey: (NSString *) key {
    [_coder encodeObject: [NSNumber numberWithDouble: value] forKey: key];
    [_keys addObject: key];
}

- (void) encodeObject: (id) object forKey: (NSString *) key {
    [_coder encodeObject: object forKey: key];
    [_keys addObject: key];
}

- (void) encodeValueProxy: (LKNSValueCodingProxy *) proxy forKey: (NSString *) key {
    [self encodeObject: proxy forKey: key];
    [proxy release];
}

- (void) encodePoint: (CGPoint) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [[LKNSValueCodingProxy alloc] init];
    proxy->kind = CAValueKindPoint;
    proxy->values[0] = value.x;
    proxy->values[1] = value.y;
    [self encodeValueProxy: proxy forKey: key];
}

- (void) encodeSize: (CGSize) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [[LKNSValueCodingProxy alloc] init];
    proxy->kind = CAValueKindSize;
    proxy->values[0] = value.width;
    proxy->values[1] = value.height;
    [self encodeValueProxy: proxy forKey: key];
}

- (void) encodeRect: (CGRect) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [[LKNSValueCodingProxy alloc] init];
    proxy->kind = CAValueKindRect;
    proxy->values[0] = value.origin.x;
    proxy->values[1] = value.origin.y;
    proxy->values[2] = value.size.width;
    proxy->values[3] = value.size.height;
    [self encodeValueProxy: proxy forKey: key];
}

- (void) encodeTransform: (CATransform3D) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [[LKNSValueCodingProxy alloc] init];
    proxy->kind = CAValueKindTransform;
    const CGFloat *m = &value.m11;
    for (int i = 0; i < 16; i++)
        proxy->values[i] = m[i];
    [self encodeValueProxy: proxy forKey: key];
}

- (void) encodeColor: (CGColorRef) value forKey: (NSString *) key {
    if (value == NULL)
        return;
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef matched = srgb ? CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, value, NULL) : NULL;
    CGColorSpaceRelease(srgb);
    if (matched == NULL || CGColorGetNumberOfComponents(matched) != 4) {
        CGColorRelease(matched);
        return;
    }
    const CGFloat *c = CGColorGetComponents(matched);
    LKCGColorCodingProxy *proxy = [[LKCGColorCodingProxy alloc] init];
    proxy->r = c[0];
    proxy->g = c[1];
    proxy->b = c[2];
    proxy->a = c[3];
    CGColorRelease(matched);
    [self encodeObject: proxy forKey: key];
    [proxy release];
}

- (void) encodePath: (CGPathRef) value forKey: (NSString *) key {
    if (value == NULL)
        return;
    NSMutableArray *segments = [[NSMutableArray alloc] init];
    CGPathApply(value, segments, appendElement);
    CACGPathCodingProxy *proxy = [[CACGPathCodingProxy alloc] init];
    proxy->segments = segments;
    [self encodeObject: proxy forKey: key];
    [proxy release];
}

- (void) encodeContents: (id) value forKey: (NSString *) key {
    if (value == nil)
        return;
    // CGImageRef is an O2Image here; contents of any other kind are archived as objects.
    if (![value isKindOfClass: [O2Image class]]) {
        [self encodeObject: value forKey: key];
        return;
    }
    NSMutableData *png = [NSMutableData data];
    CGImageDestinationRef destination =
            CGImageDestinationCreateWithData((CFMutableDataRef) png, CFSTR("public.png"), 1, NULL);
    if (destination == NULL)
        return;
    CGImageDestinationAddImage(destination, (CGImageRef) value, NULL);
    BOOL done = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    if (!done)
        return;
    LKCGImageCodingProxy *proxy = [[LKCGImageCodingProxy alloc] init];
    proxy->data = [png retain];
    [self encodeObject: proxy forKey: key];
    [proxy release];
}

- (void) encodeArray: (NSArray *) value forKey: (NSString *) key {
    if (value == nil)
        return;
    LKNSArrayCodingProxy *proxy = [[LKNSArrayCodingProxy alloc] init];
    proxy->array = [[NSMutableArray alloc] initWithArray: value];
    [self encodeObject: proxy forKey: key];
    [proxy release];
}

- (void) finish {
    [_keys sortUsingSelector: @selector(compare:)];
    [_coder encodeObject: [[_keys copy] autorelease] forKey: kContentsKey];
}

@end

#pragma mark - Reader

@implementation CAArchiveReader

+ (instancetype) readerWithCoder: (NSCoder *) coder {
    CAArchiveRequireKeyedCoder(coder);
    CAArchiveReader *reader = [[[self alloc] init] autorelease];
    reader->_coder = coder;
    return reader;
}

- (BOOL) containsKey: (NSString *) key {
    return [_coder containsValueForKey: key];
}

// Scalar properties are archived as NSNumber objects, as macOS does, not as
// the coder's inline scalar values; the plain decode methods do not follow an
// object reference.
- (NSNumber *) decodeNumberForKey: (NSString *) key {
    return [_coder decodeObjectOfClass: [NSNumber class] forKey: key];
}

- (BOOL) decodeBool: (BOOL *) value forKey: (NSString *) key {
    if (![self containsKey: key])
        return NO;
    NSNumber *number = [self decodeNumberForKey: key];
    if (number == nil)
        return NO;
    *value = [number boolValue];
    return YES;
}

- (BOOL) decodeInt: (int *) value forKey: (NSString *) key {
    if (![self containsKey: key])
        return NO;
    NSNumber *number = [self decodeNumberForKey: key];
    if (number == nil)
        return NO;
    *value = [number intValue];
    return YES;
}

- (BOOL) decodeFloat: (float *) value forKey: (NSString *) key {
    if (![self containsKey: key])
        return NO;
    NSNumber *number = [self decodeNumberForKey: key];
    if (number == nil)
        return NO;
    *value = [number floatValue];
    return YES;
}

- (BOOL) decodeDouble: (double *) value forKey: (NSString *) key {
    if (![self containsKey: key])
        return NO;
    NSNumber *number = [self decodeNumberForKey: key];
    if (number == nil)
        return NO;
    *value = [number doubleValue];
    return YES;
}

- (LKNSValueCodingProxy *) valueProxyOfKind: (int) kind forKey: (NSString *) key {
    if (![self containsKey: key])
        return nil;
    LKNSValueCodingProxy *proxy = [_coder decodeObjectOfClass: [LKNSValueCodingProxy class] forKey: key];
    if (proxy == nil || proxy->kind != kind)
        return nil;
    return proxy;
}

- (BOOL) decodePoint: (CGPoint *) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [self valueProxyOfKind: CAValueKindPoint forKey: key];
    if (proxy == nil)
        return NO;
    *value = CGPointMake(proxy->values[0], proxy->values[1]);
    return YES;
}

- (BOOL) decodeSize: (CGSize *) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [self valueProxyOfKind: CAValueKindSize forKey: key];
    if (proxy == nil)
        return NO;
    *value = CGSizeMake(proxy->values[0], proxy->values[1]);
    return YES;
}

- (BOOL) decodeRect: (CGRect *) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [self valueProxyOfKind: CAValueKindRect forKey: key];
    if (proxy == nil)
        return NO;
    *value = CGRectMake(proxy->values[0], proxy->values[1], proxy->values[2], proxy->values[3]);
    return YES;
}

- (BOOL) decodeTransform: (CATransform3D *) value forKey: (NSString *) key {
    LKNSValueCodingProxy *proxy = [self valueProxyOfKind: CAValueKindTransform forKey: key];
    if (proxy == nil)
        return NO;
    CGFloat *m = &value->m11;
    for (int i = 0; i < 16; i++)
        m[i] = proxy->values[i];
    return YES;
}

- (CGColorRef) copyColorForKey: (NSString *) key {
    if (![self containsKey: key])
        return NULL;
    LKCGColorCodingProxy *proxy = [_coder decodeObjectOfClass: [LKCGColorCodingProxy class] forKey: key];
    if (proxy == nil)
        return NULL;
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (srgb == NULL)
        return NULL;
    CGFloat components[4] = {proxy->r, proxy->g, proxy->b, proxy->a};
    CGColorRef color = CGColorCreate(srgb, components);
    CGColorSpaceRelease(srgb);
    return color;
}

- (CGPathRef) copyPathForKey: (NSString *) key {
    if (![self containsKey: key])
        return NULL;
    CACGPathCodingProxy *proxy = [_coder decodeObjectOfClass: [CACGPathCodingProxy class] forKey: key];
    if (proxy == nil)
        return NULL;
    CGMutablePathRef path = CGPathCreateMutable();
    for (CACGPathCodingSegment *s in proxy->segments) {
        if (![s isKindOfClass: [CACGPathCodingSegment class]])
            continue;
        switch (s->type) {
        case kCGPathElementMoveToPoint:
            CGPathMoveToPoint(path, NULL, s->points[0].x, s->points[0].y);
            break;
        case kCGPathElementAddLineToPoint:
            CGPathAddLineToPoint(path, NULL, s->points[0].x, s->points[0].y);
            break;
        case kCGPathElementAddQuadCurveToPoint:
            CGPathAddQuadCurveToPoint(path, NULL, s->points[0].x, s->points[0].y, s->points[1].x, s->points[1].y);
            break;
        case kCGPathElementAddCurveToPoint:
            CGPathAddCurveToPoint(path, NULL, s->points[0].x, s->points[0].y, s->points[1].x, s->points[1].y,
                                  s->points[2].x, s->points[2].y);
            break;
        case kCGPathElementCloseSubpath:
            CGPathCloseSubpath(path);
            break;
        }
    }
    return path;
}

- (NSString *) decodeStringForKey: (NSString *) key {
    return [_coder decodeObjectOfClass: [NSString class] forKey: key];
}

- (id) copyContentsForKey: (NSString *) key {
    if (![self containsKey: key])
        return nil;
    NSSet *classes = [NSSet setWithObjects: [LKCGImageCodingProxy class], [NSString class], [NSNumber class],
                                            [NSData class], nil];
    id object = [_coder decodeObjectOfClasses: classes forKey: key];
    if (![object isKindOfClass: [LKCGImageCodingProxy class]])
        return [object retain];
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef) ((LKCGImageCodingProxy *) object)->data, NULL);
    if (source == NULL)
        return nil;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    return (id) image;
}

- (NSArray *) decodeArrayForKey: (NSString *) key {
    if (![self containsKey: key])
        return nil;
    LKNSArrayCodingProxy *proxy = [_coder decodeObjectOfClass: [LKNSArrayCodingProxy class] forKey: key];
    return proxy != nil ? proxy->array : nil;
}

- (id) decodeObjectOfClasses: (NSSet *) classes forKey: (NSString *) key {
    return [_coder decodeObjectOfClasses: classes forKey: key];
}

@end
