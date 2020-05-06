#import <Foundation/NSObject.h>
#import <QuartzCore/CABase.h>

CA_EXPORT NSString *const kCAMediaTimingFunctionLinear;
CA_EXPORT NSString *const kCAMediaTimingFunctionEaseIn;
CA_EXPORT NSString *const kCAMediaTimingFunctionEaseOut;
CA_EXPORT NSString *const kCAMediaTimingFunctionEaseInEaseOut;
CA_EXPORT NSString *const kCAMediaTimingFunctionDefault;

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

+ functionWithName: (NSString *) name;

- (void) getControlPointAtIndex: (size_t) index values: (CGFloat[2]) ptr;

@end
