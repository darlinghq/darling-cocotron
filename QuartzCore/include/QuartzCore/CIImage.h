#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/NSObject.h>

@class CIFilter;

@interface CIImage : NSObject {
    CGImageRef _cgImage;
    CIFilter *_filter;
}

+ (CIImage *) emptyImage;

- initWithCGImage: (CGImageRef) cgImage;
- (CGRect) extent;

@end
