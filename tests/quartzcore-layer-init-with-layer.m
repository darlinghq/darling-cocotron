// Copyright (C) 2026 Lubos Dolezel
//
// -[CALayer initWithLayer:] makes a layer in the default state, does not run a
// subclass's -init and accepts any argument; CAShapeLayer and CATextLayer
// copies have their own defaults. Passes on macOS (the
// behaviour is a QUIRK in CALayer.m; see the observation in
// vd-upstream mac-probes/v314-initwithlayer.m).
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static int initRuns;
@interface TaggedLayer : CALayer {
    int _tag;
}
@property int tag;
@end
@implementation TaggedLayer
@synthesize tag = _tag;
- (instancetype)init { initRuns++; return [super init]; }
- (instancetype)initWithLayer:(id)layer {
    self = [super initWithLayer: layer];
    if ([layer isKindOfClass: [TaggedLayer class]])
        self.tag = ((TaggedLayer *) layer).tag;
    return self;
}
@end

int main(void) {
    @autoreleasepool {
        TaggedLayer *l = [TaggedLayer layer];
        l.tag = 7;
        l.bounds = CGRectMake(1, 2, 30, 40);
        l.position = CGPointMake(5, 6);
        l.opacity = 0.25;
        l.cornerRadius = 3;
        l.name = @"name";
        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        l.backgroundColor = red;
        CGColorRelease(red);
        [l addSublayer: [CALayer layer]];

        int runs = initRuns;
        TaggedLayer *c = [[TaggedLayer alloc] initWithLayer: l];
        CHECK(initRuns == runs, "subclass -init ran on the copy");
        CHECK(c.tag == 7, "subclass state copied by the subclass");
        CHECK(CGRectEqualToRect(c.bounds, CGRectZero) && CGPointEqualToPoint(c.position, CGPointZero), "geometry is default");
        CHECK(c.opacity == 1 && c.cornerRadius == 0 && c.backgroundColor == NULL && c.name == nil, "appearance is default");
        CHECK(c.sublayers.count == 0 && c.superlayer == nil, "no tree position");
        CHECK(l.opacity == 0.25 && l.sublayers.count == 1, "original untouched");

        CALayer *any = [[CALayer alloc] initWithLayer: @"not a layer"];
        CHECK(any != nil && any.opacity == 1, "any object is accepted");
        CALayer *none = [[CALayer alloc] initWithLayer: nil];
        CHECK(none != nil, "nil is accepted");

        CAShapeLayer *s = [CAShapeLayer layer];
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathAddRect(p, NULL, CGRectMake(0, 0, 5, 5));
        s.path = p;
        CGPathRelease(p);
        s.fillColor = NULL;
        s.lineWidth = 4;
        s.fillRule = kCAFillRuleEvenOdd;
        CAShapeLayer *sc = [[CAShapeLayer alloc] initWithLayer: s];
        CHECK(sc.path == NULL && sc.fillColor != NULL && sc.lineWidth == 1 && [sc.fillRule isEqualToString: kCAFillRuleNonZero],
              "shape layer copy has the shape defaults");

        CATextLayer *t = [CATextLayer layer];
        t.string = @"text";
        t.fontSize = 11;
        t.wrapped = YES;
        CATextLayer *tc = [[CATextLayer alloc] initWithLayer: t];
        CHECK(tc.string == nil && tc.fontSize == 36 && !tc.wrapped, "text layer copy has the text defaults");

        if (failures == 0) puts("PASS: CALayer initWithLayer:");
        return failures != 0;
    }
}
