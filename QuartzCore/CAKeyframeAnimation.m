#import <QuartzCore/CAAnimation.h>

// Implemented by CAPropertyAnimation.m, not part of the public header.
@interface CAPropertyAnimation (CAKeyframeAnimationInit)
- initWithKeyPath: (NSString *) keyPath;
@end

// A property animated through a series of values. The properties are the
// documented ones: https://developer.apple.com/documentation/quartzcore/cakeyframeanimation
#define EXTRA(field) NS_EXTRA(CAKeyframeAnimation, self)->field

// CAPropertyAnimation's initializer does not go through -init, so both set
// the documented default mode.
static void setDefaultCalculationMode(CAKeyframeAnimation *self) {
    [self setCalculationMode: kCAAnimationLinear];
}

@implementation CAKeyframeAnimation

- init {
    self = [super init];
    if (self != nil)
        setDefaultCalculationMode(self);
    return self;
}

- initWithKeyPath: (NSString *) keyPath {
    self = [super initWithKeyPath: keyPath];
    if (self != nil)
        setDefaultCalculationMode(self);
    return self;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(CAKeyframeAnimation, self)) {
        [EXTRA(_values) release];
        CGPathRelease(EXTRA(_path));
        [EXTRA(_keyTimes) release];
        [EXTRA(_timingFunctions) release];
        [EXTRA(_calculationMode) release];
        [EXTRA(_tensionValues) release];
        [EXTRA(_continuityValues) release];
        [EXTRA(_biasValues) release];
        [EXTRA(_rotationMode) release];
    }
    [super dealloc];
}

NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, values, _values, NSArray *, values, setValues:)
NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, keyTimes, _keyTimes, NSArray *, keyTimes, setKeyTimes:)
NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, timingFunctions, _timingFunctions, NSArray *, timingFunctions, setTimingFunctions:)
NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, calculationMode, _calculationMode, NSString *, calculationMode, setCalculationMode:)
NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, tensionValues, _tensionValues, NSArray *, tensionValues, setTensionValues:)
NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, continuityValues, _continuityValues, NSArray *, continuityValues, setContinuityValues:)
NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, biasValues, _biasValues, NSArray *, biasValues, setBiasValues:)
NS_EXTRA_SYNTHESIZE_COPY(CAKeyframeAnimation, rotationMode, _rotationMode, NSString *, rotationMode, setRotationMode:)

// The path is kept as a copy, like CAShapeLayer's.
- (CGPathRef) path {
    @synchronized(self) {
        return EXTRA(_path);
    }
}

- (void) setPath: (CGPathRef) path {
    CGPathRef copy = path ? CGPathCreateCopy(path) : NULL;
    CGPathRef old;

    @synchronized(self) {
        old = EXTRA(_path);
        EXTRA(_path) = copy;
    }
    CGPathRelease(old);
}

#undef EXTRA

@end
