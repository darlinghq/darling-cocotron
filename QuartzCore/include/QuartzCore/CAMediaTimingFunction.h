#import <Foundation/NSObject.h>
#import <QuartzCore/CABase.h>

typedef NSString *CAMediaTimingFunctionName NS_TYPED_ENUM;

CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionLinear;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseIn;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseOut;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseInEaseOut;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionDefault;

@interface CAMediaTimingFunction : NSObject {
    float _c1x;
    float _c1y;
    float _c2x;
    float _c2y;
}

- (id) initWithControlPoints: (float)
                         c1x: (float) c1y
                            :(float) c2x
                            :(float) c2y;

+ functionWithControlPoints: (float)
                        c1x: (float) c1y
                           :(float) c2x
                           :(float) c2y;

+ (instancetype) functionWithName: (CAMediaTimingFunctionName) name;

- (void) getControlPointAtIndex: (size_t) index values: (float[2]) ptr;

@end
