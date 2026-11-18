// Copyright (C) 2026 Lubos Dolezel
//
// On the legacy (32-bit) Objective-C ABI an application's subclass of a
// QuartzCore class is compiled against Apple's instance layout: its instance
// variables sit at offsets fixed at compile time, directly after the
// QuartzCore class's instance size. So each public QuartzCore class must report
// that size, however much state the implementation keeps, and a subclass must
// start right after it. The expected sizes are what Mac OS X 10.14.4 reports
// through the public runtime API (class_getInstanceSize; black-box observation,
// i386). The size checks only run on the legacy ABI; the behaviour checks of
// the layers and animations (state kept for them, state of subclasses next to
// it) run everywhere.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...)                                                       \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL: " __VA_ARGS__);                                      \
            printf("\n");                                                      \
            failures++;                                                        \
        }                                                                      \
    } while (0)

#if !__LP64__
static const struct {
    const char *cls;
    size_t size;
} sizes[] = {
    {"CALayer", 48}, {"CAShapeLayer", 48}, {"CAGradientLayer", 48},
    {"CAReplicatorLayer", 48}, {"CAScrollLayer", 48}, {"CATiledLayer", 48},
    {"CATransformLayer", 48}, {"CAEmitterLayer", 48}, {"CATextLayer", 52},
    {"CAOpenGLLayer", 52}, {"CAMetalLayer", 52}, {"NSOpenGLLayer", 80},
    {"CAAnimation", 12}, {"CAPropertyAnimation", 12}, {"CABasicAnimation", 12},
    {"CAKeyframeAnimation", 12}, {"CASpringAnimation", 12},
    {"CATransition", 12}, {"CAAnimationGroup", 12},
    {"CAMediaTimingFunction", 8}, {"CADisplayLink", 8}, {"CARenderer", 8},
    {"CAConstraint", 20}, {"CAEmitterCell", 20}, {"CAValueFunction", 12},
    {"CAFilter", 24},
};

static void checkSizes(void) {
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        Class c = objc_getClass(sizes[i].cls);
        CHECK(c != Nil, "%s is missing", sizes[i].cls);
        if (c == Nil)
            continue;
        CHECK(class_getInstanceSize(c) == sizes[i].size,
              "%s: instance size %zu, expected %zu", sizes[i].cls,
              class_getInstanceSize(c), sizes[i].size);
    }
}
#endif

@interface SubShapeLayer : CAShapeLayer {
    int _subValue;
    id _subObject;
}
@property int subValue;
@property(retain) id subObject;
@end
@implementation SubShapeLayer
@synthesize subValue = _subValue;
@synthesize subObject = _subObject;
- (void) dealloc {
    [_subObject release];
    [super dealloc];
}
@end

@interface SubLayer : CALayer {
    int _marker[4];
}
@end
@implementation SubLayer
- (void) mark {
    _marker[0] = 11;
    _marker[3] = 22;
}
- (int) sum {
    return _marker[0] + _marker[3];
}
@end

@interface SubAnimation : CABasicAnimation {
    int _flag;
}
@end
@implementation SubAnimation
- (void) setFlag: (int) value {
    _flag = value;
}
- (int) flag {
    return _flag;
}
@end

static void checkSubclasses(void) {
#if !__LP64__
    Ivar v = class_getInstanceVariable([SubShapeLayer class], "_subValue");
    CHECK(ivar_getOffset(v) == 48, "SubShapeLayer's first ivar at %td, expected 48",
          ivar_getOffset(v));
    v = class_getInstanceVariable([SubLayer class], "_marker");
    CHECK(ivar_getOffset(v) == 48, "SubLayer's first ivar at %td, expected 48",
          ivar_getOffset(v));
    v = class_getInstanceVariable([SubAnimation class], "_flag");
    CHECK(ivar_getOffset(v) == 12, "SubAnimation's first ivar at %td, expected 12",
          ivar_getOffset(v));
#endif

    SubShapeLayer *shape = [SubShapeLayer layer];
    shape.subValue = 7;
    shape.lineWidth = 3;
    shape.fillRule = kCAFillRuleEvenOdd;
    shape.name = @"shape";
    shape.opacity = 0.5;
    shape.subObject = @"object";
    CHECK(shape.subValue == 7, "subclass ivar lost");
    CHECK(shape.lineWidth == 3, "CAShapeLayer state lost");
    CHECK([shape.fillRule isEqualToString: kCAFillRuleEvenOdd], "fill rule lost");
    CHECK([shape.name isEqualToString: @"shape"], "CALayer name lost");
    CHECK(shape.opacity == 0.5f, "CALayer opacity lost");
    CHECK([shape.subObject isEqual: @"object"], "subclass object lost");

    SubLayer *sub = [SubLayer layer];
    sub.position = CGPointMake(5, 6);
    [sub mark];
    CHECK([sub sum] == 33, "SubLayer ivars overlapped the layer's state");
    CHECK(sub.position.x == 5 && sub.position.y == 6, "position changed by subclass ivars");

    CALayer *parent = [CALayer layer];
    [parent addSublayer: sub];
    CHECK(sub.superlayer == parent, "superlayer lost");
    CHECK([parent.sublayers count] == 1, "sublayers lost");

    SubAnimation *anim = [SubAnimation animationWithKeyPath: @"opacity"];
    anim.fromValue = @0;
    anim.toValue = @1;
    anim.duration = 2;
    [anim setFlag: 5];
    CHECK([anim flag] == 5, "SubAnimation ivar lost");
    CHECK(anim.duration == 2, "duration lost");
    CHECK([anim.keyPath isEqualToString: @"opacity"], "key path lost");
    CHECK([anim.toValue isEqual: @1], "toValue lost");

    CATextLayer *text = [CATextLayer layer];
    text.string = @"text";
    text.fontSize = 20;
    CHECK([text.string isEqual: @"text"] && text.fontSize == 20, "CATextLayer state lost");

    CAMediaTimingFunction *fn = [CAMediaTimingFunction functionWithControlPoints: 0.1 : 0.2 : 0.3 : 0.4];
    float pt[2];
    [fn getControlPointAtIndex: 1 values: pt];
    CHECK(pt[0] == 0.1f && pt[1] == 0.2f, "timing function control point lost");

    CAEmitterLayer *emitter = [CAEmitterLayer layer];
    emitter.birthRate = 3;
    emitter.emitterShape = kCAEmitterLayerLine;
    CHECK(emitter.birthRate == 3, "emitter birth rate lost");
    CHECK([emitter.emitterShape isEqualToString: kCAEmitterLayerLine], "emitter shape lost");
}

int main(void) {
    @autoreleasepool {
#if !__LP64__
        checkSizes();
#endif
        checkSubclasses();
    }
    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("OK\n");
    return 0;
}
