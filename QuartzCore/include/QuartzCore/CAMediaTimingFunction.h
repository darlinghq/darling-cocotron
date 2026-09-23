#import <Foundation/NSObject.h>
#import <QuartzCore/CABase.h>

typedef NSString *CAMediaTimingFunctionName NS_TYPED_ENUM;

CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionLinear;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseIn;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseOut;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseInEaseOut;
CA_EXPORT CAMediaTimingFunctionName const kCAMediaTimingFunctionDefault;

@interface CAMediaTimingFunction : NSObject {
    CGFloat _c1x;
    CGFloat _c1y;
    CGFloat _c2x;
    CGFloat _c2y;
}

- (id) initWithControlPoints: (CGFloat)
                         c1x: (CGFloat) c1y
                            :(CGFloat) c2x
                            :(CGFloat) c2y;

+ functionWithControlPoints: (CGFloat)
                        c1x: (CGFloat) c1y
                           :(CGFloat) c2x
                           :(CGFloat) c2y;

+ (instancetype) functionWithName: (CAMediaTimingFunctionName) name;

- (void) getControlPointAtIndex: (size_t) index values: (CGFloat[2]) ptr;

@end
